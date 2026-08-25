import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/owntend_animated_splash_screen.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/services/feedback_messenger.dart';
import 'package:owntend/src/ui/feedback/feedback_coordinator.dart';
import 'package:owntend/src/ui/components.dart' as hk_ui;

import '../support/widget_test_fakes.dart';

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

  group('startup bootstrap surface', () {
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

      final startupSurface = find.byKey(
        const ValueKey('startup-theme-loading'),
      );
      expect(startupSurface, findsOneWidget);
      expect(find.byType(OwntendStartupSurface), findsOneWidget);
      expect(find.text('Owntend'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('owntend-animated-splash')),
        findsNothing,
      );
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

      final startupSurface = find.byKey(
        const ValueKey('startup-theme-loading'),
      );
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
  });

  group('startup failure localization', () {
    testWidgets('startup failures honor an Arabic device locale', (
      tester,
    ) async {
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
  });

  group('app root onboarding', () {
    testWidgets(
      'app root starts at onboarding without owning a duplicate splash',
      (tester) async {
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: false,
        );
        addTearDown(settings.close);

        await tester.pumpWidget(
          ProviderScope(
            overrides: testOverrides(settings, session: null),
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
          roomId: 'missing-room-id',
          createdAt: DateTime.utc(2026, 8, 14),
          updatedAt: DateTime.utc(2026, 8, 14),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: testOverrides(
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
  });
}
