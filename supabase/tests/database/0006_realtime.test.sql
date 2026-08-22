begin;
set local search_path = public, extensions;

create extension if not exists pgtap with schema extensions;

select plan(2);

select is(
  (
    select count(*)::integer
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = any(array[
        'profiles', 'areas', 'rooms', 'assets',
        'device_details', 'pet_details', 'plant_details', 'safety_details',
        'tags', 'asset_tags', 'asset_photos', 'maintenance_plans',
        'maintenance_plan_metadata', 'maintenance_records',
        'notification_inbox', 'user_settings', 'streaks'
      ])
  ),
  17,
  'all Supabase-owned app tables are published to Realtime'
);

select is(
  (
    select count(*)::integer
    from pg_class
    where oid = any(array[
      'public.profiles'::regclass,
      'public.areas'::regclass, 'public.rooms'::regclass,
      'public.assets'::regclass, 'public.device_details'::regclass,
      'public.pet_details'::regclass, 'public.plant_details'::regclass,
      'public.safety_details'::regclass, 'public.tags'::regclass,
      'public.asset_tags'::regclass, 'public.asset_photos'::regclass,
      'public.maintenance_plans'::regclass,
      'public.maintenance_plan_metadata'::regclass,
      'public.maintenance_records'::regclass,
      'public.notification_inbox'::regclass,
      'public.user_settings'::regclass, 'public.streaks'::regclass
    ])
      and relreplident = 'f'
  ),
  17,
  'all Supabase-owned app tables retain full replica identity'
);

select * from finish();
rollback;
