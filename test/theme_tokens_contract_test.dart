import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/ui/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pure Dart Theme Token Contract (SB-028)', () {
    test('HkColors exposes valid ARGB colors for all semantic slots', () {
      expect(HkColors.appPrimary.toARGB32(), isNonZero);
      expect(HkColors.appBackground.toARGB32(), isNonZero);
      expect(HkColors.appSurface.toARGB32(), isNonZero);
      expect(HkColors.appDanger.toARGB32(), isNonZero);
      expect(HkColors.appWarning.toARGB32(), isNonZero);
      expect(HkColors.appInfo.toARGB32(), isNonZero);
    });

    test('HkSpacing and HkRadii tokens maintain numeric proportionality', () {
      expect(HkSpacing.base, equals(4.0));
      expect(HkSpacing.sm, equals(12.0));
      expect(HkSpacing.md, equals(16.0));
      expect(HkSpacing.lg, equals(20.0));
      expect(HkSpacing.xl, equals(24.0));

      expect(HkRadii.xs, equals(6.0));
      expect(HkRadii.sm, equals(8.0));
      expect(HkRadii.md, equals(10.0));
      expect(HkRadii.lg, equals(16.0));
      expect(HkRadii.xl, equals(22.0));
      expect(HkRadii.xxl, equals(28.0));
    });

    testWidgets('OwntendTheme light and dark themes build cleanly', (
      tester,
    ) async {
      final lightTheme = OwntendTheme.light();
      final darkTheme = OwntendTheme.dark();

      expect(lightTheme.brightness, equals(Brightness.light));
      expect(darkTheme.brightness, equals(Brightness.dark));

      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          darkTheme: darkTheme,
          home: Scaffold(
            appBar: AppBar(title: const Text('Light Theme')),
            body: Center(
              child: Container(
                padding: const EdgeInsets.all(HkSpacing.md),
                decoration: BoxDecoration(
                  color: lightTheme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(HkRadii.md),
                ),
                child: Text(
                  'Token Test',
                  style: lightTheme.textTheme.bodyMedium,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Token Test'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });
}
