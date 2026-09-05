


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "owntend_media_private";


ALTER SCHEMA "owntend_media_private" OWNER TO "postgres";


CREATE SCHEMA IF NOT EXISTS "owntend_monetization_private";


ALTER SCHEMA "owntend_monetization_private" OWNER TO "postgres";


CREATE SCHEMA IF NOT EXISTS "owntend_private";


ALTER SCHEMA "owntend_private" OWNER TO "postgres";


CREATE SCHEMA IF NOT EXISTS "owntend_security";


ALTER SCHEMA "owntend_security" OWNER TO "postgres";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "owntend_media_private"."acknowledge_media_cleanup"("p_id" bigint) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  DELETE FROM public.media_cleanup_queue
  WHERE id = p_id;
  RETURN true;
END;
$$;


ALTER FUNCTION "owntend_media_private"."acknowledge_media_cleanup"("p_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_media_private"."claim_media_cleanup_batch"("p_batch_size" integer DEFAULT 25) RETURNS TABLE("id" bigint, "user_id" "uuid", "object_path" "text", "attempts" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN QUERY
  WITH claimed AS (
    SELECT q.id
    FROM public.media_cleanup_queue q
    WHERE q.status IN ('pending', 'processing')
      AND (q.processed_at IS NULL OR q.processed_at <= clock_timestamp() - interval '5 minutes')
    ORDER BY q.created_at
    -- The worker budget assumes small batches; the hard cap keeps a single
    -- invocation bounded regardless of the caller-provided size.
    LIMIT least(p_batch_size, 25)
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.media_cleanup_queue q
  SET status = 'processing',
      attempts = q.attempts + 1,
      processed_at = clock_timestamp()
  FROM claimed
  WHERE q.id = claimed.id
  RETURNING q.id, q.user_id, q.object_path, q.attempts;
END;
$$;


ALTER FUNCTION "owntend_media_private"."claim_media_cleanup_batch"("p_batch_size" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_media_private"."delete_asset_photo_impl"("p_asset_id" "text", "p_photo_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_photo public.asset_photos%rowtype;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.asset_photos
  WHERE user_id = v_user_id AND asset_id = p_asset_id AND id = p_photo_id
  RETURNING * INTO v_photo;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', true, 'idempotent', true, 'photo_id', p_photo_id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'idempotent', false,
    'photo_id', p_photo_id,
    'object_path', v_photo.object_path
  );
END;
$$;


ALTER FUNCTION "owntend_media_private"."delete_asset_photo_impl"("p_asset_id" "text", "p_photo_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_media_private"."finalize_asset_photo_upload_impl"("p_staging_id" "uuid", "p_asset_id" "text", "p_photo_id" "text", "p_expected_revision" integer DEFAULT 1, "p_caption" "text" DEFAULT NULL::"text", "p_is_primary" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_stage public.media_staging_objects%rowtype;
  v_photo public.asset_photos%rowtype;
  v_object_metadata jsonb;
  v_object_size bigint;
  v_object_mime text;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  select * into v_stage from public.media_staging_objects
  where id = p_staging_id and user_id = v_user_id for update;
  if not found or v_stage.asset_id is distinct from p_asset_id
    or v_stage.photo_id is distinct from p_photo_id
  then
    raise exception 'MEDIA_STAGE_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into v_photo from public.asset_photos
  where user_id = v_user_id and id = p_photo_id for update;
  if v_stage.status = 'finalized' then
    if v_photo.object_path is distinct from v_stage.staging_path then
      raise exception 'MEDIA_FINALIZATION_CONFLICT' using errcode = '23505';
    end if;
    return jsonb_build_object(
      'success', true,
      'idempotent', true,
      'photo_id', p_photo_id,
      'asset_id', p_asset_id,
      'object_path', v_photo.object_path,
      'caption', v_photo.caption,
      'is_primary', v_photo.is_primary,
      'revision', v_photo.revision
    );
  end if;
  if v_stage.expires_at <= clock_timestamp() then
    raise exception 'MEDIA_STAGE_EXPIRED' using errcode = '55000';
  end if;
  select metadata into v_object_metadata from storage.objects
  where bucket_id = 'user-media' and name = v_stage.staging_path;
  if not found then
    raise exception 'MEDIA_OBJECT_NOT_FOUND' using errcode = 'P0002';
  end if;
  begin
    v_object_size := nullif(v_object_metadata ->> 'size', '')::bigint;
  exception when others then
    raise exception 'MEDIA_OBJECT_METADATA_INVALID' using errcode = '22023';
  end;
  v_object_mime := coalesce(
    nullif(v_object_metadata ->> 'mimetype', ''),
    nullif(v_object_metadata ->> 'contentType', '')
  );
  if v_object_size is distinct from v_stage.object_size
    or v_object_mime is distinct from v_stage.mime_type
  then
    raise exception 'MEDIA_OBJECT_FACTS_MISMATCH' using errcode = '22023';
  end if;
  if v_photo.id is not null then
    if v_photo.asset_id is distinct from p_asset_id
      or (p_expected_revision is not null and v_photo.revision is distinct from p_expected_revision)
    then
      raise exception 'MEDIA_PHOTO_CONFLICT' using errcode = '23505';
    end if;
    if v_photo.object_path is not null and v_photo.object_path <> v_stage.staging_path then
      insert into public.media_cleanup_queue(user_id, object_path, reason)
      values (v_user_id, v_photo.object_path, 'replaced');
    end if;
  end if;

  if coalesce(p_is_primary, false) then
    update public.asset_photos
    set is_primary = false, revision = revision + 1, updated_at = clock_timestamp()
    where user_id = v_user_id and asset_id = p_asset_id and id <> p_photo_id and is_primary = true;
  end if;

  insert into public.asset_photos(
    id, asset_id, user_id, object_path, caption, is_primary, revision, created_at, updated_at
  ) values (
    p_photo_id, p_asset_id, v_user_id, v_stage.staging_path, p_caption, coalesce(p_is_primary, false),
    coalesce(p_expected_revision, 1), clock_timestamp(), clock_timestamp()
  ) on conflict (user_id, id) do update set
    object_path = excluded.object_path,
    caption = coalesce(excluded.caption, asset_photos.caption),
    is_primary = case when excluded.is_primary then true else asset_photos.is_primary end,
    revision = case when asset_photos.object_path is distinct from excluded.object_path
      then asset_photos.revision + 1 else asset_photos.revision end,
    updated_at = clock_timestamp();

  update public.media_staging_objects
  set status = 'finalized', finalized_at = clock_timestamp()
  where id = p_staging_id;

  return jsonb_build_object(
    'success', true,
    'idempotent', false,
    'photo_id', p_photo_id,
    'asset_id', p_asset_id,
    'object_path', v_stage.staging_path,
    'caption', p_caption,
    'is_primary', coalesce(p_is_primary, false),
    'revision', coalesce(p_expected_revision, 1),
    'verified_size', v_object_size,
    'verified_mime_type', v_object_mime,
    'digest_verification', 'client_advisory'
  );
end;
$$;


ALTER FUNCTION "owntend_media_private"."finalize_asset_photo_upload_impl"("p_staging_id" "uuid", "p_asset_id" "text", "p_photo_id" "text", "p_expected_revision" integer, "p_caption" "text", "p_is_primary" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_media_private"."fn_enqueue_deleted_photo_cleanup"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  IF OLD.object_path IS NULL THEN
    RETURN OLD;
  END IF;
  -- During auth-user deletion cascades the owner row is already gone, so
  -- queueing would violate the ownership foreign key and deleting the user
  -- would otherwise fail. Account removal cleans storage through its own
  -- dedicated owntend_private.account_deletion_cleanup_jobs workflow instead.
  IF NOT EXISTS (
    SELECT 1 FROM "auth"."users" WHERE "id" = OLD."user_id"
  ) THEN
    RETURN OLD;
  END IF;
  INSERT INTO public.media_cleanup_queue(user_id, object_path, reason)
  VALUES (OLD.user_id, OLD.object_path, 'deleted');
  RETURN OLD;
END;
$$;


ALTER FUNCTION "owntend_media_private"."fn_enqueue_deleted_photo_cleanup"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_media_private"."prepare_asset_photo_upload_impl"("p_asset_id" "text", "p_photo_id" "text", "p_object_size" bigint, "p_mime_type" "text", "p_client_sha256_digest" "text", "p_idempotency_key" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
DECLARE
  v_user_id uuid := auth.uid();
  v_stage public.media_staging_objects%ROWTYPE;
  v_candidate_id uuid := gen_random_uuid();
  v_extension text;
  v_active_count integer;
  v_active_bytes bigint;
  v_old_path text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.assets
    WHERE user_id = v_user_id AND id = p_asset_id AND archived_at IS NULL
  ) THEN
    RAISE EXCEPTION USING errcode = 'P0002', message = 'ASSET_NOT_FOUND';
  END IF;
  IF p_photo_id IS NULL OR char_length(p_photo_id) NOT BETWEEN 1 AND 120
     OR p_object_size NOT BETWEEN 1 AND 10485760
     OR p_mime_type NOT IN ('image/jpeg', 'image/png', 'image/webp')
     OR p_client_sha256_digest !~ '^[0-9a-f]{64}$'
     OR p_idempotency_key !~ '^[A-Za-z0-9_-]{16,120}$' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_MEDIA_STAGE';
  END IF;
  v_extension := CASE p_mime_type
    WHEN 'image/jpeg' THEN 'jpg'
    WHEN 'image/png' THEN 'png'
    ELSE 'webp'
  END;

  -- A single transaction-scoped per-user lock makes both row-count and byte
  -- quotas exact under concurrent distinct idempotency keys.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user_id::text || ':media_stage_quota', 0)
  );

  INSERT INTO public.media_staging_objects (
    id, user_id, staging_path, object_size, mime_type,
    client_sha256_digest, idempotency_key, asset_id, photo_id,
    status, attempt, created_at, expires_at
  ) VALUES (
    v_candidate_id,
    v_user_id,
    v_user_id::text || '/media/' || v_candidate_id::text || '/0.' || v_extension,
    p_object_size,
    p_mime_type,
    p_client_sha256_digest,
    p_idempotency_key,
    p_asset_id,
    p_photo_id,
    'staged',
    0,
    clock_timestamp(),
    clock_timestamp() + interval '1 day'
  )
  ON CONFLICT (user_id, idempotency_key) DO NOTHING;

  SELECT * INTO v_stage
  FROM public.media_staging_objects
  WHERE user_id = v_user_id AND idempotency_key = p_idempotency_key
  FOR UPDATE;
  IF v_stage.asset_id IS DISTINCT FROM p_asset_id
     OR v_stage.photo_id IS DISTINCT FROM p_photo_id
     OR v_stage.object_size IS DISTINCT FROM p_object_size
     OR v_stage.mime_type IS DISTINCT FROM p_mime_type
     OR v_stage.client_sha256_digest IS DISTINCT FROM p_client_sha256_digest THEN
    RAISE EXCEPTION USING errcode = '23505', message = 'MEDIA_IDEMPOTENCY_CONFLICT';
  END IF;

  IF v_stage.status = 'finalized' THEN
    RETURN jsonb_build_object(
      'staging_id', v_stage.id, 'status', v_stage.status,
      'staging_path', v_stage.staging_path, 'expires_at', v_stage.expires_at,
      'attempt', v_stage.attempt, 'digest_verification', 'client_advisory'
    );
  END IF;
  IF v_stage.status = 'staged' AND v_stage.expires_at > clock_timestamp() THEN
    -- The just-inserted row must still pass quota; an exact replay does not
    -- consume quota twice and may return even if an operator lowered a limit.
    IF v_stage.id <> v_candidate_id THEN
      RETURN jsonb_build_object(
        'staging_id', v_stage.id, 'status', v_stage.status,
        'staging_path', v_stage.staging_path, 'expires_at', v_stage.expires_at,
        'attempt', v_stage.attempt, 'digest_verification', 'client_advisory'
      );
    END IF;
  ELSIF v_stage.status = 'staged' THEN
    UPDATE public.media_staging_objects
    SET status = 'expired'
    WHERE id = v_stage.id
    RETURNING * INTO v_stage;
  END IF;

  IF v_stage.status IN ('expired', 'failed') THEN
    v_old_path := v_stage.staging_path;
    INSERT INTO public.media_cleanup_queue(user_id, object_path, reason)
    SELECT v_user_id, v_old_path, 'expired_staging'
    WHERE NOT EXISTS (
      SELECT 1 FROM public.media_cleanup_queue q
      WHERE q.user_id = v_user_id AND q.object_path = v_old_path
        AND q.status IN ('pending', 'processing')
    );
    UPDATE public.media_staging_objects
    SET attempt = attempt + 1,
        staging_path = v_user_id::text || '/media/' || id::text || '/'
          || (attempt + 1)::text || '.' || v_extension,
        status = 'staged',
        created_at = clock_timestamp(),
        expires_at = clock_timestamp() + interval '1 day',
        finalized_at = NULL
    WHERE id = v_stage.id
    RETURNING * INTO v_stage;
  END IF;

  SELECT count(*)::integer, COALESCE(sum(object_size), 0)::bigint
  INTO v_active_count, v_active_bytes
  FROM public.media_staging_objects
  WHERE user_id = v_user_id AND status = 'staged'
    AND expires_at > clock_timestamp();
  IF v_active_count > 20 OR v_active_bytes > 104857600 THEN
    RAISE EXCEPTION USING errcode = '54000', message = 'MEDIA_STAGE_QUOTA_EXCEEDED';
  END IF;

  RETURN jsonb_build_object(
    'staging_id', v_stage.id, 'status', v_stage.status,
    'staging_path', v_stage.staging_path, 'expires_at', v_stage.expires_at,
    'attempt', v_stage.attempt, 'digest_verification', 'client_advisory'
  );
END;
$_$;


ALTER FUNCTION "owntend_media_private"."prepare_asset_photo_upload_impl"("p_asset_id" "text", "p_photo_id" "text", "p_object_size" bigint, "p_mime_type" "text", "p_client_sha256_digest" "text", "p_idempotency_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_media_private"."record_media_cleanup_failure"("p_id" bigint, "p_error_code" "text", "p_terminal" boolean DEFAULT false) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
BEGIN
  -- Only bounded, allowlisted technical codes may be recorded; raw error
  -- text, paths, and provider messages are never persisted.
  IF p_error_code IS NULL OR char_length(p_error_code) > 64
     OR p_error_code !~ '^[a-z0-9_]+$' THEN
    p_error_code := 'unknown';
  END IF;
  UPDATE public.media_cleanup_queue
  SET status = CASE WHEN p_terminal OR attempts >= 5 THEN 'failed_terminal' ELSE 'pending' END,
      last_error_code = p_error_code,
      processed_at = clock_timestamp()
  WHERE id = p_id;
  RETURN true;
END;
$_$;


ALTER FUNCTION "owntend_media_private"."record_media_cleanup_failure"("p_id" bigint, "p_error_code" "text", "p_terminal" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_media_private"."set_primary_asset_photo_impl"("p_asset_id" "text", "p_photo_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
    v_user_id UUID;
    v_asset_exists BOOLEAN;
    v_photo_exists BOOLEAN;
    v_updated_rows JSONB;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.assets
        WHERE id = p_asset_id AND user_id = v_user_id
    ) INTO v_asset_exists;

    IF NOT v_asset_exists THEN
        RAISE EXCEPTION 'Target asset not found or unauthorized.' USING ERRCODE = '42501';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.asset_photos
        WHERE id = p_photo_id AND asset_id = p_asset_id AND user_id = v_user_id
    ) INTO v_photo_exists;

    IF NOT v_photo_exists THEN
        RAISE EXCEPTION 'Target photo not found or unauthorized.' USING ERRCODE = 'P0002';
    END IF;

    -- Step 1: Demote existing primary photo(s) to avoid unique constraint collision under idx_asset_photos_single_primary
    UPDATE public.asset_photos
    SET
        is_primary = false,
        revision = revision + 1,
        updated_at = NOW()
    WHERE asset_id = p_asset_id
      AND user_id = v_user_id
      AND is_primary = true
      AND id <> p_photo_id;

    -- Step 2: Promote candidate photo to primary
    UPDATE public.asset_photos
    SET
        is_primary = true,
        revision = revision + 1,
        updated_at = NOW()
    WHERE asset_id = p_asset_id
      AND user_id = v_user_id
      AND id = p_photo_id
      AND is_primary = false;

    SELECT jsonb_agg(to_jsonb(p)) INTO v_updated_rows
    FROM public.asset_photos p
    WHERE p.asset_id = p_asset_id AND p.user_id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'asset_id', p_asset_id,
        'primary_photo_id', p_photo_id,
        'photos', COALESCE(v_updated_rows, '[]'::jsonb)
    );
END;
$$;


ALTER FUNCTION "owntend_media_private"."set_primary_asset_photo_impl"("p_asset_id" "text", "p_photo_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_media_private"."sweep_expired_media_staging"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  v_count integer := 0;
BEGIN
  WITH expired AS (
    UPDATE public.media_staging_objects
    SET status = 'expired'
    WHERE status = 'staged' AND expires_at <= clock_timestamp()
    RETURNING user_id, staging_path
  ), queued AS (
    INSERT INTO public.media_cleanup_queue(user_id, object_path, reason)
    SELECT e.user_id, e.staging_path, 'expired_staging'
    FROM expired e
    WHERE NOT EXISTS (
      SELECT 1 FROM public.media_cleanup_queue q
      WHERE q.user_id = e.user_id AND q.object_path = e.staging_path
        AND q.status IN ('pending', 'processing')
    )
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM queued;
  RETURN v_count;
END;
$$;


ALTER FUNCTION "owntend_media_private"."sweep_expired_media_staging"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_monetization_private"."can_reconcile_maintenance_plan"("p_user_id" "uuid", "p_plan_id" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  SELECT auth.uid() = p_user_id
    AND (
      EXISTS (
        SELECT 1
        FROM public.maintenance_plans
        WHERE user_id = p_user_id AND id = p_plan_id
      )
      OR EXISTS (
        SELECT 1
        FROM owntend_monetization_private.maintenance_plan_entitlements
        WHERE user_id = p_user_id AND plan_id = p_plan_id
      )
    );
$$;


ALTER FUNCTION "owntend_monetization_private"."can_reconcile_maintenance_plan"("p_user_id" "uuid", "p_plan_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_monetization_private"."change_asset_type_with_point_delta_impl"("p_operation" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
DECLARE
  caller_id uuid := auth.uid();
  operation_uuid uuid;
  v_client_request_hash text;
  v_request_hash text;
  v_asset_id text;
  v_target_type text;
  v_details jsonb;
  v_expected_revision bigint;
  v_max_charge integer;
  v_asset public.assets%ROWTYPE;
  v_existing owntend_monetization_private.plan_economy_operations%ROWTYPE;
  v_required smallint;
  v_charge integer;
  v_balance integer;
  v_next_balance integer;
  v_plan_count integer;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_operation IS NULL OR jsonb_typeof(p_operation) <> 'object'
     OR pg_column_size(p_operation) > 65536 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TYPE_CHANGE_OPERATION';
  END IF;
  BEGIN
    operation_uuid := (p_operation->>'operation_id')::uuid;
    v_expected_revision := (p_operation->>'expected_asset_revision')::bigint;
    v_max_charge := (p_operation->>'max_charge')::integer;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TYPE_CHANGE_OPERATION';
  END;
  v_client_request_hash := lower(NULLIF(btrim(p_operation->>'request_hash'), ''));
  v_asset_id := NULLIF(btrim(p_operation->>'asset_id'), '');
  v_target_type := NULLIF(btrim(p_operation->>'target_type'), '');
  v_details := COALESCE(p_operation->'details', '{}'::jsonb);
  IF v_client_request_hash IS NULL OR v_client_request_hash !~ '^[0-9a-f]{64}$'
     OR v_asset_id IS NULL
     OR v_target_type NOT IN ('device', 'pet', 'plant', 'safety', 'general')
     OR jsonb_typeof(v_details) <> 'object'
     OR v_expected_revision < 1 OR v_max_charge NOT BETWEEN 0 AND 1000 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TYPE_CHANGE_OPERATION';
  END IF;
  v_request_hash := encode(extensions.digest(p_operation::text::bytea, 'sha256'), 'hex');
  -- Match the plan-move lock before taking asset/plan/wallet row locks so the
  -- two authoritative economy paths cannot deadlock within one account.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text || ':plan_economy', 0)
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text || ':asset_type:' || operation_uuid::text, 0)
  );

  SELECT * INTO v_existing
  FROM owntend_monetization_private.plan_economy_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    IF v_existing.user_id <> caller_id
       OR v_existing.operation_kind <> 'asset_type_change'
       OR v_existing.subject_id <> v_asset_id
       OR v_existing.request_hash <> v_request_hash
       OR v_existing.client_request_hash <> v_client_request_hash THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
    END IF;
    SELECT * INTO v_asset FROM public.assets
    WHERE user_id = caller_id AND id = v_asset_id;
    SELECT balance INTO v_balance FROM public.point_wallets WHERE user_id = caller_id;
    RETURN jsonb_build_object(
      'status', 'applied', 'asset_id', v_asset_id,
      'target_type', v_asset.asset_type, 'balance', COALESCE(v_balance, 0),
      'charged', v_existing.charged_amount, 'already_processed', true,
      'asset', to_jsonb(v_asset)
    );
  END IF;

  SELECT * INTO v_asset FROM public.assets
  WHERE user_id = caller_id AND id = v_asset_id AND archived_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'ASSET_NOT_FOUND';
  END IF;
  IF v_asset.revision IS DISTINCT FROM v_expected_revision THEN
    RETURN jsonb_build_object(
      'status', 'conflict', 'conflict_reason', 'stale_asset_revision',
      'current_asset_revision', v_asset.revision, 'charged', 0,
      'already_processed', false, 'asset', to_jsonb(v_asset)
    );
  END IF;

  -- Lock every attached plan first, in a stable order, then materialize and
  -- lock its entitlement. Archived plans are intentionally included.
  PERFORM 1 FROM public.maintenance_plans
  WHERE user_id = caller_id AND asset_id = v_asset_id
  ORDER BY id
  FOR UPDATE;
  IF EXISTS (
    SELECT 1
    FROM public.maintenance_plans p
    LEFT JOIN owntend_monetization_private.maintenance_plan_entitlements e
      ON e.user_id = p.user_id AND e.plan_id = p.id
    WHERE p.user_id = caller_id
      AND p.asset_id = v_asset_id
      AND e.plan_id IS NULL
  ) THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'PLAN_ENTITLEMENT_REQUIRED';
  END IF;
  PERFORM 1 FROM owntend_monetization_private.maintenance_plan_entitlements e
  JOIN public.maintenance_plans p
    ON p.user_id = e.user_id AND p.id = e.plan_id
  WHERE p.user_id = caller_id AND p.asset_id = v_asset_id
  ORDER BY e.plan_id
  FOR UPDATE OF e;

  v_required := owntend_monetization_private.required_task_cost_for_asset_type(v_target_type);
  SELECT count(*)::integer,
         COALESCE(sum(GREATEST(0, v_required - e.paid_cost)), 0)::integer
  INTO v_plan_count, v_charge
  FROM public.maintenance_plans p
  JOIN owntend_monetization_private.maintenance_plan_entitlements e
    ON e.user_id = p.user_id AND e.plan_id = p.id
  WHERE p.user_id = caller_id AND p.asset_id = v_asset_id;
  IF v_charge > 1000 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'TYPE_CHANGE_CHARGE_LIMIT_EXCEEDED';
  END IF;
  IF v_charge > v_max_charge THEN
    RETURN jsonb_build_object(
      'status', 'charge_changed', 'charge', v_charge,
      'plan_count', v_plan_count, 'required_cost_per_plan', v_required,
      'already_processed', false
    );
  END IF;

  SELECT balance INTO v_balance FROM public.point_wallets
  WHERE user_id = caller_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = 'P0001', message = 'WALLET_NOT_FOUND';
  END IF;
  IF v_balance < v_charge THEN
    RETURN jsonb_build_object(
      'status', 'insufficient_points', 'balance', v_balance,
      'charged', 0, 'required_charge', v_charge,
      'already_processed', false
    );
  END IF;
  v_next_balance := v_balance - v_charge;

  INSERT INTO owntend_monetization_private.plan_economy_operations (
    operation_id, user_id, operation_kind, subject_id, request_hash,
    client_request_hash, charged_amount
  ) VALUES (
    operation_uuid, caller_id, 'asset_type_change', v_asset_id,
    v_request_hash, v_client_request_hash, v_charge
  );
  IF v_charge > 0 THEN
    UPDATE public.point_wallets
    SET balance = v_next_balance, updated_at = clock_timestamp()
    WHERE user_id = caller_id;
    INSERT INTO public.point_transactions (
      user_id, amount, balance_before, balance_after, transaction_type,
      reference_id, idempotency_key, metadata
    ) VALUES (
      caller_id, -v_charge, v_balance, v_next_balance,
      'task_entitlement_upgrade', v_asset_id,
      'asset-type:' || operation_uuid::text,
      jsonb_build_object('target_type', v_target_type,
                         'operation_kind', 'asset_type_change',
                         'plan_count', v_plan_count)
    );
    UPDATE owntend_monetization_private.maintenance_plan_entitlements e
    SET paid_cost = GREATEST(e.paid_cost, v_required), updated_at = clock_timestamp()
    FROM public.maintenance_plans p
    WHERE p.user_id = caller_id AND p.asset_id = v_asset_id
      AND e.user_id = p.user_id AND e.plan_id = p.id;
  END IF;

  DELETE FROM public.device_details WHERE user_id = caller_id AND asset_id = v_asset_id;
  DELETE FROM public.pet_details WHERE user_id = caller_id AND asset_id = v_asset_id;
  DELETE FROM public.plant_details WHERE user_id = caller_id AND asset_id = v_asset_id;
  DELETE FROM public.safety_details WHERE user_id = caller_id AND asset_id = v_asset_id;

  IF v_target_type = 'device' THEN
    INSERT INTO public.device_details (
      user_id, asset_id, brand, model, serial_number, power_source,
      warranty_until, manual_url, consumable, revision, created_at, updated_at
    ) VALUES (
      caller_id, v_asset_id,
      NULLIF(btrim(v_details->>'brand'), ''), NULLIF(btrim(v_details->>'model'), ''),
      NULLIF(btrim(v_details->>'serial_number'), ''),
      NULLIF(btrim(v_details->>'power_source'), ''),
      NULLIF(v_details->>'warranty_until', '')::date,
      NULLIF(btrim(v_details->>'manual_url'), ''),
      NULLIF(btrim(v_details->>'consumable'), ''), 1,
      clock_timestamp(), clock_timestamp()
    );
  ELSIF v_target_type = 'pet' THEN
    INSERT INTO public.pet_details (
      user_id, asset_id, species, breed, birth_date, microchip_id,
      vet_name, vet_phone, feeding_notes, medical_notes,
      revision, created_at, updated_at
    ) VALUES (
      caller_id, v_asset_id,
      NULLIF(btrim(v_details->>'species'), ''), NULLIF(btrim(v_details->>'breed'), ''),
      NULLIF(v_details->>'birth_date', '')::date,
      NULLIF(btrim(v_details->>'microchip_id'), ''),
      NULLIF(btrim(v_details->>'vet_name'), ''), NULLIF(btrim(v_details->>'vet_phone'), ''),
      NULLIF(btrim(v_details->>'feeding_notes'), ''),
      NULLIF(btrim(v_details->>'medical_notes'), ''),
      1, clock_timestamp(), clock_timestamp()
    );
  ELSIF v_target_type = 'plant' THEN
    INSERT INTO public.plant_details (
      user_id, asset_id, species, sunlight, watering_interval_days,
      pot_size, last_repotted_at, toxicity_notes,
      revision, created_at, updated_at
    ) VALUES (
      caller_id, v_asset_id,
      NULLIF(btrim(v_details->>'species'), ''), NULLIF(btrim(v_details->>'sunlight'), ''),
      NULLIF(v_details->>'watering_interval_days', '')::integer,
      NULLIF(btrim(v_details->>'pot_size'), ''),
      NULLIF(v_details->>'last_repotted_at', '')::timestamptz,
      NULLIF(btrim(v_details->>'toxicity_notes'), ''),
      1, clock_timestamp(), clock_timestamp()
    );
  ELSIF v_target_type = 'safety' THEN
    INSERT INTO public.safety_details (
      user_id, asset_id, safety_type, installed_at, expires_at,
      battery_type, test_interval_days, revision, created_at, updated_at
    ) VALUES (
      caller_id, v_asset_id,
      NULLIF(btrim(v_details->>'safety_type'), ''),
      NULLIF(v_details->>'installed_at', '')::timestamptz,
      NULLIF(v_details->>'expires_at', '')::timestamptz,
      NULLIF(btrim(v_details->>'battery_type'), ''),
      NULLIF(v_details->>'test_interval_days', '')::integer,
      1, clock_timestamp(), clock_timestamp()
    );
  ELSIF v_details <> '{}'::jsonb THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_GENERAL_DETAILS';
  END IF;

  UPDATE public.assets
  SET asset_type = v_target_type
  WHERE user_id = caller_id AND id = v_asset_id
  RETURNING * INTO v_asset;
  RETURN jsonb_build_object(
    'status', 'applied', 'asset_id', v_asset_id, 'target_type', v_target_type,
    'balance', v_next_balance, 'charged', v_charge,
    'already_processed', false, 'asset', to_jsonb(v_asset)
  );
EXCEPTION
  WHEN check_violation OR not_null_violation OR invalid_text_representation THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TYPE_CHANGE_OPERATION';
END;
$_$;


ALTER FUNCTION "owntend_monetization_private"."change_asset_type_with_point_delta_impl"("p_operation" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_monetization_private"."copy_asset_impl"("p_operation" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
DECLARE
  caller_id uuid := auth.uid();
  operation_uuid uuid;
  v_client_request_hash text;
  v_request_hash text;
  v_source_asset_id text;
  v_target_asset_id text;
  v_room_id text;
  v_include_tasks boolean;
  v_plan_map jsonb;
  v_source public.assets%ROWTYPE;
  v_existing public.creation_point_operations%ROWTYPE;
  v_plan_count integer;
  v_balance integer;
  v_plan public.maintenance_plans%ROWTYPE;
  v_target_plan_id text;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_operation IS NULL OR jsonb_typeof(p_operation) <> 'object'
     OR pg_column_size(p_operation) > 65536 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_COPY_OPERATION';
  END IF;
  BEGIN
    operation_uuid := (p_operation->>'operation_id')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION_ID';
  END;
  v_client_request_hash := lower(NULLIF(btrim(p_operation->>'request_hash'), ''));
  v_source_asset_id := NULLIF(btrim(p_operation->>'source_asset_id'), '');
  v_target_asset_id := NULLIF(btrim(p_operation->>'target_asset_id'), '');
  v_room_id := NULLIF(btrim(p_operation->>'destination_room_id'), '');
  v_include_tasks := COALESCE((p_operation->>'include_tasks')::boolean, false);
  v_plan_map := COALESCE(p_operation->'plan_id_map', '{}'::jsonb);
  IF v_client_request_hash IS NULL OR v_client_request_hash !~ '^[0-9a-f]{64}$'
     OR v_source_asset_id IS NULL OR v_target_asset_id IS NULL OR v_room_id IS NULL
     OR v_source_asset_id = v_target_asset_id
     OR char_length(v_target_asset_id) > 200
     OR jsonb_typeof(v_plan_map) <> 'object' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_COPY_OPERATION';
  END IF;
  v_request_hash := encode(extensions.digest(p_operation::text::bytea, 'sha256'), 'hex');
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text || ':asset_copy:' || operation_uuid::text, 0)
  );

  SELECT * INTO v_existing
  FROM public.creation_point_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    IF v_existing.user_id <> caller_id OR v_existing.entity_type <> 'asset'
       OR v_existing.entity_id <> v_target_asset_id
       OR v_existing.request_hash <> v_request_hash
       OR v_existing.client_request_hash <> v_client_request_hash THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
    END IF;
    SELECT balance INTO v_balance FROM public.point_wallets WHERE user_id = caller_id;
    RETURN jsonb_build_object(
      'asset_id', v_target_asset_id, 'balance', COALESCE(v_balance, 0),
      'charged', 0, 'already_processed', true,
      'asset', (SELECT to_jsonb(a) FROM public.assets a
                WHERE a.user_id = caller_id AND a.id = v_target_asset_id),
       'plans', COALESCE((
         SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id)
         FROM public.maintenance_plans p
         WHERE p.user_id = caller_id AND p.asset_id = v_target_asset_id
       ), '[]'::jsonb),
       'plan_metadata', COALESCE((
         SELECT jsonb_agg(to_jsonb(m) ORDER BY m.plan_id)
         FROM public.maintenance_plan_metadata m
         JOIN public.maintenance_plans p
           ON p.user_id = m.user_id AND p.id = m.plan_id
         WHERE p.user_id = caller_id AND p.asset_id = v_target_asset_id
       ), '[]'::jsonb),
       'detail_rows', COALESCE((
         SELECT jsonb_agg(x.item)
         FROM (
           SELECT jsonb_build_object('entity', 'device_detail', 'row', to_jsonb(d)) AS item
           FROM public.device_details d WHERE d.user_id = caller_id AND d.asset_id = v_target_asset_id
           UNION ALL
           SELECT jsonb_build_object('entity', 'pet_detail', 'row', to_jsonb(d))
           FROM public.pet_details d WHERE d.user_id = caller_id AND d.asset_id = v_target_asset_id
           UNION ALL
           SELECT jsonb_build_object('entity', 'plant_detail', 'row', to_jsonb(d))
           FROM public.plant_details d WHERE d.user_id = caller_id AND d.asset_id = v_target_asset_id
           UNION ALL
           SELECT jsonb_build_object('entity', 'safety_detail', 'row', to_jsonb(d))
           FROM public.safety_details d WHERE d.user_id = caller_id AND d.asset_id = v_target_asset_id
         ) x
       ), '[]'::jsonb)
    );
  END IF;

  SELECT * INTO v_source
  FROM public.assets
  WHERE user_id = caller_id AND id = v_source_asset_id AND archived_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'SOURCE_ASSET_NOT_FOUND';
  END IF;
  PERFORM 1 FROM public.rooms
  WHERE user_id = caller_id AND id = v_room_id AND archived_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'DESTINATION_ROOM_NOT_FOUND';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.assets
    WHERE user_id = caller_id AND id = v_target_asset_id
  ) THEN
    RAISE EXCEPTION USING errcode = '23505', message = 'TARGET_ASSET_EXISTS';
  END IF;

  SELECT count(*)::integer INTO v_plan_count
  FROM public.maintenance_plans
  WHERE user_id = caller_id AND asset_id = v_source_asset_id
    AND archived_at IS NULL AND is_enabled;
  IF v_plan_count > 50 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'COPY_TASK_LIMIT_EXCEEDED';
  END IF;
  IF NOT v_include_tasks AND v_plan_map <> '{}'::jsonb THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_PLAN_ID_MAP';
  END IF;
  IF v_include_tasks THEN
    IF (SELECT count(*) FROM jsonb_each(v_plan_map)) <> v_plan_count
       OR EXISTS (
         SELECT 1 FROM public.maintenance_plans p
         WHERE p.user_id = caller_id AND p.asset_id = v_source_asset_id
           AND p.archived_at IS NULL AND p.is_enabled
           AND NOT (v_plan_map ? p.id)
       )
       OR EXISTS (
         SELECT 1 FROM jsonb_each_text(v_plan_map) m
         LEFT JOIN public.maintenance_plans p
           ON p.user_id = caller_id AND p.id = m.key
          AND p.asset_id = v_source_asset_id
          AND p.archived_at IS NULL AND p.is_enabled
         WHERE p.id IS NULL OR NULLIF(btrim(m.value), '') IS NULL
            OR char_length(m.value) > 200 OR m.value = v_target_asset_id
       )
       OR (SELECT count(*) FROM jsonb_each_text(v_plan_map))
          <> (SELECT count(DISTINCT value) FROM jsonb_each_text(v_plan_map)) THEN
      RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_PLAN_ID_MAP';
    END IF;
    IF EXISTS (
      SELECT 1
      FROM jsonb_each_text(v_plan_map) m
      JOIN public.maintenance_plans p
        ON p.user_id = caller_id AND p.id = m.value
    ) THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'TARGET_PLAN_EXISTS';
    END IF;
  END IF;

  INSERT INTO public.assets (
    user_id, id, name, asset_type, room_id, placement, notes, purchase_date,
    revision, created_at, updated_at, archived_at
  ) VALUES (
    caller_id, v_target_asset_id, v_source.name, v_source.asset_type, v_room_id,
    v_source.placement, v_source.notes, v_source.purchase_date,
    1, clock_timestamp(), clock_timestamp(), NULL
  );
  INSERT INTO public.device_details (
    user_id, asset_id, brand, model, serial_number, power_source, warranty_until,
    manual_url, consumable, revision, created_at, updated_at
  )
  SELECT caller_id, v_target_asset_id, brand, model, serial_number, power_source,
         warranty_until, manual_url, consumable, 1, clock_timestamp(), clock_timestamp()
  FROM public.device_details
  WHERE user_id = caller_id AND asset_id = v_source_asset_id;
  INSERT INTO public.pet_details (
    user_id, asset_id, species, breed, birth_date, microchip_id, vet_name,
    vet_phone, feeding_notes, medical_notes, revision, created_at, updated_at
  )
  SELECT caller_id, v_target_asset_id, species, breed, birth_date, microchip_id,
         vet_name, vet_phone, feeding_notes, medical_notes, 1,
         clock_timestamp(), clock_timestamp()
  FROM public.pet_details
  WHERE user_id = caller_id AND asset_id = v_source_asset_id;
  INSERT INTO public.plant_details (
    user_id, asset_id, species, sunlight, watering_interval_days, pot_size,
    last_repotted_at, toxicity_notes, revision, created_at, updated_at
  )
  SELECT caller_id, v_target_asset_id, species, sunlight, watering_interval_days,
         pot_size, last_repotted_at, toxicity_notes, 1,
         clock_timestamp(), clock_timestamp()
  FROM public.plant_details
  WHERE user_id = caller_id AND asset_id = v_source_asset_id;
  INSERT INTO public.safety_details (
    user_id, asset_id, safety_type, installed_at, expires_at, battery_type,
    test_interval_days, revision, created_at, updated_at
  )
  SELECT caller_id, v_target_asset_id, safety_type, installed_at, expires_at,
         battery_type, test_interval_days, 1, clock_timestamp(), clock_timestamp()
  FROM public.safety_details
  WHERE user_id = caller_id AND asset_id = v_source_asset_id;

  IF v_include_tasks THEN
    FOR v_plan IN
      SELECT * FROM public.maintenance_plans
      WHERE user_id = caller_id AND asset_id = v_source_asset_id
        AND archived_at IS NULL AND is_enabled
      ORDER BY id
    LOOP
      v_target_plan_id := v_plan_map->>v_plan.id;
      INSERT INTO public.maintenance_plans (
        user_id, id, asset_id, title, instructions, recurrence_interval,
        recurrence_unit, priority, next_due_date, is_enabled,
        reminder_days_before, revision, created_at, updated_at, archived_at
      ) VALUES (
        caller_id, v_target_plan_id, v_target_asset_id, v_plan.title,
        v_plan.instructions, v_plan.recurrence_interval, v_plan.recurrence_unit,
        v_plan.priority, v_plan.next_due_date, true, v_plan.reminder_days_before,
        1, clock_timestamp(), clock_timestamp(), NULL
      );
      INSERT INTO public.maintenance_plan_metadata (
        user_id, plan_id, task_type, location_label, estimated_duration_minutes,
        required_materials_json, reminder_recommendation, sort_order,
        revision, created_at, updated_at
      )
      SELECT caller_id, v_target_plan_id, task_type, location_label,
             estimated_duration_minutes, required_materials_json,
             reminder_recommendation, sort_order, 1,
             clock_timestamp(), clock_timestamp()
      FROM public.maintenance_plan_metadata
      WHERE user_id = caller_id AND plan_id = v_plan.id;
      INSERT INTO owntend_monetization_private.maintenance_plan_entitlements (
        user_id, plan_id, paid_cost, origin
      ) VALUES (caller_id, v_target_plan_id, 0, 'asset_copy');
    END LOOP;
  END IF;

  INSERT INTO public.creation_point_operations (
    operation_id, user_id, entity_type, entity_id, charged_amount,
    request_hash, client_request_hash
  ) VALUES (
    operation_uuid, caller_id, 'asset', v_target_asset_id, 0,
    v_request_hash, v_client_request_hash
  );
  SELECT balance INTO v_balance FROM public.point_wallets WHERE user_id = caller_id;
  RETURN jsonb_build_object(
    'asset_id', v_target_asset_id, 'balance', COALESCE(v_balance, 0),
    'charged', 0, 'already_processed', false,
    'asset', (SELECT to_jsonb(a) FROM public.assets a
              WHERE a.user_id = caller_id AND a.id = v_target_asset_id),
     'plans', COALESCE((
       SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id)
       FROM public.maintenance_plans p
       WHERE p.user_id = caller_id AND p.asset_id = v_target_asset_id
     ), '[]'::jsonb),
     'plan_metadata', COALESCE((
       SELECT jsonb_agg(to_jsonb(m) ORDER BY m.plan_id)
       FROM public.maintenance_plan_metadata m
       JOIN public.maintenance_plans p
         ON p.user_id = m.user_id AND p.id = m.plan_id
       WHERE p.user_id = caller_id AND p.asset_id = v_target_asset_id
     ), '[]'::jsonb),
     'detail_rows', COALESCE((
       SELECT jsonb_agg(x.item)
       FROM (
         SELECT jsonb_build_object('entity', 'device_detail', 'row', to_jsonb(d)) AS item
         FROM public.device_details d WHERE d.user_id = caller_id AND d.asset_id = v_target_asset_id
         UNION ALL
         SELECT jsonb_build_object('entity', 'pet_detail', 'row', to_jsonb(d))
         FROM public.pet_details d WHERE d.user_id = caller_id AND d.asset_id = v_target_asset_id
         UNION ALL
         SELECT jsonb_build_object('entity', 'plant_detail', 'row', to_jsonb(d))
         FROM public.plant_details d WHERE d.user_id = caller_id AND d.asset_id = v_target_asset_id
         UNION ALL
         SELECT jsonb_build_object('entity', 'safety_detail', 'row', to_jsonb(d))
         FROM public.safety_details d WHERE d.user_id = caller_id AND d.asset_id = v_target_asset_id
       ) x
     ), '[]'::jsonb)
  );
END;
$_$;


ALTER FUNCTION "owntend_monetization_private"."copy_asset_impl"("p_operation" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_monetization_private"."create_asset_impl"("p_operation" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "owntend_monetization_private"."create_asset_impl"("p_operation" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_monetization_private"."create_reward_claim_request_impl"("p_reward_type" "text", "p_time_zone" "text" DEFAULT NULL::"text", "p_eligibility_token" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  caller_id uuid := auth.uid();
  wallet_row public.point_wallets%ROWTYPE;
  config_row public.monetization_config%ROWTYPE;
  eligibility_row public.maintenance_reward_eligibilities%ROWTYPE;
  existing_claim public.reward_claim_requests%ROWTYPE;
  reward_amount integer;
  ad_unit_id text;
  requested_time_zone text;
  local_reward_day date;
  claim_row public.reward_claim_requests%ROWTYPE;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_reward_type NOT IN ('rewarded_ad', 'rewarded_interstitial') THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_REWARD_TYPE';
  END IF;

  SELECT * INTO config_row
  FROM public.monetization_config
  WHERE singleton = true;
  IF NOT config_row.ads_enabled OR NOT config_row.rewarded_ads_enabled
     OR (p_reward_type = 'rewarded_interstitial'
         AND NOT config_row.rewarded_interstitial_enabled) THEN
    RAISE EXCEPTION USING errcode = 'P0001', message = 'REWARDS_DISABLED';
  END IF;

  reward_amount := CASE WHEN p_reward_type = 'rewarded_ad' THEN 1 ELSE 2 END;
  ad_unit_id := CASE
    WHEN p_reward_type = 'rewarded_ad'
      THEN 'ca-app-pub-5274007212820203/4541482404'
    ELSE 'ca-app-pub-5274007212820203/7295784043'
  END;

  SELECT * INTO wallet_row
  FROM public.point_wallets
  WHERE user_id = caller_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = 'P0001', message = 'WALLET_NOT_FOUND';
  END IF;

  requested_time_zone := NULLIF(btrim(p_time_zone), '');
  IF p_reward_type = 'rewarded_interstitial' THEN
    IF p_eligibility_token IS NULL THEN
      RAISE EXCEPTION USING
        errcode = 'P0001', message = 'REWARD_ELIGIBILITY_REQUIRED';
    END IF;
    SELECT * INTO eligibility_row
    FROM public.maintenance_reward_eligibilities
    WHERE token = p_eligibility_token
      AND user_id = caller_id
    FOR UPDATE;
    IF NOT FOUND OR eligibility_row.expires_at <= clock_timestamp() THEN
      RAISE EXCEPTION USING
        errcode = 'P0001', message = 'REWARD_NOT_ELIGIBLE';
    END IF;
    IF requested_time_zone IS NOT NULL
       AND requested_time_zone <> eligibility_row.time_zone_id THEN
      RAISE EXCEPTION USING
        errcode = '22023', message = 'INVALID_ELIGIBILITY_TIME_ZONE';
    END IF;
    requested_time_zone := eligibility_row.time_zone_id;
    IF eligibility_row.reward_claim_id IS NOT NULL THEN
      SELECT * INTO existing_claim
      FROM public.reward_claim_requests
      WHERE claim_id = eligibility_row.reward_claim_id
        AND user_id = caller_id;
      IF FOUND AND existing_claim.status = 'pending'
         AND existing_claim.expires_at > clock_timestamp() THEN
        RETURN jsonb_build_object(
          'claim_id', existing_claim.claim_id,
          'user_id', caller_id,
          'custom_data', existing_claim.claim_id::text,
          'reward_type', existing_claim.reward_type,
          'reward_amount', existing_claim.reward_amount,
          'ad_unit_id', existing_claim.ad_unit_id,
          'expires_at', existing_claim.expires_at,
          'reward_day', existing_claim.reward_day,
          'time_zone', eligibility_row.time_zone_id
        );
      END IF;
      RAISE EXCEPTION USING
        errcode = 'P0001', message = 'REWARD_ELIGIBILITY_USED';
    END IF;
  END IF;

  IF requested_time_zone IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_timezone_names
       WHERE name = requested_time_zone
     ) THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TIME_ZONE';
  END IF;
  IF requested_time_zone IS NOT NULL
     AND requested_time_zone <> wallet_row.reward_time_zone THEN
    IF EXISTS (
      SELECT 1 FROM public.point_transactions
      WHERE user_id = caller_id
        AND transaction_type IN ('rewarded_ad', 'rewarded_interstitial')
    ) AND wallet_row.reward_time_zone_updated_at
          > clock_timestamp() - interval '30 days' THEN
      RAISE EXCEPTION USING
        errcode = 'P0001', message = 'TIME_ZONE_CHANGE_COOLDOWN';
    END IF;
    UPDATE public.point_wallets
    SET reward_time_zone = requested_time_zone,
        reward_time_zone_updated_at = clock_timestamp(),
        updated_at = clock_timestamp()
    WHERE user_id = caller_id;
    wallet_row.reward_time_zone := requested_time_zone;
  END IF;
  local_reward_day := CASE
    WHEN p_reward_type = 'rewarded_interstitial'
      THEN eligibility_row.reward_day
    ELSE (clock_timestamp() AT TIME ZONE wallet_row.reward_time_zone)::date
  END;

  UPDATE public.reward_claim_requests
  SET status = 'expired', rejection_reason = 'expired'
  WHERE user_id = caller_id
    AND status = 'pending'
    AND expires_at <= clock_timestamp();

  IF wallet_row.balance + reward_amount > config_row.wallet_cap THEN
    RAISE EXCEPTION USING errcode = 'P0001', message = 'WALLET_CAP_REACHED';
  END IF;
  IF p_reward_type = 'rewarded_interstitial' AND EXISTS (
    SELECT 1 FROM public.point_transactions
    WHERE user_id = caller_id
      AND transaction_type = 'rewarded_interstitial'
      AND reward_day = local_reward_day
  ) THEN
    RAISE EXCEPTION USING
      errcode = 'P0001', message = 'REWARD_ALREADY_CLAIMED';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.reward_claim_requests
    WHERE user_id = caller_id
      AND created_at > clock_timestamp() - pg_catalog.make_interval(
        secs => config_row.reward_claim_cooldown_seconds
      )
  ) THEN
    RAISE EXCEPTION USING errcode = 'P0001', message = 'REWARD_COOLDOWN';
  END IF;

  INSERT INTO public.reward_claim_requests (
    user_id, reward_type, ad_unit_id, reward_amount, reward_day,
    eligibility_token
  ) VALUES (
    caller_id, p_reward_type, ad_unit_id, reward_amount, local_reward_day,
    CASE WHEN p_reward_type = 'rewarded_interstitial'
      THEN p_eligibility_token ELSE NULL END
  )
  RETURNING * INTO claim_row;

  IF p_reward_type = 'rewarded_interstitial' THEN
    UPDATE public.maintenance_reward_eligibilities
    SET consumed_at = clock_timestamp(), reward_claim_id = claim_row.claim_id
    WHERE token = p_eligibility_token AND user_id = caller_id;
  END IF;

  RETURN jsonb_build_object(
    'claim_id', claim_row.claim_id,
    'user_id', caller_id,
    'custom_data', claim_row.claim_id::text,
    'reward_type', claim_row.reward_type,
    'reward_amount', claim_row.reward_amount,
    'ad_unit_id', claim_row.ad_unit_id,
    'expires_at', claim_row.expires_at,
    'reward_day', claim_row.reward_day,
    'time_zone', wallet_row.reward_time_zone
  );
END;
$$;


ALTER FUNCTION "owntend_monetization_private"."create_reward_claim_request_impl"("p_reward_type" "text", "p_time_zone" "text", "p_eligibility_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_monetization_private"."create_task_with_point_debit_impl"("p_operation" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
DECLARE
  caller_id uuid := auth.uid();
  operation_uuid uuid;
  plan_json jsonb;
  metadata_json jsonb;
  v_plan_id text;
  target_asset_id text;
  current_balance integer;
  next_balance integer;
  charge integer := 1;
  is_safety boolean;
  config_row public.monetization_config%ROWTYPE;
  existing_operation public.creation_point_operations%ROWTYPE;
  v_request_hash text;
  v_client_request_hash text;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_operation IS NULL OR jsonb_typeof(p_operation) <> 'object'
     OR pg_column_size(p_operation) > 65536 THEN
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
  plan_json := p_operation->'plan';
  metadata_json := COALESCE(p_operation->'metadata', '{}'::jsonb);
  IF jsonb_typeof(plan_json) <> 'object'
     OR jsonb_typeof(metadata_json) <> 'object'
     OR (metadata_json ? 'required_materials'
         AND jsonb_typeof(metadata_json->'required_materials') <> 'array')
     OR plan_json ? 'health_group' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
  END IF;
  v_plan_id := NULLIF(btrim(plan_json->>'id'), '');
  target_asset_id := NULLIF(btrim(plan_json->>'asset_id'), '');
  IF v_plan_id IS NULL OR target_asset_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
  END IF;
  v_request_hash := encode(extensions.digest(p_operation::text::bytea, 'sha256'), 'hex');

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text || ':task_op:' || operation_uuid::text, 0)
  );

  SELECT * INTO existing_operation
  FROM public.creation_point_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    IF existing_operation.user_id <> caller_id
       OR existing_operation.entity_type <> 'task'
       OR existing_operation.entity_id <> v_plan_id
       OR existing_operation.request_hash <> v_request_hash
       OR existing_operation.client_request_hash <> v_client_request_hash THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
    END IF;
    SELECT balance INTO current_balance FROM public.point_wallets WHERE user_id = caller_id;
    RETURN jsonb_build_object(
      'task_id', v_plan_id,
      'balance', current_balance,
      'charged', existing_operation.charged_amount,
      'already_processed', true,
      'plan', (SELECT to_jsonb(p) FROM public.maintenance_plans p
               WHERE p.user_id = caller_id AND p.id = v_plan_id),
      'metadata', (SELECT to_jsonb(m) FROM public.maintenance_plan_metadata m
                   WHERE m.user_id = caller_id AND m.plan_id = v_plan_id)
    );
  END IF;

  SELECT a.asset_type = 'safety' INTO is_safety
  FROM public.assets a
  WHERE a.user_id = caller_id AND a.id = target_asset_id AND a.archived_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '23503', message = 'ASSET_NOT_FOUND';
  END IF;
  SELECT * INTO config_row FROM public.monetization_config WHERE singleton = true;
  IF NOT config_row.points_enabled OR config_row.emergency_free_creation_mode OR is_safety THEN
    charge := 0;
  END IF;

  SELECT balance INTO current_balance
  FROM public.point_wallets
  WHERE user_id = caller_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = 'P0001', message = 'WALLET_NOT_FOUND';
  END IF;
  IF charge = 1 AND current_balance < 1 THEN
    RETURN jsonb_build_object(
      'status', 'insufficient_points', 'task_id', NULL,
      'balance', current_balance, 'charged', 0, 'already_processed', false
    );
  END IF;
  next_balance := current_balance - charge;

  INSERT INTO public.maintenance_plans (
    user_id, id, asset_id, title, instructions, recurrence_interval,
    recurrence_unit, priority, next_due_date, reminder_days_before,
    created_at, updated_at, archived_at, revision, is_enabled
  ) VALUES (
    caller_id, v_plan_id, target_asset_id, btrim(plan_json->>'title'),
    NULLIF(btrim(plan_json->>'instructions'), ''),
    COALESCE((plan_json->>'recurrence_interval')::integer, 1),
    COALESCE(plan_json->>'recurrence_unit', 'months'),
    COALESCE(plan_json->>'priority', 'medium'),
    (plan_json->>'next_due_date')::timestamptz,
    COALESCE((plan_json->>'reminder_days_before')::integer, 0),
    clock_timestamp(), clock_timestamp(), NULL, 1,
    COALESCE((plan_json->>'is_enabled')::boolean, true)
  );

  IF metadata_json <> '{}'::jsonb THEN
    INSERT INTO public.maintenance_plan_metadata (
      user_id, plan_id, task_type, location_label, estimated_duration_minutes,
      required_materials_json, reminder_recommendation, sort_order,
      created_at, updated_at, revision
    ) VALUES (
      caller_id, v_plan_id,
      NULLIF(btrim(metadata_json->>'task_type'), ''),
      NULLIF(btrim(metadata_json->>'location_label'), ''),
      (metadata_json->>'estimated_duration_minutes')::integer,
      COALESCE(metadata_json->>'required_materials_json',
               (metadata_json->'required_materials')::text, '[]'),
      NULLIF(btrim(metadata_json->>'reminder_recommendation'), ''),
      COALESCE((metadata_json->>'sort_order')::integer, 0),
      clock_timestamp(), clock_timestamp(), 1
    );
  END IF;

  INSERT INTO public.creation_point_operations (
    operation_id, user_id, entity_type, entity_id, charged_amount,
    request_hash, client_request_hash
  ) VALUES (
    operation_uuid, caller_id, 'task', v_plan_id, charge,
    v_request_hash, v_client_request_hash
  );

  INSERT INTO owntend_monetization_private.maintenance_plan_entitlements (
    user_id, plan_id, paid_cost, origin, created_by_operation_id
  ) VALUES (
    caller_id, v_plan_id, charge::smallint, 'task_creation', operation_uuid
  );

  IF charge = 1 THEN
    UPDATE public.point_wallets
    SET balance = next_balance, updated_at = clock_timestamp()
    WHERE user_id = caller_id;
    INSERT INTO public.point_transactions (
      user_id, amount, balance_before, balance_after, transaction_type,
      reference_id, idempotency_key, metadata
    ) VALUES (
      caller_id, -1, current_balance, next_balance, 'task_creation',
      v_plan_id, 'create-task:' || operation_uuid::text,
      jsonb_build_object('asset_id', target_asset_id)
    );
  END IF;

  RETURN jsonb_build_object(
    'task_id', v_plan_id, 'balance', next_balance, 'charged', charge,
    'already_processed', false,
    'plan', (SELECT to_jsonb(p) FROM public.maintenance_plans p
             WHERE p.user_id = caller_id AND p.id = v_plan_id),
    'metadata', (SELECT to_jsonb(m) FROM public.maintenance_plan_metadata m
                 WHERE m.user_id = caller_id AND m.plan_id = v_plan_id)
  );
EXCEPTION
  WHEN check_violation OR not_null_violation OR invalid_text_representation THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
END;
$_$;


ALTER FUNCTION "owntend_monetization_private"."create_task_with_point_debit_impl"("p_operation" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_monetization_private"."get_charged_operation_status"("p_operation_id" "uuid", "p_request_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
DECLARE
  v_caller_id uuid := auth.uid();
  v_operation public.creation_point_operations%ROWTYPE;
  v_current_balance integer;
  v_normalized_hash text := lower(NULLIF(btrim(p_request_hash), ''));
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_operation_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION_ID';
  END IF;
  IF v_normalized_hash IS NULL OR v_normalized_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_REQUEST_HASH';
  END IF;

  SELECT * INTO v_operation
  FROM public.creation_point_operations
  WHERE operation_id = p_operation_id;
  IF NOT FOUND OR v_operation.user_id <> v_caller_id THEN
    RETURN jsonb_build_object('status', 'not_found');
  END IF;
  IF v_operation.client_request_hash <> v_normalized_hash THEN
    RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
  END IF;
  SELECT balance INTO v_current_balance
  FROM public.point_wallets WHERE user_id = v_caller_id;

  IF v_operation.entity_type = 'asset' THEN
    RETURN jsonb_build_object(
      'status', 'completed', 'operation_id', v_operation.operation_id,
      'entity_type', v_operation.entity_type, 'entity_id', v_operation.entity_id,
      'charged', v_operation.charged_amount,
      'balance', COALESCE(v_current_balance, 0),
      'asset', (SELECT to_jsonb(a) FROM public.assets a
                WHERE a.user_id = v_caller_id AND a.id = v_operation.entity_id),
      'plans', COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id)
                        FROM public.maintenance_plans p
                        WHERE p.user_id = v_caller_id
                          AND p.asset_id = v_operation.entity_id), '[]'::jsonb),
      'plan_metadata', COALESCE((
        SELECT jsonb_agg(to_jsonb(m) ORDER BY m.plan_id)
        FROM public.maintenance_plan_metadata m
        JOIN public.maintenance_plans p ON p.user_id = m.user_id AND p.id = m.plan_id
        WHERE p.user_id = v_caller_id AND p.asset_id = v_operation.entity_id
      ), '[]'::jsonb),
      'detail_rows', COALESCE((
        SELECT jsonb_agg(x.item)
        FROM (
          SELECT jsonb_build_object('entity', 'device_detail', 'row', to_jsonb(d)) AS item
          FROM public.device_details d WHERE d.user_id = v_caller_id AND d.asset_id = v_operation.entity_id
          UNION ALL
          SELECT jsonb_build_object('entity', 'pet_detail', 'row', to_jsonb(d))
          FROM public.pet_details d WHERE d.user_id = v_caller_id AND d.asset_id = v_operation.entity_id
          UNION ALL
          SELECT jsonb_build_object('entity', 'plant_detail', 'row', to_jsonb(d))
          FROM public.plant_details d WHERE d.user_id = v_caller_id AND d.asset_id = v_operation.entity_id
          UNION ALL
          SELECT jsonb_build_object('entity', 'safety_detail', 'row', to_jsonb(d))
          FROM public.safety_details d WHERE d.user_id = v_caller_id AND d.asset_id = v_operation.entity_id
        ) x
      ), '[]'::jsonb)
    );
  ELSIF v_operation.entity_type = 'task' THEN
    RETURN jsonb_build_object(
      'status', 'completed', 'operation_id', v_operation.operation_id,
      'entity_type', v_operation.entity_type, 'entity_id', v_operation.entity_id,
      'charged', v_operation.charged_amount,
      'balance', COALESCE(v_current_balance, 0),
      'plan', (SELECT to_jsonb(p) FROM public.maintenance_plans p
               WHERE p.user_id = v_caller_id AND p.id = v_operation.entity_id),
      'metadata', (SELECT to_jsonb(m) FROM public.maintenance_plan_metadata m
                   WHERE m.user_id = v_caller_id AND m.plan_id = v_operation.entity_id)
    );
  END IF;
  RETURN jsonb_build_object(
    'status', 'completed', 'operation_id', v_operation.operation_id,
    'entity_type', v_operation.entity_type, 'entity_id', v_operation.entity_id,
    'charged', v_operation.charged_amount,
    'balance', COALESCE(v_current_balance, 0)
  );
END;
$_$;


ALTER FUNCTION "owntend_monetization_private"."get_charged_operation_status"("p_operation_id" "uuid", "p_request_hash" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_monetization_private"."move_maintenance_plan_with_point_delta_impl"("p_operation" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
DECLARE
  caller_id uuid := auth.uid();
  operation_uuid uuid;
  v_client_request_hash text;
  v_request_hash text;
  v_plan_id text;
  v_target_asset_id text;
  v_expected_revision bigint;
  v_max_charge integer;
  v_plan public.maintenance_plans%ROWTYPE;
  v_target public.assets%ROWTYPE;
  v_entitlement owntend_monetization_private.maintenance_plan_entitlements%ROWTYPE;
  v_existing owntend_monetization_private.plan_economy_operations%ROWTYPE;
  v_required smallint;
  v_charge integer;
  v_balance integer;
  v_next_balance integer;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_operation IS NULL OR jsonb_typeof(p_operation) <> 'object'
     OR pg_column_size(p_operation) > 32768 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_MOVE_OPERATION';
  END IF;
  BEGIN
    operation_uuid := (p_operation->>'operation_id')::uuid;
    v_expected_revision := (p_operation->>'expected_plan_revision')::bigint;
    v_max_charge := (p_operation->>'max_charge')::integer;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_MOVE_OPERATION';
  END;
  v_client_request_hash := lower(NULLIF(btrim(p_operation->>'request_hash'), ''));
  v_plan_id := NULLIF(btrim(p_operation->>'plan_id'), '');
  v_target_asset_id := NULLIF(btrim(p_operation->>'target_asset_id'), '');
  IF v_client_request_hash IS NULL OR v_client_request_hash !~ '^[0-9a-f]{64}$'
     OR v_plan_id IS NULL OR v_target_asset_id IS NULL
     OR v_expected_revision < 1 OR v_max_charge NOT BETWEEN 0 AND 1 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_MOVE_OPERATION';
  END IF;
  v_request_hash := encode(extensions.digest(p_operation::text::bytea, 'sha256'), 'hex');
  -- Serialize all plan-economy commits for one account before taking row
  -- locks. This prevents a same-asset move and type change from acquiring the
  -- plan and asset rows in opposite order while preserving cross-user
  -- concurrency.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text || ':plan_economy', 0)
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text || ':plan_move:' || operation_uuid::text, 0)
  );

  SELECT * INTO v_existing
  FROM owntend_monetization_private.plan_economy_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    IF v_existing.user_id <> caller_id OR v_existing.operation_kind <> 'plan_move'
       OR v_existing.subject_id <> v_plan_id
       OR v_existing.request_hash <> v_request_hash
       OR v_existing.client_request_hash <> v_client_request_hash THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
    END IF;
    SELECT * INTO v_plan FROM public.maintenance_plans
    WHERE user_id = caller_id AND id = v_plan_id;
    SELECT balance INTO v_balance FROM public.point_wallets WHERE user_id = caller_id;
    RETURN jsonb_build_object(
      'status', 'applied', 'plan_id', v_plan_id,
      'target_asset_id', v_plan.asset_id, 'balance', COALESCE(v_balance, 0),
      'charged', v_existing.charged_amount, 'already_processed', true,
      'plan', to_jsonb(v_plan)
    );
  END IF;

  SELECT * INTO v_plan FROM public.maintenance_plans
  WHERE user_id = caller_id AND id = v_plan_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'PLAN_NOT_FOUND';
  END IF;
  IF v_plan.revision IS DISTINCT FROM v_expected_revision THEN
    RETURN jsonb_build_object(
      'status', 'conflict', 'conflict_reason', 'stale_plan_revision',
      'current_plan_revision', v_plan.revision, 'charged', 0,
      'already_processed', false, 'plan', to_jsonb(v_plan)
    );
  END IF;

  SELECT * INTO v_entitlement
  FROM owntend_monetization_private.maintenance_plan_entitlements
  WHERE user_id = caller_id AND plan_id = v_plan_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'PLAN_ENTITLEMENT_REQUIRED';
  END IF;
  SELECT * INTO v_target FROM public.assets
  WHERE user_id = caller_id AND id = v_target_asset_id AND archived_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'TARGET_ASSET_NOT_FOUND';
  END IF;
  v_required := owntend_monetization_private.required_task_cost_for_asset_type(v_target.asset_type);
  v_charge := GREATEST(0, v_required - v_entitlement.paid_cost);
  IF v_charge > v_max_charge THEN
    RETURN jsonb_build_object(
      'status', 'charge_changed', 'charge', v_charge,
      'paid_cost', v_entitlement.paid_cost, 'required_cost', v_required,
      'already_processed', false
    );
  END IF;
  SELECT balance INTO v_balance FROM public.point_wallets
  WHERE user_id = caller_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = 'P0001', message = 'WALLET_NOT_FOUND';
  END IF;
  IF v_balance < v_charge THEN
    RETURN jsonb_build_object(
      'status', 'insufficient_points', 'balance', v_balance,
      'charged', 0, 'required_charge', v_charge, 'already_processed', false
    );
  END IF;
  v_next_balance := v_balance - v_charge;

  INSERT INTO owntend_monetization_private.plan_economy_operations (
    operation_id, user_id, operation_kind, subject_id, request_hash,
    client_request_hash, charged_amount
  ) VALUES (
    operation_uuid, caller_id, 'plan_move', v_plan_id, v_request_hash,
    v_client_request_hash, v_charge
  );
  IF v_charge > 0 THEN
    UPDATE public.point_wallets
    SET balance = v_next_balance, updated_at = clock_timestamp()
    WHERE user_id = caller_id;
    INSERT INTO public.point_transactions (
      user_id, amount, balance_before, balance_after, transaction_type,
      reference_id, idempotency_key, metadata
    ) VALUES (
      caller_id, -v_charge, v_balance, v_next_balance,
      'task_entitlement_upgrade', v_plan_id,
      'plan-move:' || operation_uuid::text,
      jsonb_build_object('target_asset_id', v_target_asset_id,
                         'operation_kind', 'plan_move')
    );
    UPDATE owntend_monetization_private.maintenance_plan_entitlements
    SET paid_cost = GREATEST(paid_cost, v_required), updated_at = clock_timestamp()
    WHERE user_id = caller_id AND plan_id = v_plan_id;
  END IF;
  UPDATE public.maintenance_plans
  SET asset_id = v_target_asset_id
  WHERE user_id = caller_id AND id = v_plan_id
  RETURNING * INTO v_plan;

  RETURN jsonb_build_object(
    'status', 'applied', 'plan_id', v_plan_id,
    'target_asset_id', v_target_asset_id, 'balance', v_next_balance,
    'charged', v_charge, 'already_processed', false, 'plan', to_jsonb(v_plan)
  );
END;
$_$;


ALTER FUNCTION "owntend_monetization_private"."move_maintenance_plan_with_point_delta_impl"("p_operation" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_monetization_private"."quote_asset_type_change_impl"("p_asset_id" "text", "p_target_type" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  caller_id uuid := auth.uid();
  v_asset public.assets%ROWTYPE;
  v_required smallint;
  v_charge integer;
  v_balance integer;
  v_plan_count integer;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_target_type NOT IN ('device', 'pet', 'plant', 'safety', 'general') THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_ASSET_TYPE';
  END IF;
  SELECT * INTO v_asset FROM public.assets
  WHERE user_id = caller_id AND id = p_asset_id AND archived_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'ASSET_NOT_FOUND';
  END IF;
  v_required := owntend_monetization_private.required_task_cost_for_asset_type(p_target_type);
  SELECT count(*)::integer,
         COALESCE(sum(GREATEST(0, v_required - COALESCE(e.paid_cost, 0))), 0)::integer
  INTO v_plan_count, v_charge
  FROM public.maintenance_plans p
  LEFT JOIN owntend_monetization_private.maintenance_plan_entitlements e
    ON e.user_id = p.user_id AND e.plan_id = p.id
  WHERE p.user_id = caller_id AND p.asset_id = p_asset_id;
  SELECT balance INTO v_balance FROM public.point_wallets WHERE user_id = caller_id;
  RETURN jsonb_build_object(
    'asset_id', p_asset_id, 'target_type', p_target_type,
    'asset_revision', v_asset.revision, 'plan_count', v_plan_count,
    'required_cost_per_plan', v_required, 'charge', v_charge,
    'balance', COALESCE(v_balance, 0)
  );
END;
$$;


ALTER FUNCTION "owntend_monetization_private"."quote_asset_type_change_impl"("p_asset_id" "text", "p_target_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_monetization_private"."quote_maintenance_plan_move_impl"("p_plan_id" "text", "p_target_asset_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  caller_id uuid := auth.uid();
  v_plan public.maintenance_plans%ROWTYPE;
  v_target public.assets%ROWTYPE;
  v_paid smallint;
  v_required smallint;
  v_balance integer;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  SELECT * INTO v_plan FROM public.maintenance_plans
  WHERE user_id = caller_id AND id = p_plan_id;
  SELECT * INTO v_target FROM public.assets
  WHERE user_id = caller_id AND id = p_target_asset_id AND archived_at IS NULL;
  IF v_plan.id IS NULL OR v_target.id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'TARGET_NOT_FOUND';
  END IF;
  SELECT paid_cost INTO v_paid
  FROM owntend_monetization_private.maintenance_plan_entitlements
  WHERE user_id = caller_id AND plan_id = p_plan_id;
  v_paid := COALESCE(v_paid, 0);
  v_required := owntend_monetization_private.required_task_cost_for_asset_type(v_target.asset_type);
  SELECT balance INTO v_balance FROM public.point_wallets WHERE user_id = caller_id;
  RETURN jsonb_build_object(
    'plan_id', p_plan_id, 'target_asset_id', p_target_asset_id,
    'plan_revision', v_plan.revision, 'paid_cost', v_paid,
    'required_cost', v_required, 'charge', GREATEST(0, v_required - v_paid),
    'balance', COALESCE(v_balance, 0)
  );
END;
$$;


ALTER FUNCTION "owntend_monetization_private"."quote_maintenance_plan_move_impl"("p_plan_id" "text", "p_target_asset_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_monetization_private"."record_monetization_event_impl"("p_event_name" "text", "p_properties" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
DECLARE
  caller_id UUID := auth.uid();
  v_key TEXT;
  v_value JSONB;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_event_name NOT IN (
    'ad_native_impression',
    'ad_native_click',
    'ad_interstitial_shown',
    'ad_rewarded_watched',
    'point_shortage_encountered',
    'points_debited'
  ) OR p_properties IS NULL
    OR jsonb_typeof(p_properties) <> 'object'
    OR pg_column_size(p_properties) > 4096
  THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT';
  END IF;

  -- Event-specific allowlist of technical keys only. Unknown keys are
  -- rejected outright so user content or identifying fields can never be
  -- smuggled into the ledger, and every value is bounded and typed.
  FOR v_key, v_value IN
    SELECT * FROM jsonb_each(p_properties)
  LOOP
    CASE p_event_name
      WHEN 'ad_native_impression', 'ad_native_click' THEN
        IF v_key NOT IN ('screen_name', 'ad_unit_id')
          OR v_key = 'screen_name' AND (
            jsonb_typeof(v_value) <> 'string'
            OR v_value #>> '{}' !~ '^[a-z0-9_]{1,32}$'
          )
          OR v_key = 'ad_unit_id' AND (
            jsonb_typeof(v_value) <> 'string'
            OR v_value #>> '{}' !~ '^ca-app-pub-[0-9]{16}/[0-9]{10}$'
          )
        THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
      WHEN 'ad_interstitial_shown' THEN
        IF v_key NOT IN ('cooldown_remaining_sec', 'session_ad_count')
          OR jsonb_typeof(v_value) <> 'number'
        THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
        IF v_key = 'cooldown_remaining_sec' AND (
          (v_value #>> '{}')::numeric <> floor((v_value #>> '{}')::numeric)
          OR (v_value #>> '{}')::int NOT BETWEEN 0 AND 86400
        ) OR v_key = 'session_ad_count' AND (
          (v_value #>> '{}')::numeric <> floor((v_value #>> '{}')::numeric)
          OR (v_value #>> '{}')::int NOT BETWEEN 0 AND 100
        ) THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
      WHEN 'ad_rewarded_watched' THEN
        IF v_key NOT IN ('reward_amount', 'entry_point', 'verification') THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
        IF v_key = 'reward_amount' AND (
          jsonb_typeof(v_value) <> 'number'
          OR (v_value #>> '{}')::numeric <> floor((v_value #>> '{}')::numeric)
          OR (v_value #>> '{}')::int NOT BETWEEN 1 AND 100
        ) THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
        IF v_key = 'entry_point' AND (
          jsonb_typeof(v_value) <> 'string'
          OR v_value #>> '{}' !~ '^[a-z0-9_]{1,32}$'
        ) THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
        IF v_key = 'verification' AND (
          jsonb_typeof(v_value) <> 'string'
          OR v_value #>> '{}' NOT IN ('server_pending')
        ) THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
      WHEN 'point_shortage_encountered' THEN
        IF v_key NOT IN ('attempted_action')
          OR jsonb_typeof(v_value) <> 'string'
          OR v_value #>> '{}' NOT IN ('asset', 'task')
        THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
      WHEN 'points_debited' THEN
        IF v_key NOT IN ('entity_type', 'entity_id', 'cost', 'new_balance', 'included_task_count') THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
        IF v_key = 'entity_type' AND (
          jsonb_typeof(v_value) <> 'string'
          OR v_value #>> '{}' NOT IN ('asset', 'asset_copy', 'task')
        ) THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
        IF v_key = 'entity_id' AND (
          jsonb_typeof(v_value) <> 'string'
          OR v_value #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        ) THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
        IF v_key IN ('cost', 'new_balance', 'included_task_count') AND (
          jsonb_typeof(v_value) <> 'number'
          OR (v_value #>> '{}')::numeric <> floor((v_value #>> '{}')::numeric)
          OR (v_value #>> '{}')::int < 0
          OR (v_value #>> '{}')::int > CASE
            WHEN v_key = 'cost' THEN 1000
            WHEN v_key = 'new_balance' THEN 100000
            ELSE 50
          END
        ) THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
      ELSE
        RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT';
    END CASE;
  END LOOP;

  INSERT INTO public.monetization_events (user_id, event_name, properties)
  VALUES (caller_id, p_event_name, p_properties);
END;
$_$;


ALTER FUNCTION "owntend_monetization_private"."record_monetization_event_impl"("p_event_name" "text", "p_properties" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_monetization_private"."required_task_cost_for_asset_type"("p_asset_type" "text") RETURNS smallint
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  SELECT CASE
    WHEN NOT c.points_enabled OR c.emergency_free_creation_mode OR p_asset_type = 'safety'
      THEN 0::smallint
    ELSE 1::smallint
  END
  FROM public.monetization_config c
  WHERE c.singleton = true;
$$;


ALTER FUNCTION "owntend_monetization_private"."required_task_cost_for_asset_type"("p_asset_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_private"."compact_user_change_feed"("p_retention_days" integer DEFAULT 30, "p_max_retained_rows_per_user" integer DEFAULT 1000) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  v_user RECORD;
  v_deleted integer := 0;
  v_total_deleted integer := 0;
  v_min_seq bigint;
  v_locked public.owner_feed_state%rowtype;
BEGIN
  FOR v_user IN
    SELECT user_id FROM public.owner_feed_state ORDER BY user_id
  LOOP
    -- Serialize against concurrent compaction runs and owner-state writers:
    -- the row lock is held while rows are removed and the state advances.
    SELECT * INTO v_locked
    FROM public.owner_feed_state
    WHERE user_id = v_user.user_id
    FOR UPDATE;

    -- Retained boundary: newest rows inside the retention window, capped per
    -- user; everything strictly below it becomes removable history.
    SELECT coalesce(min(change_seq), v_locked.high_water_seq)
    INTO v_min_seq
    FROM (
      SELECT change_seq
      FROM public.server_change_feed
      WHERE user_id = v_user.user_id
        AND created_at >= clock_timestamp() - make_interval(days => p_retention_days)
      ORDER BY change_seq DESC
      LIMIT p_max_retained_rows_per_user
    ) retained;

    IF v_min_seq IS NULL OR v_min_seq <= 1 THEN
      UPDATE public.owner_feed_state
      SET last_compacted_at = clock_timestamp(),
          updated_at = clock_timestamp()
      WHERE user_id = v_user.user_id;
      CONTINUE;
    END IF;

    WITH deleted AS (
      DELETE FROM public.server_change_feed
      WHERE user_id = v_user.user_id
        AND change_seq < v_min_seq
      RETURNING 1
    )
    SELECT count(*) INTO v_deleted FROM deleted;

    IF v_deleted > 0 THEN
      -- Advancing the durable generation together with the retained boundary
      -- makes every pre-compaction cursor deterministically receive a
      -- resnapshot_required response instead of a silent gap.
      UPDATE public.owner_feed_state
      SET feed_generation = feed_generation + 1,
          retained_min_seq = v_min_seq,
          last_compacted_at = clock_timestamp(),
          updated_at = clock_timestamp()
      WHERE user_id = v_user.user_id;
    ELSE
      UPDATE public.owner_feed_state
      SET last_compacted_at = clock_timestamp(),
          updated_at = clock_timestamp()
      WHERE user_id = v_user.user_id;
    END IF;

    v_total_deleted := v_total_deleted + v_deleted;
  END LOOP;

  RETURN v_total_deleted;
END;
$$;


ALTER FUNCTION "owntend_private"."compact_user_change_feed"("p_retention_days" integer, "p_max_retained_rows_per_user" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_private"."complete_maintenance_task_impl"("p_operation" "jsonb", "p_device_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  request_user uuid := auth.uid();
  operation_id_value text;
  plan_id_value text;
  occurrence_id_value text;
  next_occurrence_id_value text;
  time_zone_id_value text;
  notes_value text;
  expected_plan_revision bigint;
  completed_at_value timestamptz;
  next_due_date_value timestamptz;
  accepted_at_value timestamptz;
  current_plan public.maintenance_plans%ROWTYPE;
  current_record public.maintenance_records%ROWTYPE;
  occurrence_record public.maintenance_records%ROWTYPE;
BEGIN
  IF request_user IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF COALESCE(char_length(btrim(p_device_id)), 0) = 0
     OR char_length(p_device_id) > 200 THEN
    RETURN owntend_private.maintenance_completion_result(
      'invalid', false, 'invalid_device_id'
    );
  END IF;
  IF jsonb_typeof(p_operation) IS DISTINCT FROM 'object'
     OR p_operation->>'contract_version' IS DISTINCT FROM '1' THEN
    RETURN owntend_private.maintenance_completion_result(
      'invalid', false, 'invalid_payload_version'
    );
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_object_keys(p_operation) AS keys(key_name)
    WHERE key_name NOT IN (
      'contract_version', 'operation_id', 'plan_id', 'occurrence_id',
      'expected_plan_revision', 'completed_at', 'time_zone_id', 'notes'
    )
  ) THEN
    RETURN owntend_private.maintenance_completion_result(
      'invalid', false, 'unexpected_payload_field'
    );
  END IF;

  operation_id_value := NULLIF(btrim(p_operation->>'operation_id'), '');
  plan_id_value := NULLIF(btrim(p_operation->>'plan_id'), '');
  occurrence_id_value := NULLIF(btrim(p_operation->>'occurrence_id'), '');
  time_zone_id_value := NULLIF(btrim(p_operation->>'time_zone_id'), '');
  notes_value := NULLIF(btrim(p_operation->>'notes'), '');
  IF operation_id_value IS NULL OR char_length(operation_id_value) > 200
     OR plan_id_value IS NULL OR char_length(plan_id_value) > 200
     OR occurrence_id_value IS NULL OR char_length(occurrence_id_value) > 200
     OR time_zone_id_value IS NULL OR char_length(time_zone_id_value) > 200
     OR char_length(COALESCE(notes_value, '')) > 4000 THEN
    RETURN owntend_private.maintenance_completion_result(
      'invalid', false, 'invalid_identifiers'
    );
  END IF;

  BEGIN
    expected_plan_revision := NULLIF(
      p_operation->>'expected_plan_revision', ''
    )::bigint;
    completed_at_value := date_trunc(
      'second', NULLIF(p_operation->>'completed_at', '')::timestamptz
    );
  EXCEPTION WHEN OTHERS THEN
    RETURN owntend_private.maintenance_completion_result(
      'invalid', false, 'invalid_values'
    );
  END;
  IF completed_at_value IS NULL
     OR completed_at_value > clock_timestamp() + interval '24 hours'
     OR (expected_plan_revision IS NOT NULL AND expected_plan_revision <= 0) THEN
    RETURN owntend_private.maintenance_completion_result(
      'invalid', false, 'invalid_completion'
    );
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_timezone_names
    WHERE name = time_zone_id_value
  ) THEN
    RETURN owntend_private.maintenance_completion_result(
      'invalid', false, 'invalid_time_zone'
    );
  END IF;

  -- Every completion takes locks in this order. The occurrence lock prevents
  -- separate operation ids from accepting the same occurrence concurrently.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      request_user::text || ':plan:' || plan_id_value, 0
    )
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      request_user::text || ':operation:' || operation_id_value, 0
    )
  );

  SELECT * INTO current_record
  FROM public.maintenance_records
  WHERE user_id = request_user AND operation_id = operation_id_value;
  IF FOUND THEN
    SELECT * INTO current_plan
    FROM public.maintenance_plans
    WHERE user_id = request_user AND id = current_record.plan_id;
    IF current_record.plan_id IS DISTINCT FROM plan_id_value
       OR current_record.occurrence_id IS DISTINCT FROM occurrence_id_value
       OR date_trunc('second', current_record.completed_at)
          IS DISTINCT FROM completed_at_value
       OR current_record.time_zone_id IS DISTINCT FROM time_zone_id_value
       OR COALESCE(NULLIF(btrim(current_record.notes), ''), '')
          IS DISTINCT FROM COALESCE(notes_value, '') THEN
      RETURN owntend_private.maintenance_completion_result(
        'conflict', false, 'operation_id_reused', current_plan.revision,
        current_record.id, current_plan.next_due_date,
        to_jsonb(current_plan), to_jsonb(current_record)
      );
    END IF;
    RETURN owntend_private.maintenance_completion_result(
      'already_applied', false, NULL, current_plan.revision,
      current_record.id, current_plan.next_due_date,
      to_jsonb(current_plan), to_jsonb(current_record)
    );
  END IF;

  SELECT * INTO current_plan
  FROM public.maintenance_plans
  WHERE user_id = request_user AND id = plan_id_value
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN owntend_private.maintenance_completion_result(
      'invalid', false, 'plan_unavailable'
    );
  END IF;
  IF current_plan.archived_at IS NOT NULL OR current_plan.is_enabled IS NOT TRUE THEN
    RETURN owntend_private.maintenance_completion_result(
      'conflict', false, 'plan_inactive', current_plan.revision,
      NULL, current_plan.next_due_date, to_jsonb(current_plan), NULL
    );
  END IF;
  IF current_plan.current_occurrence_id IS DISTINCT FROM occurrence_id_value THEN
    SELECT * INTO occurrence_record
    FROM public.maintenance_records
    WHERE user_id = request_user
      AND plan_id = plan_id_value
      AND occurrence_id = occurrence_id_value;
    IF FOUND THEN
      RETURN owntend_private.maintenance_completion_result(
        'conflict', false, 'occurrence_completed_elsewhere', current_plan.revision,
        occurrence_record.id, current_plan.next_due_date,
        to_jsonb(current_plan), to_jsonb(occurrence_record)
      );
    END IF;
    RETURN owntend_private.maintenance_completion_result(
      'conflict', false, 'stale_occurrence', current_plan.revision,
      NULL, current_plan.next_due_date, to_jsonb(current_plan), NULL
    );
  END IF;

  BEGIN
    next_due_date_value := date_trunc(
      'second',
      owntend_private.next_maintenance_due(
        completed_at_value,
        current_plan.recurrence_interval,
        current_plan.recurrence_unit,
        time_zone_id_value
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RETURN owntend_private.maintenance_completion_result(
      'invalid', false, 'invalid_recurrence'
    );
  END;
  accepted_at_value := date_trunc('second', clock_timestamp());
  next_occurrence_id_value := 'next:' || operation_id_value;

  INSERT INTO public.maintenance_records (
    id, user_id, plan_id, occurrence_id, due_date, completed_at,
    accepted_at, time_zone_id, notes, created_at, operation_id
  ) VALUES (
    operation_id_value, request_user, plan_id_value, occurrence_id_value,
    current_plan.next_due_date, completed_at_value, accepted_at_value,
    time_zone_id_value, notes_value, accepted_at_value, operation_id_value
  ) RETURNING * INTO current_record;

  UPDATE public.maintenance_plans
  SET current_occurrence_id = next_occurrence_id_value,
      next_due_date = next_due_date_value,
      updated_at = accepted_at_value
  WHERE user_id = request_user AND id = plan_id_value
  RETURNING * INTO current_plan;

  UPDATE public.notification_inbox
  SET read_at = COALESCE(read_at, accepted_at_value),
      updated_at = accepted_at_value
  WHERE user_id = request_user AND plan_id = plan_id_value;

  IF NOT EXISTS (
    SELECT 1
    FROM public.maintenance_plans AS candidate
    WHERE candidate.user_id = request_user
      AND candidate.archived_at IS NULL
      AND candidate.is_enabled IS TRUE
      AND (candidate.next_due_date AT TIME ZONE time_zone_id_value)::date
          <= (accepted_at_value AT TIME ZONE time_zone_id_value)::date
  ) THEN
    INSERT INTO public.maintenance_reward_eligibilities (
      user_id, completion_id, reward_day, time_zone_id, expires_at,
      created_at
    ) VALUES (
      request_user,
      current_record.id,
      (accepted_at_value AT TIME ZONE time_zone_id_value)::date,
      time_zone_id_value,
      accepted_at_value + interval '30 minutes',
      accepted_at_value
    )
    ON CONFLICT (user_id, completion_id) DO NOTHING;
  END IF;

  RETURN owntend_private.maintenance_completion_result(
    'applied', false, NULL, current_plan.revision,
    current_record.id, current_plan.next_due_date,
    to_jsonb(current_plan), to_jsonb(current_record)
  );
END;
$$;


ALTER FUNCTION "owntend_private"."complete_maintenance_task_impl"("p_operation" "jsonb", "p_device_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_private"."fn_log_server_change_feed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_row jsonb;
  v_identity jsonb;
  v_user_id uuid;
  v_seq bigint;
begin
  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_user_id := nullif(v_row ->> 'user_id', '')::uuid;
  if v_user_id is null then
    raise exception 'Unsupported change-feed row for table %', tg_table_name;
  end if;
  if not exists (select 1 from auth.users where id = v_user_id) then
    return null;
  end if;
  v_identity := owntend_private.sync_feed_identity(tg_table_name, v_row);
  insert into public.server_change_feed (
    user_id,
    entity_type,
    record_id,
    key_data,
    op_type,
    client_updated_at,
    revision,
    contract_version,
    payload
  ) values (
    v_user_id,
    v_identity ->> 'entity_type',
    v_identity ->> 'record_id',
    v_identity -> 'key_data',
    tg_op,
    coalesce(
      nullif(v_row ->> 'client_modified_at', '')::timestamptz,
      nullif(v_row ->> 'updated_at', '')::timestamptz,
      nullif(v_row ->> 'created_at', '')::timestamptz,
      clock_timestamp()
    ),
    coalesce(nullif(v_row ->> 'revision', '')::bigint, 1),
    1,
    case when tg_op = 'DELETE' then null else v_row end
  ) returning change_seq into v_seq;

  insert into public.owner_feed_state (
    user_id, feed_generation, high_water_seq, retained_min_seq, updated_at
  ) values (
    v_user_id, 1, v_seq, v_seq, clock_timestamp()
  ) on conflict (user_id) do update set
    high_water_seq = greatest(owner_feed_state.high_water_seq, excluded.high_water_seq),
    retained_min_seq = case
      when owner_feed_state.retained_min_seq = 0 then excluded.retained_min_seq
      else owner_feed_state.retained_min_seq
    end,
    updated_at = clock_timestamp();

  return null;
end;
$$;


ALTER FUNCTION "owntend_private"."fn_log_server_change_feed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_private"."initialize_owntend_profile_for_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  INSERT INTO public.profiles (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "owntend_private"."initialize_owntend_profile_for_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_private"."initialize_point_wallet_for_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  INSERT INTO public.point_wallets (user_id, balance)
  VALUES (NEW.id, 7)
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.point_transactions (
    user_id, amount, balance_before, balance_after,
    transaction_type, idempotency_key, metadata
  ) VALUES (
    NEW.id, 7, 0, 7,
    'initial_grant', 'initial_grant:' || NEW.id::text,
    jsonb_build_object('grant_type', 'signup_welcome')
  ) ON CONFLICT (user_id, idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "owntend_private"."initialize_point_wallet_for_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_private"."maintenance_completion_result"("p_status" "text", "p_retryable" boolean, "p_conflict_reason" "text" DEFAULT NULL::"text", "p_current_plan_revision" bigint DEFAULT NULL::bigint, "p_resulting_record_id" "text" DEFAULT NULL::"text", "p_resulting_next_due_date" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_plan" "jsonb" DEFAULT NULL::"jsonb", "p_record" "jsonb" DEFAULT NULL::"jsonb") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  SELECT jsonb_build_object(
    'contract_version', 1,
    'status', p_status,
    'retryable', p_retryable,
    'conflict_reason', p_conflict_reason,
    'current_plan_revision', p_current_plan_revision,
    'resulting_record_id', p_resulting_record_id,
    'resulting_next_due_date', p_resulting_next_due_date,
    'reward_eligibility_token', CASE
      WHEN p_status IN ('applied', 'already_applied') THEN (
        SELECT eligibility.token::text
        FROM public.maintenance_reward_eligibilities AS eligibility
        WHERE eligibility.user_id = auth.uid()
          AND eligibility.completion_id = p_resulting_record_id
          AND eligibility.expires_at > clock_timestamp()
      )
      ELSE NULL
    END,
    'plan', p_plan,
    'record', p_record
  );
$$;


ALTER FUNCTION "owntend_private"."maintenance_completion_result"("p_status" "text", "p_retryable" boolean, "p_conflict_reason" "text", "p_current_plan_revision" bigint, "p_resulting_record_id" "text", "p_resulting_next_due_date" timestamp with time zone, "p_plan" "jsonb", "p_record" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_private"."next_maintenance_due"("p_completed_at" timestamp with time zone, "p_interval" integer, "p_unit" "text", "p_time_zone_id" "text") RETURNS timestamp with time zone
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $$
DECLARE
  local_completed timestamp;
  local_next timestamp;
BEGIN
  IF p_completed_at IS NULL OR p_interval IS NULL OR p_interval <= 0
     OR p_time_zone_id IS NULL OR btrim(p_time_zone_id) = '' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_RECURRENCE_INPUT';
  END IF;

  IF p_unit = 'hours' THEN
    RETURN p_completed_at + pg_catalog.make_interval(hours => p_interval);
  END IF;

  local_completed := p_completed_at AT TIME ZONE p_time_zone_id;
  local_next := CASE p_unit
    WHEN 'days' THEN local_completed + pg_catalog.make_interval(days => p_interval)
    WHEN 'weeks' THEN local_completed + pg_catalog.make_interval(weeks => p_interval)
    WHEN 'months' THEN local_completed + pg_catalog.make_interval(months => p_interval)
    WHEN 'years' THEN local_completed + pg_catalog.make_interval(years => p_interval)
    ELSE NULL
  END;
  IF local_next IS NULL THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_RECURRENCE_UNIT';
  END IF;
  RETURN local_next AT TIME ZONE p_time_zone_id;
END;
$$;


ALTER FUNCTION "owntend_private"."next_maintenance_due"("p_completed_at" timestamp with time zone, "p_interval" integer, "p_unit" "text", "p_time_zone_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_private"."restore_maintenance_history_impl"("p_operation" "jsonb", "p_device_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
DECLARE
  caller_id uuid := auth.uid();
  operation_uuid uuid;
  v_client_request_hash text;
  v_request_hash text;
  v_plan_id text;
  v_expected_revision bigint;
  v_snapshot jsonb;
  v_records jsonb;
  v_plan public.maintenance_plans%ROWTYPE;
  v_existing_op owntend_private.maintenance_history_restore_operations%ROWTYPE;
  v_record_json jsonb;
  v_existing_record public.maintenance_records%ROWTYPE;
  v_record_id text;
  v_record_operation_id text;
  v_occurrence_id text;
  v_time_zone_id text;
  v_due_raw timestamptz;
  v_completed_raw timestamptz;
  v_accepted_raw timestamptz;
  v_created_raw timestamptz;
  v_archived_raw timestamptz;
  v_next_due_raw timestamptz;
  v_revision bigint;
  v_match_count integer;
  v_inserted integer := 0;
  v_existing integer := 0;
  v_conflict boolean := false;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF NULLIF(btrim(COALESCE(p_device_id, '')), '') IS NULL
     OR char_length(p_device_id) > 200
     OR p_operation IS NULL OR jsonb_typeof(p_operation) <> 'object'
     OR pg_column_size(p_operation) > 262144
     OR p_operation->>'version' IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
  END IF;
  BEGIN
    operation_uuid := (p_operation->>'operation_id')::uuid;
    v_expected_revision := (p_operation->>'expected_plan_revision')::bigint;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
  END;
  v_client_request_hash := lower(NULLIF(btrim(p_operation->>'request_hash'), ''));
  v_plan_id := NULLIF(btrim(p_operation->>'plan_id'), '');
  v_snapshot := p_operation->'plan_snapshot';
  v_records := p_operation->'records';
  IF v_client_request_hash IS NULL OR v_client_request_hash !~ '^[0-9a-f]{64}$'
     OR v_plan_id IS NULL OR v_expected_revision < 1
     OR jsonb_typeof(v_snapshot) <> 'object'
     OR jsonb_typeof(v_records) <> 'array'
     OR jsonb_array_length(v_records) > 100 THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_records) r
    WHERE jsonb_typeof(r) <> 'object'
  ) OR (
    SELECT count(*) FROM jsonb_array_elements(v_records)
  ) <> (
    SELECT count(DISTINCT r->>'id') FROM jsonb_array_elements(v_records) r
  ) OR (
    SELECT count(*) FROM jsonb_array_elements(v_records)
  ) <> (
    SELECT count(DISTINCT r->>'operation_id') FROM jsonb_array_elements(v_records) r
  ) THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
  END IF;
  v_request_hash := encode(extensions.digest(p_operation::text::bytea, 'sha256'), 'hex');

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(caller_id::text || ':history_restore:' || operation_uuid::text, 0)
  );
  SELECT * INTO v_existing_op
  FROM owntend_private.maintenance_history_restore_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    IF v_existing_op.user_id <> caller_id OR v_existing_op.plan_id <> v_plan_id
       OR v_existing_op.request_hash <> v_request_hash
       OR v_existing_op.client_request_hash <> v_client_request_hash THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
    END IF;
    SELECT * INTO v_plan FROM public.maintenance_plans
    WHERE user_id = caller_id AND id = v_plan_id;
    RETURN jsonb_build_object(
      'status', v_existing_op.result_status,
      'conflict_reason', v_existing_op.conflict_reason,
      'inserted_count', v_existing_op.inserted_count,
      'existing_count', v_existing_op.existing_count,
      'already_processed', true, 'plan', to_jsonb(v_plan)
    );
  END IF;

  SELECT * INTO v_plan FROM public.maintenance_plans
  WHERE user_id = caller_id AND id = v_plan_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'RESTORE_PLAN_NOT_FOUND';
  END IF;
  BEGIN
    v_next_due_raw := (v_snapshot->>'next_due_date')::timestamptz;
    v_archived_raw := CASE
      WHEN v_snapshot->'archived_at' IS NULL OR v_snapshot->'archived_at' = 'null'::jsonb
        THEN NULL
      ELSE (v_snapshot->>'archived_at')::timestamptz
    END;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
  END;
  IF v_next_due_raw IS DISTINCT FROM date_trunc('second', v_next_due_raw)
     OR (v_archived_raw IS NOT NULL
         AND v_archived_raw IS DISTINCT FROM date_trunc('second', v_archived_raw)) THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
  END IF;

  IF v_plan.revision IS DISTINCT FROM v_expected_revision
     OR v_plan.asset_id IS DISTINCT FROM NULLIF(btrim(v_snapshot->>'asset_id'), '')
     OR v_plan.recurrence_interval IS DISTINCT FROM
        NULLIF(v_snapshot->>'recurrence_interval', '')::integer
     OR v_plan.recurrence_unit IS DISTINCT FROM NULLIF(btrim(v_snapshot->>'recurrence_unit'), '')
     OR date_trunc('second', v_plan.next_due_date) IS DISTINCT FROM v_next_due_raw
     OR v_plan.is_enabled IS DISTINCT FROM NULLIF(v_snapshot->>'is_enabled', '')::boolean
     OR date_trunc('second', v_plan.archived_at) IS DISTINCT FROM v_archived_raw THEN
    INSERT INTO owntend_private.maintenance_history_restore_operations (
      operation_id, user_id, plan_id, request_hash, client_request_hash,
      result_status, conflict_reason
    ) VALUES (
      operation_uuid, caller_id, v_plan_id, v_request_hash, v_client_request_hash,
      'conflict', 'plan_snapshot_conflict'
    );
    RETURN jsonb_build_object(
      'status', 'conflict', 'conflict_reason', 'plan_snapshot_conflict',
      'inserted_count', 0, 'existing_count', 0,
      'already_processed', false, 'plan', to_jsonb(v_plan)
    );
  END IF;

  -- Validate the complete batch and detect divergence before inserting any row.
  FOR v_record_json IN SELECT value FROM jsonb_array_elements(v_records)
  LOOP
    v_record_id := NULLIF(btrim(v_record_json->>'id'), '');
    v_record_operation_id := NULLIF(btrim(v_record_json->>'operation_id'), '');
    v_occurrence_id := NULLIF(btrim(v_record_json->>'occurrence_id'), '');
    v_time_zone_id := NULLIF(btrim(v_record_json->>'time_zone_id'), '');
    BEGIN
      v_due_raw := (v_record_json->>'due_date')::timestamptz;
      v_completed_raw := (v_record_json->>'completed_at')::timestamptz;
      v_accepted_raw := (v_record_json->>'accepted_at')::timestamptz;
      v_created_raw := (v_record_json->>'created_at')::timestamptz;
      v_revision := (v_record_json->>'revision')::bigint;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
    END;
    IF v_record_id IS NULL OR char_length(v_record_id) > 200
       OR v_record_operation_id IS NULL OR char_length(v_record_operation_id) > 200
       OR v_occurrence_id IS NULL OR char_length(v_occurrence_id) > 200
       OR v_time_zone_id IS NULL OR char_length(v_time_zone_id) > 200
       OR NULLIF(btrim(v_record_json->>'plan_id'), '') IS DISTINCT FROM v_plan_id
       OR v_revision < 1
       OR char_length(COALESCE(v_record_json->>'notes', '')) > 4000
       OR v_due_raw IS DISTINCT FROM date_trunc('second', v_due_raw)
       OR v_completed_raw IS DISTINCT FROM date_trunc('second', v_completed_raw)
       OR v_accepted_raw IS DISTINCT FROM date_trunc('second', v_accepted_raw)
       OR v_created_raw IS DISTINCT FROM date_trunc('second', v_created_raw) THEN
      RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = v_time_zone_id
    ) THEN
      RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
    END IF;

    SELECT count(*)::integer INTO v_match_count
    FROM public.maintenance_records
    WHERE user_id = caller_id
      AND (
        id = v_record_id
        OR operation_id = v_record_operation_id
        OR (plan_id = v_plan_id AND occurrence_id = v_occurrence_id)
      );
    IF v_match_count = 0 THEN
      CONTINUE;
    END IF;
    IF v_match_count <> 1 THEN
      v_conflict := true;
      EXIT;
    END IF;
    SELECT * INTO v_existing_record
    FROM public.maintenance_records
    WHERE user_id = caller_id
      AND (
        id = v_record_id
        OR operation_id = v_record_operation_id
        OR (plan_id = v_plan_id AND occurrence_id = v_occurrence_id)
      )
    LIMIT 1;
    IF v_existing_record.id IS DISTINCT FROM v_record_id
       OR v_existing_record.operation_id IS DISTINCT FROM v_record_operation_id
       OR v_existing_record.plan_id IS DISTINCT FROM v_plan_id
       OR v_existing_record.occurrence_id IS DISTINCT FROM v_occurrence_id
       OR date_trunc('second', v_existing_record.due_date) IS DISTINCT FROM v_due_raw
       OR date_trunc('second', v_existing_record.completed_at) IS DISTINCT FROM v_completed_raw
       OR date_trunc('second', v_existing_record.accepted_at) IS DISTINCT FROM v_accepted_raw
       OR v_existing_record.time_zone_id IS DISTINCT FROM v_time_zone_id
       OR COALESCE(v_existing_record.notes, '') IS DISTINCT FROM
          COALESCE(NULLIF(btrim(v_record_json->>'notes'), ''), '')
       OR date_trunc('second', v_existing_record.created_at) IS DISTINCT FROM v_created_raw
       OR v_existing_record.revision IS DISTINCT FROM v_revision THEN
      v_conflict := true;
      EXIT;
    END IF;
  END LOOP;

  IF v_conflict THEN
    INSERT INTO owntend_private.maintenance_history_restore_operations (
      operation_id, user_id, plan_id, request_hash, client_request_hash,
      result_status, conflict_reason
    ) VALUES (
      operation_uuid, caller_id, v_plan_id, v_request_hash, v_client_request_hash,
      'conflict', 'history_record_conflict'
    );
    RETURN jsonb_build_object(
      'status', 'conflict', 'conflict_reason', 'history_record_conflict',
      'inserted_count', 0, 'existing_count', 0,
      'already_processed', false, 'plan', to_jsonb(v_plan)
    );
  END IF;

  FOR v_record_json IN SELECT value FROM jsonb_array_elements(v_records)
  LOOP
    v_record_id := btrim(v_record_json->>'id');
    v_record_operation_id := btrim(v_record_json->>'operation_id');
    v_occurrence_id := btrim(v_record_json->>'occurrence_id');
    v_time_zone_id := btrim(v_record_json->>'time_zone_id');
    IF EXISTS (
      SELECT 1 FROM public.maintenance_records
      WHERE user_id = caller_id AND id = v_record_id
    ) THEN
      v_existing := v_existing + 1;
    ELSE
      INSERT INTO public.maintenance_records (
        user_id, id, plan_id, occurrence_id, completed_at, accepted_at,
        time_zone_id, notes, due_date, operation_id, revision, created_at,
        updated_at
      ) VALUES (
        caller_id, v_record_id, v_plan_id, v_occurrence_id,
        (v_record_json->>'completed_at')::timestamptz,
        (v_record_json->>'accepted_at')::timestamptz,
        v_time_zone_id,
        NULLIF(btrim(v_record_json->>'notes'), ''),
        (v_record_json->>'due_date')::timestamptz,
        v_record_operation_id, (v_record_json->>'revision')::bigint,
        (v_record_json->>'created_at')::timestamptz,
        (v_record_json->>'created_at')::timestamptz
      );
      v_inserted := v_inserted + 1;
    END IF;
  END LOOP;

  INSERT INTO owntend_private.maintenance_history_restore_operations (
    operation_id, user_id, plan_id, request_hash, client_request_hash,
    result_status, conflict_reason, inserted_count, existing_count
  ) VALUES (
    operation_uuid, caller_id, v_plan_id, v_request_hash, v_client_request_hash,
    'applied', NULL, v_inserted, v_existing
  );
  RETURN jsonb_build_object(
    'status', 'applied', 'conflict_reason', NULL,
    'inserted_count', v_inserted, 'existing_count', v_existing,
    'already_processed', false, 'plan', to_jsonb(v_plan)
  );
EXCEPTION
  WHEN invalid_text_representation OR check_violation OR not_null_violation THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_HISTORY_RESTORE';
END;
$_$;


ALTER FUNCTION "owntend_private"."restore_maintenance_history_impl"("p_operation" "jsonb", "p_device_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_private"."sync_feed_identity"("p_table_name" "text", "p_row" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO 'pg_catalog'
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


ALTER FUNCTION "owntend_private"."sync_feed_identity"("p_table_name" "text", "p_row" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_private"."undo_maintenance_completion_impl"("p_operation" "jsonb", "p_device_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  request_user uuid := auth.uid();
  operation_id_value text;
  plan_id_value text;
  completion_id_value text;
  completed_occurrence_id_value text;
  expected_current_occurrence_id_value text;
  previous_due_date_value timestamptz;
  expected_current_due timestamptz;
  current_plan public.maintenance_plans%ROWTYPE;
  target_record public.maintenance_records%ROWTYPE;
BEGIN
  IF request_user IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'unauthorized', 'retryable', false,
      'conflict_reason', 'authentication_required', 'rewound', false,
      'plan', NULL
    );
  END IF;
  IF COALESCE(char_length(btrim(p_device_id)), 0) = 0
     OR char_length(p_device_id) > 200
     OR jsonb_typeof(p_operation) IS DISTINCT FROM 'object'
     OR p_operation->>'contract_version' IS DISTINCT FROM '1'
     OR EXISTS (
       SELECT 1 FROM jsonb_object_keys(p_operation) AS keys(key_name)
       WHERE key_name NOT IN (
         'contract_version', 'operation_id', 'plan_id', 'completion_id',
         'completed_occurrence_id', 'expected_current_occurrence_id',
         'previous_due_date', 'expected_current_next_due_date'
       )
     ) THEN
    RETURN jsonb_build_object(
      'status', 'invalid', 'retryable', false,
      'conflict_reason', 'invalid_payload', 'rewound', false, 'plan', NULL
    );
  END IF;

  operation_id_value := NULLIF(btrim(p_operation->>'operation_id'), '');
  plan_id_value := NULLIF(btrim(p_operation->>'plan_id'), '');
  completion_id_value := NULLIF(btrim(p_operation->>'completion_id'), '');
  completed_occurrence_id_value := NULLIF(
    btrim(p_operation->>'completed_occurrence_id'), ''
  );
  expected_current_occurrence_id_value := NULLIF(
    btrim(p_operation->>'expected_current_occurrence_id'), ''
  );
  BEGIN
    previous_due_date_value := date_trunc(
      'second', NULLIF(btrim(p_operation->>'previous_due_date'), '')::timestamptz
    );
    expected_current_due := date_trunc(
      'second',
      NULLIF(btrim(p_operation->>'expected_current_next_due_date'), '')::timestamptz
    );
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'status', 'invalid', 'retryable', false,
      'conflict_reason', 'invalid_timestamp', 'rewound', false, 'plan', NULL
    );
  END;
  IF operation_id_value IS NULL OR char_length(operation_id_value) > 200
     OR plan_id_value IS NULL OR char_length(plan_id_value) > 200
     OR completion_id_value IS NULL OR char_length(completion_id_value) > 200
     OR completed_occurrence_id_value IS NULL
     OR char_length(completed_occurrence_id_value) > 200
     OR expected_current_occurrence_id_value IS NULL
     OR char_length(expected_current_occurrence_id_value) > 200
     OR previous_due_date_value IS NULL OR expected_current_due IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'invalid', 'retryable', false,
      'conflict_reason', 'missing_fields', 'rewound', false, 'plan', NULL
    );
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      request_user::text || ':plan:' || plan_id_value, 0
    )
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      request_user::text || ':operation:' || operation_id_value, 0
    )
  );
  SELECT * INTO current_plan
  FROM public.maintenance_plans
  WHERE user_id = request_user AND id = plan_id_value
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'status', 'invalid', 'retryable', false,
      'conflict_reason', 'plan_missing', 'rewound', false, 'plan', NULL
    );
  END IF;

  SELECT * INTO target_record
  FROM public.maintenance_records
  WHERE user_id = request_user
    AND id = completion_id_value
    AND plan_id = plan_id_value
  FOR UPDATE;

  IF NOT FOUND THEN
    IF current_plan.current_occurrence_id = completed_occurrence_id_value
       AND date_trunc('second', current_plan.next_due_date)
           = previous_due_date_value THEN
      RETURN jsonb_build_object(
        'status', 'already_applied', 'retryable', false,
        'conflict_reason', NULL, 'rewound', true,
        'plan', to_jsonb(current_plan)
      );
    END IF;
    RETURN jsonb_build_object(
      'status', 'conflict', 'retryable', false,
      'conflict_reason', 'stale_occurrence', 'rewound', false,
      'plan', to_jsonb(current_plan)
    );
  END IF;

  IF target_record.occurrence_id IS DISTINCT FROM completed_occurrence_id_value
     OR current_plan.current_occurrence_id
        IS DISTINCT FROM expected_current_occurrence_id_value
     OR date_trunc('second', current_plan.next_due_date)
        IS DISTINCT FROM expected_current_due THEN
    RETURN jsonb_build_object(
      'status', 'conflict', 'retryable', false,
      'conflict_reason', 'stale_occurrence', 'rewound', false,
      'plan', to_jsonb(current_plan)
    );
  END IF;

  DELETE FROM public.maintenance_records
  WHERE user_id = request_user
    AND id = completion_id_value
    AND plan_id = plan_id_value;

  UPDATE public.maintenance_plans
  SET current_occurrence_id = completed_occurrence_id_value,
      next_due_date = previous_due_date_value,
      updated_at = date_trunc('second', clock_timestamp())
  WHERE user_id = request_user AND id = plan_id_value
  RETURNING * INTO current_plan;

  UPDATE public.notification_inbox
  SET read_at = NULL,
      updated_at = date_trunc('second', clock_timestamp())
  WHERE user_id = request_user
    AND id = (
      SELECT id FROM public.notification_inbox
      WHERE user_id = request_user
        AND plan_id = plan_id_value
        AND kind = 'task'
      ORDER BY created_at DESC, id DESC
      LIMIT 1
    );

  RETURN jsonb_build_object(
    'status', 'applied', 'retryable', false,
    'conflict_reason', NULL, 'rewound', true,
    'plan', to_jsonb(current_plan)
  );
END;
$$;


ALTER FUNCTION "owntend_private"."undo_maintenance_completion_impl"("p_operation" "jsonb", "p_device_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "owntend_security"."current_owntend_session_is_active"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM auth.sessions
    WHERE id = (
      NULLIF(
        current_setting('request.jwt.claims', true)::jsonb ->> 'session_id',
        ''
      )
    )::uuid
      AND user_id = (SELECT auth.uid())
  );
$$;


ALTER FUNCTION "owntend_security"."current_owntend_session_is_active"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."acknowledge_media_cleanup"("p_id" bigint) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  IF COALESCE(auth.jwt()->>'role', '') <> 'service_role' THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
  END IF;
  RETURN owntend_media_private.acknowledge_media_cleanup(p_id);
END;
$$;


ALTER FUNCTION "public"."acknowledge_media_cleanup"("p_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."acknowledge_owntend_account_deletion_operation"("p_operation_id" "uuid", "p_subject_binding" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $_$
declare
  operation_row owntend_private.account_deletion_operations%rowtype;
begin
  if p_operation_id is null
    or p_subject_binding is null
    or p_subject_binding !~ '^[0-9a-f]{64}$'
  then
    raise exception using errcode = '22023',
      message = 'INVALID_DELETION_ACKNOWLEDGEMENT';
  end if;

  select * into operation_row
  from owntend_private.account_deletion_operations
  where id = p_operation_id and subject_binding = p_subject_binding
  for update;

  if not found then
    raise exception using errcode = '42501',
      message = 'DELETION_OPERATION_BINDING_MISMATCH';
  end if;
  if operation_row.stage not in ('completed', 'acknowledged') then
    raise exception using errcode = '55000',
      message = 'DELETION_OPERATION_NOT_READY';
  end if;
  if operation_row.stage = 'completed' then
    update owntend_private.account_deletion_operations
    set stage = 'acknowledged',
        acknowledged_at = clock_timestamp(),
        updated_at = clock_timestamp(),
        expires_at = clock_timestamp() + interval '7 days'
    where id = p_operation_id
    returning * into operation_row;
  end if;
  return jsonb_build_object(
    'operation_id', operation_row.id,
    'stage', operation_row.stage,
    'acknowledged', true,
    'acknowledged_at', operation_row.acknowledged_at,
    'remote_boundary_at', operation_row.remote_boundary_at
  );
end;
$_$;


ALTER FUNCTION "public"."acknowledge_owntend_account_deletion_operation"("p_operation_id" "uuid", "p_subject_binding" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."advance_owntend_account_deletion_operation"("p_operation_id" "uuid", "p_user_id" "uuid", "p_stage" "text") RETURNS "text"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  operation_row owntend_private.account_deletion_operations%ROWTYPE;
  current_rank INTEGER;
  requested_rank INTEGER;
BEGIN
  SELECT * INTO operation_row
  FROM owntend_private.account_deletion_operations
  WHERE id = p_operation_id
  FOR UPDATE;

  IF NOT FOUND
    OR operation_row.active_user_id IS DISTINCT FROM p_user_id
  THEN
    RAISE EXCEPTION USING errcode = '42501',
      message = 'DELETION_OPERATION_BINDING_MISMATCH';
  END IF;

  current_rank := CASE operation_row.stage
    WHEN 'prepared' THEN 0
    WHEN 'storage_cleanup' THEN 1
    WHEN 'storage_complete' THEN 2
    WHEN 'auth_delete_started' THEN 3
    WHEN 'completed' THEN 4
    WHEN 'acknowledged' THEN 5
    ELSE NULL
  END;
  requested_rank := CASE p_stage
    WHEN 'prepared' THEN 0
    WHEN 'storage_cleanup' THEN 1
    WHEN 'storage_complete' THEN 2
    WHEN 'auth_delete_started' THEN 3
    ELSE NULL
  END;

  IF requested_rank IS NULL THEN
    RAISE EXCEPTION USING errcode = '22023',
      message = 'INVALID_DELETION_OPERATION_STAGE';
  END IF;

  IF requested_rank > current_rank THEN
    UPDATE owntend_private.account_deletion_operations
    SET
      stage = p_stage,
      last_error_code = NULL,
      updated_at = clock_timestamp(),
      remote_boundary_at = CASE
        WHEN p_stage = 'auth_delete_started'
          AND remote_boundary_at IS NULL
          THEN clock_timestamp()
        ELSE remote_boundary_at
      END
    WHERE id = p_operation_id
    RETURNING * INTO operation_row;
  END IF;

  RETURN operation_row.stage;
END;
$$;


ALTER FUNCTION "public"."advance_owntend_account_deletion_operation"("p_operation_id" "uuid", "p_user_id" "uuid", "p_stage" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."begin_owntend_account_cleanup"("p_user_id" "uuid", "p_object_paths" "text"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  v_job_id UUID;
BEGIN
  INSERT INTO owntend_private.account_deletion_cleanup_jobs (
    user_id,
    target_paths
  )
  VALUES (
    p_user_id,
    COALESCE(p_object_paths, '{}'::TEXT[])
  )
  RETURNING id INTO v_job_id;

  RETURN v_job_id;
END;
$$;


ALTER FUNCTION "public"."begin_owntend_account_cleanup"("p_user_id" "uuid", "p_object_paths" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."begin_owntend_account_deletion_operation"("p_request_hash" "text", "p_subject_binding" "text", "p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $_$
DECLARE
  operation_row owntend_private.account_deletion_operations%ROWTYPE;
BEGIN
  IF p_request_hash IS NULL
    OR p_request_hash !~ '^[0-9a-f]{64}$'
    OR p_subject_binding IS NULL
    OR p_subject_binding !~ '^[0-9a-f]{64}$'
    OR p_user_id IS NULL
  THEN
    RAISE EXCEPTION USING errcode = '22023',
      message = 'INVALID_DELETION_OPERATION';
  END IF;

  PERFORM public.prune_owntend_account_deletion_operations();

  INSERT INTO owntend_private.account_deletion_operations (
    request_hash,
    subject_binding,
    active_user_id
  ) VALUES (
    p_request_hash,
    p_subject_binding,
    p_user_id
  )
  ON CONFLICT (request_hash) DO NOTHING;

  SELECT * INTO operation_row
  FROM owntend_private.account_deletion_operations
  WHERE request_hash = p_request_hash
  FOR UPDATE;

  IF NOT FOUND
    OR operation_row.subject_binding IS DISTINCT FROM p_subject_binding
    OR (
      operation_row.active_user_id IS NOT NULL
      AND operation_row.active_user_id IS DISTINCT FROM p_user_id
    )
  THEN
    RAISE EXCEPTION USING errcode = '42501',
      message = 'DELETION_OPERATION_BINDING_MISMATCH';
  END IF;

  RETURN jsonb_build_object(
    'operation_id', operation_row.id,
    'stage', operation_row.stage,
    'completed', operation_row.stage IN ('completed', 'acknowledged')
  );
END;
$_$;


ALTER FUNCTION "public"."begin_owntend_account_deletion_operation"("p_request_hash" "text", "p_subject_binding" "text", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."change_asset_type_with_point_delta"("p_operation" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.change_asset_type_with_point_delta_impl(p_operation);
END;
$$;


ALTER FUNCTION "public"."change_asset_type_with_point_delta"("p_operation" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_media_cleanup_batch"("p_batch_size" integer DEFAULT 25) RETURNS TABLE("id" bigint, "user_id" "uuid", "object_path" "text", "attempts" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  IF COALESCE(auth.jwt()->>'role', '') <> 'service_role' THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
  END IF;
  RETURN QUERY SELECT * FROM owntend_media_private.claim_media_cleanup_batch(p_batch_size);
END;
$$;


ALTER FUNCTION "public"."claim_media_cleanup_batch"("p_batch_size" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_maintenance_task"("p_operation" "jsonb", "p_device_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_private.complete_maintenance_task_impl(p_operation, p_device_id);
END;
$$;


ALTER FUNCTION "public"."complete_maintenance_task"("p_operation" "jsonb", "p_device_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_owntend_account_cleanup"("p_job_id" "uuid", "p_error" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
BEGIN
  IF p_job_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_CLEANUP_JOB';
  END IF;

  IF p_error IS NOT NULL
    AND (
      CHAR_LENGTH(p_error) NOT BETWEEN 1 AND 120
      OR p_error !~ '^[a-z0-9_]+$'
    )
  THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_CLEANUP_ERROR';
  END IF;

  UPDATE owntend_private.account_deletion_cleanup_jobs
  SET
    processed_at = clock_timestamp(),
    last_error_code = p_error
  WHERE id = p_job_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = 'P0002', message = 'CLEANUP_JOB_NOT_FOUND';
  END IF;
END;
$_$;


ALTER FUNCTION "public"."complete_owntend_account_cleanup"("p_job_id" "uuid", "p_error" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_owntend_account_deletion_operation"("p_operation_id" "uuid", "p_user_id" "uuid", "p_subject_binding" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  operation_row owntend_private.account_deletion_operations%ROWTYPE;
BEGIN
  SELECT * INTO operation_row
  FROM owntend_private.account_deletion_operations
  WHERE id = p_operation_id
    AND subject_binding = p_subject_binding
  FOR UPDATE;

  IF NOT FOUND
    OR (
      operation_row.active_user_id IS NOT NULL
      AND operation_row.active_user_id IS DISTINCT FROM p_user_id
    )
  THEN
    RAISE EXCEPTION USING errcode = '42501',
      message = 'DELETION_OPERATION_BINDING_MISMATCH';
  END IF;

  IF operation_row.stage NOT IN ('completed', 'acknowledged') THEN
    IF operation_row.stage <> 'auth_delete_started' THEN
      RAISE EXCEPTION USING errcode = '55000',
        message = 'DELETION_OPERATION_NOT_READY';
    END IF;
    UPDATE owntend_private.account_deletion_operations
    SET
      active_user_id = NULL,
      stage = 'completed',
      last_error_code = NULL,
      completed_at = clock_timestamp(),
      updated_at = clock_timestamp(),
      expires_at = clock_timestamp() + INTERVAL '90 days',
      remote_boundary_at = COALESCE(remote_boundary_at, clock_timestamp())
    WHERE id = p_operation_id
    RETURNING * INTO operation_row;
  END IF;

  RETURN jsonb_build_object(
    'operation_id', operation_row.id,
    'stage', operation_row.stage,
    'completed', true,
    'expires_at', operation_row.expires_at,
    'remote_boundary_at', operation_row.remote_boundary_at,
    'acknowledged', operation_row.stage = 'acknowledged'
  );
END;
$$;


ALTER FUNCTION "public"."complete_owntend_account_deletion_operation"("p_operation_id" "uuid", "p_user_id" "uuid", "p_subject_binding" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."copy_asset"("p_operation" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.copy_asset_impl(p_operation);
END;
$$;


ALTER FUNCTION "public"."copy_asset"("p_operation" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_asset"("p_operation" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.create_asset_impl(p_operation);
END;
$$;


ALTER FUNCTION "public"."create_asset"("p_operation" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_reward_claim_request"("p_reward_type" "text", "p_time_zone" "text" DEFAULT NULL::"text", "p_eligibility_token" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "sql"
    SET "search_path" TO ''
    AS $$
  SELECT owntend_monetization_private.create_reward_claim_request_impl(
    p_reward_type, p_time_zone, p_eligibility_token
  );
$$;


ALTER FUNCTION "public"."create_reward_claim_request"("p_reward_type" "text", "p_time_zone" "text", "p_eligibility_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_task_with_point_debit"("p_operation" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.create_task_with_point_debit_impl(p_operation);
END;
$$;


ALTER FUNCTION "public"."create_task_with_point_debit"("p_operation" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_asset_photo"("p_asset_id" "text", "p_photo_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  END IF;
  RETURN owntend_media_private.delete_asset_photo_impl(p_asset_id, p_photo_id);
END;
$$;


ALTER FUNCTION "public"."delete_asset_photo"("p_asset_id" "text", "p_photo_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fetch_user_change_feed"("p_since_seq" bigint DEFAULT 0, "p_limit" integer DEFAULT 100, "p_expected_generation" bigint DEFAULT 1) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_limit integer;
  v_state public.owner_feed_state%rowtype;
  v_changes jsonb := '[]'::jsonb;
  v_next_seq bigint;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if p_since_seq < 0 or p_limit < 1 or coalesce(p_expected_generation, 1) < 1 then
    raise exception 'INVALID_FEED_CURSOR' using errcode = '22023';
  end if;
  v_limit := least(p_limit, 100);

  select * into v_state from public.owner_feed_state where user_id = v_user_id;
  if not found then
    return jsonb_build_object(
      'contract_version', 1,
      'feed_generation', 1,
      'changes', '[]'::jsonb,
      'high_water_seq', 0,
      'next_seq', 0,
      'has_more', false,
      'resnapshot_required', false,
      'snapshot_required', false
    );
  end if;

  if (p_expected_generation is distinct from v_state.feed_generation)
    or (p_since_seq > 0 and v_state.retained_min_seq > 0 and p_since_seq < v_state.retained_min_seq)
  then
    return jsonb_build_object(
      'contract_version', 1,
      'feed_generation', v_state.feed_generation,
      'changes', '[]'::jsonb,
      'high_water_seq', v_state.high_water_seq,
      'next_seq', v_state.retained_min_seq,
      'has_more', false,
      'resnapshot_required', true,
      'snapshot_required', true
    );
  end if;

  with page_data as (
    select change_seq, entity_type, record_id, key_data, op_type,
           client_updated_at, revision, created_at, contract_version, payload
    from public.server_change_feed
    where user_id = v_user_id and change_seq > p_since_seq
      and change_seq <= v_state.high_water_seq
    order by change_seq
    limit v_limit
  )
  select coalesce(jsonb_agg(to_jsonb(page_data) order by change_seq), '[]'::jsonb),
         coalesce(max(change_seq), p_since_seq)
  into v_changes, v_next_seq
  from page_data;

  return jsonb_build_object(
    'contract_version', 1,
    'feed_generation', v_state.feed_generation,
    'changes', v_changes,
    'high_water_seq', v_state.high_water_seq,
    'next_seq', v_next_seq,
    'has_more', v_next_seq < v_state.high_water_seq,
    'resnapshot_required', false,
    'snapshot_required', false
  );
end;
$$;


ALTER FUNCTION "public"."fetch_user_change_feed"("p_since_seq" bigint, "p_limit" integer, "p_expected_generation" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."finalize_asset_photo_upload"("p_staging_id" "uuid", "p_asset_id" "text", "p_photo_id" "text", "p_expected_revision" integer DEFAULT 1, "p_caption" "text" DEFAULT NULL::"text", "p_is_primary" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."finalize_asset_photo_upload"("p_staging_id" "uuid", "p_asset_id" "text", "p_photo_id" "text", "p_expected_revision" integer, "p_caption" "text", "p_is_primary" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_charged_operation_status"("p_operation_id" "uuid", "p_request_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.get_charged_operation_status(
    p_operation_id,
    p_request_hash
  );
END;
$$;


ALTER FUNCTION "public"."get_charged_operation_status"("p_operation_id" "uuid", "p_request_hash" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_change_feed_watermark"() RETURNS TABLE("min_change_seq" bigint, "max_change_seq" bigint, "total_changes" bigint, "feed_generation" bigint)
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $$
DECLARE
  v_target_user UUID := auth.uid();
  v_state public.owner_feed_state%ROWTYPE;
  v_count BIGINT;
BEGIN
  IF v_target_user IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_state FROM public.owner_feed_state WHERE user_id = v_target_user;
  SELECT count(*) INTO v_count FROM public.server_change_feed WHERE user_id = v_target_user;

  RETURN QUERY
  SELECT
    COALESCE(v_state.retained_min_seq, 0::bigint),
    COALESCE(v_state.high_water_seq, 0::bigint),
    COALESCE(v_count, 0::bigint),
    COALESCE(v_state.feed_generation, 1::bigint);
END;
$$;


ALTER FUNCTION "public"."get_user_change_feed_watermark"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_recent_owntend_session"("p_user_id" "uuid", "p_session_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM auth.sessions
    WHERE id = p_session_id
      AND user_id = p_user_id
      AND created_at >= NOW() - INTERVAL '5 minutes'
  );
$$;


ALTER FUNCTION "public"."is_recent_owntend_session"("p_user_id" "uuid", "p_session_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."lookup_owntend_account_deletion_operation"("p_request_hash" "text", "p_subject_binding" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $_$
DECLARE
  operation_row owntend_private.account_deletion_operations%ROWTYPE;
BEGIN
  IF p_request_hash IS NULL
    OR p_request_hash !~ '^[0-9a-f]{64}$'
    OR p_subject_binding IS NULL
    OR p_subject_binding !~ '^[0-9a-f]{64}$'
  THEN
    RAISE EXCEPTION USING errcode = '22023',
      message = 'INVALID_DELETION_OPERATION';
  END IF;

  PERFORM public.prune_owntend_account_deletion_operations();

  SELECT * INTO operation_row
  FROM owntend_private.account_deletion_operations
  WHERE request_hash = p_request_hash
    AND subject_binding = p_subject_binding;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'operation_id', operation_row.id,
    'stage', operation_row.stage,
    'active_user_id', operation_row.active_user_id,
    'completed', operation_row.stage IN ('completed', 'acknowledged'),
    'acknowledged', operation_row.stage = 'acknowledged',
    'remote_boundary_at', operation_row.remote_boundary_at,
    'expires_at', operation_row.expires_at
  );
END;
$_$;


ALTER FUNCTION "public"."lookup_owntend_account_deletion_operation"("p_request_hash" "text", "p_subject_binding" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."move_maintenance_plan_with_point_delta"("p_operation" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.move_maintenance_plan_with_point_delta_impl(p_operation);
END;
$$;


ALTER FUNCTION "public"."move_maintenance_plan_with_point_delta"("p_operation" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prepare_asset_photo_upload"("p_asset_id" "text", "p_photo_id" "text", "p_object_size" bigint, "p_mime_type" "text", "p_client_sha256_digest" "text", "p_idempotency_key" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  END IF;
  RETURN owntend_media_private.prepare_asset_photo_upload_impl(
    p_asset_id, p_photo_id, p_object_size, p_mime_type,
    p_client_sha256_digest, p_idempotency_key
  );
END;
$$;


ALTER FUNCTION "public"."prepare_asset_photo_upload"("p_asset_id" "text", "p_photo_id" "text", "p_object_size" bigint, "p_mime_type" "text", "p_client_sha256_digest" "text", "p_idempotency_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."process_admob_ssv_reward"("p_transaction_id" "text", "p_claim_id" "uuid", "p_user_id" "uuid", "p_ad_unit_id" "text", "p_reward_amount" integer, "p_reward_item" "text", "p_google_timestamp" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  claim_row public.reward_claim_requests%ROWTYPE;
  wallet_row public.point_wallets%ROWTYPE;
  config_row public.monetization_config%ROWTYPE;
  new_balance INTEGER;
  existing_claim public.ad_reward_claims%ROWTYPE;
BEGIN
  IF COALESCE(auth.jwt()->>'role', '') <> 'service_role' THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
  END IF;

  IF p_transaction_id IS NULL
    OR CHAR_LENGTH(p_transaction_id) NOT BETWEEN 1 AND 200
    OR p_transaction_id ~ '[[:cntrl:]]'
    OR p_claim_id IS NULL
    OR p_user_id IS NULL
    OR p_ad_unit_id IS NULL
    OR p_reward_amount IS NULL
    OR p_reward_item IS DISTINCT FROM 'points'
    OR p_google_timestamp IS NULL
    OR p_google_timestamp > NOW() + INTERVAL '5 minutes'
    OR p_ad_unit_id NOT IN (
      'ca-app-pub-5274007212820203/4541482404',
      'ca-app-pub-5274007212820203/7295784043'
    )
    OR (
      p_ad_unit_id = 'ca-app-pub-5274007212820203/4541482404'
      AND p_reward_amount <> 1
    )
    OR (
      p_ad_unit_id = 'ca-app-pub-5274007212820203/7295784043'
      AND p_reward_amount <> 2
    )
  THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_SSV_PAYLOAD';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_transaction_id, 0)
  );

  SELECT * INTO existing_claim
  FROM public.ad_reward_claims
  WHERE transaction_id = p_transaction_id;
  IF FOUND THEN
    IF existing_claim.claim_id IS DISTINCT FROM p_claim_id
      OR existing_claim.user_id IS DISTINCT FROM p_user_id
      OR existing_claim.ad_unit_id IS DISTINCT FROM p_ad_unit_id
      OR existing_claim.reward_amount IS DISTINCT FROM p_reward_amount
      OR existing_claim.google_timestamp IS DISTINCT FROM p_google_timestamp
    THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'TRANSACTION_ID_REUSED';
    END IF;

    SELECT balance INTO new_balance
    FROM public.point_wallets
    WHERE user_id = p_user_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING message = 'SSV_SERVER_STATE_INVALID';
    END IF;
    RETURN jsonb_build_object(
      'credited', true,
      'duplicate', true,
      'balance', new_balance,
      'reward_amount', existing_claim.reward_amount
    );
  END IF;

  IF p_google_timestamp < NOW() - INTERVAL '20 minutes' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'SSV_TIMESTAMP_EXPIRED';
  END IF;

  SELECT * INTO claim_row
  FROM public.reward_claim_requests
  WHERE claim_id = p_claim_id
  FOR UPDATE;
  IF NOT FOUND
    OR claim_row.user_id IS DISTINCT FROM p_user_id
    OR claim_row.status IS DISTINCT FROM 'pending'
    OR claim_row.expires_at <= NOW()
    OR claim_row.ad_unit_id IS DISTINCT FROM p_ad_unit_id
    OR claim_row.reward_amount IS DISTINCT FROM p_reward_amount
    OR p_google_timestamp < claim_row.created_at - INTERVAL '5 minutes'
    OR p_google_timestamp > claim_row.expires_at + INTERVAL '5 minutes'
    OR (claim_row.reward_type = 'rewarded_interstitial' AND (
      claim_row.eligibility_token IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.maintenance_reward_eligibilities
        WHERE token = claim_row.eligibility_token
      )
    ))
  THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_REWARD_CLAIM';
  END IF;

  SELECT * INTO wallet_row
  FROM public.point_wallets
  WHERE user_id = p_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING message = 'SSV_SERVER_STATE_INVALID';
  END IF;

  SELECT * INTO config_row
  FROM public.monetization_config
  WHERE singleton = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING message = 'SSV_SERVER_STATE_INVALID';
  END IF;

  IF wallet_row.balance + claim_row.reward_amount > config_row.wallet_cap THEN
    UPDATE public.reward_claim_requests
    SET status = 'rejected', processed_at = NOW(),
        rejection_reason = 'wallet_cap_reached'
    WHERE claim_id = p_claim_id;
    RETURN jsonb_build_object(
      'credited', false,
      'duplicate', false,
      'balance', wallet_row.balance,
      'reason', 'wallet_cap_reached'
    );
  END IF;

  IF claim_row.reward_type = 'rewarded_interstitial' AND EXISTS (
    SELECT 1
    FROM public.point_transactions
    WHERE user_id = p_user_id
      AND transaction_type = 'rewarded_interstitial'
      AND reward_day = claim_row.reward_day
  ) THEN
    UPDATE public.reward_claim_requests
    SET status = 'rejected', processed_at = NOW(),
        rejection_reason = 'daily_reward_already_claimed'
    WHERE claim_id = p_claim_id;
    RETURN jsonb_build_object(
      'credited', false,
      'duplicate', false,
      'balance', wallet_row.balance,
      'reason', 'daily_reward_already_claimed'
    );
  END IF;

  new_balance := wallet_row.balance + claim_row.reward_amount;
  INSERT INTO public.ad_reward_claims (
    transaction_id, claim_id, user_id, reward_type, ad_unit_id,
    reward_amount, reward_day, google_timestamp
  ) VALUES (
    p_transaction_id, p_claim_id, p_user_id, claim_row.reward_type,
    p_ad_unit_id, claim_row.reward_amount, claim_row.reward_day,
    p_google_timestamp
  );

  UPDATE public.point_wallets
  SET balance = new_balance, updated_at = NOW()
  WHERE user_id = p_user_id;

  INSERT INTO public.point_transactions (
    user_id, amount, balance_before, balance_after, transaction_type,
    reference_id, idempotency_key, reward_day, metadata
  ) VALUES (
    p_user_id,
    claim_row.reward_amount,
    wallet_row.balance,
    new_balance,
    claim_row.reward_type,
    p_transaction_id,
    'ssv:' || p_transaction_id,
    claim_row.reward_day,
    jsonb_build_object(
      'claim_id', p_claim_id,
      'ad_unit_id', p_ad_unit_id,
      'google_timestamp', p_google_timestamp
    )
  );

  UPDATE public.reward_claim_requests
  SET status = 'processed', processed_at = NOW(), rejection_reason = NULL
  WHERE claim_id = p_claim_id;

  RETURN jsonb_build_object(
    'credited', true,
    'duplicate', false,
    'balance', new_balance,
    'reward_amount', claim_row.reward_amount
  );
END;
$$;


ALTER FUNCTION "public"."process_admob_ssv_reward"("p_transaction_id" "text", "p_claim_id" "uuid", "p_user_id" "uuid", "p_ad_unit_id" "text", "p_reward_amount" integer, "p_reward_item" "text", "p_google_timestamp" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prune_owntend_account_deletion_operations"() RETURNS integer
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare
  deleted_count integer;
begin
  delete from owntend_private.account_deletion_operations
  where expires_at <= clock_timestamp();
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;


ALTER FUNCTION "public"."prune_owntend_account_deletion_operations"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."quote_asset_type_change"("p_asset_id" "text", "p_target_type" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.quote_asset_type_change_impl(p_asset_id, p_target_type);
END;
$$;


ALTER FUNCTION "public"."quote_asset_type_change"("p_asset_id" "text", "p_target_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."quote_maintenance_plan_move"("p_plan_id" "text", "p_target_asset_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_monetization_private.quote_maintenance_plan_move_impl(
    p_plan_id, p_target_asset_id
  );
END;
$$;


ALTER FUNCTION "public"."quote_maintenance_plan_move"("p_plan_id" "text", "p_target_asset_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_media_cleanup_failure"("p_id" bigint, "p_error_code" "text", "p_terminal" boolean DEFAULT false) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  IF COALESCE(auth.jwt()->>'role', '') <> 'service_role' THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
  END IF;
  RETURN owntend_media_private.record_media_cleanup_failure(p_id, p_error_code, p_terminal);
END;
$$;


ALTER FUNCTION "public"."record_media_cleanup_failure"("p_id" bigint, "p_error_code" "text", "p_terminal" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_monetization_event"("p_event_name" "text", "p_properties" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  PERFORM owntend_monetization_private.record_monetization_event_impl(
    p_event_name,
    p_properties
  );
END;
$$;


ALTER FUNCTION "public"."record_monetization_event"("p_event_name" "text", "p_properties" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_owntend_account_deletion_operation_error"("p_operation_id" "uuid", "p_user_id" "uuid", "p_error_code" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $_$
BEGIN
  IF p_error_code IS NULL
    OR CHAR_LENGTH(p_error_code) NOT BETWEEN 1 AND 120
    OR p_error_code !~ '^[a-z0-9_]+$'
  THEN
    RAISE EXCEPTION USING errcode = '22023',
      message = 'INVALID_DELETION_OPERATION_ERROR';
  END IF;

  UPDATE owntend_private.account_deletion_operations
  SET
    last_error_code = p_error_code,
    updated_at = clock_timestamp()
  WHERE id = p_operation_id
    AND active_user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '42501',
      message = 'DELETION_OPERATION_BINDING_MISMATCH';
  END IF;
END;
$_$;


ALTER FUNCTION "public"."record_owntend_account_deletion_operation_error"("p_operation_id" "uuid", "p_user_id" "uuid", "p_error_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."restore_maintenance_history"("p_operation" "jsonb", "p_device_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_private.restore_maintenance_history_impl(p_operation, p_device_id);
END;
$$;


ALTER FUNCTION "public"."restore_maintenance_history"("p_operation" "jsonb", "p_device_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_owntend_row_metadata"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    NEW.user_id := OLD.user_id;
    IF to_jsonb(NEW) ? 'revision' THEN
      NEW.revision := OLD.revision + 1;
    END IF;
  ELSIF to_jsonb(NEW) ? 'revision' THEN
    NEW.revision := COALESCE(NEW.revision, 1);
  END IF;

  IF to_jsonb(NEW) ? 'updated_at' THEN
    NEW.updated_at := CASE
      WHEN TG_OP = 'UPDATE' THEN clock_timestamp()
      ELSE COALESCE(NEW.updated_at, clock_timestamp())
    END;
  END IF;

  -- Server-side safe default coalescing for synchronized columns
  IF to_jsonb(NEW) ? 'sort_order' THEN
    NEW.sort_order := COALESCE(NEW.sort_order, 0);
  END IF;

  IF to_jsonb(NEW) ? 'required_materials_json' THEN
    NEW.required_materials_json := COALESCE(NEW.required_materials_json, '[]');
  END IF;

  IF to_jsonb(NEW) ? 'reminder_days_before' THEN
    NEW.reminder_days_before := COALESCE(NEW.reminder_days_before, 0);
  END IF;

  IF to_jsonb(NEW) ? 'is_enabled' THEN
    NEW.is_enabled := COALESCE(NEW.is_enabled, true);
  END IF;

  IF to_jsonb(NEW) ? 'is_primary' THEN
    NEW.is_primary := COALESCE(NEW.is_primary, false);
  END IF;

  IF to_jsonb(NEW) ? 'created_at' THEN
    NEW.created_at := COALESCE(NEW.created_at, clock_timestamp());
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_owntend_row_metadata"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_primary_asset_photo"("p_asset_id" "text", "p_photo_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTHENTICATION_REQUIRED';
  END IF;
  RETURN owntend_media_private.set_primary_asset_photo_impl(
    p_asset_id,
    p_photo_id
  );
END;
$$;


ALTER FUNCTION "public"."set_primary_asset_photo"("p_asset_id" "text", "p_photo_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."undo_maintenance_completion"("p_operation" "jsonb", "p_device_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  RETURN owntend_private.undo_maintenance_completion_impl(p_operation, p_device_id);
END;
$$;


ALTER FUNCTION "public"."undo_maintenance_completion"("p_operation" "jsonb", "p_device_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_change_feed_parity"("p_user_id" "uuid") RETURNS TABLE("entity_type" "text", "canonical_count" bigint, "feed_net_count" bigint, "is_parity" boolean)
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
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


ALTER FUNCTION "public"."validate_change_feed_parity"("p_user_id" "uuid") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "owntend_monetization_private"."maintenance_plan_entitlements" (
    "user_id" "uuid" NOT NULL,
    "plan_id" "text" NOT NULL,
    "paid_cost" smallint NOT NULL,
    "origin" "text" NOT NULL,
    "created_by_operation_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "maintenance_plan_entitlements_origin_check" CHECK (("origin" = ANY (ARRAY['task_creation'::"text", 'asset_copy'::"text"]))),
    CONSTRAINT "maintenance_plan_entitlements_paid_cost_check" CHECK ((("paid_cost" >= 0) AND ("paid_cost" <= 1)))
);


ALTER TABLE "owntend_monetization_private"."maintenance_plan_entitlements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "owntend_monetization_private"."plan_economy_operations" (
    "operation_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "operation_kind" "text" NOT NULL,
    "subject_id" "text" NOT NULL,
    "request_hash" "text" NOT NULL,
    "client_request_hash" "text" NOT NULL,
    "charged_amount" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "plan_economy_operations_charged_amount_check" CHECK ((("charged_amount" >= 0) AND ("charged_amount" <= 1000))),
    CONSTRAINT "plan_economy_operations_client_request_hash_check" CHECK (("client_request_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "plan_economy_operations_operation_kind_check" CHECK (("operation_kind" = ANY (ARRAY['plan_move'::"text", 'asset_type_change'::"text"]))),
    CONSTRAINT "plan_economy_operations_request_hash_check" CHECK (("request_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "plan_economy_operations_subject_id_check" CHECK ((("char_length"("subject_id") >= 1) AND ("char_length"("subject_id") <= 200)))
);


ALTER TABLE "owntend_monetization_private"."plan_economy_operations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "owntend_private"."account_deletion_cleanup_jobs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "target_paths" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "processed_at" timestamp with time zone,
    "last_error_code" "text",
    CONSTRAINT "account_deletion_cleanup_jobs_error_code_check" CHECK ((("last_error_code" IS NULL) OR (("char_length"("last_error_code") >= 1) AND ("char_length"("last_error_code") <= 120) AND ("last_error_code" ~ '^[a-z0-9_]+$'::"text"))))
);


ALTER TABLE "owntend_private"."account_deletion_cleanup_jobs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "owntend_private"."account_deletion_operations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "request_hash" "text" NOT NULL,
    "subject_binding" "text" NOT NULL,
    "active_user_id" "uuid",
    "stage" "text" DEFAULT 'prepared'::"text" NOT NULL,
    "last_error_code" "text",
    "remote_boundary_at" timestamp with time zone,
    "acknowledged_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "completed_at" timestamp with time zone,
    "expires_at" timestamp with time zone DEFAULT ("clock_timestamp"() + '7 days'::interval) NOT NULL,
    CONSTRAINT "account_deletion_operations_completion_check" CHECK (((("stage" = ANY (ARRAY['completed'::"text", 'acknowledged'::"text"])) AND ("active_user_id" IS NULL) AND ("completed_at" IS NOT NULL) AND ("last_error_code" IS NULL)) OR (("stage" <> ALL (ARRAY['completed'::"text", 'acknowledged'::"text"])) AND ("active_user_id" IS NOT NULL) AND ("completed_at" IS NULL)))),
    CONSTRAINT "account_deletion_operations_error_code_check" CHECK ((("last_error_code" IS NULL) OR (("char_length"("last_error_code") >= 1) AND ("char_length"("last_error_code") <= 120) AND ("last_error_code" ~ '^[a-z0-9_]+$'::"text")))),
    CONSTRAINT "account_deletion_operations_request_hash_check" CHECK (("request_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "account_deletion_operations_stage_check" CHECK (("stage" = ANY (ARRAY['prepared'::"text", 'storage_cleanup'::"text", 'storage_complete'::"text", 'auth_delete_started'::"text", 'completed'::"text", 'acknowledged'::"text"]))),
    CONSTRAINT "account_deletion_operations_subject_binding_check" CHECK (("subject_binding" ~ '^[0-9a-f]{64}$'::"text"))
);


ALTER TABLE "owntend_private"."account_deletion_operations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "owntend_private"."maintenance_history_restore_operations" (
    "operation_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "plan_id" "text" NOT NULL,
    "request_hash" "text" NOT NULL,
    "client_request_hash" "text" NOT NULL,
    "result_status" "text" NOT NULL,
    "conflict_reason" "text",
    "inserted_count" integer DEFAULT 0 NOT NULL,
    "existing_count" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "maintenance_history_restore_operation_client_request_hash_check" CHECK (("client_request_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "maintenance_history_restore_operations_conflict_reason_check" CHECK ((("conflict_reason" IS NULL) OR ("conflict_reason" = ANY (ARRAY['plan_snapshot_conflict'::"text", 'history_record_conflict'::"text"])))),
    CONSTRAINT "maintenance_history_restore_operations_existing_count_check" CHECK ((("existing_count" >= 0) AND ("existing_count" <= 100))),
    CONSTRAINT "maintenance_history_restore_operations_inserted_count_check" CHECK ((("inserted_count" >= 0) AND ("inserted_count" <= 100))),
    CONSTRAINT "maintenance_history_restore_operations_request_hash_check" CHECK (("request_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "maintenance_history_restore_operations_result_status_check" CHECK (("result_status" = ANY (ARRAY['applied'::"text", 'conflict'::"text"])))
);


ALTER TABLE "owntend_private"."maintenance_history_restore_operations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ad_reward_claims" (
    "transaction_id" "text" NOT NULL,
    "claim_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "reward_type" "text" NOT NULL,
    "ad_unit_id" "text" NOT NULL,
    "reward_amount" integer NOT NULL,
    "reward_day" "date" NOT NULL,
    "google_timestamp" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ad_reward_claims_reward_amount_check" CHECK (("reward_amount" = ANY (ARRAY[1, 2]))),
    CONSTRAINT "ad_reward_claims_reward_type_check" CHECK (("reward_type" = ANY (ARRAY['rewarded_ad'::"text", 'rewarded_interstitial'::"text"]))),
    CONSTRAINT "ad_reward_claims_transaction_id_check" CHECK ((("char_length"("transaction_id") >= 1) AND ("char_length"("transaction_id") <= 200)))
);


ALTER TABLE "public"."ad_reward_claims" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."areas" (
    "user_id" "uuid" NOT NULL,
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "kind" "text" DEFAULT 'indoor'::"text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "archived_at" timestamp with time zone,
    CONSTRAINT "areas_kind_check" CHECK (("kind" = ANY (ARRAY['indoor'::"text", 'outdoor'::"text", 'utility'::"text", 'other'::"text"]))),
    CONSTRAINT "areas_name_check" CHECK ((("char_length"("name") >= 1) AND ("char_length"("name") <= 120))),
    CONSTRAINT "areas_revision_check" CHECK (("revision" > 0))
);

ALTER TABLE ONLY "public"."areas" REPLICA IDENTITY FULL;


ALTER TABLE "public"."areas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."asset_photos" (
    "user_id" "uuid" NOT NULL,
    "id" "text" NOT NULL,
    "asset_id" "text" NOT NULL,
    "object_path" "text",
    "caption" "text",
    "is_primary" boolean DEFAULT false NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "asset_photos_caption_check" CHECK ((("caption" IS NULL) OR ("char_length"("caption") <= 500))),
    CONSTRAINT "asset_photos_owned_path" CHECK ((("object_path" IS NULL) OR ("object_path" ~~ (("user_id")::"text" || '/%'::"text")))),
    CONSTRAINT "asset_photos_revision_check" CHECK (("revision" > 0))
);

ALTER TABLE ONLY "public"."asset_photos" REPLICA IDENTITY FULL;


ALTER TABLE "public"."asset_photos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."asset_tags" (
    "user_id" "uuid" NOT NULL,
    "asset_id" "text" NOT NULL,
    "tag_id" "text" NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "asset_tags_revision_check" CHECK (("revision" > 0))
);

ALTER TABLE ONLY "public"."asset_tags" REPLICA IDENTITY FULL;


ALTER TABLE "public"."asset_tags" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."assets" (
    "user_id" "uuid" NOT NULL,
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "asset_type" "text" DEFAULT 'general'::"text" NOT NULL,
    "room_id" "text" NOT NULL,
    "placement" "text",
    "notes" "text",
    "purchase_date" "date",
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "archived_at" timestamp with time zone,
    CONSTRAINT "assets_asset_type_check" CHECK (("asset_type" = ANY (ARRAY['device'::"text", 'pet'::"text", 'plant'::"text", 'safety'::"text", 'general'::"text"]))),
    CONSTRAINT "assets_name_check" CHECK ((("char_length"("name") >= 1) AND ("char_length"("name") <= 200))),
    CONSTRAINT "assets_notes_check" CHECK ((("notes" IS NULL) OR ("char_length"("notes") <= 10000))),
    CONSTRAINT "assets_placement_check" CHECK ((("placement" IS NULL) OR ("char_length"("placement") <= 300))),
    CONSTRAINT "assets_revision_check" CHECK (("revision" > 0))
);

ALTER TABLE ONLY "public"."assets" REPLICA IDENTITY FULL;


ALTER TABLE "public"."assets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."creation_point_operations" (
    "operation_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "entity_type" "text" NOT NULL,
    "entity_id" "text" NOT NULL,
    "charged_amount" integer NOT NULL,
    "request_hash" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "client_request_hash" "text" NOT NULL,
    CONSTRAINT "creation_point_operations_charged_amount_check" CHECK (("charged_amount" = ANY (ARRAY[0, 1]))),
    CONSTRAINT "creation_point_operations_client_request_hash_check" CHECK (("client_request_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "creation_point_operations_entity_id_check" CHECK ((("char_length"("entity_id") >= 1) AND ("char_length"("entity_id") <= 200))),
    CONSTRAINT "creation_point_operations_entity_type_check" CHECK (("entity_type" = ANY (ARRAY['task'::"text", 'asset'::"text"]))),
    CONSTRAINT "creation_point_operations_request_hash_check" CHECK (("request_hash" ~ '^[0-9a-f]{64}$'::"text"))
);


ALTER TABLE "public"."creation_point_operations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_details" (
    "user_id" "uuid" NOT NULL,
    "asset_id" "text" NOT NULL,
    "brand" "text",
    "model" "text",
    "serial_number" "text",
    "power_source" "text",
    "warranty_until" "date",
    "manual_url" "text",
    "consumable" "text",
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "device_details_brand_check" CHECK ((("brand" IS NULL) OR ("char_length"("brand") <= 120))),
    CONSTRAINT "device_details_consumable_length_check" CHECK ((("consumable" IS NULL) OR ("char_length"("consumable") <= 500))),
    CONSTRAINT "device_details_manual_url_check" CHECK ((("manual_url" IS NULL) OR ("char_length"("manual_url") <= 1000))),
    CONSTRAINT "device_details_model_check" CHECK ((("model" IS NULL) OR ("char_length"("model") <= 120))),
    CONSTRAINT "device_details_power_source_check" CHECK ((("power_source" IS NULL) OR ("char_length"("power_source") <= 80))),
    CONSTRAINT "device_details_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "device_details_serial_number_check" CHECK ((("serial_number" IS NULL) OR ("char_length"("serial_number") <= 160)))
);

ALTER TABLE ONLY "public"."device_details" REPLICA IDENTITY FULL;


ALTER TABLE "public"."device_details" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."maintenance_plan_metadata" (
    "user_id" "uuid" NOT NULL,
    "plan_id" "text" NOT NULL,
    "task_type" "text",
    "location_label" "text",
    "estimated_duration_minutes" integer,
    "required_materials_json" "text" DEFAULT '[]'::"text" NOT NULL,
    "reminder_recommendation" "text",
    "sort_order" integer DEFAULT 0 NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "maintenance_plan_metadata_estimated_duration_minutes_check" CHECK ((("estimated_duration_minutes" IS NULL) OR ("estimated_duration_minutes" >= 0))),
    CONSTRAINT "maintenance_plan_metadata_location_label_check" CHECK ((("location_label" IS NULL) OR ("char_length"("location_label") <= 240))),
    CONSTRAINT "maintenance_plan_metadata_reminder_recommendation_check" CHECK ((("reminder_recommendation" IS NULL) OR ("char_length"("reminder_recommendation") <= 1000))),
    CONSTRAINT "maintenance_plan_metadata_required_materials_json_check" CHECK (("char_length"("required_materials_json") <= 4000)),
    CONSTRAINT "maintenance_plan_metadata_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "maintenance_plan_metadata_task_type_check" CHECK ((("task_type" IS NULL) OR ("char_length"("task_type") <= 120)))
);

ALTER TABLE ONLY "public"."maintenance_plan_metadata" REPLICA IDENTITY FULL;


ALTER TABLE "public"."maintenance_plan_metadata" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."maintenance_plans" (
    "user_id" "uuid" NOT NULL,
    "id" "text" NOT NULL,
    "asset_id" "text" NOT NULL,
    "title" "text" NOT NULL,
    "instructions" "text",
    "recurrence_interval" integer DEFAULT 1 NOT NULL,
    "recurrence_unit" "text" DEFAULT 'months'::"text" NOT NULL,
    "priority" "text" DEFAULT 'medium'::"text" NOT NULL,
    "next_due_date" timestamp with time zone NOT NULL,
    "is_enabled" boolean DEFAULT true NOT NULL,
    "reminder_days_before" integer DEFAULT 0 NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "archived_at" timestamp with time zone,
    "current_occurrence_id" "text" DEFAULT ("gen_random_uuid"())::"text" NOT NULL,
    CONSTRAINT "maintenance_plans_current_occurrence_id_check" CHECK ((("char_length"("btrim"("current_occurrence_id")) >= 1) AND ("char_length"("btrim"("current_occurrence_id")) <= 200))),
    CONSTRAINT "maintenance_plans_instructions_check" CHECK ((("instructions" IS NULL) OR ("char_length"("instructions") <= 4000))),
    CONSTRAINT "maintenance_plans_priority_check" CHECK (("priority" = ANY (ARRAY['low'::"text", 'medium'::"text", 'high'::"text", 'critical'::"text"]))),
    CONSTRAINT "maintenance_plans_recurrence_interval_check" CHECK (("recurrence_interval" > 0)),
    CONSTRAINT "maintenance_plans_recurrence_unit_check" CHECK (("recurrence_unit" = ANY (ARRAY['hours'::"text", 'days'::"text", 'weeks'::"text", 'months'::"text", 'years'::"text"]))),
    CONSTRAINT "maintenance_plans_reminder_days_before_check" CHECK ((("reminder_days_before" IS NULL) OR ("reminder_days_before" >= 0))),
    CONSTRAINT "maintenance_plans_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "maintenance_plans_title_check" CHECK ((("char_length"("title") >= 1) AND ("char_length"("title") <= 200)))
);

ALTER TABLE ONLY "public"."maintenance_plans" REPLICA IDENTITY FULL;


ALTER TABLE "public"."maintenance_plans" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."maintenance_records" (
    "user_id" "uuid" NOT NULL,
    "id" "text" NOT NULL,
    "plan_id" "text" NOT NULL,
    "completed_at" timestamp with time zone NOT NULL,
    "notes" "text",
    "due_date" timestamp with time zone NOT NULL,
    "operation_id" "text" DEFAULT ("gen_random_uuid"())::"text" NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "occurrence_id" "text" NOT NULL,
    "accepted_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "time_zone_id" "text" DEFAULT 'UTC'::"text" NOT NULL,
    CONSTRAINT "maintenance_records_notes_check" CHECK ((("notes" IS NULL) OR ("char_length"("notes") <= 4000))),
    CONSTRAINT "maintenance_records_occurrence_id_check" CHECK ((("char_length"("btrim"("occurrence_id")) >= 1) AND ("char_length"("btrim"("occurrence_id")) <= 200))),
    CONSTRAINT "maintenance_records_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "maintenance_records_time_zone_id_check" CHECK ((("char_length"("btrim"("time_zone_id")) >= 1) AND ("char_length"("btrim"("time_zone_id")) <= 200)))
);

ALTER TABLE ONLY "public"."maintenance_records" REPLICA IDENTITY FULL;


ALTER TABLE "public"."maintenance_records" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."maintenance_reward_eligibilities" (
    "token" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "completion_id" "text" NOT NULL,
    "reward_day" "date" NOT NULL,
    "time_zone_id" "text" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "consumed_at" timestamp with time zone,
    "reward_claim_id" "uuid",
    CONSTRAINT "maintenance_reward_eligibilities_expiry_check" CHECK (("expires_at" > "created_at")),
    CONSTRAINT "maintenance_reward_eligibilities_timezone_check" CHECK ((("char_length"("btrim"("time_zone_id")) >= 1) AND ("char_length"("btrim"("time_zone_id")) <= 200)))
);


ALTER TABLE "public"."maintenance_reward_eligibilities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."media_cleanup_queue" (
    "id" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "object_path" "text" NOT NULL,
    "reason" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "attempts" integer DEFAULT 0 NOT NULL,
    "last_error_code" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "processed_at" timestamp with time zone,
    CONSTRAINT "media_cleanup_queue_attempts_check" CHECK (("attempts" >= 0)),
    CONSTRAINT "media_cleanup_queue_last_error_code_check" CHECK ((("last_error_code" IS NULL) OR (("char_length"("last_error_code") <= 64) AND ("last_error_code" ~ '^[a-z0-9_]+$'::"text")))),
    CONSTRAINT "media_cleanup_queue_reason_check" CHECK (("reason" = ANY (ARRAY['replaced'::"text", 'deleted'::"text", 'expired_staging'::"text", 'account_deleted'::"text", 'orphaned_unstaged'::"text"]))),
    CONSTRAINT "media_cleanup_queue_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'processing'::"text", 'completed'::"text", 'failed_terminal'::"text"])))
);


ALTER TABLE "public"."media_cleanup_queue" OWNER TO "postgres";


ALTER TABLE "public"."media_cleanup_queue" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."media_cleanup_queue_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."media_staging_objects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "staging_path" "text" NOT NULL,
    "object_size" bigint NOT NULL,
    "mime_type" "text" NOT NULL,
    "client_sha256_digest" "text" NOT NULL,
    "status" "text" DEFAULT 'staged'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "finalized_at" timestamp with time zone,
    "idempotency_key" "text" NOT NULL,
    "asset_id" "text" NOT NULL,
    "photo_id" "text" NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("clock_timestamp"() + '1 day'::interval) NOT NULL,
    "attempt" integer DEFAULT 0 NOT NULL,
    CONSTRAINT "media_staging_objects_attempt_check" CHECK (("attempt" >= 0)),
    CONSTRAINT "media_staging_objects_digest_check" CHECK (("client_sha256_digest" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "media_staging_objects_expiry_check" CHECK (("expires_at" > "created_at")),
    CONSTRAINT "media_staging_objects_idempotency_check" CHECK (("idempotency_key" ~ '^[A-Za-z0-9_-]{16,120}$'::"text")),
    CONSTRAINT "media_staging_objects_path_check" CHECK (("staging_path" ~~ (("user_id")::"text" || '/media/%'::"text"))),
    CONSTRAINT "media_staging_objects_size_check" CHECK ((("object_size" >= 1) AND ("object_size" <= 10485760))),
    CONSTRAINT "media_staging_objects_status_check" CHECK (("status" = ANY (ARRAY['staged'::"text", 'finalized'::"text", 'expired'::"text", 'failed'::"text"])))
);


ALTER TABLE "public"."media_staging_objects" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."monetization_config" (
    "singleton" boolean DEFAULT true NOT NULL,
    "ads_enabled" boolean DEFAULT true NOT NULL,
    "native_ads_enabled" boolean DEFAULT true NOT NULL,
    "interstitial_ads_enabled" boolean DEFAULT true NOT NULL,
    "rewarded_ads_enabled" boolean DEFAULT true NOT NULL,
    "rewarded_interstitial_enabled" boolean DEFAULT true NOT NULL,
    "points_enabled" boolean DEFAULT true NOT NULL,
    "emergency_free_creation_mode" boolean DEFAULT false NOT NULL,
    "wallet_cap" integer DEFAULT 20 NOT NULL,
    "interstitial_cooldown_seconds" integer DEFAULT 180 NOT NULL,
    "rapid_completion_window_seconds" integer DEFAULT 60 NOT NULL,
    "reward_claim_cooldown_seconds" integer DEFAULT 45 NOT NULL,
    "interstitial_session_cap" integer DEFAULT 3 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "monetization_config_interstitial_cooldown_seconds_check" CHECK ((("interstitial_cooldown_seconds" >= 0) AND ("interstitial_cooldown_seconds" <= 86400))),
    CONSTRAINT "monetization_config_interstitial_session_cap_check" CHECK ((("interstitial_session_cap" >= 0) AND ("interstitial_session_cap" <= 20))),
    CONSTRAINT "monetization_config_rapid_completion_window_seconds_check" CHECK ((("rapid_completion_window_seconds" >= 0) AND ("rapid_completion_window_seconds" <= 3600))),
    CONSTRAINT "monetization_config_reward_claim_cooldown_seconds_check" CHECK ((("reward_claim_cooldown_seconds" >= 0) AND ("reward_claim_cooldown_seconds" <= 3600))),
    CONSTRAINT "monetization_config_singleton_check" CHECK ("singleton")
);


ALTER TABLE "public"."monetization_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."monetization_events" (
    "id" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "event_name" "text" NOT NULL,
    "properties" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "occurred_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "monetization_events_event_name_check" CHECK (("event_name" = ANY (ARRAY['ad_native_impression'::"text", 'ad_native_click'::"text", 'ad_interstitial_shown'::"text", 'ad_rewarded_watched'::"text", 'point_shortage_encountered'::"text", 'points_debited'::"text"])))
);


ALTER TABLE "public"."monetization_events" OWNER TO "postgres";


ALTER TABLE "public"."monetization_events" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."monetization_events_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."notification_inbox" (
    "user_id" "uuid" NOT NULL,
    "id" "text" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "kind" "text" NOT NULL,
    "route" "text",
    "plan_id" "text",
    "dedupe_key" "text" NOT NULL,
    "read_at" timestamp with time zone,
    "message_code" "text" DEFAULT 'generic'::"text" NOT NULL,
    "message_args" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "notification_inbox_body_check" CHECK (("char_length"("body") <= 20000)),
    CONSTRAINT "notification_inbox_dedupe_key_check" CHECK (("char_length"("dedupe_key") <= 128)),
    CONSTRAINT "notification_inbox_kind_check" CHECK ((("char_length"("kind") >= 1) AND ("char_length"("kind") <= 80))),
    CONSTRAINT "notification_inbox_message_args_check" CHECK (("jsonb_typeof"("message_args") = 'object'::"text")),
    CONSTRAINT "notification_inbox_message_code_check" CHECK (("message_code" = ANY (ARRAY['generic'::"text", 'weather_alert'::"text", 'task_overdue'::"text", 'task_due_today'::"text", 'daily_digest'::"text", 'task_skipped'::"text", 'task_postponed'::"text"]))),
    CONSTRAINT "notification_inbox_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "notification_inbox_route_check" CHECK ((("route" IS NULL) OR ("char_length"("route") <= 1000))),
    CONSTRAINT "notification_inbox_title_check" CHECK ((("char_length"("title") >= 1) AND ("char_length"("title") <= 500)))
);

ALTER TABLE ONLY "public"."notification_inbox" REPLICA IDENTITY FULL;


ALTER TABLE "public"."notification_inbox" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."owner_feed_state" (
    "user_id" "uuid" NOT NULL,
    "feed_generation" bigint DEFAULT 1 NOT NULL,
    "high_water_seq" bigint DEFAULT 0 NOT NULL,
    "retained_min_seq" bigint DEFAULT 0 NOT NULL,
    "last_compacted_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "owner_feed_state_generation_check" CHECK (("feed_generation" >= 1)),
    CONSTRAINT "owner_feed_state_high_water_check" CHECK (("high_water_seq" >= 0)),
    CONSTRAINT "owner_feed_state_retained_min_check" CHECK (("retained_min_seq" >= 0))
);


ALTER TABLE "public"."owner_feed_state" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pet_details" (
    "user_id" "uuid" NOT NULL,
    "asset_id" "text" NOT NULL,
    "species" "text",
    "breed" "text",
    "birth_date" "date",
    "microchip_id" "text",
    "vet_name" "text",
    "vet_phone" "text",
    "feeding_notes" "text",
    "medical_notes" "text",
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "pet_details_breed_check" CHECK ((("breed" IS NULL) OR ("char_length"("breed") <= 120))),
    CONSTRAINT "pet_details_feeding_notes_check" CHECK ((("feeding_notes" IS NULL) OR ("char_length"("feeding_notes") <= 4000))),
    CONSTRAINT "pet_details_medical_notes_check" CHECK ((("medical_notes" IS NULL) OR ("char_length"("medical_notes") <= 4000))),
    CONSTRAINT "pet_details_microchip_id_check" CHECK ((("microchip_id" IS NULL) OR ("char_length"("microchip_id") <= 120))),
    CONSTRAINT "pet_details_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "pet_details_species_check" CHECK ((("species" IS NULL) OR ("char_length"("species") <= 120))),
    CONSTRAINT "pet_details_vet_name_check" CHECK ((("vet_name" IS NULL) OR ("char_length"("vet_name") <= 200))),
    CONSTRAINT "pet_details_vet_phone_check" CHECK ((("vet_phone" IS NULL) OR ("char_length"("vet_phone") <= 80)))
);

ALTER TABLE ONLY "public"."pet_details" REPLICA IDENTITY FULL;


ALTER TABLE "public"."pet_details" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."plant_details" (
    "user_id" "uuid" NOT NULL,
    "asset_id" "text" NOT NULL,
    "species" "text",
    "sunlight" "text",
    "watering_interval_days" integer,
    "pot_size" "text",
    "last_repotted_at" timestamp with time zone,
    "toxicity_notes" "text",
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "plant_details_pot_size_check" CHECK ((("pot_size" IS NULL) OR ("char_length"("pot_size") <= 120))),
    CONSTRAINT "plant_details_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "plant_details_species_check" CHECK ((("species" IS NULL) OR ("char_length"("species") <= 200))),
    CONSTRAINT "plant_details_sunlight_check" CHECK ((("sunlight" IS NULL) OR ("char_length"("sunlight") <= 120))),
    CONSTRAINT "plant_details_toxicity_notes_check" CHECK ((("toxicity_notes" IS NULL) OR ("char_length"("toxicity_notes") <= 4000))),
    CONSTRAINT "plant_details_watering_interval_days_check" CHECK ((("watering_interval_days" IS NULL) OR ("watering_interval_days" > 0)))
);

ALTER TABLE ONLY "public"."plant_details" REPLICA IDENTITY FULL;


ALTER TABLE "public"."plant_details" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."point_transactions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "amount" integer NOT NULL,
    "balance_before" integer NOT NULL,
    "balance_after" integer NOT NULL,
    "transaction_type" "text" NOT NULL,
    "reference_id" "text",
    "idempotency_key" "text" NOT NULL,
    "reward_day" "date",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "point_transactions_amount_check" CHECK (("amount" <> 0)),
    CONSTRAINT "point_transactions_balance_after_check" CHECK ((("balance_after" >= 0) AND ("balance_after" <= 1000) AND ("balance_after" = ("balance_before" + "amount")))),
    CONSTRAINT "point_transactions_balance_before_check" CHECK ((("balance_before" >= 0) AND ("balance_before" <= 1000))),
    CONSTRAINT "point_transactions_idempotency_key_check" CHECK ((("char_length"("idempotency_key") >= 1) AND ("char_length"("idempotency_key") <= 200))),
    CONSTRAINT "point_transactions_transaction_type_check" CHECK (("transaction_type" = ANY (ARRAY['initial_grant'::"text", 'task_creation'::"text", 'asset_creation'::"text", 'task_entitlement_upgrade'::"text", 'rewarded_ad'::"text", 'rewarded_interstitial'::"text", 'refund'::"text", 'admin_adjustment'::"text"])))
);


ALTER TABLE "public"."point_transactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."point_wallets" (
    "user_id" "uuid" NOT NULL,
    "balance" integer DEFAULT 7 NOT NULL,
    "reward_time_zone" "text" DEFAULT 'UTC'::"text" NOT NULL,
    "reward_time_zone_updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "point_wallets_balance_check" CHECK ((("balance" >= 0) AND ("balance" <= 1000))),
    CONSTRAINT "point_wallets_reward_time_zone_check" CHECK ((("char_length"("reward_time_zone") >= 1) AND ("char_length"("reward_time_zone") <= 100)))
);

ALTER TABLE ONLY "public"."point_wallets" REPLICA IDENTITY FULL;


ALTER TABLE "public"."point_wallets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "user_id" "uuid" NOT NULL,
    "nickname" "text",
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "client_modified_at" timestamp with time zone,
    "revision" bigint DEFAULT 1 NOT NULL,
    CONSTRAINT "profiles_nickname_length" CHECK ((("nickname" IS NULL) OR (("char_length"("nickname") >= 1) AND ("char_length"("nickname") <= 120) AND ("nickname" = "btrim"("nickname"))))),
    CONSTRAINT "profiles_revision_positive" CHECK (("revision" > 0))
);

ALTER TABLE ONLY "public"."profiles" REPLICA IDENTITY FULL;


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reward_claim_requests" (
    "claim_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "reward_type" "text" NOT NULL,
    "ad_unit_id" "text" NOT NULL,
    "reward_amount" integer NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "reward_day" "date" DEFAULT ("timezone"('utc'::"text", "now"()))::"date" NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '00:15:00'::interval) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "processed_at" timestamp with time zone,
    "rejection_reason" "text",
    "eligibility_token" "uuid",
    CONSTRAINT "reward_claim_requests_ad_unit_id_check" CHECK ((("char_length"("ad_unit_id") >= 1) AND ("char_length"("ad_unit_id") <= 120))),
    CONSTRAINT "reward_claim_requests_rejection_reason_check" CHECK ((("rejection_reason" IS NULL) OR ("char_length"("rejection_reason") <= 200))),
    CONSTRAINT "reward_claim_requests_reward_amount_check" CHECK (("reward_amount" = ANY (ARRAY[1, 2]))),
    CONSTRAINT "reward_claim_requests_reward_type_check" CHECK (("reward_type" = ANY (ARRAY['rewarded_ad'::"text", 'rewarded_interstitial'::"text"]))),
    CONSTRAINT "reward_claim_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'processed'::"text", 'expired'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."reward_claim_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rooms" (
    "user_id" "uuid" NOT NULL,
    "id" "text" NOT NULL,
    "area_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "room_type" "text" DEFAULT 'other'::"text" NOT NULL,
    "notes" "text",
    "sort_order" integer DEFAULT 0 NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "archived_at" timestamp with time zone,
    CONSTRAINT "rooms_name_check" CHECK ((("char_length"("name") >= 1) AND ("char_length"("name") <= 120))),
    CONSTRAINT "rooms_notes_check" CHECK ((("notes" IS NULL) OR ("char_length"("notes") <= 4000))),
    CONSTRAINT "rooms_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "rooms_room_type_check" CHECK ((("char_length"("room_type") >= 1) AND ("char_length"("room_type") <= 120)))
);

ALTER TABLE ONLY "public"."rooms" REPLICA IDENTITY FULL;


ALTER TABLE "public"."rooms" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."safety_details" (
    "user_id" "uuid" NOT NULL,
    "asset_id" "text" NOT NULL,
    "safety_type" "text",
    "installed_at" timestamp with time zone,
    "expires_at" timestamp with time zone,
    "battery_type" "text",
    "test_interval_days" integer,
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "safety_details_battery_type_check" CHECK ((("battery_type" IS NULL) OR ("char_length"("battery_type") <= 120))),
    CONSTRAINT "safety_details_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "safety_details_safety_type_check" CHECK ((("safety_type" IS NULL) OR ("char_length"("safety_type") <= 120))),
    CONSTRAINT "safety_details_test_interval_days_check" CHECK ((("test_interval_days" IS NULL) OR ("test_interval_days" > 0)))
);

ALTER TABLE ONLY "public"."safety_details" REPLICA IDENTITY FULL;


ALTER TABLE "public"."safety_details" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."server_change_feed" (
    "change_seq" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "entity_type" "text" NOT NULL,
    "record_id" "text" NOT NULL,
    "op_type" "text" NOT NULL,
    "client_updated_at" timestamp with time zone NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "key_data" "jsonb" NOT NULL,
    "contract_version" smallint DEFAULT 1 NOT NULL,
    "payload" "jsonb",
    CONSTRAINT "server_change_feed_contract_check" CHECK (("contract_version" = 1)),
    CONSTRAINT "server_change_feed_entity_type_check" CHECK (("entity_type" = ANY (ARRAY['profile'::"text", 'area'::"text", 'room'::"text", 'asset'::"text", 'device_detail'::"text", 'pet_detail'::"text", 'plant_detail'::"text", 'safety_detail'::"text", 'tag'::"text", 'asset_tag'::"text", 'asset_photo'::"text", 'maintenance_plan'::"text", 'maintenance_plan_metadata'::"text", 'maintenance_record'::"text", 'notification_inbox'::"text", 'user_setting'::"text", 'streak'::"text"]))),
    CONSTRAINT "server_change_feed_key_data_object_check" CHECK (("jsonb_typeof"("key_data") = 'object'::"text")),
    CONSTRAINT "server_change_feed_op_type_check" CHECK (("op_type" = ANY (ARRAY['INSERT'::"text", 'UPDATE'::"text", 'DELETE'::"text"]))),
    CONSTRAINT "server_change_feed_payload_check" CHECK (((("op_type" = 'DELETE'::"text") AND ("payload" IS NULL)) OR (("op_type" = ANY (ARRAY['INSERT'::"text", 'UPDATE'::"text"])) AND ("jsonb_typeof"("payload") = 'object'::"text"))))
);


ALTER TABLE "public"."server_change_feed" OWNER TO "postgres";


ALTER TABLE "public"."server_change_feed" ALTER COLUMN "change_seq" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."server_change_feed_change_seq_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."streaks" (
    "user_id" "uuid" NOT NULL,
    "id" "text" DEFAULT 'default'::"text" NOT NULL,
    "current_streak" integer DEFAULT 0 NOT NULL,
    "longest_streak" integer DEFAULT 0 NOT NULL,
    "last_completion_date" "date",
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "streaks_check" CHECK ((("longest_streak" >= 0) AND ("longest_streak" >= "current_streak"))),
    CONSTRAINT "streaks_current_streak_check" CHECK (("current_streak" >= 0)),
    CONSTRAINT "streaks_revision_check" CHECK (("revision" > 0))
);

ALTER TABLE ONLY "public"."streaks" REPLICA IDENTITY FULL;


ALTER TABLE "public"."streaks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tags" (
    "user_id" "uuid" NOT NULL,
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "tags_name_check" CHECK ((("char_length"("name") >= 1) AND ("char_length"("name") <= 120))),
    CONSTRAINT "tags_revision_check" CHECK (("revision" > 0))
);

ALTER TABLE ONLY "public"."tags" REPLICA IDENTITY FULL;


ALTER TABLE "public"."tags" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_settings" (
    "user_id" "uuid" NOT NULL,
    "key" "text" NOT NULL,
    "value" "text" NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "user_settings_key_check" CHECK (("key" = ANY (ARRAY['theme'::"text", 'app_language'::"text", 'app_language_explicit'::"text", 'theme_time_of_day_enabled'::"text", 'notification_preferences'::"text", 'onboarding_completed'::"text", 'permission_education_seen'::"text", 'home_location'::"text"]))),
    CONSTRAINT "user_settings_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "user_settings_value_check" CHECK (("octet_length"("value") <= 65536))
);

ALTER TABLE ONLY "public"."user_settings" REPLICA IDENTITY FULL;


ALTER TABLE "public"."user_settings" OWNER TO "postgres";


ALTER TABLE ONLY "owntend_monetization_private"."maintenance_plan_entitlements"
    ADD CONSTRAINT "maintenance_plan_entitlements_pkey" PRIMARY KEY ("user_id", "plan_id");



ALTER TABLE ONLY "owntend_monetization_private"."plan_economy_operations"
    ADD CONSTRAINT "plan_economy_operations_pkey" PRIMARY KEY ("operation_id");



ALTER TABLE ONLY "owntend_private"."account_deletion_cleanup_jobs"
    ADD CONSTRAINT "account_deletion_cleanup_jobs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "owntend_private"."account_deletion_operations"
    ADD CONSTRAINT "account_deletion_operations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "owntend_private"."account_deletion_operations"
    ADD CONSTRAINT "account_deletion_operations_request_hash_key" UNIQUE ("request_hash");



ALTER TABLE ONLY "owntend_private"."maintenance_history_restore_operations"
    ADD CONSTRAINT "maintenance_history_restore_operations_pkey" PRIMARY KEY ("operation_id");



ALTER TABLE ONLY "public"."ad_reward_claims"
    ADD CONSTRAINT "ad_reward_claims_claim_id_key" UNIQUE ("claim_id");



ALTER TABLE ONLY "public"."ad_reward_claims"
    ADD CONSTRAINT "ad_reward_claims_pkey" PRIMARY KEY ("transaction_id");



ALTER TABLE ONLY "public"."areas"
    ADD CONSTRAINT "areas_pkey" PRIMARY KEY ("user_id", "id");



ALTER TABLE ONLY "public"."asset_photos"
    ADD CONSTRAINT "asset_photos_pkey" PRIMARY KEY ("user_id", "id");



ALTER TABLE ONLY "public"."asset_tags"
    ADD CONSTRAINT "asset_tags_pkey" PRIMARY KEY ("user_id", "asset_id", "tag_id");



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_pkey" PRIMARY KEY ("user_id", "id");



ALTER TABLE ONLY "public"."creation_point_operations"
    ADD CONSTRAINT "creation_point_operations_pkey" PRIMARY KEY ("operation_id");



ALTER TABLE ONLY "public"."creation_point_operations"
    ADD CONSTRAINT "creation_point_operations_user_id_entity_type_entity_id_key" UNIQUE ("user_id", "entity_type", "entity_id");



ALTER TABLE ONLY "public"."device_details"
    ADD CONSTRAINT "device_details_pkey" PRIMARY KEY ("user_id", "asset_id");



ALTER TABLE ONLY "public"."maintenance_plan_metadata"
    ADD CONSTRAINT "maintenance_plan_metadata_pkey" PRIMARY KEY ("user_id", "plan_id");



ALTER TABLE ONLY "public"."maintenance_plans"
    ADD CONSTRAINT "maintenance_plans_pkey" PRIMARY KEY ("user_id", "id");



ALTER TABLE ONLY "public"."maintenance_records"
    ADD CONSTRAINT "maintenance_records_pkey" PRIMARY KEY ("user_id", "id");



ALTER TABLE ONLY "public"."maintenance_reward_eligibilities"
    ADD CONSTRAINT "maintenance_reward_eligibilities_completion_key" UNIQUE ("user_id", "completion_id");



ALTER TABLE ONLY "public"."maintenance_reward_eligibilities"
    ADD CONSTRAINT "maintenance_reward_eligibilities_pkey" PRIMARY KEY ("token");



ALTER TABLE ONLY "public"."maintenance_reward_eligibilities"
    ADD CONSTRAINT "maintenance_reward_eligibilities_reward_claim_id_key" UNIQUE ("reward_claim_id");



ALTER TABLE ONLY "public"."media_cleanup_queue"
    ADD CONSTRAINT "media_cleanup_queue_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."media_staging_objects"
    ADD CONSTRAINT "media_staging_objects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."media_staging_objects"
    ADD CONSTRAINT "media_staging_objects_staging_path_key" UNIQUE ("staging_path");



ALTER TABLE ONLY "public"."monetization_config"
    ADD CONSTRAINT "monetization_config_pkey" PRIMARY KEY ("singleton");



ALTER TABLE ONLY "public"."monetization_events"
    ADD CONSTRAINT "monetization_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_inbox"
    ADD CONSTRAINT "notification_inbox_pkey" PRIMARY KEY ("user_id", "id");



ALTER TABLE ONLY "public"."owner_feed_state"
    ADD CONSTRAINT "owner_feed_state_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."pet_details"
    ADD CONSTRAINT "pet_details_pkey" PRIMARY KEY ("user_id", "asset_id");



ALTER TABLE ONLY "public"."plant_details"
    ADD CONSTRAINT "plant_details_pkey" PRIMARY KEY ("user_id", "asset_id");



ALTER TABLE ONLY "public"."point_transactions"
    ADD CONSTRAINT "point_transactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."point_transactions"
    ADD CONSTRAINT "point_transactions_user_id_idempotency_key_key" UNIQUE ("user_id", "idempotency_key");



ALTER TABLE ONLY "public"."point_wallets"
    ADD CONSTRAINT "point_wallets_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."reward_claim_requests"
    ADD CONSTRAINT "reward_claim_requests_eligibility_token_key" UNIQUE ("eligibility_token");



ALTER TABLE ONLY "public"."reward_claim_requests"
    ADD CONSTRAINT "reward_claim_requests_pkey" PRIMARY KEY ("claim_id");



ALTER TABLE ONLY "public"."rooms"
    ADD CONSTRAINT "rooms_pkey" PRIMARY KEY ("user_id", "id");



ALTER TABLE ONLY "public"."safety_details"
    ADD CONSTRAINT "safety_details_pkey" PRIMARY KEY ("user_id", "asset_id");



ALTER TABLE ONLY "public"."server_change_feed"
    ADD CONSTRAINT "server_change_feed_pkey" PRIMARY KEY ("change_seq");



ALTER TABLE ONLY "public"."streaks"
    ADD CONSTRAINT "streaks_pkey" PRIMARY KEY ("user_id", "id");



ALTER TABLE ONLY "public"."tags"
    ADD CONSTRAINT "tags_pkey" PRIMARY KEY ("user_id", "id");



ALTER TABLE ONLY "public"."user_settings"
    ADD CONSTRAINT "user_settings_pkey" PRIMARY KEY ("user_id", "key");



CREATE INDEX "maintenance_plan_entitlements_operation_idx" ON "owntend_monetization_private"."maintenance_plan_entitlements" USING "btree" ("created_by_operation_id") WHERE ("created_by_operation_id" IS NOT NULL);



CREATE INDEX "plan_economy_operations_user_created_idx" ON "owntend_monetization_private"."plan_economy_operations" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "plan_economy_operations_user_kind_subject_idx" ON "owntend_monetization_private"."plan_economy_operations" USING "btree" ("user_id", "operation_kind", "subject_id");



CREATE INDEX "account_deletion_cleanup_jobs_user_id_idx" ON "owntend_private"."account_deletion_cleanup_jobs" USING "btree" ("user_id");



CREATE INDEX "maintenance_history_restore_operations_user_plan_idx" ON "owntend_private"."maintenance_history_restore_operations" USING "btree" ("user_id", "plan_id", "created_at" DESC);



CREATE INDEX "ad_reward_claims_user_id_idx" ON "public"."ad_reward_claims" USING "btree" ("user_id");



CREATE UNIQUE INDEX "areas_user_active_name_uidx" ON "public"."areas" USING "btree" ("user_id", "lower"("name")) WHERE ("archived_at" IS NULL);



CREATE INDEX "asset_photos_user_id_asset_id_idx" ON "public"."asset_photos" USING "btree" ("user_id", "asset_id");



CREATE INDEX "asset_tags_user_id_tag_id_idx" ON "public"."asset_tags" USING "btree" ("user_id", "tag_id");



CREATE INDEX "assets_user_id_room_id_idx" ON "public"."assets" USING "btree" ("user_id", "room_id");



CREATE INDEX "creation_point_operations_user_id_idx" ON "public"."creation_point_operations" USING "btree" ("user_id");



CREATE UNIQUE INDEX "idx_asset_photos_single_primary" ON "public"."asset_photos" USING "btree" ("user_id", "asset_id") WHERE ("is_primary" = true);



CREATE INDEX "idx_media_cleanup_queue_status" ON "public"."media_cleanup_queue" USING "btree" ("status", "created_at");



CREATE INDEX "idx_media_cleanup_queue_user" ON "public"."media_cleanup_queue" USING "btree" ("user_id");



CREATE INDEX "idx_media_staging_objects_user_status" ON "public"."media_staging_objects" USING "btree" ("user_id", "status");



CREATE INDEX "idx_server_change_feed_user_entity_record" ON "public"."server_change_feed" USING "btree" ("user_id", "entity_type", "record_id");



CREATE INDEX "idx_server_change_feed_user_seq" ON "public"."server_change_feed" USING "btree" ("user_id", "change_seq");



CREATE UNIQUE INDEX "idx_tags_user_name_lower" ON "public"."tags" USING "btree" ("user_id", "lower"("name"));



CREATE INDEX "maintenance_plans_user_id_asset_id_idx" ON "public"."maintenance_plans" USING "btree" ("user_id", "asset_id");



CREATE UNIQUE INDEX "maintenance_records_occurrence_uidx" ON "public"."maintenance_records" USING "btree" ("user_id", "plan_id", "occurrence_id");



CREATE UNIQUE INDEX "maintenance_records_operation_uidx" ON "public"."maintenance_records" USING "btree" ("user_id", "operation_id");



CREATE INDEX "maintenance_records_user_id_plan_id_idx" ON "public"."maintenance_records" USING "btree" ("user_id", "plan_id");



CREATE INDEX "media_staging_objects_active_path_idx" ON "public"."media_staging_objects" USING "btree" ("user_id", "staging_path", "expires_at") WHERE ("status" = 'staged'::"text");



CREATE INDEX "media_staging_objects_staged_expiry_idx" ON "public"."media_staging_objects" USING "btree" ("expires_at") WHERE ("status" = 'staged'::"text");



CREATE UNIQUE INDEX "media_staging_objects_user_idempotency_uidx" ON "public"."media_staging_objects" USING "btree" ("user_id", "idempotency_key");



CREATE INDEX "monetization_events_user_id_idx" ON "public"."monetization_events" USING "btree" ("user_id");



CREATE UNIQUE INDEX "notification_inbox_dedupe_uidx" ON "public"."notification_inbox" USING "btree" ("user_id", "dedupe_key") WHERE ("dedupe_key" <> ''::"text");



CREATE INDEX "notification_inbox_user_id_plan_id_idx" ON "public"."notification_inbox" USING "btree" ("user_id", "plan_id");



CREATE UNIQUE INDEX "point_transactions_daily_reward_uidx" ON "public"."point_transactions" USING "btree" ("user_id", "reward_day") WHERE (("transaction_type" = 'rewarded_interstitial'::"text") AND ("reward_day" IS NOT NULL));



CREATE INDEX "point_transactions_user_created_idx" ON "public"."point_transactions" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "points_transactions_user_id_idx" ON "public"."point_transactions" USING "btree" ("user_id");



CREATE INDEX "reward_claim_requests_pending_idx" ON "public"."reward_claim_requests" USING "btree" ("user_id", "status", "expires_at") WHERE ("status" = 'pending'::"text");



CREATE INDEX "reward_claim_requests_user_created_idx" ON "public"."reward_claim_requests" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX IF NOT EXISTS "reward_claim_requests_eligibility_token_idx" ON "public"."reward_claim_requests" USING "btree" ("eligibility_token");



CREATE INDEX IF NOT EXISTS "ad_reward_claims_claim_id_idx" ON "public"."ad_reward_claims" USING "btree" ("claim_id");



CREATE UNIQUE INDEX "rooms_area_active_name_uidx" ON "public"."rooms" USING "btree" ("user_id", "area_id", "lower"("name")) WHERE ("archived_at" IS NULL);



CREATE INDEX "rooms_user_id_area_id_idx" ON "public"."rooms" USING "btree" ("user_id", "area_id");



CREATE INDEX "user_settings_user_updated_idx" ON "public"."user_settings" USING "btree" ("user_id", "updated_at");



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."areas" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."asset_photos" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."asset_tags" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."assets" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."device_details" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."maintenance_plan_metadata" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."maintenance_plans" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."maintenance_records" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."notification_inbox" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."pet_details" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."plant_details" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."rooms" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."safety_details" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."streaks" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."tags" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "set_row_metadata" BEFORE INSERT OR UPDATE ON "public"."user_settings" FOR EACH ROW EXECUTE FUNCTION "public"."set_owntend_row_metadata"();



CREATE OR REPLACE TRIGGER "trg_asset_photos_delete_cleanup" AFTER DELETE ON "public"."asset_photos" FOR EACH ROW EXECUTE FUNCTION "owntend_media_private"."fn_enqueue_deleted_photo_cleanup"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_areas" AFTER INSERT OR DELETE OR UPDATE ON "public"."areas" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_asset_photos" AFTER INSERT OR DELETE OR UPDATE ON "public"."asset_photos" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_asset_tags" AFTER INSERT OR DELETE OR UPDATE ON "public"."asset_tags" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_assets" AFTER INSERT OR DELETE OR UPDATE ON "public"."assets" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_device_details" AFTER INSERT OR DELETE OR UPDATE ON "public"."device_details" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_maintenance_plan_metadata" AFTER INSERT OR DELETE OR UPDATE ON "public"."maintenance_plan_metadata" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_maintenance_plans" AFTER INSERT OR DELETE OR UPDATE ON "public"."maintenance_plans" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_maintenance_records" AFTER INSERT OR DELETE OR UPDATE ON "public"."maintenance_records" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_notification_inbox" AFTER INSERT OR DELETE OR UPDATE ON "public"."notification_inbox" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_pet_details" AFTER INSERT OR DELETE OR UPDATE ON "public"."pet_details" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_plant_details" AFTER INSERT OR DELETE OR UPDATE ON "public"."plant_details" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_profiles" AFTER INSERT OR DELETE OR UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_rooms" AFTER INSERT OR DELETE OR UPDATE ON "public"."rooms" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_safety_details" AFTER INSERT OR DELETE OR UPDATE ON "public"."safety_details" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_streaks" AFTER INSERT OR DELETE OR UPDATE ON "public"."streaks" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_tags" AFTER INSERT OR DELETE OR UPDATE ON "public"."tags" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



CREATE OR REPLACE TRIGGER "trg_server_change_feed_user_settings" AFTER INSERT OR DELETE OR UPDATE ON "public"."user_settings" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."fn_log_server_change_feed"();



ALTER TABLE ONLY "owntend_monetization_private"."maintenance_plan_entitlements"
    ADD CONSTRAINT "maintenance_plan_entitlements_operation_fkey" FOREIGN KEY ("created_by_operation_id") REFERENCES "public"."creation_point_operations"("operation_id") ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY "owntend_monetization_private"."maintenance_plan_entitlements"
    ADD CONSTRAINT "maintenance_plan_entitlements_user_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "owntend_monetization_private"."maintenance_plan_entitlements"
    ADD CONSTRAINT "maintenance_plan_entitlements_user_plan_fkey" FOREIGN KEY ("user_id", "plan_id") REFERENCES "public"."maintenance_plans"("user_id", "id") ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;



ALTER TABLE ONLY "owntend_monetization_private"."plan_economy_operations"
    ADD CONSTRAINT "plan_economy_operations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "owntend_private"."account_deletion_cleanup_jobs"
    ADD CONSTRAINT "account_deletion_cleanup_jobs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "owntend_private"."maintenance_history_restore_operations"
    ADD CONSTRAINT "maintenance_history_restore_operations_plan_fkey" FOREIGN KEY ("user_id", "plan_id") REFERENCES "public"."maintenance_plans"("user_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "owntend_private"."maintenance_history_restore_operations"
    ADD CONSTRAINT "maintenance_history_restore_operations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ad_reward_claims"
    ADD CONSTRAINT "ad_reward_claims_claim_id_fkey" FOREIGN KEY ("claim_id") REFERENCES "public"."reward_claim_requests"("claim_id");



ALTER TABLE ONLY "public"."ad_reward_claims"
    ADD CONSTRAINT "ad_reward_claims_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."areas"
    ADD CONSTRAINT "areas_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."asset_photos"
    ADD CONSTRAINT "asset_photos_user_id_asset_id_fkey" FOREIGN KEY ("user_id", "asset_id") REFERENCES "public"."assets"("user_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."asset_photos"
    ADD CONSTRAINT "asset_photos_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."asset_tags"
    ADD CONSTRAINT "asset_tags_user_id_asset_id_fkey" FOREIGN KEY ("user_id", "asset_id") REFERENCES "public"."assets"("user_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."asset_tags"
    ADD CONSTRAINT "asset_tags_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."asset_tags"
    ADD CONSTRAINT "asset_tags_user_id_tag_id_fkey" FOREIGN KEY ("user_id", "tag_id") REFERENCES "public"."tags"("user_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."assets"
    ADD CONSTRAINT "assets_user_id_room_id_fkey" FOREIGN KEY ("user_id", "room_id") REFERENCES "public"."rooms"("user_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."creation_point_operations"
    ADD CONSTRAINT "creation_point_operations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_details"
    ADD CONSTRAINT "device_details_user_id_asset_id_fkey" FOREIGN KEY ("user_id", "asset_id") REFERENCES "public"."assets"("user_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_details"
    ADD CONSTRAINT "device_details_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."maintenance_plan_metadata"
    ADD CONSTRAINT "maintenance_plan_metadata_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."maintenance_plan_metadata"
    ADD CONSTRAINT "maintenance_plan_metadata_user_id_plan_id_fkey" FOREIGN KEY ("user_id", "plan_id") REFERENCES "public"."maintenance_plans"("user_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."maintenance_plans"
    ADD CONSTRAINT "maintenance_plans_user_id_asset_id_fkey" FOREIGN KEY ("user_id", "asset_id") REFERENCES "public"."assets"("user_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."maintenance_plans"
    ADD CONSTRAINT "maintenance_plans_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."maintenance_records"
    ADD CONSTRAINT "maintenance_records_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."maintenance_records"
    ADD CONSTRAINT "maintenance_records_user_id_plan_id_fkey" FOREIGN KEY ("user_id", "plan_id") REFERENCES "public"."maintenance_plans"("user_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."maintenance_reward_eligibilities"
    ADD CONSTRAINT "maintenance_reward_eligibilities_completion_fkey" FOREIGN KEY ("user_id", "completion_id") REFERENCES "public"."maintenance_records"("user_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."maintenance_reward_eligibilities"
    ADD CONSTRAINT "maintenance_reward_eligibilities_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."media_cleanup_queue"
    ADD CONSTRAINT "media_cleanup_queue_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."media_staging_objects"
    ADD CONSTRAINT "media_staging_objects_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."monetization_events"
    ADD CONSTRAINT "monetization_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_inbox"
    ADD CONSTRAINT "notification_inbox_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notification_inbox"
    ADD CONSTRAINT "notification_inbox_user_id_plan_id_fkey" FOREIGN KEY ("user_id", "plan_id") REFERENCES "public"."maintenance_plans"("user_id", "id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."owner_feed_state"
    ADD CONSTRAINT "owner_feed_state_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pet_details"
    ADD CONSTRAINT "pet_details_user_id_asset_id_fkey" FOREIGN KEY ("user_id", "asset_id") REFERENCES "public"."assets"("user_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pet_details"
    ADD CONSTRAINT "pet_details_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."plant_details"
    ADD CONSTRAINT "plant_details_user_id_asset_id_fkey" FOREIGN KEY ("user_id", "asset_id") REFERENCES "public"."assets"("user_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."plant_details"
    ADD CONSTRAINT "plant_details_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."point_transactions"
    ADD CONSTRAINT "point_transactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."point_wallets"
    ADD CONSTRAINT "point_wallets_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reward_claim_requests"
    ADD CONSTRAINT "reward_claim_requests_eligibility_token_fkey" FOREIGN KEY ("eligibility_token") REFERENCES "public"."maintenance_reward_eligibilities"("token") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reward_claim_requests"
    ADD CONSTRAINT "reward_claim_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."rooms"
    ADD CONSTRAINT "rooms_user_id_area_id_fkey" FOREIGN KEY ("user_id", "area_id") REFERENCES "public"."areas"("user_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."rooms"
    ADD CONSTRAINT "rooms_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."safety_details"
    ADD CONSTRAINT "safety_details_user_id_asset_id_fkey" FOREIGN KEY ("user_id", "asset_id") REFERENCES "public"."assets"("user_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."safety_details"
    ADD CONSTRAINT "safety_details_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."server_change_feed"
    ADD CONSTRAINT "server_change_feed_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."streaks"
    ADD CONSTRAINT "streaks_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tags"
    ADD CONSTRAINT "tags_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_settings"
    ADD CONSTRAINT "user_settings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE "owntend_monetization_private"."maintenance_plan_entitlements" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "maintenance_plan_entitlements_api_roles_deny_all" ON "owntend_monetization_private"."maintenance_plan_entitlements" TO "authenticated", "anon" USING (false) WITH CHECK (false);



ALTER TABLE "owntend_monetization_private"."plan_economy_operations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "plan_economy_operations_api_roles_deny_all" ON "owntend_monetization_private"."plan_economy_operations" TO "authenticated", "anon" USING (false) WITH CHECK (false);



ALTER TABLE "owntend_private"."account_deletion_cleanup_jobs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "account_deletion_cleanup_jobs_service_role_all" ON "owntend_private"."account_deletion_cleanup_jobs" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "owntend_private"."account_deletion_operations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "account_deletion_operations_service_role_all" ON "owntend_private"."account_deletion_operations" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "owntend_private"."maintenance_history_restore_operations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "maintenance_history_restore_operations_api_roles_deny_all" ON "owntend_private"."maintenance_history_restore_operations" TO "authenticated", "anon" USING (false) WITH CHECK (false);



CREATE POLICY "Users can manage their own staging objects" ON "public"."media_staging_objects" TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "Users can only select their own change feed" ON "public"."server_change_feed" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "Users can view their own cleanup entries" ON "public"."media_cleanup_queue" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."ad_reward_claims" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ad_reward_claims_service_role_all" ON "public"."ad_reward_claims" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."areas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "areas_delete_own" ON "public"."areas" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "areas_insert_own" ON "public"."areas" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "areas_select_own" ON "public"."areas" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "areas_update_own" ON "public"."areas" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."asset_photos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "asset_photos_select_own" ON "public"."asset_photos" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."asset_tags" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "asset_tags_delete_own" ON "public"."asset_tags" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "asset_tags_insert_own" ON "public"."asset_tags" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "asset_tags_select_own" ON "public"."asset_tags" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "asset_tags_update_own" ON "public"."asset_tags" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."assets" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "assets_delete_own" ON "public"."assets" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "assets_select_own" ON "public"."assets" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "assets_update_own" ON "public"."assets" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."creation_point_operations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "creation_point_operations_service_role_all" ON "public"."creation_point_operations" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."device_details" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_details_delete_own" ON "public"."device_details" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "device_details_insert_own" ON "public"."device_details" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "device_details_select_own" ON "public"."device_details" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "device_details_update_own" ON "public"."device_details" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."maintenance_plan_metadata" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "maintenance_plan_metadata_delete_own" ON "public"."maintenance_plan_metadata" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "maintenance_plan_metadata_insert_own" ON "public"."maintenance_plan_metadata" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "maintenance_plan_metadata_select_own" ON "public"."maintenance_plan_metadata" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "maintenance_plan_metadata_update_own" ON "public"."maintenance_plan_metadata" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."maintenance_plans" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "maintenance_plans_delete_own" ON "public"."maintenance_plans" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "maintenance_plans_insert_own" ON "public"."maintenance_plans" FOR INSERT TO "authenticated" WITH CHECK (((( SELECT "auth"."uid"() AS "uid") = "user_id") AND "owntend_monetization_private"."can_reconcile_maintenance_plan"("user_id", "id")));



CREATE POLICY "maintenance_plans_select_own" ON "public"."maintenance_plans" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "maintenance_plans_update_own" ON "public"."maintenance_plans" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."maintenance_records" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "maintenance_records_select_own" ON "public"."maintenance_records" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."maintenance_reward_eligibilities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "maintenance_reward_eligibilities_service_role_all" ON "public"."maintenance_reward_eligibilities" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."media_cleanup_queue" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."media_staging_objects" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."monetization_config" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "monetization_config_select_authenticated" ON "public"."monetization_config" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."monetization_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "monetization_events_service_role_all" ON "public"."monetization_events" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."notification_inbox" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notification_inbox_delete_own" ON "public"."notification_inbox" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "notification_inbox_insert_own" ON "public"."notification_inbox" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "notification_inbox_select_own" ON "public"."notification_inbox" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "notification_inbox_update_own" ON "public"."notification_inbox" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."owner_feed_state" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "owner_feed_state_select_own" ON "public"."owner_feed_state" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."pet_details" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pet_details_delete_own" ON "public"."pet_details" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "pet_details_insert_own" ON "public"."pet_details" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "pet_details_select_own" ON "public"."pet_details" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "pet_details_update_own" ON "public"."pet_details" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."plant_details" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "plant_details_delete_own" ON "public"."plant_details" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "plant_details_insert_own" ON "public"."plant_details" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "plant_details_select_own" ON "public"."plant_details" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "plant_details_update_own" ON "public"."plant_details" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."point_transactions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "point_transactions_select_own" ON "public"."point_transactions" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."point_wallets" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "point_wallets_select_own" ON "public"."point_wallets" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;



CREATE POLICY "profiles_select_own" ON "public"."profiles" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "profiles_update_own" ON "public"."profiles" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."reward_claim_requests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reward_claim_requests_select_own" ON "public"."reward_claim_requests" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."rooms" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "rooms_delete_own" ON "public"."rooms" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "rooms_insert_own" ON "public"."rooms" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "rooms_select_own" ON "public"."rooms" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "rooms_update_own" ON "public"."rooms" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."safety_details" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "safety_details_delete_own" ON "public"."safety_details" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "safety_details_insert_own" ON "public"."safety_details" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "safety_details_select_own" ON "public"."safety_details" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "safety_details_update_own" ON "public"."safety_details" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."server_change_feed" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."streaks" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "streaks_delete_own" ON "public"."streaks" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "streaks_insert_own" ON "public"."streaks" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "streaks_select_own" ON "public"."streaks" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "streaks_update_own" ON "public"."streaks" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."tags" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tags_delete_own" ON "public"."tags" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "tags_insert_own" ON "public"."tags" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "tags_select_own" ON "public"."tags" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "tags_update_own" ON "public"."tags" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."user_settings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_settings_delete_own" ON "public"."user_settings" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "user_settings_insert_own" ON "public"."user_settings" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "user_settings_select_own" ON "public"."user_settings" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "user_settings_update_own" ON "public"."user_settings" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."areas";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."asset_photos";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."asset_tags";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."assets";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."device_details";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."maintenance_plan_metadata";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."maintenance_plans";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."maintenance_records";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."notification_inbox";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."pet_details";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."plant_details";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."point_wallets";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."profiles";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."rooms";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."safety_details";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."streaks";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."tags";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."user_settings";



GRANT USAGE ON SCHEMA "owntend_media_private" TO "service_role";
GRANT USAGE ON SCHEMA "owntend_media_private" TO "authenticated";



GRANT USAGE ON SCHEMA "owntend_monetization_private" TO "service_role";
GRANT USAGE ON SCHEMA "owntend_monetization_private" TO "authenticated";



GRANT USAGE ON SCHEMA "owntend_private" TO "service_role";
GRANT USAGE ON SCHEMA "owntend_private" TO "authenticated";



GRANT USAGE ON SCHEMA "owntend_security" TO "authenticated";
GRANT USAGE ON SCHEMA "owntend_security" TO "service_role";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






















































































































































REVOKE ALL ON FUNCTION "owntend_media_private"."acknowledge_media_cleanup"("p_id" bigint) FROM PUBLIC;



REVOKE ALL ON FUNCTION "owntend_media_private"."claim_media_cleanup_batch"("p_batch_size" integer) FROM PUBLIC;



REVOKE ALL ON FUNCTION "owntend_media_private"."delete_asset_photo_impl"("p_asset_id" "text", "p_photo_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_media_private"."delete_asset_photo_impl"("p_asset_id" "text", "p_photo_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "owntend_media_private"."delete_asset_photo_impl"("p_asset_id" "text", "p_photo_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "owntend_media_private"."finalize_asset_photo_upload_impl"("p_staging_id" "uuid", "p_asset_id" "text", "p_photo_id" "text", "p_expected_revision" integer, "p_caption" "text", "p_is_primary" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_media_private"."finalize_asset_photo_upload_impl"("p_staging_id" "uuid", "p_asset_id" "text", "p_photo_id" "text", "p_expected_revision" integer, "p_caption" "text", "p_is_primary" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "owntend_media_private"."finalize_asset_photo_upload_impl"("p_staging_id" "uuid", "p_asset_id" "text", "p_photo_id" "text", "p_expected_revision" integer, "p_caption" "text", "p_is_primary" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "owntend_media_private"."fn_enqueue_deleted_photo_cleanup"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "owntend_media_private"."prepare_asset_photo_upload_impl"("p_asset_id" "text", "p_photo_id" "text", "p_object_size" bigint, "p_mime_type" "text", "p_client_sha256_digest" "text", "p_idempotency_key" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_media_private"."prepare_asset_photo_upload_impl"("p_asset_id" "text", "p_photo_id" "text", "p_object_size" bigint, "p_mime_type" "text", "p_client_sha256_digest" "text", "p_idempotency_key" "text") TO "authenticated";
GRANT ALL ON FUNCTION "owntend_media_private"."prepare_asset_photo_upload_impl"("p_asset_id" "text", "p_photo_id" "text", "p_object_size" bigint, "p_mime_type" "text", "p_client_sha256_digest" "text", "p_idempotency_key" "text") TO "service_role";



REVOKE ALL ON FUNCTION "owntend_media_private"."record_media_cleanup_failure"("p_id" bigint, "p_error_code" "text", "p_terminal" boolean) FROM PUBLIC;



REVOKE ALL ON FUNCTION "owntend_media_private"."set_primary_asset_photo_impl"("p_asset_id" "text", "p_photo_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_media_private"."set_primary_asset_photo_impl"("p_asset_id" "text", "p_photo_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "owntend_media_private"."set_primary_asset_photo_impl"("p_asset_id" "text", "p_photo_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "owntend_media_private"."sweep_expired_media_staging"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "owntend_monetization_private"."can_reconcile_maintenance_plan"("p_user_id" "uuid", "p_plan_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_monetization_private"."can_reconcile_maintenance_plan"("p_user_id" "uuid", "p_plan_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "owntend_monetization_private"."can_reconcile_maintenance_plan"("p_user_id" "uuid", "p_plan_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "owntend_monetization_private"."change_asset_type_with_point_delta_impl"("p_operation" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_monetization_private"."change_asset_type_with_point_delta_impl"("p_operation" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "owntend_monetization_private"."change_asset_type_with_point_delta_impl"("p_operation" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "owntend_monetization_private"."copy_asset_impl"("p_operation" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_monetization_private"."copy_asset_impl"("p_operation" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "owntend_monetization_private"."copy_asset_impl"("p_operation" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "owntend_monetization_private"."create_asset_impl"("p_operation" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_monetization_private"."create_asset_impl"("p_operation" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "owntend_monetization_private"."create_asset_impl"("p_operation" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "owntend_monetization_private"."create_reward_claim_request_impl"("p_reward_type" "text", "p_time_zone" "text", "p_eligibility_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_monetization_private"."create_reward_claim_request_impl"("p_reward_type" "text", "p_time_zone" "text", "p_eligibility_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "owntend_monetization_private"."create_reward_claim_request_impl"("p_reward_type" "text", "p_time_zone" "text", "p_eligibility_token" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "owntend_monetization_private"."create_task_with_point_debit_impl"("p_operation" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_monetization_private"."create_task_with_point_debit_impl"("p_operation" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "owntend_monetization_private"."create_task_with_point_debit_impl"("p_operation" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "owntend_monetization_private"."get_charged_operation_status"("p_operation_id" "uuid", "p_request_hash" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_monetization_private"."get_charged_operation_status"("p_operation_id" "uuid", "p_request_hash" "text") TO "service_role";
GRANT ALL ON FUNCTION "owntend_monetization_private"."get_charged_operation_status"("p_operation_id" "uuid", "p_request_hash" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "owntend_monetization_private"."move_maintenance_plan_with_point_delta_impl"("p_operation" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_monetization_private"."move_maintenance_plan_with_point_delta_impl"("p_operation" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "owntend_monetization_private"."move_maintenance_plan_with_point_delta_impl"("p_operation" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "owntend_monetization_private"."quote_asset_type_change_impl"("p_asset_id" "text", "p_target_type" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_monetization_private"."quote_asset_type_change_impl"("p_asset_id" "text", "p_target_type" "text") TO "authenticated";
GRANT ALL ON FUNCTION "owntend_monetization_private"."quote_asset_type_change_impl"("p_asset_id" "text", "p_target_type" "text") TO "service_role";



REVOKE ALL ON FUNCTION "owntend_monetization_private"."quote_maintenance_plan_move_impl"("p_plan_id" "text", "p_target_asset_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_monetization_private"."quote_maintenance_plan_move_impl"("p_plan_id" "text", "p_target_asset_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "owntend_monetization_private"."quote_maintenance_plan_move_impl"("p_plan_id" "text", "p_target_asset_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "owntend_monetization_private"."record_monetization_event_impl"("p_event_name" "text", "p_properties" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_monetization_private"."record_monetization_event_impl"("p_event_name" "text", "p_properties" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "owntend_monetization_private"."record_monetization_event_impl"("p_event_name" "text", "p_properties" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "owntend_monetization_private"."required_task_cost_for_asset_type"("p_asset_type" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "owntend_private"."compact_user_change_feed"("p_retention_days" integer, "p_max_retained_rows_per_user" integer) FROM PUBLIC;



REVOKE ALL ON FUNCTION "owntend_private"."complete_maintenance_task_impl"("p_operation" "jsonb", "p_device_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_private"."complete_maintenance_task_impl"("p_operation" "jsonb", "p_device_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "owntend_private"."complete_maintenance_task_impl"("p_operation" "jsonb", "p_device_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "owntend_private"."fn_log_server_change_feed"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "owntend_private"."initialize_owntend_profile_for_user"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "owntend_private"."initialize_point_wallet_for_user"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "owntend_private"."maintenance_completion_result"("p_status" "text", "p_retryable" boolean, "p_conflict_reason" "text", "p_current_plan_revision" bigint, "p_resulting_record_id" "text", "p_resulting_next_due_date" timestamp with time zone, "p_plan" "jsonb", "p_record" "jsonb") FROM PUBLIC;



REVOKE ALL ON FUNCTION "owntend_private"."next_maintenance_due"("p_completed_at" timestamp with time zone, "p_interval" integer, "p_unit" "text", "p_time_zone_id" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "owntend_private"."restore_maintenance_history_impl"("p_operation" "jsonb", "p_device_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_private"."restore_maintenance_history_impl"("p_operation" "jsonb", "p_device_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "owntend_private"."restore_maintenance_history_impl"("p_operation" "jsonb", "p_device_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "owntend_private"."sync_feed_identity"("p_table_name" "text", "p_row" "jsonb") FROM PUBLIC;



REVOKE ALL ON FUNCTION "owntend_private"."undo_maintenance_completion_impl"("p_operation" "jsonb", "p_device_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_private"."undo_maintenance_completion_impl"("p_operation" "jsonb", "p_device_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "owntend_private"."undo_maintenance_completion_impl"("p_operation" "jsonb", "p_device_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "owntend_security"."current_owntend_session_is_active"() FROM PUBLIC;
GRANT ALL ON FUNCTION "owntend_security"."current_owntend_session_is_active"() TO "authenticated";
GRANT ALL ON FUNCTION "owntend_security"."current_owntend_session_is_active"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."acknowledge_media_cleanup"("p_id" bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."acknowledge_media_cleanup"("p_id" bigint) TO "service_role";



REVOKE ALL ON FUNCTION "public"."acknowledge_owntend_account_deletion_operation"("p_operation_id" "uuid", "p_subject_binding" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."acknowledge_owntend_account_deletion_operation"("p_operation_id" "uuid", "p_subject_binding" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."advance_owntend_account_deletion_operation"("p_operation_id" "uuid", "p_user_id" "uuid", "p_stage" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."advance_owntend_account_deletion_operation"("p_operation_id" "uuid", "p_user_id" "uuid", "p_stage" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."begin_owntend_account_cleanup"("p_user_id" "uuid", "p_object_paths" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."begin_owntend_account_cleanup"("p_user_id" "uuid", "p_object_paths" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."begin_owntend_account_deletion_operation"("p_request_hash" "text", "p_subject_binding" "text", "p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."begin_owntend_account_deletion_operation"("p_request_hash" "text", "p_subject_binding" "text", "p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."change_asset_type_with_point_delta"("p_operation" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."change_asset_type_with_point_delta"("p_operation" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."change_asset_type_with_point_delta"("p_operation" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."claim_media_cleanup_batch"("p_batch_size" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_media_cleanup_batch"("p_batch_size" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_maintenance_task"("p_operation" "jsonb", "p_device_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_maintenance_task"("p_operation" "jsonb", "p_device_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."complete_maintenance_task"("p_operation" "jsonb", "p_device_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_owntend_account_cleanup"("p_job_id" "uuid", "p_error" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_owntend_account_cleanup"("p_job_id" "uuid", "p_error" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_owntend_account_deletion_operation"("p_operation_id" "uuid", "p_user_id" "uuid", "p_subject_binding" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_owntend_account_deletion_operation"("p_operation_id" "uuid", "p_user_id" "uuid", "p_subject_binding" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."copy_asset"("p_operation" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."copy_asset"("p_operation" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."copy_asset"("p_operation" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_asset"("p_operation" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_asset"("p_operation" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_asset"("p_operation" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_reward_claim_request"("p_reward_type" "text", "p_time_zone" "text", "p_eligibility_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_reward_claim_request"("p_reward_type" "text", "p_time_zone" "text", "p_eligibility_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_reward_claim_request"("p_reward_type" "text", "p_time_zone" "text", "p_eligibility_token" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_task_with_point_debit"("p_operation" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_task_with_point_debit"("p_operation" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_task_with_point_debit"("p_operation" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."delete_asset_photo"("p_asset_id" "text", "p_photo_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."delete_asset_photo"("p_asset_id" "text", "p_photo_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_asset_photo"("p_asset_id" "text", "p_photo_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."fetch_user_change_feed"("p_since_seq" bigint, "p_limit" integer, "p_expected_generation" bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."fetch_user_change_feed"("p_since_seq" bigint, "p_limit" integer, "p_expected_generation" bigint) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."finalize_asset_photo_upload"("p_staging_id" "uuid", "p_asset_id" "text", "p_photo_id" "text", "p_expected_revision" integer, "p_caption" "text", "p_is_primary" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."finalize_asset_photo_upload"("p_staging_id" "uuid", "p_asset_id" "text", "p_photo_id" "text", "p_expected_revision" integer, "p_caption" "text", "p_is_primary" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."finalize_asset_photo_upload"("p_staging_id" "uuid", "p_asset_id" "text", "p_photo_id" "text", "p_expected_revision" integer, "p_caption" "text", "p_is_primary" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_charged_operation_status"("p_operation_id" "uuid", "p_request_hash" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_charged_operation_status"("p_operation_id" "uuid", "p_request_hash" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_charged_operation_status"("p_operation_id" "uuid", "p_request_hash" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_user_change_feed_watermark"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_user_change_feed_watermark"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."is_recent_owntend_session"("p_user_id" "uuid", "p_session_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_recent_owntend_session"("p_user_id" "uuid", "p_session_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."lookup_owntend_account_deletion_operation"("p_request_hash" "text", "p_subject_binding" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."lookup_owntend_account_deletion_operation"("p_request_hash" "text", "p_subject_binding" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."move_maintenance_plan_with_point_delta"("p_operation" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."move_maintenance_plan_with_point_delta"("p_operation" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."move_maintenance_plan_with_point_delta"("p_operation" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."prepare_asset_photo_upload"("p_asset_id" "text", "p_photo_id" "text", "p_object_size" bigint, "p_mime_type" "text", "p_client_sha256_digest" "text", "p_idempotency_key" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prepare_asset_photo_upload"("p_asset_id" "text", "p_photo_id" "text", "p_object_size" bigint, "p_mime_type" "text", "p_client_sha256_digest" "text", "p_idempotency_key" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."prepare_asset_photo_upload"("p_asset_id" "text", "p_photo_id" "text", "p_object_size" bigint, "p_mime_type" "text", "p_client_sha256_digest" "text", "p_idempotency_key" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."process_admob_ssv_reward"("p_transaction_id" "text", "p_claim_id" "uuid", "p_user_id" "uuid", "p_ad_unit_id" "text", "p_reward_amount" integer, "p_reward_item" "text", "p_google_timestamp" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."process_admob_ssv_reward"("p_transaction_id" "text", "p_claim_id" "uuid", "p_user_id" "uuid", "p_ad_unit_id" "text", "p_reward_amount" integer, "p_reward_item" "text", "p_google_timestamp" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."prune_owntend_account_deletion_operations"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prune_owntend_account_deletion_operations"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."quote_asset_type_change"("p_asset_id" "text", "p_target_type" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."quote_asset_type_change"("p_asset_id" "text", "p_target_type" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."quote_asset_type_change"("p_asset_id" "text", "p_target_type" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."quote_maintenance_plan_move"("p_plan_id" "text", "p_target_asset_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."quote_maintenance_plan_move"("p_plan_id" "text", "p_target_asset_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."quote_maintenance_plan_move"("p_plan_id" "text", "p_target_asset_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_media_cleanup_failure"("p_id" bigint, "p_error_code" "text", "p_terminal" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_media_cleanup_failure"("p_id" bigint, "p_error_code" "text", "p_terminal" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_monetization_event"("p_event_name" "text", "p_properties" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_monetization_event"("p_event_name" "text", "p_properties" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_monetization_event"("p_event_name" "text", "p_properties" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_owntend_account_deletion_operation_error"("p_operation_id" "uuid", "p_user_id" "uuid", "p_error_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_owntend_account_deletion_operation_error"("p_operation_id" "uuid", "p_user_id" "uuid", "p_error_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."restore_maintenance_history"("p_operation" "jsonb", "p_device_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."restore_maintenance_history"("p_operation" "jsonb", "p_device_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."restore_maintenance_history"("p_operation" "jsonb", "p_device_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_owntend_row_metadata"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."set_primary_asset_photo"("p_asset_id" "text", "p_photo_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_primary_asset_photo"("p_asset_id" "text", "p_photo_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_primary_asset_photo"("p_asset_id" "text", "p_photo_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."undo_maintenance_completion"("p_operation" "jsonb", "p_device_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."undo_maintenance_completion"("p_operation" "jsonb", "p_device_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."undo_maintenance_completion"("p_operation" "jsonb", "p_device_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."validate_change_feed_parity"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."validate_change_feed_parity"("p_user_id" "uuid") TO "service_role";


















GRANT SELECT ON TABLE "owntend_monetization_private"."maintenance_plan_entitlements" TO "service_role";



GRANT SELECT ON TABLE "owntend_monetization_private"."plan_economy_operations" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "owntend_private"."account_deletion_operations" TO "service_role";



GRANT SELECT ON TABLE "owntend_private"."maintenance_history_restore_operations" TO "service_role";



GRANT MAINTAIN ON TABLE "public"."ad_reward_claims" TO "authenticated";
GRANT ALL ON TABLE "public"."ad_reward_claims" TO "service_role";



GRANT SELECT,INSERT,DELETE,MAINTAIN ON TABLE "public"."areas" TO "authenticated";
GRANT ALL ON TABLE "public"."areas" TO "service_role";



GRANT UPDATE("name") ON TABLE "public"."areas" TO "authenticated";



GRANT UPDATE("kind") ON TABLE "public"."areas" TO "authenticated";



GRANT UPDATE("sort_order") ON TABLE "public"."areas" TO "authenticated";



GRANT UPDATE("archived_at") ON TABLE "public"."areas" TO "authenticated";



GRANT SELECT,MAINTAIN ON TABLE "public"."asset_photos" TO "authenticated";
GRANT ALL ON TABLE "public"."asset_photos" TO "service_role";



GRANT SELECT,INSERT,DELETE,MAINTAIN ON TABLE "public"."asset_tags" TO "authenticated";
GRANT ALL ON TABLE "public"."asset_tags" TO "service_role";



GRANT SELECT,DELETE,MAINTAIN ON TABLE "public"."assets" TO "authenticated";
GRANT ALL ON TABLE "public"."assets" TO "service_role";



GRANT UPDATE("name") ON TABLE "public"."assets" TO "authenticated";



GRANT UPDATE("room_id") ON TABLE "public"."assets" TO "authenticated";



GRANT UPDATE("placement") ON TABLE "public"."assets" TO "authenticated";



GRANT UPDATE("notes") ON TABLE "public"."assets" TO "authenticated";



GRANT UPDATE("purchase_date") ON TABLE "public"."assets" TO "authenticated";



GRANT UPDATE("archived_at") ON TABLE "public"."assets" TO "authenticated";



GRANT MAINTAIN ON TABLE "public"."creation_point_operations" TO "authenticated";
GRANT ALL ON TABLE "public"."creation_point_operations" TO "service_role";



GRANT SELECT,INSERT,DELETE,MAINTAIN ON TABLE "public"."device_details" TO "authenticated";
GRANT ALL ON TABLE "public"."device_details" TO "service_role";



GRANT UPDATE("brand") ON TABLE "public"."device_details" TO "authenticated";



GRANT UPDATE("model") ON TABLE "public"."device_details" TO "authenticated";



GRANT UPDATE("serial_number") ON TABLE "public"."device_details" TO "authenticated";



GRANT UPDATE("power_source") ON TABLE "public"."device_details" TO "authenticated";



GRANT UPDATE("warranty_until") ON TABLE "public"."device_details" TO "authenticated";



GRANT UPDATE("manual_url") ON TABLE "public"."device_details" TO "authenticated";



GRANT UPDATE("consumable") ON TABLE "public"."device_details" TO "authenticated";



GRANT SELECT,INSERT,DELETE,MAINTAIN ON TABLE "public"."maintenance_plan_metadata" TO "authenticated";
GRANT ALL ON TABLE "public"."maintenance_plan_metadata" TO "service_role";



GRANT UPDATE("task_type") ON TABLE "public"."maintenance_plan_metadata" TO "authenticated";



GRANT UPDATE("location_label") ON TABLE "public"."maintenance_plan_metadata" TO "authenticated";



GRANT UPDATE("estimated_duration_minutes") ON TABLE "public"."maintenance_plan_metadata" TO "authenticated";



GRANT UPDATE("required_materials_json") ON TABLE "public"."maintenance_plan_metadata" TO "authenticated";



GRANT UPDATE("reminder_recommendation") ON TABLE "public"."maintenance_plan_metadata" TO "authenticated";



GRANT UPDATE("sort_order") ON TABLE "public"."maintenance_plan_metadata" TO "authenticated";



GRANT SELECT,INSERT,DELETE,MAINTAIN ON TABLE "public"."maintenance_plans" TO "authenticated";
GRANT ALL ON TABLE "public"."maintenance_plans" TO "service_role";



GRANT UPDATE("title") ON TABLE "public"."maintenance_plans" TO "authenticated";



GRANT UPDATE("instructions") ON TABLE "public"."maintenance_plans" TO "authenticated";



GRANT UPDATE("recurrence_interval") ON TABLE "public"."maintenance_plans" TO "authenticated";



GRANT UPDATE("recurrence_unit") ON TABLE "public"."maintenance_plans" TO "authenticated";



GRANT UPDATE("priority") ON TABLE "public"."maintenance_plans" TO "authenticated";



GRANT UPDATE("next_due_date") ON TABLE "public"."maintenance_plans" TO "authenticated";



GRANT UPDATE("is_enabled") ON TABLE "public"."maintenance_plans" TO "authenticated";



GRANT UPDATE("reminder_days_before") ON TABLE "public"."maintenance_plans" TO "authenticated";



GRANT UPDATE("archived_at") ON TABLE "public"."maintenance_plans" TO "authenticated";



GRANT SELECT,MAINTAIN ON TABLE "public"."maintenance_records" TO "authenticated";
GRANT ALL ON TABLE "public"."maintenance_records" TO "service_role";



GRANT ALL ON TABLE "public"."maintenance_reward_eligibilities" TO "service_role";



GRANT MAINTAIN ON TABLE "public"."media_cleanup_queue" TO "authenticated";
GRANT ALL ON TABLE "public"."media_cleanup_queue" TO "service_role";



GRANT ALL ON SEQUENCE "public"."media_cleanup_queue_id_seq" TO "service_role";



GRANT SELECT,MAINTAIN ON TABLE "public"."media_staging_objects" TO "authenticated";
GRANT ALL ON TABLE "public"."media_staging_objects" TO "service_role";



GRANT SELECT,MAINTAIN ON TABLE "public"."monetization_config" TO "authenticated";
GRANT ALL ON TABLE "public"."monetization_config" TO "service_role";



GRANT MAINTAIN ON TABLE "public"."monetization_events" TO "authenticated";
GRANT ALL ON TABLE "public"."monetization_events" TO "service_role";



GRANT ALL ON SEQUENCE "public"."monetization_events_id_seq" TO "service_role";



GRANT SELECT,INSERT,DELETE,MAINTAIN ON TABLE "public"."notification_inbox" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_inbox" TO "service_role";



GRANT UPDATE("read_at") ON TABLE "public"."notification_inbox" TO "authenticated";



GRANT SELECT,MAINTAIN ON TABLE "public"."owner_feed_state" TO "authenticated";
GRANT ALL ON TABLE "public"."owner_feed_state" TO "service_role";



GRANT SELECT,INSERT,DELETE,MAINTAIN ON TABLE "public"."pet_details" TO "authenticated";
GRANT ALL ON TABLE "public"."pet_details" TO "service_role";



GRANT UPDATE("species") ON TABLE "public"."pet_details" TO "authenticated";



GRANT UPDATE("breed") ON TABLE "public"."pet_details" TO "authenticated";



GRANT UPDATE("birth_date") ON TABLE "public"."pet_details" TO "authenticated";



GRANT UPDATE("microchip_id") ON TABLE "public"."pet_details" TO "authenticated";



GRANT UPDATE("vet_name") ON TABLE "public"."pet_details" TO "authenticated";



GRANT UPDATE("vet_phone") ON TABLE "public"."pet_details" TO "authenticated";



GRANT UPDATE("feeding_notes") ON TABLE "public"."pet_details" TO "authenticated";



GRANT UPDATE("medical_notes") ON TABLE "public"."pet_details" TO "authenticated";



GRANT SELECT,INSERT,DELETE,MAINTAIN ON TABLE "public"."plant_details" TO "authenticated";
GRANT ALL ON TABLE "public"."plant_details" TO "service_role";



GRANT UPDATE("species") ON TABLE "public"."plant_details" TO "authenticated";



GRANT UPDATE("sunlight") ON TABLE "public"."plant_details" TO "authenticated";



GRANT UPDATE("watering_interval_days") ON TABLE "public"."plant_details" TO "authenticated";



GRANT UPDATE("pot_size") ON TABLE "public"."plant_details" TO "authenticated";



GRANT UPDATE("last_repotted_at") ON TABLE "public"."plant_details" TO "authenticated";



GRANT UPDATE("toxicity_notes") ON TABLE "public"."plant_details" TO "authenticated";



GRANT SELECT,MAINTAIN ON TABLE "public"."point_transactions" TO "authenticated";
GRANT ALL ON TABLE "public"."point_transactions" TO "service_role";



GRANT SELECT,MAINTAIN ON TABLE "public"."point_wallets" TO "authenticated";
GRANT ALL ON TABLE "public"."point_wallets" TO "service_role";



GRANT SELECT,MAINTAIN ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT UPDATE("nickname") ON TABLE "public"."profiles" TO "authenticated";



GRANT SELECT,MAINTAIN ON TABLE "public"."reward_claim_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."reward_claim_requests" TO "service_role";



GRANT SELECT,INSERT,DELETE,MAINTAIN ON TABLE "public"."rooms" TO "authenticated";
GRANT ALL ON TABLE "public"."rooms" TO "service_role";



GRANT UPDATE("area_id") ON TABLE "public"."rooms" TO "authenticated";



GRANT UPDATE("name") ON TABLE "public"."rooms" TO "authenticated";



GRANT UPDATE("room_type") ON TABLE "public"."rooms" TO "authenticated";



GRANT UPDATE("notes") ON TABLE "public"."rooms" TO "authenticated";



GRANT UPDATE("sort_order") ON TABLE "public"."rooms" TO "authenticated";



GRANT UPDATE("archived_at") ON TABLE "public"."rooms" TO "authenticated";



GRANT SELECT,INSERT,DELETE,MAINTAIN ON TABLE "public"."safety_details" TO "authenticated";
GRANT ALL ON TABLE "public"."safety_details" TO "service_role";



GRANT UPDATE("safety_type") ON TABLE "public"."safety_details" TO "authenticated";



GRANT UPDATE("installed_at") ON TABLE "public"."safety_details" TO "authenticated";



GRANT UPDATE("expires_at") ON TABLE "public"."safety_details" TO "authenticated";



GRANT UPDATE("battery_type") ON TABLE "public"."safety_details" TO "authenticated";



GRANT UPDATE("test_interval_days") ON TABLE "public"."safety_details" TO "authenticated";



GRANT SELECT,MAINTAIN ON TABLE "public"."server_change_feed" TO "authenticated";
GRANT ALL ON TABLE "public"."server_change_feed" TO "service_role";



GRANT ALL ON SEQUENCE "public"."server_change_feed_change_seq_seq" TO "service_role";



GRANT SELECT,INSERT,DELETE,MAINTAIN ON TABLE "public"."streaks" TO "authenticated";
GRANT ALL ON TABLE "public"."streaks" TO "service_role";



GRANT UPDATE("current_streak") ON TABLE "public"."streaks" TO "authenticated";



GRANT UPDATE("longest_streak") ON TABLE "public"."streaks" TO "authenticated";



GRANT UPDATE("last_completion_date") ON TABLE "public"."streaks" TO "authenticated";



GRANT SELECT,INSERT,DELETE,MAINTAIN ON TABLE "public"."tags" TO "authenticated";
GRANT ALL ON TABLE "public"."tags" TO "service_role";



GRANT UPDATE("name") ON TABLE "public"."tags" TO "authenticated";



GRANT SELECT,INSERT,DELETE,MAINTAIN ON TABLE "public"."user_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."user_settings" TO "service_role";



GRANT UPDATE("value") ON TABLE "public"."user_settings" TO "authenticated";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";
































--
-- Dumped schema changes for auth and storage
--

CREATE OR REPLACE TRIGGER "initialize_owntend_profile_for_user" AFTER INSERT ON "auth"."users" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."initialize_owntend_profile_for_user"();



CREATE OR REPLACE TRIGGER "initialize_point_wallet_for_user" AFTER INSERT ON "auth"."users" FOR EACH ROW EXECUTE FUNCTION "owntend_private"."initialize_point_wallet_for_user"();



CREATE POLICY "user_media_insert_own" ON "storage"."objects" FOR INSERT TO "authenticated" WITH CHECK ((("bucket_id" = 'user-media'::"text") AND (("storage"."foldername"("name"))[1] = (( SELECT "auth"."uid"() AS "uid"))::"text") AND "owntend_security"."current_owntend_session_is_active"() AND (EXISTS ( SELECT 1
   FROM "public"."media_staging_objects" "s"
  WHERE (("s"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("s"."staging_path" = "objects"."name") AND ("s"."status" = 'staged'::"text") AND ("s"."expires_at" > "clock_timestamp"()))))));



CREATE POLICY "user_media_select_own" ON "storage"."objects" FOR SELECT TO "authenticated" USING ((("bucket_id" = 'user-media'::"text") AND (("storage"."foldername"("name"))[1] = (( SELECT "auth"."uid"() AS "uid"))::"text") AND "owntend_security"."current_owntend_session_is_active"()));

-- Supabase-owned configuration and singleton application state are data, not
-- schema, so the schema dumper cannot emit them. Keep their canonical initial
-- values in this one prelaunch baseline.
INSERT INTO "public"."monetization_config" ("singleton") VALUES (true)
ON CONFLICT ("singleton") DO NOTHING;

INSERT INTO "storage"."buckets" (
  "id", "name", "public", "file_size_limit", "allowed_mime_types"
) VALUES (
  'user-media',
  'user-media',
  false,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT ("id") DO UPDATE SET
  "public" = false,
  "file_size_limit" = 10485760,
  "allowed_mime_types" = ARRAY['image/jpeg', 'image/png', 'image/webp'];

-- pg_dump preserves Supabase's broad role defaults. Owntend deliberately
-- narrows them after all explicit application grants have been installed.
REVOKE ALL ON ALL TABLES IN SCHEMA "public" FROM "anon";
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
  ON ALL TABLES IN SCHEMA "public" FROM "authenticated";
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "public" FROM "anon", "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
  REVOKE ALL ON TABLES FROM "anon", "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
  REVOKE ALL ON SEQUENCES FROM "anon", "authenticated";

DO $$
DECLARE
  existing_job_id bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    SELECT jobid INTO existing_job_id FROM cron.job
    WHERE jobname = 'owntend-account-deletion-operation-prune';
    IF existing_job_id IS NOT NULL THEN
      PERFORM cron.unschedule(existing_job_id);
    END IF;
    PERFORM cron.schedule(
      'owntend-account-deletion-operation-prune',
      '17 * * * *',
      'SELECT public.prune_owntend_account_deletion_operations();'
    );

    SELECT jobid INTO existing_job_id FROM cron.job
    WHERE jobname = 'owntend-change-feed-compact';
    IF existing_job_id IS NOT NULL THEN
      PERFORM cron.unschedule(existing_job_id);
    END IF;
    PERFORM cron.schedule(
      'owntend-change-feed-compact',
      '23 3 * * *',
      'SELECT owntend_private.compact_user_change_feed();'
    );

    SELECT jobid INTO existing_job_id FROM cron.job
    WHERE jobname = 'owntend-media-staging-sweep';
    IF existing_job_id IS NOT NULL THEN
      PERFORM cron.unschedule(existing_job_id);
    END IF;
    PERFORM cron.schedule(
      'owntend-media-staging-sweep',
      '47 * * * *',
      'SELECT owntend_media_private.sweep_expired_media_staging();'
    );

    -- The protected cleanup worker is scheduled only after an operator has
    -- provisioned both its dedicated Vault capability and exact function URL.
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'vault')
       AND EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'net') THEN
      IF EXISTS (
        SELECT 1 FROM vault.decrypted_secrets
        WHERE name = 'media_cleanup_worker_authorization'
      ) AND current_setting(
        'owntend.media_cleanup_function_url', true
      ) IS NOT NULL THEN
        SELECT jobid INTO existing_job_id FROM cron.job
        WHERE jobname = 'owntend-media-cleanup-worker';
        IF existing_job_id IS NOT NULL THEN
          PERFORM cron.unschedule(existing_job_id);
        END IF;
        PERFORM cron.schedule(
          'owntend-media-cleanup-worker',
          '31 * * * *',
          $cron$SELECT net.http_post(
            url := current_setting('owntend.media_cleanup_function_url', true),
            headers := jsonb_build_object(
              'X-Owntend-Worker-Token',
              (SELECT decrypted_secret FROM vault.decrypted_secrets
               WHERE name = 'media_cleanup_worker_authorization'),
              'Content-Type', 'application/json'
            ),
            body := '{}'::jsonb,
            timeout_milliseconds := 30000
          );$cron$
        );
      ELSE
        SELECT jobid INTO existing_job_id FROM cron.job
        WHERE jobname = 'owntend-media-cleanup-worker';
        IF existing_job_id IS NOT NULL THEN
          PERFORM cron.unschedule(existing_job_id);
        END IF;
      END IF;
    END IF;
  END IF;
END
$$;
