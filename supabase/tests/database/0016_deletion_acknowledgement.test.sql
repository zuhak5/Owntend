begin;

create extension if not exists pgtap with schema extensions;

select plan(31);

-- ──────────────────────────────────────────────────────────────────────
-- 1. Schema: new columns and stage are present
-- ──────────────────────────────────────────────────────────────────────

select has_column(
  'owntend_private',
  'account_deletion_operations',
  'remote_boundary_at',
  'remote_boundary_at column exists'
);
select has_column(
  'owntend_private',
  'account_deletion_operations',
  'acknowledged_at',
  'acknowledged_at column exists'
);
select has_column(
  'owntend_private',
  'account_deletion_operations',
  'capability_version',
  'capability_version column exists'
);

-- 'acknowledged' stage is accepted by the constraint
select ok(
  (
    select exists (
      select 1
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
      where n.nspname = 'owntend_private'
        and t.relname = 'account_deletion_operations'
        and c.conname = 'account_deletion_operations_stage_check'
    )
  ),
  'stage check constraint still exists with acknowledged stage'
);

-- ──────────────────────────────────────────────────────────────────────
-- 2. Privilege checks
-- ──────────────────────────────────────────────────────────────────────

select ok(
  has_function_privilege(
    'service_role',
    'public.acknowledge_owntend_account_deletion_operation(uuid,text,text)',
    'EXECUTE'
  ),
  'service role can call acknowledge'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.acknowledge_owntend_account_deletion_operation(uuid,text,text)',
    'EXECUTE'
  ),
  'authenticated users cannot call acknowledge directly'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.acknowledge_owntend_account_deletion_operation(uuid,text,text)',
    'EXECUTE'
  ),
  'anonymous users cannot call acknowledge directly'
);

-- ──────────────────────────────────────────────────────────────────────
-- 3. Behavioural tests
-- ──────────────────────────────────────────────────────────────────────

set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

-- 3a. Set up a fresh operation and drive it to completed.

select is(
  (
    public.begin_owntend_account_deletion_operation(
      repeat('f', 64),
      repeat('a', 64),
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    ) ->> 'stage'
  ),
  'prepared',
  'acknowledgement-test operation starts prepared'
);

select is(
  public.advance_owntend_account_deletion_operation(
    (select id from owntend_private.account_deletion_operations
      where request_hash = repeat('f', 64)),
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'auth_delete_started'
  ),
  'auth_delete_started',
  'advance to auth_delete_started succeeds'
);

-- remote_boundary_at is set when crossing auth_delete_started
select ok(
  (
    select remote_boundary_at is not null
    from owntend_private.account_deletion_operations
    where request_hash = repeat('f', 64)
  ),
  'remote_boundary_at is recorded when auth_delete_started is reached'
);

select is(
  (
    public.complete_owntend_account_deletion_operation(
      (select id from owntend_private.account_deletion_operations
        where request_hash = repeat('f', 64)),
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      repeat('a', 64)
    ) ->> 'stage'
  ),
  'completed',
  'operation reaches completed stage'
);

-- 3b. Prune must NOT remove a completed-but-unacknowledged row
--     even when its expires_at is in the past.

update owntend_private.account_deletion_operations
  set expires_at = clock_timestamp() - interval '1 minute'
  where request_hash = repeat('f', 64);

select is(
  public.prune_owntend_account_deletion_operations(),
  0,
  'prune does not remove a completed-but-unacknowledged row'
);

select ok(
  exists (
    select 1
    from owntend_private.account_deletion_operations
    where request_hash = repeat('f', 64)
  ),
  'completed-unacknowledged row survives prune'
);

-- 3c. Acknowledgement is rejected before completion

select is(
  (
    public.begin_owntend_account_deletion_operation(
      repeat('b', 64),
      repeat('c', 64),
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    ) ->> 'stage'
  ),
  'prepared',
  'second test operation starts prepared'
);

select throws_ok(
  $$select public.acknowledge_owntend_account_deletion_operation(
    (select id from owntend_private.account_deletion_operations
      where request_hash = repeat('b', 64)),
    repeat('c', 64),
    '1.0.0'
  )$$,
  '55000',
  'DELETION_OPERATION_NOT_READY',
  'acknowledgement is rejected before remote completion'
);

-- 3d. Acknowledgement with wrong subject binding is rejected

select throws_ok(
  $$select public.acknowledge_owntend_account_deletion_operation(
    (select id from owntend_private.account_deletion_operations
      where request_hash = repeat('f', 64)),
    repeat('e', 64),
    '1.0.0'
  )$$,
  '42501',
  'DELETION_OPERATION_BINDING_MISMATCH',
  'acknowledgement with wrong subject binding is rejected'
);

-- 3e. Valid acknowledgement succeeds and transitions to acknowledged

select is(
  (
    public.acknowledge_owntend_account_deletion_operation(
      (select id from owntend_private.account_deletion_operations
        where request_hash = repeat('f', 64)),
      repeat('a', 64),
      '1.0.0'
    ) ->> 'stage'
  ),
  'acknowledged',
  'valid acknowledgement transitions to acknowledged stage'
);
select ok(
  (
    select acknowledged_at is not null
    from owntend_private.account_deletion_operations
    where request_hash = repeat('f', 64)
  ),
  'acknowledged_at is recorded'
);
select is(
  (
    select capability_version
    from owntend_private.account_deletion_operations
    where request_hash = repeat('f', 64)
  ),
  '1.0.0',
  'capability_version is stored'
);
select ok(
  (
    select remote_boundary_at is not null
    from owntend_private.account_deletion_operations
    where request_hash = repeat('f', 64)
  ),
  'remote_boundary_at is preserved after acknowledgement'
);

-- 3f. Acknowledgement is idempotent: a second call returns current state

select is(
  (
    public.acknowledge_owntend_account_deletion_operation(
      (select id from owntend_private.account_deletion_operations
        where request_hash = repeat('f', 64)),
      repeat('a', 64),
      '1.0.1'   -- different version supplied; original must be preserved
    ) ->> 'stage'
  ),
  'acknowledged',
  'repeated acknowledgement is idempotent'
);
select is(
  (
    select capability_version
    from owntend_private.account_deletion_operations
    where request_hash = repeat('f', 64)
  ),
  '1.0.0',
  'repeated acknowledgement does not overwrite capability_version'
);

-- 3g. Acknowledged rows ARE pruned after their expires_at passes

update owntend_private.account_deletion_operations
  set expires_at = clock_timestamp() - interval '1 second'
  where request_hash = repeat('f', 64);

select is(
  public.prune_owntend_account_deletion_operations(),
  1,
  'acknowledged rows past expires_at are pruned'
);
select ok(
  not exists (
    select 1
    from owntend_private.account_deletion_operations
    where request_hash = repeat('f', 64)
  ),
  'acknowledged row has been removed by prune'
);

-- 3h. Non-completion rows are still pruned when expired

insert into owntend_private.account_deletion_operations (
  request_hash,
  subject_binding,
  active_user_id,
  expires_at
) values (
  repeat('d', 64),
  repeat('e', 64),
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  clock_timestamp() - interval '1 minute'
);

select is(
  public.prune_owntend_account_deletion_operations(),
  1,
  'expired non-completion rows are still pruned'
);

-- 3i. Invalid inputs are rejected

select throws_ok(
  $$select public.acknowledge_owntend_account_deletion_operation(
    null,
    repeat('a', 64),
    '1.0.0'
  )$$,
  '22023',
  'INVALID_DELETION_ACKNOWLEDGEMENT',
  'null operation_id is rejected'
);

select throws_ok(
  $$select public.acknowledge_owntend_account_deletion_operation(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'not-64-hex-chars',
    '1.0.0'
  )$$,
  '22023',
  'INVALID_DELETION_ACKNOWLEDGEMENT',
  'malformed subject_binding is rejected'
);

select throws_ok(
  $$select public.acknowledge_owntend_account_deletion_operation(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    repeat('a', 64),
    ''
  )$$,
  '22023',
  'INVALID_DELETION_ACKNOWLEDGEMENT',
  'empty capability_version is rejected'
);

-- 3j. complete() response now includes remote_boundary_at and acknowledged fields
--     Drive the second test operation to completed and verify response shape.

select is(
  public.advance_owntend_account_deletion_operation(
    (select id from owntend_private.account_deletion_operations
      where request_hash = repeat('b', 64)),
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'auth_delete_started'
  ),
  'auth_delete_started',
  'second test op reaches auth_delete_started'
);

select ok(
  (
    public.complete_owntend_account_deletion_operation(
      (select id from owntend_private.account_deletion_operations
        where request_hash = repeat('b', 64)),
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      repeat('c', 64)
    ) ->> 'remote_boundary_at'
  ) is not null,
  'complete() response includes remote_boundary_at'
);

select ok(
  (
    (
      public.complete_owntend_account_deletion_operation(
        (select id from owntend_private.account_deletion_operations
          where request_hash = repeat('b', 64)),
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        repeat('c', 64)
      ) -> 'acknowledged'
    )::boolean
  ) = false,
  'complete() response shows acknowledged=false for unacknowledged completion'
);

reset role;

select * from finish();
rollback;
