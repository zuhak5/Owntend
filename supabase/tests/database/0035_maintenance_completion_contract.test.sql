begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(9);

select extensions.has_function(
  'owntend_private',
  'maintenance_completion_result',
  array['text', 'boolean', 'text', 'bigint', 'text', 'timestamp with time zone', 'jsonb', 'jsonb'],
  'maintenance completion responses use one private envelope builder'
);

select extensions.ok(
  not (
    select procedures.prosecdef
    from pg_proc as procedures
    join pg_namespace as namespaces on namespaces.oid = procedures.pronamespace
    where namespaces.nspname = 'owntend_private'
      and procedures.proname = 'maintenance_completion_result'
  ),
  'the response builder is security invoker'
);

select extensions.ok(
  not has_function_privilege(
    'anon',
    'owntend_private.maintenance_completion_result(text,boolean,text,bigint,text,timestamptz,jsonb,jsonb)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'owntend_private.maintenance_completion_result(text,boolean,text,bigint,text,timestamptz,jsonb,jsonb)',
    'execute'
  ),
  'Data API roles cannot execute the private response builder'
);

select extensions.results_eq(
  $$
    with statuses(status, retryable, reason) as (
      values
        ('applied'::text, false, null::text),
        ('already_applied', false, null),
        ('conflict', false, 'stale_occurrence'),
        ('invalid', false, 'invalid_payload_version')
    )
    select status, array_agg(key order by key)::text[]
    from statuses
    cross join lateral jsonb_object_keys(
      owntend_private.maintenance_completion_result(status, retryable, reason)
    ) as key
    group by status
    order by status
  $$,
  $$
    select status, array[
      'conflict_reason', 'contract_version', 'current_plan_revision',
      'plan', 'record', 'resulting_next_due_date', 'resulting_record_id',
      'retryable', 'reward_eligibility_token', 'status'
    ]::text[]
    from (values
      ('already_applied'::text), ('applied'), ('conflict'), ('invalid')
    ) as expected(status)
    order by status
  $$,
  'every completion status has the exact fixed envelope'
);

select extensions.results_eq(
  $$
    select distinct
      (owntend_private.maintenance_completion_result(status, false)->>'contract_version')::integer
    from (values ('applied'::text), ('already_applied'), ('conflict'), ('invalid')) as statuses(status)
  $$,
  $$ values (1) $$,
  'every envelope declares contract version one'
);

select extensions.ok(
  (
    with response as (
      select owntend_private.maintenance_completion_result(
        'conflict',
        false,
        'stale_occurrence',
        7,
        '00000000-0000-0000-0000-000000000352',
        '2026-08-29T00:00:00Z'::timestamptz,
        '{"id":"00000000-0000-0000-0000-000000000353"}'::jsonb,
        '{"id":"00000000-0000-0000-0000-000000000352"}'::jsonb
      ) as value
    )
    select jsonb_typeof(value->'contract_version') = 'number'
      and jsonb_typeof(value->'status') = 'string'
      and jsonb_typeof(value->'retryable') = 'boolean'
      and jsonb_typeof(value->'conflict_reason') = 'string'
      and jsonb_typeof(value->'current_plan_revision') = 'number'
      and jsonb_typeof(value->'resulting_record_id') = 'string'
      and jsonb_typeof(value->'resulting_next_due_date') = 'string'
      and jsonb_typeof(value->'plan') = 'object'
      and jsonb_typeof(value->'record') = 'object'
    from response
  ),
  'the fixed envelope preserves the declared JSON types'
);

select extensions.is(
  (
    select count(*)::integer
    from jsonb_each(
      owntend_private.maintenance_completion_result(
        'invalid', false, 'invalid_payload_version'
      )
    ) as fields
    where fields.value = 'null'::jsonb
  ),
  6,
  'invalid responses retain all six nullable canonical fields'
);

select extensions.ok(
  position(
    'owntend_private.maintenance_completion_result' in
    pg_get_functiondef(
      'owntend_private.complete_maintenance_task_impl(jsonb,text)'::regprocedure
    )
  ) > 0
  and position(
    'jsonb_build_object' in
    pg_get_functiondef(
      'owntend_private.complete_maintenance_task_impl(jsonb,text)'::regprocedure
    )
  ) = 0,
  'the completion implementation cannot build ad-hoc envelopes'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000351', true);
set local role authenticated;

select extensions.results_eq(
  $$
    select array_agg(key order by key)::text[]
    from jsonb_object_keys(
      public.complete_maintenance_task('{}'::jsonb, 'contract-device')
    ) as key
  $$,
  $$
    values (array[
      'conflict_reason', 'contract_version', 'current_plan_revision',
      'plan', 'record', 'resulting_next_due_date', 'resulting_record_id',
      'retryable', 'reward_eligibility_token', 'status'
    ]::text[])
  $$,
  'the authenticated public RPC returns the fixed envelope for invalid input'
);

select * from extensions.finish();
rollback;
