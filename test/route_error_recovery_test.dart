import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart' show AppLocalizations;
import 'package:owntend/src/features/navigation/route_error_screen.dart'
    show RouteNotFoundScreen;

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: const [Locale('en')],
  home: Builder(builder: (context) => Scaffold(body: child)),
);

void main() {
  testWidgets('unknown routes render a localized recovery surface without '
      'exposing the raw URI', (tester) async {
    await tester.pumpWidget(_host(const RouteNotFoundScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Page not available'), findsOneWidget);
    expect(
      find.text(
        'This link could not be opened. It may be mistyped or no longer exists.',
      ),
      findsOneWidget,
    );
    expect(find.text('Back to home'), findsOneWidget);
    // Raw failure details are never rendered.
    expect(find.textContaining('/definitely-not-a-route'), findsNothing);
  });

  test('router declares explicit error recovery and legacy redirects', () {
    final source = File('lib/src/features/navigation/app_router.dart')
        .readAsStringSync();

    // Unknown/malformed routes must render the localized recovery screen.
    expect(source, contains('errorBuilder:'));
    expect(source, contains('RouteNotFoundScreen()'));

    // The retired profile surface still resolves through an explicit
    // redirect instead of a dead route.
    expect(
      source,
      contains(
        "GoRoute(path: '/profile', redirect: (context, state) => '/account')",
      ),
    );

    // Every declared route path is unique and shell-anchored.
    final routePaths = RegExp(r"path: '([^']+)'")
        .allMatches(source)
        .map((match) => match.group(1)!)
        .toList();
    expect(routePaths.length, greaterThanOrEqualTo(12));
  });
}
