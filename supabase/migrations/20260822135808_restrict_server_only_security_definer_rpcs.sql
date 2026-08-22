-- Supabase projects can retain explicit Data API grants for newly created
-- functions. These elevated RPCs are called only by trusted Edge Functions,
-- so remove every client role explicitly instead of relying on PUBLIC alone.

revoke execute on function public.begin_owntend_account_cleanup(uuid, text[])
  from public, anon, authenticated;
grant execute on function public.begin_owntend_account_cleanup(uuid, text[])
  to service_role;

revoke execute on function public.complete_owntend_account_cleanup(uuid, text)
  from public, anon, authenticated;
grant execute on function public.complete_owntend_account_cleanup(uuid, text)
  to service_role;

revoke execute on function public.is_recent_owntend_session(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.is_recent_owntend_session(uuid, uuid)
  to service_role;

revoke execute on function public.process_admob_ssv_reward(
  text,
  uuid,
  uuid,
  text,
  integer,
  text,
  timestamp with time zone
)
  from public, anon, authenticated;
grant execute on function public.process_admob_ssv_reward(
  text,
  uuid,
  uuid,
  text,
  integer,
  text,
  timestamp with time zone
)
  to service_role;
