begin;

create extension if not exists pgtap with schema extensions;

select plan(23);

select has_table(
  'owntend_private',
  'account_deletion_cleanup_jobs',
  'account deletion cleanup jobs are private'
);
select ok(
  not has_schema_privilege(
    'authenticated',
    'owntend_private',
    'USAGE'
  ),
  'authenticated users cannot access the private schema'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'owntend_private.account_deletion_cleanup_jobs',
    'SELECT'
  ),
  'authenticated users cannot inspect cleanup jobs'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.begin_owntend_account_cleanup(uuid,text[])',
    'EXECUTE'
  ),
  'authenticated users cannot create cleanup jobs'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.begin_owntend_account_cleanup(uuid,text[])',
    'EXECUTE'
  ),
  'service role can create cleanup jobs'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.complete_owntend_account_cleanup(uuid,text)',
    'EXECUTE'
  ),
  'authenticated users cannot complete cleanup jobs'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.complete_owntend_account_cleanup(uuid,text)',
    'EXECUTE'
  ),
  'service role can complete cleanup jobs'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'asset_photos_owned_path'
      and conrelid = 'public.asset_photos'::regclass
  ),
  'asset photo paths are owner scoped'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid =
        'owntend_private.account_deletion_cleanup_jobs'::regclass
      and confrelid = 'auth.users'::regclass
      and confdeltype = 'c'
  ),
  'cleanup jobs cannot outlive the Auth user'
);
select ok(
  exists (
    select 1
    from pg_class
    where oid = 'owntend_private.account_deletion_cleanup_jobs'::regclass
      and relrowsecurity
  ),
  'cleanup jobs enable Row Level Security'
);
select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'owntend_private'
      and tablename = 'account_deletion_cleanup_jobs'
      and policyname = 'account_deletion_cleanup_jobs_service_role_all'
      and roles @> array['service_role'::name]
  ),
  'cleanup jobs are writable only by the service role'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.is_recent_owntend_session(uuid,uuid)',
    'EXECUTE'
  ),
  'clients cannot call the trusted recent-session check'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.is_recent_owntend_session(uuid,uuid)',
    'EXECUTE'
  ),
  'the Edge Function can call the recent-session check'
);
select has_schema(
  'owntend_security',
  'privileged policy helpers live outside the exposed API schema'
);
select ok(
  has_schema_privilege('authenticated', 'owntend_security', 'USAGE'),
  'authenticated Storage policies can resolve the private helper'
);
select ok(
  not has_schema_privilege('anon', 'owntend_security', 'USAGE'),
  'anonymous clients cannot resolve privileged policy helpers'
);
select ok(
  to_regprocedure('public.current_owntend_session_is_active()') is null,
  'the active-session helper is not exposed as a public RPC'
);
select ok(
  has_function_privilege(
    'authenticated',
    'owntend_security.current_owntend_session_is_active()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'owntend_security.current_owntend_session_is_active()',
    'EXECUTE'
  ),
  'only authenticated Storage policies can execute the private helper'
);

select ok(
  to_regclass(
    'owntend_private.account_deletion_cleanup_jobs_user_id_idx'
  ) is not null,
  'cleanup job Auth foreign key is indexed'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values (
  '00000000-0000-0000-0000-000000000000',
  '55555555-5555-4555-8555-555555555555',
  'authenticated', 'authenticated', 'deletion-test@example.invalid', '',
  now(), now(), now()
);
insert into auth.sessions (id, user_id, created_at, updated_at)
values (
  '66666666-6666-4666-8666-666666666666',
  '55555555-5555-4555-8555-555555555555',
  now(), now()
);

select ok(
  public.is_recent_owntend_session(
    '55555555-5555-4555-8555-555555555555',
    '66666666-6666-4666-8666-666666666666'
  ),
  'a newly created matching session satisfies reauthentication'
);
update auth.sessions
set created_at = now() - interval '6 minutes'
where id = '66666666-6666-4666-8666-666666666666';
select ok(
  not public.is_recent_owntend_session(
    '55555555-5555-4555-8555-555555555555',
    '66666666-6666-4666-8666-666666666666'
  ),
  'an older session cannot authorize account deletion'
);

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated","session_id":"66666666-6666-4666-8666-666666666666"}';
select ok(
  owntend_security.current_owntend_session_is_active(),
  'Storage accepts a JWT only while its session row exists'
);
reset role;

select is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'user_media_%_own'
      and (
        coalesce(qual, '') || ' ' || coalesce(with_check, '')
      ) like '%current_owntend_session_is_active%'
  ),
  3,
  'all user-media policies reject revoked sessions'
);

select * from finish();
rollback;
