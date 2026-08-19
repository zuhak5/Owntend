import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/services/health_score_calculator.dart';
import 'package:owntend/src/core/services/notification_service.dart';
import 'package:owntend/src/core/services/recurrence_engine.dart';
import 'package:owntend/src/core/utils/date_utils.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  group('Date utilities and DST safety', () {
    test(
      'daysBetweenDates accurately counts days across DST spring-forward',
      () {
        // March 10, 2024 to March 11, 2024 spans a 23-hour DST transition in US timezones
        final d1 = DateTime(2024, 3, 10);
        final d2 = DateTime(2024, 3, 11);
        expect(daysBetweenDates(d1, d2), 1);
        expect(daysBetweenDates(d2, d1), -1);

        final d3 = DateTime(2024, 3, 12);
        expect(daysBetweenDates(d1, d3), 2);
      },
    );

    test('daysBetweenDates accurately counts days across DST fall-back', () {
      // Nov 3, 2024 to Nov 4, 2024 spans a 25-hour DST transition in US timezones
      final d1 = DateTime(2024, 11, 3);
      final d2 = DateTime(2024, 11, 4);
      expect(daysBetweenDates(d1, d2), 1);
      expect(daysBetweenDates(d2, d1), -1);
    });

    test('endOfMonth includes all microseconds of the month', () {
      final end = endOfMonth(DateTime(2026, 2, 15));
      expect(end.year, 2026);
      expect(end.month, 2);
      expect(end.day, 28);
      expect(end.hour, 23);
      expect(end.minute, 59);
      expect(end.second, 59);
      expect(end.millisecond, 999);
      expect(end.microsecond, 999);

      final lateTimestamp = DateTime(2026, 2, 28, 23, 59, 59, 500);
      expect(
        lateTimestamp.isBefore(end) || lateTimestamp.isAtSameMomentAs(end),
        isTrue,
      );
    });
  });
  test(
    'notification scheduling preserves the instant when timezone hydrates',
    () {
      tz_data.initializeTimeZones();
      final instant = DateTime.utc(2026, 6, 28, 9, 45);
      tz.setLocalLocation(tz.UTC);
      final beforeHydration = notificationDateInConfiguredTimezone(instant);
      tz.setLocalLocation(tz.getLocation('Asia/Baghdad'));
      addTearDown(() => tz.setLocalLocation(tz.UTC));

      final scheduled = notificationDateInConfiguredTimezone(instant);

      expect(scheduled.location.name, 'Asia/Baghdad');
      expect(scheduled.millisecondsSinceEpoch, instant.millisecondsSinceEpoch);
      expect(
        scheduled.millisecondsSinceEpoch,
        beforeHydration.millisecondsSinceEpoch,
      );
      expect(scheduled.year, 2026);
      expect(scheduled.month, 6);
      expect(scheduled.day, 28);
      expect(scheduled.hour, 12);
      expect(scheduled.minute, 45);
    },
  );

  test('notification scheduling preserves instants across a DST zone', () {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/New_York'));
    addTearDown(() => tz.setLocalLocation(tz.UTC));
    final beforeTransition = DateTime.utc(2026, 3, 8, 6, 30);
    final afterTransition = DateTime.utc(2026, 3, 8, 7, 30);

    expect(
      notificationDateInConfiguredTimezone(beforeTransition)
          .millisecondsSinceEpoch,
      beforeTransition.millisecondsSinceEpoch,
    );
    expect(
      notificationDateInConfiguredTimezone(afterTransition)
          .millisecondsSinceEpoch,
      afterTransition.millisecondsSinceEpoch,
    );
  });

  group('OwntendRecurrenceEngine', () {
    const engine = OwntendRecurrenceEngine();

    test('adds day and week intervals from completion date', () {
      expect(
        engine.nextDueDate(
          DateTime(2026, 6, 13, 18, 45),
          const RecurrenceRule(interval: 3, unit: RecurrenceUnit.days),
        ),
        DateTime(2026, 6, 16, 18, 45),
      );
      expect(
        engine.nextDueDate(
          DateTime(2026, 6, 13, 7, 15, 10),
          const RecurrenceRule(interval: 2, unit: RecurrenceUnit.weeks),
        ),
        DateTime(2026, 6, 27, 7, 15, 10),
      );
    });

    test(
      'daily completion recurrence explains the observed 450-minute change',
      () {
        final previousTrigger = DateTime(2026, 7, 29, 9, 6);
        final completedAt = DateTime(2026, 7, 28, 16, 36);

        final nextTrigger = engine.nextDueDate(
          completedAt,
          const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days),
        );

        expect(nextTrigger, DateTime(2026, 7, 29, 16, 36));
        expect(
          nextTrigger.difference(previousTrigger),
          const Duration(minutes: 450),
        );
      },
    );

    test('adds hourly intervals from completion time', () {
      expect(
        engine.nextDueDate(
          DateTime(2026, 6, 13, 8, 0),
          const RecurrenceRule(interval: 6, unit: RecurrenceUnit.hours),
        ),
        DateTime(2026, 6, 13, 14, 0),
      );
    });

    test('clamps end-of-month monthly and yearly recurrence', () {
      expect(
        engine.nextDueDate(
          DateTime(2026, 1, 31),
          const RecurrenceRule(interval: 1, unit: RecurrenceUnit.months),
        ),
        DateTime(2026, 2, 28),
      );
      expect(
        engine.nextDueDate(
          DateTime(2024, 2, 29),
          const RecurrenceRule(interval: 1, unit: RecurrenceUnit.years),
        ),
        DateTime(2025, 2, 28),
      );
    });
  });

  group('WeightedHealthScoreCalculator', () {
    const calculator = WeightedHealthScoreCalculator();

    test('returns 100 when no weighted groups are active', () {
      final result = calculator.calculate(const [], DateTime(2026, 6, 13));

      expect(result.score, 100);
      expect(result.activeWeights, isEmpty);
    });

    test(
      'reweights active groups and penalizes overdue high priority plans',
      () {
        final now = DateTime(2026, 6, 13);
        final tasks = [
          _task(
            group: HealthGroup.safety,
            priority: PriorityLevel.critical,
            dueDate: DateTime(2026, 6, 8),
          ),
          _task(
            group: HealthGroup.appliances,
            priority: PriorityLevel.medium,
            dueDate: DateTime(2026, 6, 20),
          ),
        ];

        final result = calculator.calculate(tasks, now);

        expect(
          result.activeWeights.keys,
          containsAll([HealthGroup.safety, HealthGroup.appliances]),
        );
        expect(
          result.activeWeights.values.reduce((a, b) => a + b),
          closeTo(1, 0.0001),
        );
        expect(result.score, lessThan(100));
        expect(
          result.groupScores[HealthGroup.safety],
          lessThan(result.groupScores[HealthGroup.appliances]!),
        );
      },
    );
  });

  group('NotificationMessageGenerator', () {
    test('keeps deterministic task messages concise', () {
      const generator = NotificationMessageGenerator();
      final task = _task(
        group: HealthGroup.appliances,
        priority: PriorityLevel.medium,
        dueDate: DateTime(2026, 6, 13, 8),
      );
      final updatedAt = DateTime(2026, 6, 13);
      final streak = StreakState(
        currentStreak: 4,
        bestStreak: 7,
        updatedAt: updatedAt,
      );

      final message = generator.taskMessage(
        task: task,
        now: DateTime(2026, 6, 13, 9),
        streak: streak,
        dashboard: DashboardSummary(
          todayTasks: 1,
          upcomingTasks: 0,
          overdueTasks: 0,
          health: const HealthScoreBreakdown(
            score: 100,
            groupScores: {},
            activeWeights: {},
          ),
          streak: streak,
          completionRate: 0.75,
          completedThisMonth: 9,
        ),
      );

      expect(message.length, lessThanOrEqualTo(110));
      expect(message, isNot(contains('\n')));
      expect(
        message,
        anyOf(
          contains('streak'),
          contains('momentum'),
          contains('monthly'),
          contains('Asset'),
        ),
      );
    });

    test('task text includes overdue urgency without emoji', () {
      const generator = NotificationMessageGenerator();
      final task = _task(
        group: HealthGroup.cleaning,
        priority: PriorityLevel.critical,
        dueDate: DateTime(2026, 6, 10, 8),
      );

      final message = generator.taskMessage(
        task: task,
        now: DateTime(2026, 6, 13, 9),
      );
      final emojiMatches = RegExp(
        r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]',
        unicode: true,
      ).allMatches(message);

      expect(message.length, lessThanOrEqualTo(110));
      expect(message, isNot(contains('\n')));
      expect(message, contains('overdue'));
      expect(emojiMatches, isEmpty);
    });

    test('uses simple task text for regular reminders', () {
      const generator = NotificationMessageGenerator();
      final task = _task(
        group: HealthGroup.plants,
        priority: PriorityLevel.low,
        dueDate: DateTime(2026, 6, 14, 8),
      );

      final message = generator.taskMessage(
        task: task,
        now: DateTime(2026, 6, 13, 9),
      );

      expect(message, contains('Task'));
      expect(message, isNot(contains('overdue')));
    });
  });

  group('Android notification manifest', () {
    test('declares exact alarm permission and scheduled receivers', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();

      expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
      expect(
        manifest,
        contains(
          'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver',
        ),
      );
      expect(
        manifest,
        contains(
          'com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver',
        ),
      );
      expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
      expect(manifest, contains('android.intent.action.MY_PACKAGE_REPLACED'));
      expect(manifest, contains('android:allowBackup="false"'));
      expect(
        manifest,
        isNot(contains('android.permission.ACCESS_FINE_LOCATION')),
      );
    });
  });
}

TaskItem _task({
  required HealthGroup group,
  required PriorityLevel priority,
  required DateTime dueDate,
}) {
  final now = DateTime(2026, 1, 1);
  final asset = Asset(
    id: 'asset_$group',
    name: 'Asset',
    roomId: 'room',
    createdAt: now,
    updatedAt: now,
  );
  final room = Room(
    id: 'room',
    name: 'General',
    createdAt: now,
    updatedAt: now,
  );
  return TaskItem(
    plan: MaintenancePlan(
      id: 'plan_$group',
      assetId: asset.id,
      title: 'Task',
      recurrence: const RecurrenceRule(
        interval: 1,
        unit: RecurrenceUnit.months,
      ),
      priority: priority,
      nextDueDate: dueDate,
      healthGroup: group,
      createdAt: now,
      updatedAt: now,
    ),
    asset: asset,
    room: room,
    status: TaskStatus.upcoming,
  );
}
