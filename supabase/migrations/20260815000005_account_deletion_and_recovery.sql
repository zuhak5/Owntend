-- Migration: 20260815000005_account_deletion_and_recovery.sql
-- Description: Server-Authoritative Account Deletion Operation Lifecycle, Multi-Stage Recovery, and Acknowledgement Protocol

BEGIN;

CREATE SCHEMA IF NOT EXISTS owntend_private;
REVOKE ALL ON SCHEMA owntend_private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA owntend_private TO service_role;

-- 1. Account Deletion Operations Table

CREATE TABLE IF NOT EXISTS owntend_private.account_deletion_operations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_hash TEXT NOT NULL UNIQUE CONSTRAINT account_deletion_operations_request_hash_check CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  subject_binding TEXT NOT NULL CONSTRAINT account_deletion_operations_subject_binding_check CHECK (subject_binding ~ '^[0-9a-f]{64}$'),
  active_user_id UUID,
  stage TEXT NOT NULL DEFAULT 'prepared' CONSTRAINT account_deletion_operations_stage_check CHECK (
    stage IN (
      'prepared',
      'storage_cleanup',
      'storage_complete',
      'auth_delete_started',
      'completed',
      'acknowledged'
    )
  ),
  last_error_code TEXT CONSTRAINT account_deletion_operations_error_code_check CHECK (
    last_error_code IS NULL
    OR (
      CHAR_LENGTH(last_error_code) BETWEEN 1 AND 120
      AND last_error_code ~ '^[a-z0-9_]+$'
    )
  ),
  remote_boundary_at TIMESTAMPTZ,
  acknowledged_at TIMESTAMPTZ,
  capability_version TEXT CONSTRAINT account_deletion_operations_capability_version_check CHECK (
    capability_version IS NULL
    OR (
      CHAR_LENGTH(capability_version) BETWEEN 1 AND 120
      AND capability_version ~ '^[A-Za-z0-9._-]+$'
    )
  ),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  completed_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (
    clock_timestamp() + INTERVAL '7 days'
  ),
  CONSTRAINT account_deletion_operations_completion_check CHECK (
    (
      stage IN ('completed', 'acknowledged')
      AND active_user_id IS NULL
      AND completed_at IS NOT NULL
      AND last_error_code IS NULL
    )
    OR (
      stage NOT IN ('completed', 'acknowledged')
      AND active_user_id IS NOT NULL
      AND completed_at IS NULL
    )
  )
);

ALTER TABLE owntend_private.account_deletion_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON owntend_private.account_deletion_operations FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON owntend_private.account_deletion_operations TO service_role;

DROP POLICY IF EXISTS account_deletion_operations_service_role_all ON owntend_private.account_deletion_operations;
CREATE POLICY account_deletion_operations_service_role_all
  ON owntend_private.account_deletion_operations
  FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

-- 2. Prune Function

CREATE OR REPLACE FUNCTION public.prune_owntend_account_deletion_operations()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM owntend_private.account_deletion_operations
  WHERE expires_at <= clock_timestamp()
    AND stage <> 'completed';
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

REVOKE ALL ON FUNCTION public.prune_owntend_account_deletion_operations() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prune_owntend_account_deletion_operations() TO service_role;

-- 3. Begin Operation Function

CREATE OR REPLACE FUNCTION public.begin_owntend_account_deletion_operation(
  p_request_hash TEXT,
  p_subject_binding TEXT,
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  operation_row owntend_private.account_deletion_operations%ROWTYPE;
BEGIN
  IF p_request_hash IS NULL
    OR p_request_hash !~ '^[0-9a-f]{64}$'
    OR p_subject_binding IS NULL
    OR p_subject_binding !~ '^[0-9a-f]{64}$'
    OR p_user_id IS NULL
  THEN
    RAISE EXCEPTION USING errcode = '22023',
      message = 'INVALID_DELETION_OPERATION';
  END IF;

  PERFORM public.prune_owntend_account_deletion_operations();

  INSERT INTO owntend_private.account_deletion_operations (
    request_hash,
    subject_binding,
    active_user_id
  ) VALUES (
    p_request_hash,
    p_subject_binding,
    p_user_id
  )
  ON CONFLICT (request_hash) DO NOTHING;

  SELECT * INTO operation_row
  FROM owntend_private.account_deletion_operations
  WHERE request_hash = p_request_hash
  FOR UPDATE;

  IF NOT FOUND
    OR operation_row.subject_binding IS DISTINCT FROM p_subject_binding
    OR (
      operation_row.active_user_id IS NOT NULL
      AND operation_row.active_user_id IS DISTINCT FROM p_user_id
    )
  THEN
    RAISE EXCEPTION USING errcode = '42501',
      message = 'DELETION_OPERATION_BINDING_MISMATCH';
  END IF;

  RETURN jsonb_build_object(
    'operation_id', operation_row.id,
    'stage', operation_row.stage,
    'completed', operation_row.stage IN ('completed', 'acknowledged')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.begin_owntend_account_deletion_operation(TEXT, TEXT, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.begin_owntend_account_deletion_operation(TEXT, TEXT, UUID) TO service_role;

-- 4. Advance Operation Function

CREATE OR REPLACE FUNCTION public.advance_owntend_account_deletion_operation(
  p_operation_id UUID,
  p_user_id UUID,
  p_stage TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  operation_row owntend_private.account_deletion_operations%ROWTYPE;
  current_rank INTEGER;
  requested_rank INTEGER;
BEGIN
  SELECT * INTO operation_row
  FROM owntend_private.account_deletion_operations
  WHERE id = p_operation_id
  FOR UPDATE;

  IF NOT FOUND
    OR operation_row.active_user_id IS DISTINCT FROM p_user_id
  THEN
    RAISE EXCEPTION USING errcode = '42501',
      message = 'DELETION_OPERATION_BINDING_MISMATCH';
  END IF;

  current_rank := CASE operation_row.stage
    WHEN 'prepared' THEN 0
    WHEN 'storage_cleanup' THEN 1
    WHEN 'storage_complete' THEN 2
    WHEN 'auth_delete_started' THEN 3
    WHEN 'completed' THEN 4
    WHEN 'acknowledged' THEN 5
    ELSE NULL
  END;
  requested_rank := CASE p_stage
    WHEN 'prepared' THEN 0
    WHEN 'storage_cleanup' THEN 1
    WHEN 'storage_complete' THEN 2
    WHEN 'auth_delete_started' THEN 3
    ELSE NULL
  END;

  IF requested_rank IS NULL THEN
    RAISE EXCEPTION USING errcode = '22023',
      message = 'INVALID_DELETION_OPERATION_STAGE';
  END IF;

  IF requested_rank > current_rank THEN
    UPDATE owntend_private.account_deletion_operations
    SET
      stage = p_stage,
      last_error_code = NULL,
      updated_at = clock_timestamp(),
      remote_boundary_at = CASE
        WHEN p_stage = 'auth_delete_started'
          AND remote_boundary_at IS NULL
          THEN clock_timestamp()
        ELSE remote_boundary_at
      END
    WHERE id = p_operation_id
    RETURNING * INTO operation_row;
  END IF;

  RETURN operation_row.stage;
END;
$$;

REVOKE ALL ON FUNCTION public.advance_owntend_account_deletion_operation(UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.advance_owntend_account_deletion_operation(UUID, UUID, TEXT) TO service_role;

-- 5. Record Operation Error Function

CREATE OR REPLACE FUNCTION public.record_owntend_account_deletion_operation_error(
  p_operation_id UUID,
  p_user_id UUID,
  p_error_code TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF p_error_code IS NULL
    OR CHAR_LENGTH(p_error_code) NOT BETWEEN 1 AND 120
    OR p_error_code !~ '^[a-z0-9_]+$'
  THEN
    RAISE EXCEPTION USING errcode = '22023',
      message = 'INVALID_DELETION_OPERATION_ERROR';
  END IF;

  UPDATE owntend_private.account_deletion_operations
  SET
    last_error_code = p_error_code,
    updated_at = clock_timestamp()
  WHERE id = p_operation_id
    AND active_user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501',
      message = 'DELETION_OPERATION_BINDING_MISMATCH';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.record_owntend_account_deletion_operation_error(UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_owntend_account_deletion_operation_error(UUID, UUID, TEXT) TO service_role;

-- 6. Complete Operation Function

CREATE OR REPLACE FUNCTION public.complete_owntend_account_deletion_operation(
  p_operation_id UUID,
  p_user_id UUID,
  p_subject_binding TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  operation_row owntend_private.account_deletion_operations%ROWTYPE;
BEGIN
  SELECT * INTO operation_row
  FROM owntend_private.account_deletion_operations
  WHERE id = p_operation_id
    AND subject_binding = p_subject_binding
  FOR UPDATE;

  IF NOT FOUND
    OR (
      operation_row.active_user_id IS NOT NULL
      AND operation_row.active_user_id IS DISTINCT FROM p_user_id
    )
  THEN
    RAISE EXCEPTION USING errcode = '42501',
      message = 'DELETION_OPERATION_BINDING_MISMATCH';
  END IF;

  IF operation_row.stage NOT IN ('completed', 'acknowledged') THEN
    IF operation_row.stage <> 'auth_delete_started' THEN
      RAISE EXCEPTION USING errcode = '55000',
        message = 'DELETION_OPERATION_NOT_READY';
    END IF;
    UPDATE owntend_private.account_deletion_operations
    SET
      active_user_id = NULL,
      stage = 'completed',
      last_error_code = NULL,
      completed_at = clock_timestamp(),
      updated_at = clock_timestamp(),
      expires_at = clock_timestamp() + INTERVAL '90 days',
      remote_boundary_at = COALESCE(remote_boundary_at, clock_timestamp())
    WHERE id = p_operation_id
    RETURNING * INTO operation_row;
  END IF;

  RETURN jsonb_build_object(
    'operation_id', operation_row.id,
    'stage', operation_row.stage,
    'completed', true,
    'expires_at', operation_row.expires_at,
    'remote_boundary_at', operation_row.remote_boundary_at,
    'acknowledged', operation_row.stage = 'acknowledged'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.complete_owntend_account_deletion_operation(UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_owntend_account_deletion_operation(UUID, UUID, TEXT) TO service_role;

-- 7. Lookup Operation Function

CREATE OR REPLACE FUNCTION public.lookup_owntend_account_deletion_operation(
  p_request_hash TEXT,
  p_subject_binding TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  operation_row owntend_private.account_deletion_operations%ROWTYPE;
BEGIN
  IF p_request_hash IS NULL
    OR p_request_hash !~ '^[0-9a-f]{64}$'
    OR p_subject_binding IS NULL
    OR p_subject_binding !~ '^[0-9a-f]{64}$'
  THEN
    RAISE EXCEPTION USING errcode = '22023',
      message = 'INVALID_DELETION_OPERATION';
  END IF;

  PERFORM public.prune_owntend_account_deletion_operations();

  SELECT * INTO operation_row
  FROM owntend_private.account_deletion_operations
  WHERE request_hash = p_request_hash
    AND subject_binding = p_subject_binding;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'operation_id', operation_row.id,
    'stage', operation_row.stage,
    'active_user_id', operation_row.active_user_id,
    'completed', operation_row.stage IN ('completed', 'acknowledged'),
    'acknowledged', operation_row.stage = 'acknowledged',
    'remote_boundary_at', operation_row.remote_boundary_at,
    'expires_at', operation_row.expires_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.lookup_owntend_account_deletion_operation(TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lookup_owntend_account_deletion_operation(TEXT, TEXT) TO service_role;

-- 8. Acknowledge Operation Function

CREATE OR REPLACE FUNCTION public.acknowledge_owntend_account_deletion_operation(
  p_operation_id UUID,
  p_subject_binding TEXT,
  p_capability_version TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  operation_row owntend_private.account_deletion_operations%ROWTYPE;
BEGIN
  IF p_operation_id IS NULL
    OR p_subject_binding IS NULL
    OR p_subject_binding !~ '^[0-9a-f]{64}$'
    OR p_capability_version IS NULL
    OR CHAR_LENGTH(p_capability_version) NOT BETWEEN 1 AND 120
    OR p_capability_version !~ '^[A-Za-z0-9._-]+$'
  THEN
    RAISE EXCEPTION USING errcode = '22023',
      message = 'INVALID_DELETION_ACKNOWLEDGEMENT';
  END IF;

  SELECT * INTO operation_row
  FROM owntend_private.account_deletion_operations
  WHERE id = p_operation_id
    AND subject_binding = p_subject_binding
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501',
      message = 'DELETION_OPERATION_BINDING_MISMATCH';
  END IF;

  IF operation_row.stage NOT IN ('completed', 'acknowledged') THEN
    RAISE EXCEPTION USING errcode = '55000',
      message = 'DELETION_OPERATION_NOT_READY';
  END IF;

  IF operation_row.stage = 'acknowledged' THEN
    RETURN jsonb_build_object(
      'operation_id', operation_row.id,
      'stage', operation_row.stage,
      'acknowledged', true,
      'acknowledged_at', operation_row.acknowledged_at,
      'capability_version', operation_row.capability_version,
      'remote_boundary_at', operation_row.remote_boundary_at
    );
  END IF;

  UPDATE owntend_private.account_deletion_operations
  SET
    stage = 'acknowledged',
    acknowledged_at = clock_timestamp(),
    capability_version = p_capability_version,
    updated_at = clock_timestamp(),
    expires_at = clock_timestamp() + INTERVAL '7 days'
  WHERE id = p_operation_id
  RETURNING * INTO operation_row;

  RETURN jsonb_build_object(
    'operation_id', operation_row.id,
    'stage', operation_row.stage,
    'acknowledged', true,
    'acknowledged_at', operation_row.acknowledged_at,
    'capability_version', operation_row.capability_version,
    'remote_boundary_at', operation_row.remote_boundary_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.acknowledge_owntend_account_deletion_operation(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.acknowledge_owntend_account_deletion_operation(UUID, TEXT, TEXT) TO service_role;

-- 9. Scheduled Cron Job for Operations Pruning

DO $$
DECLARE
  existing_job_id BIGINT;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    SELECT jobid INTO existing_job_id
    FROM cron.job
    WHERE jobname = 'owntend-account-deletion-operation-prune';
    IF existing_job_id IS NOT NULL THEN
      PERFORM cron.unschedule(existing_job_id);
    END IF;
    PERFORM cron.schedule(
      'owntend-account-deletion-operation-prune',
      '17 * * * *',
      'SELECT public.prune_owntend_account_deletion_operations();'
    );
  END IF;
END;
$$;

COMMIT;
