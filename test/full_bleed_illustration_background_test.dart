import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/ui/full_bleed_illustration_background.dart';

void main() {
  testWidgets('asset artwork fills the viewport without blocking foreground', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FullBleedIllustrationBackground(
            key: const ValueKey('full-bleed-background'),
            illustrationAsset:
                'assets/illustrations/owntend-onboarding-hero-target.webp',
            backgroundGradient: const LinearGradient(
              colors: [Color(0xFFF8FAF5), Color(0xFFF7F9FC)],
            ),
            topFade: 0.10,
            bottomFade: 0.18,
            leftFade: 0.08,
            rightFade: 0.08,
            decorativeOverlay: const ColoredBox(
              key: ValueKey('decorative-overlay'),
              color: Color(0x1100FF00),
            ),
            scrim: const LinearGradient(
              colors: [Colors.transparent, Color(0x88FFFFFF)],
            ),
            child: Center(
              child: FilledButton(
                key: const ValueKey('foreground-action'),
                onPressed: () => taps++,
                child: const Text('Continue'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final background = find.byKey(const ValueKey('full-bleed-background'));
    expect(tester.getTopLeft(background), Offset.zero);
    expect(tester.getSize(background), const Size(360, 640));
    expect(
      find.descendant(of: background, matching: find.byType(ShaderMask)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: background, matching: find.byType(ClipRect)),
      findsNothing,
    );
    final image = tester.widget<Image>(
      find.descendant(of: background, matching: find.byType(Image)),
    );
    expect(image.fit, BoxFit.contain);

    await tester.tap(find.byKey(const ValueKey('foreground-action')));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('custom artwork uses the requested fit and alignment', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FullBleedIllustrationBackground(
          illustration: SizedBox(
            key: ValueKey('custom-illustration'),
            width: 120,
            height: 180,
          ),
          fit: BoxFit.contain,
          alignment: Alignment.topCenter,
          backgroundGradient: LinearGradient(
            colors: [Colors.white, Color(0xFFF7F9FC)],
          ),
          child: SizedBox.expand(),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('custom-illustration')), findsOneWidget);
    final fittedBox = tester.widget<FittedBox>(find.byType(FittedBox));
    expect(fittedBox.fit, BoxFit.contain);
    expect(fittedBox.alignment, Alignment.topCenter);
  });
}
