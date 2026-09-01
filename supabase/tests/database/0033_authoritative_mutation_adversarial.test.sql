begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(24);

insert into auth.users (id, email) values
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'authority-adversary@example.invalid');
insert into public.areas(user_id, id, name) values
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'adversary-area', 'Area');
insert into public.rooms(user_id, id, area_id, name) values
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'adversary-room', 'adversary-area', 'Room');
insert into public.assets(user_id, id, room_id, name, asset_type) values
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'adversary-safety', 'adversary-room', 'Alarm', 'safety'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'adversary-general', 'adversary-room', 'Cabinet', 'general');
insert into public.maintenance_plans(
  user_id, id, asset_id, title, recurrence_interval, recurrence_unit,
  priority, next_due_date, archived_at
) values
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'adversary-active',
   'adversary-safety', 'Active task', 1, 'months', 'medium',
   '2026-10-01T00:00:00Z', null),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'adversary-archived',
   'adversary-safety', 'Archived task', 1, 'months', 'medium',
   '2026-10-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into owntend_monetization_private.maintenance_plan_entitlements(
  user_id, plan_id, paid_cost, origin
) values
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'adversary-active', 0, 'task_creation'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'adversary-archived', 0, 'task_creation');
update public.point_wallets
set balance = 1
where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}';

create temporary table changed_move(payload jsonb);
insert into changed_move values (jsonb_build_object(
  'operation_id', 'cccccccc-0000-4000-8000-000000000001',
  'request_hash', repeat('a', 64),
  'plan_id', 'adversary-active',
  'target_asset_id', 'adversary-general',
  'expected_plan_revision', 1,
  'max_charge', 0
));
select extensions.is(
  public.move_maintenance_plan_with_point_delta(
    (select payload from changed_move)
  )->>'status',
  'charge_changed',
  'a stale zero-price move quote is rejected'
);
select extensions.is(
  (select asset_id from public.maintenance_plans where id = 'adversary-active'),
  'adversary-safety',
  'charge_changed leaves the plan on its source asset'
);
set local role postgres;
select extensions.is(
  (select count(*)::integer
   from owntend_monetization_private.plan_economy_operations
   where operation_id = 'cccccccc-0000-4000-8000-000000000001'),
  0,
  'charge_changed writes no economy operation'
);
select extensions.is(
  (select count(*)::integer from public.point_transactions
   where idempotency_key = 'plan-move:cccccccc-0000-4000-8000-000000000001'),
  0,
  'charge_changed writes no point transaction'
);
select extensions.is(
  (select paid_cost::integer
   from owntend_monetization_private.maintenance_plan_entitlements
   where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
     and plan_id = 'adversary-active'),
  0,
  'charge_changed does not upgrade the entitlement'
);

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}';
select extensions.is(
  (public.quote_asset_type_change('adversary-safety', 'general')->>'charge')::integer,
  2,
  'asset type quote includes both active and archived under-entitled plans'
);
create temporary table insufficient_type(payload jsonb);
insert into insufficient_type
select jsonb_build_object(
  'operation_id', 'cccccccc-0000-4000-8000-000000000002',
  'request_hash', repeat('b', 64),
  'asset_id', a.id,
  'target_type', 'general',
  'details', '{}'::jsonb,
  'expected_asset_revision', a.revision,
  'max_charge', 2
)
from public.assets a where a.id = 'adversary-safety';
select extensions.is(
  public.change_asset_type_with_point_delta(
    (select payload from insufficient_type)
  )->>'status',
  'insufficient_points',
  'an aggregate type change fails atomically when its balance is insufficient'
);
select extensions.is(
  (select asset_type from public.assets where id = 'adversary-safety'),
  'safety',
  'insufficient balance leaves the asset type unchanged'
);
set local role postgres;
select extensions.is(
  (select balance from public.point_wallets
   where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
  1,
  'insufficient balance leaves the wallet unchanged'
);
select extensions.is(
  (select sum(paid_cost)::integer
   from owntend_monetization_private.maintenance_plan_entitlements
   where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
  0,
  'insufficient balance upgrades no active or archived entitlement'
);
select extensions.is(
  (select count(*)::integer
   from owntend_monetization_private.plan_economy_operations
   where operation_id = 'cccccccc-0000-4000-8000-000000000002'),
  0,
  'insufficient type change writes no economy operation'
);
select extensions.is(
  (select count(*)::integer from public.point_transactions
   where idempotency_key = 'asset-type:cccccccc-0000-4000-8000-000000000002'),
  0,
  'insufficient type change writes no point transaction'
);

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}';
create temporary table snapshot_conflict(payload jsonb);
insert into snapshot_conflict
select jsonb_build_object(
  'version', 1,
  'operation_id', 'cccccccc-0000-4000-8000-000000000003',
  'request_hash', repeat('c', 64),
  'plan_id', p.id,
  'expected_plan_revision', p.revision + 1,
  'plan_snapshot', jsonb_build_object(
    'asset_id', p.asset_id,
    'recurrence_interval', p.recurrence_interval,
    'recurrence_unit', p.recurrence_unit,
    'next_due_date', date_trunc('second', p.next_due_date),
    'is_enabled', p.is_enabled,
    'archived_at', p.archived_at
  ),
  'records', jsonb_build_array(jsonb_build_object(
    'id', 'snapshot-conflict-record',
    'operation_id', 'snapshot-conflict-record',
    'plan_id', p.id,
    'occurrence_id', 'snapshot-conflict-occurrence',
    'due_date', '2026-09-01T00:00:00Z',
    'completed_at', '2026-09-01T01:00:00Z',
    'accepted_at', '2026-09-01T01:00:00Z',
    'time_zone_id', 'UTC',
    'notes', null,
    'created_at', '2026-09-01T01:00:00Z',
    'revision', 1
  ))
)
from public.maintenance_plans p where p.id = 'adversary-active';
select extensions.is(
  public.restore_maintenance_history(
    (select payload from snapshot_conflict), 'adversarial-device'
  )->>'conflict_reason',
  'plan_snapshot_conflict',
  'a stale restore snapshot becomes an explicit conflict'
);
select extensions.is(
  (select count(*)::integer from public.maintenance_records
   where id = 'snapshot-conflict-record'),
  0,
  'snapshot conflict inserts no history row'
);
select extensions.is(
  (public.restore_maintenance_history(
    (select payload from snapshot_conflict), 'adversarial-device'
  )->>'already_processed')::boolean,
  true,
  'snapshot conflict is durable and exactly replayable'
);
set local role postgres;
select extensions.is(
  (select conflict_reason
   from owntend_private.maintenance_history_restore_operations
   where operation_id = 'cccccccc-0000-4000-8000-000000000003'),
  'plan_snapshot_conflict',
  'snapshot conflict is persisted in the private restore ledger'
);

insert into public.maintenance_records(
  user_id, id, plan_id, occurrence_id, completed_at, accepted_at,
  time_zone_id, notes, due_date, operation_id, revision, created_at, updated_at
) values (
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'existing-history',
  'adversary-active', 'existing-occurrence', '2026-08-01T01:00:00Z',
  '2026-08-01T01:00:00Z', 'UTC', 'cloud value',
  '2026-08-01T00:00:00Z', 'existing-history-operation', 1,
  '2026-08-01T01:00:00Z', '2026-08-01T01:00:00Z'
);
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}';
create temporary table record_conflict(payload jsonb);
insert into record_conflict
select jsonb_build_object(
  'version', 1,
  'operation_id', 'cccccccc-0000-4000-8000-000000000004',
  'request_hash', repeat('d', 64),
  'plan_id', p.id,
  'expected_plan_revision', p.revision,
  'plan_snapshot', jsonb_build_object(
    'asset_id', p.asset_id,
    'recurrence_interval', p.recurrence_interval,
    'recurrence_unit', p.recurrence_unit,
    'next_due_date', date_trunc('second', p.next_due_date),
    'is_enabled', p.is_enabled,
    'archived_at', p.archived_at
  ),
  'records', jsonb_build_array(
    jsonb_build_object(
      'id', 'existing-history',
      'operation_id', 'existing-history-operation',
      'plan_id', p.id,
      'occurrence_id', 'existing-occurrence',
      'due_date', '2026-08-01T00:00:00Z',
      'completed_at', '2026-08-01T01:00:00Z',
      'accepted_at', '2026-08-01T01:00:00Z',
      'time_zone_id', 'UTC',
      'notes', 'divergent backup value',
      'created_at', '2026-08-01T01:00:00Z',
      'revision', 1
    ),
    jsonb_build_object(
      'id', 'must-not-partially-insert',
      'operation_id', 'must-not-partially-insert',
      'plan_id', p.id,
      'occurrence_id', 'must-not-partially-insert-occurrence',
      'due_date', '2026-08-02T00:00:00Z',
      'completed_at', '2026-08-02T01:00:00Z',
      'accepted_at', '2026-08-02T01:00:00Z',
      'time_zone_id', 'UTC',
      'notes', null,
      'created_at', '2026-08-02T01:00:00Z',
      'revision', 1
    )
  )
)
from public.maintenance_plans p where p.id = 'adversary-active';
select extensions.is(
  public.restore_maintenance_history(
    (select payload from record_conflict), 'adversarial-device'
  )->>'conflict_reason',
  'history_record_conflict',
  'divergent cloud history becomes an explicit conflict'
);
select extensions.is(
  (select count(*)::integer from public.maintenance_records
   where id = 'must-not-partially-insert'),
  0,
  'a divergent restore batch inserts none of its missing rows'
);
select extensions.is(
  (public.restore_maintenance_history(
    (select payload from record_conflict), 'adversarial-device'
  )->>'already_processed')::boolean,
  true,
  'history record conflict is durable and exactly replayable'
);

select extensions.throws_ok(
  $$select public.copy_asset(jsonb_build_object(
    'operation_id', 'cccccccc-0000-4000-8000-000000000005',
    'request_hash', repeat('e', 64),
    'source_asset_id', 'adversary-safety',
    'target_asset_id', 'invalid-map-copy',
    'destination_room_id', 'adversary-room',
    'include_tasks', true,
    'plan_id_map', '{}'::jsonb
  ))$$,
  '22023', 'INVALID_PLAN_ID_MAP',
  'a copy map must exactly cover the active source plan set'
);
select extensions.is(
  (select count(*)::integer from public.assets where id = 'invalid-map-copy'),
  0,
  'an invalid copy map creates no target asset'
);

set local role postgres;
update public.monetization_config
set points_enabled = false, emergency_free_creation_mode = false
where singleton;
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}';
create temporary table disabled_points_move(payload jsonb);
insert into disabled_points_move values (jsonb_build_object(
  'operation_id', 'cccccccc-0000-4000-8000-000000000006',
  'request_hash', repeat('f', 64),
  'plan_id', 'adversary-active',
  'target_asset_id', 'adversary-general',
  'expected_plan_revision', 1,
  'max_charge', 0
));
select extensions.is(
  (public.move_maintenance_plan_with_point_delta(
    (select payload from disabled_points_move)
  )->>'charged')::integer,
  0,
  'points-disabled movement remains zero-cost'
);
select extensions.is(
  (select asset_id from public.maintenance_plans where id = 'adversary-active'),
  'adversary-general',
  'a valid points-disabled move still applies'
);
set local role postgres;
select extensions.is(
  (select paid_cost::integer
   from owntend_monetization_private.maintenance_plan_entitlements
   where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
     and plan_id = 'adversary-active'),
  0,
  'a zero-cost points-disabled move does not inflate paid entitlement'
);

select * from extensions.finish();
rollback;
