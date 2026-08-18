begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(8);

select extensions.is(
  (select capability_version from public.sync_feed_capabilities where id = 'global'),
  '1.0.0'::text,
  'change-feed capability advertises the initial hardened protocol'
);

select extensions.is(
  (select enabled from public.sync_feed_capabilities where id = 'global'),
  false,
  'change-feed capability remains disabled in the pre-launch baseline'
);

with fixtures(table_name, row_data) as (
  values
    ('profiles', '{"user_id":"user-1"}'::jsonb),
    ('areas', '{"id":"area-1"}'::jsonb),
    ('rooms', '{"id":"room-1"}'::jsonb),
    ('assets', '{"id":"asset-1"}'::jsonb),
    ('device_details', '{"asset_id":"asset-1"}'::jsonb),
    ('pet_details', '{"asset_id":"asset-1"}'::jsonb),
    ('plant_details', '{"asset_id":"asset-1"}'::jsonb),
    ('safety_details', '{"asset_id":"asset-1"}'::jsonb),
    ('tags', '{"id":"tag-1"}'::jsonb),
    ('asset_tags', '{"asset_id":"asset-1","tag_id":"tag-1"}'::jsonb),
    ('asset_photos', '{"id":"photo-1"}'::jsonb),
    ('maintenance_plans', '{"id":"plan-1"}'::jsonb),
    ('maintenance_plan_metadata', '{"plan_id":"plan-1"}'::jsonb),
    ('maintenance_records', '{"id":"record-1"}'::jsonb),
    ('notification_inbox', '{"id":"inbox-1"}'::jsonb),
    ('user_settings', '{"key":"theme"}'::jsonb),
    ('streaks', '{"id":"streak-1"}'::jsonb)
), actual as (
  select jsonb_object_agg(
    table_name,
    owntend_private.sync_feed_identity(table_name, row_data)
  ) as value
  from fixtures
)
select extensions.is(
  (select value from actual),
  '{
    "profiles":{"entity_type":"profile","key_data":{},"record_id":"profile"},
    "areas":{"entity_type":"area","key_data":{"id":"area-1"},"record_id":"area-1"},
    "rooms":{"entity_type":"room","key_data":{"id":"room-1"},"record_id":"room-1"},
    "assets":{"entity_type":"asset","key_data":{"id":"asset-1"},"record_id":"asset-1"},
    "device_details":{"entity_type":"device_detail","key_data":{"asset_id":"asset-1"},"record_id":"asset-1"},
    "pet_details":{"entity_type":"pet_detail","key_data":{"asset_id":"asset-1"},"record_id":"asset-1"},
    "plant_details":{"entity_type":"plant_detail","key_data":{"asset_id":"asset-1"},"record_id":"asset-1"},
    "safety_details":{"entity_type":"safety_detail","key_data":{"asset_id":"asset-1"},"record_id":"asset-1"},
    "tags":{"entity_type":"tag","key_data":{"id":"tag-1"},"record_id":"tag-1"},
    "asset_tags":{"entity_type":"asset_tag","key_data":{"asset_id":"asset-1","tag_id":"tag-1"},"record_id":"asset-1|tag-1"},
    "asset_photos":{"entity_type":"asset_photo","key_data":{"id":"photo-1"},"record_id":"photo-1"},
    "maintenance_plans":{"entity_type":"maintenance_plan","key_data":{"id":"plan-1"},"record_id":"plan-1"},
    "maintenance_plan_metadata":{"entity_type":"maintenance_plan_metadata","key_data":{"plan_id":"plan-1"},"record_id":"plan-1"},
    "maintenance_records":{"entity_type":"maintenance_record","key_data":{"id":"record-1"},"record_id":"record-1"},
    "notification_inbox":{"entity_type":"notification_inbox","key_data":{"id":"inbox-1"},"record_id":"inbox-1"},
    "user_settings":{"entity_type":"user_setting","key_data":{"key":"theme"},"record_id":"theme"},
    "streaks":{"entity_type":"streak","key_data":{"id":"streak-1"},"record_id":"streak-1"}
  }'::jsonb,
  'server table mapping is exhaustive and uses the client canonical entity identifiers'
);

select extensions.throws_ok(
  $$ select owntend_private.sync_feed_identity('notifications', '{"id":"n-1"}'::jsonb) $$,
  '0A000',
  'Unsupported change-feed table notifications',
  'unknown server entity mapping fails closed'
);

insert into auth.users (id, email)
values ('00000000-0000-0000-0000-00000000002a', 'feed-contract@example.com');
truncate table public.server_change_feed restart identity;

insert into public.areas (
  user_id, id, name, kind, sort_order, created_at, updated_at, revision
) values (
  '00000000-0000-0000-0000-00000000002a',
  'area-contract',
  'Area Contract',
  'indoor',
  1,
  '2026-01-01T00:00:00Z',
  '2026-01-01T00:00:00Z',
  1
);

select extensions.is(
  (select entity_type from public.server_change_feed where record_id = 'area-contract'),
  'area'::text,
  'trigger emits canonical area entity identifier'
);

select extensions.is(
  (select key_data from public.server_change_feed where record_id = 'area-contract'),
  '{"id":"area-contract"}'::jsonb,
  'trigger persists typed key_data'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000002a"}';

select extensions.is(
  public.fetch_user_change_feed(0, 50)->'changes'->0->'key_data',
  '{"id":"area-contract"}'::jsonb,
  'authenticated feed page returns typed key_data'
);

select extensions.is(
  public.fetch_user_change_feed(0, 50)->>'capability_version',
  '1.0.0'::text,
  'feed page carries the same initial protocol version as capability discovery'
);

rollback;
