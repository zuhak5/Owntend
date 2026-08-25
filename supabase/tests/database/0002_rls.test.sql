begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

select ok(
  (select bool_and(relrowsecurity)
   from pg_class
   where oid in (
     'public.profiles'::regclass,
     'public.areas'::regclass,
     'public.assets'::regclass,
     'public.maintenance_records'::regclass
   )),
  'core app tables have RLS enabled'
);

select ok(
  (select bool_and(policy_count = 4)
   from (
     select table_name, count(policyname)::integer as policy_count
     from unnest(array[
       'profiles', 'areas', 'rooms',
       'device_details', 'pet_details', 'plant_details', 'safety_details',
       'tags', 'asset_tags', 'maintenance_plans',
       'maintenance_plan_metadata', 'maintenance_records',
       'notification_inbox', 'user_settings', 'streaks'
     ]) as table_name
     left join pg_policies
       on schemaname = 'public'
      and tablename = table_name
     group by table_name
   ) policy_counts)
   -- assets intentionally has no INSERT policy: creation is routed through
   -- the server-authoritative aggregate RPC (MON-001).
   and (select count(*)::integer from pg_policies where schemaname = 'public' and tablename = 'assets') = 3
   and (select count(*)::integer from pg_policies where schemaname = 'public' and tablename = 'asset_photos') = 1,
  '15 standard app tables have full policies, assets excludes INSERT, and asset_photos has select-only policy'
);

select ok(
  has_table_privilege('authenticated', 'public.areas', 'SELECT'),
  'authenticated can select owned areas'
);
select ok(
  has_table_privilege('authenticated', 'public.areas', 'INSERT'),
  'authenticated can insert owned areas'
);
select ok(
  has_table_privilege('authenticated', 'public.areas', 'UPDATE'),
  'authenticated can update owned areas'
);
select ok(
  has_table_privilege('authenticated', 'public.areas', 'DELETE'),
  'authenticated can delete owned areas'
);
select ok(
  not has_table_privilege('anon', 'public.areas', 'SELECT'),
  'unauthenticated clients cannot read areas'
);
select ok(
  not has_table_privilege('anon', 'public.assets', 'SELECT'),
  'unauthenticated clients cannot read assets'
);
select ok(
  not has_table_privilege('anon', 'public.maintenance_records', 'SELECT'),
  'unauthenticated clients cannot read maintenance history'
);

select * from finish();
rollback;
