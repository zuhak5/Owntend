begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(9);

-- 1. RPC Existence & Grants
select extensions.has_function('public', 'set_primary_asset_photo', ARRAY['text', 'text'], 'set_primary_asset_photo RPC exists');

select extensions.ok(
  not (select has_function_privilege('anon', 'public.set_primary_asset_photo(text, text)', 'execute')),
  'anon role cannot execute set_primary_asset_photo'
);

select extensions.ok(
  (select has_function_privilege('authenticated', 'public.set_primary_asset_photo(text, text)', 'execute')),
  'authenticated role can execute set_primary_asset_photo'
);

-- Setup test users
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'usera@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'userb@example.com');

-- 2. Unauthenticated Call Fails
set local role anon;
select extensions.throws_ok(
  $$ select public.set_primary_asset_photo('00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-000000000999') $$,
  '42501',
  NULL,
  'unauthenticated set_primary_asset_photo call fails'
);

-- Setup domain data
set local role postgres;
insert into public.assets (user_id, id, name, created_at, updated_at, revision)
values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000111', 'Asset Primary', NOW(), NOW(), 1);

insert into public.asset_photos (user_id, id, asset_id, object_path, is_primary, created_at, updated_at, revision)
values
  ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000901', '00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000901.jpg', true, NOW(), NOW(), 1),
  ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000902', '00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000902.jpg', false, NOW(), NOW(), 1);

-- 3. Authenticated Set Primary
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

select extensions.lives_ok(
  $$ select public.set_primary_asset_photo('00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-000000000902') $$,
  'set_primary_asset_photo succeeds for valid photo'
);

-- 4. Verify peer normalization
select extensions.is(
  (select is_primary from public.asset_photos where id = '00000000-0000-0000-0000-000000000902'),
  true,
  'target photo 902 is now primary'
);

select extensions.is(
  (select is_primary from public.asset_photos where id = '00000000-0000-0000-0000-000000000901'),
  false,
  'peer photo 901 is cleared to false'
);

-- 5. Idempotent Replay
select extensions.lives_ok(
  $$ select public.set_primary_asset_photo('00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-000000000902') $$,
  'set_primary_asset_photo idempotent replay succeeds'
);

-- 6. Cross-User Denial
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000b"}';

select extensions.throws_ok(
  $$ select public.set_primary_asset_photo('00000000-0000-0000-0000-000000000111', '00000000-0000-0000-0000-000000000902') $$,
  '42501',
  NULL,
  'user B cannot set primary on user A asset photo'
);

rollback;
