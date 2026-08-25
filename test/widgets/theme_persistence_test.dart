import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/config/app_config.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/services/feedback_messenger.dart';
import 'package:owntend/src/ui/feedback/feedback_coordinator.dart';
import 'package:owntend/src/ui/components.dart' as hk_ui;

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

  group('saved theme preferences', () {
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
          overrides: testOverrides(settings),
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
      Future<ThemeMode> pumpMode(
        ThemePreference preference,
        DateTime now,
      ) async {
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          themePreferenceValue: preference,
          timeOfDayThemeEnabledValue: preference == ThemePreference.system,
        );
        addTearDown(settings.close);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(settings),
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
  });

  group('language and appearance settings', () {
    testWidgets(
      'device Arabic is used until an explicit language is selected',
      (tester) async {
        tester.platformDispatcher.localeTestValue = const Locale('ar');
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        final settings = FakeSettingsRepository(onboardingCompletedValue: true);
        addTearDown(settings.close);
        final arabic = lookupAppLocalizations(const Locale('ar'));
        final english = lookupAppLocalizations(const Locale('en'));

        await tester.pumpWidget(
          ProviderScope(
            overrides: testOverrides(settings),
            child: const OwntendApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(arabic.home), findsOneWidget);

        await settings.setAppLocalePreference(AppLanguage.en);
        await tester.pumpAndSettle();
        expect(find.text(english.home), findsOneWidget);
        expect(settings.appLanguageExplicitValue, isTrue);
      },
    );

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
          overrides: testOverrides(settings),
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
      await tester.tap(
        find.byKey(const ValueKey('settings-language-selector')),
      );
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
              ...testOverrides(settings),
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
      expect(
        find.byKey(const ValueKey('settings-ad-inspector')),
        findsOneWidget,
      );

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
  });

  group('theme bundle', () {
    testWidgets('theme bundles Geist and includes light and dark themes', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: false);
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings),
          child: const OwntendApp(),
        ),
      );

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme?.textTheme.bodyMedium?.fontFamily, 'Geist');
      expect(app.theme?.colorScheme.brightness, Brightness.light);
      expect(app.themeMode, isIn([ThemeMode.light, ThemeMode.dark]));
      expect(app.darkTheme?.colorScheme.brightness, Brightness.dark);
    });
  });

  group('day-night theme toggle', () {
    testWidgets('Weather header exposes day-night theme toggle', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(
        onboardingCompletedValue: true,
        themePreferenceValue: ThemePreference.dark,
        timeOfDayThemeEnabledValue: true,
      );
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings, weather: makeWeather()),
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
          (widget) =>
              widget.runtimeType.toString().contains('ThemeDropOverlay'),
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
          overrides: testOverrides(settings, weather: makeWeather()),
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
  });

  group('manual theme controls', () {
    testWidgets('Settings shows manual and automatic theme controls', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings),
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
      await tester.tap(
        find.byKey(const ValueKey('settings-language-selector')),
      );
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
  });
}
