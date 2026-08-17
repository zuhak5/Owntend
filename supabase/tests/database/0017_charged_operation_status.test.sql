begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(26);

select extensions.has_function(
  'public',
  'get_charged_operation_status',
  ARRAY['uuid', 'text'],
  'get_charged_operation_status RPC exists'
);

select extensions.ok(
  not (select has_function_privilege('anon', 'public.get_charged_operation_status(uuid, text)', 'execute')),
  'anon role cannot execute get_charged_operation_status'
);

select extensions.ok(
  (select has_function_privilege('authenticated', 'public.get_charged_operation_status(uuid, text)', 'execute')),
  'authenticated role can execute get_charged_operation_status'
);

select extensions.is(
  (
    select pronargdefaults::integer
    from pg_proc
    where oid = 'public.get_charged_operation_status(uuid, text)'::regprocedure
  ),
  0,
  'status RPC has no default that permits operation-id-only reconciliation'
);

prepare create_user_a as insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000a', 'usera@example.com');
prepare create_user_b as insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000b', 'userb@example.com');
execute create_user_a;
execute create_user_b;

update public.point_wallets
set balance = 10
where user_id in (
  '00000000-0000-0000-0000-00000000000a',
  '00000000-0000-0000-0000-00000000000b'
);

insert into public.rooms (user_id, id, name, sort_order)
values ('00000000-0000-0000-0000-00000000000a', 'room-main', 'Main Room', 1);

set local role anon;
select extensions.throws_ok(
  $$ select public.get_charged_operation_status(
    '11111111-1111-1111-1111-111111111111'::uuid,
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
  ) $$,
  '42501',
  'permission denied for function get_charged_operation_status',
  'unauthenticated status lookup is rejected by function ACLs'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

select extensions.is(
  (select public.get_charged_operation_status(
    '11111111-1111-1111-1111-111111111111'::uuid,
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
  )->>'status'),
  'not_found',
  'non-existent operation returns status not_found'
);

select extensions.is(
  (select public.get_charged_operation_status(
    '11111111-1111-1111-1111-111111111111'::uuid,
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
  )->>'capability_version'),
  '1.2.0',
  'hash-qualified capability version is returned'
);

select extensions.is(
  (
    select public.create_asset_with_point_debit(jsonb_build_object(
      'operation_id', 'a1111111-1111-1111-1111-111111111111',
      'request_hash', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'asset', jsonb_build_object(
        'id', 'asset-a1',
        'room_id', 'room-main',
        'category_id', 'category_general',
        'name', 'Test Asset A',
        'asset_type', 'general'
      )
    ))->>'already_processed'
  ),
  'false',
  'initial asset creation succeeds with already_processed = false'
);

set local role postgres;
select extensions.is(
  (select client_request_hash from public.creation_point_operations where operation_id = 'a1111111-1111-1111-1111-111111111111'),
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'asset operation persists the immutable client request hash'
);
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

select extensions.is(
  (select balance from public.point_wallets where user_id = '00000000-0000-0000-0000-00000000000a'),
  10,
  'user A wallet balance remains 10 because asset creation is free'
);

select extensions.is(
  (
    select public.create_asset_with_point_debit(jsonb_build_object(
      'operation_id', 'a1111111-1111-1111-1111-111111111111',
      'request_hash', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'asset', jsonb_build_object(
        'id', 'asset-a1',
        'room_id', 'room-main',
        'category_id', 'category_general',
        'name', 'Test Asset A',
        'asset_type', 'general'
      )
    ))->>'already_processed'
  ),
  'true',
  'exact asset replay returns already_processed = true'
);

select extensions.is(
  (select balance from public.point_wallets where user_id = '00000000-0000-0000-0000-00000000000a'),
  10,
  'asset replay does not deduct points'
);

select extensions.throws_ok(
  $$
    select public.create_asset_with_point_debit(jsonb_build_object(
      'operation_id', 'a1111111-1111-1111-1111-111111111111',
      'request_hash', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'asset', jsonb_build_object(
        'id', 'asset-a1-altered',
        'room_id', 'room-main',
        'category_id', 'category_general',
        'name', 'Altered Asset Name',
        'asset_type', 'general'
      )
    ))
  $$,
  '23505',
  'OPERATION_ID_REUSED',
  'server payload digest still rejects altered replay with the same client hash'
);

select extensions.is(
  (select public.get_charged_operation_status(
    'a1111111-1111-1111-1111-111111111111'::uuid,
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  )->>'status'),
  'completed',
  'hash-qualified asset status returns completed'
);

select extensions.is(
  (select public.get_charged_operation_status(
    'a1111111-1111-1111-1111-111111111111'::uuid,
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  )->>'entity_id'),
  'asset-a1',
  'asset status returns the exact committed entity'
);

select extensions.throws_ok(
  $$ select public.get_charged_operation_status(
    'a1111111-1111-1111-1111-111111111111'::uuid,
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
  ) $$,
  '23505',
  'OPERATION_ID_REUSED',
  'same operation id with a different client hash is a hard conflict'
);

select extensions.is(
  (
    select public.create_task_with_point_debit(jsonb_build_object(
      'operation_id', '21111111-1111-1111-1111-111111111111',
      'request_hash', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      'plan', jsonb_build_object(
        'id', 'plan-t1',
        'asset_id', 'asset-a1',
        'title', 'Test Maintenance Task',
        'recurrence_interval', 1,
        'recurrence_unit', 'months',
        'priority', 'medium',
        'next_due_date', '2026-09-01T00:00:00Z'
      )
    ))->>'already_processed'
  ),
  'false',
  'task creation succeeds with already_processed = false'
);

set local role postgres;
select extensions.is(
  (select client_request_hash from public.creation_point_operations where operation_id = '21111111-1111-1111-1111-111111111111'),
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  'task operation persists the immutable client request hash'
);
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

select extensions.is(
  (select balance from public.point_wallets where user_id = '00000000-0000-0000-0000-00000000000a'),
  9,
  'initial task creation charges exactly one point'
);

select extensions.is(
  (
    select public.create_task_with_point_debit(jsonb_build_object(
      'operation_id', '21111111-1111-1111-1111-111111111111',
      'request_hash', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      'plan', jsonb_build_object(
        'id', 'plan-t1',
        'asset_id', 'asset-a1',
        'title', 'Test Maintenance Task',
        'recurrence_interval', 1,
        'recurrence_unit', 'months',
        'priority', 'medium',
        'next_due_date', '2026-09-01T00:00:00Z'
      )
    ))->>'already_processed'
  ),
  'true',
  'same operation id and hash replay returns the committed result'
);

select extensions.is(
  (select balance from public.point_wallets where user_id = '00000000-0000-0000-0000-00000000000a'),
  9,
  'replaying the logical charged operation does not charge twice'
);

select extensions.is(
  (select public.get_charged_operation_status(
    '21111111-1111-1111-1111-111111111111'::uuid,
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  )->>'status'),
  'completed',
  'hash-qualified task status returns completed'
);

select extensions.is(
  (select public.get_charged_operation_status(
    '21111111-1111-1111-1111-111111111111'::uuid,
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  )->>'entity_type'),
  'task',
  'task status returns entity_type task'
);

select extensions.ok(
  (select (public.get_charged_operation_status(
    '21111111-1111-1111-1111-111111111111'::uuid,
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  )->'plan'->>'title')) = 'Test Maintenance Task',
  'task status returns the exact canonical plan object'
);

set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000b"}';

select extensions.is(
  (select public.get_charged_operation_status(
    'a1111111-1111-1111-1111-111111111111'::uuid,
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  )->>'status'),
  'not_found',
  'cross-user asset lookup returns not_found without disclosure'
);

select extensions.is(
  (select public.get_charged_operation_status(
    '21111111-1111-1111-1111-111111111111'::uuid,
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  )->>'status'),
  'not_found',
  'cross-user task lookup returns not_found without disclosure'
);

select extensions.finish();
rollback;
