begin;
set local search_path = public, extensions;

create extension if not exists pgtap with schema extensions;

select plan(8);

select ok(
  exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'point_wallets'
  ),
  'point_wallets is published as a monetization Realtime channel'
);

select is(
  (select relreplident::text from pg_class where oid = 'public.point_wallets'::regclass),
  'f',
  'point_wallets retains full replica identity for Realtime stream snapshots'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.point_wallets'::regclass),
  'point_wallets keeps RLS enabled'
);

select ok(
  has_table_privilege('authenticated', 'public.point_wallets', 'SELECT'),
  'authenticated may read its RLS-scoped wallet'
);

select ok(
  not has_table_privilege('authenticated', 'public.point_wallets', 'INSERT'),
  'authenticated cannot directly create or credit a wallet row'
);

select ok(
  not has_table_privilege('authenticated', 'public.point_wallets', 'UPDATE'),
  'authenticated cannot directly update, debit, or credit a wallet'
);

select ok(
  not has_table_privilege('authenticated', 'public.point_wallets', 'DELETE'),
  'authenticated cannot directly delete a wallet'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'point_wallets'
      and policyname = 'point_wallets_select_own'
      and cmd = 'SELECT'
      and qual like '%auth.uid()%user_id%'
  ),
  'point_wallets SELECT policy remains owner-scoped'
);

select * from finish();
rollback;
