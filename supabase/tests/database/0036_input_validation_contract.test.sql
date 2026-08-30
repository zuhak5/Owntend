begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(13);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '35353535-3535-4535-8535-353535353535',
  'authenticated', 'authenticated', 'validation@example.test', '',
  now(), now(), now()
);

insert into public.areas (
  user_id, id, name, kind, sort_order, created_at, updated_at
) values (
  '35353535-3535-4535-8535-353535353535',
  'validation-area', 'Validation area', 'indoor', 0, now(), now()
);

insert into public.rooms (
  user_id, id, area_id, name, room_type, sort_order, created_at, updated_at
) values (
  '35353535-3535-4535-8535-353535353535',
  'validation-room', 'validation-area', 'Validation room', 'other', 0,
  now(), now()
);

select extensions.lives_ok(
  $test$
  do $body$
  begin
    insert into public.assets (
      user_id, id, name, asset_type, room_id, placement, notes
    ) values (
      '35353535-3535-4535-8535-353535353535',
      'validation-asset', repeat('a', 200), 'device', 'validation-room',
      repeat('p', 300), repeat('n', 10000)
    );
    insert into public.device_details (
      user_id, asset_id, brand, model, serial_number, power_source,
      manual_url, consumable
    ) values (
      '35353535-3535-4535-8535-353535353535', 'validation-asset',
      repeat('b', 120), repeat('m', 120), repeat('s', 160), repeat('p', 80),
      repeat('u', 1000), repeat('c', 500)
    );
    insert into public.pet_details (
      user_id, asset_id, species, breed, microchip_id, vet_name, vet_phone,
      feeding_notes, medical_notes
    ) values (
      '35353535-3535-4535-8535-353535353535', 'validation-asset',
      repeat('s', 120), repeat('b', 120), repeat('m', 120), repeat('v', 200),
      repeat('p', 80), repeat('f', 4000), repeat('m', 4000)
    );
    insert into public.plant_details (
      user_id, asset_id, species, sunlight, watering_interval_days, pot_size,
      toxicity_notes
    ) values (
      '35353535-3535-4535-8535-353535353535', 'validation-asset',
      repeat('s', 200), repeat('l', 120), 1, repeat('p', 120), repeat('t', 4000)
    );
    insert into public.safety_details (
      user_id, asset_id, safety_type, battery_type, test_interval_days
    ) values (
      '35353535-3535-4535-8535-353535353535', 'validation-asset',
      repeat('s', 120), repeat('b', 120), 1
    );
    insert into public.maintenance_plans (
      user_id, id, asset_id, title, instructions, recurrence_interval,
      recurrence_unit, priority, next_due_date
    ) values (
      '35353535-3535-4535-8535-353535353535', 'validation-plan',
      'validation-asset', repeat('t', 200), repeat('i', 4000), 1, 'days',
      'medium', now()
    );
    insert into public.maintenance_plan_metadata (
      user_id, plan_id, task_type, location_label,
      estimated_duration_minutes, required_materials_json,
      reminder_recommendation
    ) values (
      '35353535-3535-4535-8535-353535353535', 'validation-plan',
      repeat('t', 120), repeat('l', 240), 0, repeat('m', 4000),
      repeat('r', 1000)
    );
  end;
  $body$;
  $test$,
  'authoritative maximum values are accepted across asset and task fields'
);

select extensions.throws_ok(
  $$insert into public.assets (user_id, id, name, asset_type, room_id)
    values ('35353535-3535-4535-8535-353535353535', 'too-long-name',
      repeat('a', 201), 'general', 'validation-room')$$,
  '23514',
  'new row for relation "assets" violates check constraint "assets_name_check"',
  'asset name max + 1 is rejected'
);

select extensions.throws_ok(
  $$update public.device_details set manual_url = repeat('u', 1001)
    where asset_id = 'validation-asset'$$,
  '23514',
  'new row for relation "device_details" violates check constraint "device_details_manual_url_check"',
  'device manual URL max + 1 is rejected'
);

select extensions.throws_ok(
  $$update public.pet_details set feeding_notes = repeat('f', 4001)
    where asset_id = 'validation-asset'$$,
  '23514',
  'new row for relation "pet_details" violates check constraint "pet_details_feeding_notes_check"',
  'pet notes max + 1 is rejected'
);

select extensions.throws_ok(
  $$update public.plant_details set toxicity_notes = repeat('t', 4001)
    where asset_id = 'validation-asset'$$,
  '23514',
  'new row for relation "plant_details" violates check constraint "plant_details_toxicity_notes_check"',
  'plant notes max + 1 is rejected'
);

select extensions.throws_ok(
  $$update public.maintenance_plan_metadata
    set required_materials_json = repeat('m', 4001)
    where plan_id = 'validation-plan'$$,
  '23514',
  'new row for relation "maintenance_plan_metadata" violates check constraint "maintenance_plan_metadata_required_materials_json_check"',
  'serialized materials max + 1 is rejected'
);

select extensions.throws_ok(
  $$update public.plant_details set watering_interval_days = 0
    where asset_id = 'validation-asset'$$,
  '23514',
  'new row for relation "plant_details" violates check constraint "plant_details_watering_interval_days_check"',
  'zero watering interval is rejected'
);

select extensions.throws_ok(
  $$update public.plant_details set watering_interval_days = -1
    where asset_id = 'validation-asset'$$,
  '23514',
  'new row for relation "plant_details" violates check constraint "plant_details_watering_interval_days_check"',
  'negative watering interval is rejected'
);

select extensions.throws_ok(
  $$update public.safety_details set test_interval_days = 0
    where asset_id = 'validation-asset'$$,
  '23514',
  'new row for relation "safety_details" violates check constraint "safety_details_test_interval_days_check"',
  'zero safety test interval is rejected'
);

select extensions.throws_ok(
  $$update public.safety_details set test_interval_days = -1
    where asset_id = 'validation-asset'$$,
  '23514',
  'new row for relation "safety_details" violates check constraint "safety_details_test_interval_days_check"',
  'negative safety test interval is rejected'
);

select extensions.throws_ok(
  $$update public.maintenance_plan_metadata set estimated_duration_minutes = -1
    where plan_id = 'validation-plan'$$,
  '23514',
  'new row for relation "maintenance_plan_metadata" violates check constraint "maintenance_plan_metadata_estimated_duration_minutes_check"',
  'negative estimated duration is rejected'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '35353535-3535-4535-8535-353535353535',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

select extensions.throws_ok(
  $$select public.create_asset(jsonb_build_object(
      'operation_id', '35353535-0000-4000-8000-000000000001',
      'request_hash', repeat('a', 64),
      'asset', jsonb_build_object(
        'id', 'rpc-invalid-asset', 'name', repeat('a', 201),
        'asset_type', 'general', 'room_id', 'validation-room'
      ),
      'details', '{}'::jsonb
    ))$$,
  '22023',
  'INVALID_ASSET_PAYLOAD',
  'asset RPC returns the stable invalid-payload taxonomy'
);

select extensions.throws_ok(
  $$select public.create_task_with_point_debit(jsonb_build_object(
      'operation_id', '35353535-0000-4000-8000-000000000002',
      'request_hash', repeat('b', 64),
      'plan', jsonb_build_object(
        'id', 'rpc-invalid-plan', 'asset_id', 'validation-asset',
        'title', repeat('t', 201), 'recurrence_interval', 1,
        'recurrence_unit', 'days', 'priority', 'medium',
        'next_due_date', now() + interval '1 day'
      )
    ))$$,
  '22023',
  'INVALID_TASK_PAYLOAD',
  'task RPC returns the stable invalid-payload taxonomy'
);

select * from extensions.finish();
rollback;
