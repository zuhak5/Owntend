-- Migration: 20260815000002_storage_and_media.sql
-- Description: Storage Bucket, Security Helpers, Media Staging, Finalize RPCs, and Primary Photo Constraints

BEGIN;

-- 1. Security helper for active session validation in storage policies
CREATE OR REPLACE FUNCTION owntend_security.current_owntend_session_is_active()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
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

REVOKE ALL ON FUNCTION owntend_security.current_owntend_session_is_active() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_security.current_owntend_session_is_active() TO authenticated, service_role;

-- 2. Trusted recent-session check for reauthentication
CREATE OR REPLACE FUNCTION public.is_recent_owntend_session(
  p_user_id UUID,
  p_session_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM auth.sessions
    WHERE id = p_session_id
      AND user_id = p_user_id
      AND created_at >= NOW() - INTERVAL '5 minutes'
  );
$$;

REVOKE ALL ON FUNCTION public.is_recent_owntend_session(UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_recent_owntend_session(UUID, UUID) TO service_role;

-- 3. Account cleanup job initialization
CREATE OR REPLACE FUNCTION public.begin_owntend_account_cleanup(
  p_user_id UUID,
  p_object_paths TEXT[]
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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

REVOKE ALL ON FUNCTION public.begin_owntend_account_cleanup(UUID, TEXT[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.begin_owntend_account_cleanup(UUID, TEXT[]) TO service_role;

-- 4. Account cleanup job completion
CREATE OR REPLACE FUNCTION public.complete_owntend_account_cleanup(
  p_job_id UUID,
  p_error TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
$$;

REVOKE ALL ON FUNCTION public.complete_owntend_account_cleanup(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_owntend_account_cleanup(UUID, TEXT) TO service_role;

-- 5. User Media Private Storage Bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'user-media',
  'user-media',
  false,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 10485760,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'];

-- Storage RLS Policies
DROP POLICY IF EXISTS user_media_select_own ON storage.objects;
CREATE POLICY user_media_select_own ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'user-media'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  AND owntend_security.current_owntend_session_is_active()
);

DROP POLICY IF EXISTS user_media_insert_own ON storage.objects;
CREATE POLICY user_media_insert_own ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'user-media'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  AND owntend_security.current_owntend_session_is_active()
);

DROP POLICY IF EXISTS user_media_update_own ON storage.objects;
CREATE POLICY user_media_update_own ON storage.objects
FOR UPDATE TO authenticated
USING (
  bucket_id = 'user-media'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  AND owntend_security.current_owntend_session_is_active()
)
WITH CHECK (
  bucket_id = 'user-media'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  AND owntend_security.current_owntend_session_is_active()
);

DROP POLICY IF EXISTS user_media_delete_own ON storage.objects;
CREATE POLICY user_media_delete_own ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id = 'user-media'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  AND owntend_security.current_owntend_session_is_active()
);

-- 6. Media Staging Objects Table
CREATE TABLE IF NOT EXISTS public.media_staging_objects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    staging_path TEXT NOT NULL UNIQUE,
    object_size BIGINT NOT NULL,
    mime_type TEXT NOT NULL,
    sha256_digest TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'staged' CHECK (status IN ('staged', 'finalized', 'expired', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finalized_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_media_staging_objects_user_status
    ON public.media_staging_objects(user_id, status);

ALTER TABLE public.media_staging_objects ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.media_staging_objects FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.media_staging_objects TO authenticated;
GRANT ALL ON TABLE public.media_staging_objects TO service_role;

DROP POLICY IF EXISTS "Users can manage their own staging objects" ON public.media_staging_objects;
CREATE POLICY "Users can manage their own staging objects"
    ON public.media_staging_objects
    FOR ALL
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- 7. Media Cleanup Queue Table
CREATE TABLE IF NOT EXISTS public.media_cleanup_queue (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    object_path TEXT NOT NULL,
    reason TEXT NOT NULL CHECK (reason IN ('replaced', 'deleted', 'expired_staging', 'account_deleted')),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed_terminal')),
    attempts INT NOT NULL DEFAULT 0,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_media_cleanup_queue_status
    ON public.media_cleanup_queue(status, created_at);

CREATE INDEX IF NOT EXISTS idx_media_cleanup_queue_user
    ON public.media_cleanup_queue(user_id);

ALTER TABLE public.media_cleanup_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own cleanup entries" ON public.media_cleanup_queue;
CREATE POLICY "Users can view their own cleanup entries"
    ON public.media_cleanup_queue
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- 8. Media Staging RPC
CREATE OR REPLACE FUNCTION public.stage_media_upload(
    p_staging_path TEXT,
    p_object_size BIGINT,
    p_mime_type TEXT,
    p_sha256_digest TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
    v_staging_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    IF p_staging_path IS NULL OR p_staging_path !~ '^[0-9a-fA-F-]{36}/assets/[A-Za-z0-9_-]{1,120}/[A-Za-z0-9_-]{1,120}\.(jpg|jpeg|png|webp)$' THEN
        RAISE EXCEPTION 'Invalid staging path format.' USING ERRCODE = '22023';
    END IF;

    IF split_part(p_staging_path, '/', 1) <> v_user_id::text THEN
        RAISE EXCEPTION 'The media path does not belong to the caller.' USING ERRCODE = '42501';
    END IF;

    IF p_object_size IS NULL OR p_object_size <= 0 OR p_object_size > 10485760 THEN
        RAISE EXCEPTION 'Object size exceeds 10 MiB limit.' USING ERRCODE = '22023';
    END IF;

    IF p_mime_type NOT IN ('image/jpeg', 'image/png', 'image/webp') THEN
        RAISE EXCEPTION 'Unsupported MIME type.' USING ERRCODE = '22023';
    END IF;

    IF p_sha256_digest IS NULL OR p_sha256_digest !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'Invalid sha256 digest.' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.media_staging_objects (
        user_id,
        staging_path,
        object_size,
        mime_type,
        sha256_digest,
        status
    )
    VALUES (
        v_user_id,
        p_staging_path,
        p_object_size,
        p_mime_type,
        p_sha256_digest,
        'staged'
    )
    ON CONFLICT (staging_path) DO UPDATE SET
        object_size = EXCLUDED.object_size,
        mime_type = EXCLUDED.mime_type,
        sha256_digest = EXCLUDED.sha256_digest
    RETURNING id INTO v_staging_id;

    RETURN jsonb_build_object(
        'staging_id', v_staging_id,
        'status', 'staged',
        'staging_path', p_staging_path
    );
END;
$$;

-- 9. Finalize Asset Photo Upload RPC
CREATE OR REPLACE FUNCTION public.finalize_asset_photo_upload(
    p_staging_id UUID,
    p_asset_id TEXT,
    p_photo_id TEXT,
    p_expected_revision INT DEFAULT 1
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
    v_staging public.media_staging_objects%ROWTYPE;
    v_canonical_path TEXT;
    v_existing_path TEXT;
    v_asset_exists BOOLEAN;
    v_photo public.asset_photos%ROWTYPE;
    v_object_exists BOOLEAN;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_staging
    FROM public.media_staging_objects
    WHERE id = p_staging_id AND user_id = v_user_id;

    IF v_staging.id IS NULL THEN
        RAISE EXCEPTION 'Staging object not found or unauthorized.' USING ERRCODE = 'P0002';
    END IF;

    SELECT * INTO v_photo
        FROM public.asset_photos
        WHERE id = p_photo_id AND user_id = v_user_id
        FOR UPDATE;

    IF v_staging.status = 'finalized' THEN
        IF v_photo.id IS NULL
          OR v_photo.asset_id IS DISTINCT FROM p_asset_id
          OR v_photo.object_path IS DISTINCT FROM v_staging.staging_path
        THEN
          RAISE EXCEPTION 'Finalized media metadata does not match the requested photo.' USING ERRCODE = '23505';
        END IF;

        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'photo_id', p_photo_id,
            'object_path', v_photo.object_path
        );
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.assets
        WHERE id = p_asset_id AND user_id = v_user_id
    ) INTO v_asset_exists;

    IF NOT v_asset_exists THEN
        RAISE EXCEPTION 'Target asset not found or unauthorized.' USING ERRCODE = '42501';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM storage.objects
        WHERE bucket_id = 'user-media'
          AND name = v_staging.staging_path
    ) INTO v_object_exists;

    IF NOT v_object_exists THEN
        RAISE EXCEPTION 'Uploaded media object not found.' USING ERRCODE = 'P0002';
    END IF;

    v_canonical_path := v_staging.staging_path;

    IF v_photo.id IS NOT NULL THEN
      IF v_photo.asset_id IS DISTINCT FROM p_asset_id THEN
        RAISE EXCEPTION 'The photo identifier is already bound to another asset.' USING ERRCODE = '23505';
      END IF;

      IF p_expected_revision IS NOT NULL
        AND v_photo.revision IS DISTINCT FROM p_expected_revision
      THEN
        RAISE EXCEPTION 'The photo revision changed before finalization.' USING ERRCODE = '23505';
      END IF;
    END IF;

    v_existing_path := v_photo.object_path;

    IF v_existing_path IS NOT NULL AND v_existing_path <> v_canonical_path THEN
        INSERT INTO public.media_cleanup_queue (user_id, object_path, reason)
        VALUES (v_user_id, v_existing_path, 'replaced');
    END IF;

    INSERT INTO public.asset_photos (
        id,
        asset_id,
        user_id,
        object_path,
        revision,
        created_at,
        updated_at
    )
    VALUES (
        p_photo_id,
        p_asset_id,
        v_user_id,
        v_canonical_path,
        COALESCE(p_expected_revision, 1),
        NOW(),
        NOW()
    )
    ON CONFLICT (user_id, id) DO UPDATE SET
        object_path = EXCLUDED.object_path,
        revision = CASE
          WHEN asset_photos.object_path IS DISTINCT FROM EXCLUDED.object_path
            THEN asset_photos.revision + 1
          ELSE asset_photos.revision
        END,
        updated_at = NOW();

    UPDATE public.media_staging_objects
    SET status = 'finalized', finalized_at = NOW()
    WHERE id = p_staging_id;

    RETURN jsonb_build_object(
        'success', true,
        'idempotent', false,
        'photo_id', p_photo_id,
        'object_path', v_canonical_path
    );
END;
$$;

-- 10. Set Primary Asset Photo RPC
CREATE OR REPLACE FUNCTION public.set_primary_asset_photo(
    p_asset_id TEXT,
    p_photo_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
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

    UPDATE public.asset_photos
    SET
        is_primary = (id = p_photo_id),
        revision = revision + 1,
        updated_at = NOW()
    WHERE asset_id = p_asset_id
      AND user_id = v_user_id
      AND (is_primary <> (id = p_photo_id));

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

-- 11. Partial Unique Index for Single Primary Photo per Asset
CREATE UNIQUE INDEX IF NOT EXISTS idx_asset_photos_single_primary
    ON public.asset_photos(user_id, asset_id)
    WHERE is_primary = true;

REVOKE ALL ON FUNCTION public.stage_media_upload(TEXT, BIGINT, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.finalize_asset_photo_upload(UUID, TEXT, TEXT, INT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_primary_asset_photo(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.stage_media_upload(TEXT, BIGINT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_asset_photo_upload(UUID, TEXT, TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_primary_asset_photo(TEXT, TEXT) TO authenticated;

COMMIT;;
