-- Explicit RPC execute-privilege hardening for SECURITY DEFINER entry points.
--
-- PostgreSQL grants EXECUTE on every new function to PUBLIC by default. The
-- consolidated baseline revokes or narrows most surfaces, but the hosted
-- Supabase security advisor kept flagging twelve public SECURITY DEFINER
-- functions as executable by anon and/or authenticated because their ACLs
-- were shaped implicitly instead of being stated outright. This migration
-- makes the boundary explicit and idempotent so the deployed state, the
-- runtime denial behavior, and the advisor view agree:
--
--   * Media-cleanup worker RPCs are service_role-only capabilities.
--   * Authenticated application RPCs are reachable by authenticated callers
--     and by trusted server-side roles, never by anon or PUBLIC.

REVOKE EXECUTE ON FUNCTION "public"."claim_media_cleanup_batch"("p_batch_size" integer)
  FROM PUBLIC, "anon", "authenticated";
REVOKE EXECUTE ON FUNCTION "public"."acknowledge_media_cleanup"("p_id" bigint)
  FROM PUBLIC, "anon", "authenticated";
REVOKE EXECUTE ON FUNCTION "public"."record_media_cleanup_failure"("p_id" bigint, "p_error_code" text, "p_terminal" boolean)
  FROM PUBLIC, "anon", "authenticated";

REVOKE EXECUTE ON FUNCTION "public"."prepare_asset_photo_upload"("p_asset_id" "text", "p_photo_id" "text", "p_object_size" bigint, "p_mime_type" "text", "p_client_sha256_digest" "text", "p_idempotency_key" "text")
  FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION "public"."finalize_asset_photo_upload"("p_staging_id" "uuid", "p_asset_id" "text", "p_photo_id" "text", "p_expected_revision" integer, "p_caption" "text", "p_is_primary" boolean)
  FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION "public"."delete_asset_photo"("p_asset_id" "text", "p_photo_id" "text")
  FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION "public"."set_primary_asset_photo"("p_asset_id" "text", "p_photo_id" "text")
  FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION "public"."create_asset"("p_operation" "jsonb")
  FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION "public"."create_task_with_point_debit"("p_operation" "jsonb")
  FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION "public"."create_reward_claim_request"("p_reward_type" "text", "p_time_zone" "text")
  FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION "public"."get_charged_operation_status"("p_operation_id" "uuid", "p_request_hash" "text")
  FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION "public"."record_monetization_event"("p_event_name" "text", "p_properties" "jsonb")
  FROM PUBLIC, "anon";

GRANT EXECUTE ON FUNCTION "public"."prepare_asset_photo_upload"("p_asset_id" "text", "p_photo_id" "text", "p_object_size" bigint, "p_mime_type" "text", "p_client_sha256_digest" "text", "p_idempotency_key" "text")
  TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION "public"."finalize_asset_photo_upload"("p_staging_id" "uuid", "p_asset_id" "text", "p_photo_id" "text", "p_expected_revision" integer, "p_caption" "text", "p_is_primary" boolean)
  TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION "public"."delete_asset_photo"("p_asset_id" "text", "p_photo_id" "text")
  TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION "public"."set_primary_asset_photo"("p_asset_id" "text", "p_photo_id" "text")
  TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION "public"."create_asset"("p_operation" "jsonb")
  TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION "public"."create_task_with_point_debit"("p_operation" "jsonb")
  TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION "public"."create_reward_claim_request"("p_reward_type" "text", "p_time_zone" "text")
  TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION "public"."get_charged_operation_status"("p_operation_id" "uuid", "p_request_hash" "text")
  TO "authenticated", "service_role";
GRANT EXECUTE ON FUNCTION "public"."record_monetization_event"("p_event_name" "text", "p_properties" "jsonb")
  TO "authenticated", "service_role";
