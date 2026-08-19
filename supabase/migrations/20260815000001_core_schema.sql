-- Migration: 20260815000001_core_schema.sql
-- Description: Consolidated Owntend Core Cloud Schema, RLS, Change Feed, and Realtime Signals

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Helper schemas
CREATE SCHEMA IF NOT EXISTS owntend_private;
REVOKE ALL ON SCHEMA owntend_private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA owntend_private TO service_role;

CREATE SCHEMA IF NOT EXISTS owntend_archive;
REVOKE ALL ON SCHEMA owntend_archive FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA owntend_archive TO service_role;

CREATE SCHEMA IF NOT EXISTS owntend_security;
REVOKE ALL ON SCHEMA owntend_security FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA owntend_security TO authenticated, service_role;

-- 2. Core domain tables

-- PROFILES
CREATE TABLE IF NOT EXISTS public.profiles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nickname TEXT CONSTRAINT profiles_nickname_length CHECK (
    nickname IS NULL OR (
      CHAR_LENGTH(nickname) BETWEEN 1 AND 120 AND nickname = BTRIM(nickname)
    )
  ),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  client_modified_at TIMESTAMPTZ
);

-- AREAS
CREATE TABLE IF NOT EXISTS public.areas (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  name TEXT NOT NULL CHECK (CHAR_LENGTH(name) BETWEEN 1 AND 120),
  kind TEXT NOT NULL DEFAULT 'indoor' CHECK (kind IN ('indoor', 'outdoor', 'utility', 'other')),
  sort_order INTEGER NOT NULL DEFAULT 0,
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  archived_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

-- ROOMS
CREATE TABLE IF NOT EXISTS public.rooms (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  area_id TEXT,
  name TEXT NOT NULL CHECK (CHAR_LENGTH(name) BETWEEN 1 AND 120),
  room_type TEXT CHECK (room_type IS NULL OR CHAR_LENGTH(room_type) <= 120),
  notes TEXT CHECK (notes IS NULL OR CHAR_LENGTH(notes) <= 4000),
  sort_order INTEGER NOT NULL DEFAULT 0,
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  archived_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id),
  FOREIGN KEY (user_id, area_id) REFERENCES public.areas(user_id, id) ON DELETE SET NULL
);

-- ASSETS
CREATE TABLE IF NOT EXISTS public.assets (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  name TEXT NOT NULL CHECK (CHAR_LENGTH(name) BETWEEN 1 AND 200),
  asset_type TEXT NOT NULL DEFAULT 'general' CHECK (asset_type IN ('device', 'pet', 'plant', 'safety', 'general')),
  room_id TEXT,
  placement TEXT CHECK (placement IS NULL OR CHAR_LENGTH(placement) <= 300),
  notes TEXT CHECK (notes IS NULL OR CHAR_LENGTH(notes) <= 10000),
  purchase_date DATE,
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  archived_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id),
  FOREIGN KEY (user_id, room_id) REFERENCES public.rooms(user_id, id) ON DELETE SET NULL
);

-- DEVICE DETAILS
CREATE TABLE IF NOT EXISTS public.device_details (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  asset_id TEXT NOT NULL,
  brand TEXT CHECK (brand IS NULL OR CHAR_LENGTH(brand) <= 120),
  model TEXT CHECK (model IS NULL OR CHAR_LENGTH(model) <= 120),
  serial_number TEXT CHECK (serial_number IS NULL OR CHAR_LENGTH(serial_number) <= 160),
  power_source TEXT CHECK (power_source IS NULL OR CHAR_LENGTH(power_source) <= 80),
  warranty_until DATE,
  manual_url TEXT CHECK (manual_url IS NULL OR CHAR_LENGTH(manual_url) <= 1000),
  consumable BOOLEAN NOT NULL DEFAULT false,
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, asset_id),
  FOREIGN KEY (user_id, asset_id) REFERENCES public.assets(user_id, id) ON DELETE CASCADE
);

-- PET DETAILS
CREATE TABLE IF NOT EXISTS public.pet_details (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  asset_id TEXT NOT NULL,
  species TEXT CHECK (species IS NULL OR CHAR_LENGTH(species) <= 120),
  breed TEXT CHECK (breed IS NULL OR CHAR_LENGTH(breed) <= 120),
  birth_date DATE,
  microchip_id TEXT CHECK (microchip_id IS NULL OR CHAR_LENGTH(microchip_id) <= 120),
  vet_name TEXT CHECK (vet_name IS NULL OR CHAR_LENGTH(vet_name) <= 200),
  vet_phone TEXT CHECK (vet_phone IS NULL OR CHAR_LENGTH(vet_phone) <= 80),
  feeding_notes TEXT CHECK (feeding_notes IS NULL OR CHAR_LENGTH(feeding_notes) <= 4000),
  medical_notes TEXT CHECK (medical_notes IS NULL OR CHAR_LENGTH(medical_notes) <= 4000),
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, asset_id),
  FOREIGN KEY (user_id, asset_id) REFERENCES public.assets(user_id, id) ON DELETE CASCADE
);

-- PLANT DETAILS
CREATE TABLE IF NOT EXISTS public.plant_details (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  asset_id TEXT NOT NULL,
  species TEXT CHECK (species IS NULL OR CHAR_LENGTH(species) <= 200),
  sunlight TEXT CHECK (sunlight IS NULL OR CHAR_LENGTH(sunlight) <= 120),
  watering_interval_days INTEGER CHECK (watering_interval_days IS NULL OR watering_interval_days > 0),
  pot_size TEXT CHECK (pot_size IS NULL OR CHAR_LENGTH(pot_size) <= 120),
  last_repotted_at TIMESTAMPTZ,
  toxicity_notes TEXT CHECK (toxicity_notes IS NULL OR CHAR_LENGTH(toxicity_notes) <= 4000),
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, asset_id),
  FOREIGN KEY (user_id, asset_id) REFERENCES public.assets(user_id, id) ON DELETE CASCADE
);

-- SAFETY DETAILS
CREATE TABLE IF NOT EXISTS public.safety_details (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  asset_id TEXT NOT NULL,
  safety_type TEXT CHECK (safety_type IS NULL OR CHAR_LENGTH(safety_type) <= 120),
  installed_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  battery_type TEXT CHECK (battery_type IS NULL OR CHAR_LENGTH(battery_type) <= 120),
  test_interval_days INTEGER CHECK (test_interval_days IS NULL OR test_interval_days > 0),
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, asset_id),
  FOREIGN KEY (user_id, asset_id) REFERENCES public.assets(user_id, id) ON DELETE CASCADE
);

-- TAGS
CREATE TABLE IF NOT EXISTS public.tags (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  name TEXT NOT NULL CHECK (CHAR_LENGTH(name) BETWEEN 1 AND 120),
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_user_name_lower
  ON public.tags (user_id, LOWER(name));

-- ASSET TAGS
CREATE TABLE IF NOT EXISTS public.asset_tags (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  asset_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, asset_id, tag_id),
  FOREIGN KEY (user_id, asset_id) REFERENCES public.assets(user_id, id) ON DELETE CASCADE,
  FOREIGN KEY (user_id, tag_id) REFERENCES public.tags(user_id, id) ON DELETE CASCADE
);

-- ASSET PHOTOS
CREATE TABLE IF NOT EXISTS public.asset_photos (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  asset_id TEXT NOT NULL,
  storage_path TEXT,
  object_path TEXT,
  caption TEXT CHECK (caption IS NULL OR CHAR_LENGTH(caption) <= 500),
  is_primary BOOLEAN NOT NULL DEFAULT false,
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, id),
  FOREIGN KEY (user_id, asset_id) REFERENCES public.assets(user_id, id) ON DELETE CASCADE,
  CONSTRAINT asset_photos_owned_path CHECK (
    object_path IS NULL OR object_path LIKE user_id::text || '/%'
  )
);

-- MAINTENANCE PLANS
CREATE TABLE IF NOT EXISTS public.maintenance_plans (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  asset_id TEXT NOT NULL,
  title TEXT NOT NULL CHECK (CHAR_LENGTH(title) BETWEEN 1 AND 200),
  description TEXT CHECK (description IS NULL OR CHAR_LENGTH(description) <= 4000),
  interval_count INTEGER NOT NULL DEFAULT 1 CHECK (interval_count > 0),
  interval_unit TEXT NOT NULL DEFAULT 'months' CHECK (interval_unit IN ('days', 'weeks', 'months', 'years')),
  season_flags INTEGER NOT NULL DEFAULT 0,
  priority TEXT NOT NULL DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'critical')),
  next_due_date TIMESTAMPTZ,
  health_group TEXT CHECK (health_group IS NULL OR health_group IN ('safety', 'pets', 'appliances', 'plants', 'cleaning', 'other')),
  is_enabled BOOLEAN NOT NULL DEFAULT true,
  reminder_days_before INTEGER CHECK (reminder_days_before IS NULL OR reminder_days_before >= 0),
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  archived_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id),
  FOREIGN KEY (user_id, asset_id) REFERENCES public.assets(user_id, id) ON DELETE CASCADE
);

-- MAINTENANCE PLAN METADATA
CREATE TABLE IF NOT EXISTS public.maintenance_plan_metadata (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_id TEXT NOT NULL,
  task_type TEXT CHECK (task_type IS NULL OR CHAR_LENGTH(task_type) <= 120),
  location_label TEXT CHECK (location_label IS NULL OR CHAR_LENGTH(location_label) <= 240),
  estimated_duration_minutes INTEGER CHECK (estimated_duration_minutes IS NULL OR estimated_duration_minutes >= 0),
  required_materials_json TEXT NOT NULL DEFAULT '[]' CHECK (CHAR_LENGTH(required_materials_json) <= 4000),
  reminder_recommendation TEXT CHECK (reminder_recommendation IS NULL OR CHAR_LENGTH(reminder_recommendation) <= 1000),
  sort_order INTEGER NOT NULL DEFAULT 0,
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, plan_id),
  FOREIGN KEY (user_id, plan_id) REFERENCES public.maintenance_plans(user_id, id) ON DELETE CASCADE
);

-- MAINTENANCE RECORDS
CREATE TABLE IF NOT EXISTS public.maintenance_records (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  plan_id TEXT NOT NULL,
  completed_at TIMESTAMPTZ NOT NULL,
  cost NUMERIC(10, 2) CHECK (cost IS NULL OR cost >= 0),
  notes TEXT CHECK (notes IS NULL OR CHAR_LENGTH(notes) <= 4000),
  service_provider TEXT CHECK (service_provider IS NULL OR CHAR_LENGTH(service_provider) <= 200),
  rating INTEGER CHECK (rating IS NULL OR (rating BETWEEN 1 AND 5)),
  due_date TIMESTAMPTZ,
  recurrence_interval INTEGER,
  operation_id TEXT NOT NULL DEFAULT gen_random_uuid()::text,
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, id),
  FOREIGN KEY (user_id, plan_id) REFERENCES public.maintenance_plans(user_id, id) ON DELETE CASCADE
);

-- NOTIFICATIONS (LEGACY / SYNCED COMPATIBILITY)
CREATE TABLE IF NOT EXISTS public.notifications (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  plan_id TEXT,
  scheduled_for TIMESTAMPTZ NOT NULL,
  sent_at TIMESTAMPTZ,
  action_taken TEXT,
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, id),
  FOREIGN KEY (user_id, plan_id) REFERENCES public.maintenance_plans(user_id, id) ON DELETE CASCADE
);

-- NOTIFICATION INBOX
CREATE TABLE IF NOT EXISTS public.notification_inbox (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  title TEXT NOT NULL CHECK (CHAR_LENGTH(title) BETWEEN 1 AND 500),
  body TEXT NOT NULL CHECK (CHAR_LENGTH(body) <= 20000),
  kind TEXT NOT NULL CHECK (CHAR_LENGTH(kind) BETWEEN 1 AND 80),
  route TEXT CHECK (route IS NULL OR CHAR_LENGTH(route) <= 1000),
  plan_id TEXT,
  dedupe_key TEXT NOT NULL CHECK (CHAR_LENGTH(dedupe_key) <= 128),
  read_at TIMESTAMPTZ,
  message_code TEXT CHECK (message_code IS NULL OR CHAR_LENGTH(message_code) BETWEEN 1 AND 120),
  message_args JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(message_args) = 'object'),
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, id),
  FOREIGN KEY (user_id, plan_id) REFERENCES public.maintenance_plans(user_id, id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS notification_inbox_dedupe_uidx
  ON public.notification_inbox (user_id, dedupe_key)
  WHERE dedupe_key <> '';

-- USER SETTINGS
CREATE TABLE IF NOT EXISTS public.user_settings (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  key TEXT NOT NULL CHECK (key IN (
    'theme',
    'app_language',
    'app_language_explicit',
    'theme_time_of_day_enabled',
    'notifications_enabled',
    'notification_preferences',
    'onboarding_completed',
    'permission_education_seen',
    'permission_education_seen_v2',
    'home_location'
  )),
  value TEXT NOT NULL CHECK (OCTET_LENGTH(value) <= 1048576),
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, key)
);

CREATE INDEX IF NOT EXISTS user_settings_user_updated_idx
  ON public.user_settings (user_id, updated_at);

-- STREAKS
CREATE TABLE IF NOT EXISTS public.streaks (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  id TEXT NOT NULL DEFAULT 'default',
  current_streak INTEGER NOT NULL DEFAULT 0 CHECK (current_streak >= 0),
  longest_streak INTEGER NOT NULL DEFAULT 0 CHECK (longest_streak >= 0 AND longest_streak >= current_streak),
  total_completions INTEGER NOT NULL DEFAULT 0 CHECK (total_completions >= 0),
  last_completion_date DATE,
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (user_id, id)
);

-- ARCHIVE / CLEANUP HELPER TABLES
CREATE TABLE IF NOT EXISTS owntend_archive.profiles_legacy_media_20260720 (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS profiles_legacy_media_user_id_idx
  ON owntend_archive.profiles_legacy_media_20260720 (user_id);

CREATE TABLE IF NOT EXISTS owntend_archive.asset_photo_upload_metadata_20260720 (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS asset_photo_upload_metadata_user_id_idx
  ON owntend_archive.asset_photo_upload_metadata_20260720 (user_id);

CREATE TABLE IF NOT EXISTS owntend_private.account_deletion_cleanup_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  target_paths TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  processed_at TIMESTAMPTZ,
  last_error_code TEXT CONSTRAINT account_deletion_cleanup_jobs_error_code_check CHECK (
    last_error_code IS NULL
    OR (
      CHAR_LENGTH(last_error_code) BETWEEN 1 AND 120
      AND last_error_code ~ '^[a-z0-9_]+$'
    )
  )
);

CREATE INDEX IF NOT EXISTS account_deletion_cleanup_jobs_user_id_idx
  ON owntend_private.account_deletion_cleanup_jobs (user_id);

-- 3. Relationship indexes (Advisors compliance)
CREATE INDEX IF NOT EXISTS asset_photos_user_id_asset_id_idx
  ON public.asset_photos (user_id, asset_id);

CREATE INDEX IF NOT EXISTS asset_tags_user_id_tag_id_idx
  ON public.asset_tags (user_id, tag_id);

CREATE INDEX IF NOT EXISTS assets_user_id_room_id_idx
  ON public.assets (user_id, room_id);

CREATE INDEX IF NOT EXISTS maintenance_plans_user_id_asset_id_idx
  ON public.maintenance_plans (user_id, asset_id);

CREATE INDEX IF NOT EXISTS maintenance_records_user_id_plan_id_idx
  ON public.maintenance_records (user_id, plan_id);

CREATE UNIQUE INDEX IF NOT EXISTS maintenance_records_operation_uidx
  ON public.maintenance_records (user_id, operation_id);

CREATE INDEX IF NOT EXISTS notification_inbox_user_id_plan_id_idx
  ON public.notification_inbox (user_id, plan_id);

CREATE INDEX IF NOT EXISTS rooms_user_id_area_id_idx
  ON public.rooms (user_id, area_id);

-- 4. Metadata Trigger Functions

CREATE OR REPLACE FUNCTION public.set_owntend_row_metadata()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
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

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.set_owntend_row_metadata() FROM PUBLIC;

DO $$
DECLARE
  app_table TEXT;
BEGIN
  FOREACH app_table IN ARRAY ARRAY[
    'profiles', 'areas', 'rooms', 'assets', 'device_details', 'pet_details',
    'plant_details', 'safety_details', 'tags', 'asset_tags', 'asset_photos',
    'maintenance_plans', 'maintenance_records', 'maintenance_plan_metadata',
    'notification_inbox', 'user_settings', 'streaks'
  ]
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS set_row_metadata ON public.%I', app_table);
    EXECUTE format('
      CREATE TRIGGER set_row_metadata
      BEFORE INSERT OR UPDATE ON public.%I
      FOR EACH ROW EXECUTE FUNCTION public.set_owntend_row_metadata()
    ', app_table);
  END LOOP;
END
$$;

-- 5. User Initialization Triggers

CREATE OR REPLACE FUNCTION owntend_private.initialize_owntend_profile_for_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION owntend_private.initialize_owntend_profile_for_user()
FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS initialize_owntend_profile_for_user ON auth.users;
CREATE TRIGGER initialize_owntend_profile_for_user
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION owntend_private.initialize_owntend_profile_for_user();

-- 6. Server Change Feed Substrate

CREATE TABLE IF NOT EXISTS public.server_change_feed (
  change_seq BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL,
  record_id TEXT NOT NULL,
  op_type TEXT NOT NULL CHECK (op_type IN ('INSERT', 'UPDATE', 'DELETE')),
  client_updated_at TIMESTAMPTZ,
  revision BIGINT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS idx_server_change_feed_user_seq
  ON public.server_change_feed (user_id, change_seq);

CREATE INDEX IF NOT EXISTS idx_server_change_feed_user_entity_record
  ON public.server_change_feed (user_id, entity_type, record_id);

ALTER TABLE public.server_change_feed ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can only select their own change feed" ON public.server_change_feed;
CREATE POLICY "Users can only select their own change feed"
  ON public.server_change_feed
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

REVOKE ALL ON public.server_change_feed FROM PUBLIC;
GRANT SELECT ON public.server_change_feed TO authenticated;
GRANT ALL ON public.server_change_feed TO service_role;

CREATE OR REPLACE FUNCTION public.fn_log_server_change_feed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row JSONB;
  v_user_id UUID;
  v_record_id TEXT;
  v_op_type TEXT;
  v_client_updated_at TIMESTAMPTZ;
  v_revision BIGINT;
BEGIN
  v_op_type := TG_OP;

  IF TG_OP = 'DELETE' THEN
    v_row := to_jsonb(OLD);
  ELSE
    v_row := to_jsonb(NEW);
  END IF;

  v_user_id := NULLIF(v_row ->> 'user_id', '')::uuid;
  v_record_id := CASE TG_TABLE_NAME
    WHEN 'profiles' THEN v_row ->> 'user_id'
    WHEN 'device_details' THEN v_row ->> 'asset_id'
    WHEN 'pet_details' THEN v_row ->> 'asset_id'
    WHEN 'plant_details' THEN v_row ->> 'asset_id'
    WHEN 'safety_details' THEN v_row ->> 'asset_id'
    WHEN 'asset_tags' THEN concat_ws('|', v_row ->> 'asset_id', v_row ->> 'tag_id')
    WHEN 'maintenance_plan_metadata' THEN v_row ->> 'plan_id'
    WHEN 'user_settings' THEN v_row ->> 'key'
    ELSE v_row ->> 'id'
  END;
  v_client_updated_at := CASE TG_TABLE_NAME
    WHEN 'profiles' THEN NULLIF(v_row ->> 'client_modified_at', '')::timestamptz
    ELSE COALESCE(
      NULLIF(v_row ->> 'updated_at', '')::timestamptz,
      clock_timestamp()
    )
  END;
  v_revision := COALESCE(NULLIF(v_row ->> 'revision', '')::bigint, 1);

  IF v_user_id IS NULL OR v_record_id IS NULL THEN
    RAISE EXCEPTION 'Unsupported change-feed row for table %', TG_TABLE_NAME;
  END IF;

  -- Cascading account deletion removes auth.users before child-table triggers run.
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_user_id) THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.server_change_feed (
    user_id,
    entity_type,
    record_id,
    op_type,
    client_updated_at,
    revision
  ) VALUES (
    v_user_id,
    TG_TABLE_NAME,
    v_record_id,
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
    'maintenance_plans',
    'maintenance_records',
    'notifications',
    'notification_inbox',
    'user_settings',
    'streaks'
  ];
BEGIN
  FOREACH tbl IN ARRAY tbls LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = tbl
    ) THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_server_change_feed_%I ON public.%I;', tbl, tbl);
      EXECUTE format('
        CREATE TRIGGER trg_server_change_feed_%I
        AFTER INSERT OR UPDATE OR DELETE ON public.%I
        FOR EACH ROW EXECUTE FUNCTION public.fn_log_server_change_feed();
      ', tbl, tbl);
    END IF;
  END LOOP;
END;
$$;

-- 7. Change Feed Capabilities & Discovery

CREATE TABLE IF NOT EXISTS public.sync_feed_capabilities (
  id TEXT PRIMARY KEY DEFAULT 'global',
  enabled BOOLEAN NOT NULL DEFAULT false,
  capability_version TEXT NOT NULL DEFAULT '1.0.0',
  min_retained_seq BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

INSERT INTO public.sync_feed_capabilities (id, enabled, capability_version, min_retained_seq)
VALUES ('global', false, '1.0.0', 0)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.sync_feed_capabilities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view sync feed capabilities" ON public.sync_feed_capabilities;
CREATE POLICY "Authenticated users can view sync feed capabilities"
  ON public.sync_feed_capabilities
  FOR SELECT
  TO authenticated
  USING (true);

REVOKE ALL ON public.sync_feed_capabilities FROM PUBLIC;
GRANT SELECT ON public.sync_feed_capabilities TO authenticated;
GRANT ALL ON public.sync_feed_capabilities TO service_role;

CREATE OR REPLACE FUNCTION public.get_sync_feed_capability()
RETURNS TABLE (
  enabled BOOLEAN,
  capability_version TEXT,
  min_retained_seq BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT enabled, capability_version, min_retained_seq
  FROM public.sync_feed_capabilities
  WHERE id = 'global';
$$;

REVOKE EXECUTE ON FUNCTION public.get_sync_feed_capability() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_sync_feed_capability() TO authenticated;

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
          'op_type', op_type,
          'client_updated_at', client_updated_at,
          'revision', revision,
          'created_at', created_at
        )
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
    'capability_version', COALESCE(v_cap_version, '1.0.0'),
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
  WITH canonical_counts AS (
    SELECT 'areas' AS entity, COUNT(*) AS cnt FROM public.areas WHERE user_id = v_target_user
    UNION ALL
    SELECT 'rooms' AS entity, COUNT(*) AS cnt FROM public.rooms WHERE user_id = v_target_user
    UNION ALL
    SELECT 'assets' AS entity, COUNT(*) AS cnt FROM public.assets WHERE user_id = v_target_user
    UNION ALL
    SELECT 'tags' AS entity, COUNT(*) AS cnt FROM public.tags WHERE user_id = v_target_user
    UNION ALL
    SELECT 'maintenance_plans' AS entity, COUNT(*) AS cnt FROM public.maintenance_plans WHERE user_id = v_target_user
    UNION ALL
    SELECT 'maintenance_records' AS entity, COUNT(*) AS cnt FROM public.maintenance_records WHERE user_id = v_target_user
  ),
  feed_counts AS (
    SELECT
      f.entity_type AS entity,
      COUNT(DISTINCT f.record_id) FILTER (WHERE f.op_type IN ('INSERT', 'UPDATE')) -
      COUNT(DISTINCT f.record_id) FILTER (WHERE f.op_type = 'DELETE') AS cnt
    FROM public.server_change_feed f
    WHERE f.user_id = v_target_user
    GROUP BY f.entity_type
  )
  SELECT
    c.entity AS entity_type,
    c.cnt AS canonical_count,
    COALESCE(fc.cnt, 0) AS feed_net_count,
    (c.cnt = COALESCE(fc.cnt, 0)) AS is_parity
  FROM canonical_counts c
  LEFT JOIN feed_counts fc ON c.entity = fc.entity;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.validate_change_feed_parity(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_change_feed_parity(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_user_change_feed_watermark(p_user_id UUID DEFAULT NULL)
RETURNS TABLE (
  min_change_seq BIGINT,
  max_change_seq BIGINT,
  total_changes BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    COALESCE(MIN(change_seq), 0) AS min_change_seq,
    COALESCE(MAX(change_seq), 0) AS max_change_seq,
    COUNT(*) AS total_changes
  FROM public.server_change_feed
  WHERE user_id = COALESCE(p_user_id, auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.get_user_change_feed_watermark(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_user_change_feed_watermark(UUID) TO authenticated;

-- 8. Row Level Security and Table Grants

DO $$
DECLARE
  table_name TEXT;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'profiles', 'areas', 'rooms', 'assets',
    'device_details', 'pet_details', 'plant_details', 'safety_details',
    'tags', 'asset_tags', 'asset_photos', 'maintenance_plans',
    'maintenance_plan_metadata', 'maintenance_records', 'notifications',
    'notification_inbox', 'user_settings', 'streaks'
  ]
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon', table_name);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO authenticated', table_name);
    EXECUTE format('GRANT ALL ON TABLE public.%I TO service_role', table_name);

    EXECUTE format('DROP POLICY IF EXISTS %I_select_own ON public.%I', table_name, table_name);
    EXECUTE format('
      CREATE POLICY %I_select_own ON public.%I
      FOR SELECT TO authenticated
      USING (auth.uid() = user_id)
    ', table_name, table_name);

    EXECUTE format('DROP POLICY IF EXISTS %I_insert_own ON public.%I', table_name, table_name);
    EXECUTE format('
      CREATE POLICY %I_insert_own ON public.%I
      FOR INSERT TO authenticated
      WITH CHECK (auth.uid() = user_id)
    ', table_name, table_name);

    EXECUTE format('DROP POLICY IF EXISTS %I_update_own ON public.%I', table_name, table_name);
    EXECUTE format('
      CREATE POLICY %I_update_own ON public.%I
      FOR UPDATE TO authenticated
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id)
    ', table_name, table_name);

    EXECUTE format('DROP POLICY IF EXISTS %I_delete_own ON public.%I', table_name, table_name);
    EXECUTE format('
      CREATE POLICY %I_delete_own ON public.%I
      FOR DELETE TO authenticated
      USING (auth.uid() = user_id)
    ', table_name, table_name);
  END LOOP;
END
$$;

-- 9. Realtime Publication
DO $$
DECLARE
  table_name TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;

  FOREACH table_name IN ARRAY ARRAY[
    'profiles', 'areas', 'rooms', 'assets',
    'device_details', 'pet_details', 'plant_details', 'safety_details',
    'tags', 'asset_tags', 'asset_photos', 'maintenance_plans',
    'maintenance_plan_metadata', 'maintenance_records',
    'notification_inbox', 'user_settings', 'streaks'
  ]
  LOOP
    EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', table_name);
    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = table_name
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', table_name);
    END IF;
  END LOOP;
END
$$;

COMMIT;
