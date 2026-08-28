begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    '11111111-1111-1111-1111-111111111111',
    'authenticated',
    'authenticated',
    'supabase-a@example.invalid',
    '',
    now(),
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '22222222-2222-2222-2222-222222222222',
    'authenticated',
    'authenticated',
    'supabase-b@example.invalid',
    '',
    now(),
    now(),
    now()
  );

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select lives_ok(
  $$
    insert into public.areas (
      user_id, id, name, kind, sort_order, created_at, updated_at
    )
    values (
      '11111111-1111-1111-1111-111111111111',
      'area_main',
      'Main Area',
      'indoor',
      0,
      now(),
      now()
    )
  $$,
  'a user can insert an owned area'
);

select throws_ok(
  $$
    insert into public.areas (
      user_id, id, name, kind, sort_order, created_at, updated_at
    )
    values (
      '22222222-2222-2222-2222-222222222222',
      'area_main',
      'Main Area',
      'indoor',
      0,
      now(),
      now()
    )
  $$,
  '42501',
  null,
  'a user cannot insert another user area'
);

select lives_ok(
  $$
    insert into public.user_settings (user_id, key, value, created_at, updated_at)
    values (
      '11111111-1111-1111-1111-111111111111',
      'theme',
      'dark',
      now(),
      now()
    )
  $$,
  'a user can insert an owned setting'
);

select lives_ok(
  $$
    insert into public.user_settings (user_id, key, value, created_at, updated_at)
    values (
      '11111111-1111-1111-1111-111111111111',
      'permission_education_seen',
      'true',
      now(),
      now()
    )
  $$,
  'permission education state is an allowed synced setting'
);

select throws_ok(
  $$
    insert into public.user_settings (user_id, key, value, created_at, updated_at)
    values (
      '11111111-1111-1111-1111-111111111111',
      'not_a_real_setting',
      'true',
      now(),
      now()
    )
  $$,
  '23514',
  null,
  'unknown setting keys remain rejected'
);

set local request.jwt.claims =
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

select is(
  (select count(*)::integer from public.user_settings),
  0,
  'another user cannot read settings'
);

select lives_ok(
  $$
    update public.user_settings
    set value = 'hacked'
    where user_id = '11111111-1111-1111-1111-111111111111'
      and key = 'theme'
  $$,
  'another user update is safely filtered by RLS'
);

set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  (select value from public.user_settings where key = 'theme'),
  'dark',
  'another user cannot update an owned setting'
);

select lives_ok(
  $$
    update public.user_settings
    set value = 'light'
    where user_id = '11111111-1111-1111-1111-111111111111'
      and key = 'theme'
  $$,
  'owned setting values remain updatable'
);

select is(
  (select user_id::text from public.user_settings where key = 'theme'),
  '11111111-1111-1111-1111-111111111111',
  'a value-only update preserves setting ownership'
);

select lives_ok(
  $$
    delete from public.user_settings
    where user_id = '11111111-1111-1111-1111-111111111111'
      and key = 'theme'
  $$,
  'authenticated clients can hard-delete owned rows'
);

select lives_ok(
  $$
    insert into public.notification_inbox (
      user_id, id, title, body, kind, dedupe_key, created_at, updated_at
    )
    values (
      '11111111-1111-1111-1111-111111111111',
      'inbox-a',
      'Filter reminder',
      'Replace the filter',
      'task',
      'stable-dedupe-key',
      now(),
      now()
    )
  $$,
  'an owned inbox event can be inserted'
);

select throws_ok(
  $$
    insert into public.notification_inbox (
      user_id, id, title, body, kind, dedupe_key, created_at, updated_at
    )
    values (
      '11111111-1111-1111-1111-111111111111',
      'inbox-b',
      'Filter reminder',
      'Replace the filter',
      'task',
      'stable-dedupe-key',
      now(),
      now()
    )
  $$,
  '23505',
  null,
  'active inbox deduplication is enforced'
);

set local role anon;
set local request.jwt.claims = '{}';

select throws_ok(
  $$ select count(*) from public.notification_inbox $$,
  '42501',
  null,
  'unauthenticated clients cannot read notification content'
);

select * from finish();
rollback;
