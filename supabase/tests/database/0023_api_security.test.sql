begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(15);

select extensions.is(
  (select prosecdef from pg_proc where oid = 'public.prepare_asset_photo_upload(text,text,bigint,text,text,text)'::regprocedure),
  false,
  'prepare_asset_photo_upload public API is a SECURITY INVOKER delegation'
);

select extensions.is(
  (select prosecdef from pg_proc where oid = 'public.finalize_asset_photo_upload(uuid,text,text,integer,text,boolean)'::regprocedure),
  false,
  'finalize_asset_photo_upload public API is a SECURITY INVOKER delegation'
);

select extensions.is(
  (select prosecdef from pg_proc where oid = 'public.set_primary_asset_photo(text,text)'::regprocedure),
  false,
  'set_primary_asset_photo public API is a SECURITY INVOKER delegation'
);

select extensions.is(
  (select prosecdef from pg_proc where oid = 'public.get_charged_operation_status(uuid,text)'::regprocedure),
  false,
  'get_charged_operation_status public API is a SECURITY INVOKER delegation'
);

select extensions.is(
  (
    select count(*)::int
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and (p.proconfig is null or not ('search_path=' = any(p.proconfig) or 'search_path=""' = any(p.proconfig)))
  ),
  0,
  'all public SECURITY DEFINER functions enforce an empty safe search_path'
);

select extensions.is(
  (
    select count(*)::int
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('owntend_media_private', 'owntend_monetization_private', 'owntend_private')
      and has_function_privilege('anon', p.oid, 'EXECUTE')
      -- WP-002 (F-002): the auth.uid()-guarded reconcile helper is the single
      -- sanctioned exception; it backs the maintenance_plans INSERT policy.
      and p.proname <> 'can_reconcile_maintenance_plan'
  ),
  0,
  'private schema implementations are never executable by anon (except the policy-backed reconcile helper)'
);

select extensions.is(
  (
    select count(*)::int
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('owntend_media_private', 'owntend_monetization_private')
      and p.proname in (
        'prepare_asset_photo_upload_impl',
        'finalize_asset_photo_upload_impl',
        'delete_asset_photo_impl',
        'set_primary_asset_photo_impl',
        'create_asset_impl',
        'create_task_with_point_debit_impl',
        'create_reward_claim_request_impl',
        'get_charged_operation_status',
        'record_monetization_event_impl'
      )
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and has_function_privilege('service_role', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and p.prosecdef
  ),
  9,
  'exactly the nine RPC implementations stay SECURITY DEFINER while serving authenticated and service_role callers'
);

select extensions.is(
  (
    select count(*)::int
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'owntend_monetization_private'
      and p.proname = 'can_reconcile_maintenance_plan'
      and has_function_privilege('anon', p.oid, 'EXECUTE')
  ),
  0,
  'anon cannot execute the reconcile helper'
);

select extensions.is(
  (
    select prosecdef
    from pg_proc
    where oid = 'owntend_monetization_private.get_charged_operation_status(uuid,text)'::regprocedure
  ),
  true,
  'charged operation status authority remains in a private SECURITY DEFINER implementation'
);

select extensions.is(
  (
    select count(*)::int
    from pg_policies
    where schemaname = 'public'
      and (
        (
          position('AUTH.UID()' in upper(coalesce(qual, ''))) > 0
          and position('SELECT AUTH.UID()' in upper(coalesce(qual, ''))) = 0
        )
        or (
          position('AUTH.UID()' in upper(coalesce(with_check, ''))) > 0
          and position('SELECT AUTH.UID()' in upper(coalesce(with_check, ''))) = 0
        )
      )
  ),
  0,
  'public RLS policies cache statement-stable auth.uid() calls through init plans'
);

select extensions.is(
  (
    select count(*)::int
    from pg_policies
    where schemaname = 'public'
      and (
        (
          position('CURRENT_SETTING(' in upper(coalesce(qual, ''))) > 0
          and position('SELECT CURRENT_SETTING(' in upper(coalesce(qual, ''))) = 0
        )
        or (
          position('CURRENT_SETTING(' in upper(coalesce(with_check, ''))) > 0
          and position('SELECT CURRENT_SETTING(' in upper(coalesce(with_check, ''))) = 0
        )
      )
  ),
  0,
  'public RLS policies cache statement-stable current_setting() calls through init plans'
);

select extensions.ok(
  to_regclass('public.notifications') is null,
  'the duplicate notifications table is absent from the v1 schema'
);

select extensions.is(
  (
    select count(*)::int
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and has_table_privilege('anon', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
  ),
  0,
  'anonymous receives no application-table privileges'
);

select extensions.is(
  (
    select count(*)::int
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and has_table_privilege('authenticated', c.oid, 'TRUNCATE,REFERENCES,TRIGGER')
  ),
  0,
  'authenticated receives no ownership-like application-table privileges'
);

select extensions.is(
  (
    select count(*)::int
    from information_schema.sequences s
    where s.sequence_schema = 'public'
      and (
        has_sequence_privilege(
          'authenticated',
          format('%I.%I', s.sequence_schema, s.sequence_name),
          'USAGE'
        )
        or has_sequence_privilege(
          'authenticated',
          format('%I.%I', s.sequence_schema, s.sequence_name),
          'SELECT'
        )
        or has_sequence_privilege(
          'authenticated',
          format('%I.%I', s.sequence_schema, s.sequence_name),
          'UPDATE'
        )
      )
  ),
  0,
  'authenticated cannot operate internal application sequences'
);

rollback;
