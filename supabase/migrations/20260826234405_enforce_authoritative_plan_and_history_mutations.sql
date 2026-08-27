-- Apply only after the compatible client is deployed. From this point,
-- economically significant columns and maintenance history are RPC-only.

INSERT INTO owntend_monetization_private.maintenance_plan_entitlements (
  user_id, plan_id, paid_cost, origin, created_by_operation_id
)
SELECT p.user_id, p.id, COALESCE(o.charged_amount, 0)::smallint,
       CASE WHEN o.operation_id IS NULL THEN 'legacy_unverified' ELSE 'task_creation' END,
       o.operation_id
FROM public.maintenance_plans p
LEFT JOIN public.creation_point_operations o
  ON o.user_id = p.user_id AND o.entity_type = 'task' AND o.entity_id = p.id
ON CONFLICT (user_id, plan_id) DO NOTHING;

CREATE OR REPLACE FUNCTION owntend_monetization_private.create_asset_impl(
  p_operation jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id uuid := auth.uid();
  operation_uuid uuid;
  asset_json jsonb;
  details_json jsonb;
  plans_json jsonb;
  asset_id text;
  asset_kind text;
  current_balance integer;
  existing_operation public.creation_point_operations%ROWTYPE;
  v_request_hash text;
  v_client_request_hash text;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_operation IS NULL OR jsonb_typeof(p_operation) <> 'object'
     OR pg_column_size(p_operation) > 262144 THEN
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
  asset_json := p_operation->'asset';
  details_json := COALESCE(p_operation->'details', '{}'::jsonb);
  plans_json := COALESCE(p_operation->'initial_plans', '[]'::jsonb);
  IF jsonb_typeof(asset_json) <> 'object' OR jsonb_typeof(details_json) <> 'object'
     OR jsonb_typeof(plans_json) <> 'array' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_ASSET_PAYLOAD';
  END IF;
  IF jsonb_array_length(plans_json) <> 0 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'UNTRUSTED_INITIAL_PLANS';
  END IF;
  asset_id := NULLIF(btrim(asset_json->>'id'), '');
  asset_kind := COALESCE(NULLIF(btrim(asset_json->>'asset_type'), ''), 'general');
  IF asset_id IS NULL OR char_length(asset_id) > 200
     OR asset_kind NOT IN ('device', 'pet', 'plant', 'safety', 'general') THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_ASSET_PAYLOAD';
  END IF;
  v_request_hash := encode(extensions.digest(p_operation::text::bytea, 'sha256'), 'hex');
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text || ':asset_op:' || operation_uuid::text, 0)
  );
  SELECT * INTO existing_operation
  FROM public.creation_point_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    IF existing_operation.user_id <> caller_id OR existing_operation.entity_type <> 'asset'
       OR existing_operation.entity_id <> asset_id
       OR existing_operation.request_hash <> v_request_hash
       OR existing_operation.client_request_hash <> v_client_request_hash THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
    END IF;
    SELECT balance INTO current_balance FROM public.point_wallets WHERE user_id = caller_id;
    RETURN jsonb_build_object(
      'asset_id', asset_id, 'balance', COALESCE(current_balance, 0),
      'charged', existing_operation.charged_amount,
      'already_processed', true,
      'asset', (SELECT to_jsonb(a) FROM public.assets a
                WHERE a.user_id = caller_id AND a.id = asset_id)
    );
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.rooms
    WHERE user_id = caller_id AND id = asset_json->>'room_id' AND archived_at IS NULL
  ) THEN
    RAISE EXCEPTION USING errcode = '23503', message = 'ROOM_NOT_FOUND';
  END IF;
  SELECT balance INTO current_balance FROM public.point_wallets WHERE user_id = caller_id;
  current_balance := COALESCE(current_balance, 0);

  INSERT INTO public.assets (
    user_id, id, room_id, name, asset_type, placement, purchase_date, notes,
    created_at, updated_at, archived_at, revision
  ) VALUES (
    caller_id, asset_id, asset_json->>'room_id', btrim(asset_json->>'name'),
    asset_kind, NULLIF(btrim(asset_json->>'placement'), ''),
    NULLIF(asset_json->>'purchase_date', '')::date,
    NULLIF(btrim(asset_json->>'notes'), ''),
    clock_timestamp(), clock_timestamp(), NULL, 1
  );

  IF asset_kind = 'device' AND details_json <> '{}'::jsonb THEN
    INSERT INTO public.device_details (
      user_id, asset_id, brand, model, serial_number, power_source,
      warranty_until, manual_url, consumable, created_at, updated_at, revision
    ) VALUES (
      caller_id, asset_id, NULLIF(btrim(details_json->>'brand'), ''),
      NULLIF(btrim(details_json->>'model'), ''),
      NULLIF(btrim(details_json->>'serial_number'), ''),
      NULLIF(btrim(details_json->>'power_source'), ''),
      NULLIF(details_json->>'warranty_until', '')::date,
      NULLIF(btrim(details_json->>'manual_url'), ''),
      NULLIF(btrim(details_json->>'consumable'), ''),
      clock_timestamp(), clock_timestamp(), 1
    );
  ELSIF asset_kind = 'pet' AND details_json <> '{}'::jsonb THEN
    INSERT INTO public.pet_details (
      user_id, asset_id, species, breed, birth_date, microchip_id,
      vet_name, vet_phone, feeding_notes, medical_notes,
      created_at, updated_at, revision
    ) VALUES (
      caller_id, asset_id, NULLIF(btrim(details_json->>'species'), ''),
      NULLIF(btrim(details_json->>'breed'), ''),
      NULLIF(details_json->>'birth_date', '')::date,
      NULLIF(btrim(details_json->>'microchip_id'), ''),
      NULLIF(btrim(details_json->>'vet_name'), ''),
      NULLIF(btrim(details_json->>'vet_phone'), ''),
      NULLIF(btrim(details_json->>'feeding_notes'), ''),
      NULLIF(btrim(details_json->>'medical_notes'), ''),
      clock_timestamp(), clock_timestamp(), 1
    );
  ELSIF asset_kind = 'plant' AND details_json <> '{}'::jsonb THEN
    INSERT INTO public.plant_details (
      user_id, asset_id, species, sunlight, watering_interval_days,
      pot_size, last_repotted_at, toxicity_notes,
      created_at, updated_at, revision
    ) VALUES (
      caller_id, asset_id, NULLIF(btrim(details_json->>'species'), ''),
      NULLIF(btrim(details_json->>'sunlight'), ''),
      NULLIF(details_json->>'watering_interval_days', '')::integer,
      NULLIF(btrim(details_json->>'pot_size'), ''),
      NULLIF(details_json->>'last_repotted_at', '')::timestamptz,
      NULLIF(btrim(details_json->>'toxicity_notes'), ''),
      clock_timestamp(), clock_timestamp(), 1
    );
  ELSIF asset_kind = 'safety' AND details_json <> '{}'::jsonb THEN
    INSERT INTO public.safety_details (
      user_id, asset_id, safety_type, installed_at, expires_at,
      battery_type, test_interval_days, created_at, updated_at, revision
    ) VALUES (
      caller_id, asset_id, NULLIF(btrim(details_json->>'safety_type'), ''),
      NULLIF(details_json->>'installed_at', '')::timestamptz,
      NULLIF(details_json->>'expires_at', '')::timestamptz,
      NULLIF(btrim(details_json->>'battery_type'), ''),
      NULLIF(details_json->>'test_interval_days', '')::integer,
      clock_timestamp(), clock_timestamp(), 1
    );
  ELSIF asset_kind = 'general' AND details_json <> '{}'::jsonb THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_ASSET_PAYLOAD';
  END IF;

  INSERT INTO public.creation_point_operations (
    operation_id, user_id, entity_type, entity_id, charged_amount,
    request_hash, client_request_hash
  ) VALUES (
    operation_uuid, caller_id, 'asset', asset_id, 0,
    v_request_hash, v_client_request_hash
  );
  RETURN jsonb_build_object(
    'asset_id', asset_id, 'balance', current_balance, 'charged', 0,
    'already_processed', false,
    'asset', (SELECT to_jsonb(a) FROM public.assets a
              WHERE a.user_id = caller_id AND a.id = asset_id)
  );
EXCEPTION
  WHEN check_violation OR not_null_violation OR invalid_text_representation THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_ASSET_PAYLOAD';
END;
$$;

ALTER FUNCTION owntend_monetization_private.create_asset_impl(jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_monetization_private.create_asset_impl(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.create_asset_impl(jsonb)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_asset(p_operation jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.create_asset_impl(p_operation);
END;
$$;
ALTER FUNCTION public.create_asset(jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.create_asset(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_asset(jsonb) TO authenticated, service_role;

REVOKE UPDATE ON TABLE public.maintenance_plans FROM authenticated;
GRANT UPDATE (
  title, instructions, recurrence_interval, recurrence_unit, priority,
  next_due_date, reminder_days_before, updated_at, archived_at, revision, is_enabled
) ON TABLE public.maintenance_plans TO authenticated;

REVOKE UPDATE ON TABLE public.assets FROM authenticated;
GRANT UPDATE (
  name, room_id, placement, notes, purchase_date,
  updated_at, archived_at, revision
) ON TABLE public.assets TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON TABLE public.maintenance_records FROM authenticated;
DROP POLICY IF EXISTS maintenance_records_insert_own ON public.maintenance_records;
DROP POLICY IF EXISTS maintenance_records_update_own ON public.maintenance_records;
DROP POLICY IF EXISTS maintenance_records_delete_own ON public.maintenance_records;
GRANT SELECT ON TABLE public.maintenance_records TO authenticated;

-- ACL assertions are stated as comments for operator review and are enforced
-- by pgTAP: public wrappers are invokers, private implementations are definers
-- with an empty search_path, and PUBLIC/anon receive no execute privilege.
