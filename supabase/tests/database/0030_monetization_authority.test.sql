begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(17);

-- MON-001: one server-authoritative mutation path for assets and typed
-- monetization events. Direct client INSERT into assets is denied so the
-- canonical idempotent aggregate RPC cannot be bypassed; ordinary owner-
-- scoped updates and deletes remain authorized; event properties are an
-- event-specific technical allowlist that rejects unknown keys, wrong
-- types, and unbounded values.

insert into auth.users (id, email)
values ('00000000-0000-0000-0000-00000000000a', 'mon-a@example.com'),
       ('00000000-0000-0000-0000-00000000000b', 'mon-b@example.com');

truncate table public.server_change_feed restart identity;
truncate table public.owner_feed_state cascade;

-- 1. Direct asset creation is refused for authenticated clients.
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';
insert into public.areas (user_id, id, name, kind, sort_order, created_at, updated_at, revision)
values (
  '00000000-0000-0000-0000-00000000000a', 'area-mon-a', 'Mon Area A', 'indoor', 0,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 1
);
insert into public.rooms (user_id, id, area_id, name, room_type, sort_order, created_at, updated_at)
values (
  '00000000-0000-0000-0000-00000000000a', 'room-mon-a', 'area-mon-a', 'Mon Room A', 'office', 0,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
);
select extensions.throws_ok(
  $$ insert into public.assets (user_id, id, name, asset_type, room_id, created_at, updated_at, revision)
     values (
       '00000000-0000-0000-0000-00000000000a', 'asset-mon-direct', 'Bypass Asset', 'device',
       'room-mon-a', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 1
     ) $$,
  '42501',
  NULL,
  'direct INSERT into assets is denied; creation must use the aggregate RPC'
);

-- 2. Creation through the canonical idempotent RPC succeeds.
select extensions.is(
  (public.create_asset(
     jsonb_build_object(
       'operation_id', '11111111-1111-5111-8111-111111111111',
       'request_hash', repeat('a', 64),
       'asset', jsonb_build_object(
         'id', 'asset-mon-rpc', 'name', 'Rpc Asset', 'asset_type', 'device',
         'room_id', 'room-mon-a'
       )
     )
   )->>'already_processed')::boolean,
  false,
  'aggregate RPC creates the asset through the authoritative path'
);

-- 3. Replaying the exact operation stays idempotent.
select extensions.is(
  (public.create_asset(
     jsonb_build_object(
       'operation_id', '11111111-1111-5111-8111-111111111111',
       'request_hash', repeat('a', 64),
       'asset', jsonb_build_object(
         'id', 'asset-mon-rpc', 'name', 'Rpc Asset', 'asset_type', 'device',
         'room_id', 'room-mon-a'
       )
     )
   )->>'already_processed')::boolean,
  true,
  'replaying the same creation operation returns already_processed without duplicating'
);

select extensions.is(
  (select count(*) from public.assets where id = 'asset-mon-rpc'),
  1::bigint,
  'exactly one canonical asset row exists after replay'
);

-- 4. Ordinary synchronized updates keep their authorized owner-scoped
--    contract; cross-user updates are denied by RLS.
update public.assets
set name = 'Rpc Asset Renamed', updated_at = '2026-02-01T00:00:00Z', revision = 2
where user_id = '00000000-0000-0000-0000-00000000000a' and id = 'asset-mon-rpc';

select extensions.is(
  (select revision from public.assets where id = 'asset-mon-rpc'),
  2::bigint,
  'owner-scoped UPDATE remains authorized for ordinary synchronization'
);

set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000b"}';
insert into public.areas (user_id, id, name, kind, sort_order, created_at, updated_at, revision)
values (
  '00000000-0000-0000-0000-00000000000b', 'area-mon-b', 'Mon Area B', 'indoor', 0,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 1
);
insert into public.rooms (user_id, id, area_id, name, room_type, sort_order, created_at, updated_at)
values (
  '00000000-0000-0000-0000-00000000000b', 'room-mon-b', 'area-mon-b', 'Mon Room B', 'office', 0,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
);
-- Seed the other owner's asset as postgres: clients cannot INSERT directly.
set local role postgres;
insert into public.assets (user_id, id, name, asset_type, room_id, created_at, updated_at, revision)
values (
  '00000000-0000-0000-0000-00000000000b', 'asset-mon-b', 'User B Asset', 'general',
  'room-mon-b', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 1
);
set local role authenticated;
-- RLS makes the other owner's row invisible, so the UPDATE silently affects
-- zero rows instead of raising; assert nothing was mutated.
update public.assets set name = 'hijacked'
where user_id = '00000000-0000-0000-0000-00000000000a' and id = 'asset-mon-rpc';
set local role postgres;
select extensions.is(
  (select count(*) from public.assets
   where id = 'asset-mon-rpc' and name = 'hijacked'),
  0::bigint,
  'cross-user UPDATE is invisible and cannot be mutated by another owner'
);
set local role authenticated;

-- 5. Typed monetization event allowlist.
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

select extensions.lives_ok(
  $$ select public.record_monetization_event('ad_rewarded_watched',
       jsonb_build_object('reward_amount', 5, 'entry_point', 'wallet_sheet', 'verification', 'server_pending')) $$,
  'allowlisted rewarded-watch properties are accepted'
);

select extensions.lives_ok(
  $$ select public.record_monetization_event('points_debited',
       jsonb_build_object('entity_type', 'asset_copy', 'entity_id', '11111111-1111-5111-8111-111111111112',
         'cost', 1, 'new_balance', 12, 'included_task_count', 3)) $$,
  'allowlisted debit properties are accepted'
);

select extensions.lives_ok(
  $$ select public.record_monetization_event('ad_native_impression',
       jsonb_build_object('screen_name', 'home',
         'ad_unit_id', 'ca-app-pub-5274007212820203/8393243294')) $$,
  'canonical AdMob unit identifiers are accepted'
);

select extensions.throws_ok(
  $$ select public.record_monetization_event('ad_native_impression',
       jsonb_build_object('screen_name', 'home', 'ad_unit_id', 'native_home')) $$,
  '22023',
  'INVALID_EVENT_PROPERTY',
  'non-canonical ad unit identifier shapes are rejected'
);

select extensions.throws_ok(
  $$ select public.record_monetization_event('ad_native_impression',
       jsonb_build_object('screen_name', 'home', 'ad_unit_id', 'ca-app-pub-3940256099942544/2247696110', 'user_note', 'free text')) $$,
  '22023',
  'INVALID_EVENT_PROPERTY',
  'extra keys outside the allowlist are rejected even with valid core fields'
);

select extensions.throws_ok(
  $$ select public.record_monetization_event('point_shortage_encountered',
       jsonb_build_object('attempted_action', 'my house has a leaking roof')) $$,
  '22023',
  'INVALID_EVENT_PROPERTY',
  'user-content values are rejected by the permitted-value contract'
);

select extensions.throws_ok(
  $$ select public.record_monetization_event('points_debited',
       jsonb_build_object('entity_type', 'asset_copy', 'cost', 'many', 'new_balance', -5)) $$,
  '22023',
  'INVALID_EVENT_PROPERTY',
  'wrong types and out-of-range values are rejected'
);

select extensions.throws_ok(
  $$ select public.record_monetization_event('ad_interstitial_shown',
       jsonb_build_object('session_ad_count', 999999)) $$,
  '22023',
  'INVALID_EVENT_PROPERTY',
  'unbounded counters are rejected'
);

set local role postgres;
select extensions.is(
  (select count(*) from public.monetization_events),
  3::bigint,
  'only the three valid events reached the ledger'
);

select extensions.ok(
  not (select has_table_privilege('authenticated', 'public.monetization_events', 'insert')),
  'direct ledger inserts are denied; the typed RPC is the only writer'
);

select extensions.pass('monetization mutation-authority invariants complete');

rollback;
