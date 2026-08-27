-- Close monetization and maintenance-history authority gaps with private,
-- search-path-pinned implementations and minimal public invoker wrappers.

CREATE TABLE owntend_monetization_private.maintenance_plan_entitlements (
  user_id uuid NOT NULL,
  plan_id text NOT NULL,
  paid_cost smallint NOT NULL,
  origin text NOT NULL,
  created_by_operation_id uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT maintenance_plan_entitlements_pkey PRIMARY KEY (user_id, plan_id),
  CONSTRAINT maintenance_plan_entitlements_paid_cost_check CHECK (paid_cost BETWEEN 0 AND 1),
  CONSTRAINT maintenance_plan_entitlements_origin_check CHECK (
    origin IN ('task_creation', 'asset_copy', 'completion_recovery', 'legacy_unverified')
  ),
  CONSTRAINT maintenance_plan_entitlements_user_plan_fkey
    FOREIGN KEY (user_id, plan_id)
    REFERENCES public.maintenance_plans(user_id, id)
    ON DELETE CASCADE
    DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT maintenance_plan_entitlements_user_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT maintenance_plan_entitlements_operation_fkey
    FOREIGN KEY (created_by_operation_id)
    REFERENCES public.creation_point_operations(operation_id)
    ON DELETE SET NULL
    DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX maintenance_plan_entitlements_operation_idx
  ON owntend_monetization_private.maintenance_plan_entitlements(created_by_operation_id)
  WHERE created_by_operation_id IS NOT NULL;

ALTER TABLE owntend_monetization_private.maintenance_plan_entitlements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE owntend_monetization_private.maintenance_plan_entitlements
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE owntend_monetization_private.maintenance_plan_entitlements
  TO service_role;

CREATE TABLE owntend_monetization_private.plan_economy_operations (
  operation_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  operation_kind text NOT NULL CHECK (operation_kind IN ('plan_move', 'asset_type_change')),
  subject_id text NOT NULL CHECK (char_length(subject_id) BETWEEN 1 AND 200),
  request_hash text NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  client_request_hash text NOT NULL CHECK (client_request_hash ~ '^[0-9a-f]{64}$'),
  charged_amount integer NOT NULL CHECK (charged_amount BETWEEN 0 AND 1000),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX plan_economy_operations_user_created_idx
  ON owntend_monetization_private.plan_economy_operations(user_id, created_at DESC);
CREATE INDEX plan_economy_operations_user_kind_subject_idx
  ON owntend_monetization_private.plan_economy_operations(user_id, operation_kind, subject_id);

ALTER TABLE owntend_monetization_private.plan_economy_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE owntend_monetization_private.plan_economy_operations
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE owntend_monetization_private.plan_economy_operations
  TO service_role;

CREATE TABLE owntend_private.maintenance_history_restore_operations (
  operation_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_id text NOT NULL,
  request_hash text NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  client_request_hash text NOT NULL CHECK (client_request_hash ~ '^[0-9a-f]{64}$'),
  result_status text NOT NULL CHECK (result_status IN ('applied', 'conflict')),
  conflict_reason text CHECK (
    conflict_reason IS NULL OR conflict_reason IN ('plan_snapshot_conflict', 'history_record_conflict')
  ),
  inserted_count integer NOT NULL DEFAULT 0 CHECK (inserted_count BETWEEN 0 AND 100),
  existing_count integer NOT NULL DEFAULT 0 CHECK (existing_count BETWEEN 0 AND 100),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT maintenance_history_restore_operations_plan_fkey
    FOREIGN KEY (user_id, plan_id)
    REFERENCES public.maintenance_plans(user_id, id)
    ON DELETE CASCADE
);

CREATE INDEX maintenance_history_restore_operations_user_plan_idx
  ON owntend_private.maintenance_history_restore_operations(user_id, plan_id, created_at DESC);

ALTER TABLE owntend_private.maintenance_history_restore_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE owntend_private.maintenance_history_restore_operations
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE owntend_private.maintenance_history_restore_operations
  TO service_role;

-- Existing unsupported plans are preserved without pretending they were paid.
INSERT INTO owntend_monetization_private.maintenance_plan_entitlements (
  user_id,
  plan_id,
  paid_cost,
  origin,
  created_by_operation_id
)
SELECT
  p.user_id,
  p.id,
  COALESCE(o.charged_amount, 0)::smallint,
  CASE WHEN o.operation_id IS NULL THEN 'legacy_unverified' ELSE 'task_creation' END,
  o.operation_id
FROM public.maintenance_plans AS p
LEFT JOIN public.creation_point_operations AS o
  ON o.user_id = p.user_id
 AND o.entity_type = 'task'
 AND o.entity_id = p.id
ON CONFLICT (user_id, plan_id) DO NOTHING;

ALTER TABLE public.point_transactions
  DROP CONSTRAINT point_transactions_transaction_type_check;
ALTER TABLE public.point_transactions
  ADD CONSTRAINT point_transactions_transaction_type_check CHECK (
    transaction_type IN (
      'initial_grant', 'task_creation', 'asset_creation',
      'task_entitlement_upgrade', 'rewarded_ad', 'rewarded_interstitial',
      'refund', 'admin_adjustment'
    )
  );

CREATE OR REPLACE FUNCTION owntend_monetization_private.ensure_plan_entitlement_from_task_authorization(
  p_user_id uuid,
  p_plan_id text
) RETURNS smallint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_operation public.creation_point_operations%ROWTYPE;
  v_paid_cost smallint;
BEGIN
  IF auth.uid() IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;

  SELECT * INTO v_operation
  FROM public.creation_point_operations
  WHERE user_id = p_user_id
    AND entity_type = 'task'
    AND entity_id = p_plan_id;

  IF NOT FOUND OR v_operation.charged_amount NOT IN (0, 1) THEN
    RETURN NULL;
  END IF;

  INSERT INTO owntend_monetization_private.maintenance_plan_entitlements (
    user_id, plan_id, paid_cost, origin, created_by_operation_id
  ) VALUES (
    p_user_id,
    p_plan_id,
    v_operation.charged_amount::smallint,
    'completion_recovery',
    v_operation.operation_id
  )
  ON CONFLICT (user_id, plan_id) DO UPDATE
  SET paid_cost = GREATEST(
        owntend_monetization_private.maintenance_plan_entitlements.paid_cost,
        EXCLUDED.paid_cost
      ),
      updated_at = clock_timestamp()
  RETURNING paid_cost INTO v_paid_cost;

  RETURN v_paid_cost;
END;
$$;

ALTER FUNCTION owntend_monetization_private.ensure_plan_entitlement_from_task_authorization(uuid, text)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_monetization_private.ensure_plan_entitlement_from_task_authorization(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.ensure_plan_entitlement_from_task_authorization(uuid, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION owntend_monetization_private.can_reconcile_maintenance_plan(
  p_user_id uuid,
  p_plan_id text
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT auth.uid() = p_user_id
    AND (
      EXISTS (
        SELECT 1
        FROM public.maintenance_plans
        WHERE user_id = p_user_id AND id = p_plan_id
      )
      OR EXISTS (
        SELECT 1
        FROM owntend_monetization_private.maintenance_plan_entitlements
        WHERE user_id = p_user_id AND plan_id = p_plan_id
      )
    );
$$;

ALTER FUNCTION owntend_monetization_private.can_reconcile_maintenance_plan(uuid, text)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_monetization_private.can_reconcile_maintenance_plan(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.can_reconcile_maintenance_plan(uuid, text)
  TO authenticated, service_role;

DROP POLICY maintenance_plans_insert_own ON public.maintenance_plans;
CREATE POLICY maintenance_plans_insert_own ON public.maintenance_plans
FOR INSERT TO authenticated
WITH CHECK (
  (SELECT auth.uid()) = user_id
  AND owntend_monetization_private.can_reconcile_maintenance_plan(user_id, id)
);

CREATE OR REPLACE FUNCTION owntend_monetization_private.create_task_with_point_debit_impl(
  p_operation jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  operation_uuid uuid;
  plan_json jsonb;
  metadata_json jsonb;
  v_plan_id text;
  target_asset_id text;
  current_balance integer;
  next_balance integer;
  charge integer := 1;
  is_safety boolean;
  config_row public.monetization_config%ROWTYPE;
  existing_operation public.creation_point_operations%ROWTYPE;
  v_request_hash text;
  v_client_request_hash text;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_operation IS NULL OR jsonb_typeof(p_operation) <> 'object'
     OR pg_column_size(p_operation) > 65536 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION';
  END IF;
  BEGIN
    operation_uuid := (p_operation->>'operation_id')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION_ID';
  END;
  v_client_request_hash := lower(NULLIF(btrim(p_operation->>'request_hash'), ''));
  IF v_client_request_hash IS NULL OR v_client_request_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_REQUEST_HASH';
  END IF;
  plan_json := p_operation->'plan';
  metadata_json := COALESCE(p_operation->'metadata', '{}'::jsonb);
  IF jsonb_typeof(plan_json) <> 'object'
     OR jsonb_typeof(metadata_json) <> 'object'
     OR (metadata_json ? 'required_materials'
         AND jsonb_typeof(metadata_json->'required_materials') <> 'array')
     OR plan_json ? 'health_group' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
  END IF;
  v_plan_id := NULLIF(btrim(plan_json->>'id'), '');
  target_asset_id := NULLIF(btrim(plan_json->>'asset_id'), '');
  IF v_plan_id IS NULL OR target_asset_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
  END IF;
  v_request_hash := encode(extensions.digest(p_operation::text::bytea, 'sha256'), 'hex');

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text || ':task_op:' || operation_uuid::text, 0)
  );

  SELECT * INTO existing_operation
  FROM public.creation_point_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    IF existing_operation.user_id <> caller_id
       OR existing_operation.entity_type <> 'task'
       OR existing_operation.entity_id <> v_plan_id
       OR existing_operation.request_hash <> v_request_hash
       OR existing_operation.client_request_hash <> v_client_request_hash THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
    END IF;
    SELECT balance INTO current_balance FROM public.point_wallets WHERE user_id = caller_id;
    RETURN jsonb_build_object(
      'task_id', v_plan_id,
      'balance', current_balance,
      'charged', existing_operation.charged_amount,
      'already_processed', true,
      'plan', (SELECT to_jsonb(p) FROM public.maintenance_plans p
               WHERE p.user_id = caller_id AND p.id = v_plan_id),
      'metadata', (SELECT to_jsonb(m) FROM public.maintenance_plan_metadata m
                   WHERE m.user_id = caller_id AND m.plan_id = v_plan_id)
    );
  END IF;

  SELECT a.asset_type = 'safety' INTO is_safety
  FROM public.assets a
  WHERE a.user_id = caller_id AND a.id = target_asset_id AND a.archived_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '23503', message = 'ASSET_NOT_FOUND';
  END IF;
  SELECT * INTO config_row FROM public.monetization_config WHERE singleton = true;
  IF NOT config_row.points_enabled OR config_row.emergency_free_creation_mode OR is_safety THEN
    charge := 0;
  END IF;

  SELECT balance INTO current_balance
  FROM public.point_wallets
  WHERE user_id = caller_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = 'P0001', message = 'WALLET_NOT_FOUND';
  END IF;
  IF charge = 1 AND current_balance < 1 THEN
    RETURN jsonb_build_object(
      'status', 'insufficient_points', 'task_id', NULL,
      'balance', current_balance, 'charged', 0, 'already_processed', false
    );
  END IF;
  next_balance := current_balance - charge;

  INSERT INTO public.maintenance_plans (
    user_id, id, asset_id, title, instructions, recurrence_interval,
    recurrence_unit, priority, next_due_date, reminder_days_before,
    created_at, updated_at, archived_at, revision, is_enabled
  ) VALUES (
    caller_id, v_plan_id, target_asset_id, btrim(plan_json->>'title'),
    NULLIF(btrim(plan_json->>'instructions'), ''),
    COALESCE((plan_json->>'recurrence_interval')::integer, 1),
    COALESCE(plan_json->>'recurrence_unit', 'months'),
    COALESCE(plan_json->>'priority', 'medium'),
    (plan_json->>'next_due_date')::timestamptz,
    COALESCE((plan_json->>'reminder_days_before')::integer, 0),
    clock_timestamp(), clock_timestamp(), NULL, 1,
    COALESCE((plan_json->>'is_enabled')::boolean, true)
  );

  IF metadata_json <> '{}'::jsonb THEN
    INSERT INTO public.maintenance_plan_metadata (
      user_id, plan_id, task_type, location_label, estimated_duration_minutes,
      required_materials_json, reminder_recommendation, sort_order,
      created_at, updated_at, revision
    ) VALUES (
      caller_id, v_plan_id,
      NULLIF(btrim(metadata_json->>'task_type'), ''),
      NULLIF(btrim(metadata_json->>'location_label'), ''),
      (metadata_json->>'estimated_duration_minutes')::integer,
      COALESCE(metadata_json->>'required_materials_json',
               (metadata_json->'required_materials')::text, '[]'),
      NULLIF(btrim(metadata_json->>'reminder_recommendation'), ''),
      COALESCE((metadata_json->>'sort_order')::integer, 0),
      clock_timestamp(), clock_timestamp(), 1
    );
  END IF;

  INSERT INTO public.creation_point_operations (
    operation_id, user_id, entity_type, entity_id, charged_amount,
    request_hash, client_request_hash
  ) VALUES (
    operation_uuid, caller_id, 'task', v_plan_id, charge,
    v_request_hash, v_client_request_hash
  );

  INSERT INTO owntend_monetization_private.maintenance_plan_entitlements (
    user_id, plan_id, paid_cost, origin, created_by_operation_id
  ) VALUES (
    caller_id, v_plan_id, charge::smallint, 'task_creation', operation_uuid
  );

  IF charge = 1 THEN
    UPDATE public.point_wallets
    SET balance = next_balance, updated_at = clock_timestamp()
    WHERE user_id = caller_id;
    INSERT INTO public.point_transactions (
      user_id, amount, balance_before, balance_after, transaction_type,
      reference_id, idempotency_key, metadata
    ) VALUES (
      caller_id, -1, current_balance, next_balance, 'task_creation',
      v_plan_id, 'create-task:' || operation_uuid::text,
      jsonb_build_object('asset_id', target_asset_id)
    );
  END IF;

  RETURN jsonb_build_object(
    'task_id', v_plan_id, 'balance', next_balance, 'charged', charge,
    'already_processed', false,
    'plan', (SELECT to_jsonb(p) FROM public.maintenance_plans p
             WHERE p.user_id = caller_id AND p.id = v_plan_id),
    'metadata', (SELECT to_jsonb(m) FROM public.maintenance_plan_metadata m
                 WHERE m.user_id = caller_id AND m.plan_id = v_plan_id)
  );
EXCEPTION
  WHEN check_violation OR not_null_violation OR invalid_text_representation THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
END;
$$;

ALTER FUNCTION owntend_monetization_private.create_task_with_point_debit_impl(jsonb)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_monetization_private.create_task_with_point_debit_impl(jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.create_task_with_point_debit_impl(jsonb)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_task_with_point_debit(p_operation jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.create_task_with_point_debit_impl(p_operation);
END;
$$;
ALTER FUNCTION public.create_task_with_point_debit(jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.create_task_with_point_debit(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_task_with_point_debit(jsonb)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION owntend_private.complete_maintenance_task_impl(
  p_operation jsonb,
  p_device_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  request_user uuid := auth.uid();
  plan_payload jsonb;
  record_payload jsonb;
  operation_id_value text;
  plan_id_value text;
  record_id_value text;
  record_plan_id_value text;
  expected_plan_revision bigint;
  expected_next_due_date timestamptz;
  plan_next_due_date timestamptz;
  record_due_date timestamptz;
  record_completed_at timestamptz;
  plan_created_at timestamptz;
  plan_updated_at timestamptz;
  plan_archived_at timestamptz;
  plan_recurrence_interval integer;
  plan_reminder_days_before integer;
  plan_is_enabled boolean;
  current_plan public.maintenance_plans%ROWTYPE;
  current_record public.maintenance_records%ROWTYPE;
  occurrence_record public.maintenance_records%ROWTYPE;
  plan_was_created boolean := false;
  authorized_cost smallint;
BEGIN
  IF request_user IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF COALESCE(length(btrim(p_device_id)), 0) = 0 OR length(p_device_id) > 200 THEN
    RETURN jsonb_build_object('status', 'invalid', 'retryable', false,
                              'conflict_reason', 'invalid_device_id');
  END IF;
  IF jsonb_typeof(p_operation) IS DISTINCT FROM 'object'
     OR p_operation->>'version' IS DISTINCT FROM '1' THEN
    RETURN jsonb_build_object('status', 'invalid', 'retryable', false,
                              'conflict_reason', 'invalid_payload_version');
  END IF;
  plan_payload := p_operation->'plan';
  record_payload := p_operation->'record';
  IF jsonb_typeof(plan_payload) IS DISTINCT FROM 'object'
     OR jsonb_typeof(record_payload) IS DISTINCT FROM 'object' THEN
    RETURN jsonb_build_object('status', 'invalid', 'retryable', false,
                              'conflict_reason', 'incomplete_payload');
  END IF;

  operation_id_value := NULLIF(btrim(p_operation->>'operation_id'), '');
  plan_id_value := NULLIF(btrim(plan_payload->>'id'), '');
  record_id_value := NULLIF(btrim(record_payload->>'id'), '');
  record_plan_id_value := NULLIF(btrim(record_payload->>'plan_id'), '');
  IF operation_id_value IS NULL OR plan_id_value IS NULL OR record_id_value IS NULL
     OR record_plan_id_value IS NULL OR record_plan_id_value <> plan_id_value THEN
    RETURN jsonb_build_object('status', 'invalid', 'retryable', false,
                              'conflict_reason', 'invalid_identifiers');
  END IF;

  BEGIN
    expected_plan_revision := NULLIF(p_operation->>'expected_plan_revision', '')::bigint;
    expected_next_due_date := date_trunc(
      'second', NULLIF(p_operation->>'expected_next_due_date', '')::timestamptz
    );
    plan_next_due_date := date_trunc(
      'second', NULLIF(plan_payload->>'next_due_date', '')::timestamptz
    );
    record_due_date := date_trunc(
      'second', NULLIF(record_payload->>'due_date', '')::timestamptz
    );
    record_completed_at := date_trunc(
      'second', NULLIF(record_payload->>'completed_at', '')::timestamptz
    );
    plan_created_at := date_trunc(
      'second', NULLIF(plan_payload->>'created_at', '')::timestamptz
    );
    plan_updated_at := date_trunc(
      'second', COALESCE(NULLIF(plan_payload->>'updated_at', '')::timestamptz,
                         clock_timestamp())
    );
    plan_archived_at := CASE
      WHEN plan_payload->'archived_at' IS NULL OR plan_payload->'archived_at' = 'null'::jsonb
        THEN NULL
      ELSE date_trunc('second', NULLIF(plan_payload->>'archived_at', '')::timestamptz)
    END;
    plan_recurrence_interval := NULLIF(plan_payload->>'recurrence_interval', '')::integer;
    plan_reminder_days_before := COALESCE(
      NULLIF(plan_payload->>'reminder_days_before', '')::integer, 0
    );
    plan_is_enabled := NULLIF(plan_payload->>'is_enabled', '')::boolean;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('status', 'invalid', 'retryable', false,
                              'conflict_reason', 'invalid_values');
  END;

  IF expected_next_due_date IS NULL OR record_due_date IS NULL
     OR record_completed_at IS NULL OR plan_next_due_date IS NULL
     OR plan_created_at IS NULL OR plan_recurrence_interval IS NULL
     OR plan_is_enabled IS NULL
     OR record_due_date IS DISTINCT FROM expected_next_due_date
     OR plan_next_due_date <= record_completed_at
     OR plan_recurrence_interval <= 0 OR plan_reminder_days_before < 0 THEN
    RETURN jsonb_build_object('status', 'invalid', 'retryable', false,
                              'conflict_reason', 'invalid_completion');
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(request_user::text || ':' || plan_id_value, 0)
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(request_user::text || ':operation:' || operation_id_value, 0)
  );

  SELECT * INTO current_record
  FROM public.maintenance_records
  WHERE user_id = request_user AND operation_id = operation_id_value;
  IF FOUND THEN
    SELECT * INTO current_plan
    FROM public.maintenance_plans
    WHERE user_id = request_user AND id = current_record.plan_id;
    IF current_record.id <> record_id_value
       OR current_record.plan_id <> plan_id_value
       OR date_trunc('second', current_record.due_date) IS DISTINCT FROM record_due_date
       OR date_trunc('second', current_record.completed_at) IS DISTINCT FROM record_completed_at
       OR COALESCE(NULLIF(btrim(current_record.notes), ''), '') IS DISTINCT FROM
          COALESCE(NULLIF(btrim(record_payload->>'notes'), ''), '') THEN
      RETURN jsonb_build_object(
        'status', 'conflict', 'retryable', false,
        'conflict_reason', 'operation_id_reused',
        'current_plan_revision', current_plan.revision,
        'resulting_record_id', current_record.id,
        'resulting_next_due_date', current_plan.next_due_date,
        'plan', to_jsonb(current_plan), 'record', to_jsonb(current_record)
      );
    END IF;
    RETURN jsonb_build_object(
      'status', 'already_applied', 'retryable', false, 'conflict_reason', NULL,
      'current_plan_revision', current_plan.revision,
      'resulting_record_id', current_record.id,
      'resulting_next_due_date', current_plan.next_due_date,
      'plan', to_jsonb(current_plan), 'record', to_jsonb(current_record)
    );
  END IF;

  SELECT * INTO current_plan
  FROM public.maintenance_plans
  WHERE user_id = request_user AND id = plan_id_value
  FOR UPDATE;
  IF FOUND THEN
    IF current_plan.archived_at IS NOT NULL OR current_plan.is_enabled IS NOT TRUE THEN
      RETURN jsonb_build_object(
        'status', 'conflict', 'retryable', false, 'conflict_reason', 'plan_inactive',
        'current_plan_revision', current_plan.revision, 'resulting_record_id', NULL,
        'resulting_next_due_date', current_plan.next_due_date,
        'plan', to_jsonb(current_plan), 'record', NULL
      );
    END IF;
    IF date_trunc('second', current_plan.next_due_date) IS DISTINCT FROM expected_next_due_date THEN
      SELECT * INTO occurrence_record
      FROM public.maintenance_records
      WHERE user_id = request_user AND plan_id = plan_id_value
        AND date_trunc('second', due_date) = record_due_date
      ORDER BY completed_at DESC, id DESC
      LIMIT 1;
      IF FOUND THEN
        RETURN jsonb_build_object(
          'status', 'conflict', 'retryable', false,
          'conflict_reason', 'occurrence_completed_elsewhere',
          'current_plan_revision', current_plan.revision,
          'resulting_record_id', occurrence_record.id,
          'resulting_next_due_date', current_plan.next_due_date,
          'plan', to_jsonb(current_plan), 'record', to_jsonb(occurrence_record)
        );
      END IF;
      RETURN jsonb_build_object(
        'status', 'conflict', 'retryable', false,
        'conflict_reason', 'occurrence_changed',
        'current_plan_revision', current_plan.revision,
        'resulting_record_id', NULL,
        'resulting_next_due_date', current_plan.next_due_date,
        'plan', to_jsonb(current_plan), 'record', NULL
      );
    END IF;
    IF expected_plan_revision IS NOT NULL
       AND current_plan.revision IS DISTINCT FROM expected_plan_revision THEN
      RETURN jsonb_build_object(
        'status', 'conflict', 'retryable', true,
        'conflict_reason', 'stale_plan_revision',
        'current_plan_revision', current_plan.revision,
        'resulting_record_id', NULL,
        'resulting_next_due_date', current_plan.next_due_date,
        'plan', to_jsonb(current_plan), 'record', NULL
      );
    END IF;
  ELSE
    authorized_cost :=
      owntend_monetization_private.ensure_plan_entitlement_from_task_authorization(
        request_user, plan_id_value
      );
    IF authorized_cost IS NULL THEN
      RETURN jsonb_build_object(
        'status', 'invalid', 'retryable', false,
        'conflict_reason', 'task_creation_not_authorized'
      );
    END IF;
    INSERT INTO public.maintenance_plans (
      id, user_id, asset_id, title, instructions, recurrence_interval,
      recurrence_unit, priority, next_due_date, reminder_days_before,
      created_at, updated_at, archived_at, revision, is_enabled
    ) VALUES (
      plan_id_value, request_user, NULLIF(btrim(plan_payload->>'asset_id'), ''),
      NULLIF(btrim(plan_payload->>'title'), ''),
      NULLIF(btrim(plan_payload->>'instructions'), ''),
      plan_recurrence_interval,
      COALESCE(NULLIF(btrim(plan_payload->>'recurrence_unit'), ''), 'months'),
      NULLIF(btrim(plan_payload->>'priority'), ''), plan_next_due_date,
      plan_reminder_days_before, plan_created_at, plan_updated_at,
      plan_archived_at, COALESCE(expected_plan_revision, 1), plan_is_enabled
    ) RETURNING * INTO current_plan;
    plan_was_created := true;
  END IF;

  INSERT INTO public.maintenance_records (
    id, user_id, plan_id, due_date, completed_at, notes, created_at, operation_id
  ) VALUES (
    record_id_value, request_user, plan_id_value, record_due_date,
    record_completed_at, NULLIF(btrim(record_payload->>'notes'), ''),
    COALESCE(
      date_trunc('second', NULLIF(btrim(record_payload->>'created_at'), '')::timestamptz),
      date_trunc('second', clock_timestamp())
    ),
    operation_id_value
  ) RETURNING * INTO current_record;

  IF NOT plan_was_created THEN
    UPDATE public.maintenance_plans
    SET next_due_date = plan_next_due_date,
        updated_at = plan_updated_at,
        archived_at = plan_archived_at,
        is_enabled = plan_is_enabled
    WHERE user_id = request_user AND id = plan_id_value
    RETURNING * INTO current_plan;
  END IF;

  UPDATE public.notification_inbox
  SET read_at = COALESCE(read_at, clock_timestamp()), updated_at = clock_timestamp()
  WHERE user_id = request_user AND plan_id = plan_id_value;

  RETURN jsonb_build_object(
    'status', 'applied', 'retryable', false, 'conflict_reason', NULL,
    'current_plan_revision', current_plan.revision,
    'resulting_record_id', current_record.id,
    'resulting_next_due_date', current_plan.next_due_date,
    'plan', to_jsonb(current_plan), 'record', to_jsonb(current_record)
  );
END;
$$;

ALTER FUNCTION owntend_private.complete_maintenance_task_impl(jsonb, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_private.complete_maintenance_task_impl(jsonb, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_private.complete_maintenance_task_impl(jsonb, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.complete_maintenance_task(
  p_operation jsonb,
  p_device_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_private.complete_maintenance_task_impl(p_operation, p_device_id);
END;
$$;

ALTER FUNCTION public.complete_maintenance_task(jsonb, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.complete_maintenance_task(jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_maintenance_task(jsonb, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION owntend_private.undo_maintenance_completion_impl(
  p_operation jsonb,
  p_device_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  request_user uuid := auth.uid();
  operation_id_value text;
  plan_id_value text;
  completion_id_value text;
  target_completed_at timestamptz;
  previous_due_date_value timestamptz;
  expected_current_due timestamptz;
  current_plan public.maintenance_plans%ROWTYPE;
  target_record public.maintenance_records%ROWTYPE;
  latest_record public.maintenance_records%ROWTYPE;
  has_newer boolean := false;
  rewound_value boolean := false;
  target_existed boolean := false;
BEGIN
  IF request_user IS NULL THEN
    RETURN jsonb_build_object('status', 'unauthorized', 'retryable', false,
                              'conflict_reason', 'authentication_required');
  END IF;
  IF p_operation IS NULL OR jsonb_typeof(p_operation) <> 'object'
     OR COALESCE((p_operation->>'version')::integer, 0) <> 1
     OR NULLIF(btrim(COALESCE(p_device_id, '')), '') IS NULL THEN
    RETURN jsonb_build_object('status', 'invalid', 'retryable', false,
                              'conflict_reason', 'invalid_payload');
  END IF;
  operation_id_value := NULLIF(btrim(p_operation->>'operation_id'), '');
  plan_id_value := NULLIF(btrim(p_operation->>'plan_id'), '');
  completion_id_value := NULLIF(btrim(p_operation->>'completion_id'), '');
  BEGIN
    target_completed_at := date_trunc(
      'second', NULLIF(btrim(p_operation->>'completion_completed_at'), '')::timestamptz
    );
    previous_due_date_value := date_trunc(
      'second', NULLIF(btrim(p_operation->>'previous_due_date'), '')::timestamptz
    );
    expected_current_due := date_trunc(
      'second', NULLIF(btrim(p_operation->>'expected_current_next_due_date'), '')::timestamptz
    );
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('status', 'invalid', 'retryable', false,
                              'conflict_reason', 'invalid_timestamp');
  END;
  IF operation_id_value IS NULL OR plan_id_value IS NULL OR completion_id_value IS NULL
     OR target_completed_at IS NULL OR previous_due_date_value IS NULL
     OR expected_current_due IS NULL THEN
    RETURN jsonb_build_object('status', 'invalid', 'retryable', false,
                              'conflict_reason', 'missing_fields');
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(request_user::text || ':maintenance:' || plan_id_value, 0)
  );
  SELECT * INTO current_plan
  FROM public.maintenance_plans
  WHERE user_id = request_user AND id = plan_id_value
  FOR UPDATE;
  IF current_plan.id IS NULL THEN
    RETURN jsonb_build_object('status', 'invalid', 'retryable', false,
                              'conflict_reason', 'plan_missing');
  END IF;
  SELECT * INTO target_record
  FROM public.maintenance_records
  WHERE user_id = request_user AND id = completion_id_value AND plan_id = plan_id_value
  FOR UPDATE;
  target_existed := target_record.id IS NOT NULL;
  IF target_existed THEN
    DELETE FROM public.maintenance_records
    WHERE user_id = request_user AND id = completion_id_value;
  END IF;
  SELECT * INTO latest_record
  FROM public.maintenance_records
  WHERE user_id = request_user AND plan_id = plan_id_value
  ORDER BY completed_at DESC, id DESC
  LIMIT 1;
  has_newer := latest_record.id IS NOT NULL AND (
    latest_record.completed_at > target_completed_at
    OR (latest_record.completed_at = target_completed_at AND latest_record.id > completion_id_value)
  );
  IF NOT has_newer AND current_plan.next_due_date IS NOT DISTINCT FROM expected_current_due THEN
    UPDATE public.maintenance_plans
    SET next_due_date = previous_due_date_value
    WHERE user_id = request_user AND id = plan_id_value
    RETURNING * INTO current_plan;
    rewound_value := true;
  END IF;
  UPDATE public.notification_inbox
  SET read_at = NULL, updated_at = clock_timestamp()
  WHERE user_id = request_user
    AND id = (
      SELECT id FROM public.notification_inbox
      WHERE user_id = request_user AND plan_id = plan_id_value AND kind = 'task'
      ORDER BY created_at DESC, id DESC LIMIT 1
    );
  RETURN jsonb_build_object(
    'status', CASE WHEN target_existed OR rewound_value THEN 'applied' ELSE 'already_applied' END,
    'retryable', false, 'conflict_reason', NULL,
    'rewound', rewound_value, 'plan', to_jsonb(current_plan)
  );
END;
$$;

ALTER FUNCTION owntend_private.undo_maintenance_completion_impl(jsonb, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_private.undo_maintenance_completion_impl(jsonb, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_private.undo_maintenance_completion_impl(jsonb, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.undo_maintenance_completion(
  p_operation jsonb,
  p_device_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_private.undo_maintenance_completion_impl(p_operation, p_device_id);
END;
$$;

ALTER FUNCTION public.undo_maintenance_completion(jsonb, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.undo_maintenance_completion(jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.undo_maintenance_completion(jsonb, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION owntend_monetization_private.required_task_cost_for_asset_type(
  p_asset_type text
) RETURNS smallint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN NOT c.points_enabled OR c.emergency_free_creation_mode OR p_asset_type = 'safety'
      THEN 0::smallint
    ELSE 1::smallint
  END
  FROM public.monetization_config c
  WHERE c.singleton = true;
$$;

ALTER FUNCTION owntend_monetization_private.required_task_cost_for_asset_type(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_monetization_private.required_task_cost_for_asset_type(text)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION owntend_monetization_private.copy_asset_impl(
  p_operation jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  operation_uuid uuid;
  v_client_request_hash text;
  v_request_hash text;
  v_source_asset_id text;
  v_target_asset_id text;
  v_room_id text;
  v_include_tasks boolean;
  v_plan_map jsonb;
  v_source public.assets%ROWTYPE;
  v_existing public.creation_point_operations%ROWTYPE;
  v_plan_count integer;
  v_balance integer;
  v_plan public.maintenance_plans%ROWTYPE;
  v_target_plan_id text;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_operation IS NULL OR jsonb_typeof(p_operation) <> 'object'
     OR pg_column_size(p_operation) > 65536 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_COPY_OPERATION';
  END IF;
  BEGIN
    operation_uuid := (p_operation->>'operation_id')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION_ID';
  END;
  v_client_request_hash := lower(NULLIF(btrim(p_operation->>'request_hash'), ''));
  v_source_asset_id := NULLIF(btrim(p_operation->>'source_asset_id'), '');
  v_target_asset_id := NULLIF(btrim(p_operation->>'target_asset_id'), '');
  v_room_id := NULLIF(btrim(p_operation->>'destination_room_id'), '');
  v_include_tasks := COALESCE((p_operation->>'include_tasks')::boolean, false);
  v_plan_map := COALESCE(p_operation->'plan_id_map', '{}'::jsonb);
  IF v_client_request_hash IS NULL OR v_client_request_hash !~ '^[0-9a-f]{64}$'
     OR v_source_asset_id IS NULL OR v_target_asset_id IS NULL OR v_room_id IS NULL
     OR v_source_asset_id = v_target_asset_id
     OR char_length(v_target_asset_id) > 200
     OR jsonb_typeof(v_plan_map) <> 'object' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_COPY_OPERATION';
  END IF;
  v_request_hash := encode(extensions.digest(p_operation::text::bytea, 'sha256'), 'hex');
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text || ':asset_copy:' || operation_uuid::text, 0)
  );

  SELECT * INTO v_existing
  FROM public.creation_point_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    IF v_existing.user_id <> caller_id OR v_existing.entity_type <> 'asset'
       OR v_existing.entity_id <> v_target_asset_id
       OR v_existing.request_hash <> v_request_hash
       OR v_existing.client_request_hash <> v_client_request_hash THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
    END IF;
    SELECT balance INTO v_balance FROM public.point_wallets WHERE user_id = caller_id;
    RETURN jsonb_build_object(
      'asset_id', v_target_asset_id, 'balance', COALESCE(v_balance, 0),
      'charged', 0, 'already_processed', true,
      'asset', (SELECT to_jsonb(a) FROM public.assets a
                WHERE a.user_id = caller_id AND a.id = v_target_asset_id),
       'plans', COALESCE((
         SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id)
         FROM public.maintenance_plans p
         WHERE p.user_id = caller_id AND p.asset_id = v_target_asset_id
       ), '[]'::jsonb),
       'plan_metadata', COALESCE((
         SELECT jsonb_agg(to_jsonb(m) ORDER BY m.plan_id)
         FROM public.maintenance_plan_metadata m
         JOIN public.maintenance_plans p
           ON p.user_id = m.user_id AND p.id = m.plan_id
         WHERE p.user_id = caller_id AND p.asset_id = v_target_asset_id
       ), '[]'::jsonb),
       'detail_rows', COALESCE((
         SELECT jsonb_agg(x.item)
         FROM (
           SELECT jsonb_build_object('entity', 'device_detail', 'row', to_jsonb(d)) AS item
           FROM public.device_details d WHERE d.user_id = caller_id AND d.asset_id = v_target_asset_id
           UNION ALL
           SELECT jsonb_build_object('entity', 'pet_detail', 'row', to_jsonb(d))
           FROM public.pet_details d WHERE d.user_id = caller_id AND d.asset_id = v_target_asset_id
           UNION ALL
           SELECT jsonb_build_object('entity', 'plant_detail', 'row', to_jsonb(d))
           FROM public.plant_details d WHERE d.user_id = caller_id AND d.asset_id = v_target_asset_id
           UNION ALL
           SELECT jsonb_build_object('entity', 'safety_detail', 'row', to_jsonb(d))
           FROM public.safety_details d WHERE d.user_id = caller_id AND d.asset_id = v_target_asset_id
         ) x
       ), '[]'::jsonb)
    );
  END IF;

  SELECT * INTO v_source
  FROM public.assets
  WHERE user_id = caller_id AND id = v_source_asset_id AND archived_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'SOURCE_ASSET_NOT_FOUND';
  END IF;
  PERFORM 1 FROM public.rooms
  WHERE user_id = caller_id AND id = v_room_id AND archived_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'DESTINATION_ROOM_NOT_FOUND';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.assets
    WHERE user_id = caller_id AND id = v_target_asset_id
  ) THEN
    RAISE EXCEPTION USING errcode = '23505', message = 'TARGET_ASSET_EXISTS';
  END IF;

  SELECT count(*)::integer INTO v_plan_count
  FROM public.maintenance_plans
  WHERE user_id = caller_id AND asset_id = v_source_asset_id
    AND archived_at IS NULL AND is_enabled;
  IF v_plan_count > 50 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'COPY_TASK_LIMIT_EXCEEDED';
  END IF;
  IF NOT v_include_tasks AND v_plan_map <> '{}'::jsonb THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_PLAN_ID_MAP';
  END IF;
  IF v_include_tasks THEN
    IF (SELECT count(*) FROM jsonb_each(v_plan_map)) <> v_plan_count
       OR EXISTS (
         SELECT 1 FROM public.maintenance_plans p
         WHERE p.user_id = caller_id AND p.asset_id = v_source_asset_id
           AND p.archived_at IS NULL AND p.is_enabled
           AND NOT (v_plan_map ? p.id)
       )
       OR EXISTS (
         SELECT 1 FROM jsonb_each_text(v_plan_map) m
         LEFT JOIN public.maintenance_plans p
           ON p.user_id = caller_id AND p.id = m.key
          AND p.asset_id = v_source_asset_id
          AND p.archived_at IS NULL AND p.is_enabled
         WHERE p.id IS NULL OR NULLIF(btrim(m.value), '') IS NULL
            OR char_length(m.value) > 200 OR m.value = v_target_asset_id
       )
       OR (SELECT count(*) FROM jsonb_each_text(v_plan_map))
          <> (SELECT count(DISTINCT value) FROM jsonb_each_text(v_plan_map)) THEN
      RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_PLAN_ID_MAP';
    END IF;
    IF EXISTS (
      SELECT 1
      FROM jsonb_each_text(v_plan_map) m
      JOIN public.maintenance_plans p
        ON p.user_id = caller_id AND p.id = m.value
    ) THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'TARGET_PLAN_EXISTS';
    END IF;
  END IF;

  INSERT INTO public.assets (
    user_id, id, name, asset_type, room_id, placement, notes, purchase_date,
    revision, created_at, updated_at, archived_at
  ) VALUES (
    caller_id, v_target_asset_id, v_source.name, v_source.asset_type, v_room_id,
    v_source.placement, v_source.notes, v_source.purchase_date,
    1, clock_timestamp(), clock_timestamp(), NULL
  );
  INSERT INTO public.device_details (
    user_id, asset_id, brand, model, serial_number, power_source, warranty_until,
    manual_url, consumable, revision, created_at, updated_at
  )
  SELECT caller_id, v_target_asset_id, brand, model, serial_number, power_source,
         warranty_until, manual_url, consumable, 1, clock_timestamp(), clock_timestamp()
  FROM public.device_details
  WHERE user_id = caller_id AND asset_id = v_source_asset_id;
  INSERT INTO public.pet_details (
    user_id, asset_id, species, breed, birth_date, microchip_id, vet_name,
    vet_phone, feeding_notes, medical_notes, revision, created_at, updated_at
  )
  SELECT caller_id, v_target_asset_id, species, breed, birth_date, microchip_id,
         vet_name, vet_phone, feeding_notes, medical_notes, 1,
         clock_timestamp(), clock_timestamp()
  FROM public.pet_details
  WHERE user_id = caller_id AND asset_id = v_source_asset_id;
  INSERT INTO public.plant_details (
    user_id, asset_id, species, sunlight, watering_interval_days, pot_size,
    last_repotted_at, toxicity_notes, revision, created_at, updated_at
  )
  SELECT caller_id, v_target_asset_id, species, sunlight, watering_interval_days,
         pot_size, last_repotted_at, toxicity_notes, 1,
         clock_timestamp(), clock_timestamp()
  FROM public.plant_details
  WHERE user_id = caller_id AND asset_id = v_source_asset_id;
  INSERT INTO public.safety_details (
    user_id, asset_id, safety_type, installed_at, expires_at, battery_type,
    test_interval_days, revision, created_at, updated_at
  )
  SELECT caller_id, v_target_asset_id, safety_type, installed_at, expires_at,
         battery_type, test_interval_days, 1, clock_timestamp(), clock_timestamp()
  FROM public.safety_details
  WHERE user_id = caller_id AND asset_id = v_source_asset_id;

  IF v_include_tasks THEN
    FOR v_plan IN
      SELECT * FROM public.maintenance_plans
      WHERE user_id = caller_id AND asset_id = v_source_asset_id
        AND archived_at IS NULL AND is_enabled
      ORDER BY id
    LOOP
      v_target_plan_id := v_plan_map->>v_plan.id;
      INSERT INTO public.maintenance_plans (
        user_id, id, asset_id, title, instructions, recurrence_interval,
        recurrence_unit, priority, next_due_date, is_enabled,
        reminder_days_before, revision, created_at, updated_at, archived_at
      ) VALUES (
        caller_id, v_target_plan_id, v_target_asset_id, v_plan.title,
        v_plan.instructions, v_plan.recurrence_interval, v_plan.recurrence_unit,
        v_plan.priority, v_plan.next_due_date, true, v_plan.reminder_days_before,
        1, clock_timestamp(), clock_timestamp(), NULL
      );
      INSERT INTO public.maintenance_plan_metadata (
        user_id, plan_id, task_type, location_label, estimated_duration_minutes,
        required_materials_json, reminder_recommendation, sort_order,
        revision, created_at, updated_at
      )
      SELECT caller_id, v_target_plan_id, task_type, location_label,
             estimated_duration_minutes, required_materials_json,
             reminder_recommendation, sort_order, 1,
             clock_timestamp(), clock_timestamp()
      FROM public.maintenance_plan_metadata
      WHERE user_id = caller_id AND plan_id = v_plan.id;
      INSERT INTO owntend_monetization_private.maintenance_plan_entitlements (
        user_id, plan_id, paid_cost, origin
      ) VALUES (caller_id, v_target_plan_id, 0, 'asset_copy');
    END LOOP;
  END IF;

  INSERT INTO public.creation_point_operations (
    operation_id, user_id, entity_type, entity_id, charged_amount,
    request_hash, client_request_hash
  ) VALUES (
    operation_uuid, caller_id, 'asset', v_target_asset_id, 0,
    v_request_hash, v_client_request_hash
  );
  SELECT balance INTO v_balance FROM public.point_wallets WHERE user_id = caller_id;
  RETURN jsonb_build_object(
    'asset_id', v_target_asset_id, 'balance', COALESCE(v_balance, 0),
    'charged', 0, 'already_processed', false,
    'asset', (SELECT to_jsonb(a) FROM public.assets a
              WHERE a.user_id = caller_id AND a.id = v_target_asset_id),
     'plans', COALESCE((
       SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id)
       FROM public.maintenance_plans p
       WHERE p.user_id = caller_id AND p.asset_id = v_target_asset_id
     ), '[]'::jsonb),
     'plan_metadata', COALESCE((
       SELECT jsonb_agg(to_jsonb(m) ORDER BY m.plan_id)
       FROM public.maintenance_plan_metadata m
       JOIN public.maintenance_plans p
         ON p.user_id = m.user_id AND p.id = m.plan_id
       WHERE p.user_id = caller_id AND p.asset_id = v_target_asset_id
     ), '[]'::jsonb),
     'detail_rows', COALESCE((
       SELECT jsonb_agg(x.item)
       FROM (
         SELECT jsonb_build_object('entity', 'device_detail', 'row', to_jsonb(d)) AS item
         FROM public.device_details d WHERE d.user_id = caller_id AND d.asset_id = v_target_asset_id
         UNION ALL
         SELECT jsonb_build_object('entity', 'pet_detail', 'row', to_jsonb(d))
         FROM public.pet_details d WHERE d.user_id = caller_id AND d.asset_id = v_target_asset_id
         UNION ALL
         SELECT jsonb_build_object('entity', 'plant_detail', 'row', to_jsonb(d))
         FROM public.plant_details d WHERE d.user_id = caller_id AND d.asset_id = v_target_asset_id
         UNION ALL
         SELECT jsonb_build_object('entity', 'safety_detail', 'row', to_jsonb(d))
         FROM public.safety_details d WHERE d.user_id = caller_id AND d.asset_id = v_target_asset_id
       ) x
     ), '[]'::jsonb)
  );
END;
$$;

ALTER FUNCTION owntend_monetization_private.copy_asset_impl(jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_monetization_private.copy_asset_impl(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.copy_asset_impl(jsonb)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.copy_asset(p_operation jsonb) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.copy_asset_impl(p_operation);
END;
$$;

ALTER FUNCTION public.copy_asset(jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.copy_asset(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.copy_asset(jsonb) TO authenticated, service_role;

-- Extend response-loss recovery so an authoritative asset copy can restore
-- the complete server-created composite, rather than only its asset row.
CREATE OR REPLACE FUNCTION owntend_monetization_private.get_charged_operation_status(
  p_operation_id uuid,
  p_request_hash text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_operation public.creation_point_operations%ROWTYPE;
  v_current_balance integer;
  v_normalized_hash text := lower(NULLIF(btrim(p_request_hash), ''));
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_operation_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION_ID';
  END IF;
  IF v_normalized_hash IS NULL OR v_normalized_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_REQUEST_HASH';
  END IF;

  SELECT * INTO v_operation
  FROM public.creation_point_operations
  WHERE operation_id = p_operation_id;
  IF NOT FOUND OR v_operation.user_id <> v_caller_id THEN
    RETURN jsonb_build_object('status', 'not_found');
  END IF;
  IF v_operation.client_request_hash <> v_normalized_hash THEN
    RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
  END IF;
  SELECT balance INTO v_current_balance
  FROM public.point_wallets WHERE user_id = v_caller_id;

  IF v_operation.entity_type = 'asset' THEN
    RETURN jsonb_build_object(
      'status', 'completed', 'operation_id', v_operation.operation_id,
      'entity_type', v_operation.entity_type, 'entity_id', v_operation.entity_id,
      'charged', v_operation.charged_amount,
      'balance', COALESCE(v_current_balance, 0),
      'asset', (SELECT to_jsonb(a) FROM public.assets a
                WHERE a.user_id = v_caller_id AND a.id = v_operation.entity_id),
      'plans', COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id)
                        FROM public.maintenance_plans p
                        WHERE p.user_id = v_caller_id
                          AND p.asset_id = v_operation.entity_id), '[]'::jsonb),
      'plan_metadata', COALESCE((
        SELECT jsonb_agg(to_jsonb(m) ORDER BY m.plan_id)
        FROM public.maintenance_plan_metadata m
        JOIN public.maintenance_plans p ON p.user_id = m.user_id AND p.id = m.plan_id
        WHERE p.user_id = v_caller_id AND p.asset_id = v_operation.entity_id
      ), '[]'::jsonb),
      'detail_rows', COALESCE((
        SELECT jsonb_agg(x.item)
        FROM (
          SELECT jsonb_build_object('entity', 'device_detail', 'row', to_jsonb(d)) AS item
          FROM public.device_details d WHERE d.user_id = v_caller_id AND d.asset_id = v_operation.entity_id
          UNION ALL
          SELECT jsonb_build_object('entity', 'pet_detail', 'row', to_jsonb(d))
          FROM public.pet_details d WHERE d.user_id = v_caller_id AND d.asset_id = v_operation.entity_id
          UNION ALL
          SELECT jsonb_build_object('entity', 'plant_detail', 'row', to_jsonb(d))
          FROM public.plant_details d WHERE d.user_id = v_caller_id AND d.asset_id = v_operation.entity_id
          UNION ALL
          SELECT jsonb_build_object('entity', 'safety_detail', 'row', to_jsonb(d))
          FROM public.safety_details d WHERE d.user_id = v_caller_id AND d.asset_id = v_operation.entity_id
        ) x
      ), '[]'::jsonb)
    );
  ELSIF v_operation.entity_type = 'task' THEN
    RETURN jsonb_build_object(
      'status', 'completed', 'operation_id', v_operation.operation_id,
      'entity_type', v_operation.entity_type, 'entity_id', v_operation.entity_id,
      'charged', v_operation.charged_amount,
      'balance', COALESCE(v_current_balance, 0),
      'plan', (SELECT to_jsonb(p) FROM public.maintenance_plans p
               WHERE p.user_id = v_caller_id AND p.id = v_operation.entity_id),
      'metadata', (SELECT to_jsonb(m) FROM public.maintenance_plan_metadata m
                   WHERE m.user_id = v_caller_id AND m.plan_id = v_operation.entity_id)
    );
  END IF;
  RETURN jsonb_build_object(
    'status', 'completed', 'operation_id', v_operation.operation_id,
    'entity_type', v_operation.entity_type, 'entity_id', v_operation.entity_id,
    'charged', v_operation.charged_amount,
    'balance', COALESCE(v_current_balance, 0)
  );
END;
$$;

ALTER FUNCTION owntend_monetization_private.get_charged_operation_status(uuid, text)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_monetization_private.get_charged_operation_status(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.get_charged_operation_status(uuid, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_charged_operation_status(
  p_operation_id uuid,
  p_request_hash text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.get_charged_operation_status(
    p_operation_id,
    p_request_hash
  );
END;
$$;
ALTER FUNCTION public.get_charged_operation_status(uuid, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_charged_operation_status(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_charged_operation_status(uuid, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION owntend_monetization_private.quote_maintenance_plan_move_impl(
  p_plan_id text,
  p_target_asset_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  v_plan public.maintenance_plans%ROWTYPE;
  v_target public.assets%ROWTYPE;
  v_paid smallint;
  v_required smallint;
  v_balance integer;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  SELECT * INTO v_plan FROM public.maintenance_plans
  WHERE user_id = caller_id AND id = p_plan_id;
  SELECT * INTO v_target FROM public.assets
  WHERE user_id = caller_id AND id = p_target_asset_id AND archived_at IS NULL;
  IF v_plan.id IS NULL OR v_target.id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'TARGET_NOT_FOUND';
  END IF;
  SELECT paid_cost INTO v_paid
  FROM owntend_monetization_private.maintenance_plan_entitlements
  WHERE user_id = caller_id AND plan_id = p_plan_id;
  v_paid := COALESCE(v_paid, 0);
  v_required := owntend_monetization_private.required_task_cost_for_asset_type(v_target.asset_type);
  SELECT balance INTO v_balance FROM public.point_wallets WHERE user_id = caller_id;
  RETURN jsonb_build_object(
    'plan_id', p_plan_id, 'target_asset_id', p_target_asset_id,
    'plan_revision', v_plan.revision, 'paid_cost', v_paid,
    'required_cost', v_required, 'charge', GREATEST(0, v_required - v_paid),
    'balance', COALESCE(v_balance, 0)
  );
END;
$$;

ALTER FUNCTION owntend_monetization_private.quote_maintenance_plan_move_impl(text, text)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_monetization_private.quote_maintenance_plan_move_impl(text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.quote_maintenance_plan_move_impl(text, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.quote_maintenance_plan_move(
  p_plan_id text,
  p_target_asset_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.quote_maintenance_plan_move_impl(
    p_plan_id, p_target_asset_id
  );
END;
$$;

ALTER FUNCTION public.quote_maintenance_plan_move(text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.quote_maintenance_plan_move(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.quote_maintenance_plan_move(text, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION owntend_monetization_private.move_maintenance_plan_with_point_delta_impl(
  p_operation jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  operation_uuid uuid;
  v_client_request_hash text;
  v_request_hash text;
  v_plan_id text;
  v_target_asset_id text;
  v_expected_revision bigint;
  v_max_charge integer;
  v_plan public.maintenance_plans%ROWTYPE;
  v_target public.assets%ROWTYPE;
  v_entitlement owntend_monetization_private.maintenance_plan_entitlements%ROWTYPE;
  v_existing owntend_monetization_private.plan_economy_operations%ROWTYPE;
  v_required smallint;
  v_charge integer;
  v_balance integer;
  v_next_balance integer;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_operation IS NULL OR jsonb_typeof(p_operation) <> 'object'
     OR pg_column_size(p_operation) > 32768 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_MOVE_OPERATION';
  END IF;
  BEGIN
    operation_uuid := (p_operation->>'operation_id')::uuid;
    v_expected_revision := (p_operation->>'expected_plan_revision')::bigint;
    v_max_charge := (p_operation->>'max_charge')::integer;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_MOVE_OPERATION';
  END;
  v_client_request_hash := lower(NULLIF(btrim(p_operation->>'request_hash'), ''));
  v_plan_id := NULLIF(btrim(p_operation->>'plan_id'), '');
  v_target_asset_id := NULLIF(btrim(p_operation->>'target_asset_id'), '');
  IF v_client_request_hash IS NULL OR v_client_request_hash !~ '^[0-9a-f]{64}$'
     OR v_plan_id IS NULL OR v_target_asset_id IS NULL
     OR v_expected_revision < 1 OR v_max_charge NOT BETWEEN 0 AND 1 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_MOVE_OPERATION';
  END IF;
  v_request_hash := encode(extensions.digest(p_operation::text::bytea, 'sha256'), 'hex');
  -- Serialize all plan-economy commits for one account before taking row
  -- locks. This prevents a same-asset move and type change from acquiring the
  -- plan and asset rows in opposite order while preserving cross-user
  -- concurrency.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text || ':plan_economy', 0)
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text || ':plan_move:' || operation_uuid::text, 0)
  );

  SELECT * INTO v_existing
  FROM owntend_monetization_private.plan_economy_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    IF v_existing.user_id <> caller_id OR v_existing.operation_kind <> 'plan_move'
       OR v_existing.subject_id <> v_plan_id
       OR v_existing.request_hash <> v_request_hash
       OR v_existing.client_request_hash <> v_client_request_hash THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
    END IF;
    SELECT * INTO v_plan FROM public.maintenance_plans
    WHERE user_id = caller_id AND id = v_plan_id;
    SELECT balance INTO v_balance FROM public.point_wallets WHERE user_id = caller_id;
    RETURN jsonb_build_object(
      'status', 'applied', 'plan_id', v_plan_id,
      'target_asset_id', v_plan.asset_id, 'balance', COALESCE(v_balance, 0),
      'charged', v_existing.charged_amount, 'already_processed', true,
      'plan', to_jsonb(v_plan)
    );
  END IF;

  SELECT * INTO v_plan FROM public.maintenance_plans
  WHERE user_id = caller_id AND id = v_plan_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'PLAN_NOT_FOUND';
  END IF;
  IF v_plan.revision IS DISTINCT FROM v_expected_revision THEN
    RETURN jsonb_build_object(
      'status', 'conflict', 'conflict_reason', 'stale_plan_revision',
      'current_plan_revision', v_plan.revision, 'charged', 0,
      'already_processed', false, 'plan', to_jsonb(v_plan)
    );
  END IF;

  INSERT INTO owntend_monetization_private.maintenance_plan_entitlements (
    user_id, plan_id, paid_cost, origin
  ) VALUES (caller_id, v_plan_id, 0, 'legacy_unverified')
  ON CONFLICT (user_id, plan_id) DO NOTHING;
  SELECT * INTO v_entitlement
  FROM owntend_monetization_private.maintenance_plan_entitlements
  WHERE user_id = caller_id AND plan_id = v_plan_id
  FOR UPDATE;
  SELECT * INTO v_target FROM public.assets
  WHERE user_id = caller_id AND id = v_target_asset_id AND archived_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'TARGET_ASSET_NOT_FOUND';
  END IF;
  v_required := owntend_monetization_private.required_task_cost_for_asset_type(v_target.asset_type);
  v_charge := GREATEST(0, v_required - v_entitlement.paid_cost);
  IF v_charge > v_max_charge THEN
    RETURN jsonb_build_object(
      'status', 'charge_changed', 'charge', v_charge,
      'paid_cost', v_entitlement.paid_cost, 'required_cost', v_required,
      'already_processed', false
    );
  END IF;
  SELECT balance INTO v_balance FROM public.point_wallets
  WHERE user_id = caller_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = 'P0001', message = 'WALLET_NOT_FOUND';
  END IF;
  IF v_balance < v_charge THEN
    RETURN jsonb_build_object(
      'status', 'insufficient_points', 'balance', v_balance,
      'charged', 0, 'required_charge', v_charge, 'already_processed', false
    );
  END IF;
  v_next_balance := v_balance - v_charge;

  INSERT INTO owntend_monetization_private.plan_economy_operations (
    operation_id, user_id, operation_kind, subject_id, request_hash,
    client_request_hash, charged_amount
  ) VALUES (
    operation_uuid, caller_id, 'plan_move', v_plan_id, v_request_hash,
    v_client_request_hash, v_charge
  );
  IF v_charge > 0 THEN
    UPDATE public.point_wallets
    SET balance = v_next_balance, updated_at = clock_timestamp()
    WHERE user_id = caller_id;
    INSERT INTO public.point_transactions (
      user_id, amount, balance_before, balance_after, transaction_type,
      reference_id, idempotency_key, metadata
    ) VALUES (
      caller_id, -v_charge, v_balance, v_next_balance,
      'task_entitlement_upgrade', v_plan_id,
      'plan-move:' || operation_uuid::text,
      jsonb_build_object('target_asset_id', v_target_asset_id,
                         'operation_kind', 'plan_move')
    );
    UPDATE owntend_monetization_private.maintenance_plan_entitlements
    SET paid_cost = GREATEST(paid_cost, v_required), updated_at = clock_timestamp()
    WHERE user_id = caller_id AND plan_id = v_plan_id;
  END IF;
  UPDATE public.maintenance_plans
  SET asset_id = v_target_asset_id
  WHERE user_id = caller_id AND id = v_plan_id
  RETURNING * INTO v_plan;

  RETURN jsonb_build_object(
    'status', 'applied', 'plan_id', v_plan_id,
    'target_asset_id', v_target_asset_id, 'balance', v_next_balance,
    'charged', v_charge, 'already_processed', false, 'plan', to_jsonb(v_plan)
  );
END;
$$;

ALTER FUNCTION owntend_monetization_private.move_maintenance_plan_with_point_delta_impl(jsonb)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_monetization_private.move_maintenance_plan_with_point_delta_impl(jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.move_maintenance_plan_with_point_delta_impl(jsonb)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.move_maintenance_plan_with_point_delta(
  p_operation jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.move_maintenance_plan_with_point_delta_impl(p_operation);
END;
$$;

ALTER FUNCTION public.move_maintenance_plan_with_point_delta(jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.move_maintenance_plan_with_point_delta(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.move_maintenance_plan_with_point_delta(jsonb)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION owntend_monetization_private.quote_asset_type_change_impl(
  p_asset_id text,
  p_target_type text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  v_asset public.assets%ROWTYPE;
  v_required smallint;
  v_charge integer;
  v_balance integer;
  v_plan_count integer;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_target_type NOT IN ('device', 'pet', 'plant', 'safety', 'general') THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_ASSET_TYPE';
  END IF;
  SELECT * INTO v_asset FROM public.assets
  WHERE user_id = caller_id AND id = p_asset_id AND archived_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'ASSET_NOT_FOUND';
  END IF;
  v_required := owntend_monetization_private.required_task_cost_for_asset_type(p_target_type);
  SELECT count(*)::integer,
         COALESCE(sum(GREATEST(0, v_required - COALESCE(e.paid_cost, 0))), 0)::integer
  INTO v_plan_count, v_charge
  FROM public.maintenance_plans p
  LEFT JOIN owntend_monetization_private.maintenance_plan_entitlements e
    ON e.user_id = p.user_id AND e.plan_id = p.id
  WHERE p.user_id = caller_id AND p.asset_id = p_asset_id;
  SELECT balance INTO v_balance FROM public.point_wallets WHERE user_id = caller_id;
  RETURN jsonb_build_object(
    'asset_id', p_asset_id, 'target_type', p_target_type,
    'asset_revision', v_asset.revision, 'plan_count', v_plan_count,
    'required_cost_per_plan', v_required, 'charge', v_charge,
    'balance', COALESCE(v_balance, 0)
  );
END;
$$;

ALTER FUNCTION owntend_monetization_private.quote_asset_type_change_impl(text, text)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_monetization_private.quote_asset_type_change_impl(text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.quote_asset_type_change_impl(text, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.quote_asset_type_change(
  p_asset_id text,
  p_target_type text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.quote_asset_type_change_impl(p_asset_id, p_target_type);
END;
$$;

ALTER FUNCTION public.quote_asset_type_change(text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.quote_asset_type_change(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.quote_asset_type_change(text, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION owntend_monetization_private.change_asset_type_with_point_delta_impl(
  p_operation jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  operation_uuid uuid;
  v_client_request_hash text;
  v_request_hash text;
  v_asset_id text;
  v_target_type text;
  v_details jsonb;
  v_expected_revision bigint;
  v_max_charge integer;
  v_asset public.assets%ROWTYPE;
  v_existing owntend_monetization_private.plan_economy_operations%ROWTYPE;
  v_required smallint;
  v_charge integer;
  v_balance integer;
  v_next_balance integer;
  v_plan_count integer;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_operation IS NULL OR jsonb_typeof(p_operation) <> 'object'
     OR pg_column_size(p_operation) > 65536 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TYPE_CHANGE_OPERATION';
  END IF;
  BEGIN
    operation_uuid := (p_operation->>'operation_id')::uuid;
    v_expected_revision := (p_operation->>'expected_asset_revision')::bigint;
    v_max_charge := (p_operation->>'max_charge')::integer;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TYPE_CHANGE_OPERATION';
  END;
  v_client_request_hash := lower(NULLIF(btrim(p_operation->>'request_hash'), ''));
  v_asset_id := NULLIF(btrim(p_operation->>'asset_id'), '');
  v_target_type := NULLIF(btrim(p_operation->>'target_type'), '');
  v_details := COALESCE(p_operation->'details', '{}'::jsonb);
  IF v_client_request_hash IS NULL OR v_client_request_hash !~ '^[0-9a-f]{64}$'
     OR v_asset_id IS NULL
     OR v_target_type NOT IN ('device', 'pet', 'plant', 'safety', 'general')
     OR jsonb_typeof(v_details) <> 'object'
     OR v_expected_revision < 1 OR v_max_charge NOT BETWEEN 0 AND 1000 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TYPE_CHANGE_OPERATION';
  END IF;
  v_request_hash := encode(extensions.digest(p_operation::text::bytea, 'sha256'), 'hex');
  -- Match the plan-move lock before taking asset/plan/wallet row locks so the
  -- two authoritative economy paths cannot deadlock within one account.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text || ':plan_economy', 0)
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text || ':asset_type:' || operation_uuid::text, 0)
  );

  SELECT * INTO v_existing
  FROM owntend_monetization_private.plan_economy_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    IF v_existing.user_id <> caller_id
       OR v_existing.operation_kind <> 'asset_type_change'
       OR v_existing.subject_id <> v_asset_id
       OR v_existing.request_hash <> v_request_hash
       OR v_existing.client_request_hash <> v_client_request_hash THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
    END IF;
    SELECT * INTO v_asset FROM public.assets
    WHERE user_id = caller_id AND id = v_asset_id;
    SELECT balance INTO v_balance FROM public.point_wallets WHERE user_id = caller_id;
    RETURN jsonb_build_object(
      'status', 'applied', 'asset_id', v_asset_id,
      'target_type', v_asset.asset_type, 'balance', COALESCE(v_balance, 0),
      'charged', v_existing.charged_amount, 'already_processed', true,
      'asset', to_jsonb(v_asset)
    );
  END IF;

  SELECT * INTO v_asset FROM public.assets
  WHERE user_id = caller_id AND id = v_asset_id AND archived_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'ASSET_NOT_FOUND';
  END IF;
  IF v_asset.revision IS DISTINCT FROM v_expected_revision THEN
    RETURN jsonb_build_object(
      'status', 'conflict', 'conflict_reason', 'stale_asset_revision',
      'current_asset_revision', v_asset.revision, 'charged', 0,
      'already_processed', false, 'asset', to_jsonb(v_asset)
    );
  END IF;

  -- Lock every attached plan first, in a stable order, then materialize and
  -- lock its entitlement. Archived plans are intentionally included.
  PERFORM 1 FROM public.maintenance_plans
  WHERE user_id = caller_id AND asset_id = v_asset_id
  ORDER BY id
  FOR UPDATE;
  INSERT INTO owntend_monetization_private.maintenance_plan_entitlements (
    user_id, plan_id, paid_cost, origin
  )
  SELECT caller_id, p.id, 0, 'legacy_unverified'
  FROM public.maintenance_plans p
  WHERE p.user_id = caller_id AND p.asset_id = v_asset_id
  ON CONFLICT (user_id, plan_id) DO NOTHING;
  PERFORM 1 FROM owntend_monetization_private.maintenance_plan_entitlements e
  JOIN public.maintenance_plans p
    ON p.user_id = e.user_id AND p.id = e.plan_id
  WHERE p.user_id = caller_id AND p.asset_id = v_asset_id
  ORDER BY e.plan_id
  FOR UPDATE OF e;

  v_required := owntend_monetization_private.required_task_cost_for_asset_type(v_target_type);
  SELECT count(*)::integer,
         COALESCE(sum(GREATEST(0, v_required - e.paid_cost)), 0)::integer
  INTO v_plan_count, v_charge
  FROM public.maintenance_plans p
  JOIN owntend_monetization_private.maintenance_plan_entitlements e
    ON e.user_id = p.user_id AND e.plan_id = p.id
  WHERE p.user_id = caller_id AND p.asset_id = v_asset_id;
  IF v_charge > 1000 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'TYPE_CHANGE_CHARGE_LIMIT_EXCEEDED';
  END IF;
  IF v_charge > v_max_charge THEN
    RETURN jsonb_build_object(
      'status', 'charge_changed', 'charge', v_charge,
      'plan_count', v_plan_count, 'required_cost_per_plan', v_required,
      'already_processed', false
    );
  END IF;

  SELECT balance INTO v_balance FROM public.point_wallets
  WHERE user_id = caller_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = 'P0001', message = 'WALLET_NOT_FOUND';
  END IF;
  IF v_balance < v_charge THEN
    RETURN jsonb_build_object(
      'status', 'insufficient_points', 'balance', v_balance,
      'charged', 0, 'required_charge', v_charge,
      'already_processed', false
    );
  END IF;
  v_next_balance := v_balance - v_charge;

  INSERT INTO owntend_monetization_private.plan_economy_operations (
    operation_id, user_id, operation_kind, subject_id, request_hash,
    client_request_hash, charged_amount
  ) VALUES (
    operation_uuid, caller_id, 'asset_type_change', v_asset_id,
    v_request_hash, v_client_request_hash, v_charge
  );
  IF v_charge > 0 THEN
    UPDATE public.point_wallets
    SET balance = v_next_balance, updated_at = clock_timestamp()
    WHERE user_id = caller_id;
    INSERT INTO public.point_transactions (
      user_id, amount, balance_before, balance_after, transaction_type,
      reference_id, idempotency_key, metadata
    ) VALUES (
      caller_id, -v_charge, v_balance, v_next_balance,
      'task_entitlement_upgrade', v_asset_id,
      'asset-type:' || operation_uuid::text,
      jsonb_build_object('target_type', v_target_type,
                         'operation_kind', 'asset_type_change',
                         'plan_count', v_plan_count)
    );
    UPDATE owntend_monetization_private.maintenance_plan_entitlements e
    SET paid_cost = GREATEST(e.paid_cost, v_required), updated_at = clock_timestamp()
    FROM public.maintenance_plans p
    WHERE p.user_id = caller_id AND p.asset_id = v_asset_id
      AND e.user_id = p.user_id AND e.plan_id = p.id;
  END IF;

  DELETE FROM public.device_details WHERE user_id = caller_id AND asset_id = v_asset_id;
  DELETE FROM public.pet_details WHERE user_id = caller_id AND asset_id = v_asset_id;
  DELETE FROM public.plant_details WHERE user_id = caller_id AND asset_id = v_asset_id;
  DELETE FROM public.safety_details WHERE user_id = caller_id AND asset_id = v_asset_id;

  IF v_target_type = 'device' THEN
    INSERT INTO public.device_details (
      user_id, asset_id, brand, model, serial_number, power_source,
      warranty_until, manual_url, consumable, revision, created_at, updated_at
    ) VALUES (
      caller_id, v_asset_id,
      NULLIF(btrim(v_details->>'brand'), ''), NULLIF(btrim(v_details->>'model'), ''),
      NULLIF(btrim(v_details->>'serial_number'), ''),
      NULLIF(btrim(v_details->>'power_source'), ''),
      NULLIF(v_details->>'warranty_until', '')::date,
      NULLIF(btrim(v_details->>'manual_url'), ''),
      NULLIF(btrim(v_details->>'consumable'), ''), 1,
      clock_timestamp(), clock_timestamp()
    );
  ELSIF v_target_type = 'pet' THEN
    INSERT INTO public.pet_details (
      user_id, asset_id, species, breed, birth_date, microchip_id,
      vet_name, vet_phone, feeding_notes, medical_notes,
      revision, created_at, updated_at
    ) VALUES (
      caller_id, v_asset_id,
      NULLIF(btrim(v_details->>'species'), ''), NULLIF(btrim(v_details->>'breed'), ''),
      NULLIF(v_details->>'birth_date', '')::date,
      NULLIF(btrim(v_details->>'microchip_id'), ''),
      NULLIF(btrim(v_details->>'vet_name'), ''), NULLIF(btrim(v_details->>'vet_phone'), ''),
      NULLIF(btrim(v_details->>'feeding_notes'), ''),
      NULLIF(btrim(v_details->>'medical_notes'), ''),
      1, clock_timestamp(), clock_timestamp()
    );
  ELSIF v_target_type = 'plant' THEN
    INSERT INTO public.plant_details (
      user_id, asset_id, species, sunlight, watering_interval_days,
      pot_size, last_repotted_at, toxicity_notes,
      revision, created_at, updated_at
    ) VALUES (
      caller_id, v_asset_id,
      NULLIF(btrim(v_details->>'species'), ''), NULLIF(btrim(v_details->>'sunlight'), ''),
      NULLIF(v_details->>'watering_interval_days', '')::integer,
      NULLIF(btrim(v_details->>'pot_size'), ''),
      NULLIF(v_details->>'last_repotted_at', '')::timestamptz,
      NULLIF(btrim(v_details->>'toxicity_notes'), ''),
      1, clock_timestamp(), clock_timestamp()
    );
  ELSIF v_target_type = 'safety' THEN
    INSERT INTO public.safety_details (
      user_id, asset_id, safety_type, installed_at, expires_at,
      battery_type, test_interval_days, revision, created_at, updated_at
    ) VALUES (
      caller_id, v_asset_id,
      NULLIF(btrim(v_details->>'safety_type'), ''),
      NULLIF(v_details->>'installed_at', '')::timestamptz,
      NULLIF(v_details->>'expires_at', '')::timestamptz,
      NULLIF(btrim(v_details->>'battery_type'), ''),
      NULLIF(v_details->>'test_interval_days', '')::integer,
      1, clock_timestamp(), clock_timestamp()
    );
  ELSIF v_details <> '{}'::jsonb THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_GENERAL_DETAILS';
  END IF;

  UPDATE public.assets
  SET asset_type = v_target_type
  WHERE user_id = caller_id AND id = v_asset_id
  RETURNING * INTO v_asset;
  RETURN jsonb_build_object(
    'status', 'applied', 'asset_id', v_asset_id, 'target_type', v_target_type,
    'balance', v_next_balance, 'charged', v_charge,
    'already_processed', false, 'asset', to_jsonb(v_asset)
  );
EXCEPTION
  WHEN check_violation OR not_null_violation OR invalid_text_representation THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TYPE_CHANGE_OPERATION';
END;
$$;

ALTER FUNCTION owntend_monetization_private.change_asset_type_with_point_delta_impl(jsonb)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_monetization_private.change_asset_type_with_point_delta_impl(jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.change_asset_type_with_point_delta_impl(jsonb)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.change_asset_type_with_point_delta(
  p_operation jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.change_asset_type_with_point_delta_impl(p_operation);
END;
$$;

ALTER FUNCTION public.change_asset_type_with_point_delta(jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.change_asset_type_with_point_delta(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.change_asset_type_with_point_delta(jsonb)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION owntend_private.restore_maintenance_history_impl(
  p_operation jsonb,
  p_device_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  operation_uuid uuid;
  v_client_request_hash text;
  v_request_hash text;
  v_plan_id text;
  v_expected_revision bigint;
  v_snapshot jsonb;
  v_records jsonb;
  v_plan public.maintenance_plans%ROWTYPE;
  v_existing_op owntend_private.maintenance_history_restore_operations%ROWTYPE;
  v_record_json jsonb;
  v_existing_record public.maintenance_records%ROWTYPE;
  v_record_id text;
  v_record_operation_id text;
  v_due_raw timestamptz;
  v_completed_raw timestamptz;
  v_created_raw timestamptz;
  v_archived_raw timestamptz;
  v_next_due_raw timestamptz;
  v_revision bigint;
  v_match_count integer;
  v_inserted integer := 0;
  v_existing integer := 0;
  v_conflict boolean := false;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF NULLIF(btrim(COALESCE(p_device_id, '')), '') IS NULL
     OR char_length(p_device_id) > 200
     OR p_operation IS NULL OR jsonb_typeof(p_operation) <> 'object'
     OR pg_column_size(p_operation) > 262144
     OR p_operation->>'version' IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
  END IF;
  BEGIN
    operation_uuid := (p_operation->>'operation_id')::uuid;
    v_expected_revision := (p_operation->>'expected_plan_revision')::bigint;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
  END;
  v_client_request_hash := lower(NULLIF(btrim(p_operation->>'request_hash'), ''));
  v_plan_id := NULLIF(btrim(p_operation->>'plan_id'), '');
  v_snapshot := p_operation->'plan_snapshot';
  v_records := p_operation->'records';
  IF v_client_request_hash IS NULL OR v_client_request_hash !~ '^[0-9a-f]{64}$'
     OR v_plan_id IS NULL OR v_expected_revision < 1
     OR jsonb_typeof(v_snapshot) <> 'object'
     OR jsonb_typeof(v_records) <> 'array'
     OR jsonb_array_length(v_records) > 100 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_records) r
    WHERE jsonb_typeof(r) <> 'object'
  ) OR (
    SELECT count(*) FROM jsonb_array_elements(v_records)
  ) <> (
    SELECT count(DISTINCT r->>'id') FROM jsonb_array_elements(v_records) r
  ) OR (
    SELECT count(*) FROM jsonb_array_elements(v_records)
  ) <> (
    SELECT count(DISTINCT r->>'operation_id') FROM jsonb_array_elements(v_records) r
  ) THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
  END IF;
  v_request_hash := encode(extensions.digest(p_operation::text::bytea, 'sha256'), 'hex');

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text || ':history_restore:' || operation_uuid::text, 0)
  );
  SELECT * INTO v_existing_op
  FROM owntend_private.maintenance_history_restore_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    IF v_existing_op.user_id <> caller_id OR v_existing_op.plan_id <> v_plan_id
       OR v_existing_op.request_hash <> v_request_hash
       OR v_existing_op.client_request_hash <> v_client_request_hash THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
    END IF;
    SELECT * INTO v_plan FROM public.maintenance_plans
    WHERE user_id = caller_id AND id = v_plan_id;
    RETURN jsonb_build_object(
      'status', v_existing_op.result_status,
      'conflict_reason', v_existing_op.conflict_reason,
      'inserted_count', v_existing_op.inserted_count,
      'existing_count', v_existing_op.existing_count,
      'already_processed', true, 'plan', to_jsonb(v_plan)
    );
  END IF;

  SELECT * INTO v_plan FROM public.maintenance_plans
  WHERE user_id = caller_id AND id = v_plan_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'RESTORE_PLAN_NOT_FOUND';
  END IF;
  BEGIN
    v_next_due_raw := (v_snapshot->>'next_due_date')::timestamptz;
    v_archived_raw := CASE
      WHEN v_snapshot->'archived_at' IS NULL OR v_snapshot->'archived_at' = 'null'::jsonb
        THEN NULL
      ELSE (v_snapshot->>'archived_at')::timestamptz
    END;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
  END;
  IF v_next_due_raw IS DISTINCT FROM date_trunc('second', v_next_due_raw)
     OR (v_archived_raw IS NOT NULL
         AND v_archived_raw IS DISTINCT FROM date_trunc('second', v_archived_raw)) THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
  END IF;

  IF v_plan.revision IS DISTINCT FROM v_expected_revision
     OR v_plan.asset_id IS DISTINCT FROM NULLIF(btrim(v_snapshot->>'asset_id'), '')
     OR v_plan.recurrence_interval IS DISTINCT FROM
        NULLIF(v_snapshot->>'recurrence_interval', '')::integer
     OR v_plan.recurrence_unit IS DISTINCT FROM NULLIF(btrim(v_snapshot->>'recurrence_unit'), '')
     OR date_trunc('second', v_plan.next_due_date) IS DISTINCT FROM v_next_due_raw
     OR v_plan.is_enabled IS DISTINCT FROM NULLIF(v_snapshot->>'is_enabled', '')::boolean
     OR date_trunc('second', v_plan.archived_at) IS DISTINCT FROM v_archived_raw THEN
    INSERT INTO owntend_private.maintenance_history_restore_operations (
      operation_id, user_id, plan_id, request_hash, client_request_hash,
      result_status, conflict_reason
    ) VALUES (
      operation_uuid, caller_id, v_plan_id, v_request_hash, v_client_request_hash,
      'conflict', 'plan_snapshot_conflict'
    );
    RETURN jsonb_build_object(
      'status', 'conflict', 'conflict_reason', 'plan_snapshot_conflict',
      'inserted_count', 0, 'existing_count', 0,
      'already_processed', false, 'plan', to_jsonb(v_plan)
    );
  END IF;

  -- Validate the complete batch and detect divergence before inserting any row.
  FOR v_record_json IN SELECT value FROM jsonb_array_elements(v_records)
  LOOP
    v_record_id := NULLIF(btrim(v_record_json->>'id'), '');
    v_record_operation_id := NULLIF(btrim(v_record_json->>'operation_id'), '');
    BEGIN
      v_due_raw := (v_record_json->>'due_date')::timestamptz;
      v_completed_raw := (v_record_json->>'completed_at')::timestamptz;
      v_created_raw := (v_record_json->>'created_at')::timestamptz;
      v_revision := (v_record_json->>'revision')::bigint;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
    END;
    IF v_record_id IS NULL OR char_length(v_record_id) > 200
       OR v_record_operation_id IS NULL OR char_length(v_record_operation_id) > 200
       OR NULLIF(btrim(v_record_json->>'plan_id'), '') IS DISTINCT FROM v_plan_id
       OR v_revision < 1
       OR char_length(COALESCE(v_record_json->>'notes', '')) > 4000
       OR v_due_raw IS DISTINCT FROM date_trunc('second', v_due_raw)
       OR v_completed_raw IS DISTINCT FROM date_trunc('second', v_completed_raw)
       OR v_created_raw IS DISTINCT FROM date_trunc('second', v_created_raw) THEN
      RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
    END IF;

    SELECT count(*)::integer INTO v_match_count
    FROM public.maintenance_records
    WHERE user_id = caller_id
      AND (id = v_record_id OR operation_id = v_record_operation_id);
    IF v_match_count = 0 THEN
      CONTINUE;
    END IF;
    IF v_match_count <> 1 THEN
      v_conflict := true;
      EXIT;
    END IF;
    SELECT * INTO v_existing_record
    FROM public.maintenance_records
    WHERE user_id = caller_id
      AND (id = v_record_id OR operation_id = v_record_operation_id)
    LIMIT 1;
    IF v_existing_record.id IS DISTINCT FROM v_record_id
       OR v_existing_record.operation_id IS DISTINCT FROM v_record_operation_id
       OR v_existing_record.plan_id IS DISTINCT FROM v_plan_id
       OR date_trunc('second', v_existing_record.due_date) IS DISTINCT FROM v_due_raw
       OR date_trunc('second', v_existing_record.completed_at) IS DISTINCT FROM v_completed_raw
       OR COALESCE(v_existing_record.notes, '') IS DISTINCT FROM
          COALESCE(NULLIF(btrim(v_record_json->>'notes'), ''), '')
       OR date_trunc('second', v_existing_record.created_at) IS DISTINCT FROM v_created_raw
       OR v_existing_record.revision IS DISTINCT FROM v_revision THEN
      v_conflict := true;
      EXIT;
    END IF;
  END LOOP;

  IF v_conflict THEN
    INSERT INTO owntend_private.maintenance_history_restore_operations (
      operation_id, user_id, plan_id, request_hash, client_request_hash,
      result_status, conflict_reason
    ) VALUES (
      operation_uuid, caller_id, v_plan_id, v_request_hash, v_client_request_hash,
      'conflict', 'history_record_conflict'
    );
    RETURN jsonb_build_object(
      'status', 'conflict', 'conflict_reason', 'history_record_conflict',
      'inserted_count', 0, 'existing_count', 0,
      'already_processed', false, 'plan', to_jsonb(v_plan)
    );
  END IF;

  FOR v_record_json IN SELECT value FROM jsonb_array_elements(v_records)
  LOOP
    v_record_id := btrim(v_record_json->>'id');
    v_record_operation_id := btrim(v_record_json->>'operation_id');
    IF EXISTS (
      SELECT 1 FROM public.maintenance_records
      WHERE user_id = caller_id AND id = v_record_id
    ) THEN
      v_existing := v_existing + 1;
    ELSE
      INSERT INTO public.maintenance_records (
        user_id, id, plan_id, completed_at, notes, due_date, operation_id,
        revision, created_at, updated_at
      ) VALUES (
        caller_id, v_record_id, v_plan_id,
        (v_record_json->>'completed_at')::timestamptz,
        NULLIF(btrim(v_record_json->>'notes'), ''),
        (v_record_json->>'due_date')::timestamptz,
        v_record_operation_id, (v_record_json->>'revision')::bigint,
        (v_record_json->>'created_at')::timestamptz,
        (v_record_json->>'created_at')::timestamptz
      );
      v_inserted := v_inserted + 1;
    END IF;
  END LOOP;

  INSERT INTO owntend_private.maintenance_history_restore_operations (
    operation_id, user_id, plan_id, request_hash, client_request_hash,
    result_status, conflict_reason, inserted_count, existing_count
  ) VALUES (
    operation_uuid, caller_id, v_plan_id, v_request_hash, v_client_request_hash,
    'applied', NULL, v_inserted, v_existing
  );
  RETURN jsonb_build_object(
    'status', 'applied', 'conflict_reason', NULL,
    'inserted_count', v_inserted, 'existing_count', v_existing,
    'already_processed', false, 'plan', to_jsonb(v_plan)
  );
EXCEPTION
  WHEN invalid_text_representation OR check_violation OR not_null_violation THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
END;
$$;

ALTER FUNCTION owntend_private.restore_maintenance_history_impl(jsonb, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_private.restore_maintenance_history_impl(jsonb, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_private.restore_maintenance_history_impl(jsonb, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.restore_maintenance_history(
  p_operation jsonb,
  p_device_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_private.restore_maintenance_history_impl(p_operation, p_device_id);
END;
$$;

ALTER FUNCTION public.restore_maintenance_history(jsonb, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.restore_maintenance_history(jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.restore_maintenance_history(jsonb, text)
  TO authenticated, service_role;

-- Public invoker wrappers need schema usage and EXECUTE on their private
-- implementations. The private schemas are not exposed through PostgREST.
GRANT USAGE ON SCHEMA owntend_private, owntend_monetization_private
  TO authenticated, service_role;

-- Make every new API function opt-in even on projects with legacy defaults.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;
