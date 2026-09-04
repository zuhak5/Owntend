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
