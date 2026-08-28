-- Version the maintenance-completion result envelope so a well-formed
-- business rejection cannot be confused with client/server schema drift.

CREATE OR REPLACE FUNCTION owntend_private.maintenance_completion_result(
  p_status text,
  p_retryable boolean,
  p_conflict_reason text DEFAULT NULL,
  p_current_plan_revision bigint DEFAULT NULL,
  p_resulting_record_id text DEFAULT NULL,
  p_resulting_next_due_date timestamptz DEFAULT NULL,
  p_plan jsonb DEFAULT NULL,
  p_record jsonb DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'contract_version', 1,
    'status', p_status,
    'retryable', p_retryable,
    'conflict_reason', p_conflict_reason,
    'current_plan_revision', p_current_plan_revision,
    'resulting_record_id', p_resulting_record_id,
    'resulting_next_due_date', p_resulting_next_due_date,
    'plan', p_plan,
    'record', p_record
  );
$$;

ALTER FUNCTION owntend_private.maintenance_completion_result(
  text, boolean, text, bigint, text, timestamptz, jsonb, jsonb
) OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_private.maintenance_completion_result(
  text, boolean, text, bigint, text, timestamptz, jsonb, jsonb
) FROM PUBLIC, anon, authenticated;

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
    RETURN owntend_private.maintenance_completion_result(
      'invalid', false, 'invalid_device_id'
    );
  END IF;
  IF jsonb_typeof(p_operation) IS DISTINCT FROM 'object'
     OR p_operation->>'version' IS DISTINCT FROM '1' THEN
    RETURN owntend_private.maintenance_completion_result(
      'invalid', false, 'invalid_payload_version'
    );
  END IF;
  plan_payload := p_operation->'plan';
  record_payload := p_operation->'record';
  IF jsonb_typeof(plan_payload) IS DISTINCT FROM 'object'
     OR jsonb_typeof(record_payload) IS DISTINCT FROM 'object' THEN
    RETURN owntend_private.maintenance_completion_result(
      'invalid', false, 'incomplete_payload'
    );
  END IF;

  operation_id_value := NULLIF(btrim(p_operation->>'operation_id'), '');
  plan_id_value := NULLIF(btrim(plan_payload->>'id'), '');
  record_id_value := NULLIF(btrim(record_payload->>'id'), '');
  record_plan_id_value := NULLIF(btrim(record_payload->>'plan_id'), '');
  IF operation_id_value IS NULL OR plan_id_value IS NULL OR record_id_value IS NULL
     OR record_plan_id_value IS NULL OR record_plan_id_value <> plan_id_value THEN
    RETURN owntend_private.maintenance_completion_result(
      'invalid', false, 'invalid_identifiers'
    );
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
    RETURN owntend_private.maintenance_completion_result(
      'invalid', false, 'invalid_values'
    );
  END;

  IF expected_next_due_date IS NULL OR record_due_date IS NULL
     OR record_completed_at IS NULL OR plan_next_due_date IS NULL
     OR plan_created_at IS NULL OR plan_recurrence_interval IS NULL
     OR plan_is_enabled IS NULL
     OR record_due_date IS DISTINCT FROM expected_next_due_date
     OR plan_next_due_date <= record_completed_at
     OR plan_recurrence_interval <= 0 OR plan_reminder_days_before < 0 THEN
    RETURN owntend_private.maintenance_completion_result(
      'invalid', false, 'invalid_completion'
    );
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
    IF current_record.plan_id <> plan_id_value THEN
      RETURN owntend_private.maintenance_completion_result(
        'conflict', false, 'operation_id_reused'
      );
    END IF;
    IF current_record.id <> record_id_value
       OR date_trunc('second', current_record.due_date) IS DISTINCT FROM record_due_date
       OR date_trunc('second', current_record.completed_at) IS DISTINCT FROM record_completed_at
       OR COALESCE(NULLIF(btrim(current_record.notes), ''), '') IS DISTINCT FROM
          COALESCE(NULLIF(btrim(record_payload->>'notes'), ''), '') THEN
      RETURN owntend_private.maintenance_completion_result(
        'conflict', false, 'operation_id_reused', current_plan.revision,
        current_record.id, current_plan.next_due_date,
        to_jsonb(current_plan), to_jsonb(current_record)
      );
    END IF;
    RETURN owntend_private.maintenance_completion_result(
      'already_applied', false, NULL, current_plan.revision,
      current_record.id, current_plan.next_due_date,
      to_jsonb(current_plan), to_jsonb(current_record)
    );
  END IF;

  SELECT * INTO current_plan
  FROM public.maintenance_plans
  WHERE user_id = request_user AND id = plan_id_value
  FOR UPDATE;
  IF FOUND THEN
    IF current_plan.archived_at IS NOT NULL OR current_plan.is_enabled IS NOT TRUE THEN
      RETURN owntend_private.maintenance_completion_result(
        'conflict', false, 'plan_inactive', current_plan.revision,
        NULL, current_plan.next_due_date, to_jsonb(current_plan), NULL
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
        RETURN owntend_private.maintenance_completion_result(
          'conflict', false, 'occurrence_completed_elsewhere', current_plan.revision,
          occurrence_record.id, current_plan.next_due_date,
          to_jsonb(current_plan), to_jsonb(occurrence_record)
        );
      END IF;
      RETURN owntend_private.maintenance_completion_result(
        'conflict', false, 'occurrence_changed', current_plan.revision,
        NULL, current_plan.next_due_date, to_jsonb(current_plan), NULL
      );
    END IF;
    IF expected_plan_revision IS NOT NULL
       AND current_plan.revision IS DISTINCT FROM expected_plan_revision THEN
      RETURN owntend_private.maintenance_completion_result(
        'conflict', true, 'stale_plan_revision', current_plan.revision,
        NULL, current_plan.next_due_date, to_jsonb(current_plan), NULL
      );
    END IF;
  ELSE
    authorized_cost :=
      owntend_monetization_private.ensure_plan_entitlement_from_task_authorization(
        request_user, plan_id_value
      );
    IF authorized_cost IS NULL THEN
      RETURN owntend_private.maintenance_completion_result(
        'invalid', false, 'task_creation_not_authorized'
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

  RETURN owntend_private.maintenance_completion_result(
    'applied', false, NULL, current_plan.revision,
    current_record.id, current_plan.next_due_date,
    to_jsonb(current_plan), to_jsonb(current_record)
  );
END;
$$;

ALTER FUNCTION owntend_private.complete_maintenance_task_impl(jsonb, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_private.complete_maintenance_task_impl(jsonb, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_private.complete_maintenance_task_impl(jsonb, text)
  TO authenticated, service_role;
