begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(12);

-- Media-cleanup worker RPCs are service_role-only capabilities.
select extensions.ok(
  has_function_privilege('service_role', 'public.claim_media_cleanup_batch(integer)', 'execute')
    and not has_function_privilege('anon', 'public.claim_media_cleanup_batch(integer)', 'execute')
    and not has_function_privilege('authenticated', 'public.claim_media_cleanup_batch(integer)', 'execute'),
  'claim_media_cleanup_batch is service_role only'
);

select extensions.ok(
  has_function_privilege('service_role', 'public.acknowledge_media_cleanup(bigint)', 'execute')
    and not has_function_privilege('anon', 'public.acknowledge_media_cleanup(bigint)', 'execute')
    and not has_function_privilege('authenticated', 'public.acknowledge_media_cleanup(bigint)', 'execute'),
  'acknowledge_media_cleanup is service_role only'
);

select extensions.ok(
  has_function_privilege('service_role', 'public.record_media_cleanup_failure(bigint,text,boolean)', 'execute')
    and not has_function_privilege('anon', 'public.record_media_cleanup_failure(bigint,text,boolean)', 'execute')
    and not has_function_privilege('authenticated', 'public.record_media_cleanup_failure(bigint,text,boolean)', 'execute'),
  'record_media_cleanup_failure is service_role only'
);

-- Authenticated application RPCs deny anon while serving authenticated
-- callers (and trusted server-side roles where the boundary requires it).
select extensions.ok(
  has_function_privilege('authenticated', 'public.prepare_asset_photo_upload(text,text,bigint,text,text,text)', 'execute')
    and has_function_privilege('service_role', 'public.prepare_asset_photo_upload(text,text,bigint,text,text,text)', 'execute')
    and not has_function_privilege('anon', 'public.prepare_asset_photo_upload(text,text,bigint,text,text,text)', 'execute'),
  'prepare_asset_photo_upload serves authenticated and service_role only'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.finalize_asset_photo_upload(uuid,text,text,integer,text,boolean)', 'execute')
    and has_function_privilege('service_role', 'public.finalize_asset_photo_upload(uuid,text,text,integer,text,boolean)', 'execute')
    and not has_function_privilege('anon', 'public.finalize_asset_photo_upload(uuid,text,text,integer,text,boolean)', 'execute'),
  'finalize_asset_photo_upload serves authenticated and service_role only'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.delete_asset_photo(text,text)', 'execute')
    and has_function_privilege('service_role', 'public.delete_asset_photo(text,text)', 'execute')
    and not has_function_privilege('anon', 'public.delete_asset_photo(text,text)', 'execute'),
  'delete_asset_photo serves authenticated and service_role only'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.set_primary_asset_photo(text,text)', 'execute')
    and has_function_privilege('service_role', 'public.set_primary_asset_photo(text,text)', 'execute')
    and not has_function_privilege('anon', 'public.set_primary_asset_photo(text,text)', 'execute'),
  'set_primary_asset_photo serves authenticated and service_role only'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.create_asset(jsonb)', 'execute')
    and has_function_privilege('service_role', 'public.create_asset(jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.create_asset(jsonb)', 'execute'),
  'create_asset serves authenticated and service_role only'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.create_task_with_point_debit(jsonb)', 'execute')
    and has_function_privilege('service_role', 'public.create_task_with_point_debit(jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.create_task_with_point_debit(jsonb)', 'execute'),
  'create_task_with_point_debit serves authenticated and service_role only'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.create_reward_claim_request(text,text)', 'execute')
    and has_function_privilege('service_role', 'public.create_reward_claim_request(text,text)', 'execute')
    and not has_function_privilege('anon', 'public.create_reward_claim_request(text,text)', 'execute'),
  'create_reward_claim_request serves authenticated and service_role only'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.get_charged_operation_status(uuid,text)', 'execute')
    and has_function_privilege('service_role', 'public.get_charged_operation_status(uuid,text)', 'execute')
    and not has_function_privilege('anon', 'public.get_charged_operation_status(uuid,text)', 'execute'),
  'get_charged_operation_status serves authenticated and service_role only'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.record_monetization_event(text,jsonb)', 'execute')
    and has_function_privilege('service_role', 'public.record_monetization_event(text,jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.record_monetization_event(text,jsonb)', 'execute'),
  'record_monetization_event serves authenticated and service_role only'
);

rollback;
