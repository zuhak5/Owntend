begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(23);

-- ENV-004 public API shape: client RPCs are owner-scoped and no longer accept
-- a caller-selected user id.
select extensions.has_function('owntend_private', 'fn_log_server_change_feed', ARRAY[]::text[], 'private feed trigger exists');
select extensions.has_function('public', 'fetch_user_change_feed', ARRAY['bigint', 'integer'], 'feed pull RPC exists');
select extensions.has_function('public', 'validate_change_feed_parity', ARRAY[]::text[], 'operator parity RPC exists');
select extensions.has_function('public', 'get_user_change_feed_watermark', ARRAY[]::text[], 'owner-scoped watermark RPC exists');
select extensions.hasnt_function('public', 'fn_log_server_change_feed', ARRAY[]::text[], 'the trigger is absent from the Data API schema');
select extensions.hasnt_function('public', 'validate_change_feed_parity', ARRAY['uuid'], 'caller-selected parity overload is absent');
select extensions.hasnt_function('public', 'get_user_change_feed_watermark', ARRAY['uuid'], 'caller-selected watermark overload is absent');

-- Client-facing feed RPCs do not need definer privileges because the underlying
-- tables already expose the required authenticated SELECT surface under RLS.
select extensions.ok(
  not (select p.prosecdef from pg_proc p where p.oid = 'public.fetch_user_change_feed(bigint,integer)'::regprocedure),
  'fetch_user_change_feed is SECURITY INVOKER'
);
select extensions.ok(
  not (select p.prosecdef from pg_proc p where p.oid = 'public.validate_change_feed_parity()'::regprocedure),
  'validate_change_feed_parity is SECURITY INVOKER'
);
select extensions.ok(
  not (select p.prosecdef from pg_proc p where p.oid = 'public.get_user_change_feed_watermark()'::regprocedure),
  'get_user_change_feed_watermark is SECURITY INVOKER'
);
select extensions.ok(
  (select p.prosecdef from pg_proc p where p.oid = 'owntend_private.fn_log_server_change_feed()'::regprocedure),
  'trigger logger remains SECURITY DEFINER because authenticated cannot insert into the feed table'
);

-- Anonymous callers cannot invoke any feed RPC or the trigger function.
select extensions.ok(
  not has_function_privilege('anon', 'public.fetch_user_change_feed(bigint,integer)', 'execute'),
  'anon cannot execute feed pull RPC'
);
select extensions.ok(
  not has_function_privilege('anon', 'public.validate_change_feed_parity()', 'execute'),
  'anon cannot execute parity RPC'
);
select extensions.ok(
  not has_function_privilege('anon', 'public.get_user_change_feed_watermark()', 'execute'),
  'anon cannot execute watermark RPC'
);
select extensions.ok(
  not has_function_privilege('anon', 'owntend_private.fn_log_server_change_feed()', 'execute'),
  'anon cannot execute trigger logger'
);

-- Authenticated clients receive only the intended read RPCs, never direct
-- trigger-function execution.
select extensions.ok(
  has_function_privilege('authenticated', 'public.fetch_user_change_feed(bigint,integer)', 'execute'),
  'authenticated can execute feed pull RPC'
);
select extensions.ok(
  not has_function_privilege('authenticated', 'public.validate_change_feed_parity()', 'execute'),
  'authenticated cannot execute the operator parity RPC'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.get_user_change_feed_watermark()', 'execute'),
  'authenticated can execute owner-scoped watermark RPC'
);
select extensions.ok(
  not has_function_privilege('authenticated', 'owntend_private.fn_log_server_change_feed()', 'execute'),
  'authenticated cannot execute trigger logger'
);

-- service_role is not part of the mobile feed surface. It receives only the
-- parity invariant used by protected operator and CI checks.
select extensions.ok(
  not has_function_privilege('service_role', 'public.fetch_user_change_feed(bigint,integer)', 'execute'),
  'service_role cannot execute feed pull RPC'
);
select extensions.ok(
  has_function_privilege('service_role', 'public.validate_change_feed_parity()', 'execute'),
  'service_role can execute the operator parity RPC'
);
select extensions.ok(
  not has_function_privilege('service_role', 'public.get_user_change_feed_watermark()', 'execute'),
  'service_role cannot execute watermark RPC'
);
select extensions.ok(
  not has_function_privilege('service_role', 'owntend_private.fn_log_server_change_feed()', 'execute'),
  'service_role cannot execute trigger logger'
);

rollback;
