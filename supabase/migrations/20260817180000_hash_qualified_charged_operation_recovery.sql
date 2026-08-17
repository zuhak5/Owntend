-- Migration: 20260817180000_hash_qualified_charged_operation_recovery.sql
-- Description: Require the durable client request hash for charged-operation reconciliation.

BEGIN;

ALTER TABLE public.creation_point_operations
  ADD COLUMN IF NOT EXISTS client_request_hash TEXT;

ALTER TABLE public.creation_point_operations
  DROP CONSTRAINT IF EXISTS creation_point_operations_client_request_hash_check;
ALTER TABLE public.creation_point_operations
  ADD CONSTRAINT creation_point_operations_client_request_hash_check
  CHECK (
    client_request_hash IS NULL
    OR client_request_hash ~ '^[0-9a-f]{64}$'
  );

-- Keep the original status implementation as a private result renderer. Its
-- request_hash column remains the server-computed digest of the complete JSONB
-- request and continues to protect create-RPC idempotency.
ALTER FUNCTION public.get_charged_operation_status(UUID, TEXT)
  SET SCHEMA owntend_monetization_private;

REVOKE ALL ON FUNCTION owntend_monetization_private.get_charged_operation_status(UUID, TEXT)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.get_charged_operation_status(UUID, TEXT)
TO service_role;

CREATE OR REPLACE FUNCTION public.create_task_with_point_debit(p_operation JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id UUID := auth.uid();
  operation_uuid UUID;
  client_hash TEXT;
  result JSONB;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;

  BEGIN
    operation_uuid := (p_operation->>'operation_id')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION_ID';
  END;

  client_hash := LOWER(NULLIF(BTRIM(p_operation->>'request_hash'), ''));
  IF client_hash IS NULL OR client_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_REQUEST_HASH';
  END IF;

  result := owntend_monetization_private.create_task_with_point_debit_impl(p_operation);

  UPDATE public.creation_point_operations
  SET client_request_hash = client_hash
  WHERE operation_id = operation_uuid
    AND user_id = caller_id
    AND (client_request_hash IS NULL OR client_request_hash = client_hash);

  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
  END IF;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.create_task_with_point_debit(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_task_with_point_debit(JSONB)
TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_asset_with_point_debit(p_operation JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id UUID := auth.uid();
  operation_uuid UUID;
  client_hash TEXT;
  result JSONB;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;

  BEGIN
    operation_uuid := (p_operation->>'operation_id')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION_ID';
  END;

  client_hash := LOWER(NULLIF(BTRIM(p_operation->>'request_hash'), ''));
  IF client_hash IS NULL OR client_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_REQUEST_HASH';
  END IF;

  result := owntend_monetization_private.create_asset_with_point_debit_impl(p_operation);

  UPDATE public.creation_point_operations
  SET client_request_hash = client_hash
  WHERE operation_id = operation_uuid
    AND user_id = caller_id
    AND (client_request_hash IS NULL OR client_request_hash = client_hash);

  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
  END IF;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.create_asset_with_point_debit(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_asset_with_point_debit(JSONB)
TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_charged_operation_status(
  p_operation_id UUID,
  p_request_hash TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id UUID := auth.uid();
  normalized_hash TEXT := LOWER(NULLIF(BTRIM(p_request_hash), ''));
  stored_hash TEXT;
  result JSONB;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;

  IF p_operation_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION_ID';
  END IF;

  IF normalized_hash IS NULL OR normalized_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_REQUEST_HASH';
  END IF;

  SELECT client_request_hash
  INTO stored_hash
  FROM public.creation_point_operations
  WHERE operation_id = p_operation_id
    AND user_id = caller_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'status', 'not_found',
      'operation_id', p_operation_id,
      'capability_version', '1.2.0'
    );
  END IF;

  IF stored_hash IS NULL OR stored_hash <> normalized_hash THEN
    RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
  END IF;

  result := owntend_monetization_private.get_charged_operation_status(
    p_operation_id,
    NULL
  );

  RETURN jsonb_set(
    result,
    '{capability_version}',
    to_jsonb('1.2.0'::TEXT),
    true
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_charged_operation_status(UUID, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_charged_operation_status(UUID, TEXT)
TO authenticated, service_role;

COMMIT;
