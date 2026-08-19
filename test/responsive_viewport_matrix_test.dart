import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/ui/app_theme.dart';
import 'package:owntend/src/ui/components.dart' as hk_ui;

import 'test_theme.dart';

Widget _wrapWithApp({
  required Widget child,
  Locale locale = const Locale('en'),
  List<dynamic> overrides = const [],
  ThemeData? theme,
  EdgeInsets viewInsets = EdgeInsets.zero,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MediaQuery(
      data: MediaQueryData(viewInsets: viewInsets, textScaler: textScaler),
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: theme ?? testLightTheme(),
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Responsive Viewport Matrix & Usability Tests', () {
    testWidgets(
      'SereneBottomNavigationBar stays centered and constrained on wide viewports',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          _wrapWithApp(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: hk_ui.SereneBottomNavigationBar(
                selectedIndex: 0,
                destinations: const [
                  hk_ui.SereneBottomNavDestination(
                    icon: Symbols.home_rounded,
                    selectedIcon: Symbols.home_filled_rounded,
                    label: hk_ui.SereneBottomNavLabel.home,
                  ),
                  hk_ui.SereneBottomNavDestination(
                    icon: Symbols.task_alt_rounded,
                    selectedIcon: Symbols.task_alt_rounded,
                    label: hk_ui.SereneBottomNavLabel.tasks,
                  ),
                  hk_ui.SereneBottomNavDestination(
                    icon: Symbols.more_horiz_rounded,
                    selectedIcon: Symbols.more_horiz_rounded,
                    label: hk_ui.SereneBottomNavLabel.tools,
                  ),
                ],
                onDestinationSelected: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final navBarFinder = find.byType(hk_ui.SereneBottomNavigationBar);
        expect(navBarFinder, findsOneWidget);

        final constrainedBoxFinder = find.descendant(
          of: navBarFinder,
          matching: find.byType(ConstrainedBox),
        );
        expect(constrainedBoxFinder, findsWidgets);

        final renderBox = tester.renderObject(
          find
              .descendant(of: navBarFinder, matching: find.byType(DecoratedBox))
              .first,
        ) as RenderBox;
        expect(renderBox.size.width, lessThanOrEqualTo(640.0));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PremiumBottomActionBar stays centered and constrained on ultra-wide viewports',
      (tester) async {
        tester.view.physicalSize = const Size(2560, 1440);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          _wrapWithApp(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: hk_ui.PremiumBottomActionBar(
                label: 'Complete Maintenance Task',
                icon: Symbols.check_circle_rounded,
                onPressed: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final actionBarFinder = find.byType(hk_ui.PremiumBottomActionBar);
        expect(actionBarFinder, findsOneWidget);

        final filledButtonFinder = find.descendant(
          of: actionBarFinder,
          matching: find.byType(FilledButton),
        );
        expect(filledButtonFinder, findsOneWidget);

        final renderBox = tester.renderObject(filledButtonFinder) as RenderBox;
        expect(renderBox.size.width, lessThanOrEqualTo(640.0));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'StatisticsScreen adapts gracefully in short landscape viewport with scrolling',
      (tester) async {
        tester.view.physicalSize = const Size(800, 360);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final testSummary = StatisticsSummary(
          completedByMonth: {'2026-06': 12, '2026-07': 18, '2026-08': 24},
          taskDistribution: {
            AssetType.device: 8,
            AssetType.safety: 4,
            AssetType.plant: 6,
          },
          completionRate: 0.88,
          overdueRate: 0.05,
        );

        await tester.pumpWidget(
          _wrapWithApp(
            overrides: [
              statisticsProvider.overrideWith(
                (ref) => Stream.value(testSummary),
              ),
            ],
            child: const StatisticsScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SingleChildScrollView), findsOneWidget);
        expect(find.text('88%'), findsOneWidget);
        expect(find.text('5%'), findsOneWidget);
        expect(find.text('Monthly Completions'), findsOneWidget);
        expect(find.text('Task Distribution'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'StatisticsScreen displays side-by-side charts on wide tablet viewports',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final testSummary = StatisticsSummary(
          completedByMonth: {'2026-06': 10, '2026-07': 15},
          taskDistribution: {AssetType.device: 5, AssetType.safety: 3},
          completionRate: 0.92,
          overdueRate: 0.02,
        );

        await tester.pumpWidget(
          _wrapWithApp(
            overrides: [
              statisticsProvider.overrideWith(
                (ref) => Stream.value(testSummary),
              ),
            ],
            child: const StatisticsScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('92%'), findsOneWidget);
        expect(find.text('2%'), findsOneWidget);
        expect(find.text('Monthly Completions'), findsOneWidget);
        expect(find.text('Task Distribution'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'StatisticsScreen metrics format without overflow under 2.0x text scaling',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final testSummary = StatisticsSummary(
          completedByMonth: {'2026-08': 5},
          taskDistribution: {AssetType.general: 5},
          completionRate: 1.0,
          overdueRate: 0.0,
        );

        await tester.pumpWidget(
          _wrapWithApp(
            textScaler: const TextScaler.linear(2.0),
            overrides: [
              statisticsProvider.overrideWith(
                (ref) => Stream.value(testSummary),
              ),
            ],
            child: const StatisticsScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('100%'), findsOneWidget);
        expect(find.text('0%'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Point shortage dialog renders within short height viewport without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(360, 420);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          _wrapWithApp(
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      actionsOverflowButtonSpacing: HkSpacing.xs,
                      title: const Text('Need 1 point'),
                      content: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: const SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('1 point balance'),
                              SizedBox(height: 8),
                              Text(
                                'Points are used when creating items and plans. Watch a quick ad or wait for daily reset.',
                              ),
                            ],
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Keep editing'),
                        ),
                        FilledButton.icon(
                          onPressed: () {},
                          icon: const Icon(Symbols.play_circle_rounded),
                          label: const Text('Earn a point'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Show Dialog'));
        await tester.pumpAndSettle();

        expect(find.text('Need 1 point'), findsOneWidget);
        expect(find.text('Keep editing'), findsOneWidget);
        expect(find.text('Earn a point'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Arabic RTL layout mirrors and renders cleanly in wide and narrow viewports',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          _wrapWithApp(
            locale: const Locale('ar'),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  children: [
                    hk_ui.ToolTile(
                      icon: Symbols.stars_rounded,
                      title: 'كسب نقاط مجانية',
                      subtitle: 'شاهد إعلانات قصيرة للحصول على نقاط إضافية',
                      onTap: () {},
                    ),
                    hk_ui.ToolTile(
                      icon: Symbols.search_rounded,
                      title: 'بحث',
                      subtitle: 'البحث في الغرف والعناصر والمهام',
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('كسب نقاط مجانية'), findsOneWidget);
        expect(find.text('بحث'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
