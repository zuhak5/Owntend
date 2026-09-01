begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(32);

select extensions.has_function(
  'public', 'complete_maintenance_task', array['jsonb', 'text'],
  'maintenance completion RPC exists'
);
select extensions.ok(
  has_function_privilege(
    'authenticated', 'public.complete_maintenance_task(jsonb,text)', 'execute'
  ),
  'authenticated users can execute the public completion RPC'
);
select extensions.ok(
  not has_function_privilege(
    'anon', 'public.complete_maintenance_task(jsonb,text)', 'execute'
  ),
  'anonymous users cannot execute the completion RPC'
);
select extensions.ok(
  not (
    select prosecdef
    from pg_proc
    where oid = 'public.complete_maintenance_task(jsonb,text)'::regprocedure
  ),
  'the public wrapper uses invoker security'
);
select extensions.ok(
  (
    select prosecdef
    from pg_proc
    where oid =
      'owntend_private.complete_maintenance_task_impl(jsonb,text)'::regprocedure
  ),
  'the private implementation is the narrow security-definer boundary'
);
select extensions.has_index(
  'public', 'maintenance_records', 'maintenance_records_occurrence_uidx',
  'one record can be accepted per maintenance occurrence'
);

select extensions.is(
  owntend_private.next_maintenance_due(
    '2026-03-07T14:00:00Z'::timestamptz, 1, 'days', 'America/New_York'
  ),
  '2026-03-08T13:00:00Z'::timestamptz,
  'calendar-day recurrence preserves local wall-clock time across DST'
);
select extensions.is(
  owntend_private.next_maintenance_due(
    '2026-03-07T14:00:00Z'::timestamptz, 24, 'hours', 'America/New_York'
  ),
  '2026-03-08T14:00:00Z'::timestamptz,
  'hour recurrence uses elapsed duration semantics'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '33333333-3333-3333-3333-333333333333',
  'authenticated', 'authenticated', 'maintenance-rpc@example.test', '',
  now(), now(), now()
);
insert into public.areas (
  user_id, id, name, kind, sort_order, created_at, updated_at, archived_at
) values (
  '33333333-3333-3333-3333-333333333333', 'rpc-area', 'RPC Test Area',
  'indoor', 0, '2026-06-01T00:00:00Z', '2026-06-01T00:00:00Z', null
);
insert into public.rooms (
  user_id, id, area_id, name, room_type, notes, sort_order,
  created_at, updated_at, archived_at
) values (
  '33333333-3333-3333-3333-333333333333', 'rpc-room', 'rpc-area',
  'RPC Test Room', 'other', null, 0,
  '2026-06-01T00:00:00Z', '2026-06-01T00:00:00Z', null
);
insert into public.assets (
  user_id, id, name, asset_type, room_id, placement, notes, purchase_date,
  created_at, updated_at, archived_at
) values (
  '33333333-3333-3333-3333-333333333333', 'rpc-asset', 'RPC Test Asset',
  'general', 'rpc-room', null, null, null,
  '2026-06-01T00:00:00Z', '2026-06-01T00:00:00Z', null
);
insert into public.maintenance_plans (
  user_id, id, asset_id, title, recurrence_interval, recurrence_unit,
  priority, next_due_date, current_occurrence_id, reminder_days_before,
  is_enabled, revision, created_at, updated_at
) values
  (
    '33333333-3333-3333-3333-333333333333', 'rpc-plan', 'rpc-asset',
    'Daily task', 1, 'days', 'medium', '2026-08-18T09:00:00Z',
    'occurrence-1', 0, true, 1,
    '2026-08-01T00:00:00Z', '2026-08-01T00:00:00Z'
  ),
  (
    '33333333-3333-3333-3333-333333333333', 'revision-plan', 'rpc-asset',
    'Weekly task', 1, 'weeks', 'medium', '2026-08-20T09:00:00Z',
    'revision-occurrence', 0, true, 1,
    '2026-08-01T00:00:00Z', '2026-08-01T00:00:00Z'
  ),
  (
    '33333333-3333-3333-3333-333333333333', 'inactive-plan', 'rpc-asset',
    'Inactive task', 1, 'months', 'medium', '2026-08-20T09:00:00Z',
    'inactive-occurrence', 0, false, 1,
    '2026-08-01T00:00:00Z', '2026-08-01T00:00:00Z'
  ),
  (
    '33333333-3333-3333-3333-333333333333', 'reward-plan', 'rpc-asset',
    'Reward task', 1, 'days', 'medium', clock_timestamp() - interval '1 hour',
    'reward-occurrence', 0, true, 1,
    clock_timestamp() - interval '1 day', clock_timestamp() - interval '1 day'
  );

update public.maintenance_plans
set title = 'Weekly task edited'
where user_id = '33333333-3333-3333-3333-333333333333'
  and id = 'revision-plan';

set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
set local role authenticated;

select extensions.is(
  public.complete_maintenance_task(
    jsonb_build_object(
      'contract_version', 1,
      'operation_id', 'completion-1',
      'plan_id', 'rpc-plan',
      'occurrence_id', 'occurrence-1',
      'expected_plan_revision', 1,
      'completed_at', '2026-08-14T14:30:00Z',
      'time_zone_id', 'Asia/Baghdad',
      'notes', 'done'
    ),
    'rpc-device'
  )->>'status',
  'applied',
  'a completion intent is accepted'
);
select extensions.is(
  (select next_due_date from public.maintenance_plans where id = 'rpc-plan'),
  '2026-08-15T14:30:00Z'::timestamptz,
  'the server anchors recurrence to completion time'
);
select extensions.is(
  (select current_occurrence_id from public.maintenance_plans where id = 'rpc-plan'),
  'next:completion-1',
  'the server advances to a deterministic next occurrence'
);
select extensions.is(
  (select due_date from public.maintenance_records where id = 'completion-1'),
  '2026-08-18T09:00:00Z'::timestamptz,
  'the record preserves the canonical due date of the completed occurrence'
);
select extensions.ok(
  (select accepted_at is not null from public.maintenance_records where id = 'completion-1'),
  'the server records its acceptance timestamp'
);
select extensions.is(
  (select time_zone_id from public.maintenance_records where id = 'completion-1'),
  'Asia/Baghdad',
  'the recurrence time-zone decision is auditable'
);
select extensions.is(
  public.complete_maintenance_task(
    '{"contract_version":1,"operation_id":"completion-1","plan_id":"rpc-plan","occurrence_id":"occurrence-1","expected_plan_revision":1,"completed_at":"2026-08-14T14:30:00Z","time_zone_id":"Asia/Baghdad","notes":"done"}'::jsonb,
    'rpc-device'
  )->>'status',
  'already_applied',
  'the exact operation is idempotent'
);
select extensions.is(
  public.complete_maintenance_task(
    '{"contract_version":1,"operation_id":"completion-1","plan_id":"rpc-plan","occurrence_id":"occurrence-1","expected_plan_revision":1,"completed_at":"2026-08-14T14:30:00Z","time_zone_id":"Asia/Baghdad","notes":"changed"}'::jsonb,
    'rpc-device'
  )->>'conflict_reason',
  'operation_id_reused',
  'an operation id cannot be reused for different intent'
);
select extensions.is(
  public.complete_maintenance_task(
    '{"contract_version":1,"operation_id":"completion-other","plan_id":"rpc-plan","occurrence_id":"occurrence-1","completed_at":"2026-08-14T14:30:00Z","time_zone_id":"Asia/Baghdad","notes":"done"}'::jsonb,
    'rpc-device'
  )->>'conflict_reason',
  'occurrence_completed_elsewhere',
  'a second operation cannot accept an already-completed occurrence'
);
select extensions.is(
  public.complete_maintenance_task(
    '{"contract_version":1,"operation_id":"completion-2","plan_id":"rpc-plan","occurrence_id":"next:completion-1","completed_at":"2026-08-15T15:00:00Z","time_zone_id":"Asia/Baghdad"}'::jsonb,
    'rpc-device'
  )->>'status',
  'applied',
  'the immediate next offline occurrence remains causally completable'
);
select extensions.is(
  (select count(*)::integer from public.maintenance_records where plan_id = 'rpc-plan'),
  2,
  'each accepted occurrence has exactly one record'
);
select extensions.is(
  public.complete_maintenance_task(
    '{"contract_version":1,"operation_id":"stale-op","plan_id":"rpc-plan","occurrence_id":"unknown-occurrence","completed_at":"2026-08-16T15:00:00Z","time_zone_id":"UTC"}'::jsonb,
    'rpc-device'
  )->>'conflict_reason',
  'stale_occurrence',
  'unknown stale occurrence identities fail visibly'
);
select extensions.is(
  public.complete_maintenance_task(
    '{"contract_version":1,"operation_id":"revision-op","plan_id":"revision-plan","occurrence_id":"revision-occurrence","expected_plan_revision":1,"completed_at":"2026-08-18T09:00:00Z","time_zone_id":"UTC"}'::jsonb,
    'rpc-device'
  )->>'status',
  'applied',
  'a harmless plan revision mismatch does not retry a stale client projection'
);
select extensions.is(
  public.complete_maintenance_task(
    '{"contract_version":1,"operation_id":"missing-op","plan_id":"missing-plan","occurrence_id":"missing-occurrence","completed_at":"2026-08-18T09:00:00Z","time_zone_id":"UTC"}'::jsonb,
    'rpc-device'
  )->>'conflict_reason',
  'plan_unavailable',
  'completion cannot create a missing plan as a side effect'
);
select extensions.is(
  public.complete_maintenance_task(
    '{"contract_version":1,"operation_id":"extra-op","plan_id":"rpc-plan","occurrence_id":"next:completion-2","completed_at":"2026-08-16T15:00:00Z","time_zone_id":"UTC","plan":{}}'::jsonb,
    'rpc-device'
  )->>'conflict_reason',
  'unexpected_payload_field',
  'the RPC rejects client-authored plan projections'
);
select extensions.is(
  public.complete_maintenance_task(
    '{"contract_version":1,"operation_id":"zone-op","plan_id":"rpc-plan","occurrence_id":"next:completion-2","completed_at":"2026-08-16T15:00:00Z","time_zone_id":"Not/AZone"}'::jsonb,
    'rpc-device'
  )->>'conflict_reason',
  'invalid_time_zone',
  'invalid recurrence time zones are rejected explicitly'
);
select extensions.is(
  public.complete_maintenance_task(
    '{"contract_version":1,"operation_id":"inactive-op","plan_id":"inactive-plan","occurrence_id":"inactive-occurrence","completed_at":"2026-08-18T09:00:00Z","time_zone_id":"UTC"}'::jsonb,
    'rpc-device'
  )->>'conflict_reason',
  'plan_inactive',
  'disabled plans cannot be completed'
);
select extensions.is(
  (select count(*)::integer from public.maintenance_plans where id = 'missing-plan'),
  0,
  'a rejected completion never materializes a plan'
);

set local role postgres;
update public.maintenance_plans
set is_enabled = false
where user_id = '33333333-3333-3333-3333-333333333333'
  and id <> 'reward-plan';
set local role authenticated;
select extensions.ok(
  public.complete_maintenance_task(
    jsonb_build_object(
      'contract_version', 1,
      'operation_id', 'reward-completion',
      'plan_id', 'reward-plan',
      'occurrence_id', 'reward-occurrence',
      'completed_at', clock_timestamp() - interval '1 minute',
      'time_zone_id', 'Asia/Baghdad',
      'notes', null
    ),
    'rpc-device'
  )->>'reward_eligibility_token' IS NOT NULL,
  'the final due occurrence issues account-bound reward eligibility'
);
select extensions.is(
  public.complete_maintenance_task(
    jsonb_build_object(
      'contract_version', 1,
      'operation_id', 'reward-loser',
      'plan_id', 'reward-plan',
      'occurrence_id', 'reward-occurrence',
      'completed_at', clock_timestamp() - interval '1 minute',
      'time_zone_id', 'Asia/Baghdad',
      'notes', null
    ),
    'rpc-device'
  )->>'reward_eligibility_token',
  null::text,
  'a losing completion operation cannot receive the winner reward token'
);

create temporary table maintenance_undo_payload(operation jsonb) on commit drop;
insert into maintenance_undo_payload(operation)
select jsonb_build_object(
  'contract_version', 1,
  'operation_id', 'undo:reward-completion',
  'plan_id', 'reward-plan',
  'completion_id', 'reward-completion',
  'completed_occurrence_id', 'reward-occurrence',
  'expected_current_occurrence_id', plan.current_occurrence_id,
  'previous_due_date', record.due_date,
  'expected_current_next_due_date', plan.next_due_date
)
from public.maintenance_plans plan
join public.maintenance_records record
  on record.user_id = plan.user_id
 and record.plan_id = plan.id
where plan.id = 'reward-plan' and record.id = 'reward-completion';

select extensions.is(
  public.undo_maintenance_completion(
    (select operation || jsonb_build_object(
      'expected_current_occurrence_id', 'wrong-successor'
    ) from maintenance_undo_payload),
    'rpc-device'
  )->>'conflict_reason',
  'stale_occurrence',
  'stale undo cannot rewind a newer occurrence'
);
select extensions.is(
  (select count(*)::integer from public.maintenance_records
   where id = 'reward-completion'),
  1,
  'stale undo does not delete canonical completion history'
);
select extensions.is(
  public.undo_maintenance_completion(
    (select operation from maintenance_undo_payload), 'rpc-device'
  )->>'status',
  'applied',
  'exact occurrence undo deletes the completion and rewinds the plan'
);
select extensions.is(
  public.undo_maintenance_completion(
    (select operation from maintenance_undo_payload), 'rpc-device'
  )->>'status',
  'already_applied',
  'exact undo replay is idempotent after response loss'
);

select * from extensions.finish();
rollback;
