import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/ui/components.dart' as hk_ui;

import 'test_theme.dart';

const _multiSeriesSummary = StatisticsSummary(
  completionRate: 0.88,
  overdueRate: 0.05,
  completedByMonth: {
    '2026-06': 12,
    '2026-07': 18,
    '2026-08': 24,
  },
  taskDistribution: {
    HealthGroup.safety: 6,
    HealthGroup.pets: 5,
    HealthGroup.appliances: 4,
    HealthGroup.plants: 3,
    HealthGroup.cleaning: 2,
    HealthGroup.other: 1,
  },
);

const _oneSeriesSummary = StatisticsSummary(
  completionRate: 1,
  overdueRate: 0,
  completedByMonth: {'2026-08': 5},
  taskDistribution: {HealthGroup.other: 5},
);

const _emptySummary = StatisticsSummary(
  completionRate: 1,
  overdueRate: 0,
  completedByMonth: {},
  taskDistribution: {},
);

Widget _statisticsApp(
  StatisticsSummary summary, {
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return ProviderScope(
    overrides: [
      statisticsProvider.overrideWith((ref) => Stream.value(summary)),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: testLightTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: const StatisticsScreen(),
    ),
  );
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tall Statistics viewport stays content-driven and scrollable', (
    tester,
  ) async {
    _setViewport(tester, const Size(1024, 1400));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_statisticsApp(_multiSeriesSummary));
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('statistics-chart-monthly')))
          .height,
      lessThan(400),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('statistics-chart-distribution')))
          .height,
      lessThan(400),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide Statistics cards keep equal widths and aligned rows', (
    tester,
  ) async {
    _setViewport(tester, const Size(1024, 800));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_statisticsApp(_multiSeriesSummary));
    await tester.pumpAndSettle();

    final completion = find.byKey(
      const ValueKey('statistics-metric-completion'),
    );
    final overdue = find.byKey(const ValueKey('statistics-metric-overdue'));
    final monthly = find.byKey(const ValueKey('statistics-chart-monthly'));
    final distribution = find.byKey(
      const ValueKey('statistics-chart-distribution'),
    );

    expect(
      (tester.getSize(completion).width - tester.getSize(overdue).width).abs(),
      lessThan(0.5),
    );
    expect(
      (tester.getTopLeft(completion).dy - tester.getTopLeft(overdue).dy).abs(),
      lessThan(0.5),
    );
    expect(
      (tester.getSize(monthly).width - tester.getSize(distribution).width).abs(),
      lessThan(0.5),
    );
    expect(
      (tester.getTopLeft(monthly).dy - tester.getTopLeft(distribution).dy).abs(),
      lessThan(0.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow 2x Statistics layout wraps labels in English and Arabic',
    (tester) async {
      _setViewport(tester, const Size(320, 900));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final locale in const [Locale('en'), Locale('ar')]) {
        await tester.pumpWidget(
          _statisticsApp(
            _oneSeriesSummary,
            locale: locale,
            textScaler: const TextScaler.linear(2),
          ),
        );
        await tester.pumpAndSettle();

        final l10n = lookupAppLocalizations(locale);
        final completionLabel = tester.widget<Text>(
          find.text(l10n.historyCompletion),
        );
        final overdueLabel = tester.widget<Text>(find.text(l10n.activeOverdue));
        final completion = find.byKey(
          const ValueKey('statistics-metric-completion'),
        );
        final overdue = find.byKey(const ValueKey('statistics-metric-overdue'));

        expect(completionLabel.overflow, isNull);
        expect(overdueLabel.overflow, isNull);
        expect(
          tester.getTopLeft(overdue).dy,
          greaterThan(tester.getTopLeft(completion).dy),
        );
        expect(
          Directionality.of(tester.element(find.byType(StatisticsScreen))),
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('task distribution wraps measured legend items without scaling', (
    tester,
  ) async {
    _setViewport(tester, const Size(360, 1000));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);

    await tester.pumpWidget(
      _statisticsApp(
        _multiSeriesSummary,
        textScaler: const TextScaler.linear(1.8),
      ),
    );
    await tester.pumpAndSettle();

    final distributionChart = find.byType(TaskDistributionChart);
    expect(
      find.descendant(
        of: distributionChart,
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('statistics-legend-other')))
          .dy,
      greaterThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('statistics-legend-safety')))
            .dy,
      ),
    );

    final semanticsData = tester
        .getSemantics(
          find.byKey(
            const ValueKey('statistics-distribution-chart-semantics'),
          ),
        )
        .getSemanticsData();
    expect(
      semanticsData.label,
      lookupAppLocalizations(const Locale('en')).taskDistribution,
    );
    expect(semanticsData.value, contains('6'));
    expect(semanticsData.value, contains('1'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty chart sections stay inline without nested empty cards', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_statisticsApp(_emptySummary));
    await tester.pumpAndSettle();

    final monthlyPanel = find.byKey(const ValueKey('statistics-chart-monthly'));
    final distributionPanel = find.byKey(
      const ValueKey('statistics-chart-distribution'),
    );
    expect(
      find.descendant(
        of: monthlyPanel,
        matching: find.byType(hk_ui.PremiumEmptyState),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: distributionPanel,
        matching: find.byType(hk_ui.PremiumEmptyState),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('statistics-monthly-empty')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('statistics-distribution-empty')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('statistics-monthly-empty')))
          .height,
      lessThan(220),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('statistics-distribution-empty')))
          .height,
      lessThan(220),
    );
    expect(tester.takeException(), isNull);
  });
}
