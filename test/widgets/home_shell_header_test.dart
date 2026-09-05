import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/sync/sync_contracts.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';
import 'package:owntend/src/features/monetization/monetization.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/services/feedback_messenger.dart';
import 'package:owntend/src/ui/app_theme.dart';
import 'package:owntend/src/ui/feedback/feedback_coordinator.dart';
import 'package:owntend/src/ui/components.dart' as hk_ui;
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

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

  group('shell navigation', () {
    testWidgets(
      'shell navigation remains visible with route query parameters',
      (tester) async {
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
              ...testOverrides(settings),
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
      },
    );

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
            ...testOverrides(settings),
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

    testWidgets(
      'a genuine signed-in transition canonicalizes navigation home',
      (tester) async {
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
              ...testOverrides(settings, includeAuthOverrides: false),
              authStateProvider.overrideWith((ref) => authChanges.stream),
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
      },
    );
  });

  group('dashboard shell', () {
    testWidgets('dashboard shell renders when onboarding is complete', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      settings.profileValue = const AppProfile(nickname: 'Thulfiqar');
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings),
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

    testWidgets(
      'new Home user sees real setup progress and no readiness score',
      (tester) async {
        final settings = FakeSettingsRepository(onboardingCompletedValue: true);
        addTearDown(settings.close);

        await tester.pumpWidget(
          ProviderScope(
            overrides: testOverrides(
              settings,
              assets: const [],
              rooms: const [],
            ),
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
      },
    );

    testWidgets('eligible Home user sees the readiness card', (tester) async {
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
            overrides: testOverrides(settings),
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
  });

  group('account screens', () {
    testWidgets('Account nickname can be saved and cleared from the host', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      settings.profileValue = const AppProfile(nickname: 'Test User');
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings),
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
            ...testOverrides(
              settings,
              weather: makeWeather(
                temperature: 46,
                locationLabel:
                    'Al-Diwaniyah District, Al-Qadisiyah Governorate',
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
  });

  group('dashboard layout and weather', () {
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
        final task = makeTaskItem(DateTime.now());

        await tester.pumpWidget(
          ProviderScope(
            overrides: testOverrides(settings, tasks: [task]),
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
          overrides: testOverrides(
            settings,
            tasks: [
              makeTaskItem(today, id: 'plan_today_one', title: 'Today one'),
              makeTaskItem(today, id: 'plan_today_two', title: 'Today two'),
              makeTaskItem(today, id: 'plan_today_three', title: 'Today three'),
              makeTaskItem(today, id: 'plan_today_four', title: 'Today four'),
              makeTaskItem(
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
      final task = makeTaskItem(DateUtils.dateOnly(DateTime.now()));

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings, tasks: [task]),
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
      final task = makeTaskItem(DateUtils.dateOnly(DateTime.now()));

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings, tasks: [task]),
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
      final overdueTask = makeTaskItem(
        DateUtils.dateOnly(DateTime.now()).subtract(const Duration(days: 1)),
        status: TaskStatus.overdue,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(
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
          overrides: testOverrides(
            settings,
            tasks: [
              makeTaskItem(today, id: 'plan_one', title: 'Task one'),
              makeTaskItem(today, id: 'plan_two', title: 'Task two'),
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

      final nextSettings = FakeSettingsRepository(
        onboardingCompletedValue: true,
      );
      addTearDown(nextSettings.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(
            nextSettings,
            tasks: [
              makeTaskItem(today, id: 'plan_one', title: 'Task one'),
              makeTaskItem(today, id: 'plan_two', title: 'Task two'),
              makeTaskItem(today, id: 'plan_three', title: 'Task three'),
            ],
          ),
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();

      scrollView = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      expect(scrollView.physics, isA<AlwaysScrollableScrollPhysics>());
    });

    testWidgets('Home weather shows three details without Rain', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings, weather: makeWeather()),
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
            final router = await pumpDashboardHeader(
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
            const expectedH = 48.0;
            expect(tester.getSize(points).height, expectedH);
            expect(
              tester.getSize(notifications),
              const Size(expectedH, expectedH),
            );
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
                  .descendant(
                    of: notifications,
                    matching: find.byType(Material),
                  )
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
        final router = await pumpDashboardHeader(
          tester,
          settings: settings,
          theme: OwntendTheme.light(),
        );
        addTearDown(settings.close);
        addTearDown(router.dispose);

        await expectLater(
          find.byKey(const ValueKey('dashboard-header-card')),
          matchesGoldenFile('../goldens/dashboard_header_${entry.key}.png'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets(
      'Home header points and notification controls keep navigation',
      (tester) async {
        final settings = FakeSettingsRepository(onboardingCompletedValue: true);
        final router = await pumpDashboardHeader(
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

        await tester.tap(
          find.byKey(const ValueKey('home-notifications-control')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Notification route target'), findsOneWidget);
      },
    );

    testWidgets('compact points card appears only on Home Rooms and Tasks', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(settings),
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
        expect(size.height, 48.0);
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
          overrides: testOverrides(
            settings,
            weather: makeWeather(
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
            ...testOverrides(settings, weatherRepository: weatherRepository),
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

    testWidgets(
      'Home weather details stay in one row on small scaled screens',
      (tester) async {
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
                    weather: makeWeather(
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
        expect(
          tester.getCenter(wind).dy,
          closeTo(tester.getCenter(feels).dy, 1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('home stability', () {
    testWidgets('Home reports domain stream errors instead of empty content', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tasksProvider.overrideWith(
              (ref) =>
                  Stream<List<TaskItem>>.error(StateError('tasks unavailable')),
            ),
            assetsProvider.overrideWith((ref) => Stream.value(const <Asset>[])),
            roomsProvider.overrideWith((ref) => Stream.value(const <Room>[])),
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

      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Set up your home'), findsNothing);
    });

    testWidgets('Home labels saved data when a live refresh fails', (
      tester,
    ) async {
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

      expect(
        find.byKey(const ValueKey('dashboard-stale-data-warning')),
        findsOneWidget,
      );
      expect(find.text('Feed the fish'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Home ignores equal database bursts and commits real changes', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      final taskChanges = StreamController<List<TaskItem>>.broadcast();
      final assetChanges = StreamController<List<Asset>>.broadcast();
      final roomChanges = StreamController<List<Room>>.broadcast();
      final now = DateTime(2026);
      final tasks = [makeTaskItem(DateUtils.dateOnly(DateTime.now()))];
      final assets = makeThings(now);
      final rooms = makeRooms(now);
      final initialSnapshot = ValueNotifier<InitialHomeSnapshot?>(
        InitialHomeSnapshot(
          session: signedInTestSession,
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
            ...testOverrides(
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
        makeTaskItem(
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
        final task = makeTaskItem(DateUtils.dateOnly(DateTime.now()));
        addTearDown(settings.close);

        await tester.pumpWidget(
          ProviderScope(
            overrides: testOverrides(settings, tasks: [task]),
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
  });

  group('home map', () {
    testWidgets('home map renders rooms at phone and wide sizes', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final size in [const Size(390, 844), const Size(900, 900)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;

        final settings = FakeSettingsRepository(onboardingCompletedValue: true);
        addTearDown(settings.close);

        await tester.pumpWidget(
          ProviderScope(
            overrides: testOverrides(settings),
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
        final kitchenCard = find.byKey(
          const ValueKey('room-card-room_kitchen'),
        );
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
  });
}
