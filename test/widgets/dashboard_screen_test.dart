import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/domain/task_selectors.dart';
import 'package:owntend/src/core/services/feedback_messenger.dart';
import 'package:owntend/src/core/sync/sync_contracts.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/domain/contracts.dart';
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

  group('Dashboard visual ergonomics & UI fixes', () {
    test('Light theme tertiary and tertiaryContainer have high contrast', () {
      final theme = testLightTheme();
      final tertiary = theme.colorScheme.tertiary;
      final container = theme.colorScheme.tertiaryContainer;

      // Ensure tertiary and tertiaryContainer are not identical (fixes invisible icon bug)
      expect(tertiary, isNot(equals(container)));

      final l1 = tertiary.computeLuminance();
      final l2 = container.computeLuminance();
      final ratio =
          (l1 > l2 ? l1 + 0.05 : l2 + 0.05) / (l1 > l2 ? l2 + 0.05 : l1 + 0.05);
      expect(ratio, greaterThanOrEqualTo(2.5));
    });

    testWidgets(
      'Weather theme toggle button displays dark_mode icon in light theme and moon tooltip',
      (tester) async {
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          permissionEducationSeenValue: true,
        );
        addTearDown(settings.close);
        final now = DateTime(2026, 6, 15, 14, 0); // daytime (2:00 PM)
        final weather = makeWeather(updatedAt: now);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(settings, weather: weather),
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

        // In light theme, the toggle button must show dark_mode icon (to switch to dark)
        expect(find.byIcon(Symbols.dark_mode_rounded), findsOneWidget);
        expect(find.byIcon(Symbols.wb_sunny_rounded), findsNothing);
      },
    );

    testWidgets(
      'Search placeholder on mobile uses concise searchShort and does not truncate',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.physicalSize = const Size(320, 840);
        tester.view.devicePixelRatio = 1;

        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          permissionEducationSeenValue: true,
        );
        addTearDown(settings.close);
        final now = DateTime(2026, 6, 15, 10, 0);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(settings),
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

        // Mobile search bar should show 'Search…' rather than 'Search rooms, items…' which truncates
        expect(find.text('Search…'), findsOneWidget);
      },
    );

    testWidgets(
      'Tomorrow tasks See All navigates with filter=tomorrow query param',
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
        final tomorrow = DateUtils.dateOnly(now).add(const Duration(days: 1));

        final tomorrowTask = makeTaskItem(
          tomorrow,
          id: 'task_tomorrow',
          title: 'Feed the fish',
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
              ...testOverrides(settings, tasks: [tomorrowTask]),
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

        final seeAllButton = find.widgetWithText(TextButton, 'See all');
        expect(seeAllButton, findsOneWidget);
        await tester.tap(seeAllButton);
        await tester.pumpAndSettle();

        expect(pushedPath, '/maintenance?filter=tomorrow');
      },
    );

    testWidgets(
      'Readiness summary card overdue metric displays schedule icon when overdue is 0',
      (tester) async {
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          permissionEducationSeenValue: true,
        );
        addTearDown(settings.close);
        final now = DateTime(2026, 6, 15, 10, 0);
        final today = DateUtils.dateOnly(now);
        final assets = makeThings(now);
        final rooms = makeRooms(now);

        final todayTask = makeTaskItem(
          today,
          id: 'today_task',
          title: 'Check furnace',
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

        // When overdue is 0, warning icon should NOT be used for overdue metric
        expect(find.byIcon(Symbols.schedule_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'Offline weather card displays cloud_off icon when location is set',
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

        await tester.pumpWidget(
          ProviderScope(
            overrides: [...testOverrides(settings, weather: null)],
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

        expect(find.byIcon(Symbols.cloud_off_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'Stale data warning card has errorContainer surface and compact retry button',
      (tester) async {
        final settings = FakeSettingsRepository(onboardingCompletedValue: true);
        final today = DateUtils.dateOnly(DateTime.now());
        final task = makeTaskItem(today);
        final assets = makeThings(DateTime(2026));
        final rooms = makeRooms(DateTime(2026));
        final snapshot = ValueNotifier<InitialHomeSnapshot?>(
          InitialHomeSnapshot(
            session: signedInTestSession,
            profile: const AppProfile(nickname: 'Pilot'),
            tasks: [task],
            assets: assets,
            rooms: rooms,
            backupState: const BackupState(),
            unreadNotifications: 0,
            syncStatus: const SyncStatus(phase: SyncPhase.ready),
            loadedAt: today,
          ),
        );
        addTearDown(settings.close);
        addTearDown(snapshot.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(
                settings,
                tasks: [task],
                assets: assets,
                rooms: rooms,
                taskStream: Stream<List<TaskItem>>.error(
                  StateError('refresh unavailable'),
                ),
              ),
              initialHomeSnapshotProvider.overrideWithValue(snapshot),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: testLightTheme(),
              home: const DashboardScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final warningFinder = find.byKey(
          const ValueKey('dashboard-stale-data-warning'),
        );
        expect(warningFinder, findsOneWidget);

        final surfaceCard = tester.widget<hk_ui.SurfaceCard>(warningFinder);
        expect(surfaceCard.backgroundColor, isNotNull);

        final retryBtn = tester.widget<TextButton>(
          find.descendant(
            of: warningFinder,
            matching: find.widgetWithText(TextButton, 'Retry'),
          ),
        );
        expect(retryBtn.style?.visualDensity, VisualDensity.compact);
      },
    );

    testWidgets(
      'Home FAB label is protected by FittedBox to prevent truncation',
      (tester) async {
        final settings = FakeSettingsRepository(onboardingCompletedValue: true);
        addTearDown(settings.close);
        final task = makeTaskItem(DateUtils.dateOnly(DateTime.now()));

        await tester.pumpWidget(
          ProviderScope(
            overrides: testOverrides(settings, tasks: [task]),
            child: const OwntendApp(),
          ),
        );
        await tester.pumpAndSettle();

        final fab = find.byType(FloatingActionButton);
        expect(fab, findsOneWidget);

        expect(
          find.descendant(of: fab, matching: find.byType(FittedBox)),
          findsOneWidget,
        );
      },
    );
  });
}
