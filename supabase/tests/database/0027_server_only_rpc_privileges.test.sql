begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(12);

select extensions.ok(
  not has_function_privilege(
    'anon',
    'public.begin_owntend_account_cleanup(uuid,text[])',
    'execute'
  ),
  'anonymous users cannot begin account cleanup'
);
select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'public.begin_owntend_account_cleanup(uuid,text[])',
    'execute'
  ),
  'authenticated users cannot begin account cleanup'
);
select extensions.ok(
  has_function_privilege(
    'service_role',
    'public.begin_owntend_account_cleanup(uuid,text[])',
    'execute'
  ),
  'service role can begin account cleanup'
);

select extensions.ok(
  not has_function_privilege(
    'anon',
    'public.complete_owntend_account_cleanup(uuid,text)',
    'execute'
  ),
  'anonymous users cannot complete account cleanup'
);
select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'public.complete_owntend_account_cleanup(uuid,text)',
    'execute'
  ),
  'authenticated users cannot complete account cleanup'
);
select extensions.ok(
  has_function_privilege(
    'service_role',
    'public.complete_owntend_account_cleanup(uuid,text)',
    'execute'
  ),
  'service role can complete account cleanup'
);

select extensions.ok(
  not has_function_privilege(
    'anon',
    'public.is_recent_owntend_session(uuid,uuid)',
    'execute'
  ),
  'anonymous users cannot inspect recent sessions'
);
select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'public.is_recent_owntend_session(uuid,uuid)',
    'execute'
  ),
  'authenticated users cannot inspect recent sessions'
);
select extensions.ok(
  has_function_privilege(
    'service_role',
    'public.is_recent_owntend_session(uuid,uuid)',
    'execute'
  ),
  'service role can inspect recent sessions'
);

select extensions.ok(
  not has_function_privilege(
    'anon',
    'public.process_admob_ssv_reward(text,uuid,uuid,text,integer,text,timestamptz)',
    'execute'
  ),
  'anonymous users cannot settle AdMob rewards'
);
select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'public.process_admob_ssv_reward(text,uuid,uuid,text,integer,text,timestamptz)',
    'execute'
  ),
  'authenticated users cannot settle AdMob rewards'
);
select extensions.ok(
  has_function_privilege(
    'service_role',
    'public.process_admob_ssv_reward(text,uuid,uuid,text,integer,text,timestamptz)',
    'execute'
  ),
  'service role can settle AdMob rewards'
);

select extensions.finish();

rollback;
