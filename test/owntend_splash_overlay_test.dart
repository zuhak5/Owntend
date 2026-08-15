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
}
