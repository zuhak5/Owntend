import 'dart:async';

import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/owntend_animated_splash_screen.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/config/app_config.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/services/app_permission_coordinator.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/sync_connectivity.dart';
import 'package:owntend/src/core/sync/sync_contracts.dart';
import 'package:owntend/src/core/sync/sync_providers.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';
import 'package:owntend/src/features/auth/presentation/auth_providers.dart';
import 'package:owntend/src/features/maintenance/application/task_creation_controller.dart';
import 'package:owntend/src/features/maintenance/data/task_creation_operation_store.dart';
import 'package:owntend/src/features/monetization/monetization.dart';
import 'package:owntend/src/features/permissions/application/permission_education_controller.dart';
import 'package:owntend/src/features/permissions/data/device_permission_gateway.dart';
import 'package:owntend/src/features/permissions/data/permission_education_repository.dart';
import 'package:owntend/src/features/permissions/domain/permission_capability.dart';
import 'package:owntend/src/features/permissions/domain/permission_education_state.dart';
import 'package:owntend/src/features/permissions/presentation/permission_education_overlay.dart';
import 'package:owntend/src/features/permissions/presentation/permission_setup_screen.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/services/feedback_messenger.dart';
import 'package:owntend/src/ui/app_theme.dart';
import 'package:owntend/src/ui/feedback/feedback_coordinator.dart';
import 'package:owntend/src/ui/components.dart' as hk_ui;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:material_symbols_icons/symbols.dart';

import 'test_theme.dart';

const _signedInTestSession = AuthSession(
  userId: 'widget-test-user',
  fullName: 'Widget Tester',
  email: 'widget@example.invalid',
  providers: {'google'},
);

InitialHydrationProgress _testHydrationProgress(
  InitialHydrationStage stage, {
  RestoreRunState state = RestoreRunState.running,
  int completedUnits = 42,
  int totalUnits = 100,
}) {
  final timestamp = DateTime.utc(2026, 7, 20, 12);
  return InitialHydrationProgress(
    runId: 'widget-restore-run',
    state: state,
    stage: stage,
    completedUnits: completedUnits,
    totalUnits: totalUnits,
    startedAt: timestamp,
    updatedAt: timestamp,
  );
}

FakeCloudSyncRepository _blockingCloudSyncRepository(
  SyncStatus status, {
  Completer<void>? enable,
}) {
  final restore = enable ?? Completer<void>();
  addTearDown(() {
    if (!restore.isCompleted) restore.complete();
  });
  return FakeCloudSyncRepository(status, enableFuture: restore.future);
}

Future<void> _pumpSwipeRows(
  WidgetTester tester, {
  required List<Widget> rows,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: testLightTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: rows),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpPermissionEducation(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

Widget _swipeTestRow(String id, {required Future<bool> Function()? onAction}) {
  return hk_ui.SwipeDelete(
    dismissKey: ValueKey('swipe-row-$id'),
    action: hk_ui.SwipeAction.moveToTrash(onAction: onAction),
    margin: const EdgeInsets.only(bottom: 8),
    child: Container(
      key: ValueKey('swipe-card-$id'),
      width: double.infinity,
      height: 64,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(hk_ui.kSwipeRowRadius),
      ),
      child: Text('Row $id'),
    ),
  );
}

Future<GoRouter> _pumpDashboardHeader(
  WidgetTester tester, {
  required FakeSettingsRepository settings,
  required ThemeData theme,
  int balance = 7,
  int unreadNotifications = 3,
}) async {
  settings.homeLocationValue ??= const HomeLocation(
    label: 'Baghdad',
    latitude: 33.3152,
    longitude: 44.3661,
    source: 'manual',
  );
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const DashboardScreen()),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Notification route target')),
        ),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const Scaffold(body: Text('Search')),
      ),
      GoRoute(
        path: '/account',
        builder: (context, state) => const Scaffold(body: Text('Account')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._testOverrides(settings, unreadNotifications: unreadNotifications),
        monetizationRepositoryProvider.overrideWithValue(null),
        pointWalletProvider.overrideWithValue(
          AsyncData(
            PointWallet(
              balance: balance,
              timeZone: 'Asia/Baghdad',
              updatedAt: DateTime.utc(2026, 8, 2),
            ),
          ),
        ),
        monetizationConfigProvider.overrideWithValue(
          const AsyncData(MonetizationConfig.failClosed()),
        ),
        pendingRewardClaimsProvider.overrideWithValue(const AsyncData([])),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: theme,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _dragSwipeRowPastThreshold(
  WidgetTester tester,
  Finder row, {
  Offset offset = const Offset(-500, 0),
  String? dialogTitle,
}) async {
  await tester.drag(row, offset);
  await _waitForSwipeBackgroundToClose(tester);
  if (dialogTitle != null) {
    expect(find.text(dialogTitle), findsNothing);
  }
  await tester.pump(const Duration(milliseconds: 800));
}

Future<void> _waitForSwipeBackgroundToClose(WidgetTester tester) async {
  for (var index = 0; index < 20; index++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('Move to Trash').evaluate().isEmpty &&
        find.text('Swipe to move to Trash').evaluate().isEmpty &&
        find.text('Release to move to Trash').evaluate().isEmpty) {
      break;
    }
  }
  expect(find.text('Swipe to move to Trash'), findsNothing);
  expect(find.text('Release to move to Trash'), findsNothing);
  expect(find.text('Move to Trash'), findsNothing);
}

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

  testWidgets('startup bootstrap shows a branded surface until theme loads', (
    tester,
  ) async {
    final startupTheme = Completer<ThemeStartupSettings>();

    await tester.pumpWidget(
      OwntendBootstrap(
        startupThemeLoader: () => startupTheme.future,
        appBuilder: (_) => const SizedBox(key: ValueKey('bootstrapped-app')),
      ),
    );

    final startupSurface = find.byKey(const ValueKey('startup-theme-loading'));
    expect(startupSurface, findsOneWidget);
    expect(find.byType(OwntendStartupSurface), findsOneWidget);
    expect(find.text('Owntend'), findsOneWidget);
    expect(find.byKey(const ValueKey('owntend-animated-splash')), findsNothing);
    expect(tester.getSize(startupSurface), const Size(800, 600));

    await tester.pump(const Duration(milliseconds: 500));
    expect(startupSurface, findsOneWidget);

    startupTheme.complete(
      const ThemeStartupSettings(
        preference: ThemePreference.light,
        timeOfDayEnabled: false,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(startupSurface, findsNothing);
    expect(find.byKey(const ValueKey('bootstrapped-app')), findsOneWidget);
  });

  testWidgets('startup bootstrap falls back instead of hanging on timeout', (
    tester,
  ) async {
    ThemeStartupSettings? resolvedTheme;

    await tester.pumpWidget(
      OwntendBootstrap(
        startupThemeLoader: () => Completer<ThemeStartupSettings>().future,
        appBuilder: (startupTheme) {
          resolvedTheme = startupTheme;
          return const SizedBox(key: ValueKey('bootstrapped-app'));
        },
      ),
    );

    final startupSurface = find.byKey(const ValueKey('startup-theme-loading'));
    expect(startupSurface, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 3999));
    expect(startupSurface, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(startupSurface, findsNothing);
    expect(find.byKey(const ValueKey('bootstrapped-app')), findsOneWidget);
    expect(resolvedTheme?.preference, ThemePreference.light);
    expect(resolvedTheme?.timeOfDayEnabled, isFalse);
  });

  testWidgets('startup bootstrap uses fallback theme when loading fails', (
    tester,
  ) async {
    ThemeStartupSettings? resolvedTheme;

    await tester.pumpWidget(
      OwntendBootstrap(
        startupThemeLoader: () => Future<ThemeStartupSettings>.error(
          StateError('settings unavailable'),
        ),
        appBuilder: (startupTheme) {
          resolvedTheme = startupTheme;
          return const SizedBox();
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(resolvedTheme?.preference, ThemePreference.light);
    expect(resolvedTheme?.timeOfDayEnabled, isFalse);
  });

  testWidgets('startup failures honor an Arabic device locale', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('ar');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    final arabic = lookupAppLocalizations(const Locale('ar'));

    await tester.pumpWidget(
      const OwntendStartupFailure(cloudUnavailable: true),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(arabic.cloudServicesAreUnavailablePleaseTryAgainLater),
      findsOneWidget,
    );
    expect(
      Directionality.of(tester.element(find.byType(Scaffold))),
      TextDirection.rtl,
    );
  });

  testWidgets('app toasts use standard durations and replace stale messages', (
    tester,
  ) async {
    late BuildContext toastContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: testLightTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              toastContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    hk_ui.showToast(toastContext, content: const Text('First message'));
    await tester.pump();
    expect(find.text('First message'), findsOneWidget);

    hk_ui.showToast(
      toastContext,
      content: const Text('Undo message'),
      action: SnackBarAction(label: 'Undo', onPressed: () {}),
    );
    await tester.pumpAndSettle();
    expect(find.text('First message'), findsNothing);
    expect(find.text('Undo message'), findsOneWidget);

    hk_ui.showToast(
      toastContext,
      content: const Text('Error message'),
      severity: hk_ui.HkToastSeverity.error,
    );
    await tester.pumpAndSettle();
    expect(find.text('Undo message'), findsNothing);
    expect(find.text('Error message'), findsOneWidget);
  });

  testWidgets('task deletion snackbar uses semantic colors in both themes', (
    tester,
  ) async {
    for (final theme in [testLightTheme(), testDarkTheme()]) {
      late BuildContext toastContext;
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                toastContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      hk_ui.showTaskMovedToTrashSnackBar(toastContext, onUndo: () {});
      await tester.pumpAndSettle();

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.behavior, SnackBarBehavior.floating);
      expect(find.text('Task moved to Trash.'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      FeedbackCoordinator.instance.resetForTesting();
    }
  });

  testWidgets('task deletion snackbars queue undo callbacks', (tester) async {
    late BuildContext toastContext;
    var firstUndoCount = 0;
    var secondUndoCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: testLightTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              toastContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    hk_ui.showTaskMovedToTrashSnackBar(
      toastContext,
      onUndo: () => firstUndoCount++,
    );
    await tester.pump();
    hk_ui.showTaskMovedToTrashSnackBar(
      toastContext,
      onUndo: () => secondUndoCount++,
    );
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    FeedbackCoordinator.instance.handleAction();
    await tester.pump();

    expect(firstUndoCount, 1);
    expect(secondUndoCount, 1);
  });

  testWidgets(
    'task deletion snackbar fits narrow large-text layout without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      late BuildContext toastContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: testLightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                toastContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      hk_ui.showTaskMovedToTrashSnackBar(toastContext, onUndo: () {});
      await tester.pump();

      final snackBar = find.byType(SnackBar);
      expect(snackBar, findsOneWidget);
      expect(tester.getTopLeft(snackBar).dx, greaterThanOrEqualTo(0));
      expect(tester.getBottomRight(snackBar).dx, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('task completion toast keeps Undo with action timing', (
    tester,
  ) async {
    final streak = FakeStreakService();
    final task = _taskItem(DateTime(2026, 6, 28));
    final maintenance = FakeMaintenanceRepository(initialTasks: [task]);
    final scheduler = FakeNotificationScheduler();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          maintenanceRepositoryProvider.overrideWithValue(maintenance),
          streakServiceProvider.overrideWithValue(streak),
          notificationSchedulerProvider.overrideWithValue(scheduler),
        ],
        child: MaterialApp(
          scaffoldMessengerKey: hkRootScaffoldMessengerKey,
          theme: testLightTheme(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) => ElevatedButton(
                onPressed: () => completeTaskWithFeedback(context, ref, task),
                child: const Text('Complete'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Complete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 451));
    await tester.pumpAndSettle();

    expect(find.text('Task completed.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).duration,
      const Duration(seconds: 5),
    );
    expect(scheduler.refreshCount, 0);
    expect(scheduler.cancelled, isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(maintenance.undoCount, 1);
    expect(scheduler.refreshCount, 1);
    expect(find.text('Completion undone.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('task completion toast disappears after action duration', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    late BuildContext toastContext;
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: hkRootScaffoldMessengerKey,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: testLightTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              toastContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    FeedbackCoordinator.instance.resetForTesting();
    hkRootScaffoldMessengerKey.currentState?.clearSnackBars();

    final controller = hk_ui.showToast(
      toastContext,
      content: const Text('Task completed.'),
      action: SnackBarAction(label: 'Undo', onPressed: () {}),
    );
    await tester.pumpAndSettle();
    expect(find.text('Task completed.'), findsOneWidget);

    controller?.close();
    await tester.pumpAndSettle();
    await tester.pump();
    expect(find.text('Task completed.'), findsNothing);
  });

  testWidgets(
    'app root starts at onboarding without owning a duplicate splash',
    (tester) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: false);
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _testOverrides(settings, session: null),
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Continue with Google'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('owntend-animated-splash')),
        findsNothing,
      );
      expect(find.byType(hk_ui.SereneBottomNavigationBar), findsNothing);
    },
  );

  testWidgets(
    'startup bootstrap sanitizes orphaned assets without failing startup',
    (tester) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final orphan = Asset(
        id: 'orphan-asset-1',
        name: 'Orphaned Asset',
        assetType: AssetType.general,
        categoryId: 'category_general',
        roomId: 'missing-room-id',
        createdAt: DateTime.utc(2026, 8, 14),
        updatedAt: DateTime.utc(2026, 8, 14),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _testOverrides(
            settings,
            assets: [orphan],
            rooms: const [],
          ),
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DashboardScreen), findsOneWidget);
    },
  );

  testWidgets('shell navigation remains visible with route query parameters', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final router = GoRouter(
      initialLocation: '/?code=oauth-callback',
      routes: [
        ShellRoute(
          builder: (context, state, child) => HomeShell(child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const Text('Canonical home'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(settings),
          routerProvider.overrideWithValue(router),
        ],
        child: const OwntendApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Canonical home'), findsOneWidget);
    expect(find.byType(hk_ui.SereneBottomNavigationBar), findsOneWidget);
    final shellScaffold = tester.widget<Scaffold>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Scaffold &&
            widget.body is! Stack &&
            widget.bottomNavigationBar is hk_ui.SereneBottomNavigationBar,
      ),
    );
    expect(shellScaffold.extendBody, isTrue);
  });

  testWidgets('routine sync status changes do not rebuild the Home shell', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    final router = GoRouter(
      routes: [
        ShellRoute(
          builder: (context, state, child) => HomeShell(child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const SizedBox.expand(),
            ),
          ],
        ),
      ],
    );
    addTearDown(settings.close);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(settings),
          routerProvider.overrideWithValue(router),
        ],
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();
    final initialNavigation = tester.widget<hk_ui.SereneBottomNavigationBar>(
      find.byType(hk_ui.SereneBottomNavigationBar),
    );

    await tester.pump();
    await tester.pump();

    final currentNavigation = tester.widget<hk_ui.SereneBottomNavigationBar>(
      find.byType(hk_ui.SereneBottomNavigationBar),
    );
    expect(identical(currentNavigation, initialNavigation), isTrue);
  });

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
      initialHydrationProgress: _testHydrationProgress(
        InitialHydrationStage.restoringCloudData,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(settings),
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
      find.text('Securely bringing back your tasks,\nroutines, and reminders.'),
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
    expect(find.byKey(const ValueKey('hydration-spark-target')), findsNothing);
    expect(find.textContaining('restore in dependency order'), findsOneWidget);
    _expectContainedHero(tester, const ValueKey('restore-hero-illustration'));
    _expectHeroBehind(
      tester,
      const ValueKey('restore-hero-illustration'),
      find.text('Securely bringing back your tasks,\nroutines, and reminders.'),
    );
    await expectLater(
      find.byKey(const ValueKey('initial-cloud-hydration')),
      matchesGoldenFile('goldens/premium_hydration_light.png'),
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
      initialHydrationProgress: _testHydrationProgress(
        InitialHydrationStage.restoringCloudData,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(settings),
          cloudSyncRepositoryProvider.overrideWithValue(
            FakeCloudSyncRepository(status, enableFuture: failedEnable.future),
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
    expect(find.textContaining('restore in dependency order'), findsOneWidget);
    expect(find.text('Restoring cloud data needs attention'), findsOneWidget);
  });

  testWidgets('finalization failure names the finalizing step', (tester) async {
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
          ..._testOverrides(settings),
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

  testWidgets('registration starts one restoration operation', (tester) async {
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
          ..._testOverrides(settings, includeAuthOverrides: false),
          authStateProvider.overrideWith((ref) => authChanges.stream),
          cloudSyncRepositoryProvider.overrideWithValue(sync),
        ],
        child: const OwntendApp(),
      ),
    );

    authChanges.add(
      const AuthStateChange(event: AuthEventType.initialSession, session: null),
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
          ..._testOverrides(settings),
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
        initialHydrationProgress: _testHydrationProgress(
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
        initialHydrationProgress: _testHydrationProgress(
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
        initialHydrationProgress: _testHydrationProgress(
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
        initialHydrationProgress: _testHydrationProgress(
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
          ..._testOverrides(
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
      const AuthStateChange(event: AuthEventType.initialSession, session: null),
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
          ..._testOverrides(settings),
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
          ..._testOverrides(settings, includeAuthOverrides: false),
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
            ..._testOverrides(settings),
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

  testWidgets('valid verified cache opens populated Home without restoration', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    final db = AppDatabase(executor: NativeDatabase.memory());
    final store = LocalSyncStore(db);
    final task = _taskItem(DateUtils.dateOnly(DateTime.now()));
    final sync = FakeCloudSyncRepository(
      const SyncStatus(phase: SyncPhase.ready, enabled: true),
    );
    addTearDown(settings.close);
    addTearDown(db.close);
    await store.setEnabled(
      enabled: true,
      boundUserId: _signedInTestSession.userId,
      migrationState: 'active',
    );
    await store.recordSyncSuccess(DateTime.utc(2026, 7, 26, 8));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(settings, tasks: [task]),
          localSyncStoreProvider.overrideWithValue(store),
          cloudSyncRepositoryProvider.overrideWithValue(sync),
        ],
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('Feed the fish'), findsOneWidget);
    expect(find.byKey(const ValueKey('initial-cloud-hydration')), findsNothing);
    expect(sync.enableCount, 0);
  });

  testWidgets('verified Home snapshot enables offline recovery and tip', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    final db = AppDatabase(executor: NativeDatabase.memory());
    final store = LocalSyncStore(db);
    final task = _taskItem(DateUtils.dateOnly(DateTime.now()));
    final sync = FakeCloudSyncRepository(
      const SyncStatus(phase: SyncPhase.ready, enabled: true),
    );
    addTearDown(settings.close);
    addTearDown(db.close);
    await store.setEnabled(
      enabled: true,
      boundUserId: _signedInTestSession.userId,
      migrationState: 'active',
    );
    await store.recordSyncSuccess(DateTime.utc(2026, 7, 26, 8));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(settings, tasks: [task]),
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

  testWidgets('a genuine signed-in transition canonicalizes navigation home', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    final authChanges = StreamController<AuthStateChange>.broadcast();
    addTearDown(settings.close);
    addTearDown(authChanges.close);
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
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(settings, includeAuthOverrides: false),
          authStateProvider.overrideWith((ref) => authChanges.stream),
          routerProvider.overrideWithValue(router),
        ],
        child: const OwntendApp(),
      ),
    );
    authChanges.add(
      const AuthStateChange(event: AuthEventType.initialSession, session: null),
    );
    await tester.pump();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Account route'), findsNothing);

    authChanges.add(
      const AuthStateChange(
        event: AuthEventType.signedIn,
        session: AuthSession(userId: 'signed-in-user'),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('Signed-in home'), findsOneWidget);
    expect(find.byType(hk_ui.SereneBottomNavigationBar), findsOneWidget);
  });

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

  testWidgets('dashboard shell renders when onboarding is complete', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    settings.profileValue = const AppProfile(nickname: 'Thulfiqar');
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Search rooms, items, tasks, notes'), findsOneWidget);
    expect(find.text('Good afternoon'), findsNothing);
    expect(find.text("Let's make today productive"), findsNothing);
    expect(find.textContaining('Thulfiqar'), findsNothing);
    expect(find.textContaining('Home overview'), findsNothing);
    expect(find.text('Set up your home'), findsOneWidget);
    expect(find.text('2 of 3 complete'), findsOneWidget);
    expect(find.text('Home readiness'), findsNothing);
    expect(find.byType(hk_ui.SereneBottomNavigationBar), findsOneWidget);
  });

  testWidgets('new Home user sees real setup progress and no readiness score', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, assets: const [], rooms: const []),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set up your home'), findsOneWidget);
    expect(find.text('0 of 3 complete'), findsOneWidget);
    expect(find.textContaining('Create your first room'), findsWidgets);
    expect(find.text('Home readiness'), findsNothing);
    expect(find.text('55%'), findsNothing);
    expect(find.text('0%'), findsNothing);
    expect(find.text('Ready for today'), findsNothing);
  });

  testWidgets('eligible Home user sees the readiness card', (tester) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final task = _taskItem(DateUtils.dateOnly(DateTime.now()));

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, tasks: [task]),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set up your home'), findsNothing);
    expect(find.text('Home readiness'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Next 7'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
  });

  testWidgets('dashboard header is responsive at required widths', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final width in [390.0, 768.0, 1024.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 900);
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      settings.profileValue = const AppProfile(nickname: 'Hidden Name');
      addTearDown(settings.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: _testOverrides(settings),
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('dashboard-header-card')),
        findsOneWidget,
      );
      expect(find.text('Good afternoon'), findsNothing);
      expect(find.text("Let's make today productive"), findsNothing);
      expect(find.text('Hidden Name'), findsNothing);
      expect(find.text('Points'), findsNothing);
      // At width 390 the layout is in the standard-mobile breakpoint
      // (360 ≤ W ≤ 400), so the placeholder shortens to 'Search rooms, items…'.
      // At width 768+ it is in the large-mobile/desktop breakpoint (W > 400)
      // and shows the full string.
      final expectedPlaceholder = width == 390.0
          ? 'Search rooms, items\u2026'
          : 'Search rooms, items, tasks, notes';
      expect(find.text(expectedPlaceholder), findsOneWidget);
      for (final key in [
        'home-search-control',
        'home-points-control',
        'home-notifications-control',
      ]) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        // Spec: standard component height is 44 px; compact (<360 px) is 40 px.
        // Width 390 is standard, so all controls are at least 44 px tall.
        expect(size.height, greaterThanOrEqualTo(44));
      }
      expect(tester.takeException(), isNull, reason: 'width $width');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('permission education requests each permission after Continue', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(
      onboardingCompletedValue: true,
      permissionEducationSeenValue: false,
    );
    addTearDown(settings.close);
    final permissions = FakeAppPermissionGateway(
      states: {
        AppPermissionKind.location: AppPermissionState.denied,
        AppPermissionKind.notifications: AppPermissionState.denied,
        AppPermissionKind.exactAlarms: AppPermissionState.unavailable,
      },
      requestResults: {
        AppPermissionKind.location: AppPermissionState.granted,
        AppPermissionKind.notifications: AppPermissionState.granted,
      },
    );
    final weather = CountingWeatherRepository(
      settingsRepository: settings,
      deviceLocation: const HomeLocation(
        label: 'Baghdad',
        latitude: 33.3152,
        longitude: 44.3661,
        source: 'device',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(
          settings,
          permissionGateway: permissions,
          weatherRepository: weather,
        ),
        child: const OwntendApp(),
      ),
    );
    await _pumpPermissionEducation(tester);

    expect(find.text('Set your weather area'), findsOneWidget);
    expect(permissions.requests, isEmpty);

    final useLocationFinder = find.text('Use current location');
    await tester.ensureVisible(useLocationFinder);
    await tester.tap(useLocationFinder, warnIfMissed: false);
    await _pumpPermissionEducation(tester);
    expect(permissions.requests, [AppPermissionKind.location]);
    expect(weather.useDeviceLocationCount, 1);
    expect(find.text('Never miss important maintenance'), findsOneWidget);

    final enableNotificationsFinder = find.text('Enable notifications');
    await tester.ensureVisible(enableNotificationsFinder);
    await tester.tap(enableNotificationsFinder, warnIfMissed: false);
    await _pumpPermissionEducation(tester);
    expect(permissions.requests, [
      AppPermissionKind.location,
      AppPermissionKind.notifications,
    ]);
    expect(settings.permissionEducationSeenValue, isTrue);
    expect(
      find.byKey(const ValueKey('permission-education-overlay')),
      findsNothing,
    );
  });

  testWidgets(
    'permission education skips configured steps and supports Not now',
    (tester) async {
      final settings = FakeSettingsRepository(
        onboardingCompletedValue: true,
        permissionEducationSeenValue: false,
      );
      settings.homeLocationValue = const HomeLocation(
        label: 'Baghdad',
        latitude: 33.3152,
        longitude: 44.3661,
        source: 'manual',
      );
      addTearDown(settings.close);
      final permissions = FakeAppPermissionGateway(
        states: {
          AppPermissionKind.location: AppPermissionState.granted,
          AppPermissionKind.notifications: AppPermissionState.denied,
          AppPermissionKind.exactAlarms: AppPermissionState.unavailable,
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _testOverrides(settings, permissionGateway: permissions),
          child: const OwntendApp(),
        ),
      );
      await _pumpPermissionEducation(tester);

      expect(find.text('Set your weather area'), findsNothing);
      expect(find.text('Never miss important maintenance'), findsOneWidget);
      final notNowFinder = find.text('Not now');
      await tester.ensureVisible(notNowFinder);
      await tester.tap(notNowFinder, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(permissions.requests, isEmpty);
      expect(
        find.byKey(const ValueKey('permission-education-overlay')),
        findsNothing,
      );
    },
  );

  testWidgets('permanent permission denial routes to app settings', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(
      onboardingCompletedValue: true,
      permissionEducationSeenValue: false,
    );
    addTearDown(settings.close);
    final permissions = FakeAppPermissionGateway(
      states: {
        AppPermissionKind.location: AppPermissionState.permanentlyDenied,
        AppPermissionKind.notifications: AppPermissionState.granted,
        AppPermissionKind.exactAlarms: AppPermissionState.granted,
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, permissionGateway: permissions),
        child: const OwntendApp(),
      ),
    );
    await _pumpPermissionEducation(tester);
    final manageSettingsFinder = find.text('Manage in settings');
    await tester.ensureVisible(manageSettingsFinder);
    await tester.tap(manageSettingsFinder, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(permissions.openLocationSettingsCount, 1);
    expect(permissions.requests, isEmpty);
    expect(find.text('Set your weather area'), findsOneWidget);
  });

  testWidgets('prompted denied permission routes to settings without request', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(
      onboardingCompletedValue: true,
      permissionEducationSeenValue: false,
    );
    settings.homeLocationValue = const HomeLocation(
      label: 'Baghdad',
      latitude: 33.3152,
      longitude: 44.3661,
      source: 'manual',
    );
    addTearDown(settings.close);
    final permissions = FakeAppPermissionGateway(
      states: {
        AppPermissionKind.location: AppPermissionState.granted,
        AppPermissionKind.notifications: AppPermissionState.permanentlyDenied,
        AppPermissionKind.exactAlarms: AppPermissionState.granted,
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, permissionGateway: permissions),
        child: const OwntendApp(),
      ),
    );
    await _pumpPermissionEducation(tester);

    expect(find.text('Never miss important maintenance'), findsOneWidget);
    final manageSettingsFinder = find.text('Manage in settings');
    await tester.ensureVisible(manageSettingsFinder);
    await tester.tap(manageSettingsFinder, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(permissions.openAppSettingsCount, 1);
    expect(permissions.requests, isEmpty);
    expect(find.text('Never miss important maintenance'), findsOneWidget);
  });

  testWidgets('configured weather and granted permissions persist completion', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(
      onboardingCompletedValue: true,
      permissionEducationSeenValue: false,
    );
    settings.homeLocationValue = const HomeLocation(
      label: 'Baghdad',
      latitude: 33.3152,
      longitude: 44.3661,
      source: 'manual',
    );
    addTearDown(settings.close);
    final permissions = FakeAppPermissionGateway(
      states: {
        AppPermissionKind.location: AppPermissionState.granted,
        AppPermissionKind.notifications: AppPermissionState.granted,
        AppPermissionKind.exactAlarms: AppPermissionState.granted,
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, permissionGateway: permissions),
        child: const OwntendApp(),
      ),
    );
    await _pumpPermissionEducation(tester);

    expect(
      find.byKey(const ValueKey('permission-education-overlay')),
      findsNothing,
    );
    expect(settings.permissionEducationSeenValue, isTrue);
    expect(permissions.requests, isEmpty);
  });

  testWidgets(
    'permission education overlay sits above content while allowing tab navigation',
    (tester) async {
      final settings = FakeSettingsRepository(
        onboardingCompletedValue: true,
        permissionEducationSeenValue: false,
      );
      addTearDown(settings.close);
      final permissions = FakeAppPermissionGateway(
        states: {
          AppPermissionKind.location: AppPermissionState.denied,
          AppPermissionKind.notifications: AppPermissionState.denied,
          AppPermissionKind.exactAlarms: AppPermissionState.denied,
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _testOverrides(settings, permissionGateway: permissions),
          child: const OwntendApp(),
        ),
      );
      await _pumpPermissionEducation(tester);
      final router = GoRouter.of(tester.element(find.byType(HomeShell)));

      final overlayRect = tester.getRect(
        find.byKey(const ValueKey('permission-education-overlay')),
      );
      final cardRect = tester.getRect(
        find.byKey(const ValueKey('permission-card-deviceLocation')),
      );
      final navRect = tester.getRect(
        find.byType(hk_ui.SereneBottomNavigationBar),
      );
      expect(overlayRect.top, 0);
      expect(cardRect.bottom, lessThanOrEqualTo(navRect.top + 100));

      await tester.tap(find.text('Tools'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(router.routeInformationProvider.value.uri.path, '/more');
      expect(settings.permissionEducationSeenValue, isFalse);
    },
  );

  testWidgets('Settings can reopen unresolved permission education', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final permissions = FakeAppPermissionGateway(
      states: {
        AppPermissionKind.location: AppPermissionState.denied,
        AppPermissionKind.notifications: AppPermissionState.denied,
        AppPermissionKind.exactAlarms: AppPermissionState.denied,
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, permissionGateway: permissions),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(HomeShell)));
    router.go('/settings');
    await tester.pumpAndSettle();
    final setup = find.byKey(const ValueKey('settings-permission-education'));
    await tester.scrollUntilVisible(
      setup,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    tester.widget<ListTile>(setup).onTap!();
    await _pumpPermissionEducation(tester);

    expect(find.byType(PermissionSetupScreen), findsOneWidget);
  });

  testWidgets('permission education respects reduced motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final settings = FakeSettingsRepository(
      onboardingCompletedValue: true,
      permissionEducationSeenValue: false,
    );
    addTearDown(settings.close);
    final permissions = FakeAppPermissionGateway(
      states: {
        AppPermissionKind.location: AppPermissionState.denied,
        AppPermissionKind.notifications: AppPermissionState.denied,
        AppPermissionKind.exactAlarms: AppPermissionState.denied,
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, permissionGateway: permissions),
        child: const OwntendApp(),
      ),
    );
    await _pumpPermissionEducation(tester);
    await tester.pump();

    expect(find.text('Set your weather area'), findsOneWidget);
    expect(find.byType(PermissionEducationOverlayWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app honors saved dark theme preference', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final settings = FakeSettingsRepository(
      onboardingCompletedValue: true,
      themePreferenceValue: ThemePreference.dark,
      timeOfDayThemeEnabledValue: true,
    );
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings),
        child: const OwntendApp(),
      ),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.theme?.colorScheme.brightness, Brightness.light);
    expect(app.darkTheme?.colorScheme.brightness, Brightness.dark);
  });

  testWidgets('MaterialApp honors light dark and automatic local day-night', (
    tester,
  ) async {
    Future<ThemeMode> pumpMode(ThemePreference preference, DateTime now) async {
      final settings = FakeSettingsRepository(
        onboardingCompletedValue: true,
        themePreferenceValue: preference,
        timeOfDayThemeEnabledValue: preference == ThemePreference.system,
      );
      addTearDown(settings.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._testOverrides(settings),
            localThemeClockProvider.overrideWithValue(AsyncData(now)),
          ],
          child: const OwntendApp(),
        ),
      );
      await tester.pump();
      return tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;
    }

    expect(
      await pumpMode(ThemePreference.light, DateTime(2026, 7, 14, 22)),
      ThemeMode.light,
    );
    expect(
      await pumpMode(ThemePreference.dark, DateTime(2026, 7, 14, 10)),
      ThemeMode.dark,
    );
    expect(
      await pumpMode(ThemePreference.system, DateTime(2026, 7, 14, 10)),
      ThemeMode.light,
    );
    expect(
      await pumpMode(ThemePreference.system, DateTime(2026, 7, 14, 22)),
      ThemeMode.dark,
    );
  });

  testWidgets('shared floating action button keeps fixed dimensions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: testLightTheme(),
        home: Scaffold(
          floatingActionButton: hk_ui.OwntendFloatingActionButton(
            icon: Icons.add,
            label: 'Create',
            onPressed: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget);
    expect(
      tester.getSize(fab),
      const Size(hk_ui.kOwntendFabWidth, hk_ui.kOwntendFabHeight),
    );
  });

  testWidgets('shared floating action button tooltip stays above bottom nav', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: testLightTheme(),
        home: Scaffold(
          extendBody: true,
          bottomNavigationBar: hk_ui.SereneBottomNavigationBar(
            selectedIndex: 0,
            destinations: const [
              hk_ui.SereneBottomNavDestination(
                icon: Symbols.home_rounded,
                selectedIcon: Symbols.home_filled_rounded,
                label: hk_ui.SereneBottomNavLabel.home,
              ),
              hk_ui.SereneBottomNavDestination(
                icon: Symbols.inventory_2_rounded,
                selectedIcon: Symbols.inventory_2_rounded,
                label: hk_ui.SereneBottomNavLabel.rooms,
              ),
            ],
            onDestinationSelected: (_) {},
          ),
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(bottom: HkSpacing.bottomNav),
            child: hk_ui.OwntendFloatingActionButton(
              icon: Icons.add,
              label: 'Create',
              tooltip: 'Create tooltip',
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fab = find.byType(FloatingActionButton);
    await tester.longPress(fab);
    await tester.pump(const Duration(milliseconds: 800));

    final tooltip = find.text('Create tooltip');
    expect(tooltip, findsOneWidget);
    final tooltipRect = tester.getRect(tooltip);
    final fabRect = tester.getRect(fab);
    final navRect = tester.getRect(
      find.byType(hk_ui.SereneBottomNavigationBar),
    );

    expect(tooltipRect.bottom, lessThanOrEqualTo(fabRect.top));
    expect(tooltipRect.bottom, lessThan(navRect.top));
    expect(tooltipRect.left, greaterThanOrEqualTo(0));
    expect(tooltipRect.right, lessThanOrEqualTo(390));
  });

  testWidgets('Home Rooms and Tasks FABs share the same dimensions', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    void expectFixedFab() {
      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget);
      expect(
        tester.getSize(fab),
        const Size(hk_ui.kOwntendFabWidth, hk_ui.kOwntendFabHeight),
      );
    }

    expectFixedFab();

    tester
        .widget<hk_ui.SereneBottomNavigationBar>(
          find.byType(hk_ui.SereneBottomNavigationBar),
        )
        .onDestinationSelected(1);
    await tester.pumpAndSettle();
    expectFixedFab();

    tester
        .widget<hk_ui.SereneBottomNavigationBar>(
          find.byType(hk_ui.SereneBottomNavigationBar),
        )
        .onDestinationSelected(2);
    await tester.pumpAndSettle();
    expectFixedFab();
  });

  testWidgets('Arabic language renders static UI in RTL', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: testLightTheme(),
        locale: const Locale('ar'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          bottomNavigationBar: hk_ui.SereneBottomNavigationBar(
            selectedIndex: 0,
            destinations: const [
              hk_ui.SereneBottomNavDestination(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                label: hk_ui.SereneBottomNavLabel.home,
              ),
              hk_ui.SereneBottomNavDestination(
                icon: Icons.inventory_2_outlined,
                selectedIcon: Icons.inventory_2,
                label: hk_ui.SereneBottomNavLabel.rooms,
              ),
            ],
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('الغرف'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('الرئيسية'))),
      TextDirection.rtl,
    );
  });

  testWidgets(
    'production surfaces have stable English and Arabic visual baselines',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final task = _taskItem(
        DateTime(2026, 7, 22),
        title: 'Replace water filter',
      );
      final notification = InboxNotification(
        id: 'golden-notification',
        title: 'Replace water filter is overdue',
        body: 'Legacy platform snapshot',
        kind: 'task',
        createdAt: DateTime.utc(2026, 7, 22, 9, 30),
        messageCode: NotificationMessageCode.taskOverdue.wireValue,
        messageArgs: const {'task': 'Replace water filter'},
        planId: task.plan.id,
      );

      for (final language in AppLanguage.values) {
        final locale = Locale(language.name);
        final localeCode = language.name;
        final l10n = lookupAppLocalizations(locale);
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          appLanguageValue: language,
          appLanguageExplicitValue: true,
          themePreferenceValue: ThemePreference.light,
        );
        settings.profileValue = const AppProfile(nickname: 'Pilot');
        addTearDown(settings.close);
        final appBoundaryKey = ValueKey('production-app-golden-$localeCode');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ..._testOverrides(
                settings,
                tasks: [task],
                notifications: [notification],
              ),
            ],
            child: RepaintBoundary(
              key: appBoundaryKey,
              child: const OwntendApp(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        final readinessCard = find
            .ancestor(
              of: find.text(l10n.homeReadiness),
              matching: find.byType(hk_ui.PremiumCard),
            )
            .first;
        await expectLater(
          readinessCard,
          matchesGoldenFile('goldens/production_dashboard_$localeCode.png'),
        );

        final router = GoRouter.of(tester.element(find.byType(HomeShell)));
        router.go('/notifications');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await expectLater(
          find.byKey(appBoundaryKey),
          matchesGoldenFile('goldens/production_notifications_$localeCode.png'),
        );

        router.go('/settings');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await expectLater(
          find.byKey(appBoundaryKey),
          matchesGoldenFile('goldens/production_settings_$localeCode.png'),
        );

        final formBoundaryKey = ValueKey('production-form-golden-$localeCode');
        await tester.pumpWidget(
          ProviderScope(
            overrides: _testOverrides(settings, tasks: [task]),
            child: MaterialApp(
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              theme: testLightTheme(),
              home: RepaintBoundary(
                key: formBoundaryKey,
                child: Scaffold(body: PlanEditorDialog(task: task)),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(formBoundaryKey),
          matchesGoldenFile('goldens/production_form_$localeCode.png'),
        );

        final dialogBoundaryKey = ValueKey(
          'production-dialog-golden-$localeCode',
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: testLightTheme(),
            home: RepaintBoundary(
              key: dialogBoundaryKey,
              child: Scaffold(body: CompleteTaskDialog(task: task)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(dialogBoundaryKey),
          matchesGoldenFile('goldens/production_dialog_$localeCode.png'),
        );
      }
    },
  );

  testWidgets('device Arabic is used until an explicit language is selected', (
    tester,
  ) async {
    tester.platformDispatcher.localeTestValue = const Locale('ar');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final arabic = lookupAppLocalizations(const Locale('ar'));
    final english = lookupAppLocalizations(const Locale('en'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(arabic.home), findsOneWidget);

    await settings.setAppLocalePreference(AppLanguage.en);
    await tester.pumpAndSettle();
    expect(find.text(english.home), findsOneWidget);
    expect(settings.appLanguageExplicitValue, isTrue);
  });

  testWidgets('Settings Appearance control persists theme preference', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(
      onboardingCompletedValue: true,
      appLanguageValue: AppLanguage.ar,
      themePreferenceValue: ThemePreference.dark,
      timeOfDayThemeEnabledValue: true,
    );
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings),
        child: MaterialApp(
          theme: testLightTheme(),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-language-selector')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('settings-language-selector')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('language-option-en')), findsOneWidget);
    expect(find.byKey(const ValueKey('language-option-ar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('language-option-ar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automatic'));
    await tester.pumpAndSettle();
    expect(settings.appLanguageValue, AppLanguage.ar);
    expect(settings.themePreferenceValue, ThemePreference.system);
    expect(settings.timeOfDayThemeEnabledValue, isTrue);
  });

  testWidgets('Settings shows Ad Inspector only outside production', (
    tester,
  ) async {
    Future<void> pumpForConfig(AppConfig config) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._testOverrides(settings),
            appConfigProvider.overrideWithValue(config),
          ],
          child: MaterialApp(
            theme: testLightTheme(),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpForConfig(AppConfig.test(environment: AppEnvironment.dev));
    expect(find.byKey(const ValueKey('settings-ad-inspector')), findsOneWidget);

    await pumpForConfig(
      AppConfig.configured(
        environment: AppEnvironment.prod,
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'sb_publishable_example',
        googleWebClientId: '123-example.apps.googleusercontent.com',
        sentryDsn: 'https://public@example.ingest.de.sentry.io/1234567890',
      ),
    );
    expect(find.byKey(const ValueKey('settings-ad-inspector')), findsNothing);
  });

  testWidgets(
    'Settings permission recovery stays readable on narrow scaled English and Arabic layouts',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      for (final locale in const [Locale('en'), Locale('ar')]) {
        final language = AppLanguage.values.byName(locale.languageCode);
        final l10n = lookupAppLocalizations(locale);
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          appLanguageValue: language,
          appLanguageExplicitValue: true,
        );
        settings.notificationPreferencesValue = const NotificationPreferences(
          preferExactReminders: true,
        );
        final permissions = FakeAppPermissionGateway(
          states: {
            AppPermissionKind.location: AppPermissionState.denied,
            AppPermissionKind.notifications: AppPermissionState.granted,
            AppPermissionKind.exactAlarms: AppPermissionState.denied,
          },
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: _testOverrides(settings, permissionGateway: permissions),
            child: MaterialApp(
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              theme: testLightTheme(),
              home: const SettingsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final recovery = find.byKey(const ValueKey('exact-reminders-recovery'));
        await tester.scrollUntilVisible(
          recovery,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        final title = find.descendant(
          of: recovery,
          matching: find.text(l10n.preciseReminderAlarms),
        );
        final status = find.descendant(
          of: recovery,
          matching: find.text(l10n.approximateTiming),
        );
        expect(title, findsOneWidget);
        expect(status, findsOneWidget);
        expect(
          tester.getTopLeft(status).dy,
          greaterThan(tester.getTopLeft(title).dy),
        );
        expect(
          Directionality.of(tester.element(recovery)),
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await settings.close();
      }
    },
  );

  testWidgets('Account nickname can be saved and cleared from the host', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    settings.profileValue = const AppProfile(nickname: 'Test User');
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings),
        child: MaterialApp(
          theme: testLightTheme(),
          home: const AccountScreenHost(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('account-nickname-option')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('account-nickname-field')),
      '  Pilot  ',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(settings.profileValue.nickname, 'Pilot');

    await tester.tap(find.byKey(const ValueKey('account-nickname-option')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(settings.profileValue.nickname, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the Home avatar opens the account screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(486, 1536);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    settings.profileValue = const AppProfile(nickname: 'Thulfqar');
    settings.homeLocationValue = const HomeLocation(
      label: 'Al-Diwaniyah District, Al-Qadisiyah Governorate',
      latitude: 31.9868,
      longitude: 44.9255,
    );
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(
            settings,
            weather: _weather(
              temperature: 46,
              locationLabel: 'Al-Diwaniyah District, Al-Qadisiyah Governorate',
            ),
          ),
          syncStatusProvider.overrideWithValue(
            AsyncData(
              SyncStatus(
                phase: SyncPhase.ready,
                enabled: true,
                lastSyncedAt: DateTime(2026, 7, 2, 14, 45),
                realtime: SyncRealtimeConnection.connected,
              ),
            ),
          ),
          syncConnectivityProvider.overrideWithValue(const AsyncData(true)),
        ],
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open account'));
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Thulfqar'), findsOneWidget);
    expect(find.text('Synchronization'), findsNothing);
    expect(find.text('Sync now'), findsNothing);
    expect(find.text('Nickname'), findsOneWidget);
    expect(find.text('Edit account'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme bundles Geist and includes light and dark themes', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: false);
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings),
        child: const OwntendApp(),
      ),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.textTheme.bodyMedium?.fontFamily, 'Geist');
    expect(app.theme?.colorScheme.brightness, Brightness.light);
    expect(app.themeMode, isIn([ThemeMode.light, ThemeMode.dark]));
    expect(app.darkTheme?.colorScheme.brightness, Brightness.dark);
  });

  testWidgets('PremiumEmptyState renders a native semantic illustration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: testLightTheme(),
        home: const Scaffold(
          body: hk_ui.PremiumEmptyState(
            icon: Icons.task_alt,
            title: 'No tasks',
            body: 'Nothing is due right now.',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(hk_ui.HkStateIllustration), findsOneWidget);
    expect(find.byIcon(Icons.task_alt), findsOneWidget);
  });

  testWidgets(
    'PremiumEmptyState keeps its illustration when motion is reduced',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: testLightTheme(),
          home: const Scaffold(
            body: hk_ui.HkMotion(
              reduceMotion: true,
              child: hk_ui.PremiumEmptyState(
                icon: Icons.task_alt,
                title: 'No tasks',
                body: 'Nothing is due right now.',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(hk_ui.HkStateIllustration), findsOneWidget);
      expect(find.byIcon(Icons.task_alt), findsOneWidget);
    },
  );

  testWidgets('CompactActionGroup centers and stacks action buttons', (
    tester,
  ) async {
    final buttons = [
      for (final label in ['One', 'Two', 'Three'])
        OutlinedButton(onPressed: () {}, child: Text(label)),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: testLightTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: hk_ui.CompactActionGroup(
                minButtonWidth: 96,
                children: buttons,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final oneWide = tester.getCenter(find.text('One'));
    final twoWide = tester.getCenter(find.text('Two'));
    final threeWide = tester.getCenter(find.text('Three'));
    final viewportCenter =
        tester.view.physicalSize.width / tester.view.devicePixelRatio / 2;
    expect(oneWide.dy, closeTo(twoWide.dy, 1));
    expect(twoWide.dy, closeTo(threeWide.dy, 1));
    expect(twoWide.dx, closeTo(viewportCenter, 12));

    await tester.pumpWidget(
      MaterialApp(
        theme: testLightTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: hk_ui.CompactActionGroup(
                minButtonWidth: 96,
                children: buttons,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final oneNarrow = tester.getCenter(find.text('One'));
    final twoNarrow = tester.getCenter(find.text('Two'));
    final threeNarrow = tester.getCenter(find.text('Three'));
    expect(oneNarrow.dy, lessThan(twoNarrow.dy));
    expect(twoNarrow.dy, lessThan(threeNarrow.dy));
  });

  testWidgets('editor sheets keep their header next to the drag handle', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;

    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final cases = <(String, String, void Function(BuildContext))>[
      (
        'Add room',
        'Create room',
        (context) => showRoomEditorSheet(context, areaId: 'area_first_floor'),
      ),
      (
        'Add item',
        'Create item',
        (context) => showAssetEditorSheet(context, roomId: 'room_kitchen'),
      ),
      (
        'Add task',
        'Create task',
        (context) => showPlanEditorSheet(context, assetId: 'asset_dishwasher'),
      ),
    ];

    for (final sheetCase in cases) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _testOverrides(settings),
          child: MaterialApp(
            theme: testLightTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => sheetCase.$3(context),
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();

      final handle = find.byKey(const ValueKey('editor-sheet-drag-handle'));
      expect(handle, findsOneWidget);
      final bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(bottomSheet.showDragHandle, isFalse);
      expect(find.text(sheetCase.$1), findsOneWidget);
      expect(find.text(sheetCase.$2), findsOneWidget);
      final gap =
          tester.getTopLeft(find.text(sheetCase.$1)).dy -
          tester.getBottomLeft(handle).dy;
      expect(gap, lessThan(64));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('editor save remains hittable above the software keyboard', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;

    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final repository = StartupAssetRepository(
      assets: const [],
      rooms: const [],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, assetRepository: repository),
        child: MaterialApp(
          theme: testLightTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAreaEditorSheet(context),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Keyboard area');
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();

    final hitSurface = find.byKey(const ValueKey('editor-modal-hit-surface'));
    expect(hitSurface, findsOneWidget);
    expect(tester.getSize(hitSurface).height, closeTo(844, 1));
    final save = find.text('Create area');
    expect(save, findsOneWidget);
    expect(tester.getBottomLeft(save).dy, lessThan(524));
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repository.savedAreaNames, ['Keyboard area']);
    expect(find.text('Create area'), findsNothing);
  });

  testWidgets('TaskCard animates completion and blocks duplicate taps', (
    tester,
  ) async {
    final result = Completer<bool>();
    var completionCalls = 0;
    final task = _taskItem(
      DateUtils.dateOnly(DateTime.now()),
      id: 'animated_completion',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: testLightTheme(),
        home: Scaffold(
          body: hk_ui.TaskCard(
            task: task,
            onComplete: () {
              completionCalls++;
              return result.future;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Complete task'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(completionCalls, 1);
    expect(find.byKey(const ValueKey('task-completion-sweep')), findsOneWidget);

    await tester.tap(find.byTooltip('Complete task'), warnIfMissed: false);
    await tester.pump();
    expect(completionCalls, 1);

    result.complete(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-completion-sweep')), findsNothing);
  });

  testWidgets('SwipeDelete labels trash action and restores below threshold', (
    tester,
  ) async {
    var calls = 0;
    await _pumpSwipeRows(
      tester,
      rows: [
        _swipeTestRow(
          'label',
          onAction: () async {
            calls++;
            return true;
          },
        ),
      ],
    );

    final row = find.byKey(const ValueKey('swipe-row-label'));
    final gesture = await tester.startGesture(tester.getCenter(row));
    await gesture.moveBy(const Offset(-70, 0));
    await tester.pump();

    expect(find.text('Move to Trash'), findsOneWidget);
    expect(find.text('Swipe to move to Trash'), findsOneWidget);
    expect(find.text('Review'), findsNothing);
    expect(find.text('Release to review'), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(row, findsOneWidget);
    expect(find.text('Move to Trash'), findsNothing);
  });

  testWidgets('SwipeDelete closes before running threshold action', (
    tester,
  ) async {
    var calls = 0;
    var backgroundClosedWhenActionStarted = false;
    await _pumpSwipeRows(
      tester,
      rows: [
        _swipeTestRow(
          'confirm',
          onAction: () async {
            calls++;
            backgroundClosedWhenActionStarted =
                find.text('Move to Trash').evaluate().isEmpty &&
                find.text('Swipe to move to Trash').evaluate().isEmpty &&
                find.text('Release to move to Trash').evaluate().isEmpty;
            return false;
          },
        ),
      ],
    );

    await tester.drag(
      find.byKey(const ValueKey('swipe-row-confirm')),
      const Offset(-500, 0),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    expect(calls, 1);
    expect(backgroundClosedWhenActionStarted, isTrue);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('swipe-row-confirm')), findsOneWidget);
    expect(find.text('Move to Trash'), findsNothing);
  });

  testWidgets('SwipeDelete restores row when threshold action fails', (
    tester,
  ) async {
    var calls = 0;
    await _pumpSwipeRows(
      tester,
      rows: [
        _swipeTestRow(
          'failure',
          onAction: () async {
            calls++;
            throw StateError('unavailable');
          },
        ),
      ],
    );

    await tester.drag(
      find.byKey(const ValueKey('swipe-row-failure')),
      const Offset(-500, 0),
    );
    await _waitForSwipeBackgroundToClose(tester);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.byKey(const ValueKey('swipe-row-failure')), findsOneWidget);
    expect(find.text('Move to Trash'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SwipeDelete keeps only one row visually open', (tester) async {
    await _pumpSwipeRows(
      tester,
      rows: [
        _swipeTestRow('first', onAction: () async => true),
        _swipeTestRow('second', onAction: () async => true),
      ],
    );

    final first = find.byKey(const ValueKey('swipe-row-first'));
    final second = find.byKey(const ValueKey('swipe-row-second'));
    final firstGesture = await tester.startGesture(tester.getCenter(first));
    await firstGesture.moveBy(const Offset(-70, 0));
    await tester.pump();
    expect(find.text('Move to Trash'), findsOneWidget);

    final secondGesture = await tester.startGesture(tester.getCenter(second));
    await secondGesture.moveBy(const Offset(-70, 0));
    await tester.pump();
    expect(find.text('Move to Trash'), findsOneWidget);

    await firstGesture.up();
    await secondGesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Move to Trash'), findsNothing);
  });

  testWidgets('SwipeDelete mirrors trailing swipe direction in RTL', (
    tester,
  ) async {
    var calls = 0;
    await _pumpSwipeRows(
      tester,
      locale: const Locale('ar'),
      rows: [
        _swipeTestRow(
          'rtl',
          onAction: () async {
            calls++;
            return false;
          },
        ),
      ],
    );

    await tester.drag(
      find.byKey(const ValueKey('swipe-row-rtl')),
      const Offset(500, 0),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.byKey(const ValueKey('swipe-row-rtl')), findsOneWidget);
  });

  testWidgets('TaskCard shows disabled state and enable action', (
    tester,
  ) async {
    final changes = <bool>[];
    final task = _taskItem(
      DateUtils.dateOnly(DateTime.now()),
      id: 'disabled_card',
      isEnabled: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: testLightTheme(),
        home: Scaffold(
          body: hk_ui.TaskCard(
            task: task,
            onComplete: () async => true,
            onSnooze: () {},
            onSetEnabled: (enabled) async => changes.add(enabled),
            onArchive: () {},
          ),
        ),
      ),
    );

    expect(find.text('Disabled'), findsOneWidget);
    expect(find.byTooltip('Complete task'), findsNothing);

    await tester.tap(find.byTooltip('Task actions'));
    await tester.pumpAndSettle();

    expect(find.text('Enable task'), findsOneWidget);
    expect(find.text('Snooze'), findsNothing);
    expect(find.text('Move task to Trash'), findsOneWidget);

    await tester.tap(find.text('Enable task'));
    await tester.pump();

    expect(changes, [true]);
  });

  testWidgets('custom task feedback audio assets are packaged WAV files', (
    tester,
  ) async {
    for (final path in [
      'assets/audio/task_done.wav',
      'assets/audio/task_delete.wav',
    ]) {
      final bytes = await rootBundle.load(path);
      expect(bytes.lengthInBytes, greaterThan(44));
      expect(String.fromCharCodes(bytes.buffer.asUint8List(0, 4)), 'RIFF');
    }
  });

  testWidgets('dashboard layout renders at phone and wide sizes', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in [const Size(390, 844), const Size(900, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;

      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final task = _taskItem(DateTime.now());

      await tester.pumpWidget(
        ProviderScope(
          overrides: _testOverrides(settings, tasks: [task]),
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Today's tasks"), findsOneWidget);
      expect(find.text('Feed the fish'), findsOneWidget);
      expect(find.text('Care rhythm'), findsNothing);
      expect(find.byType(hk_ui.GlassPanel), findsNothing);
      expect(find.byType(hk_ui.SereneBottomNavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Home shows Tomorrow tasks beside full Today preview', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final today = DateUtils.dateOnly(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(
          settings,
          tasks: [
            _taskItem(today, id: 'plan_today_one', title: 'Today one'),
            _taskItem(today, id: 'plan_today_two', title: 'Today two'),
            _taskItem(today, id: 'plan_today_three', title: 'Today three'),
            _taskItem(today, id: 'plan_today_four', title: 'Today four'),
            _taskItem(
              tomorrow,
              id: 'plan_tomorrow_one',
              title: 'Tomorrow one',
              status: TaskStatus.upcoming,
            ),
          ],
        ),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Today's tasks"), findsOneWidget);
    expect(find.text("Tomorrow's tasks"), findsOneWidget);
    expect(find.text('Today one'), findsOneWidget);
    expect(find.text('Today two'), findsOneWidget);
    expect(find.text('Today three'), findsOneWidget);
    expect(find.text('Today four'), findsNothing);
    expect(find.text('Tomorrow one'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home FAB does not overlap the visible task card', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;

    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final task = _taskItem(DateUtils.dateOnly(DateTime.now()));

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, tasks: [task]),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    final taskRect = tester.getRect(find.byType(hk_ui.TaskCard).first);
    final fabRect = tester.getRect(find.byType(FloatingActionButton));

    expect(taskRect.overlaps(fabRect), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home no longer renders the care rhythm card', (tester) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final task = _taskItem(DateUtils.dateOnly(DateTime.now()));

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, tasks: [task]),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Care rhythm'), findsNothing);
    expect(find.text('Best 0'), findsNothing);
  });

  testWidgets('Home readiness score drops when a task is overdue', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final overdueTask = _taskItem(
      DateUtils.dateOnly(DateTime.now()).subtract(const Duration(days: 1)),
      status: TaskStatus.overdue,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(
          settings,
          tasks: [overdueTask],
          backupState: BackupState(
            lastBackup: BackupStatus(
              successful: true,
              updatedAt: DateTime(2026, 6, 18),
              trigger: BackupTrigger.automatic,
            ),
          ),
        ),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home readiness'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
    expect(find.text('1'), findsWidgets);
    expect(find.text('Overdue'), findsOneWidget);
  });

  testWidgets('Home scroll stays enabled for short and long task lists', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final today = DateUtils.dateOnly(DateTime.now());

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(
          settings,
          tasks: [
            _taskItem(today, id: 'plan_one', title: 'Task one'),
            _taskItem(today, id: 'plan_two', title: 'Task two'),
          ],
        ),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    var scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(scrollView.physics, isA<AlwaysScrollableScrollPhysics>());

    await tester.pumpWidget(const SizedBox.shrink());

    final nextSettings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(nextSettings.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(
          nextSettings,
          tasks: [
            _taskItem(today, id: 'plan_one', title: 'Task one'),
            _taskItem(today, id: 'plan_two', title: 'Task two'),
            _taskItem(today, id: 'plan_three', title: 'Task three'),
          ],
        ),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    scrollView = tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    expect(scrollView.physics, isA<AlwaysScrollableScrollPhysics>());
  });

  testWidgets('Home weather shows three details without Rain', (tester) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, weather: _weather()),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Feels 24°C'), findsOneWidget);
    expect(find.text('Humidity 56%'), findsOneWidget);
    expect(find.text('Wind 12 km/h'), findsOneWidget);
    expect(find.textContaining('Rain'), findsNothing);
  });

  testWidgets(
    'Home header actions remain aligned and accessible across sizes and themes',
    (tester) async {
      final semantics = tester.ensureSemantics();
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;

      for (final theme in [OwntendTheme.light(), OwntendTheme.dark()]) {
        for (final width in [320.0, 600.0]) {
          tester.view.physicalSize = Size(width, 844);
          final settings = FakeSettingsRepository(
            onboardingCompletedValue: true,
          );
          final router = await _pumpDashboardHeader(
            tester,
            settings: settings,
            theme: theme,
          );
          addTearDown(settings.close);
          addTearDown(router.dispose);

          final points = find.byKey(const ValueKey('home-points-control'));
          final notifications = find.byKey(
            const ValueKey('home-notifications-control'),
          );
          expect(points, findsOneWidget);
          expect(notifications, findsOneWidget);
          // Spec: compact (<360 layout px) → 40 px; standard (≥360) → 44 px.
          // At screen 320 the full layout width is 320, which is <360 → compact.
          // At screen 600 the full layout width is 600 → standard.
          final expectedH = width == 320.0 ? 40.0 : 44.0;
          expect(tester.getSize(points).height, expectedH);
          expect(tester.getSize(notifications), Size(expectedH, expectedH));
          expect(
            tester.getTopLeft(notifications).dx -
                tester.getBottomRight(points).dx,
            // Spec: compact (<360 px) gap = 6; standard gap = HkSpacing.xs (8).
            width == 320.0 ? 6.0 : HkSpacing.xs,
          );
          expect(find.text('Good afternoon'), findsNothing);
          expect(find.text("Let's make today productive"), findsNothing);
          // At screen width 320 the layout is compact (<360), placeholder is short.
          // At screen width 600 the layout is large (>400), full placeholder shown.
          final expectedSearch = width == 320.0
              ? 'Search\u2026'
              : 'Search rooms, items, tasks, notes';
          expect(find.text(expectedSearch), findsOneWidget);
          expect(
            find.descendant(of: points, matching: find.text('Points')),
            findsNothing,
          );
          expect(
            find.descendant(
              of: points,
              matching: find.byIcon(Symbols.chevron_right_rounded),
            ),
            findsNothing,
          );
          expect(find.bySemanticsLabel('7 points'), findsOneWidget);
          expect(
            find.bySemanticsLabel('Notifications, 3 unread'),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('home-notification-unread-badge')),
            findsOneWidget,
          );
          final unreadBadge = tester.widget<Container>(
            find.byKey(const ValueKey('home-notification-unread-badge')),
          );
          expect(
            (unreadBadge.decoration! as BoxDecoration).color,
            // Spec: status_danger #EF4444 (brighter red than legacy appDanger).
            const Color(0xFFEF4444),
          );
          final notificationMaterial = tester.widget<Material>(
            find
                .descendant(of: notifications, matching: find.byType(Material))
                .first,
          );
          expect(
            notificationMaterial.color,
            theme.colorScheme.surfaceContainerLowest,
          );
          expect(tester.takeException(), isNull);
        }
      }
      semantics.dispose();
    },
  );

  testWidgets('dashboard header has desktop and mobile golden baselines', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final entry in {
      'mobile': const Size(390, 844),
      'desktop': const Size(1440, 900),
    }.entries) {
      tester.view.physicalSize = entry.value;
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      final router = await _pumpDashboardHeader(
        tester,
        settings: settings,
        theme: OwntendTheme.light(),
      );
      addTearDown(settings.close);
      addTearDown(router.dispose);

      await expectLater(
        find.byKey(const ValueKey('dashboard-header-card')),
        matchesGoldenFile('goldens/dashboard_header_${entry.key}.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Home header points and notification controls keep navigation', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    final router = await _pumpDashboardHeader(
      tester,
      settings: settings,
      theme: OwntendTheme.light(),
    );
    addTearDown(settings.close);
    addTearDown(router.dispose);

    await tester.tap(find.byKey(const ValueKey('home-points-control')));
    await tester.pumpAndSettle();
    expect(find.text('Points wallet'), findsOneWidget);
    expect(find.text('7 / 20'), findsOneWidget);

    Navigator.of(
      tester.element(find.text('Points wallet')),
      rootNavigator: true,
    ).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-notifications-control')));
    await tester.pumpAndSettle();
    expect(find.text('Notification route target'), findsOneWidget);
  });

  testWidgets('compact points card appears only on Home Rooms and Tasks', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(settings),
          monetizationRepositoryProvider.overrideWithValue(null),
          pointWalletProvider.overrideWithValue(
            AsyncData(
              PointWallet(
                balance: 7,
                timeZone: 'Asia/Baghdad',
                updatedAt: DateTime.utc(2026, 8, 2),
              ),
            ),
          ),
          monetizationConfigProvider.overrideWithValue(
            const AsyncData(MonetizationConfig.failClosed()),
          ),
          pendingRewardClaimsProvider.overrideWithValue(const AsyncData([])),
        ],
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    void expectCompactPointsCard() {
      final points = find.byType(HkPointsPill);
      expect(points, findsOneWidget);
      // Spec: Component C is now an intrinsic-width squircle tile at 44 px height.
      // The old fixed width (82 px) and height (48 px) from HeaderActionSurface
      // no longer apply after the modular refactoring.
      final size = tester.getSize(points);
      expect(size.height, 44.0);
      expect(size.width, greaterThan(0));
      expect(
        find.descendant(of: points, matching: find.text('Points')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: points,
          matching: find.byIcon(Symbols.chevron_right_rounded),
        ),
        findsNothing,
      );
    }

    expectCompactPointsCard();

    await tester.tap(find.text('Rooms').last);
    await tester.pumpAndSettle();
    expectCompactPointsCard();

    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    expectCompactPointsCard();

    await tester.tap(find.text('Calendar').last);
    await tester.pumpAndSettle();
    expect(find.byType(HkPointsPill), findsNothing);

    await tester.tap(find.text('Tools').last);
    await tester.pumpAndSettle();
    expect(find.byType(HkPointsPill), findsNothing);

    await tester.tap(find.text('Statistics'));
    await tester.pumpAndSettle();
    expect(find.byType(HkPointsPill), findsNothing);
  });

  testWidgets('Home weather shortens long district labels', (tester) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(
          settings,
          weather: _weather(
            locationLabel: 'Al-Diwaniyah District, Al-Qadisiyah Governorate',
          ),
        ),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Al-Diwaniyah'), findsOneWidget);
    expect(find.textContaining('Al-Qadisiyah'), findsNothing);
  });

  testWidgets('Home does not request missing weather after startup', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true)
      ..homeLocationValue = const HomeLocation(
        label: 'Baghdad',
        latitude: 33.3152,
        longitude: 44.3661,
      );
    final weatherRepository = CountingWeatherRepository();
    addTearDown(settings.close);
    late VoidCallback rebuildParent;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(settings, weatherRepository: weatherRepository),
        ],
        child: MaterialApp(
          theme: testLightTheme(),
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuildParent = () => setState(() {});
              return DashboardScreen();
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(weatherRepository.refreshCount, 0);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -360));
    await tester.pump();
    expect(find.text('Weather unavailable'), findsOneWidget);
    expect(find.text('Weather not set'), findsNothing);

    for (var index = 0; index < 3; index++) {
      rebuildParent();
      await tester.pump();
    }

    expect(weatherRepository.refreshCount, 0);
    expect(find.text('Set up your home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home ignores equal database bursts and commits real changes', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    final taskChanges = StreamController<List<TaskItem>>.broadcast();
    final assetChanges = StreamController<List<Asset>>.broadcast();
    final roomChanges = StreamController<List<Room>>.broadcast();
    final now = DateTime(2026);
    final tasks = [_taskItem(DateUtils.dateOnly(DateTime.now()))];
    final assets = _things(now);
    final rooms = _rooms(now);
    final initialSnapshot = ValueNotifier<InitialHomeSnapshot?>(
      InitialHomeSnapshot(
        session: _signedInTestSession,
        profile: const AppProfile(nickname: 'Pilot'),
        tasks: tasks,
        assets: assets,
        rooms: rooms,
        backupState: const BackupState(),
        unreadNotifications: 0,
        syncStatus: const SyncStatus(phase: SyncPhase.ready),
        loadedAt: now,
      ),
    );
    addTearDown(settings.close);
    addTearDown(initialSnapshot.dispose);
    addTearDown(taskChanges.close);
    addTearDown(assetChanges.close);
    addTearDown(roomChanges.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(
            settings,
            tasks: tasks,
            taskStream: taskChanges.stream,
            assetStream: assetChanges.stream,
            roomStream: roomChanges.stream,
          ),
          initialHomeSnapshotProvider.overrideWithValue(initialSnapshot),
        ],
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: testLightTheme(),
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pump();
    taskChanges.add(tasks);
    assetChanges.add(assets);
    roomChanges.add(rooms);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    taskChanges.add(tasks);
    assetChanges.add(assets);
    roomChanges.add(rooms);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 300));

    final stabilityBoundary = find.byKey(
      const ValueKey('home-stability-boundary'),
    );
    for (
      var attempt = 0;
      attempt < 20 && stabilityBoundary.evaluate().isEmpty;
      attempt++
    ) {
      taskChanges.add(tasks);
      assetChanges.add(assets);
      roomChanges.add(rooms);
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(stabilityBoundary, findsOneWidget);
    final initialRenderBoundary = tester.renderObject<RenderRepaintBoundary>(
      stabilityBoundary,
    );
    expect(initialRenderBoundary.debugNeedsPaint, isFalse);

    taskChanges.add(List<TaskItem>.of(tasks));
    assetChanges.add(List<Asset>.of(assets));
    roomChanges.add(List<Room>.of(rooms));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final stableRenderBoundary = tester.renderObject<RenderRepaintBoundary>(
      stabilityBoundary,
    );
    expect(identical(stableRenderBoundary, initialRenderBoundary), isTrue);
    expect(stableRenderBoundary.debugNeedsPaint, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);

    final changedTasks = [
      _taskItem(
        tasks.single.plan.nextDueDate,
        title: 'Feed the fish carefully',
      ),
    ];
    taskChanges.add(changedTasks);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Feed the fish carefully'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home, Item, Task, and Statistics stay stable through navigation',
    (tester) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      final task = _taskItem(DateUtils.dateOnly(DateTime.now()));
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _testOverrides(settings, tasks: [task]),
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('home-stability-boundary')),
        findsOneWidget,
      );

      final router = GoRouter.of(tester.element(find.byType(HomeShell)));

      router.go('/assets');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('rooms-stability-boundary')),
        findsOneWidget,
      );

      router.go('/assets/room/room_kitchen');
      await tester.pumpAndSettle();
      router.go('/assets/thing/asset_dishwasher');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('item-detail-stability-boundary')),
        findsOneWidget,
      );

      router.go('/maintenance');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('tasks-stability-boundary')),
        findsOneWidget,
      );

      router.go('/maintenance/${task.plan.id}');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('task-detail-stability-boundary')),
        findsOneWidget,
      );

      router.go('/statistics');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('statistics-stability-boundary')),
        findsOneWidget,
      );

      router.go('/');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('home-stability-boundary')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home weather details stay in one row on small scaled screens', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;

    await tester.pumpWidget(
      MaterialApp(
        theme: testLightTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 254,
              child: WeatherDetailChips(
                weather: _weather(
                  apparentTemperature: -123,
                  humidity: 100,
                  windSpeed: 123,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final feels = find.text('Feels -123\u00B0C');
    final humidity = find.text('Humidity 100%');
    final wind = find.text('Wind 123 km/h');

    expect(feels, findsOneWidget);
    expect(humidity, findsOneWidget);
    expect(wind, findsOneWidget);
    expect(
      tester.getCenter(humidity).dy,
      closeTo(tester.getCenter(feels).dy, 1),
    );
    expect(tester.getCenter(wind).dy, closeTo(tester.getCenter(feels).dy, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('statistics distribution legend uses two centered lines', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: testLightTheme(),
        home: const Scaffold(
          body: SizedBox(
            width: 260,
            height: 260,
            child: TaskDistributionChart(
              data: {
                HealthGroup.appliances: 6,
                HealthGroup.plants: 5,
                HealthGroup.pets: 4,
                HealthGroup.safety: 3,
                HealthGroup.cleaning: 2,
                HealthGroup.other: 1,
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final labels = [
      'Appliances 6',
      'Plants 5',
      'Pets 4',
      'Safety 3',
      'Cleaning 2',
      'General 1',
    ];
    final firstRowY = tester.getCenter(find.text(labels[0])).dy;
    final secondRowY = tester.getCenter(find.text(labels[3])).dy;

    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
    }
    for (final label in labels.take(3)) {
      expect(tester.getCenter(find.text(label)).dy, closeTo(firstRowY, 1));
    }
    for (final label in labels.skip(3)) {
      expect(tester.getCenter(find.text(label)).dy, closeTo(secondRowY, 1));
    }
    expect(secondRowY, greaterThan(firstRowY));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Weather header exposes day-night theme toggle', (tester) async {
    final settings = FakeSettingsRepository(
      onboardingCompletedValue: true,
      themePreferenceValue: ThemePreference.dark,
      timeOfDayThemeEnabledValue: true,
    );
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, weather: _weather()),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set up your home'), findsOneWidget);
    expect(find.text('Search rooms, items, tasks, notes'), findsOneWidget);
    expect(find.text('Good afternoon'), findsNothing);
    expect(find.byType(hk_ui.SereneBottomNavigationBar), findsOneWidget);
    final toggle = find.byTooltip('Switch to light mode');
    expect(toggle, findsOneWidget);
    tester
        .widget<IconButton>(
          find.descendant(of: toggle, matching: find.byType(IconButton)),
        )
        .onPressed
        ?.call();
    await tester.pumpAndSettle();
    expect(settings.themePreferenceValue, ThemePreference.light);
    expect(settings.timeOfDayThemeEnabledValue, isFalse);
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString().contains('ThemeDropOverlay'),
      ),
      findsNothing,
    );
  });

  testWidgets('Weather dashboard honors saved dark settings', (tester) async {
    final settings = FakeSettingsRepository(
      onboardingCompletedValue: true,
      themePreferenceValue: ThemePreference.dark,
      timeOfDayThemeEnabledValue: true,
    );
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, weather: _weather()),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.darkTheme?.colorScheme.brightness, Brightness.dark);
    expect(find.byTooltip('Switch to dark mode'), findsNothing);
    expect(find.byTooltip('Switch to light mode'), findsOneWidget);
    expect(settings.themePreferenceValue, ThemePreference.dark);
    expect(settings.timeOfDayThemeEnabledValue, isTrue);
  });

  testWidgets('Settings shows manual and automatic theme controls', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings),
        child: MaterialApp(
          theme: testLightTheme(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-language-selector')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('settings-language-selector')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('language-option-en')), findsOneWidget);
    expect(find.byKey(const ValueKey('language-option-ar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('language-option-en')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(settings.themePreferenceValue, ThemePreference.dark);
    expect(settings.timeOfDayThemeEnabledValue, isFalse);
  });

  testWidgets('home map renders rooms at phone and wide sizes', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in [const Size(390, 844), const Size(900, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;

      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _testOverrides(settings),
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rooms').last);
      await tester.pumpAndSettle();

      expect(find.text('Rooms'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(hk_ui.HkStateIllustration),
        ),
        findsNothing,
      );
      expect(find.byTooltip('Add area'), findsOneWidget);
      expect(find.byTooltip('Use template'), findsNothing);
      expect(find.text('Main Level'), findsWidgets);
      expect(find.text('Upper Level'), findsOneWidget);
      expect(find.text('Garden'), findsOneWidget);
      expect(find.text('2 rooms'), findsWidgets);
      expect(find.text('Search rooms'), findsNothing);
      expect(
        find.byKey(const ValueKey('area-chip-area_outdoor_garden')),
        findsOneWidget,
      );
      expect(find.text('Kitchen'), findsWidgets);
      expect(find.text('2 items'), findsOneWidget);
      final kitchenCard = find.byKey(const ValueKey('room-card-room_kitchen'));
      expect(kitchenCard, findsOneWidget);
      expect(tester.getSize(kitchenCard).height, lessThanOrEqualTo(136));
      if (size.width >= 620) {
        final generalCard = find.byKey(
          const ValueKey('room-card-room_general'),
        );
        expect(generalCard, findsOneWidget);
        expect(
          tester.getTopLeft(generalCard).dy,
          tester.getTopLeft(kitchenCard).dy,
        );
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('tasks screen groups work by urgency and shows locations', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final now = DateUtils.dateOnly(DateTime.now());
    final tasks = [
      _taskItem(
        now.subtract(const Duration(days: 1)),
        id: 'plan_overdue',
        title: 'Replace filter',
        status: TaskStatus.overdue,
      ),
      _taskItem(now, id: 'plan_today', status: TaskStatus.dueToday),
      _taskItem(
        now.add(const Duration(days: 1)),
        id: 'plan_tomorrow',
        title: 'Flush heater',
        status: TaskStatus.upcoming,
      ),
      _taskItem(
        now.add(const Duration(days: 3)),
        id: 'plan_next',
        title: 'Clean vent',
        status: TaskStatus.upcoming,
      ),
      _taskItem(
        now.add(const Duration(days: 20)),
        id: 'plan_later',
        title: 'Service pump',
        status: TaskStatus.upcoming,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, tasks: tasks),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();

    expect(find.text('Overdue'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(hk_ui.HkStateIllustration),
      ),
      findsNothing,
    );
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('Next 7 days'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Today')).dy,
      lessThan(tester.getTopLeft(find.text('Tomorrow')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Tomorrow')).dy,
      lessThan(tester.getTopLeft(find.text('Next 7 days')).dy),
    );
    expect(find.text('1 task'), findsAtLeastNWidgets(3));
    expect(find.text('Fish in Kitchen'), findsWidgets);
    expect(find.text('Due now'), findsOneWidget);
    expect(find.text('Overdue by 1 day'), findsOneWidget);

    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Later'), findsOneWidget);
    expect(find.text('1 task'), findsAtLeastNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a task opens task detail', (tester) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final task = _taskItem(
      DateUtils.dateOnly(DateTime.now()),
      id: 'plan_today',
      title: 'Replace filter',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, tasks: [task]),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace filter').first);
    await tester.pumpAndSettle();

    expect(find.text('Next due'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Open item'), findsOneWidget);
  });

  testWidgets('task detail disables task and cancels reminders', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final scheduler = FakeNotificationScheduler();
    final task = _taskItem(
      DateUtils.dateOnly(DateTime.now()),
      id: 'plan_disable',
      title: 'Replace filter',
    );
    final maintenance = FakeMaintenanceRepository(initialTasks: [task]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(
            settings,
            tasks: [task],
            notificationScheduler: scheduler,
            maintenanceRepository: maintenance,
          ),
        ],
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace filter').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Task actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disable task'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(maintenance.enabledChanges, [
      (planId: 'plan_disable', enabled: false),
    ]);
    expect(scheduler.cancelled, ['plan_disable']);
    expect(scheduler.refreshCount, 1);
    expect(find.text('Task disabled.'), findsOneWidget);
  });

  testWidgets('swiping moves a task to Trash with countdown and Undo', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final task = _taskItem(
      DateUtils.dateOnly(DateTime.now()),
      id: 'plan_today',
    );
    final maintenance = FakeMaintenanceRepository(initialTasks: [task]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(
            settings,
            tasks: [task],
            maintenanceRepository: maintenance,
          ),
        ],
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    await _dragSwipeRowPastThreshold(
      tester,
      find.byKey(const ValueKey('task-delete-plan_today')),
      dialogTitle: 'Move task to Trash?',
    );

    expect(find.text('Move task to Trash?'), findsOneWidget);
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();
    expect(maintenance.archivedPlanIds, ['plan_today']);
    expect(find.text('Task moved to Trash.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    for (var index = 0; index < 4; index++) {
      await tester.pump();
    }
    expect(maintenance.restoredPlanIds, ['plan_today']);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('Trash Undo expires without permanently deleting the task', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final task = _taskItem(
      DateUtils.dateOnly(DateTime.now()),
      id: 'plan_expiry',
    );
    final maintenance = FakeMaintenanceRepository(initialTasks: [task]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(
            settings,
            tasks: [task],
            maintenanceRepository: maintenance,
          ),
        ],
        child: const OwntendApp(),
      ),
    );
    FeedbackCoordinator.instance.resetForTesting();
    hkRootScaffoldMessengerKey.currentState?.clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    await _dragSwipeRowPastThreshold(
      tester,
      find.byKey(const ValueKey('task-delete-plan_expiry')),
      dialogTitle: 'Move task to Trash?',
    );
    expect(find.text('Move task to Trash?'), findsOneWidget);
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();
    expect(find.text('Task moved to Trash.'), findsOneWidget);

    hkRootScaffoldMessengerKey.currentState?.hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.pump();
    expect(find.text('Task moved to Trash.'), findsNothing);
    expect(maintenance.archivedPlanIds, ['plan_expiry']);
    expect(maintenance.restoredPlanIds, isEmpty);
  });

  testWidgets('cancelled swipe confirmation leaves the task active', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final task = _taskItem(
      DateUtils.dateOnly(DateTime.now()),
      id: 'plan_cancelled',
    );
    final maintenance = FakeMaintenanceRepository(initialTasks: [task]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(
            settings,
            tasks: [task],
            maintenanceRepository: maintenance,
          ),
        ],
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('task-delete-plan_cancelled'));
    await _dragSwipeRowPastThreshold(
      tester,
      row,
      dialogTitle: 'Move task to Trash?',
    );

    expect(find.text('Move task to Trash?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(maintenance.archivedPlanIds, isEmpty);
    expect(row, findsOneWidget);
    expect(find.text('Task moved to Trash.'), findsNothing);
    expect(find.text('Move to Trash'), findsNothing);
  });

  testWidgets('swipe archive failure leaves the task active and reports it', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final task = _taskItem(
      DateUtils.dateOnly(DateTime.now()),
      id: 'plan_failure',
    );
    final maintenance = FakeMaintenanceRepository(
      archiveFailure: StateError('archive unavailable'),
      initialTasks: [task],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(
            settings,
            tasks: [task],
            maintenanceRepository: maintenance,
          ),
        ],
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    await _dragSwipeRowPastThreshold(
      tester,
      find.byKey(const ValueKey('task-delete-plan_failure')),
      dialogTitle: 'Move task to Trash?',
    );

    expect(find.text('Move task to Trash?'), findsOneWidget);
    await tester.tap(find.text('Move to Trash'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text(
        lookupAppLocalizations(const Locale('en'))
            .theTaskCouldNotBeUpdatedPleaseTryAgain,
      ),
      findsOneWidget,
    );
    expect(find.text('Task moved to Trash.'), findsNothing);
    expect(find.text('Move to Trash'), findsNothing);
    expect(maintenance.archivedPlanIds, isEmpty);
    expect(maintenance.restoredPlanIds, isEmpty);
  });

  testWidgets('calendar renders an aligned month grid and selected day tasks', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;

    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final today = DateUtils.dateOnly(DateTime.now());
    final task = _taskItem(today);
    final tomorrowTask = _taskItem(
      today.add(const Duration(days: 1)),
      id: 'plan_calendar_tomorrow',
      title: 'Tomorrow calendar task',
      status: TaskStatus.upcoming,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, tasks: [task, tomorrowTask]),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar').last);
    await tester.pumpAndSettle();

    expect(
      find.text(DateFormat.yMMMM().format(DateTime(today.year, today.month))),
      findsOneWidget,
    );
    for (final weekday in ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']) {
      expect(find.text(weekday), findsOneWidget);
    }
    expect(
      find.byKey(ValueKey('calendar-day-${today.toIso8601String()}')),
      findsOneWidget,
    );
    expect(find.text(DateFormat.yMMMMEEEEd().format(today)), findsOneWidget);
    expect(find.text('Feed the fish'), findsOneWidget);
    expect(find.text('Tomorrow calendar task'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('room detail opens grouped items', (tester) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rooms').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitchen').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Devices & Appliances'), findsOneWidget);
    expect(find.text('Dishwasher'), findsOneWidget);
    expect(find.text('Basil'), findsOneWidget);
  });

  testWidgets('tapping an item opens item detail', (tester) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings),
        child: const OwntendApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rooms').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitchen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dishwasher').first);
    await tester.pumpAndSettle();

    expect(find.text('Related tasks'), findsOneWidget);
    expect(find.text('No tasks yet'), findsOneWidget);
    final addPhoto = find.byKey(const ValueKey('item-add-photo'));
    final addTask = find.byKey(const ValueKey('item-add-task'));
    expect(tester.getSize(addPhoto), tester.getSize(addTask));
    expect(
      tester.getCenter(addPhoto).dy,
      closeTo(tester.getCenter(addTask).dy, 1),
    );
    final photoIcon = find.descendant(
      of: addPhoto,
      matching: find.byIcon(Symbols.add_photo_alternate_rounded),
    );
    final photoLabel = find.descendant(
      of: addPhoto,
      matching: find.text('Add photo'),
    );
    final taskIcon = find.descendant(
      of: addTask,
      matching: find.byIcon(Symbols.add_task_rounded),
    );
    final taskLabel = find.descendant(
      of: addTask,
      matching: find.text('Add task'),
    );
    final photoContentCenter =
        (tester.getTopLeft(photoIcon).dx +
            tester.getBottomRight(photoLabel).dx) /
        2;
    final taskContentCenter =
        (tester.getTopLeft(taskIcon).dx + tester.getBottomRight(taskLabel).dx) /
        2;
    expect(photoContentCenter, closeTo(tester.getCenter(addPhoto).dx, 1));
    expect(taskContentCenter, closeTo(tester.getCenter(addTask).dx, 1));
    expect(
      tester.getCenter(photoIcon).dy,
      closeTo(tester.getCenter(photoLabel).dy, 1),
    );
    expect(
      tester.getCenter(taskIcon).dy,
      closeTo(tester.getCenter(taskLabel).dy, 1),
    );
  });

  testWidgets('item editor renders dynamic detail fields', (tester) async {
    final cases = <AssetType, List<String>>{
      AssetType.device: ['Device details', 'Brand', 'Power source'],
      AssetType.pet: ['Pet details', 'Pet Type', 'Breed', 'Vet phone'],
      AssetType.plant: ['Plant details', 'Sunlight', 'Watering interval'],
      AssetType.safety: ['Safety details', 'Safety type', 'Test interval'],
      AssetType.general: ['Item type', 'Placement', 'Tags'],
    };

    for (final entry in cases.entries) {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      final asset = _thing('thing_${entry.key.name}', 'Sample', entry.key);
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._testOverrides(settings),
            assetTagsProvider(asset.id).overrideWithValue(const AsyncData([])),
          ],
          child: MaterialApp(
            theme: testLightTheme(),
            home: Scaffold(
              body: AssetEditorDialog(asset: asset, roomId: 'room_kitchen'),
            ),
          ),
        ),
      );
      await tester.pump();

      for (final label in entry.value) {
        expect(find.text(label), findsOneWidget);
      }
      if (entry.key == AssetType.pet) {
        final currentPetType = find.text('Cat');
        await tester.ensureVisible(currentPetType);
        await tester.pumpAndSettle();
        await tester.tap(currentPetType);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Fish').last);
        await tester.pumpAndSettle();
        expect(find.text('Fish Type'), findsOneWidget);
        expect(find.text('Goldfish'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('task editor can create and add another task', (tester) async {
    final maintenance = FakeMaintenanceRepository();
    final monetization = FakeMonetizationRepository();
    final drafts = FakeOfflineCreationDraftStore();
    final now = DateTime(2026);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          maintenanceRepositoryProvider.overrideWithValue(maintenance),
          monetizationRepositoryProvider.overrideWithValue(monetization),
          taskCreationOperationStoreProvider.overrideWithValue(
            TaskCreationOperationStore(),
          ),
          offlineCreationDraftStoreProvider.overrideWithValue(drafts),
          syncConnectivityInstanceProvider.overrideWithValue(
            const AlwaysOnlineSyncConnectivity(),
          ),
          notificationSchedulerProvider.overrideWithValue(
            FakeNotificationScheduler(),
          ),
          assetsProvider.overrideWithValue(AsyncData(_things(now))),
        ],
        child: MaterialApp(
          theme: testLightTheme(),
          home: const Scaffold(
            body: PlanEditorDialog(assetId: 'asset_dishwasher'),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextField, 'Task title'),
      'Clean seals',
    );
    await tester.pump();
    final createAnother = find.widgetWithText(
      OutlinedButton,
      'Create & add another',
    );
    expect(tester.widget<OutlinedButton>(createAnother).onPressed, isNotNull);
    tester.widget<OutlinedButton>(createAnother).onPressed!();
    for (
      var attempt = 0;
      attempt < 20 && maintenance.savedTitles.isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(maintenance.savedTitles, ['Clean seals']);
    expect(find.text('Task created.'), findsOneWidget);
    final titleField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Task title'),
    );
    expect(titleField.controller?.text, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, 'Task title'),
      'Check hoses',
    );
    await tester.pump();
    tester.widget<OutlinedButton>(createAnother).onPressed!();
    for (
      var attempt = 0;
      attempt < 20 && maintenance.savedTitles.length < 2;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(maintenance.savedTitles, ['Clean seals', 'Check hoses']);
  });

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
    final completeAction = find.byKey(const ValueKey('inbox-complete-action'));
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

  testWidgets('Inbox marks already completed task notification', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final completedTask = _taskItem(
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
        overrides: _testOverrides(
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
    final dueTask = _taskItem(
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
        overrides: _testOverrides(
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
        overrides: _testOverrides(
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

  testWidgets(
    'unrelated notification preferences never request Android permission',
    (tester) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      final permissions = FakeAppPermissionGateway(
        states: {
          AppPermissionKind.location: AppPermissionState.denied,
          AppPermissionKind.notifications: AppPermissionState.denied,
          AppPermissionKind.exactAlarms: AppPermissionState.denied,
        },
      );
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _testOverrides(settings, permissionGateway: permissions),
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
        AppPermissionKind.exactAlarms: AppPermissionState.denied,
      },
      requestResults: {
        AppPermissionKind.notifications: AppPermissionState.denied,
      },
    );
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, permissionGateway: permissions),
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

  testWidgets('denied exact access preserves approximate timing preference', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    settings.notificationPreferencesValue = const NotificationPreferences(
      preferExactReminders: false,
    );
    final permissions = FakeAppPermissionGateway(
      states: {
        AppPermissionKind.location: AppPermissionState.denied,
        AppPermissionKind.notifications: AppPermissionState.granted,
        AppPermissionKind.exactAlarms: AppPermissionState.denied,
      },
      requestResults: {
        AppPermissionKind.exactAlarms: AppPermissionState.denied,
      },
    );
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _testOverrides(settings, permissionGateway: permissions),
        child: MaterialApp(
          theme: testLightTheme(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final exact = find.widgetWithText(
      SwitchListTile,
      'Precise reminder alarms',
    );
    await tester.scrollUntilVisible(
      exact,
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(exact);
    await tester.pumpAndSettle();

    expect(permissions.requests, [AppPermissionKind.exactAlarms]);
    expect(settings.notificationPreferencesValue.preferExactReminders, isFalse);
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
        overrides: _testOverrides(settings),
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

  testWidgets('backup screen renders polished status and toggles automation', (
    tester,
  ) async {
    final repository = FakeBackupRepository(
      state: BackupState(
        lastBackup: BackupStatus(
          successful: true,
          updatedAt: DateTime(2026, 7, 10, 14, 30),
          createdAt: DateTime(2026, 7, 10, 14, 30),
          trigger: BackupTrigger.manual,
          path: 'C:\\backups\\owntend-backup.zip',
          sizeBytes: 3 * 1024 * 1024,
          message: 'Backup verified and ready.',
        ),
      ),
    );

    await _pumpBackupScreen(tester, repository: repository);

    expect(find.text('Latest backup'), findsOneWidget);
    expect(find.text('Export diagnostics'), findsNothing);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Backup complete'), findsOneWidget);
    expect(find.text('Create backup'), findsWidgets);
    expect(find.text('Share latest backup'), findsOneWidget);
    expect(find.text('Automatic local backups'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(repository.automaticBackupsEnabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'backup button stays inline and never flickers for fast success',
    (tester) async {
      final repository = FakeBackupRepository(
        exportCompleter: Completer<String>()
          ..complete('C:\\backups\\owntend-backup.zip'),
      );

      await _pumpBackupScreen(tester, repository: repository);

      final button = find.widgetWithText(FilledButton, 'Create backup');
      final initialSize = tester.getSize(button);

      await tester.tap(button);
      await tester.pump();

      expect(repository.exportCount, 1);
      expect(find.text('Creating backup...'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Create backup'),
        findsOneWidget,
      );
      expect(tester.getSize(button), initialSize);

      await tester.pumpAndSettle();

      expect(find.text('Create backup'), findsWidgets);
      expect(find.text('Creating backup...'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('owntend-backup.zip'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('backup button shows inline loading after the delay', (
    tester,
  ) async {
    final completer = Completer<String>();
    final repository = FakeBackupRepository(exportCompleter: completer);

    await _pumpBackupScreen(tester, repository: repository);

    final button = find.widgetWithText(FilledButton, 'Create backup');
    final initialSize = tester.getSize(button);

    await tester.tap(button);
    await tester.pump();
    expect(repository.exportCount, 1);
    expect(find.text('Creating backup...'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getSize(button), initialSize);

    await tester.pump(const Duration(milliseconds: 401));
    expect(find.text('Creating backup...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(button), initialSize);

    completer.complete('C:\\backups\\owntend-backup.zip');
    await tester.pumpAndSettle();

    expect(find.text('Creating backup...'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('owntend-backup.zip'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('backup button ignores repeated taps while running', (
    tester,
  ) async {
    final completer = Completer<String>();
    final repository = FakeBackupRepository(exportCompleter: completer);

    await _pumpBackupScreen(tester, repository: repository);

    final button = find.widgetWithText(FilledButton, 'Create backup');

    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();

    expect(repository.exportCount, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    completer.complete('C:\\backups\\owntend-backup.zip');
    await tester.pumpAndSettle();

    expect(find.textContaining('owntend-backup.zip'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('backup button resets after failure', (tester) async {
    final repository = FakeBackupRepository(
      exportCompleter: Completer<String>()
        ..complete('C:\\backups\\owntend-backup.zip'),
      exportError: StateError('disk full'),
    );

    await _pumpBackupScreen(tester, repository: repository);

    final button = find.widgetWithText(FilledButton, 'Create backup');
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('Creating backup...'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Create backup'), findsOneWidget);
    expect(find.textContaining('could not be completed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('backup button does not update after disposal', (tester) async {
    final completer = Completer<String>();
    final repository = FakeBackupRepository(exportCompleter: completer);

    await _pumpBackupScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    completer.complete('C:\\backups\\owntend-backup.zip');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'backup screen previews a selected zip and opens restore dialog',
    (tester) async {
      final repository = FakeBackupRepository(
        preview: BackupPreview(
          path: 'C:\\backups\\selected.zip',
          createdAt: DateTime(2026, 7, 11, 8, 15),
          formatVersion: 2,
          schemaVersion: 12,
          backupSizeBytes: 2 * 1024 * 1024,
          databaseSizeBytes: 640 * 1024,
          fileCount: 7,
          counts: const {
            'maintenance_plans': 4,
            'assets': 3,
            'maintenance_records': 9,
            'notifications': 2,
          },
          includedData: const ['tasks', 'items', 'history'],
          excludedData: const [
            'Android scheduled alarm handles are recreated from restored tasks and settings',
          ],
          warnings: const ['This backup was created on another device.'],
        ),
      );
      final picker = FakeFilePicker('C:\\backups\\selected.zip');
      final previousPicker = _installFilePicker(picker);
      addTearDown(() {
        if (previousPicker != null) {
          FilePickerPlatform.instance = previousPicker;
        }
      });

      await _pumpBackupScreen(
        tester,
        repository: repository,
        sync: FakeCloudSyncRepository(
          const SyncStatus(phase: SyncPhase.ready, enabled: true),
        ),
      );

      await tester.tap(find.text('Choose backup ZIP'));
      await tester.pumpAndSettle();

      expect(picker.pickCount, 1);
      expect(repository.inspectedPath, 'C:\\backups\\selected.zip');
      expect(find.textContaining('Backup from'), findsOneWidget);
      expect(find.text('Tasks 4'), findsOneWidget);
      expect(find.text('Items 3'), findsOneWidget);
      expect(find.text('History 9'), findsOneWidget);
      expect(
        find.text(
          'This backup contains a compatibility warning. Review it before restoring.',
        ),
        findsOneWidget,
      );

      final restoreButton = find.widgetWithText(
        FilledButton,
        'Restore this backup',
      );
      await tester.ensureVisible(restoreButton);
      await tester.pumpAndSettle();
      await tester.tap(restoreButton);
      await tester.pumpAndSettle();

      expect(find.text('Restore this backup?'), findsOneWidget);
      expect(find.text('Restore and update cloud backup'), findsOneWidget);
      expect(
        find.text('Restore locally and pause cloud backup'),
        findsOneWidget,
      );
      expect(
        find.textContaining('A safety copy is created before restore starts'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('backup screen smokes in the permanent light narrow layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpBackupScreen(
      tester,
      repository: FakeBackupRepository(),
      theme: testLightTheme(),
    );

    expect(find.text('Backup & Restore'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Restore from a backup'), 240);
    expect(find.text('Restore from a backup'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
      initialHydrationProgress: _testHydrationProgress(
        InitialHydrationStage.restoringCloudData,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(settings),
          cloudSyncRepositoryProvider.overrideWithValue(
            _blockingCloudSyncRepository(
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
    _expectContainedHero(tester, const ValueKey('restore-hero-illustration'));
    _expectHeroBehind(
      tester,
      const ValueKey('restore-hero-illustration'),
      find.text('Securely bringing back your tasks,\nroutines, and reminders.'),
    );
    await expectLater(
      find.byKey(const ValueKey('initial-cloud-hydration')),
      matchesGoldenFile('goldens/visual_restore_applying_640.png'),
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
      initialHydrationProgress: _testHydrationProgress(
        InitialHydrationStage.checkingLatestUpdates,
        completedUnits: 78,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(settings),
          cloudSyncRepositoryProvider.overrideWithValue(
            _blockingCloudSyncRepository(
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
    _expectContainedHero(tester, const ValueKey('restore-hero-illustration'));
    expect(tester.takeException(), isNull);
    await expectLater(
      hydration,
      matchesGoldenFile('goldens/visual_restore_wide.png'),
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
        initialHydrationProgress: _testHydrationProgress(
          InitialHydrationStage.restoringCloudData,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._testOverrides(settings),
            cloudSyncRepositoryProvider.overrideWithValue(
              _blockingCloudSyncRepository(
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

      _expectContainedHero(tester, const ValueKey('restore-hero-illustration'));
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
      initialHydrationProgress: _testHydrationProgress(
        InitialHydrationStage.restoringCloudData,
        completedUnits: 24,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(settings),
          cloudSyncRepositoryProvider.overrideWithValue(
            _blockingCloudSyncRepository(
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
      tester.getBottomRight(find.byKey(const ValueKey('restore-tip-card'))).dy,
      lessThanOrEqualTo(640),
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      hydration,
      matchesGoldenFile('goldens/visual_restore_short_scaled.png'),
    );
    restoreEnable.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('compact verified-cache failure exposes every recovery action', (
    tester,
  ) async {
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
      boundUserId: _signedInTestSession.userId,
      migrationState: 'active',
    );
    await store.recordSyncSuccess(DateTime.utc(2026, 7, 26, 8));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._testOverrides(settings),
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

    expect(find.byKey(const ValueKey('restore-scroll-view')), findsOneWidget);
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
  });

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
      initialHydrationProgress: _testHydrationProgress(
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
          ..._testOverrides(settings),
          cloudSyncRepositoryProvider.overrideWithValue(
            FakeCloudSyncRepository(status, enableFuture: failedEnable.future),
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

  testWidgets(
    'point shortage dialog remains visible when rewards are unavailable',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            monetizationConfigProvider.overrideWithValue(
              const AsyncData(MonetizationConfig.failClosed()),
            ),
            pointWalletProvider.overrideWithValue(
              AsyncData(
                PointWallet(
                  balance: 0,
                  timeZone: 'Asia/Baghdad',
                  updatedAt: DateTime.utc(2026, 8, 9),
                ),
              ),
            ),
            monetizationRepositoryProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: testLightTheme(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => FilledButton(
                  onPressed: () => showPointShortageDialog(
                    context,
                    ref,
                    attemptedAction: 'task',
                  ),
                  child: const Text('Create task'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Create task'));
      await tester.pumpAndSettle();
      expect(find.text('You need 1 point'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('point-shortage-watch-ad')));
      await tester.pump();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('Point rewards are temporarily unavailable.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('point-shortage-status')),
        findsOneWidget,
      );
      expect(find.text('Keep editing'), findsOneWidget);
    },
  );
}

void _expectContainedHero(WidgetTester tester, ValueKey<String> key) {
  final hero = find.byKey(key);
  expect(hero, findsOneWidget);

  final topLeft = tester.getTopLeft(hero);
  final heroSize = tester.getSize(hero);
  final viewportSize = tester.view.physicalSize / tester.view.devicePixelRatio;

  expect(topLeft.dx, moreOrLessEquals(0));
  expect(topLeft.dy, moreOrLessEquals(0));
  expect(heroSize.width, moreOrLessEquals(viewportSize.width));
  expect(heroSize.height, moreOrLessEquals(viewportSize.height));
  final image = tester.widget<Image>(
    find.descendant(of: hero, matching: find.byType(Image)),
  );
  expect(image.fit, BoxFit.contain);
}

void _expectHeroBehind(
  WidgetTester tester,
  ValueKey<String> key,
  Finder above,
) {
  final hero = find.byKey(key);
  expect(hero, findsOneWidget);
  expect(above, findsOneWidget);

  expect(tester.getTopLeft(hero).dy, lessThan(tester.getBottomLeft(above).dy));
}

Future<void> _pumpBackupScreen(
  WidgetTester tester, {
  required FakeBackupRepository repository,
  FakeCloudSyncRepository? sync,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backupRepositoryProvider.overrideWithValue(repository),
        cloudSyncRepositoryProvider.overrideWithValue(
          sync ?? FakeCloudSyncRepository(const SyncStatus.disabled()),
        ),
        notificationAutoStartProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        theme: theme ?? testLightTheme(),
        home: const BackupScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

FilePickerPlatform? _installFilePicker(FilePickerPlatform picker) {
  FilePickerPlatform? previous;
  try {
    previous = FilePickerPlatform.instance;
  } catch (_) {
    previous = null;
  }
  FilePickerPlatform.instance = picker;
  return previous;
}

List<Override> _testOverrides(
  FakeSettingsRepository settings, {
  List<TaskItem> tasks = const [],
  List<Asset>? assets,
  List<Room>? rooms,
  Stream<List<TaskItem>>? taskStream,
  Stream<List<Asset>>? assetStream,
  Stream<List<Room>>? roomStream,
  WeatherSnapshot? weather,
  BackupState? backupState,
  List<InboxNotification> notifications = const [],
  int unreadNotifications = 0,
  Map<String, List<MaintenanceRecord>> taskRecords = const {},
  AuthSession? session = _signedInTestSession,
  bool includeAuthOverrides = true,
  AsyncValue<AppProfile>? profileState,
  FakeNotificationScheduler? notificationScheduler,
  MaintenanceRepository? maintenanceRepository,
  AssetRepository? assetRepository,
  WeatherRepository? weatherRepository,
  AppPermissionGateway? permissionGateway,
  PermissionEducationRepository? permissionEducationRepository,
}) {
  final now = DateTime(2026);
  final streak = StreakState(currentStreak: 0, bestStreak: 0, updatedAt: now);
  final things = assets ?? _things(now);
  final homeRooms = rooms ?? _rooms(now);
  final recordOverrides = <String, List<MaintenanceRecord>>{};
  for (final task in tasks) {
    recordOverrides[task.plan.id] = taskRecords[task.plan.id] ?? const [];
  }
  for (final notification in notifications) {
    final planId = notification.planId;
    if (planId != null) {
      recordOverrides.putIfAbsent(
        planId,
        () => taskRecords[planId] ?? const [],
      );
    }
  }
  for (final entry in taskRecords.entries) {
    recordOverrides[entry.key] = entry.value;
  }
  final effectiveGateway =
      permissionGateway ??
      FakeAppPermissionGateway(
        states: {
          AppPermissionKind.location: AppPermissionState.granted,
          AppPermissionKind.notifications: AppPermissionState.granted,
          AppPermissionKind.exactAlarms: AppPermissionState.granted,
        },
      );
  final defaultDeviceState = settings.permissionEducationSeenValue
      ? PermissionEducationDeviceState(completedAt: DateTime(2026))
      : const PermissionEducationDeviceState();
  return [
    notificationAutoStartProvider.overrideWithValue(false),
    backupAutoStartProvider.overrideWithValue(false),
    if (includeAuthOverrides) ...[
      authSessionProvider.overrideWithValue(AsyncData(session)),
      authStateProvider.overrideWithValue(
        AsyncData(
          AuthStateChange(
            event: AuthEventType.initialSession,
            session: session,
          ),
        ),
      ),
    ],
    startupThemeSettingsProvider.overrideWithValue(
      ThemeStartupSettings(
        preference: settings.themePreferenceValue,
        timeOfDayEnabled: settings.timeOfDayThemeEnabledValue,
      ),
    ),
    notificationSchedulerProvider.overrideWithValue(
      notificationScheduler ?? FakeNotificationScheduler(),
    ),
    permissionCoordinatorProvider.overrideWithValue(effectiveGateway),
    devicePermissionGatewayProvider.overrideWithValue(
      AppPermissionGatewayDeviceAdapter(effectiveGateway),
    ),
    permissionEducationRepositoryProvider.overrideWithValue(
      permissionEducationRepository ??
          FakePermissionEducationRepository(initialState: defaultDeviceState),
    ),
    weatherRepositoryProvider.overrideWithValue(
      weatherRepository ?? CountingWeatherRepository(),
    ),
    settingsRepositoryProvider.overrideWithValue(settings),
    maintenanceRepositoryProvider.overrideWithValue(
      maintenanceRepository ?? FakeMaintenanceRepository(initialTasks: tasks),
    ),
    assetRepositoryProvider.overrideWithValue(
      assetRepository ??
          StartupAssetRepository(assets: things, rooms: homeRooms),
    ),
    profileProvider.overrideWithValue(
      profileState ?? AsyncData(settings.profileValue),
    ),
    homeLocationProvider.overrideWithValue(
      AsyncData(settings.homeLocationValue),
    ),
    weatherProvider.overrideWithValue(AsyncData(weather)),
    backupStateProvider.overrideWithValue(
      AsyncData(backupState ?? const BackupState()),
    ),
    notificationsProvider.overrideWithValue(AsyncData(notifications)),
    unreadNotificationsProvider.overrideWithValue(
      AsyncData(unreadNotifications),
    ),
    notificationPreferencesProvider.overrideWithValue(
      AsyncData(settings.notificationPreferencesValue),
    ),
    notificationPermissionStateProvider.overrideWithValue(
      const AsyncData(
        NotificationPermissionState(
          notificationsEnabled: true,
          canScheduleExact: true,
        ),
      ),
    ),
    streakRefreshProvider.overrideWithValue(AsyncData(streak)),
    taskStream == null
        ? tasksProvider.overrideWithValue(AsyncData(tasks))
        : tasksProvider.overrideWith((ref) => _seededStream(tasks, taskStream)),
    for (final task in tasks) ...[
      taskDetailProvider(task.plan.id).overrideWithValue(AsyncData(task)),
    ],
    for (final entry in recordOverrides.entries)
      taskRecordsProvider(entry.key).overrideWithValue(AsyncData(entry.value)),
    areasProvider.overrideWithValue(AsyncData(_areas(now))),
    roomStream == null
        ? roomsProvider.overrideWithValue(AsyncData(homeRooms))
        : roomsProvider.overrideWith(
            (ref) => _seededStream(homeRooms, roomStream),
          ),
    categoriesProvider.overrideWithValue(AsyncData(_categories(now))),
    assetStream == null
        ? assetsProvider.overrideWithValue(AsyncData(things))
        : assetsProvider.overrideWith(
            (ref) => _seededStream(things, assetStream),
          ),
    roomAssetsProvider('room_kitchen').overrideWithValue(AsyncData(things)),
    for (final thing in things) ...[
      assetDetailProvider(thing.id).overrideWithValue(AsyncData(thing)),
      assetTasksProvider(thing.id).overrideWithValue(
        AsyncData(tasks.where((task) => task.asset.id == thing.id).toList()),
      ),
      assetSavedTasksProvider(thing.id).overrideWithValue(
        AsyncData(tasks.where((task) => task.asset.id == thing.id).toList()),
      ),
      assetTagsProvider(thing.id).overrideWithValue(const AsyncData([])),
      assetPhotosProvider(thing.id).overrideWithValue(const AsyncData([])),
      assetRecordsProvider(thing.id).overrideWithValue(
        AsyncData(
          tasks
              .where((task) => task.asset.id == thing.id)
              .expand(
                (task) =>
                    recordOverrides[task.plan.id] ??
                    const <MaintenanceRecord>[],
              )
              .toList(),
        ),
      ),
    ],
    dashboardProvider.overrideWithValue(
      AsyncData(
        DashboardSummary(
          todayTasks: tasks
              .where((task) => task.status == TaskStatus.dueToday)
              .length,
          upcomingTasks: tasks
              .where((task) => task.status == TaskStatus.upcoming)
              .length,
          overdueTasks: tasks
              .where((task) => task.status == TaskStatus.overdue)
              .length,
          health: const HealthScoreBreakdown(
            score: 100,
            groupScores: {},
            activeWeights: {},
          ),
          streak: streak,
          completionRate: tasks.isEmpty ? 1 : 0,
          completedThisMonth: 0,
        ),
      ),
    ),
    statisticsProvider.overrideWithValue(
      const AsyncData(
        StatisticsSummary(
          completionRate: 1,
          overdueRate: 0,
          completedByMonth: {},
          taskDistribution: {},
        ),
      ),
    ),
  ];
}

Stream<T> _seededStream<T>(T initialValue, Stream<T> updates) {
  return Stream<T>.multi((controller) {
    controller.add(initialValue);
    final subscription = updates.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  });
}

WeatherSnapshot _weather({
  double temperature = 26,
  double apparentTemperature = 24,
  double windSpeed = 12,
  int humidity = 56,
  String locationLabel = 'Baghdad',
}) {
  final now = DateTime(2026, 6, 18, 9);
  return WeatherSnapshot(
    location: HomeLocation(
      label: locationLabel,
      latitude: 33.3152,
      longitude: 44.3661,
      timezone: 'Asia/Baghdad',
    ),
    updatedAt: now,
    temperature: temperature,
    apparentTemperature: apparentTemperature,
    weatherCode: 0,
    windSpeed: windSpeed,
    precipitation: 0,
    humidity: humidity,
    forecast: [
      WeatherForecastDay(
        date: now,
        weatherCode: 0,
        temperatureMax: 30,
        temperatureMin: 20,
        precipitationProbabilityMax: 0,
        windSpeedMax: 16,
      ),
    ],
  );
}

List<Area> _areas(DateTime now) {
  return [
    Area(
      id: 'area_first_floor',
      name: 'Main Level',
      kind: AreaKind.indoor,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    ),
    Area(
      id: 'area_second_floor',
      name: 'Upper Level',
      kind: AreaKind.indoor,
      sortOrder: 1,
      createdAt: now,
      updatedAt: now,
    ),
    Area(
      id: 'area_outdoor_garden',
      name: 'Garden',
      kind: AreaKind.outdoor,
      sortOrder: 2,
      createdAt: now,
      updatedAt: now,
    ),
  ];
}

List<Room> _rooms(DateTime now) {
  return [
    Room(
      id: 'room_general',
      areaId: 'area_first_floor',
      name: 'General',
      roomType: RoomType.other,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    ),
    Room(
      id: 'room_kitchen',
      areaId: 'area_first_floor',
      name: 'Kitchen',
      roomType: RoomType.kitchen,
      sortOrder: 1,
      createdAt: now,
      updatedAt: now,
    ),
    Room(
      id: 'room_garden',
      areaId: 'area_outdoor_garden',
      name: 'Garden',
      roomType: RoomType.garden,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    ),
  ];
}

TaskItem _taskItem(
  DateTime dueDate, {
  String id = 'plan_feed_fish',
  String title = 'Feed the fish',
  TaskStatus status = TaskStatus.dueToday,
  bool preserveDueTime = false,
  bool isEnabled = true,
}) {
  final now = DateTime(2026);
  final category = Category(
    id: 'category_pets',
    name: 'Pets',
    healthGroup: HealthGroup.pets,
    iconName: 'pets',
    createdAt: now,
    updatedAt: now,
  );
  final asset = Asset(
    id: 'asset_fish',
    name: 'Fish',
    assetType: AssetType.pet,
    categoryId: category.id,
    roomId: 'room_kitchen',
    createdAt: now,
    updatedAt: now,
  );
  final room = Room(
    id: 'room_kitchen',
    areaId: 'area_first_floor',
    name: 'Kitchen',
    roomType: RoomType.kitchen,
    createdAt: now,
    updatedAt: now,
  );
  return TaskItem(
    plan: MaintenancePlan(
      id: id,
      assetId: asset.id,
      title: title,
      recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days),
      priority: PriorityLevel.medium,
      nextDueDate: preserveDueTime ? dueDate : DateUtils.dateOnly(dueDate),
      isEnabled: isEnabled,
      healthGroup: HealthGroup.pets,
      createdAt: now,
      updatedAt: now,
    ),
    asset: asset,
    category: category,
    room: room,
    status: status,
  );
}

List<Category> _categories(DateTime now) {
  return [
    Category(
      id: 'category_appliances',
      name: 'Appliances',
      healthGroup: HealthGroup.appliances,
      iconName: 'kitchen',
      createdAt: now,
      updatedAt: now,
    ),
    Category(
      id: 'category_plants',
      name: 'Plants',
      healthGroup: HealthGroup.plants,
      iconName: 'yard',
      createdAt: now,
      updatedAt: now,
    ),
    Category(
      id: 'category_pets',
      name: 'Pets',
      healthGroup: HealthGroup.pets,
      iconName: 'pets',
      createdAt: now,
      updatedAt: now,
    ),
    Category(
      id: 'category_safety',
      name: 'Safety',
      healthGroup: HealthGroup.safety,
      iconName: 'shield',
      createdAt: now,
      updatedAt: now,
    ),
    Category(
      id: 'category_general',
      name: 'General',
      healthGroup: HealthGroup.other,
      iconName: 'home',
      createdAt: now,
      updatedAt: now,
    ),
  ];
}

List<Asset> _things(DateTime now) {
  return [
    _thing('asset_dishwasher', 'Dishwasher', AssetType.device, now: now),
    _thing('asset_basil', 'Basil', AssetType.plant, now: now),
  ];
}

Asset _thing(String id, String name, AssetType type, {DateTime? now}) {
  final timestamp = now ?? DateTime(2026);
  return Asset(
    id: id,
    name: name,
    assetType: type,
    categoryId: switch (type) {
      AssetType.device => 'category_appliances',
      AssetType.pet => 'category_pets',
      AssetType.plant => 'category_plants',
      AssetType.safety => 'category_safety',
      AssetType.general => 'category_general',
    },
    roomId: 'room_kitchen',
    placement: 'North wall',
    createdAt: timestamp,
    updatedAt: timestamp,
    deviceDetails: type == AssetType.device
        ? const DeviceDetails(brand: 'Bosch')
        : null,
    petDetails: type == AssetType.pet ? const PetDetails(species: 'Cat') : null,
    plantDetails: type == AssetType.plant
        ? const PlantDetails(sunlight: Sunlight.medium)
        : null,
    safetyDetails: type == AssetType.safety
        ? const SafetyDetails(safetyType: 'Detector')
        : null,
  );
}

class FakeBackupRepository implements BackupRepository {
  FakeBackupRepository({
    BackupState? state,
    BackupPreview? preview,
    this.exportDelay,
    this.exportError,
    this.exportCompleter,
  }) : state = state ?? const BackupState(),
       preview = preview ?? _defaultBackupPreview;

  BackupState state;
  BackupPreview preview;
  String? inspectedPath;
  bool? automaticBackupsEnabled;
  var exportCount = 0;
  var restoreCount = 0;
  final Duration? exportDelay;
  final Object? exportError;
  final Completer<String>? exportCompleter;

  @override
  Future<String> exportBackup({
    BackupTrigger trigger = BackupTrigger.manual,
  }) async {
    exportCount++;
    if (exportCompleter != null) {
      final path = await exportCompleter!.future;
      if (exportError != null) {
        throw exportError!;
      }
      state = BackupState(
        lastBackup: BackupStatus(
          successful: true,
          updatedAt: DateTime(2026, 7, 12, 9),
          createdAt: DateTime(2026, 7, 12, 9),
          trigger: trigger,
          path: path,
          sizeBytes: 1024,
        ),
        automaticBackupsEnabled: state.automaticBackupsEnabled,
      );
      return state.lastBackup!.path!;
    }
    if (exportDelay != null) {
      await Future<void>.delayed(exportDelay!);
    }
    if (exportError != null) {
      throw exportError!;
    }
    state = BackupState(
      lastBackup: BackupStatus(
        successful: true,
        updatedAt: DateTime(2026, 7, 12, 9),
        createdAt: DateTime(2026, 7, 12, 9),
        trigger: trigger,
        path: 'C:\\backups\\owntend-backup.zip',
        sizeBytes: 1024,
      ),
      automaticBackupsEnabled: state.automaticBackupsEnabled,
    );
    return state.lastBackup!.path!;
  }

  @override
  Future<String?> exportAutomaticBackupIfDue() async => null;

  @override
  Future<BackupState> backupState() async => state;

  @override
  Future<void> setAutomaticBackupsEnabled(bool enabled) async {
    automaticBackupsEnabled = enabled;
    state = BackupState(
      lastBackup: state.lastBackup,
      automaticBackupsEnabled: enabled,
    );
  }

  @override
  Future<BackupPreview> inspectBackup(String zipPath) async {
    inspectedPath = zipPath;
    return preview;
  }

  @override
  Future<void> restoreBackup(String zipPath) async {
    restoreCount++;
  }
}

class FakeCloudSyncRepository implements CloudSyncRepository {
  FakeCloudSyncRepository(this.currentStatus, {this.enableFuture});

  SyncStatus currentStatus;
  Future<void>? enableFuture;
  var enableCount = 0;
  var disableCount = 0;
  var fullReconcileCount = 0;
  var syncNowCount = 0;

  @override
  Future<void> disable() async {
    disableCount++;
    currentStatus = const SyncStatus.disabled();
  }

  @override
  Future<void> enable() {
    enableCount++;
    return enableFuture ?? Future<void>.value();
  }

  @override
  Future<void> fullReconcile() async {
    fullReconcileCount++;
  }

  @override
  Future<void> retry() async {}

  @override
  Future<SyncStatus> status() async => currentStatus;

  @override
  Future<void> syncNow() async {
    syncNowCount++;
  }

  @override
  Future<void> unlink() async {}

  @override
  Stream<SyncStatus> watchStatus() => Stream.value(currentStatus);
}

final class FakePlatformFile extends PlatformFile {
  FakePlatformFile(this._path, {this.fileSize = 2048});

  final String _path;
  final int fileSize;

  @override
  String get name => _path.split(RegExp(r'[\\/]')).last;

  @override
  Uri get uri => Uri.file(_path);

  @override
  String? get path => _path;

  @override
  XFile get xFile => XFile(_path);

  @override
  Future<int> length() async => fileSize;

  @override
  Future<Uint8List> readAsBytes() async => Uint8List(0);

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(Uint8List(0));
}

class FakeFilePicker extends FilePickerPlatform {
  FakeFilePicker(this.path);

  final String? path;
  var pickCount = 0;

  @override
  Future<List<PlatformFile>> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic Function(FilePickerStatus)? onFileLoading,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    int compressionQuality = 0,
    String? dialogTitle,
    String? initialDirectory,
    bool lockParentWindow = false,
    bool readSequential = false,
    AndroidOptions androidOptions = const AndroidOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
  }) async {
    pickCount++;
    if (path == null) {
      return const [];
    }
    return [FakePlatformFile(path!)];
  }
}

final _defaultBackupPreview = BackupPreview(
  path: 'C:\\backups\\selected.zip',
  createdAt: DateTime(2026, 7, 12, 9),
  formatVersion: 2,
  schemaVersion: 12,
  backupSizeBytes: 1024,
  databaseSizeBytes: 512,
  fileCount: 1,
  counts: const {'maintenance_plans': 1, 'assets': 1, 'maintenance_records': 1},
  includedData: const ['tasks'],
  excludedData: const [
    'Android scheduled alarm handles are recreated from restored tasks and settings',
  ],
);

class FakeAppPermissionGateway implements AppPermissionGateway {
  FakeAppPermissionGateway({
    Map<AppPermissionKind, AppPermissionState>? states,
    Map<AppPermissionKind, AppPermissionState>? requestResults,
  }) : states = states ?? <AppPermissionKind, AppPermissionState>{},
       requestResults =
           requestResults ?? <AppPermissionKind, AppPermissionState>{};

  final Map<AppPermissionKind, AppPermissionState> states;
  final Map<AppPermissionKind, AppPermissionState> requestResults;
  final List<AppPermissionKind> requests = [];
  final List<AppPermissionKind> prompted = [];
  var openAppSettingsCount = 0;
  var openLocationSettingsCount = 0;

  @override
  Future<AppPermissionState> check(AppPermissionKind kind) async =>
      states[kind] ?? AppPermissionState.unavailable;

  @override
  Future<AppPermissionState> request(AppPermissionKind kind) async {
    requests.add(kind);
    if (!prompted.contains(kind)) {
      prompted.add(kind);
    }
    final result =
        requestResults[kind] ?? states[kind] ?? AppPermissionState.denied;
    states[kind] = result;
    return result;
  }

  @override
  Future<bool> wasPrompted(AppPermissionKind kind) async =>
      prompted.contains(kind);

  @override
  Future<void> markPrompted(AppPermissionKind kind) async {
    prompted.add(kind);
  }

  @override
  Future<bool> openAppPermissionSettings() async {
    openAppSettingsCount++;
    return true;
  }

  @override
  Future<bool> openLocationServiceSettings() async {
    openLocationSettingsCount++;
    return true;
  }
}

class AppPermissionGatewayDeviceAdapter implements DevicePermissionGateway {
  AppPermissionGatewayDeviceAdapter(this.gateway);
  final AppPermissionGateway gateway;

  AppPermissionKind _map(PermissionCapability cap) => switch (cap) {
    PermissionCapability.deviceLocation => AppPermissionKind.location,
    PermissionCapability.notifications => AppPermissionKind.notifications,
    PermissionCapability.exactReminderTiming => AppPermissionKind.exactAlarms,
  };

  @override
  Future<AppPermissionState> check(PermissionCapability capability) =>
      gateway.check(_map(capability));

  @override
  Future<DeviceLocationAccessState> checkLocationAccess() async {
    final state = await gateway.check(AppPermissionKind.location);
    return DeviceLocationAccessState(
      permissionState: state == AppPermissionState.serviceDisabled
          ? AppPermissionState.denied
          : state,
      serviceEnabled: state == AppPermissionState.unavailable
          ? null
          : state != AppPermissionState.serviceDisabled,
    );
  }

  @override
  Future<AppPermissionState> request(PermissionCapability capability) =>
      gateway.request(_map(capability));

  @override
  Future<bool> openSettings(PermissionCapability capability) async {
    final kind = _map(capability);
    if (kind == AppPermissionKind.location) {
      await gateway.openLocationServiceSettings();
    } else {
      await gateway.openAppPermissionSettings();
    }
    return true;
  }
}

class FakePermissionEducationRepository
    implements PermissionEducationRepository {
  FakePermissionEducationRepository({
    PermissionEducationDeviceState? initialState,
  }) : deviceState = initialState ?? const PermissionEducationDeviceState();

  PermissionEducationDeviceState deviceState;

  @override
  Future<PermissionEducationDeviceState> loadDeviceState() async {
    return deviceState;
  }

  @override
  Future<void> saveDeviceState(PermissionEducationDeviceState state) async {
    deviceState = state;
  }
}

class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository({
    required this.onboardingCompletedValue,
    this.permissionEducationSeenValue = true,
    this.themePreferenceValue = ThemePreference.system,
    this.timeOfDayThemeEnabledValue = false,
    this.appLanguageValue = AppLanguage.en,
    this.appLanguageExplicitValue = false,
    this.profileFailure,
  });

  final _appLanguageController = StreamController<AppLanguage>.broadcast();
  final _appLocalePreferenceController =
      StreamController<AppLocalePreference>.broadcast();
  final _themeController = StreamController<ThemePreference>.broadcast();
  final _timeOfDayThemeController = StreamController<bool>.broadcast();
  final _onboardingController = StreamController<bool>.broadcast();
  final _permissionEducationController = StreamController<bool>.broadcast();
  final _profileController = StreamController<AppProfile>.broadcast();
  final _notificationPreferencesController =
      StreamController<NotificationPreferences>.broadcast();

  AppLanguage appLanguageValue;
  bool appLanguageExplicitValue;
  DateTime appLanguageUpdatedAt = DateTime.fromMillisecondsSinceEpoch(0);
  ThemePreference themePreferenceValue;
  bool timeOfDayThemeEnabledValue;
  bool onboardingCompletedValue;
  bool permissionEducationSeenValue;
  AppProfile profileValue = const AppProfile();
  HomeLocation? homeLocationValue;
  NotificationPreferences notificationPreferencesValue =
      const NotificationPreferences();
  final Object? profileFailure;
  int notificationSaveCount = 0;

  @override
  Future<AppLanguage> appLanguage() async => appLanguageValue;

  @override
  Future<void> setAppLanguage(AppLanguage language) async {
    await setAppLocalePreference(language);
  }

  @override
  Future<AppLocalePreference> appLocalePreference() async =>
      AppLocalePreference(
        language: appLanguageValue,
        isExplicit: appLanguageExplicitValue,
        updatedAt: appLanguageUpdatedAt,
      );

  @override
  Future<void> setAppLocalePreference(AppLanguage language) async {
    appLanguageValue = language;
    appLanguageExplicitValue = true;
    appLanguageUpdatedAt = DateTime.now();
    _appLanguageController.add(language);
    _appLocalePreferenceController.add(await appLocalePreference());
  }

  @override
  Stream<AppLanguage> watchAppLanguage() async* {
    yield appLanguageValue;
    yield* _appLanguageController.stream;
  }

  @override
  Stream<AppLocalePreference> watchAppLocalePreference() async* {
    yield await appLocalePreference();
    yield* _appLocalePreferenceController.stream;
  }

  @override
  Future<ThemePreference> themePreference() async => themePreferenceValue;

  @override
  Future<void> setThemePreference(ThemePreference preference) async {
    themePreferenceValue = preference;
    _themeController.add(preference);
  }

  @override
  Stream<ThemePreference> watchThemePreference() async* {
    yield themePreferenceValue;
    yield* _themeController.stream;
  }

  @override
  Future<bool> timeOfDayThemeEnabled() async => timeOfDayThemeEnabledValue;

  @override
  Future<void> setTimeOfDayThemeEnabled(bool enabled) async {
    timeOfDayThemeEnabledValue = enabled;
    _timeOfDayThemeController.add(enabled);
  }

  @override
  Stream<bool> watchTimeOfDayThemeEnabled() async* {
    yield timeOfDayThemeEnabledValue;
    yield* _timeOfDayThemeController.stream;
  }

  @override
  Future<bool> onboardingCompleted() async => onboardingCompletedValue;

  @override
  Future<void> setOnboardingCompleted(bool completed) async {
    onboardingCompletedValue = completed;
    _onboardingController.add(completed);
  }

  @override
  Stream<bool> watchOnboardingCompleted() async* {
    yield onboardingCompletedValue;
    yield* _onboardingController.stream;
  }

  @override
  Future<bool> permissionEducationSeen() async => permissionEducationSeenValue;

  @override
  Future<void> setPermissionEducationSeen(bool seen) async {
    permissionEducationSeenValue = seen;
    _permissionEducationController.add(seen);
  }

  @override
  Stream<bool> watchPermissionEducationSeen() async* {
    yield permissionEducationSeenValue;
    yield* _permissionEducationController.stream;
  }

  @override
  Future<AppProfile> profile() async {
    if (profileFailure case final failure?) throw failure;
    return profileValue;
  }

  @override
  Stream<AppProfile> watchProfile() async* {
    yield profileValue;
    yield* _profileController.stream;
  }

  @override
  Future<void> setProfile({String? nickname}) async {
    profileValue = AppProfile(
      nickname: nickname?.trim().isEmpty ?? true ? null : nickname!.trim(),
      displayName: profileValue.displayName,
      avatarPath: profileValue.avatarPath,
    );
    _profileController.add(profileValue);
  }

  @override
  Future<HomeLocation?> homeLocation() async => homeLocationValue;

  @override
  Stream<HomeLocation?> watchHomeLocation() async* {
    yield homeLocationValue;
  }

  @override
  Future<void> setHomeLocation(HomeLocation? location) async {
    homeLocationValue = location;
  }

  @override
  Future<NotificationPreferences> notificationPreferences() async =>
      notificationPreferencesValue;

  @override
  Stream<NotificationPreferences> watchNotificationPreferences() async* {
    yield notificationPreferencesValue;
    yield* _notificationPreferencesController.stream;
  }

  @override
  Future<void> setNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    notificationSaveCount++;
    notificationPreferencesValue = preferences;
    _notificationPreferencesController.add(preferences);
  }

  @override
  Future<void> mergeNotificationPreferences({
    required NotificationPreferences baseline,
    required NotificationPreferences desired,
  }) async {
    await setNotificationPreferences(desired);
  }

  Future<void> close() async {
    await _appLanguageController.close();
    await _appLocalePreferenceController.close();
    await _themeController.close();
    await _timeOfDayThemeController.close();
    await _onboardingController.close();
    await _permissionEducationController.close();
    await _profileController.close();
    await _notificationPreferencesController.close();
  }
}

class FakeNotificationScheduler implements NotificationScheduler {
  int refreshCount = 0;
  int permissionRequestCount = 0;
  int clearCount = 0;
  final snoozed = <String, Duration>{};
  final cancelled = <String>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationPermissionState> permissionState() async {
    return const NotificationPermissionState(
      notificationsEnabled: true,
      canScheduleExact: true,
    );
  }

  @override
  Future<void> refreshSchedules() async {
    refreshCount++;
  }

  @override
  Future<void> clearAllScheduledReminders() async {
    clearCount++;
    cancelled.clear();
    snoozed.clear();
  }

  @override
  Future<void> cancelPlanReminders(String planId) async {
    cancelled.add(planId);
    snoozed.remove(planId);
  }

  @override
  Future<void> requestPermissions({bool exactAlarms = false}) async {
    permissionRequestCount++;
  }

  @override
  Future<void> sendTestReminder() async {}

  @override
  Future<void> snoozePlan(String planId, Duration duration) async {
    snoozed[planId] = duration;
  }
}

class StartupAssetRepository implements AssetRepository {
  StartupAssetRepository({required this.assets, required this.rooms});

  final List<Asset> assets;
  final List<Room> rooms;
  final List<String> savedAreaNames = [];

  @override
  Future<List<Asset>> listAssets({String? roomId}) async => roomId == null
      ? assets
      : assets.where((asset) => asset.roomId == roomId).toList();

  @override
  Future<List<Room>> listRooms({String? areaId}) async => areaId == null
      ? rooms
      : rooms.where((room) => room.areaId == areaId).toList();

  @override
  Future<List<Area>> listAreas() async => const [];

  @override
  Future<String> saveArea({
    String? id,
    required String name,
    required AreaKind kind,
    int? sortOrder,
  }) async {
    savedAreaNames.add(name.trim());
    return id ?? 'area-${savedAreaNames.length}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMonetizationRepository extends MonetizationRepository {
  final taskOperations = <Map<String, dynamic>>[];

  @override
  Future<PointDebitResult> createTask(Map<String, dynamic> operation) async {
    taskOperations.add(operation);
    return const PointDebitResult(
      balance: 6,
      charged: 1,
      alreadyProcessed: false,
    );
  }
}

class FakeOfflineCreationDraftStore extends OfflineCreationDraftStore {
  final drafts = <String, Map<String, dynamic>>{};

  @override
  Future<void> save(String key, Map<String, dynamic> value) async {
    drafts[key] = value;
  }

  @override
  Future<Map<String, dynamic>?> load(String key) async => drafts[key];

  @override
  Future<void> clear(String key) async {
    drafts.remove(key);
  }
}

class FakeMaintenanceRepository implements MaintenanceRepository {
  FakeMaintenanceRepository({
    this.archiveFailure,
    this.enableFailure,
    this.initialTasks = const [],
  });

  final savedTitles = <String>[];
  final archivedPlanIds = <String>[];
  final restoredPlanIds = <String>[];
  final enabledChanges = <({String planId, bool enabled})>[];
  final Object? archiveFailure;
  final Object? enableFailure;
  final List<TaskItem> initialTasks;
  var undoCount = 0;

  @override
  Stream<List<TaskItem>> watchTasks() => Stream.value(const []);

  @override
  Stream<List<TaskItem>> watchSavedTasks() => Stream.value(const []);

  @override
  Stream<List<TaskItem>> watchArchivedTasks() => Stream.value(const []);

  @override
  Stream<TaskItem?> watchTask(String planId) => Stream.value(null);

  @override
  Stream<List<TaskItem>> watchTasksForAsset(String assetId) =>
      Stream.value(const []);

  @override
  Stream<List<TaskItem>> watchSavedTasksForAsset(String assetId) =>
      Stream.value(const []);

  @override
  Future<List<TaskItem>> listTasks() async => initialTasks;

  @override
  Future<List<TaskItem>> listSavedTasks() async => const [];

  @override
  Future<List<TaskItem>> listArchivedTasks() async => const [];

  @override
  Future<TaskItem?> getTask(String planId) async => null;

  @override
  Future<List<TaskItem>> listTasksForAsset(String assetId) async => const [];

  @override
  Future<List<TaskItem>> listSavedTasksForAsset(String assetId) async =>
      const [];

  @override
  Future<String> savePlan({
    String? id,
    required String assetId,
    required String title,
    String? instructions,
    required RecurrenceRule recurrence,
    required PriorityLevel priority,
    required DateTime nextDueDate,
    required HealthGroup healthGroup,
    int reminderDaysBefore = 0,
    TaskMetadata? metadata,
  }) async {
    savedTitles.add(title);
    return id ?? 'plan_${savedTitles.length}';
  }

  @override
  Future<bool> completePlan(
    String planId, {
    DateTime? completedAt,
    DateTime? expectedNextDueDate,
    String? notes,
  }) async => true;

  @override
  Future<LocalMaintenanceCompletionResult> completePlanResult(
    String planId, {
    DateTime? completedAt,
    DateTime? expectedNextDueDate,
    String? notes,
  }) async {
    final ok = await completePlan(
      planId,
      completedAt: completedAt,
      expectedNextDueDate: expectedNextDueDate,
      notes: notes,
    );
    return LocalMaintenanceCompletionResult(
      status: ok
          ? LocalMaintenanceCompletionStatus.applied
          : LocalMaintenanceCompletionStatus.occurrenceChanged,
    );
  }

  @override
  Future<void> undoCompletion({
    required String planId,
    required String completionId,
    required DateTime previousDueDate,
    required DateTime expectedCurrentNextDueDate,
  }) async {
    undoCount++;
  }

  @override
  Future<void> archivePlan(String planId) async {
    if (archiveFailure case final failure?) {
      throw failure;
    }
    archivedPlanIds.add(planId);
  }

  @override
  Future<void> restorePlan(String planId) async {
    restoredPlanIds.add(planId);
  }

  @override
  Future<void> setTaskEnabled(String planId, bool enabled) async {
    if (enableFailure case final failure?) {
      throw failure;
    }
    enabledChanges.add((planId: planId, enabled: enabled));
  }

  @override
  Future<void> skipPlanOccurrence(
    String planId, {
    DateTime? skippedAt,
    String? reason,
  }) async {}

  @override
  Future<void> postponePlan(
    String planId,
    DateTime nextDueDate, {
    String? reason,
  }) async {}

  @override
  Future<void> deletePlan(String planId) async {}

  @override
  Future<List<MaintenanceRecord>> listRecordsForPlan(String planId) async =>
      const [];

  @override
  Stream<List<MaintenanceRecord>> watchRecordsForPlan(String planId) =>
      Stream.value(const []);

  @override
  Stream<List<MaintenanceRecord>> watchRecordsForAsset(String assetId) =>
      Stream.value(const []);

  @override
  Future<List<MaintenanceRecord>> listRecordsForAsset(String assetId) async =>
      const [];
}

class FakeStreakService implements StreakService {
  var refreshCount = 0;

  @override
  Future<StreakState> current() async =>
      StreakState(currentStreak: 0, bestStreak: 0, updatedAt: DateTime(2026));

  @override
  Future<StreakState> refresh(DateTime now) async {
    refreshCount++;
    return StreakState(currentStreak: 0, bestStreak: 0, updatedAt: now);
  }
}

class CountingWeatherRepository implements WeatherRepository {
  CountingWeatherRepository({this.deviceLocation, this.settingsRepository});

  final HomeLocation? deviceLocation;
  final FakeSettingsRepository? settingsRepository;
  var refreshCount = 0;
  var useDeviceLocationCount = 0;

  @override
  Future<WeatherSnapshot?> cachedWeather() async => null;

  @override
  Future<WeatherSnapshot?> refreshWeather() async {
    refreshCount++;
    return null;
  }

  @override
  Future<List<HomeLocation>> searchLocations(String query) async => const [];

  @override
  Future<HomeLocation?> useDeviceLocation() async {
    useDeviceLocationCount++;
    if (deviceLocation != null) {
      await settingsRepository?.setHomeLocation(deviceLocation);
    }
    return deviceLocation;
  }

  @override
  Future<HomeLocation?> useCurrentLocationHomeArea() async =>
      useDeviceLocation();

  @override
  Stream<WeatherSnapshot?> watchWeather() => const Stream.empty();
}

class HangingWeatherRepository implements WeatherRepository {
  final releaseRefresh = Completer<void>();
  var refreshCount = 0;

  @override
  Future<WeatherSnapshot?> cachedWeather() async => null;

  @override
  Future<WeatherSnapshot?> refreshWeather() async {
    refreshCount++;
    await releaseRefresh.future;
    return null;
  }

  @override
  Future<List<HomeLocation>> searchLocations(String query) async => const [];

  @override
  Future<HomeLocation?> useDeviceLocation() async => null;

  @override
  Future<HomeLocation?> useCurrentLocationHomeArea() async =>
      useDeviceLocation();

  @override
  Stream<WeatherSnapshot?> watchWeather() => const Stream.empty();
}
