begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(12);

select extensions.results_eq(
  $$
    select
      columns.table_name::text collate "C",
      columns.column_name::text collate "C"
    from information_schema.columns as columns
    where columns.table_schema = 'public'
      and columns.table_name = any (array[
        'profiles', 'areas', 'rooms', 'assets', 'device_details',
        'pet_details', 'plant_details', 'safety_details', 'tags',
        'asset_tags', 'asset_photos', 'maintenance_plans',
        'maintenance_plan_metadata', 'maintenance_records',
        'notification_inbox', 'user_settings', 'streaks'
      ])
      and has_column_privilege(
        'authenticated',
        format('public.%I', columns.table_name),
        columns.column_name,
        'UPDATE'
      )
    order by columns.table_name, columns.column_name
  $$,
  $$
    select
      expected.table_name collate "C",
      expected.column_name collate "C"
    from (values
      ('areas', 'archived_at'),
      ('areas', 'kind'),
      ('areas', 'name'),
      ('areas', 'sort_order'),
      ('assets', 'archived_at'),
      ('assets', 'name'),
      ('assets', 'notes'),
      ('assets', 'placement'),
      ('assets', 'purchase_date'),
      ('assets', 'room_id'),
      ('device_details', 'brand'),
      ('device_details', 'consumable'),
      ('device_details', 'manual_url'),
      ('device_details', 'model'),
      ('device_details', 'power_source'),
      ('device_details', 'serial_number'),
      ('device_details', 'warranty_until'),
      ('maintenance_plan_metadata', 'estimated_duration_minutes'),
      ('maintenance_plan_metadata', 'location_label'),
      ('maintenance_plan_metadata', 'reminder_recommendation'),
      ('maintenance_plan_metadata', 'required_materials_json'),
      ('maintenance_plan_metadata', 'sort_order'),
      ('maintenance_plan_metadata', 'task_type'),
      ('maintenance_plans', 'archived_at'),
      ('maintenance_plans', 'instructions'),
      ('maintenance_plans', 'is_enabled'),
      ('maintenance_plans', 'next_due_date'),
      ('maintenance_plans', 'priority'),
      ('maintenance_plans', 'recurrence_interval'),
      ('maintenance_plans', 'recurrence_unit'),
      ('maintenance_plans', 'reminder_days_before'),
      ('maintenance_plans', 'title'),
      ('notification_inbox', 'read_at'),
      ('pet_details', 'birth_date'),
      ('pet_details', 'breed'),
      ('pet_details', 'feeding_notes'),
      ('pet_details', 'medical_notes'),
      ('pet_details', 'microchip_id'),
      ('pet_details', 'species'),
      ('pet_details', 'vet_name'),
      ('pet_details', 'vet_phone'),
      ('plant_details', 'last_repotted_at'),
      ('plant_details', 'pot_size'),
      ('plant_details', 'species'),
      ('plant_details', 'sunlight'),
      ('plant_details', 'toxicity_notes'),
      ('plant_details', 'watering_interval_days'),
      ('profiles', 'nickname'),
      ('rooms', 'archived_at'),
      ('rooms', 'area_id'),
      ('rooms', 'name'),
      ('rooms', 'notes'),
      ('rooms', 'room_type'),
      ('rooms', 'sort_order'),
      ('safety_details', 'battery_type'),
      ('safety_details', 'expires_at'),
      ('safety_details', 'installed_at'),
      ('safety_details', 'safety_type'),
      ('safety_details', 'test_interval_days'),
      ('streaks', 'current_streak'),
      ('streaks', 'last_completion_date'),
      ('streaks', 'longest_streak'),
      ('tags', 'name'),
      ('user_settings', 'value')
    ) as expected(table_name, column_name)
    order by expected.table_name, expected.column_name
  $$,
  'authenticated has exactly the generic sync UPDATE column matrix'
);

select extensions.ok(
  (
    select bool_and(
      not has_table_privilege(
        'authenticated',
        format('public.%I', table_name),
        'UPDATE'
      )
    )
    from unnest(array[
      'profiles', 'areas', 'rooms', 'assets', 'device_details',
      'pet_details', 'plant_details', 'safety_details', 'tags',
      'asset_tags', 'asset_photos', 'maintenance_plans',
      'maintenance_plan_metadata', 'maintenance_records',
      'notification_inbox', 'user_settings', 'streaks'
    ]) as table_names(table_name)
  ),
  'authenticated retains no table-wide UPDATE privilege on synchronized tables'
);

insert into auth.users (id, email) values
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'sync-acl-owner@example.invalid'),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'sync-acl-other@example.invalid');
insert into public.areas (user_id, id, name) values
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'sync-acl-area', 'Before area');
insert into public.rooms (user_id, id, area_id, name) values
  (
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'sync-acl-room',
    'sync-acl-area',
    'Before room'
  );
insert into public.assets (user_id, id, room_id, name, asset_type) values
  (
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'sync-acl-asset',
    'sync-acl-room',
    'Before asset',
    'general'
  );
insert into public.maintenance_plans (
  user_id,
  id,
  asset_id,
  title,
  recurrence_interval,
  recurrence_unit,
  priority,
  next_due_date
) values (
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  'sync-acl-plan',
  'sync-acl-asset',
  'Before plan',
  1,
  'months',
  'medium',
  '2026-10-01T00:00:00Z'
);

create temporary table sync_acl_before (
  entity text primary key,
  revision bigint not null,
  updated_at timestamptz not null
);
insert into sync_acl_before
select 'asset', revision, updated_at
from public.assets
where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
  and id = 'sync-acl-asset'
union all
select 'plan', revision, updated_at
from public.maintenance_plans
where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
  and id = 'sync-acl-plan';
grant select on sync_acl_before to authenticated;

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}';

create temporary table sync_acl_after (
  entity text primary key,
  revision bigint not null,
  updated_at timestamptz not null
);
with changed as (
  update public.assets
  set name = 'After asset', notes = null
  where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
    and id = 'sync-acl-asset'
  returning revision, updated_at
)
insert into sync_acl_after
select 'asset', revision, updated_at from changed;
with changed as (
  update public.maintenance_plans
  set title = 'After plan', instructions = null
  where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
    and id = 'sync-acl-plan'
  returning revision, updated_at
)
insert into sync_acl_after
select 'plan', revision, updated_at from changed;

select extensions.is(
  (select revision from sync_acl_after where entity = 'asset'),
  (select revision + 1 from sync_acl_before where entity = 'asset'),
  'an allowed asset UPDATE returns a server-incremented revision'
);
select extensions.ok(
  (select after.updated_at > before.updated_at
   from sync_acl_after as after
   join sync_acl_before as before using (entity)
   where after.entity = 'asset'),
  'an allowed asset UPDATE returns a newer server timestamp'
);
select extensions.is(
  (select revision from sync_acl_after where entity = 'plan'),
  (select revision + 1 from sync_acl_before where entity = 'plan'),
  'an allowed plan UPDATE returns a server-incremented revision'
);
select extensions.ok(
  (select after.updated_at > before.updated_at
   from sync_acl_after as after
   join sync_acl_before as before using (entity)
   where after.entity = 'plan'),
  'an allowed plan UPDATE returns a newer server timestamp'
);

select extensions.throws_ok(
  $$update public.assets set asset_type = 'safety' where id = 'sync-acl-asset'$$,
  '42501',
  'permission denied for table assets',
  'asset type remains RPC-authoritative'
);
select extensions.throws_ok(
  $$update public.maintenance_plans set asset_id = 'other' where id = 'sync-acl-plan'$$,
  '42501',
  'permission denied for table maintenance_plans',
  'plan ownership relation remains RPC-authoritative'
);
select extensions.throws_ok(
  $$update public.assets set updated_at = now() where id = 'sync-acl-asset'$$,
  '42501',
  'permission denied for table assets',
  'clients cannot author asset server timestamps'
);
select extensions.throws_ok(
  $$update public.maintenance_plans set revision = 99 where id = 'sync-acl-plan'$$,
  '42501',
  'permission denied for table maintenance_plans',
  'clients cannot author plan revisions'
);

set local "request.jwt.claims" =
  '{"sub":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","role":"authenticated"}';
create temporary table sync_acl_cross_user_attempts (entity text);
with asset_attempt as (
  update public.assets
  set name = 'Cross-user asset'
  where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
    and id = 'sync-acl-asset'
  returning 'asset'::text as entity
), plan_attempt as (
  update public.maintenance_plans
  set title = 'Cross-user plan'
  where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
    and id = 'sync-acl-plan'
  returning 'plan'::text as entity
)
insert into sync_acl_cross_user_attempts
select entity from asset_attempt
union all
select entity from plan_attempt;

select extensions.is(
  (select count(*)::integer from sync_acl_cross_user_attempts),
  0,
  'owner RLS hides both asset and plan rows from another account'
);

set local role postgres;
select extensions.ok(
  (select name = 'After asset'
   from public.assets
   where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
     and id = 'sync-acl-asset')
  and
  (select title = 'After plan'
   from public.maintenance_plans
   where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
     and id = 'sync-acl-plan'),
  'cross-user attempts leave both canonical rows unchanged'
);

select * from extensions.finish();
rollback;
