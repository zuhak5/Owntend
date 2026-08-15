begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(31);

select extensions.has_table('public', 'profiles', 'profiles table exists');
select extensions.has_table('public', 'areas', 'areas table exists');
select extensions.has_table('public', 'rooms', 'rooms table exists');
select extensions.has_table('public', 'assets', 'assets table exists');
select extensions.has_table('public', 'device_details', 'device details table exists');
select extensions.has_table('public', 'pet_details', 'pet details table exists');
select extensions.has_table('public', 'plant_details', 'plant details table exists');
select extensions.has_table('public', 'safety_details', 'safety details table exists');
select extensions.has_table('public', 'tags', 'tags table exists');
select extensions.has_table('public', 'asset_tags', 'asset tags table exists');
select extensions.has_table('public', 'asset_photos', 'asset photos table exists');
select extensions.has_table('public', 'maintenance_plans', 'plans table exists');
select extensions.has_table('public', 'maintenance_plan_metadata', 'plan metadata table exists');
select extensions.has_table('public', 'maintenance_records', 'records table exists');

select extensions.col_is_pk('public', 'profiles', 'user_id', 'profile user id is primary');
select extensions.has_column('public', 'profiles', 'nickname', 'profiles store nickname');
select extensions.ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'display_name'
  ),
  'legacy profile display name is removed'
);
select extensions.ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'avatar_object_path'
  ),
  'legacy profile avatar path is removed'
);
select extensions.has_column('public', 'device_details', 'created_at', 'detail tables have create time');
select extensions.has_column('public', 'asset_tags', 'updated_at', 'join rows have update time');
select extensions.ok(
  (
    select count(*) = 8
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'pet_details'
      and column_name in (
        'species', 'breed', 'birth_date', 'microchip_id', 'vet_name',
        'vet_phone', 'feeding_notes', 'medical_notes'
      )
  ),
  'pet detail columns match the Flutter sync payload'
);
select extensions.ok(
  (
    select count(*) = 6
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'plant_details'
      and column_name in (
        'species', 'sunlight', 'watering_interval_days', 'pot_size',
        'last_repotted_at', 'toxicity_notes'
      )
  ),
  'plant detail columns match the Flutter sync payload'
);
select extensions.ok(
  (
    select count(*) = 5
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'safety_details'
      and column_name in (
        'safety_type', 'installed_at', 'expires_at', 'battery_type',
        'test_interval_days'
      )
  ),
  'safety detail columns match the Flutter sync payload'
);
select extensions.ok(
  (
    select count(*) = 7
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'maintenance_plan_metadata'
      and column_name in (
        'task_type', 'location_label', 'estimated_duration_minutes',
        'required_materials_json', 'reminder_recommendation', 'sort_order',
        'updated_at'
      )
  ),
  'maintenance metadata columns match the Flutter sync payload'
);
select extensions.ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'maintenance_plans'
      and column_name = 'interval_count'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'streaks'
      and column_name = 'longest_streak'
  ),
  'documented cloud aliases remain the canonical maintenance and streak columns'
);
select extensions.ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'assets'
      and column_name = 'sync_seq'
  ),
  'assets no longer expose sync sequence'
);
select extensions.ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'assets'
      and column_name = 'deleted_at'
  ),
  'assets use hard deletes'
);
select extensions.ok(
  to_regclass('public.maintenance_sessions') is null,
  'maintenance sessions table is removed'
);
select extensions.ok(
  to_regclass('public.maintenance_session_tasks') is null,
  'maintenance session tasks table is removed'
);
select extensions.ok(
  exists (
    select 1
    from information_schema.triggers
    where trigger_schema = 'auth'
      and event_object_schema = 'auth'
      and event_object_table = 'users'
      and trigger_name = 'initialize_owntend_profile_for_user'
  ),
  'new Auth users initialize a Owntend profile'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-1111-1111-111111111111',
  'authenticated',
  'authenticated',
  'profile-init@example.test',
  '',
  now(),
  now(),
  now()
);
select extensions.is(
  (
    select count(*)::integer
    from public.profiles
    where user_id = '11111111-1111-1111-1111-111111111111'
  ),
  1,
  'Auth registration creates exactly one profile row'
);

select * from extensions.finish();
rollback;
