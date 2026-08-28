begin;

create extension if not exists pgtap with schema extensions;

select plan(51);

select has_function(
  'public',
  'complete_maintenance_task',
  array['jsonb', 'text'],
  'maintenance completion RPC exists'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.complete_maintenance_task(jsonb,text)',
    'EXECUTE'
  ),
  'authenticated users can execute the released completion RPC'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.complete_maintenance_task(jsonb,text)',
    'EXECUTE'
  ),
  'anonymous users cannot execute the completion RPC'
);

select ok(
  not (
    select prosecdef
    from pg_proc
    where oid =
      'public.complete_maintenance_task(jsonb,text)'::regprocedure
  ),
  'RPC executes with invoker security'
);

select is(
  has_function_privilege(
    'anon',
    'public.complete_maintenance_task(jsonb,text)',
    'EXECUTE'
  ),
  false,
  'anon cannot execute the contained maintenance completion RPC'
);

select is(
  has_function_privilege(
    'authenticated',
    'public.complete_maintenance_task(jsonb,text)',
    'EXECUTE'
  ),
  true,
  'authenticated users can execute the released RPC'
);

select is(
  has_function_privilege(
    'service_role',
    'public.complete_maintenance_task(jsonb,text)',
    'EXECUTE'
  ),
  true,
  'service role can execute the maintenance RPC for protected smoke tests'
);

select is(
  (
    select count(*)::integer
    from regexp_matches(
      pg_get_functiondef(
        'public.complete_maintenance_task(jsonb,text)'::regprocedure
      ),
      'PT409',
      'g'
    )
  ),
  0,
  'business conflicts are returned as structured outcomes instead of PT409'
);

select is(
  (
    select count(*)::integer
    from regexp_matches(
      pg_get_functiondef(
        'public.complete_maintenance_task(jsonb,text)'::regprocedure
      ),
      '40001',
      'g'
    )
  ),
  0,
  'the RPC has no explicit business-conflict 40001 branches'
);

select is(
  (
    select count(*)::integer
    from regexp_matches(
      pg_get_functiondef(
        'public.complete_maintenance_task(jsonb,text)'::regprocedure
      ),
      '23505',
      'g'
    )
  ),
  0,
  'the RPC has no explicit retryable uniqueness-conflict branches'
);


insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at
)
values (
  '00000000-0000-0000-0000-000000000000',
  '33333333-3333-3333-3333-333333333333',
  'authenticated',
  'authenticated',
  'maintenance-rpc@example.test',
  '',
  now(),
  now(),
  now()
);

insert into public.areas (
  user_id,
  id,
  name,
  kind,
  sort_order,
  created_at,
  updated_at,
  archived_at
)
values (
  '33333333-3333-3333-3333-333333333333',
  'rpc-area',
  'RPC Test Area',
  'indoor',
  0,
  '2026-06-01 00:00:00+00',
  '2026-06-01 00:00:00+00',
  null
);

insert into public.rooms (
  user_id,
  id,
  area_id,
  name,
  room_type,
  notes,
  sort_order,
  created_at,
  updated_at,
  archived_at
)
values (
  '33333333-3333-3333-3333-333333333333',
  'rpc-room',
  'rpc-area',
  'RPC Test Room',
  'other',
  null,
  0,
  '2026-06-01 00:00:00+00',
  '2026-06-01 00:00:00+00',
  null
);

insert into public.assets (
  user_id,
  id,
  name,
  asset_type,
  room_id,
  placement,
  notes,
  purchase_date,
  created_at,
  updated_at,
  archived_at
)
values (
  '33333333-3333-3333-3333-333333333333',
  'rpc-asset',
  'RPC Test Asset',
  'general',
  'rpc-room',
  null,
  null,
  null,
  '2026-06-01 00:00:00+00',
  '2026-06-01 00:00:00+00',
  null
);

-- Monetized task creation is authorized before an offline sync replay can ask
-- the existing completion RPC to materialize the same plan.
insert into public.creation_point_operations (
  operation_id, user_id, entity_type, entity_id, charged_amount,
  request_hash, client_request_hash
) values (
  '33333333-0000-0000-0000-000000000001',
  '33333333-3333-3333-3333-333333333333',
  'task',
  'rpc-plan',
  1,
  repeat('1', 64),
  repeat('2', 64)
);

insert into public.maintenance_plans (
  user_id,
  id,
  asset_id,
  title,
  recurrence_interval,
  recurrence_unit,
  priority,
  next_due_date,
  reminder_days_before,
  is_enabled,
  revision,
  created_at,
  updated_at
)
values (
  '33333333-3333-3333-3333-333333333333',
  'rpc-early-plan',
  'rpc-asset',
  'Early daily task',
  1,
  'days',
  'medium',
  '2026-08-18 09:00:00+00',
  0,
  true,
  1,
  '2026-08-01 00:00:00+00',
  '2026-08-01 00:00:00+00'
);

set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
set local role authenticated;

select is(
  (
    public.complete_maintenance_task(
      jsonb_build_object(
        'version', 1,
        'operation_id', 'rpc-early-record',
        'expected_next_due_date', '2026-08-18T09:00:00.000Z',
        'plan', jsonb_build_object(
          'id', 'rpc-early-plan',
          'asset_id', 'rpc-asset',
          'title', 'Early daily task',
          'recurrence_interval', 1,
          'recurrence_unit', 'days',
          'priority', 'medium',
          'next_due_date', '2026-08-14T14:30:00.000Z',
          'reminder_days_before', 0,
          'is_enabled', true,
          'created_at', '2026-08-01T00:00:00.000Z',
          'updated_at', '2026-08-13T14:30:00.000Z'
        ),
        'record', jsonb_build_object(
          'id', 'rpc-early-record',
          'plan_id', 'rpc-early-plan',
          'due_date', '2026-08-18T09:00:00.000Z',
          'completed_at', '2026-08-13T14:30:00.000Z'
        )
      ),
      'rpc-device-early'
    ) ->> 'status'
  ),
  'applied',
  'early completion accepts a next due date based on actual completion even when it precedes the old due date'
);

set local role postgres;

select is(
  (
    select next_due_date
    from public.maintenance_plans
    where user_id = '33333333-3333-3333-3333-333333333333'
      and id = 'rpc-early-plan'
  ),
  '2026-08-14 14:30:00+00'::timestamptz,
  'early daily completion stores actual completedAt plus one day'
);

set local role authenticated;

select lives_ok(
  $sql$
    select public.complete_maintenance_task(
      $json$
      {
        "version": 1,
        "operation_id": "rpc-record-1",
        "expected_next_due_date": "2026-07-01T00:00:00.000Z",
        "plan": {
          "id": "rpc-plan",
          "asset_id": "rpc-asset",
          "title": "Replace RPC filter",
          "instructions": "Replace the test filter",
          "recurrence_interval": 1,
          "recurrence_unit": "months",
          "priority": "medium",
          "next_due_date": "2026-08-01T00:00:00.000Z",
          "reminder_days_before": 3,
          "is_enabled": true,
          "created_at": "2026-06-01T00:00:00.000Z",
          "updated_at": "2026-07-01T10:00:00.000Z",
          "archived_at": null
        },
        "record": {
          "id": "rpc-record-1",
          "plan_id": "rpc-plan",
          "due_date": "2026-07-01T00:00:00.000Z",
          "completed_at": "2026-07-01T09:00:00.000Z",
          "notes": "First completion"
        }
      }
      $json$::jsonb,
      'rpc-device'
    )
  $sql$,
  'first completion creates the plan and record atomically'
);

set local role postgres;

select is(
  (
    select count(*)::integer
    from public.maintenance_plans
    where user_id = '33333333-3333-3333-3333-333333333333'
      and id = 'rpc-plan'
  ),
  1,
  'first execution creates one maintenance plan'
);

select is(
  (
    select count(*)::integer
    from public.maintenance_records
    where user_id = '33333333-3333-3333-3333-333333333333'
      and id = 'rpc-record-1'
  ),
  1,
  'first execution creates one maintenance record'
);

select is(
  (
    select next_due_date
    from public.maintenance_plans
    where user_id = '33333333-3333-3333-3333-333333333333'
      and id = 'rpc-plan'
  ),
  '2026-08-01 00:00:00+00'::timestamptz,
  'first execution advances the plan due date'
);

create temporary table rpc_first_snapshot as
select revision, updated_at
from public.maintenance_plans
where user_id = '33333333-3333-3333-3333-333333333333'
  and id = 'rpc-plan';

set local role authenticated;

select is(
  (
    public.complete_maintenance_task(
      $json$
      {
        "version": 1,
        "operation_id": "rpc-record-1",
        "expected_next_due_date": "2026-07-01T00:00:00.000Z",
        "plan": {
          "id": "rpc-plan",
          "asset_id": "rpc-asset",
          "title": "Replace RPC filter",
          "instructions": "Replace the test filter",
          "recurrence_interval": 1,
          "recurrence_unit": "months",
          "priority": "medium",
          "next_due_date": "2026-08-01T00:00:00.000Z",
          "reminder_days_before": 3,
          "is_enabled": true,
          "created_at": "2026-06-01T00:00:00.000Z",
          "updated_at": "2026-07-01T10:00:00.000Z",
          "archived_at": null
        },
        "record": {
          "id": "rpc-record-1",
          "plan_id": "rpc-plan",
          "due_date": "2026-07-01T00:00:00.000Z",
          "completed_at": "2026-07-01T09:00:00.000Z",
          "notes": "First completion"
        }
      }
      $json$::jsonb,
      'rpc-device'
    ) -> 'record' ->> 'id'
  ),
  'rpc-record-1',
  'an idempotent retry returns the canonical record'
);

select is(
  (
    public.complete_maintenance_task(
      jsonb_build_object(
        'version', 1,
        'operation_id', 'rpc-record-1',
        'expected_next_due_date', '2026-07-01T00:00:00.000Z',
        'plan', jsonb_build_object(
          'id', 'rpc-plan',
          'asset_id', 'rpc-asset',
          'title', 'Replace RPC filter',
          'recurrence_interval', 1,
          'recurrence_unit', 'months',
          'priority', 'medium',
          'next_due_date', '2026-08-01T00:00:00.000Z',
          'reminder_days_before', 3,
          'is_enabled', true,
          'created_at', '2026-06-01T00:00:00.000Z',
          'updated_at', '2026-07-01T10:00:00.000Z'
        ),
        'record', jsonb_build_object(
          'id', 'rpc-record-1',
          'plan_id', 'rpc-plan',
          'due_date', '2026-07-01T00:00:00.000Z',
          'completed_at', '2026-07-01T09:01:00.000Z',
          'notes', 'First completion'
        )
      ),
      'rpc-device'
    ) ->> 'status'
  ),
  'conflict',
  'reusing a completion operation with a different completedAt is rejected'
);

select is(
  (
    public.complete_maintenance_task(
      jsonb_build_object(
        'version', 1,
        'operation_id', 'rpc-record-1',
        'expected_next_due_date', '2026-07-01T00:00:00.000Z',
        'plan', jsonb_build_object(
          'id', 'rpc-plan',
          'asset_id', 'rpc-asset',
          'title', 'Replace RPC filter',
          'recurrence_interval', 1,
          'recurrence_unit', 'months',
          'priority', 'medium',
          'next_due_date', '2026-08-01T00:00:00.000Z',
          'reminder_days_before', 3,
          'is_enabled', true,
          'created_at', '2026-06-01T00:00:00.000Z',
          'updated_at', '2026-07-01T10:00:00.000Z'
        ),
        'record', jsonb_build_object(
          'id', 'rpc-record-1',
          'plan_id', 'rpc-plan',
          'due_date', '2026-07-01T00:00:00.000Z',
          'completed_at', '2026-07-01T09:01:00.000Z',
          'notes', 'First completion'
        )
      ),
      'rpc-device'
    ) ->> 'conflict_reason'
  ),
  'operation_id_reused',
  'completedAt mismatch reports operation_id_reused'
);

select is(
  (
    public.complete_maintenance_task(
      $json$
      {
        "version": 1,
        "operation_id": "rpc-record-1",
        "expected_next_due_date": "2026-07-01T00:00:00.000Z",
        "plan": {
          "id": "rpc-plan",
          "asset_id": "rpc-asset",
          "title": "Replace RPC filter",
          "instructions": "Replace the test filter",
          "recurrence_interval": 1,
          "recurrence_unit": "months",
          "priority": "medium",
          "next_due_date": "2026-08-01T00:00:00.000Z",
          "reminder_days_before": 3,
          "is_enabled": true,
          "created_at": "2026-06-01T00:00:00.000Z",
          "updated_at": "2026-07-01T10:00:00.000Z",
          "archived_at": null
        },
        "record": {
          "id": "rpc-record-1",
          "plan_id": "rpc-plan",
          "due_date": "2026-07-01T00:00:00.000Z",
          "completed_at": "2026-07-01T09:00:00.000Z",
          "notes": "Different completion data"
        }
      }
      $json$::jsonb,
      'rpc-device'
    ) ->> 'status'
  ),
  'conflict',
  'a reused completion identifier with different data is rejected'
);

select is(
  (
    public.complete_maintenance_task(
      $json$
      {
        "version": 1,
        "operation_id": "rpc-record-1",
        "expected_next_due_date": "2026-07-01T00:00:00.000Z",
        "plan": {
          "id": "rpc-plan",
          "asset_id": "rpc-asset",
          "title": "Replace RPC filter",
          "recurrence_interval": 1,
          "recurrence_unit": "months",
          "priority": "medium",
          "next_due_date": "2026-08-01T00:00:00.000Z",
          "reminder_days_before": 3,
          "is_enabled": true,
          "created_at": "2026-06-01T00:00:00.000Z",
          "updated_at": "2026-07-01T10:00:00.000Z"
        },
        "record": {
          "id": "rpc-record-1",
          "plan_id": "rpc-plan",
          "due_date": "2026-07-01T00:00:00.000Z",
          "completed_at": "2026-07-01T09:00:00.000Z",
          "notes": "Different completion data"
        }
      }
      $json$::jsonb,
      'rpc-device'
    ) ->> 'conflict_reason'
  ),
  'operation_id_reused',
  'a reused operation identifies the conflict reason'
);

select ok(
  (
    select result->>'status' = 'conflict'
      and result->>'conflict_reason' = 'operation_id_reused'
      and result->'plan' = 'null'::jsonb
      and result->'record' = 'null'::jsonb
      and result->'current_plan_revision' = 'null'::jsonb
      and result->'resulting_record_id' = 'null'::jsonb
      and result->'resulting_next_due_date' = 'null'::jsonb
    from (
      select public.complete_maintenance_task(
        jsonb_build_object(
          'version', 1,
          'operation_id', 'rpc-record-1',
          'expected_next_due_date', '2026-08-14T14:30:00.000Z',
          'plan', jsonb_build_object(
            'id', 'rpc-early-plan',
            'asset_id', 'rpc-asset',
            'title', 'Early daily task',
            'recurrence_interval', 1,
            'recurrence_unit', 'days',
            'priority', 'medium',
            'next_due_date', '2026-08-15T14:30:00.000Z',
            'reminder_days_before', 0,
            'is_enabled', true,
            'created_at', '2026-08-01T00:00:00.000Z',
            'updated_at', '2026-08-13T14:30:00.000Z'
          ),
          'record', jsonb_build_object(
            'id', 'different-record',
            'plan_id', 'rpc-early-plan',
            'due_date', '2026-08-14T14:30:00.000Z',
            'completed_at', '2026-08-14T13:30:00.000Z'
          )
        ),
        'rpc-device'
      ) as result
    ) as response
  ),
  'an operation reused across plans is terminal without returning unrelated canonical rows'
);

set local role postgres;

select is(
  (
    select revision
    from public.maintenance_plans
    where user_id = '33333333-3333-3333-3333-333333333333'
      and id = 'rpc-plan'
  ),
  (select revision from rpc_first_snapshot),
  'an idempotent retry does not increment the plan revision'
);

select is(
  (
    select updated_at
    from public.maintenance_plans
    where user_id = '33333333-3333-3333-3333-333333333333'
      and id = 'rpc-plan'
  ),
  (select updated_at from rpc_first_snapshot),
  'an idempotent retry does not rewrite the plan timestamp'
);

select is(
  (
    select count(*)::integer
    from public.maintenance_records
    where user_id = '33333333-3333-3333-3333-333333333333'
      and plan_id = 'rpc-plan'
  ),
  1,
  'an idempotent retry does not duplicate the completion record'
);

update public.maintenance_plans
set title = 'Cloud-edited RPC filter'
where user_id = '33333333-3333-3333-3333-333333333333'
  and id = 'rpc-plan';

set local role authenticated;

select lives_ok(
  $sql$
    select public.complete_maintenance_task(
      $json$
      {
        "version": 1,
        "operation_id": "rpc-record-2",
        "expected_next_due_date": "2026-08-01T00:00:00.000Z",
        "plan": {
          "id": "rpc-plan",
          "asset_id": "rpc-asset",
          "title": "Replace RPC filter",
          "instructions": "Replace the test filter",
          "recurrence_interval": 1,
          "recurrence_unit": "months",
          "priority": "medium",
          "next_due_date": "2026-09-01T00:00:00.000Z",
          "reminder_days_before": 3,
          "is_enabled": true,
          "created_at": "2026-06-01T00:00:00.000Z",
          "updated_at": "2026-07-27T10:00:00.000Z",
          "archived_at": null
        },
        "record": {
          "id": "rpc-record-2",
          "plan_id": "rpc-plan",
          "due_date": "2026-08-01T00:00:00.000Z",
          "completed_at": "2026-07-27T09:00:00.000Z",
          "notes": "Second completion"
        }
      }
      $json$::jsonb,
      'rpc-device'
    )
  $sql$,
  'a second ordered offline completion succeeds'
);

set local role postgres;

select is(
  (
    select count(*)::integer
    from public.maintenance_records
    where user_id = '33333333-3333-3333-3333-333333333333'
      and plan_id = 'rpc-plan'
  ),
  2,
  'two ordered completions create two records'
);

select is(
  (
    select next_due_date
    from public.maintenance_plans
    where user_id = '33333333-3333-3333-3333-333333333333'
      and id = 'rpc-plan'
  ),
  '2026-09-01 00:00:00+00'::timestamptz,
  'the second completion advances the due date again'
);

select is(
  (
    select title
    from public.maintenance_plans
    where user_id = '33333333-3333-3333-3333-333333333333'
      and id = 'rpc-plan'
  ),
  'Cloud-edited RPC filter',
  'a completion preserves concurrent non-due-date plan edits'
);

set local role authenticated;

select is(
  (
    public.complete_maintenance_task(
      $json$
      {
        "version": 1,
        "operation_id": "rpc-record-conflict",
        "expected_next_due_date": "2026-08-15T00:00:00.000Z",
        "plan": {
          "id": "rpc-plan",
          "asset_id": "rpc-asset",
          "title": "Replace RPC filter",
          "instructions": "Replace the test filter",
          "recurrence_interval": 1,
          "recurrence_unit": "months",
          "priority": "medium",
          "next_due_date": "2026-10-01T00:00:00.000Z",
          "reminder_days_before": 3,
          "is_enabled": true,
          "created_at": "2026-06-01T00:00:00.000Z",
          "updated_at": "2026-07-27T12:00:00.000Z",
          "archived_at": null
        },
        "record": {
          "id": "rpc-record-conflict",
          "plan_id": "rpc-plan",
          "due_date": "2026-08-15T00:00:00.000Z",
          "completed_at": "2026-07-27T11:00:00.000Z",
          "notes": "Conflicting completion"
        }
      }
      $json$::jsonb,
      'rpc-device'
    ) ->> 'status'
  ),
  'conflict',
  'a stale expected due date rejects the entire completion'
);

select is(
  (
    public.complete_maintenance_task(
      $json$
      {
        "version": 1,
        "operation_id": "rpc-record-conflict",
        "expected_next_due_date": "2026-08-15T00:00:00.000Z",
        "plan": {
          "id": "rpc-plan",
          "asset_id": "rpc-asset",
          "title": "Replace RPC filter",
          "recurrence_interval": 1,
          "recurrence_unit": "months",
          "priority": "medium",
          "next_due_date": "2026-10-01T00:00:00.000Z",
          "reminder_days_before": 3,
          "is_enabled": true,
          "created_at": "2026-06-01T00:00:00.000Z",
          "updated_at": "2026-07-27T12:00:00.000Z"
        },
        "record": {
          "id": "rpc-record-conflict",
          "plan_id": "rpc-plan",
          "due_date": "2026-08-15T00:00:00.000Z",
          "completed_at": "2026-07-27T11:00:00.000Z"
        }
      }
      $json$::jsonb,
      'rpc-device'
    ) ->> 'conflict_reason'
  ),
  'occurrence_changed',
  'a stale occurrence reports a machine-readable reason'
);

set local role postgres;

select is(
  (
    select count(*)::integer
    from public.maintenance_records
    where user_id = '33333333-3333-3333-3333-333333333333'
      and plan_id = 'rpc-plan'
  ),
  2,
  'a conflict does not insert a partial maintenance record'
);

select is(
  (
    select next_due_date
    from public.maintenance_plans
    where user_id = '33333333-3333-3333-3333-333333333333'
      and id = 'rpc-plan'
  ),
  '2026-09-01 00:00:00+00'::timestamptz,
  'a conflict does not partially update the maintenance plan'
);

select col_not_null(
  'public',
  'maintenance_records',
  'operation_id',
  'completion idempotency keys are required'
);

select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'maintenance_records'
      and indexname = 'maintenance_records_operation_uidx'
  ),
  'completion idempotency keys are unique per user'
);

select is(
  (
    public.complete_maintenance_task(
      jsonb_build_object(
        'version', 1,
        'operation_id', 'rpc-record-3',
        'expected_plan_revision', 0,
        'expected_next_due_date', '2026-09-01T00:00:00.000Z',
        'plan', jsonb_build_object(
          'id', 'rpc-plan',
          'asset_id', 'rpc-asset',
          'title', 'Replace RPC filter',
          'recurrence_interval', 1,
          'recurrence_unit', 'months',
          'priority', 'medium',
          'next_due_date', '2026-10-01T00:00:00.000Z',
          'reminder_days_before', 3,
          'is_enabled', true,
          'created_at', '2026-06-01T00:00:00.000Z',
          'updated_at', '2026-07-27T13:00:00.000Z'
        ),
        'record', jsonb_build_object(
          'id', 'rpc-record-3',
          'plan_id', 'rpc-plan',
          'due_date', '2026-09-01T00:00:00.000Z',
          'completed_at', '2026-07-27T12:30:00.000Z'
        )
      ),
      'rpc-device'
    ) ->> 'status'
  ),
  'conflict',
  'a stale revision returns a structured conflict'
);

select is(
  (
    public.complete_maintenance_task(
      jsonb_build_object(
        'version', 1,
        'operation_id', 'rpc-record-3',
        'expected_plan_revision', 0,
        'expected_next_due_date', '2026-09-01T00:00:00.000Z',
        'plan', jsonb_build_object(
          'id', 'rpc-plan',
          'asset_id', 'rpc-asset',
          'title', 'Replace RPC filter',
          'recurrence_interval', 1,
          'recurrence_unit', 'months',
          'priority', 'medium',
          'next_due_date', '2026-10-01T00:00:00.000Z',
          'reminder_days_before', 3,
          'is_enabled', true,
          'created_at', '2026-06-01T00:00:00.000Z',
          'updated_at', '2026-07-27T13:00:00.000Z'
        ),
        'record', jsonb_build_object(
          'id', 'rpc-record-3',
          'plan_id', 'rpc-plan',
          'due_date', '2026-09-01T00:00:00.000Z',
          'completed_at', '2026-07-27T12:30:00.000Z'
        )
      ),
      'rpc-device'
    ) ->> 'retryable'
  ),
  'true',
  'a stale revision with an unchanged occurrence is safe to retry once'
);

select is(
  (
    public.complete_maintenance_task(
      jsonb_build_object(
        'version', 1,
        'operation_id', 'rpc-record-3',
        'expected_plan_revision', 0,
        'expected_next_due_date', '2026-09-01T00:00:00.000Z',
        'plan', jsonb_build_object(
          'id', 'rpc-plan',
          'asset_id', 'rpc-asset',
          'title', 'Replace RPC filter',
          'recurrence_interval', 1,
          'recurrence_unit', 'months',
          'priority', 'medium',
          'next_due_date', '2026-10-01T00:00:00.000Z',
          'reminder_days_before', 3,
          'is_enabled', true,
          'created_at', '2026-06-01T00:00:00.000Z',
          'updated_at', '2026-07-27T13:00:00.000Z'
        ),
        'record', jsonb_build_object(
          'id', 'rpc-record-3',
          'plan_id', 'rpc-plan',
          'due_date', '2026-09-01T00:00:00.000Z',
          'completed_at', '2026-07-27T12:30:00.000Z'
        )
      ),
      'rpc-device'
    ) ->> 'conflict_reason'
  ),
  'stale_plan_revision',
  'a safe stale revision reports its exact recovery reason'
);

select is(
  (
    public.complete_maintenance_task(
      jsonb_build_object(
        'version', 1,
        'operation_id', 'rpc-record-3',
        'expected_plan_revision', (
          select revision
          from public.maintenance_plans
          where user_id = '33333333-3333-3333-3333-333333333333'
            and id = 'rpc-plan'
        ),
        'expected_next_due_date', '2026-09-01T00:00:00.000Z',
        'plan', jsonb_build_object(
          'id', 'rpc-plan',
          'asset_id', 'rpc-asset',
          'title', 'Replace RPC filter',
          'recurrence_interval', 1,
          'recurrence_unit', 'months',
          'priority', 'medium',
          'next_due_date', '2026-10-01T00:00:00.000Z',
          'reminder_days_before', 3,
          'is_enabled', true,
          'created_at', '2026-06-01T00:00:00.000Z',
          'updated_at', '2026-07-27T13:00:00.000Z'
        ),
        'record', jsonb_build_object(
          'id', 'rpc-record-3',
          'plan_id', 'rpc-plan',
          'due_date', '2026-09-01T00:00:00.000Z',
          'completed_at', '2026-07-27T12:30:00.000Z'
        )
      ),
      'rpc-device'
    ) ->> 'status'
  ),
  'applied',
  'retrying with the fetched revision applies the same operation'
);

select is(
  (
    select count(*)::integer
    from public.maintenance_records
    where user_id = '33333333-3333-3333-3333-333333333333'
      and plan_id = 'rpc-plan'
  ),
  3,
  'the recovered operation creates exactly one new completion'
);

select is(
  (
    public.complete_maintenance_task(
      jsonb_build_object(
        'version', 1,
        'operation_id', 'rpc-record-race-a',
        'expected_next_due_date', '2026-10-01T00:00:00.000Z',
        'plan', jsonb_build_object(
          'id', 'rpc-plan',
          'asset_id', 'rpc-asset',
          'title', 'Replace RPC filter',
          'recurrence_interval', 1,
          'recurrence_unit', 'months',
          'priority', 'medium',
          'next_due_date', '2026-11-01T00:00:00.000Z',
          'reminder_days_before', 3,
          'is_enabled', true,
          'created_at', '2026-06-01T00:00:00.000Z',
          'updated_at', '2026-07-27T14:00:00.000Z'
        ),
        'record', jsonb_build_object(
          'id', 'rpc-record-race-a',
          'plan_id', 'rpc-plan',
          'due_date', '2026-10-01T00:00:00.000Z',
          'completed_at', '2026-07-27T13:30:00.000Z'
        )
      ),
      'rpc-device-a'
    ) ->> 'status'
  ),
  'applied',
  'the first device wins a same-occurrence completion race'
);

create temporary table rpc_race_loser_result as
select public.complete_maintenance_task(
  jsonb_build_object(
    'version', 1,
    'operation_id', 'rpc-record-race-b',
    'expected_next_due_date', '2026-10-01T00:00:00.000Z',
    'plan', jsonb_build_object(
      'id', 'rpc-plan',
      'asset_id', 'rpc-asset',
      'title', 'Replace RPC filter',
      'recurrence_interval', 1,
      'recurrence_unit', 'months',
      'priority', 'medium',
      'next_due_date', '2026-11-01T00:00:00.000Z',
      'reminder_days_before', 3,
      'is_enabled', true,
      'created_at', '2026-06-01T00:00:00.000Z',
      'updated_at', '2026-07-27T14:00:00.000Z'
    ),
    'record', jsonb_build_object(
      'id', 'rpc-record-race-b',
      'plan_id', 'rpc-plan',
      'due_date', '2026-10-01T00:00:00.000Z',
      'completed_at', '2026-07-27T13:31:00.000Z'
    )
  ),
  'rpc-device-b'
) as result;

select is(
  (select result ->> 'status' from rpc_race_loser_result),
  'conflict',
  'the second device receives a structured race conflict'
);

select is(
  (select result ->> 'conflict_reason' from rpc_race_loser_result),
  'occurrence_completed_elsewhere',
  'the losing device learns that the occurrence was already completed'
);

select is(
  (select result ->> 'retryable' from rpc_race_loser_result),
  'false',
  'a completed occurrence is never automatically retried'
);

select is(
  (
    select count(*)::integer
    from public.maintenance_records
    where user_id = '33333333-3333-3333-3333-333333333333'
      and plan_id = 'rpc-plan'
  ),
  4,
  'the two-device race creates only one logical completion'
);

select is(
  (
    select next_due_date
    from public.maintenance_plans
    where user_id = '33333333-3333-3333-3333-333333333333'
      and id = 'rpc-plan'
  ),
  '2026-11-01 00:00:00+00'::timestamptz,
  'the losing race operation never advances recurrence twice'
);

-- Fractional timestamp precision is canonical across completion payloads.
insert into public.maintenance_plans (
  id,
  user_id,
  asset_id,
  title,
  recurrence_interval,
  recurrence_unit,
  priority,
  next_due_date,
  reminder_days_before,
  created_at,
  updated_at,
  revision,
  is_enabled
) values (
  'fractional-plan',
  '33333333-3333-3333-3333-333333333333',
  'rpc-asset',
  'Fractional Test Task',
  1,
  'months',
  'high',
  '2026-08-08T18:13:27.842731Z'::timestamptz,
  0,
  '2026-06-01T00:00:00Z'::timestamptz,
  '2026-06-01T00:00:00Z'::timestamptz,
  1,
  true
);

create temp table rpc_fractional_result as
select public.complete_maintenance_task(
  jsonb_build_object(
    'version', 1,
    'operation_id', 'frac-op-1',
    'plan_id', 'fractional-plan',
    'expected_plan_revision', 1,
    'expected_next_due_date', '2026-08-08T18:13:27.000Z',
    'plan', jsonb_build_object(
      'id', 'fractional-plan',
      'asset_id', 'rpc-asset',
      'title', 'Fractional Test Task',
      'recurrence_interval', 1,
      'recurrence_unit', 'months',
      'priority', 'high',
      'next_due_date', '2026-09-08T18:13:27.000Z',
      'reminder_days_before', 0,
      'is_enabled', true,
      'created_at', '2026-06-01T00:00:00.000Z'
    ),
    'record', jsonb_build_object(
      'id', 'frac-rec-1',
      'plan_id', 'fractional-plan',
      'due_date', '2026-08-08T18:13:27.000Z',
      'completed_at', '2026-08-08T18:13:27.842Z'
    )
  ),
  'frac-device-1'
) as result;

select is(
  (select result ->> 'status' from rpc_fractional_result),
  'applied',
  'RPC accepts a whole-second completion against a fractional cloud plan'
);

select is(
  (
    select next_due_date
    from public.maintenance_plans
    where id = 'fractional-plan'
  ),
  '2026-09-08 18:13:27+00'::timestamptz,
  'successful completion self-heals next_due_date to whole-second precision'
);

-- Sequential completion for next occurrence
create temp table rpc_fractional_seq_result as
select public.complete_maintenance_task(
  jsonb_build_object(
    'version', 1,
    'operation_id', 'frac-op-2',
    'plan_id', 'fractional-plan',
    'depends_on_operation_id', 'frac-op-1',
    'expected_plan_revision', 2,
    'expected_next_due_date', '2026-09-08T18:13:27.000Z',
    'plan', jsonb_build_object(
      'id', 'fractional-plan',
      'asset_id', 'rpc-asset',
      'title', 'Fractional Test Task',
      'recurrence_interval', 1,
      'recurrence_unit', 'months',
      'priority', 'high',
      'next_due_date', '2026-10-08T18:13:27.000Z',
      'reminder_days_before', 0,
      'is_enabled', true,
      'created_at', '2026-06-01T00:00:00.000Z'
    ),
    'record', jsonb_build_object(
      'id', 'frac-rec-2',
      'plan_id', 'fractional-plan',
      'due_date', '2026-09-08T18:13:27.000Z',
      'completed_at', '2026-09-08T18:13:27.999Z'
    )
  ),
  'frac-device-1'
) as result;

select is(
  (select result ->> 'status' from rpc_fractional_seq_result),
  'applied',
  'sequential completion for next occurrence succeeds cleanly'
);

-- Remote winner precision test
create temp table rpc_fractional_winner_result as
select public.complete_maintenance_task(
  jsonb_build_object(
    'version', 1,
    'operation_id', 'frac-op-winner-b',
    'plan_id', 'fractional-plan',
    'expected_plan_revision', 2,
    'expected_next_due_date', '2026-09-08T18:13:27.000Z',
    'plan', jsonb_build_object(
      'id', 'fractional-plan',
      'asset_id', 'rpc-asset',
      'title', 'Fractional Test Task',
      'recurrence_interval', 1,
      'recurrence_unit', 'months',
      'priority', 'high',
      'next_due_date', '2026-10-08T18:13:27.000Z',
      'reminder_days_before', 0,
      'is_enabled', true,
      'created_at', '2026-06-01T00:00:00.000Z'
    ),
    'record', jsonb_build_object(
      'id', 'frac-rec-winner-b',
      'plan_id', 'fractional-plan',
      'due_date', '2026-09-08T18:13:27.000Z',
      'completed_at', '2026-09-08T18:13:27.000Z'
    )
  ),
  'frac-device-2'
) as result;

select is(
  (select result ->> 'conflict_reason' from rpc_fractional_winner_result),
  'occurrence_completed_elsewhere',
  'remote winner is recognized even when comparing whole-second vs stored timestamps'
);

set local role authenticated;
set local request.jwt.claims = '{}';

select throws_ok(
  $$ select public.complete_maintenance_task('{}'::jsonb, 'rpc-device') $$,
  '42501',
  'AUTH_REQUIRED',
  'the RPC rejects a call without an authenticated identity'
);

set local role postgres;

select * from finish();

rollback;
