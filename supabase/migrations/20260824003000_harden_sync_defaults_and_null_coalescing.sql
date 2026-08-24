-- Migration: 20260824003000_harden_sync_defaults_and_null_coalescing.sql
-- Description: Harden public.set_owntend_row_metadata trigger with server-side null coalescing
--              for sort_order, required_materials_json, reminder_days_before, is_enabled,
--              is_primary, and created_at across all 17 synchronized tables.

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
REVOKE ALL ON FUNCTION "public"."set_owntend_row_metadata"() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."set_owntend_row_metadata"() TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."set_owntend_row_metadata"() TO "service_role";
