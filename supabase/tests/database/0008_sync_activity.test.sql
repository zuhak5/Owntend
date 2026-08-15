begin;

create extension if not exists pgtap with schema extensions;

select plan(5);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values (
  '00000000-0000-0000-0000-000000000000',
  '33333333-3333-3333-3333-333333333333',
  'authenticated',
  'authenticated',
  'metadata@example.invalid',
  '',
  now(),
  now(),
  now()
);

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

insert into public.areas (
  user_id, id, name, kind, sort_order, created_at, updated_at
)
values (
  '33333333-3333-3333-3333-333333333333',
  'area_main',
  'Main Area',
  'indoor',
  0,
  now(),
  now()
);

select is(
  (select revision::integer from public.areas where id = 'area_main'),
  1,
  'new rows start at row version 1'
);

update public.areas
set name = 'Main Floor'
where id = 'area_main';

select is(
  (select revision::integer from public.areas where id = 'area_main'),
  2,
  'updates increment the row version'
);

select is(
  (select user_id::text from public.areas where id = 'area_main'),
  '33333333-3333-3333-3333-333333333333',
  'metadata trigger preserves ownership'
);

select hasnt_table('public', 'sync_activity', 'no separate sync activity table remains');
select has_trigger(
  'public',
  'areas',
  'set_row_metadata',
  'row metadata trigger exists on areas'
);

select * from finish();
rollback;
