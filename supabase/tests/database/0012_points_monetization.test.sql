begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(85);

select extensions.has_table('public', 'point_wallets', 'point wallet table exists');
select extensions.has_table('public', 'point_transactions', 'point ledger table exists');
select extensions.has_table('public', 'reward_claim_requests', 'reward claim table exists');
select extensions.has_table(
  'public', 'maintenance_reward_eligibilities',
  'canonical completion reward eligibility table exists'
);
select extensions.hasnt_column(
  'public',
  'maintenance_plan_metadata',
  'dependency_plan_ids_json',
  'task dependency metadata is retired from the cloud schema'
);
select extensions.ok(
  pg_catalog.strpos(
    pg_catalog.pg_get_functiondef(
      'owntend_monetization_private.create_task_with_point_debit_impl(jsonb)'::regprocedure
    ),
    'dependency_plan_ids'
  ) = 0,
  'task creation no longer reads or writes dependency metadata'
);
select extensions.ok(
  pg_catalog.strpos(
    pg_catalog.pg_get_functiondef(
      'owntend_monetization_private.create_asset_impl(jsonb)'::regprocedure
    ),
    'dependency_plan_ids'
  ) = 0,
  'initial asset tasks no longer read or write dependency metadata'
);
select extensions.ok(
  (select bool_and(relrowsecurity)
   from pg_class
   where oid in (
     'public.point_wallets'::regclass,
     'public.point_transactions'::regclass,
     'public.reward_claim_requests'::regclass,
     'public.ad_reward_claims'::regclass,
     'public.creation_point_operations'::regclass,
     'public.monetization_config'::regclass,
     'public.monetization_events'::regclass
   )),
  'every monetization table has RLS enabled'
);
select extensions.is(
  (
    select count(*)::integer
    from (
      values
        ('ad_reward_claims'),
        ('creation_point_operations'),
        ('monetization_events')
    ) as advisor_tables(table_name)
    where not exists (
      select 1
      from pg_policy policies
      join pg_class tables on tables.oid = policies.polrelid
      join pg_namespace schemas on schemas.oid = tables.relnamespace
      where schemas.nspname = 'public'
        and tables.relname = advisor_tables.table_name
    )
  ),
  0,
  'internal monetization tables have explicit RLS policies'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.ad_reward_claims', 'SELECT')
  and not has_table_privilege(
    'authenticated',
    'public.creation_point_operations',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.monetization_events',
    'SELECT'
  ),
  'advisor RLS policies do not grant client table reads'
);
select extensions.is(
  (
    select count(*)::integer
    from pg_proc functions
    join pg_namespace schemas on schemas.oid = functions.pronamespace
    where schemas.nspname = 'public'
      and functions.proname in (
        'create_asset',
        'create_reward_claim_request',
        'create_task_with_point_debit',
        'record_monetization_event'
      )
      and not functions.prosecdef
      and has_function_privilege('authenticated', functions.oid, 'EXECUTE')
  ),
  4,
  'authenticated point RPCs are security invoker delegations in public'
);
select extensions.is(
  (
    select count(*)::integer
    from pg_proc functions
    join pg_namespace schemas on schemas.oid = functions.pronamespace
    where schemas.nspname = 'owntend_monetization_private'
      and functions.proname in (
        'create_asset_impl',
        'create_reward_claim_request_impl',
        'create_task_with_point_debit_impl',
        'record_monetization_event_impl'
      )
      and functions.prosecdef
      and has_function_privilege('authenticated', functions.oid, 'EXECUTE')
  ),
  4,
  'privileged point implementations stay definer in the private schema and serve authenticated callers'
);
select extensions.ok(
  exists (
    select 1
    from pg_constraint constraints
    join pg_class tables on tables.oid = constraints.conrelid
    join pg_namespace schemas on schemas.oid = tables.relnamespace
    join pg_index indexes on indexes.indrelid = constraints.conrelid
    where schemas.nspname = 'public'
      and tables.relname = 'ad_reward_claims'
      and constraints.conname = 'ad_reward_claims_user_id_fkey'
      and constraints.contype = 'f'
      and indexes.indisvalid
      and indexes.indisready
      and (
        string_to_array(indexes.indkey::text, ' ')::smallint[]
      )[1] = constraints.conkey[1]
  ),
  'ad reward Auth foreign key has a covering index'
);
select extensions.ok(
  has_table_privilege('authenticated', 'public.point_wallets', 'SELECT'),
  'authenticated users can read their wallet'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.point_wallets', 'UPDATE'),
  'clients cannot mutate wallet balances'
);
select extensions.ok(
  not has_table_privilege(
    'authenticated', 'public.monetization_config', 'UPDATE'
  ),
  'clients cannot alter monetization kill switches or limits'
);
select extensions.ok(
  not (has_table_privilege('authenticated', 'public.assets', 'INSERT')),
  'direct asset INSERT is revoked; creation goes through the aggregate RPC'
);
select extensions.has_function(
  'public', 'create_asset', array['jsonb'],
  'atomic asset creation RPC exists'
);
select extensions.has_function(
  'public', 'create_task_with_point_debit', array['jsonb'],
  'atomic task creation RPC exists'
);
select extensions.has_function(
  'public', 'create_reward_claim_request', array['text', 'text', 'uuid'],
  'reward claim request RPC exists'
);
select extensions.ok(
  has_function_privilege(
    'service_role',
    'public.process_admob_ssv_reward(text,uuid,uuid,text,integer,text,timestamptz)',
    'EXECUTE'
  ) and not has_function_privilege(
    'authenticated',
    'public.process_admob_ssv_reward(text,uuid,uuid,text,integer,text,timestamptz)',
    'EXECUTE'
  ),
  'SSV settlement is service-role only'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000',
    '44444444-4444-4444-4444-444444444444',
    'authenticated', 'authenticated', 'points-one@example.test', '',
    now(), now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '55555555-5555-5555-5555-555555555555',
    'authenticated', 'authenticated', 'points-two@example.test', '',
    now(), now(), now()
  );

insert into public.areas (
  user_id, id, name, kind, sort_order, created_at, updated_at
) values (
  '44444444-4444-4444-4444-444444444444',
  'points-area', 'Points test area', 'indoor', 0, now(), now()
);
insert into public.rooms (
  user_id, id, area_id, name, room_type, sort_order, created_at, updated_at
) values (
  '44444444-4444-4444-4444-444444444444',
  'points-room', 'points-area', 'Points test room', 'other', 0, now(), now()
);

create temporary table monetization_test_claim (payload jsonb);
create temporary table monetization_test_claim_regular_two (payload jsonb);
create temporary table monetization_test_claim_daily (payload jsonb);
grant all on monetization_test_claim,
  monetization_test_claim_regular_two,
  monetization_test_claim_daily to authenticated, service_role;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '44444444-4444-4444-4444-444444444444',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

select extensions.is(
  (select balance from public.point_wallets)::integer,
  7,
  'a new account starts with seven points'
);
select extensions.is(
  (select count(*) from public.point_transactions
   where transaction_type = 'initial_grant')::integer,
  1,
  'the starting grant is recorded exactly once'
);

select extensions.is(
  (
    public.create_asset(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000001',
        'request_hash', 'c813adc62ab3f9d608220e84a969c7055803e54847eb667ece9e427f498a0b7d',
        'asset', jsonb_build_object(
          'id', 'points-general-asset',
          'name', 'General item',
          'asset_type', 'general',
          'room_id', 'points-room'
        ),
        'initial_plans', jsonb_build_array()
      )
    )->>'charged'
  )::integer,
  0,
  'ordinary asset creation is free (0 points)'
);
select extensions.is(
  (select balance from public.point_wallets)::integer,
  7,
  'asset creation does not debit the wallet'
);
select extensions.is(
  (select count(*) from public.maintenance_plans
   where asset_id = 'points-general-asset'
     and id in ('points-bundled-task-one', 'points-bundled-task-two'))::integer,
  0,
  'ordinary asset creation cannot smuggle maintenance plans'
);
select extensions.is(
  (select count(*) from public.point_transactions
   where transaction_type = 'asset_creation'
     and reference_id = 'points-general-asset')::integer,
  0,
  'free asset creation produces no negative point transaction'
);
select extensions.is(
  (
    public.create_asset(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000001',
        'request_hash', 'c813adc62ab3f9d608220e84a969c7055803e54847eb667ece9e427f498a0b7d',
        'asset', jsonb_build_object(
          'id', 'points-general-asset',
          'name', 'General item',
          'asset_type', 'general',
          'room_id', 'points-room'
        ),
        'initial_plans', jsonb_build_array()
      )
    )->>'already_processed'
  )::boolean,
  true,
  'replaying an asset operation is idempotent'
);
select extensions.is(
  (select count(*) from public.assets where id = 'points-general-asset')::integer,
  1,
  'an idempotent asset replay creates no duplicate'
);

select extensions.is(
  (
    select data_type
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'device_details'
      and column_name = 'consumable'
  ),
  'text',
  'device consumable uses the same text contract as Flutter and Drift'
);
select extensions.is(
  (
    select is_nullable
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'device_details'
      and column_name = 'consumable'
  ),
  'YES',
  'device consumable remains optional'
);
select extensions.is(
  (
    public.create_asset(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000009',
        'request_hash', 'a0bdc12ffb7f4d8ccbc5063a44b3745937acce7ce89a27f5ca4b8e5ae9d970aa',
        'asset', jsonb_build_object(
          'id', 'points-device-asset',
          'name', 'Air purifier',
          'asset_type', 'device',
          'room_id', 'points-room',
          'placement', 'Utility shelf'
        ),
        'details', jsonb_build_object(
          'brand', 'Example',
          'power_source', 'mains',
          'consumable', 'HEPA filter'
        )
      )
    )->>'asset_id'
  ),
  'points-device-asset',
  'device creation accepts descriptive consumable text'
);
select extensions.is(
  (select placement from public.assets where id = 'points-device-asset'),
  'Utility shelf',
  'asset creation RPC persists placement'
);
select extensions.is(
  (select consumable from public.device_details where asset_id = 'points-device-asset'),
  'HEPA filter',
  'asset creation RPC preserves descriptive consumable text'
);

select extensions.is(
  (
    public.create_task_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000002',
        'request_hash', '9ac37a595de21e379e34080d15c2a666bb361ce2aa6c61c9cf8cfa7db70e468f',
        'plan', jsonb_build_object(
          'id', 'points-general-task',
          'asset_id', 'points-general-asset',
          'title', 'General task',
          'instructions', 'Inspect the general asset',
          'recurrence_interval', 1,
          'recurrence_unit', 'months',
          'priority', 'medium',
          'next_due_date', now() + interval '1 day',
          'reminder_days_before', 0
        )
      )
    )->>'charged'
  )::integer,
  1,
  'ordinary task creation costs one point'
);
select extensions.is(
  (select instructions from public.maintenance_plans where id = 'points-general-task'),
  'Inspect the general asset',
  'task creation preserves the Flutter instructions field in the cloud alias'
);
select extensions.is(
  (select balance from public.point_wallets)::integer,
  6,
  'task creation debits the wallet atomically'
);

select extensions.is(
  (
    public.create_asset(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000003',
        'request_hash', '7f7756932bfdfe6138ec4be10299f6e345b7b073e2396f9e11284a054491443d',
        'asset', jsonb_build_object(
          'id', 'points-safety-asset',
          'name', 'Smoke alarm',
          'asset_type', 'safety',
          'room_id', 'points-room'
        ),
        'details', jsonb_build_object(
          'safety_type', 'smoke_alarm',
          'installed_at', '2026-08-15T10:00:00Z',
          'expires_at', '2036-08-15T10:00:00Z',
          'battery_type', 'AA',
          'test_interval_days', 30
        )
      )
    )->>'charged'
  )::integer,
  0,
  'server-derived safety asset creation is free'
);
select extensions.is(
  (
    select jsonb_build_object(
      'safety_type', safety_type,
      'battery_type', battery_type,
      'test_interval_days', test_interval_days
    )
    from public.safety_details
    where asset_id = 'points-safety-asset'
  ),
  '{"safety_type":"smoke_alarm","battery_type":"AA","test_interval_days":30}'::jsonb,
  'asset creation preserves Flutter safety detail fields'
);
select extensions.is(
  (select balance from public.point_wallets)::integer,
  6,
  'a safety asset does not change the balance'
);
select extensions.is(
  (
    public.create_task_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000004',
        'request_hash', 'b3d88703c7b92efe53382222cb5b4b6c3c9c0463f41f2df8dfba13bb961b601a',
        'plan', jsonb_build_object(
          'id', 'points-safety-task',
          'asset_id', 'points-safety-asset',
          'title', 'Test smoke alarm',
          'recurrence_interval', 1,
          'recurrence_unit', 'months',
          'priority', 'critical',
          'next_due_date', now() + interval '1 day',
          'reminder_days_before', 0
        )
      )
    )->>'charged'
  )::integer,
  0,
  'task safety is derived from its owned asset and is free'
);
select extensions.is(
  (select balance from public.point_wallets)::integer,
  6,
  'a safety task does not change the balance'
);
select extensions.is(
  (select count(*) from public.point_transactions)::integer,
  2,
  'only the starting grant and one charged task creation enter the ledger'
);

select extensions.throws_ok(
  $$insert into public.maintenance_plans (
      user_id, id, asset_id, title, recurrence_interval, recurrence_unit,
      priority, created_at, updated_at
    ) values (
      '44444444-4444-4444-4444-444444444444', 'bypass-task',
      'points-general-asset', 'Bypass task', 1, 'months', 'medium', now(), now()
    )$$,
  '42501',
  null,
  'direct charged task inserts are denied'
);
select extensions.lives_ok(
  $$insert into public.maintenance_plans
      select * from public.maintenance_plans
      where user_id = '44444444-4444-4444-4444-444444444444'
        and id = 'points-general-task'
      on conflict (user_id, id) do update
      set title = excluded.title$$,
  'offline sync can reconcile a task already created by the atomic RPC'
);

insert into monetization_test_claim (payload)
select public.create_reward_claim_request('rewarded_ad', 'Asia/Baghdad', null);
select extensions.is(
  (select (payload->>'reward_amount')::integer from monetization_test_claim),
  1,
  'a standard rewarded ad claim is worth one point'
);

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.is(
  (
    public.process_admob_ssv_reward(
      'test-transaction-1',
      (select (payload->>'claim_id')::uuid from monetization_test_claim),
      '44444444-4444-4444-4444-444444444444',
      'ca-app-pub-5274007212820203/4541482404',
      1,
      'points',
      now()
    )->>'credited'
  )::boolean,
  true,
  'a valid verified SSV callback credits the wallet'
);
set local role postgres;
select extensions.is(
  (select balance from public.point_wallets
   where user_id = '44444444-4444-4444-4444-444444444444')::integer,
  7,
  'the reward credit is persisted'
);

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.is(
  (
    public.process_admob_ssv_reward(
      'test-transaction-1',
      (select (payload->>'claim_id')::uuid from monetization_test_claim),
      '44444444-4444-4444-4444-444444444444',
      'ca-app-pub-5274007212820203/4541482404',
      1,
      'points',
      now()
    )->>'duplicate'
  )::boolean,
  true,
  'an SSV retry creates no duplicate reward claim'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.throws_ok(
  $$select public.create_reward_claim_request('rewarded_ad', 'Asia/Baghdad', null)$$,
  'P0001',
  'REWARD_COOLDOWN',
  'a regular reward is limited only by the configured cooldown'
);

set local role postgres;
update public.reward_claim_requests
set created_at = now() - interval '46 seconds'
where user_id = '44444444-4444-4444-4444-444444444444';
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
insert into monetization_test_claim_regular_two (payload)
select public.create_reward_claim_request('rewarded_ad', 'Asia/Baghdad', null);
select extensions.is(
  (
    select (payload->>'reward_amount')::integer
    from monetization_test_claim_regular_two
  ),
  1,
  'regular rewarded ads remain renewable on the same local day'
);

set local role postgres;
update public.reward_claim_requests
set created_at = now() - interval '46 seconds'
where user_id = '44444444-4444-4444-4444-444444444444';
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.lives_ok(
  $$select public.create_reward_claim_request('rewarded_ad', 'Asia/Baghdad', null)$$,
  'a delayed SSV callback does not block a later claim after cooldown'
);
select extensions.is(
  (select count(*) from public.reward_claim_requests
   where status = 'pending')::integer,
  2,
  'multiple short-lived pending claims can coexist safely'
);

set local role postgres;
update public.reward_claim_requests
set created_at = now() - interval '46 seconds'
where user_id = '44444444-4444-4444-4444-444444444444';
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.throws_ok(
  $$select public.create_reward_claim_request(
      'rewarded_interstitial', 'Asia/Baghdad', null
    )$$,
  'P0001',
  'REWARD_ELIGIBILITY_REQUIRED',
  'a two-point reward cannot be created without canonical completion eligibility'
);

set local role postgres;
insert into public.maintenance_records (
  user_id, id, plan_id, occurrence_id, due_date, completed_at, accepted_at,
  time_zone_id, operation_id
) values (
  '44444444-4444-4444-4444-444444444444',
  'daily-eligible-completion',
  'points-general-task',
  'daily-eligible-occurrence',
  now() - interval '1 hour',
  now() - interval '1 minute',
  now() - interval '1 minute',
  'Asia/Baghdad',
  'daily-eligible-completion'
);
insert into public.maintenance_reward_eligibilities (
  token, user_id, completion_id, reward_day, time_zone_id, expires_at
) values (
  '44444444-4444-4444-8444-444444444440',
  '44444444-4444-4444-4444-444444444444',
  'daily-eligible-completion',
  (clock_timestamp() at time zone 'Asia/Baghdad')::date,
  'Asia/Baghdad',
  clock_timestamp() + interval '30 minutes'
);
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '55555555-5555-5555-5555-555555555555',
  true
);
select extensions.throws_ok(
  $$select public.create_reward_claim_request(
      'rewarded_interstitial', 'Asia/Baghdad',
      '44444444-4444-4444-8444-444444444440'
    )$$,
  'P0001',
  'REWARD_NOT_ELIGIBLE',
  'another account cannot consume a completion eligibility token'
);
select set_config(
  'request.jwt.claim.sub',
  '44444444-4444-4444-4444-444444444444',
  true
);
insert into monetization_test_claim_daily (payload)
select public.create_reward_claim_request(
  'rewarded_interstitial', 'Asia/Baghdad',
  '44444444-4444-4444-8444-444444444440'
);
select extensions.is(
  (select (payload->>'reward_amount')::integer from monetization_test_claim_daily),
  2,
  'the daily completion rewarded interstitial is worth two points'
);

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.is(
  (
    public.process_admob_ssv_reward(
      'test-transaction-daily-1',
      (select (payload->>'claim_id')::uuid from monetization_test_claim_daily),
      '44444444-4444-4444-4444-444444444444',
      'ca-app-pub-5274007212820203/7295784043',
      2,
      'points',
      now()
    )->>'credited'
  )::boolean,
  true,
  'a verified daily completion callback credits exactly two points'
);
set local role postgres;
select extensions.is(
  (select balance from public.point_wallets
   where user_id = '44444444-4444-4444-4444-444444444444')::integer,
  9,
  'the daily completion reward updates the cached wallet'
);
update public.reward_claim_requests
set created_at = now() - interval '46 seconds'
where user_id = '44444444-4444-4444-4444-444444444444';
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.throws_ok(
  $$select public.create_reward_claim_request(
      'rewarded_interstitial', 'Asia/Baghdad',
      '44444444-4444-4444-8444-444444444440'
    )$$,
  'P0001',
  'REWARD_ELIGIBILITY_USED',
  'a consumed completion eligibility cannot create another reward claim'
);

select set_config(
  'request.jwt.claim.sub',
  '55555555-5555-5555-5555-555555555555',
  true
);
select extensions.is(
  (select count(*) from public.point_wallets)::integer,
  1,
  'RLS exposes only the caller wallet'
);
select set_config(
  'request.jwt.claim.sub',
  '44444444-4444-4444-4444-444444444444',
  true
);
select extensions.lives_ok(
  $$select public.record_monetization_event(
      'points_debited', jsonb_build_object('entity_type','asset_copy','entity_id',
        '11111111-1111-5111-8111-111111111111','cost',0,'new_balance',0,'included_task_count',0)
    )$$,
  'allowlisted analytics events can be recorded'
);

set local role postgres;
select extensions.is(
  (select count(*) from public.monetization_events
   where event_name = 'points_debited')::integer,
  1,
  'analytics events are stored server-side'
);
select extensions.is(
  (select wallet_cap from public.monetization_config where singleton),
  20,
  'the production wallet cap defaults to twenty'
);
select extensions.lives_ok(
  $$update public.monetization_config set wallet_cap = 25 where singleton$$,
  'the service-side wallet cap is remotely configurable'
);
select extensions.is(
  (select wallet_cap from public.monetization_config where singleton),
  25,
  'a remote wallet cap update is persisted'
);
select extensions.lives_ok(
  $$insert into public.point_transactions (
      user_id, amount, balance_before, balance_after, transaction_type,
      idempotency_key
    ) values (
      '44444444-4444-4444-4444-444444444444', 16, 8, 24,
      'admin_adjustment', 'database-test-cap-24'
    );
    update public.point_wallets set balance = 24
    where user_id = '44444444-4444-4444-4444-444444444444'$$,
  'ledger and wallet storage accept a balance above the old fixed cap'
);
select extensions.is(
  (select balance from public.point_wallets
   where user_id = '44444444-4444-4444-4444-444444444444')::integer,
  24,
  'the remotely configured wallet cap is effective in storage'
);
delete from public.point_transactions
where idempotency_key = 'database-test-cap-24';
update public.point_wallets set balance = 8
where user_id = '44444444-4444-4444-4444-444444444444';
update public.monetization_config set wallet_cap = 20 where singleton;

update public.point_wallets set balance = 0
where user_id = '44444444-4444-4444-4444-444444444444';
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '44444444-4444-4444-4444-444444444444',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.is(
  (
    public.create_task_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000005',
        'request_hash', '5f71738f287b2e14234dd045d2386fca50c25aa5c0316acf39922a9fc2b59f17',
        'plan', jsonb_build_object(
          'id', 'points-insufficient-task',
          'asset_id', 'points-general-asset',
          'title', 'Must not be created',
          'recurrence_interval', 1,
          'recurrence_unit', 'days',
          'priority', 'low',
          'next_due_date', now() + interval '1 day'
        )
      )
    )->>'status'
  ),
  'insufficient_points',
  'insufficient points are a structured task-creation business result'
);
select extensions.is(
  (select count(*) from public.maintenance_plans
   where id = 'points-insufficient-task')::integer,
  0,
  'a rejected debit leaves no task behind'
);
select extensions.is(
  (
    public.create_asset(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000008',
        'request_hash', 'fb8baaa2045157233d22b1d6b5d19a2d0ace94ff77405be3db2f6dce6da81a86',
        'asset', jsonb_build_object(
          'id', 'points-zero-wallet-asset',
          'name', 'Created with zero points',
          'asset_type', 'general',
          'room_id', 'points-room'
        )
      )
    )->>'charged'
  )::integer,
  0,
  'asset creation succeeds with zero wallet balance at 0 points'
);
select extensions.is(
  (select count(*) from public.assets
   where id = 'points-zero-wallet-asset')::integer,
  1,
  'an asset is successfully created even with 0 points balance'
);

set local role postgres;
update public.monetization_config
set emergency_free_creation_mode = true
where singleton;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.is(
  (
    public.create_task_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000006',
        'request_hash', '439b51ebcce5f41b1d3e09c65c32d82a43e66fd127ff398823ec1a74d66a878c',
        'plan', jsonb_build_object(
          'id', 'points-emergency-free-task',
          'asset_id', 'points-general-asset',
          'title', 'Emergency free task',
          'recurrence_interval', 1,
          'recurrence_unit', 'days',
          'priority', 'low',
          'next_due_date', now() + interval '1 day'
        )
      )
    )->>'charged'
  )::integer,
  0,
  'the emergency kill switch makes ordinary creation free'
);
select extensions.is(
  (select count(*) from public.maintenance_plans
   where id = 'points-emergency-free-task')::integer,
  1,
  'emergency free creation still commits the requested task atomically'
);
select extensions.is(
  (select balance from public.point_wallets)::integer,
  0,
  'emergency free creation never creates point debt'
);

set local role postgres;
update public.monetization_config
set emergency_free_creation_mode = false, points_enabled = false
where singleton;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.is(
  (
    public.create_task_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000007',
        'request_hash', '25a92381c8487426df847c8fc8846718ca5d84d21aa4807b630e7d952af25cb3',
        'plan', jsonb_build_object(
          'id', 'points-disabled-free-task',
          'asset_id', 'points-general-asset',
          'title', 'Points disabled free task',
          'recurrence_interval', 1,
          'recurrence_unit', 'days',
          'priority', 'low',
          'next_due_date', now() + interval '1 day'
        )
      )
    )->>'charged'
  )::integer,
  0,
  'the points kill switch makes ordinary creation free'
);
select extensions.is(
  (select count(*) from public.maintenance_plans
   where id = 'points-disabled-free-task')::integer,
  1,
  'points-disabled mode still commits the requested task'
);

set local role postgres;
update public.monetization_config
set points_enabled = true, rewarded_ads_enabled = false
where singleton;
update public.reward_claim_requests
set created_at = now() - interval '46 seconds'
where user_id = '44444444-4444-4444-4444-444444444444';
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.throws_ok(
  $$select public.create_reward_claim_request('rewarded_ad', 'Asia/Baghdad', null)$$,
  'P0001',
  'REWARDS_DISABLED',
  'the rewarded-ad kill switch rejects new claims server-side'
);
set local role postgres;
update public.monetization_config set rewarded_ads_enabled = true
where singleton;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.throws_ok(
  $$select public.record_monetization_event('not_allowed', '{}'::jsonb)$$,
  '22023',
  'INVALID_EVENT',
  'analytics rejects unknown event names'
);
select extensions.throws_ok(
  $$update public.point_wallets set balance = 20$$,
  '42501',
  null,
  'clients cannot update their wallet through the Data API role'
);

-- CTC-001 & CTC-004 & CTR-003 tests
set local role postgres;
update public.point_wallets
set balance = 1000
where user_id = '44444444-4444-4444-4444-444444444444';
set local role authenticated;
select set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);

select extensions.is(
  (
    public.create_task_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000088',
        'request_hash', 'b25a0a56459301efdbefa58c13b1c89c9d8d9f379474ea5fd03bc0a31f879b90',
        'plan', jsonb_build_object(
          'id', 'ctc-001-metadata-task',
          'asset_id', 'points-general-asset',
          'title', 'Task with metadata',
          'recurrence_interval', 1,
          'recurrence_unit', 'days',
          'priority', 'medium',
          'next_due_date', now() + interval '1 day'
        ),
        'metadata', jsonb_build_object(
          'task_type', 'inspection',
          'location_label', 'Utility room',
          'reminder_recommendation', 'Check monthly',
          'required_materials', jsonb_build_array('Wrench', 'Screwdriver')
        )
      )
    )->>'task_id'
  ),
  'ctc-001-metadata-task',
  'create_task_with_point_debit handles metadata subquery without 42702 error (CTC-001)'
);
select extensions.is(
  (
    select jsonb_build_object(
      'location_label', location_label,
      'required_materials_json', required_materials_json,
      'reminder_recommendation', reminder_recommendation
    )
    from public.maintenance_plan_metadata
    where plan_id = 'ctc-001-metadata-task'
  ),
  '{"location_label":"Utility room","required_materials_json":"[\"Wrench\", \"Screwdriver\"]","reminder_recommendation":"Check monthly"}'::jsonb,
  'task creation preserves Flutter maintenance metadata fields'
);

select extensions.throws_ok(
  $$
    with auth_setup as (
      select set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true)
    )
    select public.create_task_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000088',
        'request_hash', 'b25a0a56459301efdbefa58c13b1c89c9d8d9f379474ea5fd03bc0a31f879b90',
        'plan', jsonb_build_object(
          'id', 'different-task-id',
          'asset_id', 'points-general-asset',
          'title', 'Different task title',
          'recurrence_interval', 1,
          'recurrence_unit', 'days',
          'priority', 'medium',
          'next_due_date', now() + interval '1 day'
        )
      )
    )
    from auth_setup
  $$,
  '23505',
  'OPERATION_ID_REUSED',
  'reusing operation ID with a different payload is rejected (CTC-004)'
);

select extensions.throws_ok(
  $$
    with auth_setup as (
      select set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true)
    )
    select public.create_task_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000089',
        'request_hash', 'c089d0be5e93e93d6160fd7310c5d84f8d7e5b189290606c80335630a77197e5',
        'plan', jsonb_build_object(
          'id', 'ctr-003-invalid-meta-task',
          'asset_id', 'points-general-asset',
          'title', 'Invalid metadata task',
          'recurrence_interval', 1,
          'recurrence_unit', 'days',
          'priority', 'medium',
          'next_due_date', now() + interval '1 day'
        ),
        'metadata', jsonb_build_object(
          'required_materials', 'not-an-array'
        )
      )
    )
    from auth_setup
  $$,
  '22023',
  'INVALID_TASK_PAYLOAD',
  'invalid non-array metadata fields are rejected (CTR-003)'
);

select extensions.is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'maintenance_plans'
      and column_name = 'health_group'
  ),
  0,
  'maintenance_plans no longer persists health_group'
);

set local role postgres;
select extensions.ok(
  position(
    'plan_json ? ''health_group''' in
    pg_get_functiondef('owntend_monetization_private.create_task_with_point_debit_impl(jsonb)'::regprocedure)
  ) > 0,
  'task creation rejects the obsolete client health_group classifier'
);

select * from extensions.finish();
rollback;
