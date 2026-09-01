import 'dart:io';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/services/notification_service.dart';
import 'package:owntend/src/core/services/reminder_schedule_reconciler.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/timezone.dart' as tz;

class _MockNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    registerFallbackValue(tz.TZDateTime.now(tz.UTC));
    registerFallbackValue(const NotificationDetails());
    registerFallbackValue(AndroidScheduleMode.inexactAllowWhileIdle);
  });
  test('notification completion acknowledges only confirmed success', () {
    final source = File(
      'lib/src/features/notifications/presentation/notifications_screen.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    final methodStart = source.indexOf(
      'Future<void> _completeFromNotification(',
    );
    final methodEnd = source.indexOf(
      '\n  Future<void> _openNotification(',
      methodStart,
    );

    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));

    final method = source.substring(methodStart, methodEnd);
    final completionCall = method.indexOf(
      'final completed = await completeTaskWithFeedback(',
    );
    final failureGuard = method.indexOf('if (!completed) {');
    final failureReturn = method.indexOf('return;', failureGuard);
    final markRead = method.indexOf('.markRead(item.id);');

    expect(completionCall, greaterThanOrEqualTo(0));
    expect(failureGuard, greaterThan(completionCall));
    expect(failureReturn, greaterThan(failureGuard));
    expect(markRead, greaterThan(failureReturn));
    expect(RegExp(r'\.markRead\(item\.id\);').allMatches(method).length, 1);
  });

  test('serialized reconciliation repairs missing future alarms', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final assets = DriftAssetRepository(db);
    final maintenance = DriftMaintenanceRepository(db);
    final settings = DriftSettingsRepository(db);
    final areaId = await assets.saveArea(
      name: 'Reminder area',
      kind: AreaKind.indoor,
    );
    final roomId = await assets.saveRoom(areaId: areaId, name: 'Reminder room');
    final assetId = await assets.saveAsset(
      name: 'Reminder asset',
      roomId: roomId,
    );
    final planId = await maintenance.savePlan(
      assetId: assetId,
      title: 'Reminder task',
      recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days),
      priority: PriorityLevel.medium,
      nextDueDate: DateTime.now().add(const Duration(days: 1)),
    );
    await settings.setNotificationPreferences(
      const NotificationPreferences(
        inAppInbox: false,
        weatherAlerts: false,
        dailyDigest: false,
      ),
    );
    await db.delete(db.notificationReconciliationRequests).go();

    final plugin = _MockNotificationsPlugin();
    final pending = <int, PendingNotificationRequest>{};
    var scheduleCalls = 0;
    Completer<void>? cancelEntered;
    Completer<void>? cancelRelease;
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
        .thenAnswer((_) async => pending.values.toList(growable: false));
    when(() => plugin.getNotificationAppLaunchDetails())
        .thenAnswer((_) async => null);
    when(
      () => plugin.zonedSchedule(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        scheduledDate: any(named: 'scheduledDate'),
        notificationDetails: any(named: 'notificationDetails'),
        androidScheduleMode: any(named: 'androidScheduleMode'),
        payload: any(named: 'payload'),
        matchDateTimeComponents: any(named: 'matchDateTimeComponents'),
      ),
    ).thenAnswer((invocation) async {
      scheduleCalls += 1;
      final id = invocation.namedArguments[#id]! as int;
      pending[id] = PendingNotificationRequest(
        id,
        invocation.namedArguments[#title] as String?,
        invocation.namedArguments[#body] as String?,
        invocation.namedArguments[#payload] as String?,
      );
    });
    when(
      () => plugin.cancel(
        id: any(named: 'id'),
        tag: any(named: 'tag'),
      ),
    ).thenAnswer((invocation) async {
      final entered = cancelEntered;
      final release = cancelRelease;
      if (entered != null && !entered.isCompleted) {
        entered.complete();
        await release!.future;
        cancelEntered = null;
        cancelRelease = null;
      }
      pending.remove(invocation.namedArguments[#id] as int);
    });
    final snapshots = MemoryReminderScheduleStore();
    final scheduler = OwntendNotificationScheduler(
      maintenance,
      plugin: plugin,
      scheduleStore: snapshots,
      settingsRepository: settings,
    );

    await scheduler.refreshSchedules();
    expect(pending, hasLength(1));
    expect(await snapshots.readAll(), hasLength(1));

    // A future snapshot is not treated as proof when the platform alarm is
    // missing; the next durable reconciliation recreates it.
    pending.clear();
    final schedulesBeforeRepair = scheduleCalls;
    await scheduler.refreshSchedules();
    expect(scheduleCalls, schedulesBeforeRepair + 1);
    expect(pending, hasLength(1));

    // Cancellation and refresh share one owner. Even when cancellation is
    // paused, refresh runs after it and publishes the final scheduled state.
    cancelEntered = Completer<void>();
    cancelRelease = Completer<void>();
    final cancel = scheduler.cancelPlanReminders(planId);
    await cancelEntered!.future;
    final refresh = scheduler.refreshSchedules();
    cancelRelease!.complete();
    await Future.wait([cancel, refresh]);

    expect(pending, hasLength(1));
    final finalSnapshots = await snapshots.readAll();
    expect(finalSnapshots, hasLength(1));
    expect(finalSnapshots.single.identity, 'task:$planId');
    expect(pending.containsKey(finalSnapshots.single.notificationId), isTrue);
  });

  test(
    'failed snooze survives restart as durable reconciliation work',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final assets = DriftAssetRepository(db);
      final maintenance = DriftMaintenanceRepository(db);
      final settings = DriftSettingsRepository(db);
      final areaId = await assets.saveArea(
        name: 'Snooze area',
        kind: AreaKind.indoor,
      );
      final roomId = await assets.saveRoom(areaId: areaId, name: 'Snooze room');
      final assetId = await assets.saveAsset(
        name: 'Snooze asset',
        roomId: roomId,
      );
      final planId = await maintenance.savePlan(
        assetId: assetId,
        title: 'Snooze task',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.days,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: DateTime.now().add(const Duration(days: 1)),
      );
      await settings.setNotificationPreferences(
        const NotificationPreferences(
          inAppInbox: false,
          weatherAlerts: false,
          dailyDigest: false,
        ),
      );
      await db.delete(db.notificationReconciliationRequests).go();

      final plugin = _MockNotificationsPlugin();
      final pending = <int, PendingNotificationRequest>{};
      var failSchedule = true;
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
          .thenAnswer((_) async => pending.values.toList(growable: false));
      when(() => plugin.getNotificationAppLaunchDetails())
          .thenAnswer((_) async => null);
      when(
        () => plugin.cancel(
          id: any(named: 'id'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer((invocation) async {
        pending.remove(invocation.namedArguments[#id] as int);
      });
      when(
        () => plugin.zonedSchedule(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          scheduledDate: any(named: 'scheduledDate'),
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: any(named: 'androidScheduleMode'),
          payload: any(named: 'payload'),
          matchDateTimeComponents: any(named: 'matchDateTimeComponents'),
        ),
      ).thenAnswer((invocation) async {
        if (failSchedule) throw StateError('injected schedule failure');
        final id = invocation.namedArguments[#id]! as int;
        pending[id] = PendingNotificationRequest(
          id,
          invocation.namedArguments[#title] as String?,
          invocation.namedArguments[#body] as String?,
          invocation.namedArguments[#payload] as String?,
        );
      });

      final store = DriftReminderScheduleStore(db);
      final firstScheduler = OwntendNotificationScheduler(
        maintenance,
        plugin: plugin,
        scheduleStore: store,
        settingsRepository: settings,
      );
      await expectLater(
        firstScheduler.snoozePlan(planId, const Duration(hours: 1)),
        throwsA(isA<StateError>()),
      );

      final staged = await store.readAll();
      expect(staged.single.identity, 'snooze:$planId');
      expect(
        await db.select(db.notificationReconciliationRequests).get(),
        hasLength(1),
      );

      failSchedule = false;
      final restartedScheduler = OwntendNotificationScheduler(
        maintenance,
        plugin: plugin,
        scheduleStore: store,
        settingsRepository: settings,
      );
      final consumer = NotificationReconciliationConsumer(
        database: db,
        scheduler: restartedScheduler,
        accountGuard: (_) async => true,
      );
      expect(
        await consumer.drainForAccount('user-a'),
        NotificationReconciliationDrainResult.refreshed,
      );

      final repaired = await store.readAll();
      expect(repaired.single.identity, 'snooze:$planId');
      expect(pending.containsKey(repaired.single.notificationId), isTrue);
      expect(
        await db.select(db.notificationReconciliationRequests).get(),
        isEmpty,
      );
    },
  );
}
