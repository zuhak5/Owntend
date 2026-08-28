-- Generic sync PATCH authority is a column contract, independent of owner RLS.
-- Clear both table-wide and stale column grants before installing the exact
-- allowlist used by SyncEntitySpec.updatableLocalColumns.
DO $migration$
DECLARE
  table_name_value text;
  column_list text;
BEGIN
  FOREACH table_name_value IN ARRAY ARRAY[
    'profiles',
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
    'maintenance_plan_metadata',
    'maintenance_records',
    'notification_inbox',
    'user_settings',
    'streaks'
  ]
  LOOP
    EXECUTE format(
      'REVOKE UPDATE ON TABLE public.%I FROM authenticated',
      table_name_value
    );

    SELECT string_agg(format('%I', column_name), ', ' ORDER BY ordinal_position)
    INTO column_list
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = table_name_value;

    IF column_list IS NOT NULL THEN
      EXECUTE format(
        'REVOKE UPDATE (%s) ON TABLE public.%I FROM authenticated',
        column_list,
        table_name_value
      );
    END IF;
  END LOOP;
END;
$migration$;

GRANT UPDATE (nickname)
ON TABLE public.profiles TO authenticated;

GRANT UPDATE (name, kind, sort_order, archived_at)
ON TABLE public.areas TO authenticated;

GRANT UPDATE (area_id, name, room_type, notes, sort_order, archived_at)
ON TABLE public.rooms TO authenticated;

GRANT UPDATE (name, room_id, placement, notes, purchase_date, archived_at)
ON TABLE public.assets TO authenticated;

GRANT UPDATE (
  brand,
  model,
  serial_number,
  power_source,
  warranty_until,
  manual_url,
  consumable
)
ON TABLE public.device_details TO authenticated;

GRANT UPDATE (
  species,
  breed,
  birth_date,
  microchip_id,
  vet_name,
  vet_phone,
  feeding_notes,
  medical_notes
)
ON TABLE public.pet_details TO authenticated;

GRANT UPDATE (
  species,
  sunlight,
  watering_interval_days,
  pot_size,
  last_repotted_at,
  toxicity_notes
)
ON TABLE public.plant_details TO authenticated;

GRANT UPDATE (
  safety_type,
  installed_at,
  expires_at,
  battery_type,
  test_interval_days
)
ON TABLE public.safety_details TO authenticated;

GRANT UPDATE (name)
ON TABLE public.tags TO authenticated;

GRANT UPDATE (
  title,
  instructions,
  recurrence_interval,
  recurrence_unit,
  priority,
  next_due_date,
  reminder_days_before,
  is_enabled,
  archived_at
)
ON TABLE public.maintenance_plans TO authenticated;

GRANT UPDATE (
  task_type,
  location_label,
  estimated_duration_minutes,
  required_materials_json,
  reminder_recommendation,
  sort_order
)
ON TABLE public.maintenance_plan_metadata TO authenticated;

GRANT UPDATE (read_at)
ON TABLE public.notification_inbox TO authenticated;

GRANT UPDATE (value)
ON TABLE public.user_settings TO authenticated;

GRANT UPDATE (current_streak, longest_streak, last_completion_date)
ON TABLE public.streaks TO authenticated;
