import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/sync_contracts.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';
import 'package:owntend/src/core/services/feedback_messenger.dart';
import 'package:owntend/src/ui/feedback/feedback_coordinator.dart';
import 'package:owntend/src/ui/components.dart' as hk_ui;
import 'package:go_router/go_router.dart';

import '../support/widget_test_fakes.dart';

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

  group('initial hydration', () {
    testWidgets('initial hydration blocks Home until restoration completes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(769, 1536);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final restoreEnable = Completer<void>();
      addTearDown(() {
        if (!restoreEnable.isCompleted) restoreEnable.complete();
      });
      final hydrationStatus = SyncStatus(
        phase: SyncPhase.initializing,
        enabled: true,
        initialHydrationProgress: testHydrationProgress(
          InitialHydrationStage.restoringCloudData,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(settings),
            cloudSyncRepositoryProvider.overrideWithValue(
              FakeCloudSyncRepository(
                hydrationStatus,
                enableFuture: restoreEnable.future,
              ),
            ),
            syncStatusProvider.overrideWithValue(AsyncData(hydrationStatus)),
          ],
          child: const OwntendApp(),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('initial-cloud-hydration')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Securely bringing back your tasks,\nroutines, and reminders.',
        ),
        findsOneWidget,
      );
      expect(find.byType(HomeShell), findsNothing);
      expect(find.byType(hk_ui.SereneBottomNavigationBar), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('initial-cloud-hydration')),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );

      final hydrationContext = tester.element(
        find.byKey(const ValueKey('initial-cloud-hydration')),
      );
      await tester
          .runAsync(() async {
            await precacheImage(
              const AssetImage(
                'assets/illustrations/owntend-restore-hero-target.png',
              ),
              hydrationContext,
            );
          })
          .timeout(const Duration(seconds: 10));

      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('42%'), findsOneWidget);
      expect(find.text('Restoring cloud data'), findsWidgets);
      expect(find.text('Finalizing Owntend'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('hydration-spark-target')),
        findsNothing,
      );
      expect(
        find.textContaining('restore in dependency order'),
        findsOneWidget,
      );
      expectContainedHero(tester, const ValueKey('restore-hero-illustration'));
      expectHeroBehind(
        tester,
        const ValueKey('restore-hero-illustration'),
        find.text(
          'Securely bringing back your tasks,\nroutines, and reminders.',
        ),
      );
      await expectLater(
        find.byKey(const ValueKey('initial-cloud-hydration')),
        matchesGoldenFile('../goldens/premium_hydration_light.png'),
      );
      restoreEnable.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('failed new-user restore does not offer offline continuation', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      final failedEnable = Completer<void>();
      addTearDown(settings.close);
      addTearDown(() {
        if (!failedEnable.isCompleted) failedEnable.complete();
      });
      final status = SyncStatus(
        phase: SyncPhase.offline,
        enabled: true,
        initialHydrationProgress: testHydrationProgress(
          InitialHydrationStage.restoringCloudData,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(settings),
            cloudSyncRepositoryProvider.overrideWithValue(
              FakeCloudSyncRepository(
                status,
                enableFuture: failedEnable.future,
              ),
            ),
            syncStatusProvider.overrideWithValue(AsyncData(status)),
          ],
          child: const OwntendApp(),
        ),
      );
      await tester.pump();
      failedEnable.completeError(StateError('offline'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.byKey(const ValueKey('initial-cloud-hydration')),
        findsOneWidget,
      );
      expect(find.byType(HomeShell), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Check connection'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Continue offline'), findsNothing);
      expect(find.textContaining('tasks stay available'), findsNothing);
      expect(
        find.textContaining('restore in dependency order'),
        findsOneWidget,
      );
      expect(find.text('Restoring cloud data needs attention'), findsOneWidget);
    });

    testWidgets('finalization failure names the finalizing step', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(
        onboardingCompletedValue: true,
        profileFailure: StateError('local profile read failed'),
      );
      final sync = FakeCloudSyncRepository(
        const SyncStatus(phase: SyncPhase.ready, enabled: true),
      );
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(settings),
            cloudSyncRepositoryProvider.overrideWithValue(sync),
          ],
          child: const OwntendApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Finalizing Owntend needs attention'), findsOneWidget);
      expect(find.text('Cloud data is still waiting'), findsNothing);
      expect(
        find.text(
          'Owntend could not complete Finalizing Owntend. Retry to continue.',
        ),
        findsOneWidget,
      );
      expect(find.text('Continue offline'), findsNothing);
      expect(find.textContaining('tasks stay available'), findsNothing);
    });
  });

  group('registration restore lifecycle', () {
    testWidgets('registration starts one restoration operation', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      final authChanges = StreamController<AuthStateChange>.broadcast();
      final restoreEnable = Completer<void>();
      final sync = FakeCloudSyncRepository(
        const SyncStatus(phase: SyncPhase.ready, enabled: true),
        enableFuture: restoreEnable.future,
      );
      addTearDown(settings.close);
      addTearDown(authChanges.close);
      addTearDown(() {
        if (!restoreEnable.isCompleted) restoreEnable.complete();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(settings, includeAuthOverrides: false),
            authStateProvider.overrideWith((ref) => authChanges.stream),
            cloudSyncRepositoryProvider.overrideWithValue(sync),
          ],
          child: const OwntendApp(),
        ),
      );

      authChanges.add(
        const AuthStateChange(
          event: AuthEventType.initialSession,
          session: null,
        ),
      );
      await tester.pump();
      authChanges.add(
        const AuthStateChange(
          event: AuthEventType.signedIn,
          session: AuthSession(userId: 'signed-in-user'),
        ),
      );
      await tester.pump();
      authChanges.add(
        const AuthStateChange(
          event: AuthEventType.signedIn,
          session: AuthSession(userId: 'signed-in-user'),
        ),
      );
      authChanges.add(
        const AuthStateChange(
          event: AuthEventType.tokenRefreshed,
          session: AuthSession(userId: 'signed-in-user'),
        ),
      );
      await tester.pump();

      expect(sync.enableCount, 1);
      expect(
        find.byKey(const ValueKey('initial-cloud-hydration')),
        findsOneWidget,
      );

      restoreEnable.complete();
      await tester.pumpAndSettle();

      expect(sync.enableCount, 1);
      expect(find.byType(HomeShell), findsOneWidget);
    });

    testWidgets('restore progress is monotonic across rebuild updates', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      final statusUpdates = StreamController<SyncStatus>.broadcast();
      final restoreEnable = Completer<void>();
      final sync = FakeCloudSyncRepository(
        const SyncStatus(phase: SyncPhase.initializing, enabled: true),
        enableFuture: restoreEnable.future,
      );
      addTearDown(settings.close);
      addTearDown(statusUpdates.close);
      addTearDown(() {
        if (!restoreEnable.isCompleted) restoreEnable.complete();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(settings),
            cloudSyncRepositoryProvider.overrideWithValue(sync),
            syncStatusProvider.overrideWith((ref) => statusUpdates.stream),
          ],
          child: const OwntendApp(),
        ),
      );
      await tester.pump();

      expect(sync.enableCount, 1);
      statusUpdates.add(
        SyncStatus(
          phase: SyncPhase.initializing,
          enabled: true,
          initialHydrationProgress: testHydrationProgress(
            InitialHydrationStage.syncingLocalChanges,
            completedUnits: 80,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('80%'), findsOneWidget);

      statusUpdates.add(
        SyncStatus(
          phase: SyncPhase.initializing,
          enabled: true,
          initialHydrationProgress: testHydrationProgress(
            InitialHydrationStage.restoringCloudData,
            completedUnits: 15,
          ),
        ),
      );
      await tester.pump();
      expect(sync.enableCount, 1);
      expect(find.text('80%'), findsOneWidget);
      expect(find.text('15%'), findsNothing);

      statusUpdates.add(
        SyncStatus(
          phase: SyncPhase.ready,
          enabled: true,
          initialHydrationProgress: testHydrationProgress(
            InitialHydrationStage.finalizing,
            state: RestoreRunState.completed,
            completedUnits: 1,
            totalUnits: 1,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('100%'), findsOneWidget);

      statusUpdates.add(
        SyncStatus(
          phase: SyncPhase.initializing,
          enabled: true,
          initialHydrationProgress: testHydrationProgress(
            InitialHydrationStage.connecting,
            completedUnits: 0,
          ),
        ),
      );
      await tester.pump();
      expect(sync.enableCount, 1);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('0%'), findsNothing);

      restoreEnable.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('successful registration restore navigates Home exactly once', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true)
        ..homeLocationValue = const HomeLocation(
          label: 'Baghdad',
          latitude: 33.3152,
          longitude: 44.3661,
        );
      final backgroundWeather = HangingWeatherRepository();
      final authChanges = StreamController<AuthStateChange>.broadcast();
      final restoreEnable = Completer<void>();
      final restoreServiceStop = Completer<void>();
      final sync = FakeCloudSyncRepository(
        const SyncStatus(phase: SyncPhase.ready, enabled: true),
        enableFuture: restoreEnable.future,
      );
      var homeNavigationCount = 0;
      var lastPath = '/account';
      final router = GoRouter(
        initialLocation: '/account',
        routes: [
          ShellRoute(
            builder: (context, state, child) => HomeShell(child: child),
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const Text('Signed-in home'),
              ),
              GoRoute(
                path: '/account',
                builder: (context, state) => const Text('Account route'),
              ),
            ],
          ),
        ],
      );
      void routeListener() {
        final path = router.routeInformationProvider.value.uri.path;
        if (path == '/' && lastPath != '/') homeNavigationCount++;
        lastPath = path;
      }

      router.routeInformationProvider.addListener(routeListener);
      addTearDown(settings.close);
      addTearDown(authChanges.close);
      addTearDown(() {
        router.routeInformationProvider.removeListener(routeListener);
        router.dispose();
        if (!restoreEnable.isCompleted) restoreEnable.complete();
        if (!restoreServiceStop.isCompleted) restoreServiceStop.complete();
        if (!backgroundWeather.releaseRefresh.isCompleted) {
          backgroundWeather.releaseRefresh.complete();
        }
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(
              settings,
              includeAuthOverrides: false,
              weatherRepository: backgroundWeather,
            ),
            authStateProvider.overrideWith((ref) => authChanges.stream),
            cloudSyncRepositoryProvider.overrideWithValue(sync),
            startupRestoreServiceStopperProvider.overrideWithValue(
              () => restoreServiceStop.future,
            ),
            routerProvider.overrideWithValue(router),
          ],
          child: const OwntendApp(),
        ),
      );
      authChanges.add(
        const AuthStateChange(
          event: AuthEventType.initialSession,
          session: null,
        ),
      );
      await tester.pump();
      authChanges.add(
        const AuthStateChange(
          event: AuthEventType.signedIn,
          session: AuthSession(userId: 'signed-in-user'),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('initial-cloud-hydration')),
        findsOneWidget,
      );

      restoreEnable.complete();
      await tester.pumpAndSettle();

      expect(find.text('Signed-in home'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(homeNavigationCount, 1);
      expect(restoreServiceStop.isCompleted, isFalse);
      expect(backgroundWeather.refreshCount, 1);
      expect(backgroundWeather.releaseRefresh.isCompleted, isFalse);

      authChanges.add(
        const AuthStateChange(
          event: AuthEventType.signedIn,
          session: AuthSession(userId: 'signed-in-user'),
        ),
      );
      await tester.pumpAndSettle();

      expect(homeNavigationCount, 1);
      expect(sync.enableCount, 1);
      restoreServiceStop.complete();
      await tester.pump();
    });
  });

  group('restore recovery actions', () {
    testWidgets('restore timeout shows recovery actions instead of hanging', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      final restoreEnable = Completer<void>();
      final sync = FakeCloudSyncRepository(
        const SyncStatus(phase: SyncPhase.initializing, enabled: true),
        enableFuture: restoreEnable.future,
      );
      addTearDown(settings.close);
      addTearDown(() {
        if (!restoreEnable.isCompleted) restoreEnable.complete();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(settings),
            startupRestoreTimeoutProvider.overrideWithValue(
              const Duration(milliseconds: 10),
            ),
            cloudSyncRepositoryProvider.overrideWithValue(sync),
          ],
          child: const OwntendApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 3500));
      await tester.pump();

      expect(sync.enableCount, 1);
      expect(
        find.byKey(const ValueKey('initial-cloud-hydration')),
        findsOneWidget,
      );
      expect(find.byType(HomeShell), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Check connection'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Continue offline'), findsNothing);
    });

    testWidgets('duplicate auth event after failure waits for Retry', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      final authChanges = StreamController<AuthStateChange>.broadcast();
      final restoreEnable = Completer<void>();
      final sync = FakeCloudSyncRepository(
        const SyncStatus(phase: SyncPhase.offline, enabled: true),
        enableFuture: restoreEnable.future,
      );
      addTearDown(settings.close);
      addTearDown(authChanges.close);
      addTearDown(() {
        if (!restoreEnable.isCompleted) restoreEnable.complete();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(settings, includeAuthOverrides: false),
            authStateProvider.overrideWith((ref) => authChanges.stream),
            cloudSyncRepositoryProvider.overrideWithValue(sync),
          ],
          child: const OwntendApp(),
        ),
      );
      authChanges.add(
        const AuthStateChange(
          event: AuthEventType.signedIn,
          session: AuthSession(userId: 'signed-in-user'),
        ),
      );
      await tester.pump();
      restoreEnable.completeError(StateError('offline'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(sync.enableCount, 1);
      expect(find.text('Retry'), findsOneWidget);

      authChanges.add(
        const AuthStateChange(
          event: AuthEventType.signedIn,
          session: AuthSession(userId: 'signed-in-user'),
        ),
      );
      authChanges.add(
        const AuthStateChange(
          event: AuthEventType.tokenRefreshed,
          session: AuthSession(userId: 'signed-in-user'),
        ),
      );
      await tester.pump();

      expect(sync.enableCount, 1);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets(
      'retry creates one clean restore attempt and ignores stale work',
      (tester) async {
        final settings = FakeSettingsRepository(onboardingCompletedValue: true);
        final firstEnable = Completer<void>();
        final secondEnable = Completer<void>();
        final sync = FakeCloudSyncRepository(
          const SyncStatus(phase: SyncPhase.ready, enabled: true),
          enableFuture: firstEnable.future,
        );
        addTearDown(settings.close);
        addTearDown(() {
          if (!firstEnable.isCompleted) firstEnable.complete();
          if (!secondEnable.isCompleted) secondEnable.complete();
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(settings),
              startupRestoreTimeoutProvider.overrideWithValue(
                const Duration(milliseconds: 10),
              ),
              cloudSyncRepositoryProvider.overrideWithValue(sync),
            ],
            child: const OwntendApp(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 3500));
        await tester.pump();

        expect(sync.enableCount, 1);
        expect(find.text('Retry'), findsOneWidget);

        sync.enableFuture = secondEnable.future;
        await tester.tap(find.byKey(const ValueKey('restore-retry-button')));
        await tester.pump();

        expect(sync.enableCount, 2);
        firstEnable.complete();
        await tester.pump();
        expect(find.byType(HomeShell), findsNothing);

        secondEnable.complete();
        await tester.pumpAndSettle();

        expect(sync.enableCount, 2);
        expect(find.byType(HomeShell), findsOneWidget);
      },
    );
  });

  group('verified cache recovery', () {
    testWidgets(
      'valid verified cache opens populated Home without restoration',
      (tester) async {
        final settings = FakeSettingsRepository(onboardingCompletedValue: true);
        final db = AppDatabase(executor: NativeDatabase.memory());
        final store = LocalSyncStore(db);
        final task = makeTaskItem(DateUtils.dateOnly(DateTime.now()));
        final sync = FakeCloudSyncRepository(
          const SyncStatus(phase: SyncPhase.ready, enabled: true),
        );
        addTearDown(settings.close);
        addTearDown(db.close);
        await store.setEnabled(
          enabled: true,
          boundUserId: signedInTestSession.userId,
          migrationState: 'active',
        );
        await store.recordSyncSuccess(DateTime.utc(2026, 7, 26, 8));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(settings, tasks: [task]),
              localSyncStoreProvider.overrideWithValue(store),
              cloudSyncRepositoryProvider.overrideWithValue(sync),
            ],
            child: const OwntendApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(HomeShell), findsOneWidget);
        expect(find.text('Feed the fish'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('initial-cloud-hydration')),
          findsNothing,
        );
        expect(sync.enableCount, 0);
      },
    );

    testWidgets('verified Home snapshot enables offline recovery and tip', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      final db = AppDatabase(executor: NativeDatabase.memory());
      final store = LocalSyncStore(db);
      final task = makeTaskItem(DateUtils.dateOnly(DateTime.now()));
      final sync = FakeCloudSyncRepository(
        const SyncStatus(phase: SyncPhase.ready, enabled: true),
      );
      addTearDown(settings.close);
      addTearDown(db.close);
      await store.setEnabled(
        enabled: true,
        boundUserId: signedInTestSession.userId,
        migrationState: 'active',
      );
      await store.recordSyncSuccess(DateTime.utc(2026, 7, 26, 8));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(settings, tasks: [task]),
            localSyncStoreProvider.overrideWithValue(store),
            cloudSyncRepositoryProvider.overrideWithValue(sync),
          ],
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(OwntendApp)),
      );
      final failedEnable = Completer<void>();
      sync.enableFuture = failedEnable.future;
      final retry = container
          .read(startupBootstrapControllerProvider)
          .retryStartupRestore();
      await tester.pump();
      failedEnable.completeError(StateError('offline'));
      await retry;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 3500));
      await tester.pump();

      expect(find.text('Continue offline'), findsOneWidget);
      expect(find.textContaining('tasks stay available'), findsOneWidget);
      expect(find.textContaining('restore in dependency order'), findsNothing);

      await tester.tap(find.text('Continue offline'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.text('Feed the fish'), findsOneWidget);
    });
  });

  group('restore visual validation', () {
    testWidgets('visual validation golden renders restore during applying', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(640, 1280);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final restoreEnable = Completer<void>();
      final hydrationStatus = SyncStatus(
        phase: SyncPhase.syncing,
        enabled: true,
        initialHydrationProgress: testHydrationProgress(
          InitialHydrationStage.restoringCloudData,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(settings),
            cloudSyncRepositoryProvider.overrideWithValue(
              blockingCloudSyncRepository(
                hydrationStatus,
                enable: restoreEnable,
              ),
            ),
            syncStatusProvider.overrideWithValue(AsyncData(hydrationStatus)),
          ],
          child: const OwntendApp(),
        ),
      );
      await tester.pump();
      final context = tester.element(
        find.byKey(const ValueKey('initial-cloud-hydration')),
      );
      await tester
          .runAsync(() async {
            await precacheImage(
              const AssetImage(
                'assets/illustrations/owntend-restore-hero-target.png',
              ),
              context,
            );
          })
          .timeout(const Duration(seconds: 10));
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('42%'), findsOneWidget);
      expect(find.text('Restoring cloud data'), findsWidgets);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expectContainedHero(tester, const ValueKey('restore-hero-illustration'));
      expectHeroBehind(
        tester,
        const ValueKey('restore-hero-illustration'),
        find.text(
          'Securely bringing back your tasks,\nroutines, and reminders.',
        ),
      );
      await expectLater(
        find.byKey(const ValueKey('initial-cloud-hydration')),
        matchesGoldenFile('../goldens/visual_restore_applying_640.png'),
      ).timeout(const Duration(seconds: 10));
      restoreEnable.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('restore remains centered on a wide viewport', (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final restoreEnable = Completer<void>();
      final hydrationStatus = SyncStatus(
        phase: SyncPhase.syncing,
        enabled: true,
        initialHydrationProgress: testHydrationProgress(
          InitialHydrationStage.checkingLatestUpdates,
          completedUnits: 78,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(settings),
            cloudSyncRepositoryProvider.overrideWithValue(
              blockingCloudSyncRepository(
                hydrationStatus,
                enable: restoreEnable,
              ),
            ),
            syncStatusProvider.overrideWithValue(AsyncData(hydrationStatus)),
          ],
          child: const OwntendApp(),
        ),
      );
      await tester.pump();
      final hydration = find.byKey(const ValueKey('initial-cloud-hydration'));
      final hydrationContext = tester.element(hydration);
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage(
            'assets/illustrations/owntend-restore-hero-target.png',
          ),
          hydrationContext,
        );
      });
      await tester.pump(const Duration(milliseconds: 700));

      expect(
        tester
            .getSize(find.byKey(const ValueKey('restore-reference-frame')))
            .width,
        lessThanOrEqualTo(640),
      );
      expectContainedHero(tester, const ValueKey('restore-hero-illustration'));
      expect(tester.takeException(), isNull);
      await expectLater(
        hydration,
        matchesGoldenFile('../goldens/visual_restore_wide.png'),
      );
      restoreEnable.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('restore full-bleed background fits phone width endpoints', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final viewport in const [Size(320, 700), Size(430, 932)]) {
        tester.view.physicalSize = viewport;
        final settings = FakeSettingsRepository(onboardingCompletedValue: true);
        addTearDown(settings.close);
        final restoreEnable = Completer<void>();
        final hydrationStatus = SyncStatus(
          phase: SyncPhase.syncing,
          enabled: true,
          initialHydrationProgress: testHydrationProgress(
            InitialHydrationStage.restoringCloudData,
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(settings),
              cloudSyncRepositoryProvider.overrideWithValue(
                blockingCloudSyncRepository(
                  hydrationStatus,
                  enable: restoreEnable,
                ),
              ),
              syncStatusProvider.overrideWithValue(AsyncData(hydrationStatus)),
            ],
            child: const OwntendApp(),
          ),
        );
        await tester.pump();
        final hydration = find.byKey(const ValueKey('initial-cloud-hydration'));
        final hydrationContext = tester.element(hydration);
        await tester.runAsync(() async {
          await precacheImage(
            const AssetImage(
              'assets/illustrations/owntend-restore-hero-target.png',
            ),
            hydrationContext,
          );
        });
        await tester.pump(const Duration(milliseconds: 700));

        expectContainedHero(
          tester,
          const ValueKey('restore-hero-illustration'),
        );
        expect(
          tester
              .getBottomRight(find.byKey(const ValueKey('restore-tip-card')))
              .dy,
          lessThanOrEqualTo(viewport.height),
        );
        expect(tester.takeException(), isNull);

        restoreEnable.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });

    testWidgets('short scaled restore keeps all recovery content visible', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final restoreEnable = Completer<void>();
      final hydrationStatus = SyncStatus(
        phase: SyncPhase.syncing,
        enabled: true,
        initialHydrationProgress: testHydrationProgress(
          InitialHydrationStage.restoringCloudData,
          completedUnits: 24,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(settings),
            cloudSyncRepositoryProvider.overrideWithValue(
              blockingCloudSyncRepository(
                hydrationStatus,
                enable: restoreEnable,
              ),
            ),
            syncStatusProvider.overrideWithValue(AsyncData(hydrationStatus)),
          ],
          child: const OwntendApp(),
        ),
      );
      await tester.pump();
      final hydration = find.byKey(const ValueKey('initial-cloud-hydration'));
      final hydrationContext = tester.element(hydration);
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage(
            'assets/illustrations/owntend-restore-hero-target.png',
          ),
          hydrationContext,
        );
      });
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.byKey(const ValueKey('restore-scroll-view')), findsNothing);
      for (final copy in [
        'Connecting securely',
        'Restoring cloud data',
        'Restoring photos',
        'Syncing local changes',
        'Checking latest updates',
        'Finalizing Owntend',
      ]) {
        final finder = find.text(copy);
        expect(finder, findsWidgets);
        for (final element in finder.evaluate()) {
          final text = element.widget as Text;
          expect(text.overflow, isNot(TextOverflow.ellipsis));
          final instance = find.byWidget(text);
          expect(tester.getTopLeft(instance).dy, greaterThanOrEqualTo(0));
          expect(tester.getBottomRight(instance).dy, lessThanOrEqualTo(640));
        }
      }
      final frame = find.byKey(const ValueKey('restore-reference-frame'));
      expect(tester.getTopLeft(frame).dy, greaterThanOrEqualTo(0));
      expect(tester.getBottomRight(frame).dy, lessThanOrEqualTo(640));
      expect(
        tester
            .getBottomRight(find.byKey(const ValueKey('restore-tip-card')))
            .dy,
        lessThanOrEqualTo(640),
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        hydration,
        matchesGoldenFile('../goldens/visual_restore_short_scaled.png'),
      );
      restoreEnable.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('compact restore failure layouts', () {
    testWidgets(
      'compact verified-cache failure exposes every recovery action',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final settings = FakeSettingsRepository(onboardingCompletedValue: true);
        final db = AppDatabase(executor: NativeDatabase.memory());
        final store = LocalSyncStore(db);
        final sync = FakeCloudSyncRepository(
          const SyncStatus(phase: SyncPhase.ready, enabled: true),
        );
        addTearDown(settings.close);
        addTearDown(db.close);
        await store.setEnabled(
          enabled: true,
          boundUserId: signedInTestSession.userId,
          migrationState: 'active',
        );
        await store.recordSyncSuccess(DateTime.utc(2026, 7, 26, 8));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(settings),
              localSyncStoreProvider.overrideWithValue(store),
              cloudSyncRepositoryProvider.overrideWithValue(sync),
            ],
            child: const OwntendApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(OwntendApp)),
        );
        final failedEnable = Completer<void>();
        sync.enableFuture = failedEnable.future;
        final retry = container
            .read(startupBootstrapControllerProvider)
            .retryStartupRestore();
        await tester.pump();
        failedEnable.completeError(StateError('offline'));
        await retry;
        await tester.pump();
        expect(tester.takeException(), isNull);

        expect(
          find.byKey(const ValueKey('restore-scroll-view')),
          findsOneWidget,
        );
        for (final key in const [
          ValueKey('restore-retry-button'),
          ValueKey('restore-check-connection-button'),
          ValueKey('restore-continue-offline-button'),
          ValueKey('restore-sign-out-button'),
        ]) {
          final action = find.byKey(key);
          expect(action, findsOneWidget);
          await tester.ensureVisible(action);
          await tester.pump();
          final rect = tester.getRect(action);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(360));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(640));
          expect(action, findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('compact Arabic failure keeps recovery actions visible', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final settings = FakeSettingsRepository(
        onboardingCompletedValue: true,
        appLanguageValue: AppLanguage.ar,
        appLanguageExplicitValue: true,
      );
      final failedEnable = Completer<void>();
      final status = SyncStatus(
        phase: SyncPhase.offline,
        enabled: true,
        initialHydrationProgress: testHydrationProgress(
          InitialHydrationStage.finalizing,
          completedUnits: 91,
        ),
      );
      addTearDown(settings.close);
      addTearDown(() {
        if (!failedEnable.isCompleted) failedEnable.complete();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(settings),
            cloudSyncRepositoryProvider.overrideWithValue(
              FakeCloudSyncRepository(
                status,
                enableFuture: failedEnable.future,
              ),
            ),
            syncStatusProvider.overrideWithValue(AsyncData(status)),
          ],
          child: const OwntendApp(),
        ),
      );
      await tester.pump();
      failedEnable.completeError(StateError('offline'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        Directionality.of(
          tester.element(find.byKey(const ValueKey('initial-cloud-hydration'))),
        ),
        TextDirection.rtl,
      );
      for (final key in const [
        ValueKey('restore-retry-button'),
        ValueKey('restore-sign-out-button'),
      ]) {
        final action = find.byKey(key);
        expect(action, findsOneWidget);
        await tester.ensureVisible(action);
        await tester.pump();
        final rect = tester.getRect(action);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(640));
      }
      expect(
        find.text('ما زالت البيانات السحابية بانتظار الاتصال'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
