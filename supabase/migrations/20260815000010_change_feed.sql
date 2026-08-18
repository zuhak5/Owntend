BEGIN;

-- The pre-launch reset starts from an empty database, so define the final feed
-- row contract directly instead of retaining conversion logic for unshipped data.
ALTER TABLE public.server_change_feed
  ADD COLUMN key_data JSONB;
ALTER TABLE public.server_change_feed
  ALTER COLUMN key_data SET NOT NULL;

ALTER TABLE public.server_change_feed
  ADD CONSTRAINT server_change_feed_entity_type_check CHECK (
    entity_type IN (
      'profile', 'area', 'room', 'asset', 'device_detail', 'pet_detail',
      'plant_detail', 'safety_detail', 'tag', 'asset_tag', 'asset_photo',
      'maintenance_plan', 'maintenance_plan_metadata', 'maintenance_record',
      'notification_inbox', 'user_setting', 'streak'
    )
  );
ALTER TABLE public.server_change_feed
  ADD CONSTRAINT server_change_feed_key_data_object_check CHECK (
    jsonb_typeof(key_data) = 'object'
  );

CREATE OR REPLACE FUNCTION owntend_private.sync_feed_identity(
  p_table_name TEXT,
  p_row JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog
AS $$
DECLARE
  v_entity_type TEXT;
  v_key_data JSONB;
  v_record_id TEXT;
BEGIN
  CASE p_table_name
    WHEN 'profiles' THEN
      v_entity_type := 'profile';
      v_key_data := '{}'::jsonb;
      v_record_id := 'profile';
    WHEN 'areas' THEN
      v_entity_type := 'area';
      v_key_data := jsonb_build_object('id', p_row ->> 'id');
      v_record_id := p_row ->> 'id';
    WHEN 'rooms' THEN
      v_entity_type := 'room';
      v_key_data := jsonb_build_object('id', p_row ->> 'id');
      v_record_id := p_row ->> 'id';
    WHEN 'assets' THEN
      v_entity_type := 'asset';
      v_key_data := jsonb_build_object('id', p_row ->> 'id');
      v_record_id := p_row ->> 'id';
    WHEN 'device_details' THEN
      v_entity_type := 'device_detail';
      v_key_data := jsonb_build_object('asset_id', p_row ->> 'asset_id');
      v_record_id := p_row ->> 'asset_id';
    WHEN 'pet_details' THEN
      v_entity_type := 'pet_detail';
      v_key_data := jsonb_build_object('asset_id', p_row ->> 'asset_id');
      v_record_id := p_row ->> 'asset_id';
    WHEN 'plant_details' THEN
      v_entity_type := 'plant_detail';
      v_key_data := jsonb_build_object('asset_id', p_row ->> 'asset_id');
      v_record_id := p_row ->> 'asset_id';
    WHEN 'safety_details' THEN
      v_entity_type := 'safety_detail';
      v_key_data := jsonb_build_object('asset_id', p_row ->> 'asset_id');
      v_record_id := p_row ->> 'asset_id';
    WHEN 'tags' THEN
      v_entity_type := 'tag';
      v_key_data := jsonb_build_object('id', p_row ->> 'id');
      v_record_id := p_row ->> 'id';
    WHEN 'asset_tags' THEN
      v_entity_type := 'asset_tag';
      v_key_data := jsonb_build_object(
        'asset_id', p_row ->> 'asset_id',
        'tag_id', p_row ->> 'tag_id'
      );
      v_record_id := concat_ws('|', p_row ->> 'asset_id', p_row ->> 'tag_id');
    WHEN 'asset_photos' THEN
      v_entity_type := 'asset_photo';
      v_key_data := jsonb_build_object('id', p_row ->> 'id');
      v_record_id := p_row ->> 'id';
    WHEN 'maintenance_plans' THEN
      v_entity_type := 'maintenance_plan';
      v_key_data := jsonb_build_object('id', p_row ->> 'id');
      v_record_id := p_row ->> 'id';
    WHEN 'maintenance_plan_metadata' THEN
      v_entity_type := 'maintenance_plan_metadata';
      v_key_data := jsonb_build_object('plan_id', p_row ->> 'plan_id');
      v_record_id := p_row ->> 'plan_id';
    WHEN 'maintenance_records' THEN
      v_entity_type := 'maintenance_record';
      v_key_data := jsonb_build_object('id', p_row ->> 'id');
      v_record_id := p_row ->> 'id';
    WHEN 'notification_inbox' THEN
      v_entity_type := 'notification_inbox';
      v_key_data := jsonb_build_object('id', p_row ->> 'id');
      v_record_id := p_row ->> 'id';
    WHEN 'user_settings' THEN
      v_entity_type := 'user_setting';
      v_key_data := jsonb_build_object('key', p_row ->> 'key');
      v_record_id := p_row ->> 'key';
    WHEN 'streaks' THEN
      v_entity_type := 'streak';
      v_key_data := jsonb_build_object('id', p_row ->> 'id');
      v_record_id := p_row ->> 'id';
    ELSE
      RAISE EXCEPTION 'Unsupported change-feed table %', p_table_name
        USING ERRCODE = '0A000';
  END CASE;

  IF v_record_id IS NULL OR
     EXISTS (
       SELECT 1
       FROM jsonb_each(v_key_data) AS item
       WHERE item.value = 'null'::jsonb OR item.value = '""'::jsonb
     ) THEN
    RAISE EXCEPTION 'Malformed change-feed key for table %', p_table_name
      USING ERRCODE = '23514';
  END IF;

  RETURN jsonb_build_object(
    'entity_type', v_entity_type,
    'key_data', v_key_data,
    'record_id', v_record_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_log_server_change_feed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row JSONB;
  v_identity JSONB;
  v_user_id UUID;
  v_entity_type TEXT;
  v_key_data JSONB;
  v_record_id TEXT;
  v_op_type TEXT;
  v_client_updated_at TIMESTAMPTZ;
  v_revision BIGINT;
BEGIN
  v_op_type := TG_OP;
  v_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  v_user_id := NULLIF(v_row ->> 'user_id', '')::uuid;
  v_identity := owntend_private.sync_feed_identity(TG_TABLE_NAME, v_row);
  v_entity_type := v_identity ->> 'entity_type';
  v_key_data := v_identity -> 'key_data';
  v_record_id := v_identity ->> 'record_id';
  v_client_updated_at := CASE TG_TABLE_NAME
    WHEN 'profiles' THEN NULLIF(v_row ->> 'client_modified_at', '')::timestamptz
    ELSE COALESCE(
      NULLIF(v_row ->> 'updated_at', '')::timestamptz,
      clock_timestamp()
    )
  END;
  v_revision := COALESCE(NULLIF(v_row ->> 'revision', '')::bigint, 1);

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unsupported change-feed row for table %', TG_TABLE_NAME;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_user_id) THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.server_change_feed (
    user_id,
    entity_type,
    record_id,
    key_data,
    op_type,
    client_updated_at,
    revision
  ) VALUES (
    v_user_id,
    v_entity_type,
    v_record_id,
    v_key_data,
    v_op_type,
    v_client_updated_at,
    v_revision
  );
  RETURN NULL;
END;
$$;

DO $$
DECLARE
  tbl TEXT;
  tbls TEXT[] := ARRAY[
    'profiles', 'areas', 'rooms', 'assets', 'device_details', 'pet_details',
    'plant_details', 'safety_details', 'tags', 'asset_tags', 'asset_photos',
    'maintenance_plans', 'maintenance_plan_metadata', 'maintenance_records',
    'notification_inbox', 'user_settings', 'streaks'
  ];
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'notifications'
  ) THEN
    DROP TRIGGER IF EXISTS trg_server_change_feed_notifications
      ON public.notifications;
  END IF;

  FOREACH tbl IN ARRAY tbls LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_server_change_feed_%I ON public.%I;',
      tbl,
      tbl
    );
    EXECUTE format(
      'CREATE TRIGGER trg_server_change_feed_%I '
      'AFTER INSERT OR UPDATE OR DELETE ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.fn_log_server_change_feed();',
      tbl,
      tbl
    );
  END LOOP;
END;
$$;

INSERT INTO public.sync_feed_capabilities (
  id,
  enabled,
  capability_version,
  min_retained_seq,
  updated_at
)
VALUES ('global', false, '1.0.1', 0, clock_timestamp())
ON CONFLICT (id) DO UPDATE SET
  enabled = false,
  capability_version = '1.0.1',
  min_retained_seq = 0,
  updated_at = clock_timestamp();

COMMIT;
