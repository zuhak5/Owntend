-- Forward fixes for pre-production maintenance completion integrity.
BEGIN;

ALTER TABLE public.maintenance_plans
  DROP CONSTRAINT IF EXISTS maintenance_plans_interval_unit_check;
ALTER TABLE public.maintenance_plans
  ADD CONSTRAINT maintenance_plans_interval_unit_check
  CHECK (interval_unit IN ('hours', 'days', 'weeks', 'months', 'years'));

CREATE OR REPLACE FUNCTION public.complete_maintenance_task(
  p_operation JSONB,
  p_device_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  request_user UUID := (SELECT auth.uid());
  plan_payload JSONB;
  record_payload JSONB;

  operation_id_value TEXT;
  plan_id_value TEXT;
  record_id_value TEXT;
  record_plan_id_value TEXT;

  expected_plan_revision BIGINT;
  expected_next_due_date TIMESTAMPTZ;
  plan_next_due_date TIMESTAMPTZ;
  record_due_date TIMESTAMPTZ;
  record_completed_at TIMESTAMPTZ;

  plan_created_at TIMESTAMPTZ;
  plan_updated_at TIMESTAMPTZ;
  plan_archived_at TIMESTAMPTZ;
  plan_recurrence_interval INTEGER;
  plan_reminder_days_before INTEGER;
  plan_is_enabled BOOLEAN;

  current_plan public.maintenance_plans%ROWTYPE;
  current_record public.maintenance_records%ROWTYPE;
  occurrence_record public.maintenance_records%ROWTYPE;
  plan_was_created BOOLEAN := false;
BEGIN
  IF request_user IS NULL THEN
    RAISE EXCEPTION 'Authentication is required'
      USING errcode = '42501';
  END IF;

  IF COALESCE(LENGTH(TRIM(p_device_id)), 0) = 0
      OR LENGTH(p_device_id) > 200 THEN
    RETURN jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'invalid_device_id'
    );
  END IF;

  IF jsonb_typeof(p_operation) IS DISTINCT FROM 'object'
      OR (p_operation ->> 'version' IS DISTINCT FROM '1' AND p_operation ->> 'version' IS DISTINCT FROM '2') THEN
    RETURN jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'invalid_payload_version'
    );
  END IF;

  plan_payload := p_operation -> 'plan';
  record_payload := p_operation -> 'record';
  IF jsonb_typeof(plan_payload) IS DISTINCT FROM 'object'
      OR jsonb_typeof(record_payload) IS DISTINCT FROM 'object' THEN
    RETURN jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'incomplete_payload'
    );
  END IF;

  operation_id_value := NULLIF(TRIM(p_operation ->> 'operation_id'), '');
  plan_id_value := NULLIF(TRIM(plan_payload ->> 'id'), '');
  record_id_value := NULLIF(TRIM(record_payload ->> 'id'), '');
  record_plan_id_value := NULLIF(TRIM(record_payload ->> 'plan_id'), '');

  IF operation_id_value IS NULL
      OR plan_id_value IS NULL
      OR record_id_value IS NULL
      OR record_plan_id_value IS NULL
      OR record_plan_id_value <> plan_id_value THEN
    RETURN jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'invalid_identifiers'
    );
  END IF;

  BEGIN
    expected_plan_revision :=
      NULLIF(p_operation ->> 'expected_plan_revision', '')::bigint;
    expected_next_due_date := date_trunc(
      'second',
      NULLIF(p_operation ->> 'expected_next_due_date', '')::timestamptz
    );
    plan_next_due_date := date_trunc(
      'second',
      NULLIF(plan_payload ->> 'next_due_date', '')::timestamptz
    );
    record_due_date := date_trunc(
      'second',
      NULLIF(record_payload ->> 'due_date', '')::timestamptz
    );
    record_completed_at := date_trunc(
      'second',
      NULLIF(record_payload ->> 'completed_at', '')::timestamptz
    );
    plan_created_at := date_trunc(
      'second',
      NULLIF(plan_payload ->> 'created_at', '')::timestamptz
    );
    plan_updated_at := date_trunc(
      'second',
      COALESCE(
        NULLIF(plan_payload ->> 'updated_at', '')::timestamptz,
        clock_timestamp()
      )
    );
    plan_archived_at := CASE
      WHEN plan_payload -> 'archived_at' IS NULL
        OR plan_payload -> 'archived_at' = 'null'::jsonb
        THEN NULL
      ELSE date_trunc('second', NULLIF(plan_payload ->> 'archived_at', '')::timestamptz)
    END;
    plan_recurrence_interval := COALESCE(
      NULLIF(plan_payload ->> 'interval_count', '')::integer,
      NULLIF(plan_payload ->> 'recurrence_interval', '')::integer
    );
    plan_reminder_days_before := COALESCE(
      NULLIF(plan_payload ->> 'reminder_days_before', '')::integer,
      0
    );
    plan_is_enabled :=
      NULLIF(plan_payload ->> 'is_enabled', '')::boolean;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN jsonb_build_object(
        'status', 'invalid',
        'retryable', false,
        'conflict_reason', 'invalid_values'
      );
  END;

  IF expected_next_due_date IS NULL
      OR record_due_date IS NULL
      OR record_completed_at IS NULL
      OR plan_next_due_date IS NULL
      OR plan_created_at IS NULL
      OR plan_recurrence_interval IS NULL
      OR plan_is_enabled IS NULL
      OR record_due_date IS DISTINCT FROM expected_next_due_date
      OR plan_next_due_date <= record_completed_at
      OR plan_recurrence_interval <= 0
      OR plan_reminder_days_before < 0 THEN
    RETURN jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'invalid_completion'
    );
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      request_user::text || ':' || plan_id_value,
      0
    )
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      request_user::text || ':operation:' || operation_id_value,
      0
    )
  );

  SELECT *
  INTO current_record
  FROM public.maintenance_records
  WHERE user_id = request_user
    AND operation_id = operation_id_value;

  IF FOUND THEN
    SELECT *
    INTO current_plan
    FROM public.maintenance_plans
    WHERE user_id = request_user
      AND id = current_record.plan_id;

    IF current_record.id <> record_id_value
        OR current_record.plan_id <> plan_id_value
        OR date_trunc('second', current_record.due_date) IS DISTINCT FROM record_due_date
        OR date_trunc('second', current_record.completed_at) IS DISTINCT FROM record_completed_at
        OR COALESCE(NULLIF(TRIM(current_record.notes), ''), '') IS DISTINCT FROM COALESCE(NULLIF(TRIM(record_payload ->> 'notes'), ''), '') THEN
      RETURN jsonb_build_object(
        'status', 'conflict',
        'retryable', false,
        'conflict_reason', 'operation_id_reused',
        'current_plan_revision', current_plan.revision,
        'resulting_record_id', current_record.id,
        'resulting_next_due_date', current_plan.next_due_date,
        'plan', to_jsonb(current_plan),
        'record', to_jsonb(current_record)
      );
    END IF;

    RETURN jsonb_build_object(
      'status', 'already_applied',
      'retryable', false,
      'conflict_reason', null,
      'current_plan_revision', current_plan.revision,
      'resulting_record_id', current_record.id,
      'resulting_next_due_date', current_plan.next_due_date,
      'plan', to_jsonb(current_plan),
      'record', to_jsonb(current_record)
    );
  END IF;

  SELECT *
  INTO current_plan
  FROM public.maintenance_plans
  WHERE user_id = request_user
    AND id = plan_id_value
  FOR UPDATE;

  IF FOUND THEN
    IF current_plan.archived_at IS NOT NULL
        OR current_plan.is_enabled IS NOT TRUE THEN
      RETURN jsonb_build_object(
        'status', 'conflict',
        'retryable', false,
        'conflict_reason', 'plan_inactive',
        'current_plan_revision', current_plan.revision,
        'resulting_record_id', null,
        'resulting_next_due_date', current_plan.next_due_date,
        'plan', to_jsonb(current_plan),
        'record', null
      );
    END IF;

    IF date_trunc('second', current_plan.next_due_date) IS DISTINCT FROM expected_next_due_date THEN
      SELECT *
      INTO occurrence_record
      FROM public.maintenance_records
      WHERE user_id = request_user
        AND plan_id = plan_id_value
        AND date_trunc('second', due_date) = record_due_date
      ORDER BY completed_at DESC, id DESC LIMIT 1;

      IF FOUND THEN
        RETURN jsonb_build_object(
          'status', 'conflict',
          'retryable', false,
          'conflict_reason', 'occurrence_completed_elsewhere',
          'current_plan_revision', current_plan.revision,
          'resulting_record_id', occurrence_record.id,
          'resulting_next_due_date', current_plan.next_due_date,
          'plan', to_jsonb(current_plan),
          'record', to_jsonb(occurrence_record)
        );
      END IF;

      RETURN jsonb_build_object(
        'status', 'conflict',
        'retryable', false,
        'conflict_reason', 'occurrence_changed',
        'current_plan_revision', current_plan.revision,
        'resulting_record_id', null,
        'resulting_next_due_date', current_plan.next_due_date,
        'plan', to_jsonb(current_plan),
        'record', null
      );
    END IF;

    IF expected_plan_revision IS NOT NULL
        AND current_plan.revision IS DISTINCT FROM expected_plan_revision THEN
      RETURN jsonb_build_object(
        'status', 'conflict',
        'retryable', true,
        'conflict_reason', 'stale_plan_revision',
        'current_plan_revision', current_plan.revision,
        'resulting_record_id', null,
        'resulting_next_due_date', current_plan.next_due_date,
        'plan', to_jsonb(current_plan),
        'record', null
      );
    END IF;
  ELSE
    PERFORM set_config('owntend.completion_plan_insert', 'true', true);
    INSERT INTO public.maintenance_plans (
      id,
      user_id,
      asset_id,
      title,
      description,
      interval_count,
      interval_unit,
      priority,
      next_due_date,
      reminder_days_before,
      created_at,
      updated_at,
      archived_at,
      revision,
      is_enabled
    ) VALUES (
      plan_id_value,
      request_user,
      NULLIF(TRIM(plan_payload ->> 'asset_id'), ''),
      NULLIF(TRIM(plan_payload ->> 'title'), ''),
      COALESCE(
        NULLIF(TRIM(plan_payload ->> 'description'), ''),
        NULLIF(TRIM(plan_payload ->> 'instructions'), '')
      ),
      plan_recurrence_interval,
      COALESCE(NULLIF(TRIM(plan_payload ->> 'interval_unit'), ''), NULLIF(TRIM(plan_payload ->> 'recurrence_unit'), ''), 'months'),
      NULLIF(TRIM(plan_payload ->> 'priority'), ''),
      plan_next_due_date,
      plan_reminder_days_before,
      plan_created_at,
      plan_updated_at,
      plan_archived_at,
      COALESCE(expected_plan_revision, 1),
      plan_is_enabled
    )
    RETURNING * INTO current_plan;
    PERFORM set_config('owntend.completion_plan_insert', 'false', true);

    plan_was_created := true;
  END IF;

  INSERT INTO public.maintenance_records (
    id,
    user_id,
    plan_id,
    due_date,
    completed_at,
    notes,
    created_at,
    operation_id
  ) VALUES (
    record_id_value,
    request_user,
    plan_id_value,
    record_due_date,
    record_completed_at,
    NULLIF(TRIM(record_payload ->> 'notes'), ''),
    COALESCE(date_trunc('second', NULLIF(TRIM(record_payload ->> 'created_at'), '')::timestamptz), date_trunc('second', clock_timestamp())),
    operation_id_value
  )
  RETURNING * INTO current_record;

  IF NOT plan_was_created THEN
    UPDATE public.maintenance_plans
    SET next_due_date = plan_next_due_date,
        updated_at = plan_updated_at,
        archived_at = plan_archived_at,
        revision = current_plan.revision + 1,
        is_enabled = plan_is_enabled
    WHERE user_id = request_user
      AND id = plan_id_value
    RETURNING * INTO current_plan;
  END IF;

  UPDATE public.notification_inbox
  SET read_at = COALESCE(read_at, clock_timestamp()),
      updated_at = clock_timestamp()
  WHERE user_id = request_user
    AND plan_id = plan_id_value;

  RETURN jsonb_build_object(
    'status', 'applied',
    'retryable', false,
    'conflict_reason', null,
    'current_plan_revision', current_plan.revision,
    'resulting_record_id', current_record.id,
    'resulting_next_due_date', current_plan.next_due_date,
    'plan', to_jsonb(current_plan),
    'record', to_jsonb(current_record)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.complete_maintenance_task(JSONB, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.complete_maintenance_task(JSONB, TEXT)
  TO authenticated;


CREATE OR REPLACE FUNCTION public.undo_maintenance_completion(
  p_operation JSONB,
  p_device_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  request_user UUID := auth.uid();
  operation_id_value TEXT;
  plan_id_value TEXT;
  completion_id_value TEXT;
  target_completed_at TIMESTAMPTZ;
  previous_due_date_value TIMESTAMPTZ;
  expected_current_due TIMESTAMPTZ;
  current_plan public.maintenance_plans%ROWTYPE;
  target_record public.maintenance_records%ROWTYPE;
  latest_record public.maintenance_records%ROWTYPE;
  has_newer BOOLEAN := false;
  rewound_value BOOLEAN := false;
  target_existed BOOLEAN := false;
BEGIN
  IF request_user IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'unauthorized',
      'retryable', false,
      'conflict_reason', 'authentication_required'
    );
  END IF;
  IF p_operation IS NULL
     OR jsonb_typeof(p_operation) <> 'object'
     OR COALESCE((p_operation ->> 'version')::integer, 0) <> 1
     OR NULLIF(TRIM(COALESCE(p_device_id, '')), '') IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'invalid_payload'
    );
  END IF;

  operation_id_value := NULLIF(TRIM(p_operation ->> 'operation_id'), '');
  plan_id_value := NULLIF(TRIM(p_operation ->> 'plan_id'), '');
  completion_id_value := NULLIF(TRIM(p_operation ->> 'completion_id'), '');
  BEGIN
    target_completed_at := date_trunc(
      'second',
      NULLIF(TRIM(p_operation ->> 'completion_completed_at'), '')::timestamptz
    );
    previous_due_date_value := date_trunc(
      'second',
      NULLIF(TRIM(p_operation ->> 'previous_due_date'), '')::timestamptz
    );
    expected_current_due := date_trunc(
      'second',
      NULLIF(TRIM(p_operation ->> 'expected_current_next_due_date'), '')::timestamptz
    );
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'invalid_timestamp'
    );
  END;
  IF operation_id_value IS NULL
     OR plan_id_value IS NULL
     OR completion_id_value IS NULL
     OR target_completed_at IS NULL
     OR previous_due_date_value IS NULL
     OR expected_current_due IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'missing_fields'
    );
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(request_user::text || ':maintenance:' || plan_id_value, 0)
  );

  SELECT * INTO current_plan
  FROM public.maintenance_plans
  WHERE user_id = request_user
    AND id = plan_id_value
  FOR UPDATE;
  IF current_plan.id IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'plan_missing'
    );
  END IF;

  SELECT * INTO target_record
  FROM public.maintenance_records
  WHERE user_id = request_user
    AND id = completion_id_value
    AND plan_id = plan_id_value
  FOR UPDATE;
  target_existed := target_record.id IS NOT NULL;
  IF target_existed THEN
    DELETE FROM public.maintenance_records
    WHERE user_id = request_user
      AND id = completion_id_value;
  END IF;

  SELECT * INTO latest_record
  FROM public.maintenance_records
  WHERE user_id = request_user
    AND plan_id = plan_id_value
  ORDER BY completed_at DESC, id DESC
  LIMIT 1;

  has_newer := latest_record.id IS NOT NULL AND (
    latest_record.completed_at > target_completed_at OR
    (
      latest_record.completed_at = target_completed_at AND
      latest_record.id > completion_id_value
    )
  );

  IF NOT has_newer
     AND current_plan.next_due_date IS NOT DISTINCT FROM expected_current_due THEN
    UPDATE public.maintenance_plans
    SET next_due_date = previous_due_date_value,
        updated_at = date_trunc('second', clock_timestamp()),
        revision = current_plan.revision + 1
    WHERE user_id = request_user
      AND id = plan_id_value
    RETURNING * INTO current_plan;
    rewound_value := true;
  END IF;

  UPDATE public.notification_inbox
  SET read_at = NULL,
      updated_at = clock_timestamp()
  WHERE user_id = request_user
    AND id = (
      SELECT id
      FROM public.notification_inbox
      WHERE user_id = request_user
        AND plan_id = plan_id_value
        AND kind = 'task'
      ORDER BY created_at DESC, id DESC
      LIMIT 1
    );

  RETURN jsonb_build_object(
    'status', CASE
      WHEN target_existed OR rewound_value THEN 'applied'
      ELSE 'already_applied'
    END,
    'retryable', false,
    'conflict_reason', null,
    'rewound', rewound_value,
    'plan', to_jsonb(current_plan)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.undo_maintenance_completion(JSONB, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.undo_maintenance_completion(JSONB, TEXT)
  TO authenticated;


COMMIT;
