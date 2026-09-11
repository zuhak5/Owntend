import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/domain/task_selectors.dart';
import 'package:owntend/src/core/providers/app_providers.dart';
import 'package:owntend/src/core/services/feedback_messenger.dart';
import 'package:owntend/src/core/sync/sync_contracts.dart';
import 'package:owntend/src/core/sync/sync_providers.dart';
import 'package:owntend/src/features/dashboard/presentation/dashboard_presentation.dart';
import 'package:owntend/src/ui/components.dart' as hk_ui;
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
    FeedbackCoordinator.instance.resetForTesting();
    try {
      hkRootScaffoldMessengerKey.currentState?.clearSnackBars();
    } catch (_) {}
  });

  group('Home task sections & overdue display', () {
    testWidgets(
      'Home renders overdue tasks section above today and upcoming tasks',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.physicalSize = const Size(500, 1400);
        tester.view.devicePixelRatio = 1;

        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          permissionEducationSeenValue: true,
        );
        settings.homeLocationValue = const HomeLocation(
          label: 'Baghdad',
          latitude: 33.3152,
          longitude: 44.3661,
          source: 'manual',
        );
        addTearDown(settings.close);
        final now = DateTime(2026, 6, 15, 10, 0);
        final today = DateUtils.dateOnly(now);
        final yesterday = today.subtract(const Duration(days: 1));
        final tomorrow = today.add(const Duration(days: 1));

        final overdueTask = makeTaskItem(
          yesterday,
          id: 'task_overdue',
          title: 'Clean gutters',
          status: TaskStatus.overdue,
        );
        final todayTask = makeTaskItem(
          today,
          id: 'task_today',
          title: 'Water plants',
          status: TaskStatus.dueToday,
        );
        final tomorrowTask = makeTaskItem(
          tomorrow,
          id: 'task_tomorrow',
          title: 'Change air filter',
          status: TaskStatus.upcoming,
        );

        String? pushedPath;
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const DashboardScreen(),
            ),
            GoRoute(
              path: '/maintenance',
              builder: (context, state) {
                pushedPath = state.uri.toString();
                return const Scaffold(body: Text('Maintenance Screen'));
              },
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(
                settings,
                tasks: [overdueTask, todayTask, tomorrowTask],
              ),
              localNowProvider.overrideWithValue(() => now),
            ],
            child: MaterialApp.router(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: testLightTheme().copyWith(
                platform: TargetPlatform.android,
              ),
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Check that Overdue, Today's tasks, and Tomorrow's tasks headers exist
        expect(find.text('Overdue'), findsWidgets);
        expect(find.text("Today's tasks"), findsOneWidget);
        expect(find.text("Tomorrow's tasks"), findsOneWidget);

        // Check that task titles are visible
        expect(find.text('Clean gutters'), findsOneWidget);
        expect(find.text('Water plants'), findsOneWidget);
        expect(find.text('Change air filter'), findsOneWidget);

        // Tapping the first "See all" (associated with Overdue section) should route to /maintenance?filter=overdue
        final seeAllButtons = find.text('See all');
        expect(seeAllButtons, findsNWidgets(3));
        await tester.tap(seeAllButtons.first);
        await tester.pumpAndSettle();

        expect(pushedPath, '/maintenance?filter=overdue');
      },
    );

    testWidgets(
      'Home empty state displays no maintenance plans yet when tasks list is empty',
      (tester) async {
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          permissionEducationSeenValue: true,
        );
        addTearDown(settings.close);
        final now = DateTime(2026, 6, 15, 10, 0);
        final assets = makeThings(now);
        final rooms = makeRooms(now);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(
                settings,
                tasks: [],
                assets: assets,
                rooms: rooms,
              ),
              localNowProvider.overrideWithValue(() => now),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: testLightTheme().copyWith(
                platform: TargetPlatform.android,
              ),
              home: const DashboardScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('No maintenance plans yet'), findsOneWidget);
        expect(find.text('Overdue'), findsNothing);
        expect(find.text("Today's tasks"), findsNothing);
        expect(find.byType(hk_ui.OwntendFloatingActionButton), findsNothing);
      },
    );

    testWidgets(
      'Home empty state displays plan is up to date when tasks exist but none are due today or overdue',
      (tester) async {
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          permissionEducationSeenValue: true,
        );
        addTearDown(settings.close);
        final now = DateTime(2026, 6, 15, 10, 0);
        final assets = makeThings(now);
        final rooms = makeRooms(now);

        final completedTask = makeTaskItem(
          DateUtils.dateOnly(now),
          id: 'completed_task',
          title: 'Deep clean refrigerator',
          status: TaskStatus.completed,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(
                settings,
                tasks: [completedTask],
                assets: assets,
                rooms: rooms,
              ),
              localNowProvider.overrideWithValue(() => now),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: testLightTheme().copyWith(
                platform: TargetPlatform.android,
              ),
              home: const DashboardScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Your maintenance plan is up to date.'),
          findsOneWidget,
        );
        expect(
          find.text('Your maintenance plan is clear for today.'),
          findsOneWidget,
        );
        expect(find.text('No maintenance plans yet'), findsNothing);
        expect(find.byType(hk_ui.OwntendFloatingActionButton), findsNothing);
      },
    );

    testWidgets(
      'Home displays tasks and floating action button when tasks are due today',
      (tester) async {
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          permissionEducationSeenValue: true,
        );
        addTearDown(settings.close);
        final now = DateTime(2026, 6, 15, 10, 0);
        final assets = makeThings(now);
        final rooms = makeRooms(now);

        final todayTask = makeTaskItem(
          DateUtils.dateOnly(now),
          id: 'today_task',
          title: 'Inspect smoke detector',
          status: TaskStatus.dueToday,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(
                settings,
                tasks: [todayTask],
                assets: assets,
                rooms: rooms,
              ),
              localNowProvider.overrideWithValue(() => now),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: testLightTheme().copyWith(
                platform: TargetPlatform.android,
              ),
              home: const DashboardScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text("Today's tasks"), findsOneWidget);
        expect(find.byType(hk_ui.OwntendFloatingActionButton), findsOneWidget);
      },
    );

    testWidgets(
      'Home limits overdue tasks to 5 items and displays task count subtitle',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.physicalSize = const Size(500, 1600);
        tester.view.devicePixelRatio = 1;

        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          permissionEducationSeenValue: true,
        );
        settings.homeLocationValue = const HomeLocation(
          label: 'Baghdad',
          latitude: 33.3152,
          longitude: 44.3661,
          source: 'manual',
        );
        addTearDown(settings.close);
        final now = DateTime(2026, 6, 15, 10, 0);
        final today = DateUtils.dateOnly(now);
        final yesterday = today.subtract(const Duration(days: 1));

        final overdueTasks = List.generate(
          6,
          (i) => makeTaskItem(
            yesterday,
            id: 'overdue_$i',
            title: 'Overdue item $i',
            status: TaskStatus.overdue,
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(settings, tasks: overdueTasks),
              localNowProvider.overrideWithValue(() => now),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: testLightTheme().copyWith(
                platform: TargetPlatform.android,
              ),
              home: const DashboardScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Overdue'), findsWidgets);
        expect(find.text('6 tasks'), findsOneWidget);
        expect(find.text('Overdue item 0'), findsOneWidget);
        expect(find.text('Overdue item 4'), findsOneWidget);
        expect(find.text('Overdue item 5'), findsNothing);
      },
    );
  });

  group('Temporal status normalization', () {
    test(
      'getTaskBuckets normalizes stale task status across midnight rollover',
      () {
        final now = DateTime(2026, 6, 15, 8, 0);
        final yesterday = DateTime(2026, 6, 14, 12, 0);

        // Stale task item in database had status: dueToday or upcoming from yesterday
        final rawStaleTask = makeTaskItem(
          yesterday,
          id: 'stale_task',
          title: 'Inspect smoke detector',
          status: TaskStatus.dueToday,
        );

        final buckets = getTaskBuckets([rawStaleTask], now);

        expect(buckets.overdue.length, 1);
        expect(buckets.overdue.first.status, TaskStatus.overdue);
        expect(buckets.today.isEmpty, isTrue);
      },
    );
  });

  group('Coordinated pull-to-refresh', () {
    testWidgets(
      'pull-to-refresh refreshes streaks, weather, and sync in parallel',
      (tester) async {
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          permissionEducationSeenValue: true,
        );
        settings.homeLocationValue = const HomeLocation(
          label: 'Baghdad',
          latitude: 33.3152,
          longitude: 44.3661,
          source: 'manual',
        );
        final weatherRepo = CountingWeatherRepository();
        final streakService = FakeStreakService();
        final cloudSyncRepo = FakeCloudSyncRepository(
          const SyncStatus(phase: SyncPhase.ready, enabled: true),
        );
        addTearDown(settings.close);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(settings, weatherRepository: weatherRepo),
              streakServiceProvider.overrideWithValue(streakService),
              cloudSyncRepositoryProvider.overrideWithValue(cloudSyncRepo),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: testLightTheme().copyWith(
                platform: TargetPlatform.android,
              ),
              home: const DashboardScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(streakService.refreshCount, 0);
        expect(weatherRepo.refreshCount, 0);
        expect(cloudSyncRepo.syncNowCount, 0);

        // Perform pull-to-refresh gesture
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        expect(streakService.refreshCount, 1);
        expect(weatherRepo.refreshCount, 1);
        expect(cloudSyncRepo.syncNowCount, 1);
      },
    );
  });

  group('Weather card freshness formatting', () {
    testWidgets(
      'stale weather card displays full date and time when updated on previous day',
      (tester) async {
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          permissionEducationSeenValue: true,
        );
        settings.homeLocationValue = const HomeLocation(
          label: 'Baghdad',
          latitude: 33.3152,
          longitude: 44.3661,
          source: 'manual',
        );
        addTearDown(settings.close);
        final now = DateTime(2026, 6, 15, 10, 0);
        final yesterday = DateTime(2026, 6, 14, 14, 30);

        final staleWeather = makeWeather(updatedAt: yesterday);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(settings, weather: staleWeather),
              localNowProvider.overrideWithValue(() => now),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: testLightTheme().copyWith(
                platform: TargetPlatform.android,
              ),
              home: const DashboardScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Stale weather contains month and day 'Jun 14' rather than just time
        expect(find.textContaining('Jun 14'), findsOneWidget);
      },
    );
  });
}
