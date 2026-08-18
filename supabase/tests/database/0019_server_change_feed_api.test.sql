begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(15);

-- 1. Check RPC Existence & Function Grants
select extensions.has_function('public', 'get_sync_feed_capability', ARRAY[]::text[], 'get_sync_feed_capability RPC exists');
select extensions.has_function('public', 'fetch_user_change_feed', ARRAY['bigint', 'integer'], 'fetch_user_change_feed RPC exists');
select extensions.has_function('public', 'validate_change_feed_parity', ARRAY[]::text[], 'owner-scoped validate_change_feed_parity RPC exists');
select extensions.hasnt_function('public', 'validate_change_feed_parity', ARRAY['uuid'], 'caller-selected parity RPC was removed');

select extensions.ok(
  not (select has_function_privilege('anon', 'public.fetch_user_change_feed(bigint, integer)', 'execute')),
  'anon role cannot execute fetch_user_change_feed'
);

select extensions.ok(
  (select has_function_privilege('authenticated', 'public.fetch_user_change_feed(bigint, integer)', 'execute')),
  'authenticated role can execute fetch_user_change_feed'
);

-- Setup test users
prepare create_user_a as insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000a', 'usera@example.com');
prepare create_user_b as insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000b', 'userb@example.com');
execute create_user_a;
execute create_user_b;

truncate table public.server_change_feed restart identity;

-- 2. Unauthenticated Call Fails
set local role anon;
select extensions.throws_ok(
  $$ select public.fetch_user_change_feed(0, 50) $$,
  '42501',
  'permission denied for function fetch_user_change_feed',
  'unauthenticated fetch_user_change_feed call is rejected by function ACLs'
);

-- 3. Authenticated Paging & High-Water Capture
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

-- Create initial items for User A
insert into public.areas (user_id, id, name, kind, sort_order, created_at, updated_at, revision)
values
  ('00000000-0000-0000-0000-00000000000a', 'area-a1', 'Area A1', 'indoor', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 1),
  ('00000000-0000-0000-0000-00000000000a', 'area-a2', 'Area A2', 'indoor', 2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 1),
  ('00000000-0000-0000-0000-00000000000a', 'area-a3', 'Area A3', 'indoor', 3, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 1);

select extensions.is(
  (public.fetch_user_change_feed(0, 2)->>'next_seq')::bigint,
  2::bigint,
  'fetch_user_change_feed with limit 2 returns next_seq = 2'
);

select extensions.is(
  (public.fetch_user_change_feed(0, 2)->>'has_more')::boolean,
  true,
  'fetch_user_change_feed with limit 2 indicates has_more = true'
);

select extensions.is(
  (public.fetch_user_change_feed(2, 50)->>'next_seq')::bigint,
  3::bigint,
  'fetching since_seq = 2 returns remaining item with next_seq = 3'
);

select extensions.is(
  (public.fetch_user_change_feed(2, 50)->>'has_more')::boolean,
  false,
  'fetching page draining high-water returns has_more = false'
);

-- 4. Cross-Owner Isolation
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000b"}';

select extensions.is(
  (public.fetch_user_change_feed(0, 50)->>'high_water_seq')::bigint,
  0::bigint,
  'User B sees empty high_water_seq and no User A changes'
);

-- 5. Dark Parity Validator Test
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

select extensions.results_eq(
  $$ select is_parity from public.validate_change_feed_parity() where entity_type = 'area' $$,
  $$ values (true) $$,
  'Dark parity validator derives User A from auth.uid and matches change feed net count'
);

-- 6. Resnapshot Required Test
set local role postgres;
update public.sync_feed_capabilities set min_retained_seq = 10 where id = 'global';

set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

select extensions.is(
  (public.fetch_user_change_feed(5, 50)->>'resnapshot_required')::boolean,
  true,
  'fetch_user_change_feed returns resnapshot_required = true when requested sequence predates min_retained_seq'
);

select extensions.pass('Task 18 Server Change-Feed API tests complete');

rollback;
