import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/features/auth/presentation/authentication_gate.dart';
import 'package:owntend/src/features/startup/presentation/startup_route_host.dart';

void main() {
  testWidgets(
    'startup route host opens onboarding language menu without router child',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const SizedBox.shrink(),
          ),
        ],
      );
      addTearDown(router.dispose);

      var language = AppLanguage.en;
      final changes = <AppLanguage>[];

      await tester.pumpWidget(
        ProviderScope(
          child: StatefulBuilder(
            builder: (context, setState) {
              return MaterialApp.router(
                routerConfig: router,
                locale: Locale(language.name),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (context, child) {
                  return StartupRouteHost(
                    child: AuthenticationGate(
                      language: language,
                      onLanguageChanged: (value) {
                        changes.add(value);
                        setState(() => language = value);
                      },
                      child: const SizedBox.shrink(),
                    ),
                  );
                },
              );
            },
          ),
        ),
      );
      await tester.pump();

      // The GoRouter child is deliberately omitted above, matching OwntendApp's
      // pre-auth builder. StartupRouteHost must therefore be the route host that
      // makes PopupMenuButton usable.
      expect(find.byType(Navigator), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('onboarding-language-selector-hit-target'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const ValueKey('onboarding-language-selector-hit-target'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('language-option-en')), findsOneWidget);
      expect(find.byKey(const ValueKey('language-option-ar')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('language-option-ar')));
      await tester.pumpAndSettle();

      expect(changes, [AppLanguage.ar]);
      expect(find.text('العربية'), findsOneWidget);
      expect(
        Directionality.of(
          tester.element(find.byKey(const ValueKey('onboarding-actions'))),
        ),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
