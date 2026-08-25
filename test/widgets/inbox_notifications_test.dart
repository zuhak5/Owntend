import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/services/app_permission_coordinator.dart';
import 'package:owntend/src/core/services/feedback_messenger.dart';
import 'package:owntend/src/ui/feedback/feedback_coordinator.dart';

import '../support/widget_test_fakes.dart';
import '../test_theme.dart';

void main() {
  setUp(() {
    addTearDown(FeedbackCoordinator.instance.resetForTesting);
    addTearDown(() {
      try {
        hkRootScaffoldMessengerKey.currentState?.clearSnackBars();
      } catch (_) {}
    });
    addTearDown(
      TestWidgetsFlutterBinding
          .instance
          .platformDispatcher
          .clearAccessibilityFeaturesTestValue,
    );
    FeedbackCoordinator.instance.resetForTesting();
    try {
      hkRootScaffoldMessengerKey.currentState?.clearSnackBars();
    } catch (_) {}
    TestWidgetsFlutterBinding
            .instance
            .platformDispatcher
            .accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
  });

  group('notification bootstrap', () {
    testWidgets('notification bootstrap initializes without prompting', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: false);
      final scheduler = FakeNotificationScheduler();
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationAutoStartProvider.overrideWithValue(true),
            backupAutoStartProvider.overrideWithValue(false),
            settingsRepositoryProvider.overrideWithValue(settings),
            notificationSchedulerProvider.overrideWithValue(scheduler),
          ],
          child: const NotificationBootstrap(child: SizedBox()),
        ),
      );
      await tester.pump();

      expect(scheduler.permissionRequestCount, 0);
      expect(scheduler.refreshCount, 1);
    });
  });

  group('notification cards', () {
    testWidgets('notification card renders task actions and unread state', (
      tester,
    ) async {
      var completed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: testLightTheme(),
          home: Scaffold(
            body: NotificationCard(
              notification: InboxNotification(
                id: 'inbox_task',
                title: 'Feed the fish is due today',
                body: 'Fish: Feed the fish',
                kind: 'task',
                route: '/maintenance/plan_feed',
                planId: 'plan_feed',
                createdAt: DateTime(2026, 6, 18, 9),
              ),
              onTap: () {},
              onAction: (_) {},
              onComplete: () => completed = true,
            ),
          ),
        ),
      );

      expect(find.text('Feed the fish is due today'), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);
      expect(find.text('Snooze'), findsNothing);
      final completeAction = find.byKey(
        const ValueKey('inbox-complete-action'),
      );
      expect(tester.getSize(completeAction).height, 48);
      expect(tester.getSize(completeAction).width, greaterThanOrEqualTo(176));

      await tester.tap(find.text('Complete'));

      expect(completed, isTrue);
      await tester.tap(find.byTooltip('Notification actions'));
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Mark read'), findsOneWidget);
      expect(find.text('Snooze'), findsNothing);
    });

    testWidgets('completed notification card shows timestamp without actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: testLightTheme(),
          home: Scaffold(
            body: NotificationCard(
              notification: InboxNotification(
                id: 'inbox_task',
                title: 'Feed the fish is due today',
                body: 'Fish: Feed the fish',
                kind: 'task',
                route: '/maintenance/plan_feed',
                planId: 'plan_feed',
                createdAt: DateTime(2026, 6, 18, 9),
                readAt: DateTime(2026, 6, 18, 9, 30),
              ),
              completedAt: DateTime(2026, 6, 18, 9, 30),
              onTap: () {},
              onAction: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Completed 9:30 AM'), findsOneWidget);
      expect(find.text('Complete'), findsNothing);
      expect(find.text('Snooze'), findsNothing);
    });
  });

  group('inbox state reconciliation', () {
    testWidgets('Inbox marks already completed task notification', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final completedTask = makeTaskItem(
        DateTime(2026, 6, 19),
        id: 'plan_feed',
        title: 'Feed the fish',
        status: TaskStatus.upcoming,
      );
      final notifications = [
        InboxNotification(
          id: 'task_due',
          title: 'Feed the fish is due today',
          body: 'Fish: Feed the fish',
          kind: 'task',
          route: '/maintenance/plan_feed',
          planId: 'plan_feed',
          createdAt: DateTime(2026, 6, 18, 9),
          readAt: DateTime(2026, 6, 18, 9, 30),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(
            settings,
            tasks: [completedTask],
            notifications: notifications,
            taskRecords: {
              'plan_feed': [
                MaintenanceRecord(
                  id: 'record_feed',
                  planId: 'plan_feed',
                  dueDate: DateTime(2026, 6, 18, 9),
                  completedAt: DateTime(2026, 6, 18, 9, 30),
                ),
              ],
            },
          ),
          child: MaterialApp(
            theme: testLightTheme(),
            home: const NotificationsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Completed 9:30 AM'), findsOneWidget);
      expect(find.text('Complete'), findsNothing);
      expect(find.text('Snooze'), findsNothing);
    });

    testWidgets('Inbox keeps read due task active without completion record', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final dueTask = makeTaskItem(
        DateTime(2026, 6, 18, 12),
        id: 'plan_water',
        title: 'Water Dieffenbachia',
        preserveDueTime: true,
      );
      final notifications = [
        InboxNotification(
          id: 'task_due',
          title: 'Water Dieffenbachia is due today',
          body: 'Water today',
          kind: 'task',
          route: '/maintenance/plan_water',
          planId: 'plan_water',
          createdAt: DateTime(2026, 6, 18, 0, 4),
          readAt: DateTime(2026, 6, 18, 2, 14),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(
            settings,
            tasks: [dueTask],
            notifications: notifications,
          ),
          child: MaterialApp(
            theme: testLightTheme(),
            home: const NotificationsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Completed 2:14 AM'), findsNothing);
      expect(find.text('Complete'), findsOneWidget);
      expect(find.text('Snooze'), findsNothing);
    });
  });

  group('inbox filters', () {
    testWidgets('inbox filters fit on one line without horizontal scrolling', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;

      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final notifications = [
        InboxNotification(
          id: 'task_due',
          title: 'Water plant is due today',
          body: 'Living Room: Water plant',
          kind: 'task',
          route: '/maintenance/plan_water',
          planId: 'plan_water',
          createdAt: DateTime(2026, 6, 18, 9),
        ),
        InboxNotification(
          id: 'system_tip',
          title: 'System update ready',
          body: 'Review maintenance reminders.',
          kind: 'system',
          createdAt: DateTime(2026, 6, 18, 10),
          readAt: DateTime(2026, 6, 18, 11),
        ),
        InboxNotification(
          id: 'system_backup',
          title: 'Backup completed',
          body: 'Your backup is ready.',
          kind: 'system',
          createdAt: DateTime(2026, 6, 17, 12),
          readAt: DateTime(2026, 6, 17, 13),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(
            settings,
            notifications: notifications,
            unreadNotifications: 1,
          ),
          child: MaterialApp(
            theme: testLightTheme(),
            home: const NotificationsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in ['All', 'Unread', 'Tasks', 'System']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        find.ancestor(
          of: find.text('Unread'),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
    });
  });

  group('notification preferences permissions', () {
    testWidgets(
      'unrelated notification preferences never request Android permission',
      (tester) async {
        final settings = FakeSettingsRepository(onboardingCompletedValue: true);
        final permissions = FakeAppPermissionGateway(
          states: {
            AppPermissionKind.location: AppPermissionState.denied,
            AppPermissionKind.notifications: AppPermissionState.denied,
          },
        );
        addTearDown(settings.close);

        await tester.pumpWidget(
          ProviderScope(
            overrides: testOverrides(settings, permissionGateway: permissions),
            child: MaterialApp(
              theme: testLightTheme(),
              home: const SettingsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final inbox = find.widgetWithText(SwitchListTile, 'In-app inbox');
        await tester.scrollUntilVisible(
          inbox,
          320,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(inbox);
        await tester.pump();

        expect(permissions.requests, isEmpty);
        expect(settings.notificationPreferencesValue.inAppInbox, isFalse);
      },
    );

    testWidgets('denied notification enable is not persisted as active', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      settings.notificationPreferencesValue = const NotificationPreferences(
        localReminders: false,
      );
      final permissions = FakeAppPermissionGateway(
        states: {
          AppPermissionKind.location: AppPermissionState.denied,
          AppPermissionKind.notifications: AppPermissionState.denied,
        },
        requestResults: {
          AppPermissionKind.notifications: AppPermissionState.denied,
        },
      );
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings, permissionGateway: permissions),
          child: MaterialApp(
            theme: testLightTheme(),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final reminders = find.widgetWithText(SwitchListTile, 'Device reminders');
      await tester.scrollUntilVisible(
        reminders,
        320,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(reminders);
      await tester.pumpAndSettle();

      expect(permissions.requests, [AppPermissionKind.notifications]);
      expect(settings.notificationPreferencesValue.localReminders, isFalse);
    });

    testWidgets('Quiet Hours start picker saves notification preferences', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      settings.notificationPreferencesValue = const NotificationPreferences(
        quietHoursEnabled: true,
        quietHoursStartMinutes: 22 * 60,
        quietHoursEndMinutes: 7 * 60,
      );
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings),
          child: MaterialApp(
            theme: testLightTheme(),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pump();

      final startTile = find.widgetWithText(ListTile, 'Quiet hours start');
      await tester.ensureVisible(startTile);
      await tester.pumpAndSettle();
      await tester.tap(startTile);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(settings.notificationSaveCount, greaterThan(0));
      expect(
        settings.notificationPreferencesValue.quietHoursStartMinutes,
        22 * 60,
      );
    });
  });
}
