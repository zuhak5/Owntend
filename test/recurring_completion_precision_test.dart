import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/contracts.dart';
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
      final assetId = await assetRepo.saveAsset(
        name: 'Water Filter',
        assetType: AssetType.device,
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
      );
      final firstOccurrenceId = (await maintenance.getTask(planId))!
          .plan
          .currentOccurrenceId;

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
        expectedOccurrenceId: firstOccurrenceId,
        completedAt: fractionalCompletedAt,
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
      final payloadCompletedAt = payload['completed_at'] as String;

      // Outbox payload dates must equal stored Drift dates byte-for-byte
      expect(
        payloadCompletedAt,
        equals(record.completedAt.toUtc().toIso8601String()),
      );
      expect(payload['contract_version'], 1);
      expect(payload['occurrence_id'], firstOccurrenceId);
      expect(payload.containsKey('plan'), isFalse);
      expect(payload.containsKey('record'), isFalse);
      expect(payload.containsKey('expected_next_due_date'), isFalse);

      expect(payloadCompletedAt, endsWith('.000Z'));

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
        expectedOccurrenceId: plan.currentOccurrenceId,
        completedAt: secondFractionalCompletedAt,
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
      final assetId = await assetRepo.saveAsset(
        name: 'Monthly filter',
        assetType: AssetType.device,
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
      );
      final completedAt = DateTime(2026, 8, 13, 14, 30);
      final occurrenceId = (await maintenance.getTask(planId))!
          .plan
          .currentOccurrenceId;
      final result = await maintenance.completePlanResult(
        planId,
        expectedOccurrenceId: occurrenceId,
        completedAt: completedAt,
      );
      expect(result.isApplied, isTrue);
      expect(
        (await maintenance.getTask(planId))!.plan.nextDueDate.toLocal(),
        DateTime(2026, 9, 13, 14, 30),
      );
      final record = (await maintenance.listRecordsForPlan(planId)).single;
      expect(record.completedAt.toLocal(), DateTime(2026, 8, 13, 14, 30));
      expect(record.dueDate.toLocal(), due);
    },
  );

  test('occurrence and operation identities distinguish replay, loser, and next occurrence', () async {
    final actionNow = DateTime(2026, 8, 16, 14, 30, 10);
    final guardedMaintenance = DriftMaintenanceRepository(
      db,
      now: () => actionNow,
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
    final assetId = await assetRepo.saveAsset(
      name: 'Rapid task',
      roomId: roomId,
    );
    final due = DateTime(2026, 8, 17, 9);
    final planId = await guardedMaintenance.savePlan(
      assetId: assetId,
      title: 'Rapid task',
      recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days),
      priority: PriorityLevel.medium,
      nextDueDate: due,
    );
    final firstOccurrenceId = (await guardedMaintenance.getTask(planId))!
        .plan
        .currentOccurrenceId;
    final firstAt = DateTime(2026, 8, 16, 14, 30, 10);
    final first = await guardedMaintenance.completePlanResult(
      planId,
      expectedOccurrenceId: firstOccurrenceId,
      operationId: 'operation-repeat',
      completedAt: firstAt,
    );
    expect(first.isApplied, isTrue);
    final replay = await guardedMaintenance.completePlanResult(
      planId,
      expectedOccurrenceId: firstOccurrenceId,
      operationId: 'operation-repeat',
      completedAt: firstAt.add(const Duration(milliseconds: 250)),
    );
    expect(
      replay.status,
      LocalMaintenanceCompletionStatus.alreadyAppliedByThisOperation,
    );
    final loser = await guardedMaintenance.completePlanResult(
      planId,
      expectedOccurrenceId: firstOccurrenceId,
      operationId: 'operation-other-screen',
      completedAt: firstAt.add(const Duration(milliseconds: 500)),
    );
    expect(loser.status, LocalMaintenanceCompletionStatus.completedElsewhere);
    expect(await guardedMaintenance.listRecordsForPlan(planId), hasLength(1));

    final nextOccurrenceId = (await guardedMaintenance.getTask(planId))!
        .plan
        .currentOccurrenceId;
    final second = await guardedMaintenance.completePlanResult(
      planId,
      expectedOccurrenceId: nextOccurrenceId,
      completedAt: firstAt.add(const Duration(seconds: 1)),
    );
    expect(second.isApplied, isTrue);
    expect(await guardedMaintenance.listRecordsForPlan(planId), hasLength(2));
    expect(
      (await guardedMaintenance.getTask(planId))!.plan.nextDueDate.toLocal(),
      DateTime(2026, 8, 17, 14, 30, 11),
    );
  });
  test(
    'Undo restores occurrence identity for immediate re-completion',
    () async {
      final now = DateTime(2026, 8, 16, 14, 30);
      final guardedMaintenance = DriftMaintenanceRepository(db, now: () => now);
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
      );
      final occurrenceId = (await guardedMaintenance.getTask(planId))!
          .plan
          .currentOccurrenceId;
      final first = await guardedMaintenance.completePlanResult(
        planId,
        expectedOccurrenceId: occurrenceId,
        completedAt: now,
      );
      expect(first.isApplied, isTrue);
      await guardedMaintenance.undoCompletion(
        planId: planId,
        completionId: first.operationId!,
        completedOccurrenceId: first.completedOccurrenceId!,
        expectedCurrentOccurrenceId: first.nextOccurrenceId!,
        previousDueDate: first.previousDueDate!,
        expectedCurrentNextDueDate: first.nextDueDate!,
      );

      final second = await guardedMaintenance.completePlanResult(
        planId,
        expectedOccurrenceId: occurrenceId,
        completedAt: now.add(const Duration(minutes: 1)),
      );
      expect(second.isApplied, isTrue);
      expect(second.operationId, isNot(first.operationId));
      expect(await guardedMaintenance.listRecordsForPlan(planId), hasLength(1));
    },
  );

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
      final assetId = await assetRepo.saveAsset(
        name: 'Matrix asset',
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
        );
        final result = await maintenance.completePlanResult(
          planId,
          expectedOccurrenceId: (await maintenance.getTask(planId))!
              .plan
              .currentOccurrenceId,
          completedAt: completedAt,
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
    final assetId = await assetRepo.saveAsset(
      name: 'Timing asset',
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
    );
    await maintenance.completePlanResult(
      exactPlan,
      expectedOccurrenceId: (await maintenance.getTask(exactPlan))!
          .plan
          .currentOccurrenceId,
      completedAt: exactDue,
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
    );
    await maintenance.completePlanResult(
      latePlan,
      expectedOccurrenceId: (await maintenance.getTask(latePlan))!
          .plan
          .currentOccurrenceId,
      completedAt: lateAt,
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
      final assetId = await assetRepo.saveAsset(
        name: 'Calendar asset',
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
        );
        await maintenance.completePlanResult(
          planId,
          expectedOccurrenceId: (await maintenance.getTask(planId))!
              .plan
              .currentOccurrenceId,
          completedAt: completedAt,
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

  test(
    'operation replay remains idempotent after a file-backed database reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'owntend-occurrence-reopen-',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final file = File('${directory.path}/owntend.sqlite');
      var restartDb = AppDatabase(executor: NativeDatabase(file));
      final restartAssets = DriftAssetRepository(restartDb);
      var restartMaintenance = DriftMaintenanceRepository(restartDb);

      await restartAssets.saveArea(
        id: 'area_durable_dedupe',
        name: 'Durable Dedupe',
        kind: AreaKind.indoor,
        sortOrder: 0,
      );
      final roomId = await restartAssets.saveRoom(
        areaId: 'area_durable_dedupe',
        name: 'Durable Room',
      );
      final assetId = await restartAssets.saveAsset(
        name: 'Durable Device',
        roomId: roomId,
      );
      final planId = await restartMaintenance.savePlan(
        assetId: assetId,
        title: 'Water filter check',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.high,
        nextDueDate: DateTime.utc(2026, 9, 1, 9),
      );
      final occurrenceId = (await restartMaintenance.getTask(planId))!
          .plan
          .currentOccurrenceId;
      final firstResult = await restartMaintenance.completePlanResult(
        planId,
        expectedOccurrenceId: occurrenceId,
        operationId: 'durable-completion-operation',
        completedAt: DateTime.utc(2026, 9, 1, 9, 15),
      );
      expect(firstResult.isApplied, isTrue);
      await restartDb.close();

      restartDb = AppDatabase(executor: NativeDatabase(file));
      restartMaintenance = DriftMaintenanceRepository(restartDb);
      addTearDown(restartDb.close);

      final replay = await restartMaintenance.completePlanResult(
        planId,
        expectedOccurrenceId: occurrenceId,
        operationId: 'durable-completion-operation',
        completedAt: DateTime.utc(2026, 9, 1, 9, 20),
      );
      expect(
        replay.status,
        LocalMaintenanceCompletionStatus.alreadyAppliedByThisOperation,
      );
      expect(replay.operationId, firstResult.operationId);
      expect(await restartMaintenance.listRecordsForPlan(planId), hasLength(1));
    },
  );
}
