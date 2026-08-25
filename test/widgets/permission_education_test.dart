import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/services/app_permission_coordinator.dart';
import 'package:owntend/src/features/permissions/presentation/permission_education_overlay.dart';
import 'package:owntend/src/features/permissions/presentation/permission_setup_screen.dart';
import 'package:owntend/src/core/services/feedback_messenger.dart';
import 'package:owntend/src/ui/feedback/feedback_coordinator.dart';
import 'package:owntend/src/ui/components.dart' as hk_ui;
import 'package:go_router/go_router.dart';

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

  group('permission education steps', () {
    testWidgets(
      'permission education requests each permission after Continue',
      (tester) async {
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          permissionEducationSeenValue: false,
        );
        addTearDown(settings.close);
        final permissions = FakeAppPermissionGateway(
          states: {
            AppPermissionKind.location: AppPermissionState.denied,
            AppPermissionKind.notifications: AppPermissionState.denied,
          },
          requestResults: {
            AppPermissionKind.location: AppPermissionState.granted,
            AppPermissionKind.notifications: AppPermissionState.granted,
          },
        );
        final weather = CountingWeatherRepository(
          settingsRepository: settings,
          deviceLocation: const HomeLocation(
            label: 'Baghdad',
            latitude: 33.3152,
            longitude: 44.3661,
            source: 'device',
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: testOverrides(
              settings,
              permissionGateway: permissions,
              weatherRepository: weather,
            ),
            child: const OwntendApp(),
          ),
        );
        await pumpPermissionEducation(tester);

        expect(find.text('Set your weather area'), findsOneWidget);
        expect(permissions.requests, isEmpty);

        final useLocationFinder = find.text('Use current location');
        await tester.ensureVisible(useLocationFinder);
        await tester.tap(useLocationFinder, warnIfMissed: false);
        await pumpPermissionEducation(tester);
        expect(permissions.requests, [AppPermissionKind.location]);
        expect(weather.useDeviceLocationCount, 1);
        expect(find.text('Never miss important maintenance'), findsOneWidget);

        final enableNotificationsFinder = find.text('Enable notifications');
        await tester.ensureVisible(enableNotificationsFinder);
        await tester.tap(enableNotificationsFinder, warnIfMissed: false);
        await pumpPermissionEducation(tester);
        expect(permissions.requests, [
          AppPermissionKind.location,
          AppPermissionKind.notifications,
        ]);
        expect(settings.permissionEducationSeenValue, isTrue);
        expect(
          find.byKey(const ValueKey('permission-education-overlay')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'permission education skips configured steps and supports Not now',
      (tester) async {
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          permissionEducationSeenValue: false,
        );
        settings.homeLocationValue = const HomeLocation(
          label: 'Baghdad',
          latitude: 33.3152,
          longitude: 44.3661,
          source: 'manual',
        );
        addTearDown(settings.close);
        final permissions = FakeAppPermissionGateway(
          states: {
            AppPermissionKind.location: AppPermissionState.granted,
            AppPermissionKind.notifications: AppPermissionState.denied,
          },
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: testOverrides(settings, permissionGateway: permissions),
            child: const OwntendApp(),
          ),
        );
        await pumpPermissionEducation(tester);

        expect(find.text('Set your weather area'), findsNothing);
        expect(find.text('Never miss important maintenance'), findsOneWidget);
        final notNowFinder = find.text('Not now');
        await tester.ensureVisible(notNowFinder);
        await tester.tap(notNowFinder, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(permissions.requests, isEmpty);
        expect(
          find.byKey(const ValueKey('permission-education-overlay')),
          findsNothing,
        );
      },
    );

    testWidgets('permanent permission denial routes to app settings', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(
        onboardingCompletedValue: true,
        permissionEducationSeenValue: false,
      );
      addTearDown(settings.close);
      final permissions = FakeAppPermissionGateway(
        states: {
          AppPermissionKind.location: AppPermissionState.permanentlyDenied,
          AppPermissionKind.notifications: AppPermissionState.granted,
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings, permissionGateway: permissions),
          child: const OwntendApp(),
        ),
      );
      await pumpPermissionEducation(tester);
      final manageSettingsFinder = find.text('Manage in settings');
      await tester.ensureVisible(manageSettingsFinder);
      await tester.tap(manageSettingsFinder, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(permissions.openLocationSettingsCount, 1);
      expect(permissions.requests, isEmpty);
      expect(find.text('Set your weather area'), findsOneWidget);
    });

    testWidgets(
      'prompted denied permission routes to settings without request',
      (tester) async {
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          permissionEducationSeenValue: false,
        );
        settings.homeLocationValue = const HomeLocation(
          label: 'Baghdad',
          latitude: 33.3152,
          longitude: 44.3661,
          source: 'manual',
        );
        addTearDown(settings.close);
        final permissions = FakeAppPermissionGateway(
          states: {
            AppPermissionKind.location: AppPermissionState.granted,
            AppPermissionKind.notifications:
                AppPermissionState.permanentlyDenied,
          },
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: testOverrides(settings, permissionGateway: permissions),
            child: const OwntendApp(),
          ),
        );
        await pumpPermissionEducation(tester);

        expect(find.text('Never miss important maintenance'), findsOneWidget);
        final manageSettingsFinder = find.text('Manage in settings');
        await tester.ensureVisible(manageSettingsFinder);
        await tester.tap(manageSettingsFinder, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(permissions.openAppSettingsCount, 1);
        expect(permissions.requests, isEmpty);
        expect(find.text('Never miss important maintenance'), findsOneWidget);
      },
    );

    testWidgets(
      'configured weather and granted permissions persist completion',
      (tester) async {
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          permissionEducationSeenValue: false,
        );
        settings.homeLocationValue = const HomeLocation(
          label: 'Baghdad',
          latitude: 33.3152,
          longitude: 44.3661,
          source: 'manual',
        );
        addTearDown(settings.close);
        final permissions = FakeAppPermissionGateway(
          states: {
            AppPermissionKind.location: AppPermissionState.granted,
            AppPermissionKind.notifications: AppPermissionState.granted,
          },
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: testOverrides(settings, permissionGateway: permissions),
            child: const OwntendApp(),
          ),
        );
        await pumpPermissionEducation(tester);

        expect(
          find.byKey(const ValueKey('permission-education-overlay')),
          findsNothing,
        );
        expect(settings.permissionEducationSeenValue, isTrue);
        expect(permissions.requests, isEmpty);
      },
    );
  });

  group('permission education integration', () {
    testWidgets(
      'permission education overlay sits above content while allowing tab navigation',
      (tester) async {
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          permissionEducationSeenValue: false,
        );
        addTearDown(settings.close);
        final permissions = FakeAppPermissionGateway(
          states: {
            AppPermissionKind.location: AppPermissionState.denied,
            AppPermissionKind.notifications: AppPermissionState.denied,
          },
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: testOverrides(settings, permissionGateway: permissions),
            child: const OwntendApp(),
          ),
        );
        await pumpPermissionEducation(tester);
        final router = GoRouter.of(tester.element(find.byType(HomeShell)));

        final overlayRect = tester.getRect(
          find.byKey(const ValueKey('permission-education-overlay')),
        );
        final cardRect = tester.getRect(
          find.byKey(const ValueKey('permission-card-deviceLocation')),
        );
        final navRect = tester.getRect(
          find.byType(hk_ui.SereneBottomNavigationBar),
        );
        expect(overlayRect.top, 0);
        expect(cardRect.bottom, lessThanOrEqualTo(navRect.top + 100));

        await tester.tap(find.text('Tools'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));

        expect(router.routeInformationProvider.value.uri.path, '/more');
        expect(settings.permissionEducationSeenValue, isFalse);
      },
    );

    testWidgets('Settings can reopen unresolved permission education', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final permissions = FakeAppPermissionGateway(
        states: {
          AppPermissionKind.location: AppPermissionState.denied,
          AppPermissionKind.notifications: AppPermissionState.denied,
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings, permissionGateway: permissions),
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(HomeShell)));
      router.go('/settings');
      await tester.pumpAndSettle();
      final setup = find.byKey(const ValueKey('settings-permission-education'));
      await tester.scrollUntilVisible(
        setup,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      tester.widget<ListTile>(setup).onTap!();
      await pumpPermissionEducation(tester);

      expect(find.byType(PermissionSetupScreen), findsOneWidget);
    });

    testWidgets('permission education respects reduced motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final settings = FakeSettingsRepository(
        onboardingCompletedValue: true,
        permissionEducationSeenValue: false,
      );
      addTearDown(settings.close);
      final permissions = FakeAppPermissionGateway(
        states: {
          AppPermissionKind.location: AppPermissionState.denied,
          AppPermissionKind.notifications: AppPermissionState.denied,
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings, permissionGateway: permissions),
          child: const OwntendApp(),
        ),
      );
      await pumpPermissionEducation(tester);
      await tester.pump();

      expect(find.text('Set your weather area'), findsOneWidget);
      expect(find.byType(PermissionEducationOverlayWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
