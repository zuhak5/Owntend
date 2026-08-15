begin;

create extension if not exists pgtap with schema extensions;

select plan(19);

select has_table(
  'owntend_private',
  'account_deletion_operations',
  'durable deletion operations are private'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'owntend_private.account_deletion_operations',
    'SELECT'
  ),
  'authenticated users cannot inspect deletion recovery operations'
);
select ok(
  has_table_privilege(
    'service_role',
    'owntend_private.account_deletion_operations',
    'SELECT'
  ),
  'service role can inspect deletion recovery operations'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.begin_owntend_account_deletion_operation(text,text,uuid)',
    'EXECUTE'
  ),
  'authenticated users cannot create recovery operations directly'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.begin_owntend_account_deletion_operation(text,text,uuid)',
    'EXECUTE'
  ),
  'service role can create recovery operations'
);
select ok(
  not exists (
    select 1
    from pg_constraint
    where conrelid =
      'owntend_private.account_deletion_operations'::regclass
      and confrelid = 'auth.users'::regclass
  ),
  'recovery receipts are not cascaded with the deleted Auth user'
);
select lives_ok(
  $test$
  do $block$
  declare
    schedule_exists boolean;
  begin
    if to_regclass('cron.job') is not null then
      execute 'select exists (
        select 1 from cron.job
        where jobname = ''owntend-account-deletion-operation-prune''
      )' into schedule_exists;
      if not schedule_exists then
        raise exception 'account deletion prune schedule is missing';
      end if;
    end if;
  end
  $block$
  $test$,
  'expired recovery receipts are scheduled when pg_cron is available'
);

set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';

select is(
  (
    public.begin_owntend_account_deletion_operation(
      repeat('a', 64),
      repeat('b', 64),
      '77777777-7777-4777-8777-777777777777'
    ) ->> 'stage'
  ),
  'prepared',
  'a recovery operation starts prepared'
);
select is(
  (
    public.begin_owntend_account_deletion_operation(
      repeat('a', 64),
      repeat('b', 64),
      '77777777-7777-4777-8777-777777777777'
    ) ->> 'stage'
  ),
  'prepared',
  'begin is idempotent for the same binding'
);
select throws_ok(
  $$select public.begin_owntend_account_deletion_operation(
    repeat('a', 64),
    repeat('c', 64),
    '88888888-8888-4888-8888-888888888888'
  )$$,
  '42501',
  'DELETION_OPERATION_BINDING_MISMATCH',
  'a recovery key cannot be rebound to another subject'
);

select is(
  public.advance_owntend_account_deletion_operation(
    (
      select id from owntend_private.account_deletion_operations
      where request_hash = repeat('a', 64)
    ),
    '77777777-7777-4777-8777-777777777777',
    'storage_complete'
  ),
  'storage_complete',
  'operation advances monotonically'
);
select is(
  public.advance_owntend_account_deletion_operation(
    (
      select id from owntend_private.account_deletion_operations
      where request_hash = repeat('a', 64)
    ),
    '77777777-7777-4777-8777-777777777777',
    'storage_cleanup'
  ),
  'storage_complete',
  'an older retry cannot regress the operation stage'
);
select throws_ok(
  $$select public.complete_owntend_account_deletion_operation(
    (select id from owntend_private.account_deletion_operations
      where request_hash = repeat('a', 64)),
    '77777777-7777-4777-8777-777777777777',
    repeat('b', 64)
  )$$,
  '55000',
  'DELETION_OPERATION_NOT_READY',
  'completion is rejected before the Auth deletion boundary'
);

select is(
  public.advance_owntend_account_deletion_operation(
    (
      select id from owntend_private.account_deletion_operations
      where request_hash = repeat('a', 64)
    ),
    '77777777-7777-4777-8777-777777777777',
    'auth_delete_started'
  ),
  'auth_delete_started',
  'operation records the Auth deletion boundary durably'
);
select is(
  (
    public.complete_owntend_account_deletion_operation(
      (
        select id from owntend_private.account_deletion_operations
        where request_hash = repeat('a', 64)
      ),
      '77777777-7777-4777-8777-777777777777',
      repeat('b', 64)
    ) ->> 'completed'
  )::boolean,
  true,
  'operation completion is durable'
);
select is(
  (
    select active_user_id
    from owntend_private.account_deletion_operations
    where request_hash = repeat('a', 64)
  ),
  null::uuid,
  'completed receipt clears the raw user identifier'
);
select is(
  (
    public.lookup_owntend_account_deletion_operation(
      repeat('a', 64), repeat('b', 64)
    ) ->> 'completed'
  )::boolean,
  true,
  'the capability lookup recovers a completed receipt'
);
select is(
  public.lookup_owntend_account_deletion_operation(
    repeat('a', 64), repeat('c', 64)
  ),
  null::jsonb,
  'a mismatched subject binding reveals no operation'
);

insert into owntend_private.account_deletion_operations (
  request_hash,
  subject_binding,
  active_user_id,
  expires_at
) values (
  repeat('d', 64),
  repeat('e', 64),
  '99999999-9999-4999-8999-999999999999',
  clock_timestamp() - interval '1 minute'
);
select is(
  public.prune_owntend_account_deletion_operations(),
  1,
  'expired operations are removed'
);

reset role;

select * from finish();
rollback;
