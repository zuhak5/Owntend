begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(22);

-- FEED-001: real generational compaction. Compaction that removes rows must
-- atomically advance owner_feed_state.feed_generation together with the
-- retained boundary; no-op runs must never advance it; stale cursors must
-- deterministically receive resnapshot_required; and the PostgREST-facing
-- feed/watermark RPCs must expose the durable generation through explicit
-- grants.

select extensions.has_function(
  'owntend_private',
  'compact_user_change_feed',
  ARRAY['integer', 'integer'],
  'service-only compaction function exists in the private schema'
);

select extensions.ok(
  not (select has_function_privilege('authenticated', 'owntend_private.compact_user_change_feed(integer, integer)', 'execute')),
  'authenticated clients cannot execute feed compaction directly'
);
select extensions.ok(
  not (select has_function_privilege('anon', 'public.fetch_user_change_feed(bigint, integer, bigint)', 'execute')),
  'anon role cannot execute the fetch RPC (explicit Data API exposure)'
);
select extensions.ok(
  (select has_function_privilege('authenticated', 'public.get_user_change_feed_watermark()', 'execute')),
  'authenticated role can execute the watermark RPC'
);
select extensions.ok(
  (select has_table_privilege('authenticated', 'public.owner_feed_state', 'select')),
  'owner_feed_state is explicitly readable by its owner through RLS'
);
select extensions.ok(
  not (select has_table_privilege('anon', 'public.owner_feed_state', 'select')),
  'owner_feed_state is not exposed to anon'
);

insert into auth.users (id, email)
values ('00000000-0000-0000-0000-00000000000a', 'compaction-a@example.com');

truncate table public.server_change_feed restart identity;
truncate table public.owner_feed_state cascade;

-- Five monotonic feed entries for user A.
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

insert into public.areas (user_id, id, name, kind, sort_order, created_at, updated_at, revision)
values
  ('00000000-0000-0000-0000-00000000000a', 'area-c1', 'Area C1', 'indoor', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 1),
  ('00000000-0000-0000-0000-00000000000a', 'area-c2', 'Area C2', 'indoor', 2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 1),
  ('00000000-0000-0000-0000-00000000000a', 'area-c3', 'Area C3', 'indoor', 3, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 1),
  ('00000000-0000-0000-0000-00000000000a', 'area-c4', 'Area C4', 'indoor', 4, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 1),
  ('00000000-0000-0000-0000-00000000000a', 'area-c5', 'Area C5', 'indoor', 5, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 1);

set local role postgres;
-- 1. No-op compaction: nothing to remove -> generation stays put.
select extensions.is(
  owntend_private.compact_user_change_feed(30, 1000),
  0::integer,
  'no-op compaction removes no rows'
);
select extensions.is(
  (select feed_generation from public.owner_feed_state where user_id = '00000000-0000-0000-0000-00000000000a'),
  1::bigint,
  'generation does not advance on a no-op compaction'
);
select extensions.is(
  (select retained_min_seq from public.owner_feed_state where user_id = '00000000-0000-0000-0000-00000000000a'),
  1::bigint,
  'retained boundary does not move on a no-op compaction'
);

set local role postgres;
-- 2. Row-cap compaction: newest three rows retained -> two removed and the
--    durable generation advances atomically with the retained boundary.
select extensions.is(
  owntend_private.compact_user_change_feed(30, 3),
  2::integer,
  'cap-driven compaction removes exactly the rows below the retained boundary'
);
select extensions.is(
  (select feed_generation from public.owner_feed_state where user_id = '00000000-0000-0000-0000-00000000000a'),
  2::bigint,
  'feed_generation advances when compaction removes rows'
);
select extensions.is(
  (select retained_min_seq from public.owner_feed_state where user_id = '00000000-0000-0000-0000-00000000000a'),
  3::bigint,
  'retained_min_seq advances to the new boundary'
);

-- 3. A pre-compaction cursor receives an explicit resnapshot response.
select extensions.is(
  (public.fetch_user_change_feed(1, 50, 1)->>'resnapshot_required')::boolean,
  true,
  'old-generation cursor gets resnapshot_required after compaction'
);
select extensions.is(
  (public.fetch_user_change_feed(1, 50, 1)->>'feed_generation')::bigint,
  2::bigint,
  'resnapshot response carries the new durable generation'
);

-- 4. A same-generation cursor below the retained boundary also resnapshots
--    instead of serving a silent gap.
select extensions.is(
  (public.fetch_user_change_feed(1, 50, 2)->>'resnapshot_required')::boolean,
  true,
  'same-generation cursor predating the retained range gets resnapshot_required'
);

-- 5. Continuation from exactly the retained boundary serves the remaining
--    page without a resnapshot.
select extensions.is(
  (public.fetch_user_change_feed(3, 50, 2)->>'resnapshot_required')::boolean,
  false,
  'cursor at the retained boundary continues normally'
);
select extensions.is(
  (public.fetch_user_change_feed(3, 50, 2)->>'next_seq')::bigint,
  5::bigint,
  'continuation drains up to high-water'
);

-- 6. Writes concurrent with a compacted state keep the watermark consistent
--    and do not disturb the durable generation; a repeated compaction run is
--    idempotent for the generation.
insert into public.areas (user_id, id, name, kind, sort_order, created_at, updated_at, revision)
values (
  '00000000-0000-0000-0000-00000000000a', 'area-c6', 'Area C6', 'indoor', 6,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 1
);

select extensions.results_eq(
  $$ select min_change_seq, max_change_seq, feed_generation
     from public.get_user_change_feed_watermark() $$,
  $$ values (3::bigint, 6::bigint, 2::bigint) $$,
  'watermark returns the durable generation and retained range consistently'
);

set local role postgres;
select extensions.is(
  owntend_private.compact_user_change_feed(30, 1000),
  0::integer,
  'repeat compaction with nothing below the boundary removes nothing'
);
select extensions.is(
  (select feed_generation from public.owner_feed_state where user_id = '00000000-0000-0000-0000-00000000000a'),
  2::bigint,
  'idempotent repeat run leaves the durable generation untouched'
);

-- 7. Durability across an aborted operation (restart analogue): the
--    compacted generation is independent of unrelated rollbacks.
savepoint before_unrelated_delete;
delete from public.areas where user_id = '00000000-0000-0000-0000-00000000000a' and id = 'area-c6';
rollback to savepoint before_unrelated_delete;

select extensions.is(
  (select feed_generation from public.owner_feed_state where user_id = '00000000-0000-0000-0000-00000000000a'),
  2::bigint,
  'durable generation is independent of unrelated transaction rollbacks'
);

select extensions.pass('change-feed generational compaction invariants complete');

rollback;
