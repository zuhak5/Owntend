BEGIN;

-- Keep privileged media mutations behind authenticated SECURITY INVOKER API
-- wrappers while moving the SECURITY DEFINER implementations out of the
-- exposed public schema.
CREATE SCHEMA IF NOT EXISTS owntend_media_private;
REVOKE ALL ON SCHEMA owntend_media_private FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA owntend_media_private TO authenticated, service_role;

ALTER FUNCTION public.stage_media_upload(TEXT, BIGINT, TEXT, TEXT)
  SET SCHEMA owntend_media_private;
ALTER FUNCTION owntend_media_private.stage_media_upload(TEXT, BIGINT, TEXT, TEXT)
  RENAME TO stage_media_upload_impl;
ALTER FUNCTION owntend_media_private.stage_media_upload_impl(TEXT, BIGINT, TEXT, TEXT)
  SET search_path TO '';
REVOKE ALL ON FUNCTION owntend_media_private.stage_media_upload_impl(TEXT, BIGINT, TEXT, TEXT)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION owntend_media_private.stage_media_upload_impl(TEXT, BIGINT, TEXT, TEXT)
TO authenticated;

CREATE FUNCTION public.stage_media_upload(
  p_staging_path TEXT,
  p_object_size BIGINT,
  p_mime_type TEXT,
  p_sha256_digest TEXT
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT owntend_media_private.stage_media_upload_impl(
    p_staging_path,
    p_object_size,
    p_mime_type,
    p_sha256_digest
  );
$$;
REVOKE ALL ON FUNCTION public.stage_media_upload(TEXT, BIGINT, TEXT, TEXT)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.stage_media_upload(TEXT, BIGINT, TEXT, TEXT)
TO authenticated;

ALTER FUNCTION public.finalize_asset_photo_upload(UUID, TEXT, TEXT, INT)
  SET SCHEMA owntend_media_private;
ALTER FUNCTION owntend_media_private.finalize_asset_photo_upload(UUID, TEXT, TEXT, INT)
  RENAME TO finalize_asset_photo_upload_impl;
ALTER FUNCTION owntend_media_private.finalize_asset_photo_upload_impl(UUID, TEXT, TEXT, INT)
  SET search_path TO '';
REVOKE ALL ON FUNCTION owntend_media_private.finalize_asset_photo_upload_impl(UUID, TEXT, TEXT, INT)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION owntend_media_private.finalize_asset_photo_upload_impl(UUID, TEXT, TEXT, INT)
TO authenticated;

CREATE FUNCTION public.finalize_asset_photo_upload(
  p_staging_id UUID,
  p_asset_id TEXT,
  p_photo_id TEXT,
  p_expected_revision INT DEFAULT 1
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT owntend_media_private.finalize_asset_photo_upload_impl(
    p_staging_id,
    p_asset_id,
    p_photo_id,
    p_expected_revision
  );
$$;
REVOKE ALL ON FUNCTION public.finalize_asset_photo_upload(UUID, TEXT, TEXT, INT)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.finalize_asset_photo_upload(UUID, TEXT, TEXT, INT)
TO authenticated;

ALTER FUNCTION public.set_primary_asset_photo(TEXT, TEXT)
  SET SCHEMA owntend_media_private;
ALTER FUNCTION owntend_media_private.set_primary_asset_photo(TEXT, TEXT)
  RENAME TO set_primary_asset_photo_impl;
ALTER FUNCTION owntend_media_private.set_primary_asset_photo_impl(TEXT, TEXT)
  SET search_path TO '';
REVOKE ALL ON FUNCTION owntend_media_private.set_primary_asset_photo_impl(TEXT, TEXT)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION owntend_media_private.set_primary_asset_photo_impl(TEXT, TEXT)
TO authenticated;

CREATE FUNCTION public.set_primary_asset_photo(
  p_asset_id TEXT,
  p_photo_id TEXT
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT owntend_media_private.set_primary_asset_photo_impl(
    p_asset_id,
    p_photo_id
  );
$$;
REVOKE ALL ON FUNCTION public.set_primary_asset_photo(TEXT, TEXT)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_primary_asset_photo(TEXT, TEXT)
TO authenticated;

-- The charged-operation status RPC also needs elevated access to the private
-- operation journal. Keep that authority in the already-private monetization
-- schema and expose only an invoker wrapper.
CREATE OR REPLACE FUNCTION owntend_monetization_private.get_charged_operation_status_hash_qualified_impl(
  p_operation_id UUID,
  p_request_hash TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id UUID := auth.uid();
  normalized_hash TEXT := LOWER(NULLIF(BTRIM(p_request_hash), ''));
  stored_hash TEXT;
  result JSONB;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;

  IF p_operation_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION_ID';
  END IF;

  IF normalized_hash IS NULL OR normalized_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_REQUEST_HASH';
  END IF;

  SELECT client_request_hash
  INTO stored_hash
  FROM public.creation_point_operations
  WHERE operation_id = p_operation_id
    AND user_id = caller_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'status', 'not_found',
      'operation_id', p_operation_id,
      'capability_version', '1.2.0'
    );
  END IF;

  IF stored_hash IS NULL OR stored_hash <> normalized_hash THEN
    RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
  END IF;

  result := owntend_monetization_private.get_charged_operation_status(
    p_operation_id,
    NULL
  );

  RETURN jsonb_set(
    result,
    '{capability_version}',
    to_jsonb('1.2.0'::TEXT),
    true
  );
END;
$$;
REVOKE ALL ON FUNCTION owntend_monetization_private.get_charged_operation_status_hash_qualified_impl(UUID, TEXT)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.get_charged_operation_status_hash_qualified_impl(UUID, TEXT)
TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_charged_operation_status(
  p_operation_id UUID,
  p_request_hash TEXT
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT owntend_monetization_private.get_charged_operation_status_hash_qualified_impl(
    p_operation_id,
    p_request_hash
  );
$$;
REVOKE ALL ON FUNCTION public.get_charged_operation_status(UUID, TEXT)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_charged_operation_status(UUID, TEXT)
TO authenticated, service_role;

-- Supabase recommends wrapping statement-stable auth helpers in SELECT so
-- PostgreSQL evaluates them once per statement instead of once per row.
DO $$
DECLARE
  v_table TEXT;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'areas',
    'rooms',
    'assets',
    'device_details',
    'pet_details',
    'plant_details',
    'safety_details',
    'tags',
    'asset_tags',
    'asset_photos',
    'maintenance_plan_metadata',
    'maintenance_records',
    'notifications',
    'notification_inbox',
    'user_settings',
    'streaks',
    'profiles'
  ]
  LOOP
    EXECUTE format(
      'ALTER POLICY %I ON public.%I USING ((SELECT auth.uid()) = user_id)',
      v_table || '_select_own',
      v_table
    );
    EXECUTE format(
      'ALTER POLICY %I ON public.%I WITH CHECK ((SELECT auth.uid()) = user_id)',
      v_table || '_insert_own',
      v_table
    );
    EXECUTE format(
      'ALTER POLICY %I ON public.%I USING ((SELECT auth.uid()) = user_id) WITH CHECK ((SELECT auth.uid()) = user_id)',
      v_table || '_update_own',
      v_table
    );
    EXECUTE format(
      'ALTER POLICY %I ON public.%I USING ((SELECT auth.uid()) = user_id)',
      v_table || '_delete_own',
      v_table
    );
  END LOOP;
END;
$$;

ALTER POLICY maintenance_plans_select_own ON public.maintenance_plans
  USING ((SELECT auth.uid()) = user_id);
ALTER POLICY maintenance_plans_update_own ON public.maintenance_plans
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);
ALTER POLICY maintenance_plans_delete_own ON public.maintenance_plans
  USING ((SELECT auth.uid()) = user_id);
ALTER POLICY maintenance_plans_insert_own ON public.maintenance_plans
  WITH CHECK (
    (SELECT auth.uid()) = user_id
    AND (
      owntend_monetization_private.can_reconcile_maintenance_plan(user_id, id)
      OR (SELECT current_setting('owntend.completion_plan_insert', true)) = 'true'
    )
  );

ALTER POLICY "Users can manage their own staging objects" ON public.media_staging_objects
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));
ALTER POLICY "Users can view their own cleanup entries" ON public.media_cleanup_queue
  USING (user_id = (SELECT auth.uid()));
ALTER POLICY "Users can only select their own change feed" ON public.server_change_feed
  USING ((SELECT auth.uid()) = user_id);
ALTER POLICY point_wallets_select_own ON public.point_wallets
  USING ((SELECT auth.uid()) = user_id);
ALTER POLICY point_transactions_select_own ON public.point_transactions
  USING ((SELECT auth.uid()) = user_id);
ALTER POLICY reward_claim_requests_select_own ON public.reward_claim_requests
  USING ((SELECT auth.uid()) = user_id);

-- Cover the composite notification foreign key reported by the Performance
-- Advisor. This also supports owner/plan lookups used during reconciliation.
CREATE INDEX IF NOT EXISTS notifications_user_id_plan_id_idx
  ON public.notifications(user_id, plan_id);

COMMIT;
