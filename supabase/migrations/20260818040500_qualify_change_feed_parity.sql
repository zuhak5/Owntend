BEGIN;

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

REVOKE EXECUTE ON FUNCTION public.validate_change_feed_parity(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_change_feed_parity(UUID) TO authenticated;

COMMIT;
