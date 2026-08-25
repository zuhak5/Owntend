begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(22);

select extensions.has_function('public', 'prepare_asset_photo_upload', ARRAY['text', 'text', 'bigint', 'text', 'text', 'text'], 'prepare-first media RPC exists');
select extensions.has_function('public', 'finalize_asset_photo_upload', ARRAY['uuid', 'text', 'text', 'integer', 'text', 'boolean'], 'media finalization RPC exists');
select extensions.has_function('public', 'complete_owntend_account_cleanup', ARRAY['uuid', 'text'], 'account cleanup completion RPC exists');
select extensions.ok(not has_function_privilege('anon', 'public.prepare_asset_photo_upload(text,text,bigint,text,text,text)', 'execute'), 'anonymous callers cannot prepare uploads');
select extensions.ok(has_function_privilege('authenticated', 'public.prepare_asset_photo_upload(text,text,bigint,text,text,text)', 'execute'), 'authenticated callers can prepare uploads');
select extensions.ok(has_function_privilege('service_role', 'public.complete_owntend_account_cleanup(uuid,text)', 'execute'), 'service role can complete cleanup jobs');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'usera@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'userb@example.com');

set local role anon;
select extensions.throws_ok(
  $$select public.prepare_asset_photo_upload('asset-a', 'photo-a', 1024, 'image/jpeg', repeat('a', 64), 'prepare-upload-0001')$$,
  '42501',
  'permission denied for function prepare_asset_photo_upload',
  'function ACLs reject unauthenticated preparation'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000a"}';

select extensions.throws_ok(
  $$select public.prepare_asset_photo_upload('missing-asset', 'photo-a', 1024, 'image/jpeg', repeat('a', 64), 'prepare-upload-0001')$$,
  'P0002',
  'ASSET_NOT_FOUND',
  'preparation requires an owned asset'
);

set local role postgres;
insert into public.areas (user_id, id, name, sort_order)
values ('00000000-0000-0000-0000-00000000000a', 'area-a', 'Area A', 1);
insert into public.rooms (user_id, id, area_id, name, sort_order)
values ('00000000-0000-0000-0000-00000000000a', 'room-a', 'area-a', 'Room A', 1);
insert into public.assets (user_id, id, room_id, name, asset_type)
values ('00000000-0000-0000-0000-00000000000a', 'asset-a', 'room-a', 'Asset A', 'general');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000a"}';

select extensions.throws_ok(
  $$select public.prepare_asset_photo_upload('asset-a', 'photo-a', 10485761, 'image/jpeg', repeat('a', 64), 'prepare-upload-0001')$$,
  '22023',
  'INVALID_MEDIA_STAGE',
  'preparation rejects objects over 10 MiB'
);
select extensions.throws_ok(
  $$select public.prepare_asset_photo_upload('asset-a', 'photo-a', 1024, 'application/pdf', repeat('a', 64), 'prepare-upload-0001')$$,
  '22023',
  'INVALID_MEDIA_STAGE',
  'preparation rejects unsupported media types'
);
select extensions.throws_ok(
  $$select public.prepare_asset_photo_upload('asset-a', 'photo-a', 1024, 'image/jpeg', 'not-a-digest', 'prepare-upload-0001')$$,
  '22023',
  'INVALID_MEDIA_STAGE',
  'preparation rejects malformed advisory digests'
);
select extensions.lives_ok(
  $$select public.prepare_asset_photo_upload('asset-a', 'photo-a', 1024, 'image/jpeg', repeat('a', 64), 'prepare-upload-0001')$$,
  'valid upload preparation succeeds before object upload'
);
select extensions.ok(
  (select staging_path like '00000000-0000-0000-0000-00000000000a/media/photo-a.jpg'
   from public.media_staging_objects where idempotency_key = 'prepare-upload-0001'),
  'the server issues an immutable owner-scoped staging path'
);
select extensions.is(
  public.prepare_asset_photo_upload('asset-a', 'photo-a', 1024, 'image/jpeg', repeat('a', 64), 'prepare-upload-0001') ->> 'digest_verification',
  'client_advisory',
  'the API labels the client digest as advisory'
);
select extensions.is(
  (select count(*)::integer from storage.objects o
   join public.media_staging_objects s on s.staging_path = o.name
   where s.idempotency_key = 'prepare-upload-0001'),
  0,
  'a database stage exists before its Storage object is uploaded'
);
select extensions.is(
  public.prepare_asset_photo_upload('asset-a', 'photo-a', 1024, 'image/jpeg', repeat('a', 64), 'prepare-upload-0001') ->> 'staging_id',
  (select id::text from public.media_staging_objects where idempotency_key = 'prepare-upload-0001'),
  'an exact preparation retry returns the same stage'
);
select extensions.throws_ok(
  $$select public.prepare_asset_photo_upload('asset-a', 'photo-a', 2048, 'image/jpeg', repeat('a', 64), 'prepare-upload-0001')$$,
  '23505',
  'MEDIA_IDEMPOTENCY_CONFLICT',
  'an altered idempotency replay fails closed'
);

set local role postgres;
insert into storage.objects (bucket_id, name, owner, metadata)
select 'user-media', staging_path, user_id,
       '{"size":"1024","mimetype":"image/jpeg"}'::jsonb
from public.media_staging_objects
where idempotency_key = 'prepare-upload-0001';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000a"}';

select extensions.is(
  public.finalize_asset_photo_upload(
    (select id from public.media_staging_objects where idempotency_key = 'prepare-upload-0001'),
    'asset-a',
    'photo-a',
    1
  ) ->> 'digest_verification',
  'client_advisory',
  'finalization verifies trusted object facts without claiming a server digest'
);
select extensions.is(
  (select status from public.media_staging_objects where idempotency_key = 'prepare-upload-0001'),
  'finalized',
  'finalization records terminal stage state'
);
select extensions.is(
  (select count(*)::integer from public.asset_photos where id = 'photo-a' and asset_id = 'asset-a'),
  1,
  'finalization creates the asset photo row'
);
select extensions.is(
  public.finalize_asset_photo_upload(
    (select id from public.media_staging_objects where idempotency_key = 'prepare-upload-0001'),
    'asset-a',
    'photo-a',
    1
  ) ->> 'idempotent',
  'true',
  'finalization is idempotent'
);

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
select extensions.throws_ok(
  $$select public.finalize_asset_photo_upload(
    (select id from public.media_staging_objects where idempotency_key = 'prepare-upload-0001'),
    'asset-a',
    'photo-a',
    1
  )$$,
  'P0002',
  'MEDIA_STAGE_NOT_FOUND',
  'another user cannot finalize the stage'
);

rollback;
