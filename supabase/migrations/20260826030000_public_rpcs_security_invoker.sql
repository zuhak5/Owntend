-- Public RPC entry points become SECURITY INVOKER delegation wrappers.
--
-- The hosted security advisor (splinter lint 0029) flags every SECURITY
-- DEFINER function that the authenticated role can execute inside the
-- PostgREST-exposed schemas. The nine server-authoritative application RPCs
-- below must stay callable by signed-in users, so the elevation boundary
-- moves out of the exposed schema entirely:
--
--   * `public.<rpc>` becomes a SECURITY INVOKER wrapper whose body only
--     performs the authentication guard and delegates to the private
--     implementation. It holds no elevated authority itself.
--   * `owntend_media_private.<rpc>_impl` /
--     `owntend_monetization_private.<rpc>_impl` remain SECURITY DEFINER,
--     owned by postgres, pinned to an empty search_path, and invisible to
--     the advisor because their schemas are not exposed through PostgREST.
--
-- Callers need EXECUTE on both layers, so the implementations are granted to
-- `authenticated` and `service_role`; anon and PUBLIC stay revoked on both.
-- Runtime behavior is unchanged: the wrappers previously ran as definer but
-- only evaluated `auth.uid()` and forwarded arguments.

CREATE OR REPLACE FUNCTION public.prepare_asset_photo_upload(p_asset_id text, p_photo_id text, p_object_size bigint, p_mime_type text, p_client_sha256_digest text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  END IF;
  RETURN owntend_media_private.prepare_asset_photo_upload_impl(
    p_asset_id, p_photo_id, p_object_size, p_mime_type,
    p_client_sha256_digest, p_idempotency_key
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.finalize_asset_photo_upload(p_staging_id uuid, p_asset_id text, p_photo_id text, p_expected_revision integer DEFAULT 1, p_caption text DEFAULT NULL::text, p_is_primary boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  END IF;
  RETURN owntend_media_private.finalize_asset_photo_upload_impl(
    p_staging_id,
    p_asset_id,
    p_photo_id,
    p_expected_revision,
    p_caption,
    p_is_primary
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_asset_photo(p_asset_id text, p_photo_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  END IF;
  RETURN owntend_media_private.delete_asset_photo_impl(p_asset_id, p_photo_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_primary_asset_photo(p_asset_id text, p_photo_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  END IF;
  RETURN owntend_media_private.set_primary_asset_photo_impl(
    p_asset_id,
    p_photo_id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_asset(p_operation jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.create_asset_impl(p_operation);
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_task_with_point_debit(p_operation jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.create_task_with_point_debit_impl(p_operation);
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_reward_claim_request(p_reward_type text, p_time_zone text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.create_reward_claim_request_impl(
    p_reward_type,
    p_time_zone
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_charged_operation_status(p_operation_id uuid, p_request_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.get_charged_operation_status(
    p_operation_id,
    p_request_hash
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_monetization_event(p_event_name text, p_properties jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  PERFORM owntend_monetization_private.record_monetization_event_impl(
    p_event_name,
    p_properties
  );
END;
$function$;

-- Restate the public wrapper boundary: reachable by authenticated callers
-- and trusted server-side roles, never by anon or PUBLIC.
REVOKE EXECUTE ON FUNCTION public.prepare_asset_photo_upload(text, text, bigint, text, text, text) FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION public.finalize_asset_photo_upload(uuid, text, text, integer, text, boolean) FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION public.delete_asset_photo(text, text) FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION public.set_primary_asset_photo(text, text) FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION public.create_asset(jsonb) FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION public.create_task_with_point_debit(jsonb) FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION public.create_reward_claim_request(text, text) FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION public.get_charged_operation_status(uuid, text) FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION public.record_monetization_event(text, jsonb) FROM PUBLIC, "anon";

GRANT EXECUTE ON FUNCTION public.prepare_asset_photo_upload(text, text, bigint, text, text, text) TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION public.finalize_asset_photo_upload(uuid, text, text, integer, text, boolean) TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION public.delete_asset_photo(text, text) TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION public.set_primary_asset_photo(text, text) TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION public.create_asset(jsonb) TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION public.create_task_with_point_debit(jsonb) TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION public.create_reward_claim_request(text, text) TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION public.get_charged_operation_status(uuid, text) TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION public.record_monetization_event(text, jsonb) TO "authenticated", "service_role";

-- Invoker wrappers execute with caller privileges, so callers must also hold
-- EXECUTE on the privileged implementations they delegate to, plus USAGE on
-- the owning schemas. The advisor does not inspect these schemas because
-- PostgREST never exposes them.
GRANT USAGE ON SCHEMA owntend_media_private TO "authenticated", "service_role";
GRANT USAGE ON SCHEMA owntend_monetization_private TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION owntend_media_private.prepare_asset_photo_upload_impl(text, text, bigint, text, text, text) TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION owntend_media_private.finalize_asset_photo_upload_impl(uuid, text, text, integer, text, boolean) TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION owntend_media_private.delete_asset_photo_impl(text, text) TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION owntend_media_private.set_primary_asset_photo_impl(text, text) TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION owntend_monetization_private.create_asset_impl(jsonb) TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION owntend_monetization_private.create_task_with_point_debit_impl(jsonb) TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION owntend_monetization_private.create_reward_claim_request_impl(text, text) TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION owntend_monetization_private.get_charged_operation_status(uuid, text) TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION owntend_monetization_private.record_monetization_event_impl(text, jsonb) TO "authenticated", "service_role";
