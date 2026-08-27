DROP FUNCTION public.validate_change_feed_parity();

CREATE FUNCTION public.validate_change_feed_parity(p_user_id uuid)
RETURNS TABLE(
  entity_type text,
  canonical_count bigint,
  feed_net_count bigint,
  is_parity boolean
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  -- SECURITY INVOKER deliberately avoids granting service_role direct access to
  -- auth.users. Profiles are created transactionally for every application user
  -- and are the least-privilege public account anchor available to this operator.
  IF p_user_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE user_id = p_user_id
  ) THEN
    RAISE EXCEPTION USING errcode = 'P0002', message = 'TARGET_USER_NOT_FOUND';
  END IF;

  RETURN QUERY
  WITH canonical_counts(entity, cnt) AS (
    SELECT 'profile', count(*) FROM public.profiles WHERE user_id = p_user_id
    UNION ALL SELECT 'area', count(*) FROM public.areas WHERE user_id = p_user_id
    UNION ALL SELECT 'room', count(*) FROM public.rooms WHERE user_id = p_user_id
    UNION ALL SELECT 'asset', count(*) FROM public.assets WHERE user_id = p_user_id
    UNION ALL SELECT 'device_detail', count(*) FROM public.device_details WHERE user_id = p_user_id
    UNION ALL SELECT 'pet_detail', count(*) FROM public.pet_details WHERE user_id = p_user_id
    UNION ALL SELECT 'plant_detail', count(*) FROM public.plant_details WHERE user_id = p_user_id
    UNION ALL SELECT 'safety_detail', count(*) FROM public.safety_details WHERE user_id = p_user_id
    UNION ALL SELECT 'tag', count(*) FROM public.tags WHERE user_id = p_user_id
    UNION ALL SELECT 'asset_tag', count(*) FROM public.asset_tags WHERE user_id = p_user_id
    UNION ALL SELECT 'asset_photo', count(*) FROM public.asset_photos WHERE user_id = p_user_id
    UNION ALL SELECT 'maintenance_plan', count(*) FROM public.maintenance_plans WHERE user_id = p_user_id
    UNION ALL SELECT 'maintenance_plan_metadata', count(*) FROM public.maintenance_plan_metadata WHERE user_id = p_user_id
    UNION ALL SELECT 'maintenance_record', count(*) FROM public.maintenance_records WHERE user_id = p_user_id
    UNION ALL SELECT 'notification_inbox', count(*) FROM public.notification_inbox WHERE user_id = p_user_id
    UNION ALL SELECT 'user_setting', count(*) FROM public.user_settings WHERE user_id = p_user_id
    UNION ALL SELECT 'streak', count(*) FROM public.streaks WHERE user_id = p_user_id
  ), latest_feed AS (
    SELECT DISTINCT ON (sf.entity_type, sf.record_id)
      sf.entity_type, sf.record_id, sf.op_type
    FROM public.server_change_feed sf
    WHERE sf.user_id = p_user_id
    ORDER BY sf.entity_type, sf.record_id, sf.change_seq DESC
  ), feed_counts AS (
    SELECT lf.entity_type AS entity,
           count(*) FILTER (WHERE lf.op_type <> 'DELETE') AS cnt
    FROM latest_feed lf
    GROUP BY lf.entity_type
  )
  SELECT c.entity, c.cnt, COALESCE(f.cnt, 0), c.cnt = COALESCE(f.cnt, 0)
  FROM canonical_counts c
  LEFT JOIN feed_counts f ON f.entity = c.entity;
END;
$$;

ALTER FUNCTION public.validate_change_feed_parity(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.validate_change_feed_parity(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_change_feed_parity(uuid) TO service_role;
