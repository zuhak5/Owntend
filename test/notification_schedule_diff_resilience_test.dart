import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/services/notification_service.dart';
import 'package:owntend/src/core/services/reminder_schedule_reconciler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class _MockFlutterLocalNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
    registerFallbackValue(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    registerFallbackValue(tz.TZDateTime.now(tz.UTC));
    registerFallbackValue(const NotificationDetails());
    registerFallbackValue(AndroidScheduleMode.inexactAllowWhileIdle);
  });

  group('Notification Schedule Diff Resilience (BUG-08)', () {
    late AppDatabase db;
    late MemoryReminderScheduleStore store;
    late DriftMaintenanceRepository maintenance;
    late DriftSettingsRepository settings;
    late _MockFlutterLocalNotificationsPlugin plugin;

    setUp(() async {
      db = AppDatabase(executor: NativeDatabase.memory());
      store = MemoryReminderScheduleStore();
      maintenance = DriftMaintenanceRepository(db);
      settings = DriftSettingsRepository(db);
      plugin = _MockFlutterLocalNotificationsPlugin();

      when(
        () => plugin.initialize(
          settings: any(named: 'settings'),
          onDidReceiveNotificationResponse: any(
            named: 'onDidReceiveNotificationResponse',
          ),
          onDidReceiveBackgroundNotificationResponse: any(
            named: 'onDidReceiveBackgroundNotificationResponse',
          ),
        ),
      ).thenAnswer((_) async => true);
      when(() => plugin.pendingNotificationRequests())
          .thenAnswer((_) async => <PendingNotificationRequest>[]);
      when(() => plugin.getNotificationAppLaunchDetails())
          .thenAnswer((_) async => null);
      when(() => plugin.cancel(id: any(named: 'id'))).thenAnswer((_) async {});
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'disabled reminders drop snooze intent absent from the platform',
      () async {
        await settings.setNotificationPreferences(
          const NotificationPreferences(enabled: false),
        );
        await store.stageSnooze(
          ReminderScheduleEntry(
            identity: 'snooze:removed',
            notificationId: 15001,
            planRevision: '1',
            scheduledAt: DateTime.now().add(const Duration(days: 1)),
            timezone: 'UTC',
            localComponents: 'future',
            scheduleMode: 'inexactAllowWhileIdle',
            contentVersion: 'old',
          ),
        );
        final scheduler = OwntendNotificationScheduler(
          maintenance,
          plugin: plugin,
          scheduleStore: store,
          settingsRepository: settings,
        );
        await scheduler.refreshSchedules();
        expect(await store.readAll(), isEmpty);
      },
    );

    for (final directCancellation in [false, true]) {
      test(
        '${directCancellation ? 'direct cancellation' : 'refresh'} retains a failed alarm cancellation for retry',
        () async {
          await settings.setNotificationPreferences(
            const NotificationPreferences(enabled: false),
          );
          final stale = ReminderScheduleEntry(
            identity: 'task:deleted-plan',
            notificationId: 10001,
            planRevision: '1',
            scheduledAt: DateTime.now().add(const Duration(days: 1)),
            timezone: 'UTC',
            localComponents: 'future',
            scheduleMode: 'inexactAllowWhileIdle',
            contentVersion: 'old',
          );
          await store.replaceAll([stale]);
          final pending = <int>{stale.notificationId};
          when(() => plugin.pendingNotificationRequests()).thenAnswer(
            (_) async => [
              for (final id in pending)
                PendingNotificationRequest(id, 'old', 'old', null),
            ],
          );
          var failCancellation = true;
          when(() => plugin.cancel(id: any(named: 'id')))
              .thenAnswer((invocation) async {
                if (failCancellation) {
                  throw PlatformException(code: 'cancel_failed');
                }
                pending.remove(invocation.namedArguments[#id] as int);
              });
          final scheduler = OwntendNotificationScheduler(
            maintenance,
            plugin: plugin,
            scheduleStore: store,
            settingsRepository: settings,
          );
          await expectLater(
            directCancellation
                ? scheduler.cancelPlanReminders('deleted-plan')
                : scheduler.refreshSchedules(),
            throwsA(isA<PlatformException>()),
          );
          expect((await store.readAll()).map((entry) => entry.identity), [
            stale.identity,
          ]);
          expect(pending, contains(stale.notificationId));

          failCancellation = false;
          await scheduler.refreshSchedules();
          expect(pending, isEmpty);
          expect(await store.readAll(), isEmpty);
        },
      );
    }

    test('overdue plans cannot starve an eligible future reminder', () async {
      await settings.setNotificationPreferences(
        const NotificationPreferences(
          inAppInbox: false,
          weatherAlerts: false,
          dailyDigest: false,
        ),
      );
      await db
          .into(db.areas)
          .insert(AreasCompanion.insert(id: 'a', name: 'Home', kind: 'indoor'));
      await db
          .into(db.rooms)
          .insert(RoomsCompanion.insert(id: 'r', areaId: 'a', name: 'Room'));
      await db
          .into(db.assets)
          .insert(AssetsCompanion.insert(id: 'i', name: 'Item', roomId: 'r'));
      final now = DateTime.now();
      for (var index = 0; index < 129; index++) {
        await maintenance.savePlan(
          assetId: 'i',
          title: 'Overdue $index',
          recurrence: const RecurrenceRule(
            interval: 1,
            unit: RecurrenceUnit.months,
          ),
          priority: PriorityLevel.medium,
          nextDueDate: now.subtract(const Duration(days: 7)),
        );
      }
      await maintenance.savePlan(
        assetId: 'i',
        title: 'Future task',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: now.add(const Duration(days: 3)),
      );
      final scheduledTitles = <String?>[];
      when(
        () => plugin.zonedSchedule(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          scheduledDate: any(named: 'scheduledDate'),
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: any(named: 'androidScheduleMode'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer(
        (invocation) async =>
            scheduledTitles.add(invocation.namedArguments[#title] as String?),
      );
      final scheduler = OwntendNotificationScheduler(
        maintenance,
        plugin: plugin,
        scheduleStore: store,
        settingsRepository: settings,
      );
      await scheduler.refreshSchedules();
      expect(scheduledTitles, hasLength(1));
      expect(await store.readAll(), hasLength(1));
    });

    test('partial zonedSchedule failures do not discard successfully scheduled alarms', () async {
      await settings.setNotificationPreferences(
        const NotificationPreferences(
          inAppInbox: false,
          weatherAlerts: false,
          dailyDigest: false,
        ),
      );

      // Seed two maintenance tasks with reminders
      final now = DateTime.now().toUtc();
      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(id: 'area-1', name: 'Home', kind: 'indoor'),
          );
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              id: 'room-1',
              areaId: 'area-1',
              name: 'Kitchen',
            ),
          );
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: 'asset-1',
              name: 'Fridge',
              roomId: 'room-1',
            ),
          );
      await maintenance.savePlan(
        assetId: 'asset-1',
        title: 'Task 1',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: now.add(const Duration(days: 2)),
      );
      await maintenance.savePlan(
        assetId: 'asset-1',
        title: 'Task 2',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: now.add(const Duration(days: 3)),
      );

      // Make the plugin fail on the second call:
      var scheduleCount = 0;
      when(
        () => plugin.zonedSchedule(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          scheduledDate: any(named: 'scheduledDate'),
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: any(named: 'androidScheduleMode'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async {
        scheduleCount++;
        if (scheduleCount > 1) {
          throw PlatformException(
            code: 'exact_alarms_not_permitted',
            message: 'Exact alarms denied by OS',
          );
        }
      });

      final scheduler = OwntendNotificationScheduler(
        maintenance,
        plugin: plugin,
        scheduleStore: store,
        settingsRepository: settings,
      );

      // Run reconciliation: it throws the error, but successfully scheduled items are persisted in store:
      await expectLater(
        scheduler.refreshSchedules(),
        throwsA(isA<PlatformException>()),
      );

      // Assert that the first successfully scheduled reminder was persisted in store:
      final scheduledInStore = await store.readAll();
      expect(scheduledInStore, isNotEmpty);
      expect(scheduleCount, greaterThanOrEqualTo(2));
    });
  });
}
