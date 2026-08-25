import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/features/permissions/domain/permission_capability.dart';
import 'package:owntend/src/features/permissions/presentation/permission_education_overlay.dart';

void main() {
  // A taller screen gives the card room to show all content without scrolling.
  const testScreenSize = Size(800, 1200);

  /// Wraps [child] with MaterialApp + localization.
  /// Sets disableAnimations so the repeating AnimationController stops
  /// immediately and pumpAndSettle does not time out.
  Widget buildTestableWidget(Widget child) {
    return MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets(
    'Renders weather location step with Use current location and Choose location buttons',
    (tester) async {
      tester.view.physicalSize = testScreenSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool currentLocationTapped = false;
      bool chooseLocationTapped = false;

      await tester.pumpWidget(
        buildTestableWidget(
          PermissionEducationOverlayWidget(
            activeCapability: PermissionCapability.deviceLocation,
            relevantCapabilities: const [
              PermissionCapability.deviceLocation,
              PermissionCapability.notifications,
            ],
            isBusy: false,
            onUseCurrentLocation: () => currentLocationTapped = true,
            onChooseLocationManually: () => chooseLocationTapped = true,
            onEnableNotifications: () {},
            onDefer: () {},
            onFinishLater: () {},
          ),
        ),
      );
      await tester.pump(); // settle post-frame callbacks (focus, etc.)

      expect(find.text('Set your weather area'), findsOneWidget);

      final useLocationFinder = find.text('Use current location');
      expect(useLocationFinder, findsOneWidget);
      await tester.ensureVisible(useLocationFinder);
      await tester.pump();
      await tester.tap(useLocationFinder, warnIfMissed: false);
      expect(currentLocationTapped, isTrue);

      final chooseLocationFinder = find.text('Choose location');
      expect(chooseLocationFinder, findsOneWidget);
      await tester.ensureVisible(chooseLocationFinder);
      await tester.pump();
      await tester.tap(chooseLocationFinder, warnIfMissed: false);
      expect(chooseLocationTapped, isTrue);
    },
  );

  testWidgets('Renders notifications step with Enable notifications button', (
    tester,
  ) async {
    tester.view.physicalSize = testScreenSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    bool enableNotificationsTapped = false;

    await tester.pumpWidget(
      buildTestableWidget(
        PermissionEducationOverlayWidget(
          activeCapability: PermissionCapability.notifications,
          relevantCapabilities: const [PermissionCapability.notifications],
          isBusy: false,
          onUseCurrentLocation: () {},
          onChooseLocationManually: () {},
          onEnableNotifications: () => enableNotificationsTapped = true,
          onDefer: () {},
          onFinishLater: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Never miss important maintenance'), findsOneWidget);

    final enableFinder = find.text('Enable notifications');
    expect(enableFinder, findsOneWidget);
    await tester.ensureVisible(enableFinder);
    await tester.pump();
    await tester.tap(enableFinder, warnIfMissed: false);
    expect(enableNotificationsTapped, isTrue);
  });

  testWidgets('Close button triggers finish later callback', (tester) async {
    tester.view.physicalSize = testScreenSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    bool finishLaterTapped = false;

    await tester.pumpWidget(
      buildTestableWidget(
        PermissionEducationOverlayWidget(
          activeCapability: PermissionCapability.deviceLocation,
          relevantCapabilities: const [PermissionCapability.deviceLocation],
          isBusy: false,
          onUseCurrentLocation: () {},
          onChooseLocationManually: () {},
          onEnableNotifications: () {},
          onDefer: () {},
          onFinishLater: () => finishLaterTapped = true,
        ),
      ),
    );
    await tester.pump();

    // The close button uses Symbols.close_rounded (material_symbols_icons),
    // not Icons.close_rounded. Find by its tooltip text instead.
    final closeButtonFinder = find.byTooltip('Finish later');
    expect(closeButtonFinder, findsOneWidget);
    await tester.tap(closeButtonFinder, warnIfMissed: false);
    expect(finishLaterTapped, isTrue);
  });

  testWidgets('Renders correctly under 200% text scale', (tester) async {
    tester.view.physicalSize = testScreenSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          textScaler: TextScaler.linear(2.0),
          disableAnimations: true,
        ),
        child: buildTestableWidget(
          PermissionEducationOverlayWidget(
            activeCapability: PermissionCapability.deviceLocation,
            relevantCapabilities: const [PermissionCapability.deviceLocation],
            isBusy: false,
            onUseCurrentLocation: () {},
            onChooseLocationManually: () {},
            onEnableNotifications: () {},
            onDefer: () {},
            onFinishLater: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Set your weather area'), findsOneWidget);
  });
}
