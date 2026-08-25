import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/domain/models.dart';
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

  group('floating action button', () {
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

    testWidgets(
      'shared floating action button tooltip stays above bottom nav',
      (tester) async {
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
      },
    );

    testWidgets('Home Rooms and Tasks FABs share the same dimensions', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings),
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
  });

  group('rtl surface rendering', () {
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
  });

  group('production golden baselines', () {
    testWidgets(
      'production surfaces have stable English and Arabic visual baselines',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final task = makeTaskItem(
          DateTime(2026, 7, 22),
          title: 'Replace water filter',
        );
        final notification = InboxNotification(
          id: 'golden-notification',
          title: 'Replace water filter is overdue',
          body: 'Canonical platform snapshot',
          kind: 'task',
          createdAt: DateTime.utc(2026, 7, 22, 9, 30),
          messageCode: NotificationMessageCode.taskOverdue,
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
                ...testOverrides(
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
            matchesGoldenFile(
              '../goldens/production_dashboard_$localeCode.png',
            ),
          );

          final router = GoRouter.of(tester.element(find.byType(HomeShell)));
          router.go('/notifications');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          await expectLater(
            find.byKey(appBoundaryKey),
            matchesGoldenFile(
              '../goldens/production_notifications_$localeCode.png',
            ),
          );

          router.go('/settings');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          await expectLater(
            find.byKey(appBoundaryKey),
            matchesGoldenFile('../goldens/production_settings_$localeCode.png'),
          );

          final formBoundaryKey = ValueKey(
            'production-form-golden-$localeCode',
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: testOverrides(settings, tasks: [task]),
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
            matchesGoldenFile('../goldens/production_form_$localeCode.png'),
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
            matchesGoldenFile('../goldens/production_dialog_$localeCode.png'),
          );
        }
      },
    );
  });

  group('shared components', () {
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
  });
}
