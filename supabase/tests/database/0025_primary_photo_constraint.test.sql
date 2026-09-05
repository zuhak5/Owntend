begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(23);

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

-- 7. Add 3 more photos (simulating 5-photo real user scenario)
select extensions.lives_ok(
  $$
  insert into public.asset_photos (user_id, id, asset_id, object_path, is_primary, created_at, updated_at, revision)
  values
    ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000903', '00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000903.jpg', false, NOW(), NOW(), 1),
    ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000904', '00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000904.jpg', false, NOW(), NOW(), 1),
    ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000905', '00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000905.jpg', false, NOW(), NOW(), 1);
  $$,
  'inserting 3 additional non-primary photos succeeds'
);

-- 8. Verify total photos count is 5
select extensions.is(
  (select count(*)::int from public.asset_photos where asset_id = '00000000-0000-0000-0000-000000000111'),
  5,
  'all 5 photo rows are present'
);

-- 9. Switch primary to photo 905
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

select extensions.lives_ok(
  $$ select public.set_primary_asset_photo('00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-000000000905') $$,
  'switch primary to photo 905 succeeds without unique constraint violation'
);

set local role postgres;

-- 10. Verify 905 is primary
select extensions.is(
  (select is_primary from public.asset_photos where id = '00000000-0000-0000-0000-000000000905'),
  true,
  'photo 905 is now primary'
);

-- 11. Verify exactly 1 primary exists
select extensions.is(
  (select count(*)::int from public.asset_photos where asset_id = '00000000-0000-0000-0000-000000000111' and is_primary = true),
  1,
  'exactly 1 primary photo exists after switching to 905'
);

-- 12. Switch primary to photo 903
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

select extensions.lives_ok(
  $$ select public.set_primary_asset_photo('00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-000000000903') $$,
  'switch primary to photo 903 succeeds without unique constraint violation'
);

set local role postgres;

-- 13. Verify 903 is primary and 905 is demoted
select extensions.is(
  (select is_primary from public.asset_photos where id = '00000000-0000-0000-0000-000000000903'),
  true,
  'photo 903 is now primary'
);

select extensions.is(
  (select is_primary from public.asset_photos where id = '00000000-0000-0000-0000-000000000905'),
  false,
  'former primary photo 905 is now non-primary'
);

-- 14. Verify exactly 1 primary exists
select extensions.is(
  (select count(*)::int from public.asset_photos where asset_id = '00000000-0000-0000-0000-000000000111' and is_primary = true),
  1,
  'exactly 1 primary photo exists after switching to 903'
);

-- 15. Switch back to original photo 901
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

select extensions.lives_ok(
  $$ select public.set_primary_asset_photo('00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-000000000901') $$,
  'switch back to original photo 901 succeeds'
);

set local role postgres;

-- 16. Verify 901 is primary and 903 is demoted
select extensions.is(
  (select is_primary from public.asset_photos where id = '00000000-0000-0000-0000-000000000901'),
  true,
  'photo 901 is now primary'
);

-- 17. Verify exactly 1 primary photo exists for asset
select extensions.is(
  (select count(*)::int from public.asset_photos where asset_id = '00000000-0000-0000-0000-000000000111' and is_primary = true),
  1,
  'exactly 1 primary photo exists for asset after multi-way switching'
);

-- 18. Delete photo 905 with explicit asset_id
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

select extensions.lives_ok(
  $$ select public.delete_asset_photo('00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-000000000905') $$,
  'delete photo 905 with explicit asset_id succeeds'
);

-- 19. Delete photo 904 with omitted/NULL asset_id
select extensions.lives_ok(
  $$ select public.delete_asset_photo(p_photo_id := '00000000-0000-0000-0000-000000000904') $$,
  'delete photo 904 with omitted asset_id succeeds'
);

set local role postgres;

-- 20. Verify 3 photos remaining
select extensions.is(
  (select count(*)::int from public.asset_photos where asset_id = '00000000-0000-0000-0000-000000000111'),
  3,
  '3 photos remain after deleting 2 photos'
);

-- 21. Idempotent delete on photo 904
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

select extensions.is(
  (select (public.delete_asset_photo(p_photo_id := '00000000-0000-0000-0000-000000000904') ->> 'idempotent')::boolean),
  true,
  'subsequent delete on already-deleted photo 904 is idempotent'
);

set local role postgres;

rollback;
