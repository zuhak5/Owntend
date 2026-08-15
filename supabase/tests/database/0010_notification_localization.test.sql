begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

select has_column(
  'public', 'notification_inbox', 'message_code',
  'notification inbox stores stable message codes'
);
select has_column(
  'public', 'notification_inbox', 'message_args',
  'notification inbox stores structured message arguments'
);
select col_type_is(
  'public', 'notification_inbox', 'message_args', 'jsonb',
  'message arguments use jsonb'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    '33333333-3333-3333-3333-333333333333',
    'authenticated', 'authenticated', 'locale-a@example.invalid', '',
    now(), now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '44444444-4444-4444-4444-444444444444',
    'authenticated', 'authenticated', 'locale-b@example.invalid', '',
    now(), now(), now()
  );

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

insert into public.notification_inbox (
  user_id, id, title, body, kind, dedupe_key, created_at, updated_at
)
values (
  '33333333-3333-3333-3333-333333333333',
  'legacy-notification', 'Legacy title', 'Legacy body', 'task',
  'legacy-localization-test', now(), now()
);

select is(
  (
    select message_args
    from public.notification_inbox
    where id = 'legacy-notification'
  ),
  '{}'::jsonb,
  'legacy notification writes receive an empty argument object'
);
select is(
  (
    select message_code
    from public.notification_inbox
    where id = 'legacy-notification'
  ),
  null,
  'legacy notification writes retain a null message code'
);

select throws_ok(
  $$
    insert into public.notification_inbox (
      user_id, id, title, body, kind, dedupe_key,
      message_code, message_args, created_at, updated_at
    ) values (
      '33333333-3333-3333-3333-333333333333',
      'invalid-args', 'Invalid', 'Invalid', 'task', 'invalid-args-test',
      'task_due', '[]'::jsonb, now(), now()
    )
  $$,
  '23514',
  null,
  'notification arguments reject non-object JSON values'
);

select lives_ok(
  $$
    insert into public.notification_inbox (
      user_id, id, title, body, kind, dedupe_key,
      message_code, message_args, created_at, updated_at
    ) values (
      '33333333-3333-3333-3333-333333333333',
      'localized-notification', 'Snapshot title', 'Snapshot body', 'task',
      'localized-notification-test', 'task_due',
      '{"task":"Replace filter"}'::jsonb, now(), now()
    )
  $$,
  'a controlled notification accepts a stable code and object arguments'
);

select lives_ok(
  $$
    insert into public.user_settings (user_id, key, value, updated_at)
    values
      (
        '33333333-3333-3333-3333-333333333333',
        'app_language', 'ar', '2026-07-22 06:30:00+00'
      ),
      (
        '33333333-3333-3333-3333-333333333333',
        'app_language_explicit', 'true', '2026-07-22 06:30:00+00'
      )
  $$,
  'language and explicit-choice settings are accepted together'
);
select is(
  (
    select count(distinct updated_at)::integer
    from public.user_settings
    where user_id = '33333333-3333-3333-3333-333333333333'
      and key in ('app_language', 'app_language_explicit')
  ),
  1,
  'the synchronized locale-setting pair can share one conflict timestamp'
);

set local request.jwt.claims =
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}';

select is(
  (select count(*)::integer from public.notification_inbox),
  0,
  'another user cannot read localized notifications'
);
select lives_ok(
  $$
    update public.notification_inbox
    set message_code = 'weather_summary'
    where user_id = '33333333-3333-3333-3333-333333333333'
      and id = 'localized-notification'
  $$,
  'another user notification update is safely filtered by RLS'
);

set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

select is(
  (
    select message_code
    from public.notification_inbox
    where id = 'localized-notification'
  ),
  'task_due',
  'another user cannot alter localized notification content'
);
select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'notification_inbox'
      and policyname = 'notification_inbox_update_own'
      and cmd = 'UPDATE'
      and with_check like '%auth.uid()%'
      and with_check like '%user_id%'
  ),
  'notification update policy retains an owner-scoped WITH CHECK'
);

set local role postgres;

select ok(
  (
    select bool_and(
      has_table_privilege('service_role', format('public.%I', table_name), privilege)
    )
    from unnest(array[
      'areas', 'asset_photos', 'asset_tags', 'assets',
      'device_details', 'maintenance_plans', 'maintenance_records',
      'notification_inbox', 'pet_details', 'plant_details', 'profiles',
      'rooms', 'safety_details', 'streaks', 'tags', 'user_settings'
    ]) as table_name
    cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) as privilege
  ),
  'service role retains explicit CRUD grants on reconciled app tables'
);
select ok(
  not has_table_privilege('anon', 'public.notification_inbox', 'SELECT'),
  'notification localization does not broaden anonymous inbox access'
);
select ok(
  not has_table_privilege('anon', 'public.user_settings', 'SELECT'),
  'language preferences do not broaden anonymous settings access'
);
select ok(
  (
    select bool_and(to_regclass(format('public.%I', index_name)) is not null)
    from unnest(array[
      'asset_photos_user_id_asset_id_idx',
      'asset_tags_user_id_tag_id_idx',
      'assets_user_id_category_id_idx',
      'assets_user_id_room_id_idx',
      'maintenance_plans_user_id_asset_id_idx',
      'maintenance_records_user_id_plan_id_idx',
      'notification_inbox_user_id_plan_id_idx',
      'rooms_user_id_area_id_idx'
    ]) as index_name
  ),
  'all eight relationship indexes are represented by migrations'
);
select ok(
  (
    select bool_and(relrowsecurity)
    from pg_class
    where oid in (
      'public.notification_inbox'::regclass,
      'public.user_settings'::regclass
    )
  ),
  'notification and locale tables retain RLS'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.begin_owntend_account_cleanup(uuid,text[])',
    'EXECUTE'
  ),
  'account cleanup function permissions remain unchanged'
);

delete from auth.users
where id = '33333333-3333-3333-3333-333333333333';

select is(
  (
    select count(*)::integer
    from public.notification_inbox
    where user_id = '33333333-3333-3333-3333-333333333333'
  ),
  0,
  'auth deletion still cascades localized notifications'
);
select is(
  (
    select count(*)::integer
    from public.user_settings
    where user_id = '33333333-3333-3333-3333-333333333333'
  ),
  0,
  'auth deletion still cascades language preferences'
);

select * from finish();
rollback;
