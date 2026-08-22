begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(7);

-- Setup test user
insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000a', 'usera@example.com');

insert into public.areas (user_id, id, name, sort_order)
values ('00000000-0000-0000-0000-00000000000a', 'area-dedupe', 'Area Dedupe', 1);
insert into public.rooms (user_id, id, area_id, name, sort_order)
values ('00000000-0000-0000-0000-00000000000a', 'room-dedupe', 'area-dedupe', 'Room Dedupe', 1);
insert into public.assets (user_id, id, room_id, name, created_at, updated_at, revision)
values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000111', 'room-dedupe', 'Asset Dedupe', NOW(), NOW(), 1);

-- Insert photo 1 (primary)
insert into public.asset_photos (user_id, id, asset_id, object_path, is_primary, created_at, updated_at, revision)
values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000901', '00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000901.jpg', true, NOW(), NOW(), 1);

-- 1. Verify direct second primary insertion fails due to partial unique index
select extensions.throws_ok(
  $$
  insert into public.asset_photos (user_id, id, asset_id, object_path, is_primary, created_at, updated_at, revision)
  values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000902', '00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000902.jpg', true, NOW(), NOW(), 1);
  $$,
  '23505',
  NULL,
  'inserting second primary photo fails with unique constraint 23505'
);

-- 2. Insert non-primary photo succeeds
select extensions.lives_ok(
  $$
  insert into public.asset_photos (user_id, id, asset_id, object_path, is_primary, created_at, updated_at, revision)
  values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000902', '00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000902.jpg', false, NOW(), NOW(), 1);
  $$,
  'inserting non-primary photo succeeds'
);

-- 3. Check row count (all photos preserved)
select extensions.is(
  (select count(*)::int from public.asset_photos where asset_id = '00000000-0000-0000-0000-000000000111'),
  2,
  'both photo rows are preserved'
);

-- 4. set_primary_asset_photo RPC works cleanly under constraint
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

select extensions.lives_ok(
  $$ select public.set_primary_asset_photo('00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-000000000902') $$,
  'set_primary_asset_photo RPC succeeds under constraint'
);

set local role postgres;

-- 5. Verify 902 is primary and 901 is demoted
select extensions.is(
  (select is_primary from public.asset_photos where id = '00000000-0000-0000-0000-000000000902'),
  true,
  'photo 902 is primary'
);

select extensions.is(
  (select is_primary from public.asset_photos where id = '00000000-0000-0000-0000-000000000901'),
  false,
  'photo 901 is non-primary'
);

-- 6. Verify exactly 1 primary photo exists for asset
select extensions.is(
  (select count(*)::int from public.asset_photos where asset_id = '00000000-0000-0000-0000-000000000111' and is_primary = true),
  1,
  'exactly 1 primary photo exists for asset'
);

rollback;
