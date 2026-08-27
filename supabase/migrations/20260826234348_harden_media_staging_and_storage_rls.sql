-- Bind Storage writes to a fresh staging lease and make prepare retries atomic.

ALTER TABLE public.media_staging_objects
  ADD COLUMN attempt integer NOT NULL DEFAULT 0
  CONSTRAINT media_staging_objects_attempt_check CHECK (attempt >= 0);

CREATE INDEX media_staging_objects_active_path_idx
  ON public.media_staging_objects(user_id, staging_path, expires_at)
  WHERE status = 'staged';
CREATE INDEX media_staging_objects_staged_expiry_idx
  ON public.media_staging_objects(expires_at)
  WHERE status = 'staged';

ALTER TABLE public.media_cleanup_queue
  DROP CONSTRAINT media_cleanup_queue_reason_check;
ALTER TABLE public.media_cleanup_queue
  ADD CONSTRAINT media_cleanup_queue_reason_check CHECK (
    reason IN ('replaced', 'deleted', 'expired_staging', 'account_deleted', 'orphaned_unstaged')
  );

CREATE OR REPLACE FUNCTION owntend_media_private.prepare_asset_photo_upload_impl(
  p_asset_id text,
  p_photo_id text,
  p_object_size bigint,
  p_mime_type text,
  p_client_sha256_digest text,
  p_idempotency_key text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
$$;

ALTER FUNCTION owntend_media_private.prepare_asset_photo_upload_impl(
  text, text, bigint, text, text, text
) OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_media_private.prepare_asset_photo_upload_impl(
  text, text, bigint, text, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_media_private.prepare_asset_photo_upload_impl(
  text, text, bigint, text, text, text
) TO authenticated, service_role;
GRANT USAGE ON SCHEMA owntend_media_private TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.prepare_asset_photo_upload(
  p_asset_id text,
  p_photo_id text,
  p_object_size bigint,
  p_mime_type text,
  p_client_sha256_digest text,
  p_idempotency_key text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
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
ALTER FUNCTION public.prepare_asset_photo_upload(text, text, bigint, text, text, text)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.prepare_asset_photo_upload(text, text, bigint, text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_asset_photo_upload(text, text, bigint, text, text, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION owntend_media_private.sweep_expired_media_staging()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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

ALTER FUNCTION owntend_media_private.sweep_expired_media_staging() OWNER TO postgres;
REVOKE ALL ON FUNCTION owntend_media_private.sweep_expired_media_staging()
  FROM PUBLIC, anon, authenticated;

DROP POLICY IF EXISTS user_media_insert_own ON storage.objects;
CREATE POLICY user_media_insert_own ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'user-media'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  AND owntend_security.current_owntend_session_is_active()
  AND EXISTS (
    SELECT 1
    FROM public.media_staging_objects s
    WHERE s.user_id = (SELECT auth.uid())
      AND s.staging_path = storage.objects.name
      AND s.status = 'staged'
      AND s.expires_at > clock_timestamp()
  )
);

DROP POLICY IF EXISTS user_media_delete_own ON storage.objects;

-- Existing owner-prefixed bytes that are neither live nor staged are handed
-- to the service-role cleanup worker; SQL never deletes Storage metadata.
INSERT INTO public.media_cleanup_queue(user_id, object_path, reason)
SELECT u.id, o.name, 'orphaned_unstaged'
FROM storage.objects o
JOIN auth.users u
  ON u.id::text = (storage.foldername(o.name))[1]
WHERE o.bucket_id = 'user-media'
  AND NOT EXISTS (
    SELECT 1 FROM public.asset_photos p
    WHERE p.user_id = u.id AND p.object_path = o.name
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.media_staging_objects s
    WHERE s.user_id = u.id AND s.staging_path = o.name
      AND s.status IN ('staged', 'finalized')
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.media_cleanup_queue q
    WHERE q.user_id = u.id AND q.object_path = o.name
      AND q.status IN ('pending', 'processing')
  );
