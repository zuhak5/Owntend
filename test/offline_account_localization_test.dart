import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/config/app_config.dart';
import 'package:owntend/src/features/auth/presentation/account_screen.dart';
import 'package:owntend/src/features/auth/presentation/auth_providers.dart';

void main() {
  testWidgets('offline account presentation works in English and Arabic', (
    tester,
  ) async {
    for (final locale in const [Locale('en'), Locale('ar')]) {
      final l10n = lookupAppLocalizations(locale);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appConfigProvider.overrideWithValue(AppConfig.test())],
          child: MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const AccountScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.account), findsOneWidget);
      expect(find.text(l10n.settings), findsOneWidget);
      expect(find.text(l10n.backupAndRestore), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(AccountScreen))),
        locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );
    }
  });
}
