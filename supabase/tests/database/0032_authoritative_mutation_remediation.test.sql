begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(39);

select extensions.has_table(
  'owntend_monetization_private', 'maintenance_plan_entitlements',
  'private plan entitlements exist'
);
select extensions.has_table(
  'owntend_monetization_private', 'plan_economy_operations',
  'private economy operation ledger exists'
);
select extensions.has_table(
  'owntend_private', 'maintenance_history_restore_operations',
  'private history restore operation ledger exists'
);
select extensions.ok(
  not has_table_privilege('authenticated',
    'owntend_monetization_private.maintenance_plan_entitlements', 'SELECT'),
  'authenticated callers cannot read entitlements directly'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.maintenance_records', 'INSERT')
  and not has_table_privilege('authenticated', 'public.maintenance_records', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.maintenance_records', 'DELETE'),
  'maintenance history is read-only to authenticated table access'
);
select extensions.ok(
  not has_column_privilege('authenticated', 'public.maintenance_plans', 'asset_id', 'UPDATE')
  and has_column_privilege('authenticated', 'public.maintenance_plans', 'title', 'UPDATE'),
  'plan reparenting is RPC-only while safe edits remain available'
);
select extensions.ok(
  not has_column_privilege('authenticated', 'public.assets', 'asset_type', 'UPDATE')
  and has_column_privilege('authenticated', 'public.assets', 'name', 'UPDATE'),
  'asset type changes are RPC-only while safe edits remain available'
);
select extensions.ok(
  (select bool_and(not p.prosecdef)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in (
     'create_asset', 'create_task_with_point_debit',
     'get_charged_operation_status', 'prepare_asset_photo_upload',
     'copy_asset', 'quote_maintenance_plan_move',
     'move_maintenance_plan_with_point_delta', 'quote_asset_type_change',
     'change_asset_type_with_point_delta', 'restore_maintenance_history'
   )),
  'remediated public RPCs are SECURITY INVOKER wrappers'
);
select extensions.ok(
  (select bool_and(p.prosecdef and p.proconfig @> array['search_path=""'])
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in (
       'owntend_private', 'owntend_monetization_private', 'owntend_media_private'
     )
     and p.proname in (
       'create_asset_impl', 'create_task_with_point_debit_impl',
       'get_charged_operation_status', 'prepare_asset_photo_upload_impl',
       'copy_asset_impl', 'move_maintenance_plan_with_point_delta_impl',
       'change_asset_type_with_point_delta_impl',
       'restore_maintenance_history_impl', 'complete_maintenance_task_impl',
       'undo_maintenance_completion_impl'
     )),
  'new private implementations are pinned SECURITY DEFINER functions'
);

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'authority-a@example.invalid'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'authority-b@example.invalid');
insert into public.areas(user_id, id, name) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'area-a', 'Area A'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'area-b', 'Area B');
insert into public.rooms(user_id, id, area_id, name) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'room-a', 'area-a', 'Room A'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'room-a2', 'area-a', 'Room A2'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'room-b', 'area-b', 'Room B');
insert into public.assets(user_id, id, room_id, name, asset_type) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'safety-a', 'room-a', 'Alarm', 'safety'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'general-a', 'room-a2', 'Sofa', 'general'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'general-b', 'room-b', 'Other sofa', 'general');

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

select extensions.throws_ok(
  $$select public.create_asset(jsonb_build_object(
    'operation_id','aaaaaaaa-0000-4000-8000-000000000001',
    'request_hash',repeat('a',64),
    'asset',jsonb_build_object('id','bundle-bypass','name','Bypass',
      'asset_type','general','room_id','room-a'),
    'initial_plans',jsonb_build_array(jsonb_build_object('id','free-task'))
  ))$$,
  '22023', 'UNTRUSTED_INITIAL_PLANS',
  'arbitrary initial plan bundles are rejected'
);
select extensions.is(
  (select count(*)::integer from public.assets where id = 'bundle-bypass'), 0,
  'rejected bundles create no asset'
);

select extensions.is(
  (public.create_task_with_point_debit(jsonb_build_object(
    'operation_id','aaaaaaaa-0000-4000-8000-000000000002',
    'request_hash',repeat('b',64),
    'plan',jsonb_build_object(
      'id','free-safety-task','asset_id','safety-a','title','Test alarm',
      'recurrence_interval',1,'recurrence_unit','months','priority','high',
      'next_due_date','2026-10-01T00:00:00Z'
    )
  ))->>'charged')::integer,
  0,
  'a safety task receives a zero-cost server entitlement'
);
set local role postgres;
select extensions.is(
  (select paid_cost::integer
   from owntend_monetization_private.maintenance_plan_entitlements
   where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     and plan_id = 'free-safety-task'),
  0,
  'zero-cost task entitlement is durable'
);
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';
select extensions.is(
  (public.quote_maintenance_plan_move('free-safety-task','general-a')->>'charge')::integer,
  1,
  'moving the free safety task to a general asset quotes one point'
);

create temporary table move_request(payload jsonb);
insert into move_request values (jsonb_build_object(
  'operation_id','aaaaaaaa-0000-4000-8000-000000000003',
  'request_hash',repeat('c',64),
  'plan_id','free-safety-task','target_asset_id','general-a',
  'expected_plan_revision',1,'max_charge',1
));
select extensions.is(
  (public.move_maintenance_plan_with_point_delta(
    (select payload from move_request))->>'charged')::integer,
  1,
  'the move charges the entitlement delta once'
);
select extensions.is(
  (public.move_maintenance_plan_with_point_delta(
    (select payload from move_request))->>'already_processed')::boolean,
  true,
  'an exact move replay is idempotent'
);
select extensions.is(
  (select balance from public.point_wallets
   where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  6,
  'move replay does not debit twice'
);
set local role postgres;
select extensions.is(
  (select paid_cost::integer
   from owntend_monetization_private.maintenance_plan_entitlements
   where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     and plan_id = 'free-safety-task'),
  1,
  'move upgrades the entitlement monotonically'
);
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';
select extensions.throws_ok(
  $$update public.maintenance_plans set asset_id = 'safety-a'
    where id = 'free-safety-task'$$,
  '42501', 'permission denied for table maintenance_plans',
  'direct plan reparenting is denied'
);
select extensions.throws_ok(
  $$update public.assets set asset_type = 'safety' where id = 'general-a'$$,
  '42501', 'permission denied for table assets',
  'direct asset type changes are denied'
);

-- Copy content is derived from the owned source and its exact active plan set.
select extensions.is(
  (public.create_task_with_point_debit(jsonb_build_object(
    'operation_id','aaaaaaaa-0000-4000-8000-000000000004',
    'request_hash',repeat('d',64),
    'plan',jsonb_build_object(
      'id','copy-source-task','asset_id','safety-a','title','Copied alarm test',
      'recurrence_interval',1,'recurrence_unit','months','priority','medium',
      'next_due_date','2026-11-01T00:00:00Z'
    )
  ))->>'charged')::integer,
  0,
  'copy source has a server-created task'
);
create temporary table copy_request(payload jsonb);
insert into copy_request values (jsonb_build_object(
  'operation_id','aaaaaaaa-0000-4000-8000-000000000005',
  'request_hash',repeat('e',64),
  'source_asset_id','safety-a','target_asset_id','safety-copy',
  'destination_room_id','room-a2','include_tasks',true,
  'plan_id_map',jsonb_build_object('copy-source-task','copied-task')
));
select extensions.is(
  public.copy_asset((select payload from copy_request))->'asset'->>'name',
  'Alarm',
  'owned copy uses the server source asset name'
);
select extensions.is(
  (select count(*)::integer from public.maintenance_plans
   where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     and id = 'copied-task' and title = 'Copied alarm test'),
  1,
  'owned copy derives the exact source task body'
);
set local role postgres;
select extensions.is(
  (select origin from owntend_monetization_private.maintenance_plan_entitlements
   where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     and plan_id = 'copied-task'),
  'asset_copy',
  'copied tasks receive explicit free-copy provenance'
);
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';
select extensions.is(
  (public.copy_asset((select payload from copy_request))->>'already_processed')::boolean,
  true,
  'owned copy replay commits once'
);
select extensions.throws_ok(
  $$select public.copy_asset(jsonb_build_object(
    'operation_id','aaaaaaaa-0000-4000-8000-000000000006',
    'request_hash',repeat('f',64),'source_asset_id','general-b',
    'target_asset_id','cross-copy','destination_room_id','room-a',
    'include_tasks',false,'plan_id_map','{}'::jsonb))$$,
  '42501', 'SOURCE_ASSET_NOT_FOUND',
  'another tenant source cannot be copied'
);

select extensions.is(
  (public.quote_asset_type_change('safety-copy','general')->>'charge')::integer,
  1,
  'safety-to-general type change quotes every entitlement shortfall'
);
create temporary table type_request(payload jsonb);
insert into type_request
select jsonb_build_object(
  'operation_id','aaaaaaaa-0000-4000-8000-000000000007',
  'request_hash',repeat('1',64),'asset_id','safety-copy',
  'target_type','general','details','{}'::jsonb,
  'expected_asset_revision',revision,'max_charge',1
)
from public.assets
where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and id = 'safety-copy';
select extensions.is(
  (public.change_asset_type_with_point_delta(
    (select payload from type_request))->>'charged')::integer,
  1,
  'asset type change charges its aggregate shortfall'
);
select extensions.is(
  (select balance from public.point_wallets
   where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  5,
  'aggregate type change debits once'
);
select extensions.is(
  (public.change_asset_type_with_point_delta(
    (select payload from type_request))->>'already_processed')::boolean,
  true,
  'asset type change replay is idempotent'
);

select extensions.is(
  public.complete_maintenance_task(
    jsonb_build_object(
      'version',1,'operation_id','unauthorized-completion',
      'expected_next_due_date','2026-10-01T00:00:00Z',
      'plan',jsonb_build_object(
        'id','unauthorized-plan','asset_id','general-a','title','No debit',
        'recurrence_interval',1,'recurrence_unit','months','priority','medium',
        'next_due_date','2026-11-01T00:00:00Z','reminder_days_before',0,
        'is_enabled',true,'created_at','2026-09-01T00:00:00Z',
        'updated_at','2026-10-01T01:00:00Z','archived_at',null
      ),
      'record',jsonb_build_object(
        'id','unauthorized-record','plan_id','unauthorized-plan',
        'due_date','2026-10-01T00:00:00Z',
        'completed_at','2026-10-01T01:00:00Z'
      )
    ), 'authority-device'
  )->>'conflict_reason',
  'task_creation_not_authorized',
  'missing-plan completion requires exact task authorization'
);
select extensions.is(
  (select count(*)::integer from public.maintenance_plans
   where id = 'unauthorized-plan'), 0,
  'unauthorized completion creates no plan'
);
select extensions.is(
  (select count(*)::integer from public.maintenance_records
   where id = 'unauthorized-record'), 0,
  'unauthorized completion creates no history'
);
select extensions.throws_ok(
  $$insert into public.maintenance_records(
      user_id,id,plan_id,due_date,completed_at
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','direct-history',
      'free-safety-task',now(),now()
    )$$,
  '42501', 'permission denied for table maintenance_records',
  'direct history insertion is denied'
);

create temporary table restore_request(payload jsonb);
insert into restore_request
select jsonb_build_object(
  'version',1,'operation_id','aaaaaaaa-0000-4000-8000-000000000008',
  'request_hash',repeat('2',64),'plan_id',p.id,
  'expected_plan_revision',p.revision,
  'plan_snapshot',jsonb_build_object(
    'asset_id',p.asset_id,'recurrence_interval',p.recurrence_interval,
    'recurrence_unit',p.recurrence_unit,
    'next_due_date',date_trunc('second',p.next_due_date),
    'is_enabled',p.is_enabled,'archived_at',p.archived_at
  ),
  'records',jsonb_build_array(jsonb_build_object(
    'id','restored-record','operation_id','restored-operation',
    'plan_id',p.id,'due_date','2026-09-01T00:00:00Z',
    'completed_at','2026-09-01T01:00:00Z','notes',null,
    'created_at','2026-09-01T01:00:00Z','revision',1
  ))
)
from public.maintenance_plans p
where p.user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  and p.id = 'free-safety-task';
select extensions.is(
  (public.restore_maintenance_history(
    (select payload from restore_request),'authority-device')->>'inserted_count')::integer,
  1,
  'validated restore inserts an exact missing history row'
);
select extensions.is(
  (public.restore_maintenance_history(
    (select payload from restore_request),'authority-device')->>'already_processed')::boolean,
  true,
  'validated restore replay is idempotent'
);

set local role postgres;
update public.media_staging_objects
set expires_at = clock_timestamp() - interval '1 second'
where false;
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';
select extensions.lives_ok(
  $$select public.prepare_asset_photo_upload(
    'general-a','quota-photo',1024,'image/jpeg',repeat('3',64),'authority-media-0001'
  )$$,
  'media stage preparation succeeds'
);
create temporary table original_media_path as
select id, staging_path, attempt from public.media_staging_objects
where idempotency_key = 'authority-media-0001';
set local role postgres;
update public.media_staging_objects
set created_at = clock_timestamp() - interval '2 days',
    expires_at = clock_timestamp() - interval '1 day'
where idempotency_key = 'authority-media-0001';
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';
select extensions.is(
  public.prepare_asset_photo_upload(
    'general-a','quota-photo',1024,'image/jpeg',repeat('3',64),'authority-media-0001'
  )->>'status',
  'staged',
  'expired media idempotency retries become active again'
);
select extensions.ok(
  (select s.id = o.id and s.attempt = o.attempt + 1
          and s.staging_path <> o.staging_path
   from public.media_staging_objects s cross join original_media_path o
   where s.idempotency_key = 'authority-media-0001'),
  'expired retry keeps the stage identity and rotates its path'
);

select * from extensions.finish();
rollback;
