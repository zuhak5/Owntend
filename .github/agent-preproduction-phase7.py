from pathlib import Path

migration_path = Path('supabase/migrations/20260816163000_preproduction_completion_integrity.sql')
migration = migration_path.read_text()
old = """    IF current_record.id <> record_id_value
        OR current_record.plan_id <> plan_id_value
        OR date_trunc('second', current_record.due_date) IS DISTINCT FROM record_due_date
        OR COALESCE(NULLIF(TRIM(current_record.notes), ''), '') IS DISTINCT FROM COALESCE(NULLIF(TRIM(record_payload ->> 'notes'), ''), '') THEN
"""
new = """    IF current_record.id <> record_id_value
        OR current_record.plan_id <> plan_id_value
        OR date_trunc('second', current_record.due_date) IS DISTINCT FROM record_due_date
        OR date_trunc('second', current_record.completed_at) IS DISTINCT FROM record_completed_at
        OR COALESCE(NULLIF(TRIM(current_record.notes), ''), '') IS DISTINCT FROM COALESCE(NULLIF(TRIM(record_payload ->> 'notes'), ''), '') THEN
"""
if old not in migration:
    raise SystemExit('completion idempotency block did not match')
migration_path.write_text(migration.replace(old, new, 1))

sql_path = Path('supabase/tests/database/0011_complete_maintenance_task.test.sql')
sql = sql_path.read_text()
if 'select plan(46);' not in sql:
    raise SystemExit('pgTAP plan count did not match')
sql = sql.replace('select plan(46);', 'select plan(50);', 1)

anchor = """set local request.jwt.claims =
  '{\"sub\":\"33333333-3333-3333-3333-333333333333\",\"role\":\"authenticated\"}';
set local role authenticated;

"""
if anchor not in sql:
    raise SystemExit('authenticated test anchor did not match')
insert_plan = """insert into public.maintenance_plans (
  user_id,
  id,
  asset_id,
  title,
  interval_count,
  interval_unit,
  priority,
  next_due_date,
  reminder_days_before,
  health_group,
  is_enabled,
  revision,
  created_at,
  updated_at
)
values (
  '33333333-3333-3333-3333-333333333333',
  'rpc-early-plan',
  'rpc-asset',
  'Early daily task',
  1,
  'days',
  'medium',
  '2026-08-18 09:00:00+00',
  0,
  'other',
  true,
  1,
  '2026-08-01 00:00:00+00',
  '2026-08-01 00:00:00+00'
);

"""
sql = sql.replace(anchor, insert_plan + anchor, 1)

early_test = """select is(
  (
    public.complete_maintenance_task(
      jsonb_build_object(
        'version', 2,
        'operation_id', 'rpc-early-record',
        'expected_next_due_date', '2026-08-18T09:00:00.000Z',
        'plan', jsonb_build_object(
          'id', 'rpc-early-plan',
          'asset_id', 'rpc-asset',
          'title', 'Early daily task',
          'recurrence_interval', 1,
          'recurrence_unit', 'days',
          'priority', 'medium',
          'next_due_date', '2026-08-14T14:30:00.000Z',
          'reminder_days_before', 0,
          'is_enabled', true,
          'health_group', 'other',
          'created_at', '2026-08-01T00:00:00.000Z',
          'updated_at', '2026-08-13T14:30:00.000Z'
        ),
        'record', jsonb_build_object(
          'id', 'rpc-early-record',
          'plan_id', 'rpc-early-plan',
          'due_date', '2026-08-18T09:00:00.000Z',
          'completed_at', '2026-08-13T14:30:00.000Z'
        )
      ),
      'rpc-device-early'
    ) ->> 'status'
  ),
  'applied',
  'early completion accepts a next due date based on actual completion even when it precedes the old due date'
);

set local role postgres;

select is(
  (
    select next_due_date
    from public.maintenance_plans
    where user_id = '33333333-3333-3333-3333-333333333333'
      and id = 'rpc-early-plan'
  ),
  '2026-08-14 14:30:00+00'::timestamptz,
  'early daily completion stores actual completedAt plus one day'
);

set local role authenticated;

"""
sql = sql.replace(anchor, anchor + early_test, 1)

idempotent_anchor = """select is(
  (
    public.complete_maintenance_task(
      $json$
      {
        \"version\": 1,
        \"operation_id\": \"rpc-record-1\",
        \"expected_next_due_date\": \"2026-07-01T00:00:00.000Z\",
        \"plan\": {
          \"id\": \"rpc-plan\",
          \"asset_id\": \"rpc-asset\",
          \"title\": \"Replace RPC filter\",
          \"instructions\": \"Replace the test filter\",
          \"recurrence_interval\": 1,
          \"recurrence_unit\": \"months\",
          \"priority\": \"medium\",
          \"next_due_date\": \"2026-08-01T00:00:00.000Z\",
          \"reminder_days_before\": 3,
          \"is_enabled\": true,
          \"health_group\": \"other\",
          \"created_at\": \"2026-06-01T00:00:00.000Z\",
          \"updated_at\": \"2026-07-01T10:00:00.000Z\",
          \"archived_at\": null
        },
        \"record\": {
          \"id\": \"rpc-record-1\",
          \"plan_id\": \"rpc-plan\",
          \"due_date\": \"2026-07-01T00:00:00.000Z\",
          \"completed_at\": \"2026-07-01T09:00:00.000Z\",
          \"notes\": \"First completion\"
        }
      }
      $json$::jsonb,
      'rpc-device'
    ) -> 'record' ->> 'id'
  ),
  'rpc-record-1',
  'an idempotent retry returns the canonical record'
);

"""
if idempotent_anchor not in sql:
    raise SystemExit('idempotent retry anchor did not match')
idempotency_tests = """select is(
  (
    public.complete_maintenance_task(
      jsonb_build_object(
        'version', 2,
        'operation_id', 'rpc-record-1',
        'expected_next_due_date', '2026-07-01T00:00:00.000Z',
        'plan', jsonb_build_object(
          'id', 'rpc-plan',
          'asset_id', 'rpc-asset',
          'title', 'Replace RPC filter',
          'recurrence_interval', 1,
          'recurrence_unit', 'months',
          'priority', 'medium',
          'next_due_date', '2026-08-01T00:00:00.000Z',
          'reminder_days_before', 3,
          'is_enabled', true,
          'health_group', 'other',
          'created_at', '2026-06-01T00:00:00.000Z',
          'updated_at', '2026-07-01T10:00:00.000Z'
        ),
        'record', jsonb_build_object(
          'id', 'rpc-record-1',
          'plan_id', 'rpc-plan',
          'due_date', '2026-07-01T00:00:00.000Z',
          'completed_at', '2026-07-01T09:01:00.000Z',
          'notes', 'First completion'
        )
      ),
      'rpc-device'
    ) ->> 'status'
  ),
  'conflict',
  'reusing a completion operation with a different completedAt is rejected'
);

select is(
  (
    public.complete_maintenance_task(
      jsonb_build_object(
        'version', 2,
        'operation_id', 'rpc-record-1',
        'expected_next_due_date', '2026-07-01T00:00:00.000Z',
        'plan', jsonb_build_object(
          'id', 'rpc-plan',
          'asset_id', 'rpc-asset',
          'title', 'Replace RPC filter',
          'recurrence_interval', 1,
          'recurrence_unit', 'months',
          'priority', 'medium',
          'next_due_date', '2026-08-01T00:00:00.000Z',
          'reminder_days_before', 3,
          'is_enabled', true,
          'health_group', 'other',
          'created_at', '2026-06-01T00:00:00.000Z',
          'updated_at', '2026-07-01T10:00:00.000Z'
        ),
        'record', jsonb_build_object(
          'id', 'rpc-record-1',
          'plan_id', 'rpc-plan',
          'due_date', '2026-07-01T00:00:00.000Z',
          'completed_at', '2026-07-01T09:01:00.000Z',
          'notes', 'First completion'
        )
      ),
      'rpc-device'
    ) ->> 'conflict_reason'
  ),
  'operation_id_reused',
  'completedAt mismatch reports operation_id_reused'
);

"""
sql = sql.replace(idempotent_anchor, idempotent_anchor + idempotency_tests, 1)
sql_path.write_text(sql)

dart_path = Path('test/recurring_completion_precision_test.dart')
dart = dart_path.read_text()
closing = '\n}\n'
if not dart.endswith(closing):
    raise SystemExit('Dart test file closing did not match')
extra = r'''
  test('completion recurrence matrix anchors every supported unit to completedAt', () async {
    await assetRepo.saveArea(
      id: 'area_matrix',
      name: 'Matrix',
      kind: AreaKind.indoor,
      sortOrder: 0,
    );
    final roomId = await assetRepo.saveRoom(
      areaId: 'area_matrix',
      name: 'Matrix',
    );
    final categoryId = (await assetRepo.listCategories()).first.id;
    final assetId = await assetRepo.saveAsset(
      name: 'Matrix asset',
      categoryId: categoryId,
      roomId: roomId,
    );
    final due = DateTime(2026, 8, 18, 9);
    final completedAt = DateTime(2026, 8, 13, 14, 30);
    final cases = <(String, RecurrenceRule, DateTime)>[
      (
        'hours',
        const RecurrenceRule(interval: 6, unit: RecurrenceUnit.hours),
        DateTime(2026, 8, 13, 20, 30),
      ),
      (
        'days',
        const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days),
        DateTime(2026, 8, 14, 14, 30),
      ),
      (
        'weeks',
        const RecurrenceRule(interval: 1, unit: RecurrenceUnit.weeks),
        DateTime(2026, 8, 20, 14, 30),
      ),
      (
        'months',
        const RecurrenceRule(interval: 1, unit: RecurrenceUnit.months),
        DateTime(2026, 9, 13, 14, 30),
      ),
      (
        'years',
        const RecurrenceRule(interval: 1, unit: RecurrenceUnit.years),
        DateTime(2027, 8, 13, 14, 30),
      ),
    ];

    for (final (name, rule, expected) in cases) {
      final planId = await maintenance.savePlan(
        id: 'plan_matrix_$name',
        assetId: assetId,
        title: 'Matrix $name',
        recurrence: rule,
        priority: PriorityLevel.medium,
        nextDueDate: due,
        healthGroup: HealthGroup.other,
      );
      final result = await maintenance.completePlanResult(
        planId,
        completedAt: completedAt,
        expectedNextDueDate: due,
      );
      expect(result.isApplied, isTrue, reason: name);
      expect(
        (await maintenance.getTask(planId))!.plan.nextDueDate.toLocal(),
        expected,
        reason: name,
      );
      final record = (await maintenance.listRecordsForPlan(planId)).single;
      expect(record.completedAt.toLocal(), completedAt, reason: name);
      expect(record.dueDate.toLocal(), due, reason: name);
    }
  });

  test('exact and late completions preserve actual date and time', () async {
    await assetRepo.saveArea(
      id: 'area_timing',
      name: 'Timing',
      kind: AreaKind.indoor,
      sortOrder: 0,
    );
    final roomId = await assetRepo.saveRoom(
      areaId: 'area_timing',
      name: 'Timing',
    );
    final categoryId = (await assetRepo.listCategories()).first.id;
    final assetId = await assetRepo.saveAsset(
      name: 'Timing asset',
      categoryId: categoryId,
      roomId: roomId,
    );

    final exactDue = DateTime(2026, 8, 18, 9, 12, 34);
    final exactPlan = await maintenance.savePlan(
      id: 'plan_exact',
      assetId: assetId,
      title: 'Exact',
      recurrence: const RecurrenceRule(
        interval: 1,
        unit: RecurrenceUnit.days,
      ),
      priority: PriorityLevel.medium,
      nextDueDate: exactDue,
      healthGroup: HealthGroup.other,
    );
    await maintenance.completePlanResult(
      exactPlan,
      completedAt: exactDue,
      expectedNextDueDate: exactDue,
    );
    expect(
      (await maintenance.getTask(exactPlan))!.plan.nextDueDate.toLocal(),
      DateTime(2026, 8, 19, 9, 12, 34),
    );

    final lateDue = DateTime(2026, 8, 18, 9);
    final lateAt = DateTime(2026, 8, 20, 10, 45, 17);
    final latePlan = await maintenance.savePlan(
      id: 'plan_late',
      assetId: assetId,
      title: 'Late',
      recurrence: const RecurrenceRule(
        interval: 1,
        unit: RecurrenceUnit.months,
      ),
      priority: PriorityLevel.medium,
      nextDueDate: lateDue,
      healthGroup: HealthGroup.other,
    );
    await maintenance.completePlanResult(
      latePlan,
      completedAt: lateAt,
      expectedNextDueDate: lateDue,
    );
    expect(
      (await maintenance.getTask(latePlan))!.plan.nextDueDate.toLocal(),
      DateTime(2026, 9, 20, 10, 45, 17),
    );
  });

  test('month-end, leap-year, and UTC date-boundary recurrence remain precise', () async {
    await assetRepo.saveArea(
      id: 'area_calendar_edges',
      name: 'Calendar edges',
      kind: AreaKind.indoor,
      sortOrder: 0,
    );
    final roomId = await assetRepo.saveRoom(
      areaId: 'area_calendar_edges',
      name: 'Calendar edges',
    );
    final categoryId = (await assetRepo.listCategories()).first.id;
    final assetId = await assetRepo.saveAsset(
      name: 'Calendar asset',
      categoryId: categoryId,
      roomId: roomId,
    );

    Future<void> verify({
      required String id,
      required DateTime completedAt,
      required RecurrenceRule rule,
      required DateTime expected,
    }) async {
      final planId = await maintenance.savePlan(
        id: id,
        assetId: assetId,
        title: id,
        recurrence: rule,
        priority: PriorityLevel.medium,
        nextDueDate: completedAt,
        healthGroup: HealthGroup.other,
      );
      await maintenance.completePlanResult(
        planId,
        completedAt: completedAt,
        expectedNextDueDate: completedAt,
      );
      expect(
        (await maintenance.getTask(planId))!.plan.nextDueDate.toUtc(),
        expected.toUtc(),
        reason: id,
      );
    }

    await verify(
      id: 'month_end',
      completedAt: DateTime(2026, 1, 31, 23, 15),
      rule: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.months),
      expected: DateTime(2026, 2, 28, 23, 15),
    );
    await verify(
      id: 'leap_year',
      completedAt: DateTime(2024, 2, 29, 6, 5),
      rule: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.years),
      expected: DateTime(2025, 2, 28, 6, 5),
    );
    await verify(
      id: 'utc_boundary',
      completedAt: DateTime.utc(2026, 8, 13, 21, 30),
      rule: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days),
      expected: DateTime.utc(2026, 8, 14, 21, 30),
    );
  });
'''
dart_path.write_text(dart[:-len(closing)] + extra + closing)
