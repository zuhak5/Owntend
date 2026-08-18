BEGIN;

ALTER TABLE public.server_change_feed
  ADD COLUMN IF NOT EXISTS key_data JSONB;

UPDATE public.server_change_feed
SET
  key_data = CASE entity_type
    WHEN 'profiles' THEN '{}'::jsonb
    WHEN 'profile' THEN '{}'::jsonb
    WHEN 'areas' THEN jsonb_build_object('id', record_id)
    WHEN 'area' THEN jsonb_build_object('id', record_id)
    WHEN 'rooms' THEN jsonb_build_object('id', record_id)
    WHEN 'room' THEN jsonb_build_object('id', record_id)
    WHEN 'assets' THEN jsonb_build_object('id', record_id)
    WHEN 'asset' THEN jsonb_build_object('id', record_id)
    WHEN 'device_details' THEN jsonb_build_object('asset_id', record_id)
    WHEN 'device_detail' THEN jsonb_build_object('asset_id', record_id)
    WHEN 'pet_details' THEN jsonb_build_object('asset_id', record_id)
    WHEN 'pet_detail' THEN jsonb_build_object('asset_id', record_id)
    WHEN 'plant_details' THEN jsonb_build_object('asset_id', record_id)
    WHEN 'plant_detail' THEN jsonb_build_object('asset_id', record_id)
    WHEN 'safety_details' THEN jsonb_build_object('asset_id', record_id)
    WHEN 'safety_detail' THEN jsonb_build_object('asset_id', record_id)
    WHEN 'tags' THEN jsonb_build_object('id', record_id)
    WHEN 'tag' THEN jsonb_build_object('id', record_id)
    WHEN 'asset_tags' THEN jsonb_build_object(
      'asset_id', split_part(record_id, '|', 1),
      'tag_id', split_part(record_id, '|', 2)
    )
    WHEN 'asset_tag' THEN jsonb_build_object(
      'asset_id', split_part(record_id, '|', 1),
      'tag_id', split_part(record_id, '|', 2)
    )
    WHEN 'asset_photos' THEN jsonb_build_object('id', record_id)
    WHEN 'asset_photo' THEN jsonb_build_object('id', record_id)
    WHEN 'maintenance_plans' THEN jsonb_build_object('id', record_id)
    WHEN 'maintenance_plan' THEN jsonb_build_object('id', record_id)
    WHEN 'maintenance_plan_metadata' THEN jsonb_build_object('plan_id', record_id)
    WHEN 'maintenance_records' THEN jsonb_build_object('id', record_id)
    WHEN 'maintenance_record' THEN jsonb_build_object('id', record_id)
    WHEN 'notification_inbox' THEN jsonb_build_object('id', record_id)
    WHEN 'user_settings' THEN jsonb_build_object('key', record_id)
    WHEN 'user_setting' THEN jsonb_build_object('key', record_id)
    WHEN 'streaks' THEN jsonb_build_object('id', record_id)
    WHEN 'streak' THEN jsonb_build_object('id', record_id)
    ELSE NULL
  END,
  record_id = CASE entity_type
    WHEN 'profiles' THEN 'profile'
    WHEN 'profile' THEN 'profile'
    ELSE record_id
  END,
  entity_type = CASE entity_type
    WHEN 'profiles' THEN 'profile'
    WHEN 'areas' THEN 'area'
    WHEN 'rooms' THEN 'room'
    WHEN 'assets' THEN 'asset'
    WHEN 'device_details' THEN 'device_detail'
    WHEN 'pet_details' THEN 'pet_detail'
    WHEN 'plant_details' THEN 'plant_detail'
    WHEN 'safety_details' THEN 'safety_detail'
    WHEN 'tags' THEN 'tag'
    WHEN 'asset_tags' THEN 'asset_tag'
    WHEN 'asset_photos' THEN 'asset_photo'
    WHEN 'maintenance_plans' THEN 'maintenance_plan'
    WHEN 'maintenance_plan_metadata' THEN 'maintenance_plan_metadata'
    WHEN 'maintenance_records' THEN 'maintenance_record'
    WHEN 'notification_inbox' THEN 'notification_inbox'
    WHEN 'user_settings' THEN 'user_setting'
    WHEN 'streaks' THEN 'streak'
    ELSE entity_type
  END;

-- The retired notifications feed has no matching SyncEntitySpec and the feed is
-- still disabled. Remove only that derived pre-enable history rather than allow
-- an unknown entity to become routable after the protocol cutover.
DELETE FROM public.server_change_feed
WHERE entity_type NOT IN (
  'profile', 'area', 'room', 'asset', 'device_detail', 'pet_detail',
  'plant_detail', 'safety_detail', 'tag', 'asset_tag', 'asset_photo',
  'maintenance_plan', 'maintenance_plan_metadata', 'maintenance_record',
  'notification_inbox', 'user_setting', 'streak'
);

ALTER TABLE public.server_change_feed
  ALTER COLUMN key_data SET NOT NULL;

ALTER TABLE public.server_change_feed
  DROP CONSTRAINT IF EXISTS server_change_feed_entity_type_v2_check;
ALTER TABLE public.server_change_feed
  ADD CONSTRAINT server_change_feed_entity_type_v2_check CHECK (
    entity_type IN (
      'profile', 'area', 'room', 'asset', 'device_detail', 'pet_detail',
      'plant_detail', 'safety_detail', 'tag', 'asset_tag', 'asset_photo',
      'maintenance_plan', 'maintenance_plan_metadata', 'maintenance_record',
      'notification_inbox', 'user_setting', 'streak'
    )
  );
ALTER TABLE public.server_change_feed
  DROP CONSTRAINT IF EXISTS server_change_feed_key_data_object_check;
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
    EXECUTE format('DROP TRIGGER IF EXISTS trg_server_change_feed_%I ON public.%I;', tbl, tbl);
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
VALUES ('global', false, '2.0.0', 0, clock_timestamp())
ON CONFLICT (id) DO UPDATE SET
  enabled = false,
  capability_version = '2.0.0',
  updated_at = clock_timestamp();

CREATE OR REPLACE FUNCTION public.fetch_user_change_feed(
  p_since_seq BIGINT DEFAULT 0,
  p_limit INT DEFAULT 100
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID;
  v_high_water BIGINT;
  v_min_retained BIGINT;
  v_effective_limit INT;
  v_resnapshot_required BOOLEAN := false;
  v_changes JSONB;
  v_next_seq BIGINT;
  v_has_more BOOLEAN := false;
  v_cap_version TEXT;
  v_cap_enabled BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501';
  END IF;

  SELECT enabled, capability_version, min_retained_seq
  INTO v_cap_enabled, v_cap_version, v_min_retained
  FROM public.sync_feed_capabilities
  WHERE id = 'global';

  IF p_since_seq > 0 AND v_min_retained > 0 AND p_since_seq < v_min_retained THEN
    v_resnapshot_required := true;
  END IF;
  v_effective_limit := LEAST(GREATEST(p_limit, 1), 500);

  SELECT COALESCE(MAX(change_seq), 0)
  INTO v_high_water
  FROM public.server_change_feed
  WHERE user_id = v_user_id;

  WITH page_data AS (
    SELECT
      change_seq,
      entity_type,
      record_id,
      key_data,
      op_type,
      client_updated_at,
      revision,
      created_at
    FROM public.server_change_feed
    WHERE user_id = v_user_id
      AND change_seq > p_since_seq
      AND change_seq <= v_high_water
    ORDER BY change_seq ASC
    LIMIT v_effective_limit
  )
  SELECT
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'change_seq', change_seq,
          'entity_type', entity_type,
          'record_id', record_id,
          'key_data', key_data,
          'op_type', op_type,
          'client_updated_at', client_updated_at,
          'revision', revision,
          'created_at', created_at
        ) ORDER BY change_seq
      ),
      '[]'::jsonb
    ),
    COALESCE(MAX(change_seq), p_since_seq)
  INTO v_changes, v_next_seq
  FROM page_data;

  v_has_more := v_next_seq < v_high_water;
  RETURN jsonb_build_object(
    'changes', v_changes,
    'high_water_seq', v_high_water,
    'next_seq', v_next_seq,
    'has_more', v_has_more,
    'resnapshot_required', v_resnapshot_required,
    'capability_version', COALESCE(v_cap_version, '2.0.0'),
    'capability_enabled', COALESCE(v_cap_enabled, false)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fetch_user_change_feed(BIGINT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fetch_user_change_feed(BIGINT, INT) TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_change_feed_parity(p_user_id UUID DEFAULT NULL)
RETURNS TABLE (
  entity_type TEXT,
  canonical_count BIGINT,
  feed_net_count BIGINT,
  is_parity BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_target_user UUID;
BEGIN
  v_target_user := COALESCE(p_user_id, auth.uid());
  IF v_target_user IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH canonical_counts(entity, cnt) AS (
    SELECT 'profile', COUNT(*) FROM public.profiles WHERE user_id = v_target_user
    UNION ALL SELECT 'area', COUNT(*) FROM public.areas WHERE user_id = v_target_user
    UNION ALL SELECT 'room', COUNT(*) FROM public.rooms WHERE user_id = v_target_user
    UNION ALL SELECT 'asset', COUNT(*) FROM public.assets WHERE user_id = v_target_user
    UNION ALL SELECT 'device_detail', COUNT(*) FROM public.device_details WHERE user_id = v_target_user
    UNION ALL SELECT 'pet_detail', COUNT(*) FROM public.pet_details WHERE user_id = v_target_user
    UNION ALL SELECT 'plant_detail', COUNT(*) FROM public.plant_details WHERE user_id = v_target_user
    UNION ALL SELECT 'safety_detail', COUNT(*) FROM public.safety_details WHERE user_id = v_target_user
    UNION ALL SELECT 'tag', COUNT(*) FROM public.tags WHERE user_id = v_target_user
    UNION ALL SELECT 'asset_tag', COUNT(*) FROM public.asset_tags WHERE user_id = v_target_user
    UNION ALL SELECT 'asset_photo', COUNT(*) FROM public.asset_photos WHERE user_id = v_target_user
    UNION ALL SELECT 'maintenance_plan', COUNT(*) FROM public.maintenance_plans WHERE user_id = v_target_user
    UNION ALL SELECT 'maintenance_plan_metadata', COUNT(*) FROM public.maintenance_plan_metadata WHERE user_id = v_target_user
    UNION ALL SELECT 'maintenance_record', COUNT(*) FROM public.maintenance_records WHERE user_id = v_target_user
    UNION ALL SELECT 'notification_inbox', COUNT(*) FROM public.notification_inbox WHERE user_id = v_target_user
    UNION ALL SELECT 'user_setting', COUNT(*) FROM public.user_settings WHERE user_id = v_target_user
    UNION ALL SELECT 'streak', COUNT(*) FROM public.streaks WHERE user_id = v_target_user
  ),
  latest_feed AS (
    SELECT DISTINCT ON (entity_type, record_id)
      entity_type,
      record_id,
      op_type
    FROM public.server_change_feed
    WHERE user_id = v_target_user
    ORDER BY entity_type, record_id, change_seq DESC
  ),
  feed_counts AS (
    SELECT entity_type AS entity, COUNT(*) FILTER (WHERE op_type <> 'DELETE') AS cnt
    FROM latest_feed
    GROUP BY entity_type
  )
  SELECT
    c.entity,
    c.cnt,
    COALESCE(f.cnt, 0),
    c.cnt = COALESCE(f.cnt, 0)
  FROM canonical_counts c
  LEFT JOIN feed_counts f ON f.entity = c.entity;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.validate_change_feed_parity(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_change_feed_parity(UUID) TO authenticated;

COMMIT;
