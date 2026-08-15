import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/owntend_animated_splash_screen.dart';
import 'package:owntend/l10n/app_localizations.dart';

class _BranchHost extends StatefulWidget {
  const _BranchHost({required this.branch});

  final ValueNotifier<int> branch;

  @override
  State<_BranchHost> createState() => _BranchHostState();
}

class _BranchHostState extends State<_BranchHost> {
  static int initCount = 0;

  @override
  void initState() {
    super.initState();
    initCount++;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.branch,
      builder: (context, branch, _) {
        return ColoredBox(
          key: ValueKey<String>('branch-$branch'),
          color: Colors.white,
          child: Center(
            child: Semantics(
              label: 'underlying branch $branch',
              child: Text('Branch $branch'),
            ),
          ),
        );
      },
    );
  }
}

void main() {
  setUp(() {
    _BranchHostState.initCount = 0;
  });

  testWidgets('first Flutter frame contains the process splash', (
    tester,
  ) async {
    final branch = ValueNotifier<int>(0);
    addTearDown(branch.dispose);

    await tester.pumpWidget(
      OwntendProcessSplash(child: _BranchHost(branch: branch)),
    );

    expect(find.byType(OwntendProcessSplash), findsOneWidget);
    expect(find.byType(OwntendSplashOverlay), findsOneWidget);
    expect(find.byType(OwntendAnimatedSplashScreen), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('branch-0')), findsOneWidget);
    expect(_BranchHostState.initCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup branch changes do not reset the process timer', (
    tester,
  ) async {
    const display = Duration(milliseconds: 400);
    const fade = Duration(milliseconds: 100);
    final branch = ValueNotifier<int>(0);
    addTearDown(branch.dispose);

    await tester.pumpWidget(
      OwntendProcessSplash(
        displayDuration: display,
        fadeOutDuration: fade,
        child: _BranchHost(branch: branch),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    branch.value = 1;
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('branch-1')), findsOneWidget);
    expect(find.byType(OwntendAnimatedSplashScreen), findsOneWidget);
    expect(_BranchHostState.initCount, 1);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(fade);
    expect(find.byType(OwntendAnimatedSplashScreen), findsNothing);
    expect(find.byKey(const ValueKey<String>('branch-1')), findsOneWidget);

    branch.value = 2;
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('branch-2')), findsOneWidget);
    expect(find.byType(OwntendAnimatedSplashScreen), findsNothing);
    expect(_BranchHostState.initCount, 1);
  });

  testWidgets('failure content remains beneath the same fixed splash', (
    tester,
  ) async {
    const display = Duration(milliseconds: 300);
    const fade = Duration(milliseconds: 50);

    await tester.pumpWidget(
      const OwntendProcessSplash(
        displayDuration: display,
        fadeOutDuration: fade,
        child: MaterialApp(home: Scaffold(body: Text('Startup failed safely'))),
      ),
    );

    expect(find.text('Startup failed safely'), findsOneWidget);
    expect(find.byType(OwntendAnimatedSplashScreen), findsOneWidget);

    await tester.pump(display + fade);
    expect(find.byType(OwntendAnimatedSplashScreen), findsNothing);
    expect(find.text('Startup failed safely'), findsOneWidget);
  });

  testWidgets(
    'splash exposes one Arabic announcement and blocks child semantics',
    (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('ar');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final semantics = tester.ensureSemantics();
      final arabic = lookupAppLocalizations(const Locale('ar'));

      await tester.pumpWidget(
        OwntendProcessSplash(
          displayDuration: const Duration(milliseconds: 300),
          fadeOutDuration: const Duration(milliseconds: 50),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Semantics(
              label: 'underlying content',
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(arabic.startupStartingOwntend),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('underlying content'), findsNothing);
      expect(
        tester
            .widget<Directionality>(find.byType(Directionality).first)
            .textDirection,
        TextDirection.rtl,
      );

      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.bySemanticsLabel(arabic.startupStartingOwntend),
        findsNothing,
      );
      expect(find.bySemanticsLabel('underlying content'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('reduced motion leaves no repeating splash animation', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      const OwntendProcessSplash(
        displayDuration: Duration(seconds: 3),
        child: SizedBox.expand(),
      ),
    );
    await tester.pump();

    expect(find.byType(OwntendAnimatedSplashScreen), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
