import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/features/navigation/route_error_screen.dart'
    show RouteNotFoundScreen;

Widget _host(Locale locale, Widget child) => MaterialApp(
  locale: locale,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: const [Locale('en'), Locale('ar')],
  home: Builder(builder: (context) => Scaffold(body: child)),
);

void main() {
  testWidgets('route recovery surface exposes semantics in English', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const Locale('en'), const RouteNotFoundScreen()),
    );
    await tester.pumpAndSettle();

    // The status icon carries a semantic label matching the visible title.
    final labeledIcons = tester
        .widgetList<Icon>(find.byType(Icon))
        .where((icon) => icon.semanticLabel != null)
        .toList();
    expect(labeledIcons, isNotEmpty);
    expect(
      labeledIcons.any((icon) => icon.semanticLabel == 'Page not available'),
      isTrue,
      reason: 'the status icon must expose the localized title as its label',
    );

    // Title and action are reachable by semantics.
    expect(
      find.bySemanticsLabel('Page not available'),
      findsAtLeastNWidgets(1),
    );
    expect(find.bySemanticsLabel('Back to home'), findsOneWidget);

    // The recovery action meets the 48dp minimum touch target.
    final button = tester.getSize(find.byType(FilledButton));
    expect(button.height, greaterThanOrEqualTo(48));
    expect(button.width, greaterThanOrEqualTo(48));
  });

  testWidgets('route recovery surface renders Arabic RTL correctly', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const Locale('ar'), const RouteNotFoundScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('الصفحة غير متوفرة'), findsOneWidget);
    expect(find.text('العودة إلى الرئيسية'), findsOneWidget);

    final context = tester.element(find.text('الصفحة غير متوفرة'));
    expect(Directionality.of(context), TextDirection.rtl);
  });

  testWidgets('recovery text scales without clipping at large text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Locale('en'),
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: const RouteNotFoundScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Page not available'), findsOneWidget);
    expect(find.text('Back to home'), findsOneWidget);
  });
}
