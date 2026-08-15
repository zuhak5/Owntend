begin;

create extension if not exists pgtap with schema extensions;

select plan(6);

select results_eq(
  $$select public::boolean from storage.buckets where id = 'user-media'$$,
  array[false],
  'user-media is private'
);
select results_eq(
  $$select file_size_limit from storage.buckets where id = 'user-media'$$,
  array[10485760::bigint],
  'user-media has a 10 MiB limit'
);
select is(
  (select count(*)::integer from pg_policies
   where schemaname = 'storage'
     and tablename = 'objects'
     and policyname = 'user_media_select_own'),
  1,
  'private media select policy exists'
);
select is(
  (select count(*)::integer from pg_policies
   where schemaname = 'storage'
     and tablename = 'objects'
     and policyname = 'user_media_insert_own'),
  1,
  'private media insert policy exists'
);
select is(
  (select count(*)::integer from pg_policies
   where schemaname = 'storage'
     and tablename = 'objects'
     and policyname = 'user_media_update_own'),
  1,
  'private media update policy exists'
);
select is(
  (select count(*)::integer from pg_policies
   where schemaname = 'storage'
     and tablename = 'objects'
     and policyname = 'user_media_delete_own'),
  1,
  'private media delete policy exists'
);

select * from finish();
rollback;
