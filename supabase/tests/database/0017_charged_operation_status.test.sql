begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(20);

-- 1. Check RPC function existence and grants
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

-- Setup test users and data
prepare create_user_a as insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000a', 'usera@example.com');
prepare create_user_b as insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000b', 'userb@example.com');
execute create_user_a;
execute create_user_b;

-- Replace the automatic seven-point grants with deterministic test balances.
update public.point_wallets
set balance = 10
where user_id in (
  '00000000-0000-0000-0000-00000000000a',
  '00000000-0000-0000-0000-00000000000b'
);

-- Create room for User A
insert into public.rooms (user_id, id, name, sort_order)
values ('00000000-0000-0000-0000-00000000000a', 'room-main', 'Main Room', 1);

-- 2. Test unauthenticated call fails
set local role anon;
select extensions.throws_ok(
  $$ select public.get_charged_operation_status('11111111-1111-1111-1111-111111111111'::uuid) $$,
  '42501',
  'permission denied for function get_charged_operation_status',
  'unauthenticated status lookup is rejected by function ACLs'
);

-- Switch to User A
set local role authenticated;
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

-- 3. Lookup non-existent operation returns not_found with capability_version 1.1.0
select extensions.is(
  (select public.get_charged_operation_status('11111111-1111-1111-1111-111111111111'::uuid)->>'status'),
  'not_found',
  'non-existent operation returns status not_found'
);

select extensions.is(
  (select public.get_charged_operation_status('11111111-1111-1111-1111-111111111111'::uuid)->>'capability_version'),
  '1.1.0',
  'capability_version 1.1.0 returned'
);

-- 4. Create asset operation with User A
select extensions.is(
  (
    select public.create_asset_with_point_debit(jsonb_build_object(
      'operation_id', 'a1111111-1111-1111-1111-111111111111',
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

-- 5. User A wallet balance remains unchanged (10) since asset creation is free
select extensions.is(
  (select balance from public.point_wallets where user_id = '00000000-0000-0000-0000-00000000000a'),
  10,
  'user A wallet balance remains 10 (asset creation is free)'
);

-- 6. Exact replay of asset creation returns already_processed = true without deducting points
select extensions.is(
  (
    select public.create_asset_with_point_debit(jsonb_build_object(
      'operation_id', 'a1111111-1111-1111-1111-111111111111',
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
  'exact replay of asset creation returns already_processed = true'
);

select extensions.is(
  (select balance from public.point_wallets where user_id = '00000000-0000-0000-0000-00000000000a'),
  10,
  'user A wallet balance remains 10 after replay'
);

-- 7. Asset creation with same operation_id but altered payload throws OPERATION_ID_REUSED
select extensions.throws_ok(
  $$
    select public.create_asset_with_point_debit(jsonb_build_object(
      'operation_id', 'a1111111-1111-1111-1111-111111111111',
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
  'asset creation with same operation_id and altered payload throws OPERATION_ID_REUSED'
);

-- 8. Query status for completed asset operation
select extensions.is(
  (select public.get_charged_operation_status('a1111111-1111-1111-1111-111111111111'::uuid)->>'status'),
  'completed',
  'get_charged_operation_status returns completed for created asset'
);

select extensions.is(
  (select public.get_charged_operation_status('a1111111-1111-1111-1111-111111111111'::uuid)->>'entity_id'),
  'asset-a1',
  'status query returns correct asset entity_id'
);

-- 9. Create task operation with User A
select extensions.is(
  (
    select public.create_task_with_point_debit(jsonb_build_object(
        'operation_id', '21111111-1111-1111-1111-111111111111',
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

-- 10. Query status for completed task operation
select extensions.is(
  (select public.get_charged_operation_status('21111111-1111-1111-1111-111111111111'::uuid)->>'status'),
  'completed',
  'get_charged_operation_status returns completed for created task'
);

select extensions.is(
  (select public.get_charged_operation_status('21111111-1111-1111-1111-111111111111'::uuid)->>'entity_type'),
  'task',
  'status query returns entity_type task'
);

select extensions.ok(
  (select (public.get_charged_operation_status('21111111-1111-1111-1111-111111111111'::uuid)->'plan'->>'title')) = 'Test Maintenance Task',
  'status query returns canonical plan object'
);

-- 11. Cross-user lookup isolation: User B queries User A's operation_id
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000b"}';

select extensions.is(
  (select public.get_charged_operation_status('a1111111-1111-1111-1111-111111111111'::uuid)->>'status'),
  'not_found',
  'cross-user status query returns status not_found without disclosing asset'
);

select extensions.is(
  (select public.get_charged_operation_status('21111111-1111-1111-1111-111111111111'::uuid)->>'status'),
  'not_found',
  'cross-user status query returns status not_found without disclosing task'
);

-- 12. Query status with mismatched request hash throws OPERATION_ID_REUSED
set local "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

select extensions.throws_ok(
  $$ select public.get_charged_operation_status('a1111111-1111-1111-1111-111111111111'::uuid, 'mismatched_hash_12345') $$,
  '23505',
  'OPERATION_ID_REUSED',
  'status query with mismatched request hash throws OPERATION_ID_REUSED'
);

select extensions.finish();
rollback;
