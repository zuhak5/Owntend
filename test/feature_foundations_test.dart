import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/domain/feature_models.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/domain/task_selectors.dart';
import 'package:owntend/src/core/services/feature_selectors.dart';
import 'package:owntend/src/core/utils/date_utils.dart' as hk_dates;

void main() {
  group('task selectors', () {
    test('bucket active tasks by local calendar day', () {
      final now = DateTime(2026, 6, 18, 18);
      final tasks = [
        _task('overdue', DateTime(2026, 6, 17, 23)),
        _task('today-early', DateTime(2026, 6, 18, 8)),
        _task('today-late', DateTime(2026, 6, 18, 23)),
        _task('tomorrow-late', DateTime(2026, 6, 19, 23)),
        _task('tomorrow-early', DateTime(2026, 6, 19, 8)),
        _task('next-seven', DateTime(2026, 6, 25, 9)),
        _task('later', DateTime(2026, 6, 26, 9)),
      ];

      final buckets = getTaskBuckets(tasks, now);

      expect(buckets.overdue.map((task) => task.plan.id), ['overdue']);
      expect(buckets.today.map((task) => task.plan.id), [
        'today-early',
        'today-late',
      ]);
      expect(buckets.tomorrow.map((task) => task.plan.id), [
        'tomorrow-early',
        'tomorrow-late',
      ]);
      expect(buckets.next7Days.map((task) => task.plan.id), ['next-seven']);
      expect(buckets.dueSoon.map((task) => task.plan.id), [
        'tomorrow-early',
        'tomorrow-late',
        'next-seven',
      ]);
      expect(buckets.next7DaysCount, 3);
      expect(buckets.later.map((task) => task.plan.id), ['later']);
      expect(
        activeTaskStatusForDueDate(DateTime(2026, 6, 18, 8), now),
        TaskStatus.dueToday,
      );
      expect(
        activeTaskStatusForDueDate(DateTime(2026, 6, 19, 8), now),
        TaskStatus.upcoming,
      );
    });

    test('item status selects the most urgent task bucket', () {
      final now = DateTime(2026, 6, 18, 18);
      final asset = _asset(id: 'asset_fish', name: 'Fish');
      final status = itemTaskStatusFor(asset, [
        _task(
          'future',
          DateTime(2026, 7, 1),
          asset: asset,
          priority: PriorityLevel.low,
        ),
        _task(
          'today',
          DateTime(2026, 6, 18, 9),
          asset: asset,
          priority: PriorityLevel.critical,
        ),
        _task('overdue', DateTime(2026, 6, 17), asset: asset),
      ], now);

      expect(status.status, ItemDueStatus.overdue);
      expect(status.label, '1 overdue');
      expect(status.count, 1);
    });

    test('item status distinguishes no tasks and on track', () {
      final now = DateTime(2026, 6, 18, 18);
      final asset = _asset(id: 'asset_snake_plant', name: 'Snake plant');

      expect(
        itemTaskStatusFor(asset, const [], now).status,
        ItemDueStatus.noTasks,
      );
      expect(
        itemTaskStatusFor(asset, [
          _task('later', DateTime(2026, 7, 1), asset: asset),
        ], now).status,
        ItemDueStatus.onTrack,
      );
    });

    test('inactive tasks are excluded from actionable date grouping', () {
      final now = DateTime(2026, 6, 18, 18);
      final asset = _asset(id: 'asset_filter', name: 'Filter');
      final disabled = _task(
        'disabled',
        DateTime(2026, 6, 1),
        asset: asset,
        isEnabled: false,
      );
      final completed = _task(
        'completed',
        DateTime(2026, 6, 18, 8),
        asset: asset,
        status: TaskStatus.completed,
      );
      final archived = _task(
        'archived',
        DateTime(2026, 6, 18, 9),
        asset: asset,
        archivedAt: DateTime(2026, 6, 18, 10),
      );
      final active = _task('active', DateTime(2026, 6, 18), asset: asset);

      final tasks = [disabled, completed, archived, active];
      final buckets = getTaskBuckets(tasks, now);
      final status = itemTaskStatusFor(asset, [disabled, archived], now);

      expect(buckets.overdue, isEmpty);
      expect(buckets.today.map((task) => task.plan.id), ['active']);
      expect(tasksDueOnDate(tasks, now), [active]);
      expect(groupTasksByDueDate(tasks).keys, [hk_dates.dateOnly(now)]);
      expect(status.status, ItemDueStatus.noTasks);
    });

    test('calendar grid renders each date once for June 2026', () {
      final grid = hk_dates.calendarMonthGrid(DateTime(2026, 6));
      final dates = [
        for (final week in grid)
          for (final day in week)
            if (day != null) day.day,
      ];

      expect(grid.every((week) => week.length == 7), isTrue);
      expect(dates, List.generate(30, (index) => index + 1));
      expect(dates.toSet(), hasLength(30));
    });
  });

  group('copy helpers', () {
    test('formats recurrence naturally', () {
      expect(
        const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days).label,
        'Every day',
      );
      expect(
        const RecurrenceRule(interval: 2, unit: RecurrenceUnit.weeks).label,
        'Every 2 weeks',
      );
    });
  });

  group('feature selectors', () {
    test('item health falls when tasks are overdue', () {
      final asset = _asset(id: 'asset', name: 'Smoke detector');
      final score = itemHealthScore(
        asset: asset,
        tasks: [
          _task(
            'critical',
            DateTime(2026, 6, 10),
            asset: asset,
            priority: PriorityLevel.critical,
            group: HealthGroup.safety,
          ),
        ],
        now: DateTime(2026, 6, 18),
      );

      expect(score.score, lessThan(100));
      expect(score.state, isNot(HealthState.excellent));
      expect(score.reasons.join(' '), contains('overdue'));
    });

    test('home readiness reflects overdue tasks and backup state', () {
      final room = _room();
      final asset = _asset(id: 'asset', name: 'Water heater');
      final readiness = homeReadiness(
        rooms: [room],
        assets: [asset],
        tasks: [_task('overdue', DateTime(2026, 6, 1), asset: asset)],
        backupState: const BackupState(),
        now: DateTime(2026, 6, 18),
      );

      expect(readiness, isNotNull);
      expect(readiness!.score, lessThan(100));
      expect(readiness.reasons.join(' '), contains('overdue'));
      expect(readiness.reasons.join(' '), contains('backup'));
    });

    test('disabled tasks do not make readiness eligible', () {
      final room = _room();
      final asset = _asset(id: 'asset', name: 'Water heater');
      final disabled = _task(
        'disabled',
        DateTime(2026, 6, 1),
        asset: asset,
        isEnabled: false,
      );

      final readiness = homeReadiness(
        rooms: [room],
        assets: [asset],
        tasks: [disabled],
        backupState: BackupState(
          lastBackup: BackupStatus(
            successful: true,
            updatedAt: DateTime(2026, 6, 18),
            trigger: BackupTrigger.manual,
          ),
        ),
        now: DateTime(2026, 6, 18),
      );

      expect(readiness, isNull);
      expect(smartPriorityTasks([disabled], DateTime(2026, 6, 18)), isEmpty);
    });

    test('home setup progress uses real source data', () {
      final room = _room();
      final asset = _asset(id: 'asset', name: 'Water heater');

      final empty = homeSetupProgress(
        rooms: const [],
        assets: const [],
        tasks: const [],
      );
      expect(empty.completedSteps, 0);
      expect(empty.nextStep, HomeSetupStep.room);
      expect(empty.isEligible, isFalse);

      final roomOnly = homeSetupProgress(
        rooms: [room],
        assets: const [],
        tasks: const [],
      );
      expect(roomOnly.completedSteps, 1);
      expect(roomOnly.nextStep, HomeSetupStep.maintainedItem);

      final itemAdded = homeSetupProgress(
        rooms: [room],
        assets: [asset],
        tasks: const [],
      );
      expect(itemAdded.completedSteps, 2);
      expect(itemAdded.nextStep, HomeSetupStep.scheduledTask);

      final eligible = homeSetupProgress(
        rooms: [room],
        assets: [asset],
        tasks: [_task('scheduled', DateTime(2026, 7, 1), asset: asset)],
      );
      expect(eligible.completedSteps, HomeSetupProgress.totalSteps);
      expect(eligible.nextStep, isNull);
      expect(eligible.isEligible, isTrue);
    });

    test('ineligible homes have no readiness score', () {
      expect(
        homeReadiness(
          rooms: const [],
          assets: const [],
          tasks: const [],
          backupState: const BackupState(),
          now: DateTime(2026, 6, 18),
        ),
        isNull,
      );
    });

    test(
      'room health score handles mixed maintained and unmaintained assets',
      () {
        final room = _room();
        final assetWithTask = _asset(id: 'asset_fridge', name: 'Fridge');
        final unmaintainedAsset = _asset(id: 'asset_table', name: 'Table');
        final now = DateTime(2026, 6, 18, 18);
        final tasks = [
          _task('fridge_task', DateTime(2026, 7, 18), asset: assetWithTask),
        ];

        // Room has 1 maintained item on track and 1 passive item with no maintenance plan.
        final mixedScore = roomHealthScore(
          room: room,
          assets: [assetWithTask, unmaintainedAsset],
          tasks: tasks,
          now: now,
        );
        expect(mixedScore.score, 100);
        expect(mixedScore.state, HealthState.excellent);

        // Room with only unmaintained assets returns insufficientData
        final unmaintainedScore = roomHealthScore(
          room: room,
          assets: [unmaintainedAsset],
          tasks: const [],
          now: now,
        );
        expect(unmaintainedScore.score, 0);
        expect(unmaintainedScore.state, HealthState.insufficientData);
      },
    );

    test('home readiness recommends next 7 days task when earlier buckets are clear', () {
      final room = _room();
      final asset = _asset(id: 'asset', name: 'Appliance');
      final now = DateTime(2026, 6, 18, 18);
      final readiness = homeReadiness(
        rooms: [room],
        assets: [asset],
        tasks: [
          _task(
            'due_soon',
            DateTime(2026, 6, 22),
            asset: asset,
            title: 'Clean filter',
          ),
        ],
        backupState: const BackupState(),
        now: now,
      );

      expect(readiness, isNotNull);
      expect(readiness!.nextBestAction, 'Clean filter');
    });

    test('item status onTrack uses the soonest upcoming due date', () {
      final asset = _asset(id: 'asset', name: 'HVAC');
      final now = DateTime(2026, 6, 18, 18);
      final tasks = [
        _task(
          'far_task',
          DateTime(2026, 9, 1),
          asset: asset,
          title: 'Yearly check',
        ),
        _task(
          'soon_task',
          DateTime(2026, 7, 15),
          asset: asset,
          title: 'Monthly clean',
        ),
      ];

      final status = itemTaskStatusFor(asset, tasks, now);
      expect(status.status, ItemDueStatus.onTrack);
      expect(status.nextDueAt, DateTime(2026, 7, 15));
    });

    test('warranty alerts are derived locally', () {
      final asset = _asset(
        id: 'asset',
        name: 'Washer',
        type: AssetType.device,
        warrantyUntil: DateTime(2026, 7, 1),
      );
      final now = DateTime(2026, 6, 18);

      expect(
        warrantyAlertsFor(assets: [asset], now: now).single.daysRemaining,
        13,
      );
    });
  });

  group('fresh install schema', () {
    test('new databases start empty with seeded categories', () async {
      final file = await File(
        '${Directory.systemTemp.path}/owntend_schema_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      ).create();
      final db = AppDatabase(executor: NativeDatabase(file));
      try {
        await db.customSelect('SELECT 1').get();
        final areas = await db.customSelect('SELECT id FROM areas').get();
        final categories = await db
            .customSelect('SELECT id FROM categories')
            .get();

        expect(db.schemaVersion, AppDatabase.currentSchemaVersion);
        expect(areas, isEmpty);
        expect(categories, isNotEmpty);
      } finally {
        await db.close();
        if (await file.exists()) {
          await file.delete();
        }
      }
    });
  });
}

TaskItem _task(
  String id,
  DateTime dueDate, {
  Asset? asset,
  String title = 'Task',
  PriorityLevel priority = PriorityLevel.medium,
  HealthGroup group = HealthGroup.appliances,
  bool isEnabled = true,
  TaskStatus? status,
  DateTime? archivedAt,
}) {
  final resolvedAsset = asset ?? _asset(id: 'asset_$id', name: 'Asset');
  final room = _room();
  return TaskItem(
    plan: MaintenancePlan(
      id: id,
      assetId: resolvedAsset.id,
      title: title,
      recurrence: const RecurrenceRule(
        interval: 1,
        unit: RecurrenceUnit.months,
      ),
      priority: priority,
      nextDueDate: dueDate,
      isEnabled: isEnabled,
      healthGroup: group,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      archivedAt: archivedAt,
    ),
    asset: resolvedAsset,
    room: room,
    status:
        status ??
        activeTaskStatusForDueDate(dueDate, DateTime(2026, 6, 18, 18)),
  );
}

Asset _asset({
  required String id,
  required String name,
  AssetType type = AssetType.general,
  DateTime? warrantyUntil,
}) {
  return Asset(
    id: id,
    name: name,
    assetType: type,
    roomId: 'room',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    deviceDetails: warrantyUntil == null
        ? null
        : DeviceDetails(warrantyUntil: warrantyUntil),
  );
}

Room _room() {
  return Room(
    id: 'room',
    name: 'Utility',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}
