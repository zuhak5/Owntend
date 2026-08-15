begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

select has_table('public', 'user_settings', 'user settings table exists');
select has_table('public', 'notification_inbox', 'inbox table exists');
select has_table('public', 'streaks', 'streaks table exists');
select hasnt_table('public', 'device_settings', 'device settings were removed');
select hasnt_table('public', 'device_notifications', 'device notifications were removed');

select has_column('public', 'user_settings', 'user_id', 'settings are user scoped');
select has_column('public', 'notification_inbox', 'updated_at', 'inbox rows have update time');
select has_column('public', 'streaks', 'created_at', 'streak rows have create time');

select has_index(
  'public',
  'notification_inbox',
  'notification_inbox_dedupe_uidx',
  'inbox dedupe index exists'
);
select ok(
  to_regclass('public.notification_inbox_created_idx') is null,
  'obsolete inbox created-time index is retired'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_settings'
      and column_name = 'sync_seq'
  ),
  'settings no longer expose sync cursor metadata'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'streaks'
      and column_name = 'deleted_at'
  ),
  'streaks use hard deletes'
);

select * from finish();
rollback;
