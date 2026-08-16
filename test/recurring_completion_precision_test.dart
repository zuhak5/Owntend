import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/models.dart';

void main() {
  late AppDatabase db;
  late DriftAssetRepository assetRepo;
  late DriftMaintenanceRepository maintenance;

  setUp(() async {
    db = AppDatabase(executor: NativeDatabase.memory());
    assetRepo = DriftAssetRepository(db);
    maintenance = DriftMaintenanceRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'sub-second completion canonicalization and payload consistency',
    () async {
      await assetRepo.saveArea(
        id: 'area_kitchen',
        name: 'Kitchen',
        kind: AreaKind.indoor,
        sortOrder: 0,
      );
      final roomId = await assetRepo.saveRoom(
        areaId: 'area_kitchen',
        name: 'Kitchen',
      );
      final categories = await assetRepo.listCategories();
      final categoryId = categories.first.id;
      final assetId = await assetRepo.saveAsset(
        name: 'Water Filter',
        assetType: AssetType.device,
        categoryId: categoryId,
        roomId: roomId,
      );

      final originalDue = DateTime.utc(2026, 8, 7, 18, 0, 0);
      final planId = await maintenance.savePlan(
        assetId: assetId,
        title: 'Filter change',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.days,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: originalDue,
        healthGroup: HealthGroup.appliances,
      );

      // Sub-second completion timestamp with non-zero milliseconds and microseconds
      final fractionalCompletedAt = DateTime.utc(
        2026,
        8,
        7,
        18,
        13,
        27,
        842,
        731,
      );

      final result = await maintenance.completePlanResult(
        planId,
        completedAt: fractionalCompletedAt,
        expectedNextDueDate: originalDue,
      );

      expect(result.isApplied, isTrue);

      // Read plan and record back from local database
      final task = await maintenance.getTask(planId);
      expect(task, isNotNull);
      final records = await maintenance.listRecordsForPlan(planId);
      expect(records, hasLength(1));

      final record = records.single;
      final plan = task!.plan;

      // Local record completedAt and plan nextDueDate must be whole-second canonical
      expect(record.completedAt.millisecond, equals(0));
      expect(record.completedAt.microsecond, equals(0));
      expect(plan.nextDueDate.millisecond, equals(0));
      expect(plan.nextDueDate.microsecond, equals(0));

      // Inspect queued outbox mutation
      final outboxRows = await db.select(db.syncOutbox).get();
      final completionOutboxRows = outboxRows
          .where((row) => row.entity == 'maintenance_completion')
          .toList();
      expect(completionOutboxRows, hasLength(1));

      final outboxRow = completionOutboxRows.single;
      expect(outboxRow.entity, equals('maintenance_completion'));

      final payload =
          jsonDecode(outboxRow.payloadJson!) as Map<String, dynamic>;
      final payloadRecord = payload['record'] as Map<String, dynamic>;
      final payloadPlan = payload['plan'] as Map<String, dynamic>;

      final payloadCompletedAt = payloadRecord['completed_at'] as String;
      final payloadNextDueDate = payloadPlan['next_due_date'] as String;
      final payloadExpectedNextDueDate =
          payload['expected_next_due_date'] as String;

      // Outbox payload dates must equal stored Drift dates byte-for-byte
      expect(
        payloadCompletedAt,
        equals(record.completedAt.toUtc().toIso8601String()),
      );
      expect(
        payloadNextDueDate,
        equals(plan.nextDueDate.toUtc().toIso8601String()),
      );
      expect(
        payloadExpectedNextDueDate,
        equals(originalDue.toUtc().toIso8601String()),
      );

      expect(payloadCompletedAt, endsWith('.000Z'));
      expect(payloadNextDueDate, endsWith('.000Z'));

      // Perform a second completion for the next recurrence
      final secondFractionalCompletedAt = DateTime.utc(
        2026,
        8,
        8,
        18,
        14,
        10,
        123,
        456,
      );

      final secondResult = await maintenance.completePlanResult(
        planId,
        completedAt: secondFractionalCompletedAt,
        expectedNextDueDate: plan.nextDueDate,
      );

      expect(secondResult.isApplied, isTrue);

      final updatedTask = await maintenance.getTask(planId);
      expect(updatedTask!.plan.nextDueDate.millisecond, equals(0));
      expect(updatedTask.plan.nextDueDate.microsecond, equals(0));
    },
  );

  test(
    'early completion resets recurrence from actual completion time',
    () async {
      await assetRepo.saveArea(
        id: 'area_early',
        name: 'Early',
        kind: AreaKind.indoor,
        sortOrder: 0,
      );
      final roomId = await assetRepo.saveRoom(
        areaId: 'area_early',
        name: 'Early',
      );
      final categoryId = (await assetRepo.listCategories()).first.id;
      final assetId = await assetRepo.saveAsset(
        name: 'Monthly filter',
        assetType: AssetType.device,
        categoryId: categoryId,
        roomId: roomId,
      );
      final due = DateTime(2026, 8, 18, 9);
      final planId = await maintenance.savePlan(
        assetId: assetId,
        title: 'Monthly filter',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: due,
        healthGroup: HealthGroup.appliances,
      );
      final completedAt = DateTime(2026, 8, 13, 14, 30);
      final result = await maintenance.completePlanResult(
        planId,
        completedAt: completedAt,
        expectedNextDueDate: due,
      );
      expect(result.isApplied, isTrue);
      expect(result.duplicateIgnored, isFalse);
      expect(
        (await maintenance.getTask(planId))!.plan.nextDueDate.toLocal(),
        DateTime(2026, 9, 13, 14, 30),
      );
      final record = (await maintenance.listRecordsForPlan(planId)).single;
      expect(record.completedAt.toLocal(), DateTime(2026, 8, 13, 14, 30));
      expect(record.dueDate.toLocal(), due);
    },
  );

  test('rapid repeated completions use the action clock while a later action is allowed', () async {
    final actionNow = DateTime(2026, 8, 16, 14, 30, 10);
    var actionElapsed = Duration.zero;
    final guardedMaintenance = DriftMaintenanceRepository(
      db,
      now: () => actionNow,
      actionElapsed: () => actionElapsed,
    );
    await assetRepo.saveArea(
      id: 'area_repeat',
      name: 'Repeat',
      kind: AreaKind.indoor,
      sortOrder: 0,
    );
    final roomId = await assetRepo.saveRoom(
      areaId: 'area_repeat',
      name: 'Repeat',
    );
    final categoryId = (await assetRepo.listCategories()).first.id;
    final assetId = await assetRepo.saveAsset(
      name: 'Rapid task',
      categoryId: categoryId,
      roomId: roomId,
    );
    final due = DateTime(2026, 8, 17, 9);
    final planId = await guardedMaintenance.savePlan(
      assetId: assetId,
      title: 'Rapid task',
      recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days),
      priority: PriorityLevel.medium,
      nextDueDate: due,
      healthGroup: HealthGroup.other,
    );
    final firstAt = DateTime(2026, 8, 16, 14, 30, 10);
    final first = await guardedMaintenance.completePlanResult(
      planId,
      completedAt: firstAt,
      expectedNextDueDate: due,
    );
    expect(first.isApplied, isTrue);
    for (var i = 1; i <= 4; i++) {
      actionElapsed = Duration(milliseconds: 500 * i);
      final repeat = await guardedMaintenance.completePlanResult(
        planId,
        completedAt: i == 2
            ? firstAt.add(const Duration(hours: 1))
            : firstAt.add(Duration(milliseconds: 500 * i)),
        expectedNextDueDate: first.nextDueDate,
      );
      expect(repeat.isApplied, isTrue);
      expect(repeat.duplicateIgnored, isTrue);
      expect(repeat.operationId, first.operationId);
    }
    expect(await guardedMaintenance.listRecordsForPlan(planId), hasLength(1));
    expect(
      (await guardedMaintenance.getTask(planId))!.plan.nextDueDate.toLocal(),
      DateTime(2026, 8, 17, 14, 30, 10),
    );

    final afterWindowAt = firstAt.add(const Duration(seconds: 5));
    actionElapsed = const Duration(seconds: 5);
    final second = await guardedMaintenance.completePlanResult(
      planId,
      completedAt: afterWindowAt,
      expectedNextDueDate: first.nextDueDate,
    );
    expect(second.isApplied, isTrue);
    expect(second.duplicateIgnored, isFalse);
    expect(await guardedMaintenance.listRecordsForPlan(planId), hasLength(2));
    expect(
      (await guardedMaintenance.getTask(planId))!.plan.nextDueDate.toLocal(),
      DateTime(2026, 8, 17, 14, 30, 15),
    );
  });
  test('Undo clears the duplicate guard for an immediate legitimate re-completion', () async {
    var actionElapsed = Duration.zero;
    final now = DateTime(2026, 8, 16, 14, 30);
    final guardedMaintenance = DriftMaintenanceRepository(
      db,
      now: () => now,
      actionElapsed: () => actionElapsed,
    );
    await assetRepo.saveArea(
      id: 'area_undo_guard',
      name: 'Undo guard',
      kind: AreaKind.indoor,
      sortOrder: 0,
    );
    final roomId = await assetRepo.saveRoom(
      areaId: 'area_undo_guard',
      name: 'Undo guard',
    );
    final assetId = await assetRepo.saveAsset(
      name: 'Undo guard asset',
      categoryId: (await assetRepo.listCategories()).first.id,
      roomId: roomId,
    );
    final due = DateTime(2026, 8, 18, 9);
    final planId = await guardedMaintenance.savePlan(
      id: 'plan_undo_guard',
      assetId: assetId,
      title: 'Undo guard task',
      recurrence: const RecurrenceRule(
        interval: 1,
        unit: RecurrenceUnit.months,
      ),
      priority: PriorityLevel.medium,
      nextDueDate: due,
      healthGroup: HealthGroup.other,
    );
    final first = await guardedMaintenance.completePlanResult(
      planId,
      completedAt: now,
      expectedNextDueDate: due,
    );
    expect(first.isApplied, isTrue);
    await guardedMaintenance.undoCompletion(
      planId: planId,
      completionId: first.operationId!,
      previousDueDate: first.previousDueDate!,
      expectedCurrentNextDueDate: first.nextDueDate!,
    );

    actionElapsed = const Duration(seconds: 1);
    final second = await guardedMaintenance.completePlanResult(
      planId,
      completedAt: now.add(const Duration(minutes: 1)),
      expectedNextDueDate: due,
    );
    expect(second.isApplied, isTrue);
    expect(second.duplicateIgnored, isFalse);
    expect(second.operationId, isNot(first.operationId));
    expect(await guardedMaintenance.listRecordsForPlan(planId), hasLength(1));
  });

  test(
    'completion recurrence matrix anchors every supported unit to completedAt',
    () async {
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
    },
  );

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
      recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days),
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

  test(
    'month-end, leap-year, and UTC date-boundary recurrence remain precise',
    () async {
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
    },
  );
}
