begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(5);

select extensions.hasnt_column(
  'public', 'assets', 'category_id',
  'assets no longer persist a Category classifier'
);
select extensions.ok(
  not exists (
    select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'assets'
      and indexdef ilike '%category_id%'
  ),
  'assets have no Category index'
);
select extensions.ok(
  strpos(
    pg_get_functiondef(
      'owntend_monetization_private.create_asset_with_point_debit_impl(jsonb)'::regprocedure
    ),
    'category_id'
  ) = 0,
  'asset creation implementation no longer reads or writes Category'
);
select extensions.ok(
  strpos(
    pg_get_functiondef(
      'owntend_monetization_private.create_task_with_point_debit_impl(jsonb)'::regprocedure
    ),
    'category_id'
  ) = 0,
  'task safety classification no longer falls back to Category'
);
select extensions.ok(
  strpos(
    pg_get_constraintdef(
      (select oid from pg_constraint
       where conrelid = 'public.assets'::regclass
         and contype = 'c'
         and pg_get_constraintdef(oid) ilike '%asset_type%')
    ),
    'device'
  ) > 0,
  'Item Type remains the constrained asset classifier'
);

select * from extensions.finish();
rollback;
