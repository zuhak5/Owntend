-- Align device consumable semantics with Flutter/Drift and persist asset placement.
-- The client models consumable as optional descriptive text (filters, batteries,
-- cartridges, etc.); Boolean values from the original cloud baseline were a
-- schema/RPC mismatch that caused INVALID_ASSET_PAYLOAD on normal text input.

BEGIN;

ALTER TABLE public.device_details
  ALTER COLUMN consumable DROP DEFAULT;

ALTER TABLE public.device_details
  ALTER COLUMN consumable DROP NOT NULL;

ALTER TABLE public.device_details
  ALTER COLUMN consumable TYPE TEXT
  USING CASE WHEN consumable IS TRUE THEN 'true' ELSE NULL END;

ALTER TABLE public.device_details
  ADD CONSTRAINT device_details_consumable_length_check
  CHECK (consumable IS NULL OR CHAR_LENGTH(consumable) <= 500);

CREATE OR REPLACE FUNCTION owntend_monetization_private.create_asset_with_point_debit_impl(
  p_operation JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id UUID := auth.uid();
  operation_uuid UUID;
  asset_json JSONB;
  details_json JSONB;
  plans_json JSONB;
  plan_json JSONB;
  metadata_json JSONB;
  asset_id TEXT;
  asset_kind TEXT;
  category_health_group TEXT;
  current_balance INTEGER;
  existing_operation public.creation_point_operations%ROWTYPE;
  v_request_hash TEXT;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_operation IS NULL
    OR jsonb_typeof(p_operation) <> 'object'
    OR pg_column_size(p_operation) > 262144
  THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION';
  END IF;

  BEGIN
    operation_uuid := (p_operation->>'operation_id')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION_ID';
  END;

  asset_json := p_operation->'asset';
  details_json := COALESCE(p_operation->'details', '{}'::jsonb);
  plans_json := COALESCE(p_operation->'initial_plans', '[]'::jsonb);
  IF jsonb_typeof(asset_json) <> 'object'
    OR jsonb_typeof(details_json) <> 'object'
    OR jsonb_typeof(plans_json) <> 'array'
    OR jsonb_array_length(plans_json) > 50
  THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_ASSET_PAYLOAD';
  END IF;

  asset_id := NULLIF(BTRIM(asset_json->>'id'), '');
  asset_kind := asset_json->>'asset_type';
  IF asset_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_ASSET_PAYLOAD';
  END IF;

  v_request_hash := encode(extensions.digest(p_operation::text::bytea, 'sha256'), 'hex');

  -- Advisory lock scoped to caller and operation UUID
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      caller_id::text || ':asset_op:' || operation_uuid::text,
      0
    )
  );

  -- Check for existing operation for idempotency
  SELECT * INTO existing_operation
  FROM public.creation_point_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    IF existing_operation.user_id <> caller_id
      OR existing_operation.entity_type <> 'asset'
      OR existing_operation.entity_id <> asset_id
      OR (existing_operation.request_hash IS NOT NULL AND existing_operation.request_hash <> v_request_hash)
    THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
    END IF;
    SELECT COALESCE(balance, 0) INTO current_balance
    FROM public.point_wallets WHERE user_id = caller_id;
    RETURN jsonb_build_object(
      'asset_id', asset_id,
      'balance', COALESCE(current_balance, 0),
      'charged', existing_operation.charged_amount,
      'already_processed', true,
      'asset', (
        SELECT to_jsonb(a) FROM public.assets a
        WHERE a.user_id = caller_id AND a.id = asset_id
      )
    );
  END IF;

  IF (asset_json->>'room_id') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.rooms
    WHERE user_id = caller_id
      AND id = asset_json->>'room_id'
      AND archived_at IS NULL
  ) THEN
    RAISE EXCEPTION USING errcode = '23503', message = 'ROOM_NOT_FOUND';
  END IF;

  category_health_group := CASE asset_json->>'category_id'
    WHEN 'category_safety' THEN 'safety'
    WHEN 'category_pets' THEN 'pets'
    WHEN 'category_appliances' THEN 'appliances'
    WHEN 'category_plants' THEN 'plants'
    WHEN 'category_cleaning' THEN 'cleaning'
    WHEN 'category_general' THEN 'other'
    ELSE NULL
  END;
  IF category_health_group IS NULL AND asset_json->>'category_id' IS NOT NULL THEN
    RAISE EXCEPTION USING errcode = '23503', message = 'CATEGORY_NOT_FOUND';
  END IF;

  -- Read current balance (if wallet exists, otherwise default 0).
  -- Note: In the V1 economy, asset creation is always free (0 points),
  -- so no balance sufficiency check or wallet row locking is required.
  SELECT balance INTO current_balance
  FROM public.point_wallets
  WHERE user_id = caller_id;
  IF NOT FOUND THEN
    current_balance := 0;
  END IF;

  -- Re-verify operation idempotency
  SELECT * INTO existing_operation
  FROM public.creation_point_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    IF existing_operation.user_id <> caller_id
      OR existing_operation.entity_type <> 'asset'
      OR existing_operation.entity_id <> asset_id
      OR (existing_operation.request_hash IS NOT NULL AND existing_operation.request_hash <> v_request_hash)
    THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
    END IF;
    RETURN jsonb_build_object(
      'asset_id', existing_operation.entity_id,
      'balance', current_balance,
      'charged', existing_operation.charged_amount,
      'already_processed', true,
      'asset', (
        SELECT to_jsonb(a) FROM public.assets a
        WHERE a.user_id = caller_id AND a.id = existing_operation.entity_id
      )
    );
  END IF;

  -- Insert asset
  INSERT INTO public.assets (
    user_id, id, room_id, category_id, name,
    placement, purchase_date, notes, created_at, updated_at,
    archived_at, revision, asset_type
  ) VALUES (
    caller_id, asset_id, asset_json->>'room_id', asset_json->>'category_id',
    BTRIM(asset_json->>'name'),
    NULLIF(BTRIM(asset_json->>'placement'), ''),
    (asset_json->>'purchase_date')::date,
    NULLIF(BTRIM(asset_json->>'notes'), ''),
    NOW(), NOW(), NULL, 1, COALESCE(asset_kind, 'general')
  );

  -- Insert specialized details if present
  IF details_json <> '{}'::jsonb THEN
    IF asset_kind = 'device' THEN
      INSERT INTO public.device_details (
        user_id, asset_id, brand, model, serial_number, power_source,
        warranty_until, manual_url, consumable, created_at, updated_at, revision
      ) VALUES (
        caller_id, asset_id,
        NULLIF(BTRIM(details_json->>'brand'), ''),
        NULLIF(BTRIM(details_json->>'model'), ''),
        NULLIF(BTRIM(details_json->>'serial_number'), ''),
        NULLIF(BTRIM(details_json->>'power_source'), ''),
        (details_json->>'warranty_until')::date,
        NULLIF(BTRIM(details_json->>'manual_url'), ''),
        NULLIF(BTRIM(details_json->>'consumable'), ''),
        NOW(), NOW(), 1
      );
    ELSIF asset_kind = 'pet' THEN
      INSERT INTO public.pet_details (
        user_id, asset_id, species, breed, birth_date, microchip_id,
        vet_name, vet_phone, feeding_notes, medical_notes, created_at, updated_at, revision
      ) VALUES (
        caller_id, asset_id,
        NULLIF(BTRIM(details_json->>'species'), ''),
        NULLIF(BTRIM(details_json->>'breed'), ''),
        (details_json->>'birth_date')::date,
        NULLIF(BTRIM(details_json->>'microchip_id'), ''),
        NULLIF(BTRIM(details_json->>'vet_name'), ''),
        NULLIF(BTRIM(details_json->>'vet_phone'), ''),
        NULLIF(BTRIM(details_json->>'feeding_notes'), ''),
        NULLIF(BTRIM(details_json->>'medical_notes'), ''),
        NOW(), NOW(), 1
      );
    ELSIF asset_kind = 'plant' THEN
      INSERT INTO public.plant_details (
        user_id, asset_id, species, sunlight, watering_interval_days,
        pot_size, last_repotted_at, toxicity_notes, created_at, updated_at, revision
      ) VALUES (
        caller_id, asset_id,
        NULLIF(BTRIM(details_json->>'species'), ''),
        NULLIF(BTRIM(details_json->>'sunlight'), ''),
        (details_json->>'watering_interval_days')::integer,
        NULLIF(BTRIM(details_json->>'pot_size'), ''),
        (details_json->>'last_repotted_at')::timestamptz,
        NULLIF(BTRIM(details_json->>'toxicity_notes'), ''),
        NOW(), NOW(), 1
      );
    ELSIF asset_kind = 'safety' THEN
      INSERT INTO public.safety_details (
        user_id, asset_id, safety_type, installed_at, expires_at,
        battery_type, test_interval_days, created_at, updated_at, revision
      ) VALUES (
        caller_id, asset_id,
        NULLIF(BTRIM(details_json->>'safety_type'), ''),
        (details_json->>'installed_at')::timestamptz,
        (details_json->>'expires_at')::timestamptz,
        NULLIF(BTRIM(details_json->>'battery_type'), ''),
        (details_json->>'test_interval_days')::integer,
        NOW(), NOW(), 1
      );
    END IF;
  END IF;

  -- Insert bundled initial maintenance plans (always 0 points)
  FOR plan_json IN SELECT * FROM jsonb_array_elements(plans_json) LOOP
    metadata_json := COALESCE(plan_json->'metadata', '{}'::jsonb);
    INSERT INTO public.maintenance_plans (
      user_id, id, asset_id, title, description, interval_count,
      interval_unit, priority, next_due_date, reminder_days_before,
      health_group, created_at, updated_at, archived_at, revision, is_enabled
    ) VALUES (
      caller_id, plan_json->>'id', asset_id, BTRIM(plan_json->>'title'),
      COALESCE(
        NULLIF(BTRIM(plan_json->>'description'), ''),
        NULLIF(BTRIM(plan_json->>'instructions'), '')
      ),
      COALESCE((plan_json->>'interval_count')::integer, (plan_json->>'recurrence_interval')::integer, 1),
      COALESCE(plan_json->>'interval_unit', plan_json->>'recurrence_unit', 'months'),
      COALESCE(plan_json->>'priority', 'medium'),
      (plan_json->>'next_due_date')::timestamptz,
      COALESCE((plan_json->>'reminder_days_before')::integer, 0),
      CASE WHEN category_health_group = 'safety' THEN 'safety' ELSE plan_json->>'health_group' END,
      NOW(), NOW(), NULL, 1, COALESCE((plan_json->>'is_enabled')::boolean, true)
    );
    IF metadata_json <> '{}'::jsonb THEN
      INSERT INTO public.maintenance_plan_metadata (
        user_id, plan_id, task_type, location_label, estimated_duration_minutes,
        required_materials_json, reminder_recommendation,
        sort_order, created_at, updated_at, revision
      ) VALUES (
        caller_id, plan_json->>'id',
        NULLIF(BTRIM(metadata_json->>'task_type'), ''),
        NULLIF(BTRIM(metadata_json->>'location_label'), ''),
        (metadata_json->>'estimated_duration_minutes')::integer,
        COALESCE(metadata_json->>'required_materials_json', (metadata_json->'required_materials')::text, '[]'),
        NULLIF(BTRIM(metadata_json->>'reminder_recommendation'), ''),
        COALESCE((metadata_json->>'sort_order')::integer, 0),
        NOW(), NOW(), 1
      );
    END IF;
  END LOOP;

  -- Record creation operation with charged_amount = 0
  INSERT INTO public.creation_point_operations (
    operation_id, user_id, entity_type, entity_id, charged_amount, request_hash
  ) VALUES (operation_uuid, caller_id, 'asset', asset_id, 0, v_request_hash);

  -- Return success with charged = 0 and unchanged balance
  RETURN jsonb_build_object(
    'asset_id', asset_id,
    'balance', current_balance,
    'charged', 0,
    'already_processed', false,
    'asset', (
      SELECT to_jsonb(a) FROM public.assets a
      WHERE a.user_id = caller_id AND a.id = asset_id
    )
  );
EXCEPTION
  WHEN check_violation OR not_null_violation OR invalid_text_representation THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_ASSET_PAYLOAD';
END;
$$;

REVOKE ALL ON FUNCTION owntend_monetization_private.create_asset_with_point_debit_impl(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.create_asset_with_point_debit_impl(JSONB) TO authenticated, service_role;

COMMIT;
