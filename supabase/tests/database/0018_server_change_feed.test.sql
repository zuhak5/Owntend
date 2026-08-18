begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(15);

-- 1. Table and Function Existence Checks
select extensions.has_table('public', 'server_change_feed', 'server_change_feed table exists');
select extensions.has_function('public', 'fn_log_server_change_feed', 'fn_log_server_change_feed trigger function exists');
select extensions.has_function('public', 'get_user_change_feed_watermark', ARRAY[]::text[], 'owner-scoped get_user_change_feed_watermark RPC exists');
select extensions.hasnt_function('public', 'get_user_change_feed_watermark', ARRAY['uuid'], 'caller-selected watermark RPC was removed');

-- Grants Check
select extensions.ok(
  not (select has_table_privilege('anon', 'public.server_change_feed', 'select')),
  'anon role cannot select server_change_feed'
);

select extensions.ok(
  (select has_table_privilege('authenticated', 'public.server_change_feed', 'select')),
  'authenticated role can select server_change_feed'
);

select extensions.ok(
  not (select has_table_privilege('authenticated', 'public.server_change_feed', 'insert')),
  'authenticated role cannot insert directly into server_change_feed'
);

-- Setup test users
prepare create_user_a as insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000a', 'usera@example.com');
prepare create_user_b as insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000b', 'userb@example.com');
execute create_user_a;
execute create_user_b;

-- Auth initialization creates a profile, and profiles participate in the
-- canonical owner-scoped change feed.
select extensions.results_eq(
  $$ select entity_type, record_id, op_type
     from public.server_change_feed
     where user_id = '00000000-0000-0000-0000-00000000000a'
       and entity_type = 'profile'
       and record_id = 'profile'
     order by change_seq asc
     limit 1 $$,
  $$ values (
    'profile',
    'profile',
    'INSERT'
  ) $$,
  'Auth user initialization logs profile INSERT change feed entry'
);

-- 2. Test Trigger on INSERT / UPDATE / DELETE
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

insert into public.areas (user_id, id, name, kind, sort_order, created_at, updated_at, revision)
values (
  '00000000-0000-0000-0000-00000000000a',
  'area-1',
  'Main Area',
  'indoor',
  1,
  '2020-01-01T00:00:00Z',
  '2020-01-01T00:00:00Z',
  1
);

select extensions.results_eq(
  $$ select entity_type, record_id, op_type
     from public.server_change_feed
     where user_id = '00000000-0000-0000-0000-00000000000a'
       and entity_type = 'area'
       and record_id = 'area-1' $$,
  $$ values ('area', 'area-1', 'INSERT') $$,
  'INSERT on areas automatically logs INSERT change feed entry'
);

-- Update area with backdated client timestamp
update public.areas
set name = 'Updated Main Area', updated_at = '1999-01-01T00:00:00Z', revision = 2
where user_id = '00000000-0000-0000-0000-00000000000a' and id = 'area-1';

select extensions.results_eq(
  $$ select op_type, revision from public.server_change_feed where user_id = '00000000-0000-0000-0000-00000000000a' order by change_seq desc limit 1 $$,
  $$ values ('UPDATE', 2::bigint) $$,
  'UPDATE on areas automatically logs UPDATE change feed entry regardless of backdated timestamp'
);

-- Delete area
delete from public.areas
where user_id = '00000000-0000-0000-0000-00000000000a' and id = 'area-1';

select extensions.results_eq(
  $$ select op_type, record_id from public.server_change_feed where user_id = '00000000-0000-0000-0000-00000000000a' order by change_seq desc limit 1 $$,
  $$ values ('DELETE', 'area-1') $$,
  'DELETE on areas logs durable DELETE record in change feed'
);

-- 3. Check Monotonic Sequence Ordering
select extensions.results_eq(
  $$ select count(distinct change_seq)
     from public.server_change_feed
     where user_id = '00000000-0000-0000-0000-00000000000a'
       and entity_type = 'area' $$,
  $$ values (3::bigint) $$,
  'All 3 area operations created unique monotonic change sequences'
);

-- 4. Check RLS Cross-User Isolation
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000b"}';

insert into public.areas (user_id, id, name, kind, sort_order, created_at, updated_at, revision)
values (
  '00000000-0000-0000-0000-00000000000b',
  'area-b1',
  'User B Area',
  'indoor',
  1,
  '2026-01-01T00:00:00Z',
  '2026-01-01T00:00:00Z',
  1
);

select extensions.results_eq(
  $$ select count(*) from public.server_change_feed $$,
  $$ values (2::bigint) $$,
  'User B RLS policy permits reading only User B profile and area records'
);

-- 5. Test owner-scoped Watermark Helper Function
select extensions.results_eq(
  $$ select total_changes from public.get_user_change_feed_watermark() $$,
  $$ values (2::bigint) $$,
  'Watermark helper derives User B from auth.uid and includes only User B changes'
);

-- 6. The pre-launch baseline has no legacy backfill surface.
set local role postgres;
select extensions.hasnt_function(
  'public',
  'fn_backfill_server_change_feed',
  'pre-launch change feed has no legacy backfill function'
);

rollback;
