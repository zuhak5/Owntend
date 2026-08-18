BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS revision BIGINT;

-- Existing production profiles predate the revision column. The shared
-- BEFORE UPDATE metadata trigger derives revision from OLD.revision, so a
-- normal backfill would turn NULL + 1 back into NULL. Disable only that
-- trigger while seeding legacy rows, then restore it before enforcing the
-- steady-state constraints.
ALTER TABLE public.profiles
  DISABLE TRIGGER set_row_metadata;

UPDATE public.profiles
SET revision = 1
WHERE revision IS NULL;

ALTER TABLE public.profiles
  ENABLE TRIGGER set_row_metadata;

ALTER TABLE public.profiles
  ALTER COLUMN revision SET DEFAULT 1,
  ALTER COLUMN revision SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'profiles_revision_positive'
      AND conrelid = 'public.profiles'::regclass
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_revision_positive
      CHECK (revision > 0);
  END IF;
END
$$;

DROP TRIGGER IF EXISTS trg_server_change_feed_profiles
  ON public.profiles;

CREATE TRIGGER trg_server_change_feed_profiles
AFTER INSERT OR UPDATE OR DELETE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.fn_log_server_change_feed();

COMMIT;
