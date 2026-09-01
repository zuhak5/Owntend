begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(20);

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
  has_function_privilege('authenticated', 'public.create_reward_claim_request(text,text,uuid)', 'execute')
    and has_function_privilege('service_role', 'public.create_reward_claim_request(text,text,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.create_reward_claim_request(text,text,uuid)', 'execute'),
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

select extensions.ok(
  has_function_privilege('authenticated', 'public.copy_asset(jsonb)', 'execute')
    and has_function_privilege('service_role', 'public.copy_asset(jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.copy_asset(jsonb)', 'execute'),
  'copy_asset serves authenticated and service_role only'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.quote_maintenance_plan_move(text,text)', 'execute')
    and has_function_privilege('service_role', 'public.quote_maintenance_plan_move(text,text)', 'execute')
    and not has_function_privilege('anon', 'public.quote_maintenance_plan_move(text,text)', 'execute'),
  'quote_maintenance_plan_move serves authenticated and service_role only'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.move_maintenance_plan_with_point_delta(jsonb)', 'execute')
    and has_function_privilege('service_role', 'public.move_maintenance_plan_with_point_delta(jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.move_maintenance_plan_with_point_delta(jsonb)', 'execute'),
  'move_maintenance_plan_with_point_delta serves authenticated and service_role only'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.quote_asset_type_change(text,text)', 'execute')
    and has_function_privilege('service_role', 'public.quote_asset_type_change(text,text)', 'execute')
    and not has_function_privilege('anon', 'public.quote_asset_type_change(text,text)', 'execute'),
  'quote_asset_type_change serves authenticated and service_role only'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.change_asset_type_with_point_delta(jsonb)', 'execute')
    and has_function_privilege('service_role', 'public.change_asset_type_with_point_delta(jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.change_asset_type_with_point_delta(jsonb)', 'execute'),
  'change_asset_type_with_point_delta serves authenticated and service_role only'
);

select extensions.ok(
  has_function_privilege('authenticated', 'public.restore_maintenance_history(jsonb,text)', 'execute')
    and has_function_privilege('service_role', 'public.restore_maintenance_history(jsonb,text)', 'execute')
    and not has_function_privilege('anon', 'public.restore_maintenance_history(jsonb,text)', 'execute'),
  'restore_maintenance_history serves authenticated and service_role only'
);

select extensions.ok(
  has_function_privilege('service_role', 'public.validate_change_feed_parity(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.validate_change_feed_parity(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.validate_change_feed_parity(uuid)', 'execute')
    and to_regprocedure('public.validate_change_feed_parity()') is null,
  'target-user parity is service-role only and the obsolete overload is absent'
);

-- The public entry points must hold no elevated authority themselves: the
-- SECURITY DEFINER boundary lives exclusively in the private implementations,
-- which keeps the hosted advisor (splinter lint 0029) clean without weakening
-- the server-authoritative behavior.
select extensions.is(
  (
    select count(*)::int
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'prepare_asset_photo_upload',
        'finalize_asset_photo_upload',
        'delete_asset_photo',
        'set_primary_asset_photo',
        'create_asset',
        'create_task_with_point_debit',
        'create_reward_claim_request',
        'get_charged_operation_status',
        'record_monetization_event',
        'copy_asset',
        'quote_maintenance_plan_move',
        'move_maintenance_plan_with_point_delta',
        'quote_asset_type_change',
        'change_asset_type_with_point_delta',
        'restore_maintenance_history'
      )
      and not p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ),
  15,
  'all public application RPC entry points are invoker delegations executable only by authenticated callers'
);

rollback;
