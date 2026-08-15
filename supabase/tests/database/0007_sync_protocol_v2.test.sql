begin;

create extension if not exists pgtap with schema extensions;

select plan(7);

select hasnt_table('public', 'sync_devices', 'legacy sync device registry is removed');
select hasnt_table('public', 'sync_tombstones', 'legacy tombstone ledger is removed');
select hasnt_table('public', 'sync_activity', 'legacy activity head table is removed');
select hasnt_function(
  'public',
  'delete_owntend_record',
  array['text', 'text', 'text', 'timestamp with time zone', 'text', 'bigint'],
  'legacy delete RPC is removed'
);
select is(
  to_regclass('public.owntend_sync_seq')::text,
  null,
  'legacy sync sequence is removed'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'areas'
      and column_name = 'sync_seq'
  ),
  'areas no longer carry sync cursors'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'areas'
      and column_name = 'origin_device_id'
  ),
  'areas no longer carry origin device metadata'
);

select * from finish();
rollback;
