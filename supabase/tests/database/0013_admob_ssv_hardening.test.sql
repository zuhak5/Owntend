begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(14);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '77777777-7777-4777-8777-777777777777',
  'authenticated', 'authenticated', 'ssv-hardening@example.test', '',
  now(), now(), now()
);

insert into public.reward_claim_requests (
  claim_id, user_id, reward_type, ad_unit_id, reward_amount,
  status, reward_day, expires_at, created_at
) values (
  '88888888-8888-4888-8888-888888888888',
  '77777777-7777-4777-8777-777777777777',
  'rewarded_ad',
  'ca-app-pub-5274007212820203/4541482404',
  1, 'pending', (timezone('utc', now()))::date,
  now() + interval '15 minutes', now()
);

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select extensions.throws_ok(
  $$select public.process_admob_ssv_reward(
      'ssv-null-user',
      '88888888-8888-4888-8888-888888888888', null::uuid,
      'ca-app-pub-5274007212820203/4541482404', 1, 'points', now()
    )$$,
  '22023', 'INVALID_SSV_PAYLOAD',
  'null signed user IDs fail closed at the database boundary'
);

select extensions.throws_ok(
  $$select public.process_admob_ssv_reward(
      'ssv-invalid-unit',
      '88888888-8888-4888-8888-888888888888',
      '77777777-7777-4777-8777-777777777777',
      'ca-app-pub-5274007212820203/9999999999', 1, 'points', now()
    )$$,
  '22023', 'INVALID_SSV_PAYLOAD',
  'the RPC independently rejects unknown ad units'
);

select extensions.throws_ok(
  $$select public.process_admob_ssv_reward(
      'ssv-invalid-amount',
      '88888888-8888-4888-8888-888888888888',
      '77777777-7777-4777-8777-777777777777',
      'ca-app-pub-5274007212820203/4541482404', 2, 'points', now()
    )$$,
  '22023', 'INVALID_SSV_PAYLOAD',
  'the RPC derives and enforces the amount for each ad unit'
);

select extensions.throws_ok(
  $$select public.process_admob_ssv_reward(
      'ssv-future',
      '88888888-8888-4888-8888-888888888888',
      '77777777-7777-4777-8777-777777777777',
      'ca-app-pub-5274007212820203/4541482404', 1, 'points',
      now() + interval '6 minutes'
    )$$,
  '22023', 'INVALID_SSV_PAYLOAD',
  'timestamps beyond the clock-skew allowance are rejected'
);

select extensions.throws_ok(
  $$select public.process_admob_ssv_reward(
      'ssv-expired',
      '88888888-8888-4888-8888-888888888888',
      '77777777-7777-4777-8777-777777777777',
      'ca-app-pub-5274007212820203/4541482404', 1, 'points',
      now() - interval '21 minutes'
    )$$,
  '22023', 'SSV_TIMESTAMP_EXPIRED',
  'a new transaction with an expired Google timestamp is rejected'
);

select extensions.is(
  (
    public.process_admob_ssv_reward(
      'ssv-valid-transaction',
      '88888888-8888-4888-8888-888888888888',
      '77777777-7777-4777-8777-777777777777',
      'ca-app-pub-5274007212820203/4541482404', 1, 'points', now()
    )->>'credited'
  )::boolean,
  true,
  'a fresh valid callback is credited'
);

select extensions.is(
  (
    public.process_admob_ssv_reward(
      'ssv-valid-transaction',
      '88888888-8888-4888-8888-888888888888',
      '77777777-7777-4777-8777-777777777777',
      'ca-app-pub-5274007212820203/4541482404', 1, 'points',
      now()
    )->>'duplicate'
  )::boolean,
  true,
  'an exact signed transaction replay is an idempotent success'
);

set local role postgres;
select extensions.is(
  (select balance from public.point_wallets
   where user_id = '77777777-7777-4777-8777-777777777777')::integer,
  8,
  'the exact replay does not add a second point'
);
select extensions.is(
  (select count(*) from public.ad_reward_claims
   where user_id = '77777777-7777-4777-8777-777777777777')::integer,
  1,
  'the exact replay creates one immutable AdMob claim'
);
select extensions.is(
  (select count(*) from public.point_transactions
   where user_id = '77777777-7777-4777-8777-777777777777'
     and transaction_type = 'rewarded_ad')::integer,
  1,
  'the exact replay creates one reward ledger transaction'
);

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.throws_ok(
  $$select public.process_admob_ssv_reward(
      'ssv-valid-transaction',
      '88888888-8888-4888-8888-888888888888',
      '77777777-7777-4777-8777-777777777777',
      'ca-app-pub-5274007212820203/4541482404', 1, 'points',
      now() + interval '1 millisecond'
    )$$,
  '23505', 'TRANSACTION_ID_REUSED',
  'a transaction ID replay with a changed signed timestamp is rejected'
);

select extensions.throws_ok(
  $$select public.process_admob_ssv_reward(
      'ssv-valid-transaction',
      '88888888-8888-4888-8888-888888888888', null::uuid,
      'ca-app-pub-5274007212820203/4541482404', 1, 'points',
      now()
    )$$,
  '22023', 'INVALID_SSV_PAYLOAD',
  'null values cannot exploit SQL null comparison during deduplication'
);

select extensions.throws_ok(
  $$select public.process_admob_ssv_reward(
      'ssv-unknown-claim',
      '99999999-9999-4999-8999-999999999999',
      '77777777-7777-4777-8777-777777777777',
      'ca-app-pub-5274007212820203/4541482404', 1, 'points', now()
    )$$,
  '22023', 'INVALID_REWARD_CLAIM',
  'a signed callback cannot create an unregistered reward claim'
);

set local role postgres;
select extensions.is(
  (select status from public.reward_claim_requests
   where claim_id = '88888888-8888-4888-8888-888888888888'),
  'processed',
  'the successfully credited claim is permanently marked processed'
);

select * from extensions.finish();
rollback;
