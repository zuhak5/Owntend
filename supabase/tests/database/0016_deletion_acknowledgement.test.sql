begin;

create extension if not exists pgtap with schema extensions;

select plan(28);

select has_column('owntend_private', 'account_deletion_operations', 'remote_boundary_at', 'remote boundary timestamp exists');
select has_column('owntend_private', 'account_deletion_operations', 'acknowledged_at', 'acknowledgement timestamp exists');
select hasnt_column('owntend_private', 'account_deletion_operations', 'capability_version', 'the v1 receipt has no compatibility-version column');
select ok(
  exists (
    select 1 from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'owntend_private'
      and t.relname = 'account_deletion_operations'
      and c.conname = 'account_deletion_operations_stage_check'
  ),
  'the deletion stage constraint includes acknowledged state'
);

select ok(has_function_privilege('service_role', 'public.acknowledge_owntend_account_deletion_operation(uuid,text)', 'EXECUTE'), 'service role can acknowledge a deletion receipt');
select ok(not has_function_privilege('authenticated', 'public.acknowledge_owntend_account_deletion_operation(uuid,text)', 'EXECUTE'), 'authenticated users cannot acknowledge receipts directly');
select ok(not has_function_privilege('anon', 'public.acknowledge_owntend_account_deletion_operation(uuid,text)', 'EXECUTE'), 'anonymous users cannot acknowledge receipts directly');

set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select is(
  public.begin_owntend_account_deletion_operation(repeat('f', 64), repeat('a', 64), 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') ->> 'stage',
  'prepared',
  'a deletion operation starts prepared'
);
select is(
  public.advance_owntend_account_deletion_operation(
    (select id from owntend_private.account_deletion_operations where request_hash = repeat('f', 64)),
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'auth_delete_started'
  ),
  'auth_delete_started',
  'the operation crosses the remote deletion boundary'
);
select ok(
  (select remote_boundary_at is not null from owntend_private.account_deletion_operations where request_hash = repeat('f', 64)),
  'the remote boundary timestamp is recorded'
);
select is(
  public.complete_owntend_account_deletion_operation(
    (select id from owntend_private.account_deletion_operations where request_hash = repeat('f', 64)),
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    repeat('a', 64)
  ) ->> 'stage',
  'completed',
  'the operation reaches completed state'
);
select is(public.prune_owntend_account_deletion_operations(), 0, 'a nonexpired completed receipt remains available');
select ok(exists (select 1 from owntend_private.account_deletion_operations where request_hash = repeat('f', 64)), 'the completed receipt remains until its expiry');

select is(
  public.begin_owntend_account_deletion_operation(repeat('b', 64), repeat('c', 64), 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') ->> 'stage',
  'prepared',
  'a second deletion operation starts prepared'
);
select throws_ok(
  $$select public.acknowledge_owntend_account_deletion_operation(
    (select id from owntend_private.account_deletion_operations where request_hash = repeat('b', 64)), repeat('c', 64)
  )$$,
  '55000',
  'DELETION_OPERATION_NOT_READY',
  'acknowledgement is rejected before remote completion'
);
select throws_ok(
  $$select public.acknowledge_owntend_account_deletion_operation(
    (select id from owntend_private.account_deletion_operations where request_hash = repeat('f', 64)), repeat('e', 64)
  )$$,
  '42501',
  'DELETION_OPERATION_BINDING_MISMATCH',
  'a wrong subject binding is rejected'
);
select is(
  public.acknowledge_owntend_account_deletion_operation(
    (select id from owntend_private.account_deletion_operations where request_hash = repeat('f', 64)), repeat('a', 64)
  ) ->> 'stage',
  'acknowledged',
  'a valid acknowledgement transitions state'
);
select ok((select acknowledged_at is not null from owntend_private.account_deletion_operations where request_hash = repeat('f', 64)), 'the acknowledgement timestamp is recorded');
select ok((select remote_boundary_at is not null from owntend_private.account_deletion_operations where request_hash = repeat('f', 64)), 'acknowledgement preserves the remote boundary timestamp');
select is(
  public.acknowledge_owntend_account_deletion_operation(
    (select id from owntend_private.account_deletion_operations where request_hash = repeat('f', 64)), repeat('a', 64)
  ) ->> 'stage',
  'acknowledged',
  'acknowledgement is idempotent'
);

update owntend_private.account_deletion_operations
set expires_at = clock_timestamp() - interval '1 second'
where request_hash = repeat('f', 64);

select is(public.prune_owntend_account_deletion_operations(), 1, 'an acknowledged receipt is pruned after expiry');
select ok(not exists (select 1 from owntend_private.account_deletion_operations where request_hash = repeat('f', 64)), 'the expired acknowledged receipt is removed');

insert into owntend_private.account_deletion_operations (request_hash, subject_binding, active_user_id, expires_at)
values (repeat('d', 64), repeat('e', 64), 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', clock_timestamp() - interval '1 minute');

select is(public.prune_owntend_account_deletion_operations(), 1, 'an expired pre-completion operation is also pruned');
select throws_ok(
  $$select public.acknowledge_owntend_account_deletion_operation(null, repeat('a', 64))$$,
  '22023',
  'INVALID_DELETION_ACKNOWLEDGEMENT',
  'a null operation identifier is rejected'
);
select throws_ok(
  $$select public.acknowledge_owntend_account_deletion_operation('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'not-64-hex-chars')$$,
  '22023',
  'INVALID_DELETION_ACKNOWLEDGEMENT',
  'a malformed subject binding is rejected'
);

select is(
  public.advance_owntend_account_deletion_operation(
    (select id from owntend_private.account_deletion_operations where request_hash = repeat('b', 64)),
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'auth_delete_started'
  ),
  'auth_delete_started',
  'the second operation reaches the remote boundary'
);
select ok(
  public.complete_owntend_account_deletion_operation(
    (select id from owntend_private.account_deletion_operations where request_hash = repeat('b', 64)),
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    repeat('c', 64)
  ) ->> 'remote_boundary_at' is not null,
  'the completion receipt includes the remote boundary timestamp'
);
select is(
  (public.complete_owntend_account_deletion_operation(
    (select id from owntend_private.account_deletion_operations where request_hash = repeat('b', 64)),
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    repeat('c', 64)
  ) -> 'acknowledged')::text,
  'false',
  'a completed receipt is not acknowledged implicitly'
);

reset role;

select * from finish();
rollback;
