begin;

create extension if not exists pgtap with schema extensions;

select plan(3);

select ok(
  exists (
    select 1
    from pg_policy policies
    join pg_class tables on tables.oid = policies.polrelid
    join pg_namespace schemas on schemas.oid = tables.relnamespace
    where schemas.nspname = 'owntend_private'
      and tables.relname = 'account_deletion_operations'
      and policies.polname =
        'account_deletion_operations_service_role_all'
      and (
        select oid from pg_roles where rolname = 'service_role'
      ) = any(policies.polroles)
  ),
  'private deletion operations have an explicit service-role policy'
);

select ok(
  (
    select bool_and(
      to_regclass(format('public.%I', index_name)) is null
    )
    from unnest(array[
      'areas_user_updated_idx',
      'rooms_user_updated_idx',
      'asset_photos_user_updated_idx',
      'maintenance_plans_enabled_due_idx',
      'device_details_user_updated_idx',
      'pet_details_user_updated_idx',
      'safety_details_user_updated_idx',
      'streaks_user_updated_idx',
      'notification_inbox_created_idx'
    ]) as index_name
  ),
  'hosted-statistics-confirmed unused indexes are retired'
);

select ok(
  to_regclass(
    'owntend_archive.profiles_legacy_media_user_id_idx'
  ) is not null
  and to_regclass(
    'owntend_archive.asset_photo_upload_metadata_user_id_idx'
  ) is not null
  and to_regclass(
    'public.asset_photos_user_id_asset_id_idx'
  ) is not null
  and to_regclass(
    'public.rooms_user_id_area_id_idx'
  ) is not null,
  'low-frequency account and relationship cascade indexes remain available'
);

select * from finish();
rollback;
