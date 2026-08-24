begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(7);

-- Create a test user
insert into auth.users (id, email)
values ('00000000-0000-0000-0000-000000000099', 'null_coalesce_test@owntend.app')
on conflict (id) do nothing;

-- 1. Insert area with explicit null sort_order
insert into public.areas (user_id, id, name, sort_order)
values ('00000000-0000-0000-0000-000000000099', 'area_null_test', 'Test Area', null);

select extensions.is(
  (select sort_order from public.areas where id = 'area_null_test'),
  0,
  'areas sort_order coalesces null to 0'
);

-- 2. Insert room with explicit null sort_order
insert into public.rooms (user_id, id, area_id, name, sort_order)
values ('00000000-0000-0000-0000-000000000099', 'room_null_test', 'area_null_test', 'Test Room', null);

select extensions.is(
  (select sort_order from public.rooms where id = 'room_null_test'),
  0,
  'rooms sort_order coalesces null to 0'
);

-- 3. Insert asset
insert into public.assets (user_id, id, room_id, name)
values ('00000000-0000-0000-0000-000000000099', 'asset_null_test', 'room_null_test', 'Test Asset');

-- 4. Insert maintenance plan with explicit null reminder_days_before and is_enabled
insert into public.maintenance_plans (user_id, id, asset_id, title, recurrence_interval, recurrence_unit, priority, next_due_date, reminder_days_before, is_enabled)
values ('00000000-0000-0000-0000-000000000099', 'plan_null_test', 'asset_null_test', 'Test Plan', 1, 'months', 'medium', now(), null, null);

select extensions.is(
  (select reminder_days_before from public.maintenance_plans where id = 'plan_null_test'),
  0,
  'maintenance_plans reminder_days_before coalesces null to 0'
);

select extensions.is(
  (select is_enabled from public.maintenance_plans where id = 'plan_null_test'),
  true,
  'maintenance_plans is_enabled coalesces null to true'
);

-- 5. Insert maintenance plan metadata with explicit null sort_order and required_materials_json
insert into public.maintenance_plan_metadata (user_id, plan_id, sort_order, required_materials_json)
values ('00000000-0000-0000-0000-000000000099', 'plan_null_test', null, null);

select extensions.is(
  (select sort_order from public.maintenance_plan_metadata where plan_id = 'plan_null_test'),
  0,
  'maintenance_plan_metadata sort_order coalesces null to 0'
);

select extensions.is(
  (select required_materials_json from public.maintenance_plan_metadata where plan_id = 'plan_null_test'),
  '[]',
  'maintenance_plan_metadata required_materials_json coalesces null to []'
);

-- 6. Insert asset photo with explicit null is_primary
insert into public.asset_photos (user_id, id, asset_id, storage_path, thumbnail_path, is_primary)
values ('00000000-0000-0000-0000-000000000099', 'photo_null_test', 'asset_null_test', 'test/path.jpg', 'test/thumb.jpg', null);

select extensions.is(
  (select is_primary from public.asset_photos where id = 'photo_null_test'),
  false,
  'asset_photos is_primary coalesces null to false'
);

select * from extensions.finish();
rollback;
