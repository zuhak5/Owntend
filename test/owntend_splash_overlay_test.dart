import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/owntend_animated_splash_screen.dart';

class _TestChildWidget extends StatefulWidget {
  const _TestChildWidget({this.onTap});

  final VoidCallback? onTap;

  @override
  State<_TestChildWidget> createState() => _TestChildWidgetState();
}

class _TestChildWidgetState extends State<_TestChildWidget> {
  static int initStateCallCount = 0;

  @override
  void initState() {
    super.initState();
    initStateCallCount++;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: widget.onTap,
          child: const Text('Child Button'),
        ),
      ),
    );
  }
}

class _NavObserverSpy extends NavigatorObserver {
  int pushCount = 0;
  int popCount = 0;
  int replaceCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (previousRoute != null) {
      pushCount++;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    popCount++;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    replaceCount++;
  }
}

void main() {
  setUp(() {
    _TestChildWidgetState.initStateCallCount = 0;
    resetOwntendStartupNotifiers();
  });

  testWidgets('Test 1 — App child is built immediately', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OwntendSplashOverlay(child: _TestChildWidget())),
    );

    expect(find.byType(_TestChildWidget), findsOneWidget);
    expect(find.byType(OwntendAnimatedSplashScreen), findsOneWidget);
    expect(_TestChildWidgetState.initStateCallCount, equals(1));
  });

  testWidgets('Test 2 — Splash disappears after fixed time', (tester) async {
    const display = Duration(milliseconds: 3200);
    const fadeOut = Duration(milliseconds: 250);

    await tester.pumpWidget(
      const MaterialApp(
        home: OwntendSplashOverlay(
          displayDuration: display,
          fadeOutDuration: fadeOut,
          child: _TestChildWidget(),
        ),
      ),
    );

    await tester.pump(display - const Duration(milliseconds: 100));
    expect(find.byType(OwntendAnimatedSplashScreen), findsOneWidget);

    await tester.pump(
      const Duration(milliseconds: 100) +
          fadeOut +
          const Duration(milliseconds: 50),
    );
    expect(find.byType(OwntendAnimatedSplashScreen), findsNothing);
    expect(find.byType(_TestChildWidget), findsOneWidget);
  });

  testWidgets('Test 3 — Child remains mounted', (tester) async {
    const display = Duration(milliseconds: 3200);
    const fadeOut = Duration(milliseconds: 250);

    await tester.pumpWidget(
      const MaterialApp(
        home: OwntendSplashOverlay(
          displayDuration: display,
          fadeOutDuration: fadeOut,
          child: _TestChildWidget(),
        ),
      ),
    );

    final initialElement = tester.element(find.byType(_TestChildWidget));
    await tester.pump(display + fadeOut + const Duration(milliseconds: 100));

    final finalElement = tester.element(find.byType(_TestChildWidget));
    expect(identical(initialElement, finalElement), isTrue);
    expect(_TestChildWidgetState.initStateCallCount, equals(1));
  });

  testWidgets('Test 4 — No navigation occurs', (tester) async {
    final spy = _NavObserverSpy();
    const display = Duration(milliseconds: 3200);
    const fadeOut = Duration(milliseconds: 250);

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [spy],
        home: const OwntendSplashOverlay(
          displayDuration: display,
          fadeOutDuration: fadeOut,
          child: _TestChildWidget(),
        ),
      ),
    );

    await tester.pump(display + fadeOut + const Duration(milliseconds: 100));

    expect(spy.pushCount, equals(0));
    expect(spy.popCount, equals(0));
    expect(spy.replaceCount, equals(0));
  });

  testWidgets('Test 6 — Small-screen layout', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(home: OwntendSplashOverlay(child: _TestChildWidget())),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(OwntendAnimatedSplashScreen), findsOneWidget);
  });

  testWidgets('Test 7 — Large text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(
      const MaterialApp(home: OwntendSplashOverlay(child: _TestChildWidget())),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(OwntendAnimatedSplashScreen), findsOneWidget);
  });

  testWidgets('Test 7b — Landscape at large text scale', (tester) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(
      const MaterialApp(home: OwntendSplashOverlay(child: _TestChildWidget())),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(OwntendAnimatedSplashScreen), findsOneWidget);
  });

  testWidgets('Test 8 — Interaction blocking', (tester) async {
    int tapCount = 0;
    const display = Duration(milliseconds: 3200);
    const fadeOut = Duration(milliseconds: 250);

    await tester.pumpWidget(
      MaterialApp(
        home: OwntendSplashOverlay(
          displayDuration: display,
          fadeOutDuration: fadeOut,
          child: _TestChildWidget(
            onTap: () {
              tapCount++;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
    await tester.pump();
    expect(tapCount, equals(0));

    await tester.pump(display + fadeOut + const Duration(milliseconds: 100));

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(tapCount, equals(1));
  });

  testWidgets('Test 9 — Splash does not reappear on child rebuild', (
    tester,
  ) async {
    const display = Duration(milliseconds: 3200);
    const fadeOut = Duration(milliseconds: 250);

    await tester.pumpWidget(
      const MaterialApp(
        home: OwntendSplashOverlay(
          displayDuration: display,
          fadeOutDuration: fadeOut,
          child: _TestChildWidget(),
        ),
      ),
    );

    await tester.pump(display + fadeOut + const Duration(milliseconds: 100));
    expect(find.byType(OwntendAnimatedSplashScreen), findsNothing);

    // Trigger child rebuild by pumping app with same structure
    await tester.pumpWidget(
      const MaterialApp(
        home: OwntendSplashOverlay(
          displayDuration: display,
          fadeOutDuration: fadeOut,
          child: _TestChildWidget(),
        ),
      ),
    );

    expect(find.byType(OwntendAnimatedSplashScreen), findsNothing);
  });

  testWidgets(
    'Test 10 — Early dismissal via isReadyNotifier respects minDisplayDuration',
    (tester) async {
      final readyNotifier = ValueNotifier<bool>(false);
      const minDisplay = Duration(milliseconds: 600);
      const fadeOut = Duration(milliseconds: 250);

      await tester.pumpWidget(
        MaterialApp(
          home: OwntendSplashOverlay(
            minDisplayDuration: minDisplay,
            fadeOutDuration: fadeOut,
            isReadyNotifier: readyNotifier,
            child: const _TestChildWidget(),
          ),
        ),
      );

      expect(find.byType(OwntendAnimatedSplashScreen), findsOneWidget);

      // Ready signaled early at 200ms
      await tester.pump(const Duration(milliseconds: 200));
      readyNotifier.value = true;
      await tester.pump();

      // At 400ms (elapsed 400ms < 600ms minDisplay), splash is still visible
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(OwntendAnimatedSplashScreen), findsOneWidget);

      // Advance past minDisplayDuration (600ms) + fadeOut (250ms)
      await tester.pump(const Duration(milliseconds: 500) + fadeOut);
      expect(find.byType(OwntendAnimatedSplashScreen), findsNothing);
    },
  );

  testWidgets('Test 11 — Immediate dismissal when isFailed is true', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OwntendSplashOverlay(isFailed: true, child: _TestChildWidget()),
      ),
    );

    expect(find.byType(OwntendAnimatedSplashScreen), findsNothing);
    expect(find.byType(_TestChildWidget), findsOneWidget);
  });

  testWidgets('Test 12 — Immediate dismissal when isFailedNotifier triggers', (
    tester,
  ) async {
    final failedNotifier = ValueNotifier<bool>(false);

    await tester.pumpWidget(
      MaterialApp(
        home: OwntendSplashOverlay(
          isFailedNotifier: failedNotifier,
          child: const _TestChildWidget(),
        ),
      ),
    );

    expect(find.byType(OwntendAnimatedSplashScreen), findsOneWidget);

    // Fatal failure occurs
    failedNotifier.value = true;
    await tester.pump();

    // Splash dismissed immediately without waiting for timer or fade
    expect(find.byType(OwntendAnimatedSplashScreen), findsNothing);
    expect(find.byType(_TestChildWidget), findsOneWidget);
  });

  testWidgets(
    'Test 13 — Reduced motion bypasses minDisplayDuration upon readiness',
    (tester) async {
      final readyNotifier = ValueNotifier<bool>(false);
      const minDisplay = Duration(milliseconds: 600);
      const fadeOut = Duration(milliseconds: 250);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: OwntendSplashOverlay(
              minDisplayDuration: minDisplay,
              fadeOutDuration: fadeOut,
              isReadyNotifier: readyNotifier,
              child: const _TestChildWidget(),
            ),
          ),
        ),
      );

      expect(find.byType(OwntendAnimatedSplashScreen), findsOneWidget);

      // Signaled at 100ms
      await tester.pump(const Duration(milliseconds: 100));
      readyNotifier.value = true;
      await tester.pump();

      // With disableAnimations, minDisplayDuration is Duration.zero, so fade out begins immediately.
      // Advance fadeOut + buffer
      await tester.pump(fadeOut + const Duration(milliseconds: 50));
      expect(find.byType(OwntendAnimatedSplashScreen), findsNothing);
    },
  );

  testWidgets(
    'Test 14 — Splash overlay updates listeners when notifiers change on rebuild',
    (tester) async {
      final notifier1 = ValueNotifier<bool>(false);
      final notifier2 = ValueNotifier<bool>(false);

      await tester.pumpWidget(
        MaterialApp(
          home: OwntendSplashOverlay(
            isReadyNotifier: notifier1,
            child: const _TestChildWidget(),
          ),
        ),
      );

      expect(find.byType(OwntendAnimatedSplashScreen), findsOneWidget);

      // Rebuild with new notifier
      await tester.pumpWidget(
        MaterialApp(
          home: OwntendSplashOverlay(
            isReadyNotifier: notifier2,
            child: const _TestChildWidget(),
          ),
        ),
      );

      // Old notifier trigger should not cause dismissal
      notifier1.value = true;
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(OwntendAnimatedSplashScreen), findsOneWidget);

      // New notifier trigger should trigger dismissal
      notifier2.value = true;
      await tester.pump();
      await tester.pump(
        const Duration(milliseconds: 650) +
            owntendSplashFadeOutDuration +
            const Duration(milliseconds: 50),
      );
      expect(find.byType(OwntendAnimatedSplashScreen), findsNothing);
    },
  );

  testWidgets(
    'Test 15 — Splash overlay dismisses immediately if isFailed becomes true on update',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OwntendSplashOverlay(
            isFailed: false,
            child: _TestChildWidget(),
          ),
        ),
      );

      expect(find.byType(OwntendAnimatedSplashScreen), findsOneWidget);

      // Rebuild with isFailed: true
      await tester.pumpWidget(
        const MaterialApp(
          home: OwntendSplashOverlay(isFailed: true, child: _TestChildWidget()),
        ),
      );

      // Immediately dismissed without fade delay
      expect(find.byType(OwntendAnimatedSplashScreen), findsNothing);
      expect(find.byType(_TestChildWidget), findsOneWidget);
    },
  );
}
