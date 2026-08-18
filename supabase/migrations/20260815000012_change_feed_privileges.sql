-- Finalize the pre-launch change-feed contract and Data API boundary.
-- Client-facing feed RPCs are SECURITY INVOKER, derive ownership from auth.uid(),
-- and are executable only by authenticated. Trigger logging remains SECURITY
-- DEFINER but is not directly callable by Data API roles.
--
-- Existing Supabase projects can retain automatic Data API function grants.
-- Do not rely on default-privilege changes alone: every function below receives
-- an explicit post-definition REVOKE followed by the minimum required GRANT.

BEGIN;

-- This is the only shipped pre-launch feed contract. Earlier audit iterations
-- were never released, so the hardened contract starts at protocol 1.0.0.
UPDATE public.sync_feed_capabilities
SET capability_version = '1.0.0',
    enabled = false,
    updated_at = clock_timestamp()
WHERE id = 'global';

ALTER TABLE public.server_change_feed
  RENAME CONSTRAINT server_change_feed_entity_type_v2_check
  TO server_change_feed_entity_type_check;

CREATE OR REPLACE FUNCTION public.get_sync_feed_capability()
RETURNS TABLE (
  enabled BOOLEAN,
  capability_version TEXT,
  min_retained_seq BIGINT
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT
    c.enabled,
    c.capability_version,
    c.min_retained_seq
  FROM public.sync_feed_capabilities AS c
  WHERE c.id = 'global';
$$;

REVOKE ALL ON FUNCTION public.get_sync_feed_capability()
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_sync_feed_capability()
TO authenticated;

CREATE OR REPLACE FUNCTION public.fetch_user_change_feed(
  p_since_seq BIGINT DEFAULT 0,
  p_limit INT DEFAULT 100
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
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

  SELECT c.enabled, c.capability_version, c.min_retained_seq
  INTO v_cap_enabled, v_cap_version, v_min_retained
  FROM public.sync_feed_capabilities AS c
  WHERE c.id = 'global';

  IF p_since_seq > 0 AND v_min_retained > 0 AND p_since_seq < v_min_retained THEN
    v_resnapshot_required := true;
  END IF;
  v_effective_limit := LEAST(GREATEST(p_limit, 1), 500);

  SELECT COALESCE(MAX(sf.change_seq), 0)
  INTO v_high_water
  FROM public.server_change_feed AS sf
  WHERE sf.user_id = v_user_id;

  WITH page_data AS (
    SELECT
      sf.change_seq,
      sf.entity_type,
      sf.record_id,
      sf.key_data,
      sf.op_type,
      sf.client_updated_at,
      sf.revision,
      sf.created_at
    FROM public.server_change_feed AS sf
    WHERE sf.user_id = v_user_id
      AND sf.change_seq > p_since_seq
      AND sf.change_seq <= v_high_water
    ORDER BY sf.change_seq ASC
    LIMIT v_effective_limit
  )
  SELECT
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'change_seq', page_data.change_seq,
          'entity_type', page_data.entity_type,
          'record_id', page_data.record_id,
          'key_data', page_data.key_data,
          'op_type', page_data.op_type,
          'client_updated_at', page_data.client_updated_at,
          'revision', page_data.revision,
          'created_at', page_data.created_at
        ) ORDER BY page_data.change_seq
      ),
      '[]'::jsonb
    ),
    COALESCE(MAX(page_data.change_seq), p_since_seq)
  INTO v_changes, v_next_seq
  FROM page_data;

  v_has_more := v_next_seq < v_high_water;
  RETURN jsonb_build_object(
    'changes', v_changes,
    'high_water_seq', v_high_water,
    'next_seq', v_next_seq,
    'has_more', v_has_more,
    'resnapshot_required', v_resnapshot_required,
    'capability_version', COALESCE(v_cap_version, '1.0.0'),
    'capability_enabled', COALESCE(v_cap_enabled, false)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fetch_user_change_feed(BIGINT, INT)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fetch_user_change_feed(BIGINT, INT)
TO authenticated;

-- The mobile healing scan calls this RPC without parameters; ownership is
-- always the authenticated account rather than a caller-selected user id.
DROP FUNCTION IF EXISTS public.validate_change_feed_parity(UUID);

CREATE FUNCTION public.validate_change_feed_parity()
RETURNS TABLE (
  entity_type TEXT,
  canonical_count BIGINT,
  feed_net_count BIGINT,
  is_parity BOOLEAN
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_target_user UUID := auth.uid();
BEGIN
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
    SELECT DISTINCT ON (sf.entity_type, sf.record_id)
      sf.entity_type,
      sf.record_id,
      sf.op_type
    FROM public.server_change_feed AS sf
    WHERE sf.user_id = v_target_user
    ORDER BY sf.entity_type, sf.record_id, sf.change_seq DESC
  ),
  feed_counts AS (
    SELECT
      lf.entity_type AS entity,
      COUNT(*) FILTER (WHERE lf.op_type <> 'DELETE') AS cnt
    FROM latest_feed AS lf
    GROUP BY lf.entity_type
  )
  SELECT
    c.entity,
    c.cnt,
    COALESCE(f.cnt, 0),
    c.cnt = COALESCE(f.cnt, 0)
  FROM canonical_counts AS c
  LEFT JOIN feed_counts AS f ON f.entity = c.entity;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_change_feed_parity()
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.validate_change_feed_parity()
TO authenticated;

-- Watermark inspection is likewise owner-scoped. Operational cross-account
-- inspection belongs to protected SQL tooling, not a client-callable RPC.
DROP FUNCTION IF EXISTS public.get_user_change_feed_watermark(UUID);

CREATE FUNCTION public.get_user_change_feed_watermark()
RETURNS TABLE (
  min_change_seq BIGINT,
  max_change_seq BIGINT,
  total_changes BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_target_user UUID := auth.uid();
BEGIN
  IF v_target_user IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    COALESCE(MIN(sf.change_seq), 0),
    COALESCE(MAX(sf.change_seq), 0),
    COUNT(*)
  FROM public.server_change_feed AS sf
  WHERE sf.user_id = v_target_user;
END;
$$;

REVOKE ALL ON FUNCTION public.get_user_change_feed_watermark()
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_user_change_feed_watermark()
TO authenticated;

-- Trigger execution does not require client EXECUTE privilege. Keep the
-- SECURITY DEFINER trigger implementation private to the trigger mechanism.
REVOKE ALL ON FUNCTION public.fn_log_server_change_feed()
FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
