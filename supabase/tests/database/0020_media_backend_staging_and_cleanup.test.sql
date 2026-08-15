begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(17);

-- 1. Check RPC Existence & Function Grants
select extensions.has_function('public', 'stage_media_upload', ARRAY['text', 'bigint', 'text', 'text'], 'stage_media_upload RPC exists');
select extensions.has_function('public', 'finalize_asset_photo_upload', ARRAY['uuid', 'text', 'text', 'integer'], 'finalize_asset_photo_upload RPC exists');
select extensions.has_function('public', 'complete_owntend_account_cleanup', ARRAY['uuid', 'text'], 'account cleanup completion RPC exists');

select extensions.ok(
  not (select has_function_privilege('anon', 'public.stage_media_upload(text, bigint, text, text)', 'execute')),
  'anon role cannot execute stage_media_upload'
);

select extensions.ok(
  (select has_function_privilege('authenticated', 'public.stage_media_upload(text, bigint, text, text)', 'execute')),
  'authenticated role can execute stage_media_upload'
);
select extensions.ok(
  has_function_privilege('service_role', 'public.complete_owntend_account_cleanup(uuid, text)', 'EXECUTE'),
  'service role can complete cleanup jobs'
);

-- Setup test users
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'usera@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'userb@example.com');

-- 2. Unauthenticated Call Fails
set local role anon;
select extensions.throws_ok(
  $$ select public.stage_media_upload('00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000999.jpg', 1024, 'image/jpeg', '1234567890123456789012345678901234567890123456789012345678901234') $$,
  '42501',
  NULL,
  'unauthenticated stage_media_upload call fails'
);

-- 3. Parameter Validation
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

select extensions.throws_ok(
  $$ select public.stage_media_upload('invalid_path', 1024, 'image/jpeg', '12345678901234567890123456789012') $$,
  '22023',
  NULL,
  'invalid path format fails'
);

select extensions.throws_ok(
  $$ select public.stage_media_upload('00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000999.jpg', 20000000, 'image/jpeg', '1234567890123456789012345678901234567890123456789012345678901234') $$,
  '22023',
  NULL,
  'object size > 10 MiB fails'
);

select extensions.throws_ok(
  $$ select public.stage_media_upload('00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000999.jpg', 1024, 'application/pdf', '1234567890123456789012345678901234567890123456789012345678901234') $$,
  '22023',
  NULL,
  'unsupported mime type fails'
);

select extensions.throws_ok(
  $$ select public.stage_media_upload('00000000-0000-0000-0000-00000000000b/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000999.jpg', 1024, 'image/jpeg', '1234567890123456789012345678901234567890123456789012345678901234') $$,
  '42501',
  NULL,
  'caller cannot stage media under another user path'
);

-- 4. Valid Staging
select extensions.lives_ok(
  $$ select public.stage_media_upload('00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000999.jpg', 1024, 'image/jpeg', '1234567890123456789012345678901234567890123456789012345678901234') $$,
  'stage_media_upload succeeds for valid input'
);

-- 5. Asset Setup & Finalization
set local role postgres;
insert into public.assets (user_id, id, name, created_at, updated_at, revision)
values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000111', 'Test Asset', NOW(), NOW(), 1);

insert into storage.objects (bucket_id, name)
values (
  'user-media',
  '00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000999.jpg'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

select extensions.lives_ok(
  $$
  select public.finalize_asset_photo_upload(
    (select id from public.media_staging_objects where staging_path = '00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000999.jpg'),
    '00000000-0000-0000-0000-000000000111',
    '00000000-0000-0000-0000-000000000999',
    1
  )
  $$,
  'finalize_asset_photo_upload succeeds'
);

-- 6. Check Asset Photo & Staging Status
select extensions.is(
  (select status from public.media_staging_objects where staging_path = '00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000999.jpg'),
  'finalized',
  'staging status is updated to finalized'
);

select extensions.is(
  (select count(*)::int from public.asset_photos where id = '00000000-0000-0000-0000-000000000999'),
  1,
  'asset_photo row is created'
);

-- 7. Idempotent Replay
select extensions.is(
  (
    select (public.finalize_asset_photo_upload(
      (select id from public.media_staging_objects where staging_path = '00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000999.jpg'),
      '00000000-0000-0000-0000-000000000111',
      '00000000-0000-0000-0000-000000000999',
      1
    ))->>'idempotent'
  ),
  'true',
  're-finalizing already finalized staging object returns idempotent true'
);

-- 8. Cross-User Isolation
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000b"}';

select extensions.throws_ok(
  $$
  select public.finalize_asset_photo_upload(
    (select id from public.media_staging_objects where staging_path = '00000000-0000-0000-0000-00000000000a/assets/00000000-0000-0000-0000-000000000111/00000000-0000-0000-0000-000000000999.jpg'),
    '00000000-0000-0000-0000-000000000111',
    '00000000-0000-0000-0000-000000000999',
    1
  )
  $$,
  'P0002',
  NULL,
  'user B cannot finalize user A staging object'
);

rollback;
