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

  test('rapid repeated completions are idempotent but a later completion is allowed', () async {
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
    final planId = await maintenance.savePlan(
      assetId: assetId,
      title: 'Rapid task',
      recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days),
      priority: PriorityLevel.medium,
      nextDueDate: due,
      healthGroup: HealthGroup.other,
    );
    final firstAt = DateTime(2026, 8, 16, 14, 30, 10);
    final first = await maintenance.completePlanResult(
      planId,
      completedAt: firstAt,
      expectedNextDueDate: due,
    );
    expect(first.isApplied, isTrue);
    for (var i = 1; i <= 4; i++) {
      final repeat = await maintenance.completePlanResult(
        planId,
        completedAt: firstAt.add(Duration(milliseconds: 500 * i)),
        expectedNextDueDate: first.nextDueDate,
      );
      expect(repeat.isApplied, isTrue);
      expect(repeat.duplicateIgnored, isTrue);
      expect(repeat.operationId, first.operationId);
    }
    expect(await maintenance.listRecordsForPlan(planId), hasLength(1));
    expect(
      (await maintenance.getTask(planId))!.plan.nextDueDate.toLocal(),
      DateTime(2026, 8, 17, 14, 30, 10),
    );

    final afterWindowAt = firstAt.add(const Duration(seconds: 5));
    final second = await maintenance.completePlanResult(
      planId,
      completedAt: afterWindowAt,
      expectedNextDueDate: first.nextDueDate,
    );
    expect(second.isApplied, isTrue);
    expect(second.duplicateIgnored, isFalse);
    expect(await maintenance.listRecordsForPlan(planId), hasLength(2));
    expect(
      (await maintenance.getTask(planId))!.plan.nextDueDate.toLocal(),
      DateTime(2026, 8, 17, 14, 30, 15),
    );
  });
}
