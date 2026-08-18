import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/ui/components.dart' as hk_ui;

import 'test_theme.dart';

void main() {
  testWidgets(
    'selector matches anchor geometry and exposes open state in LTR',
    (tester) async {
      await tester.pumpWidget(
        const _SelectorHost(initialLanguage: AppLanguage.en, width: 240),
      );
      await tester.pumpAndSettle();

      final anchor = find.byKey(const ValueKey('test-language-hit-target'));
      final anchorRect = tester.getRect(anchor);
      expect(_chevron(tester).turns, 0);

      await tester.tap(anchor);
      await tester.pumpAndSettle();

      final english = find.byKey(const ValueKey('language-option-en'));
      final englishLabel = find.byKey(
        const ValueKey('language-option-label-en'),
      );
      final englishCheck = find.byKey(
        const ValueKey('language-option-check-en'),
      );
      final arabicCheck = find.byKey(
        const ValueKey('language-option-check-ar'),
      );
      expect(english, findsOneWidget);
      expect(englishCheck, findsOneWidget);
      expect(arabicCheck, findsNothing);
      expect(_chevron(tester).turns, 0.5);

      final menuRect = tester.getRect(english);
      expect((menuRect.width - anchorRect.width).abs(), lessThanOrEqualTo(1));
      expect(menuRect.top, greaterThanOrEqualTo(anchorRect.bottom + 5));
      expect((menuRect.left - anchorRect.left).abs(), lessThanOrEqualTo(1));
      expect(
        (tester.getRect(englishLabel).center.dx - menuRect.center.dx).abs(),
        lessThanOrEqualTo(1),
      );
      expect(
        tester.getRect(englishCheck).center.dx,
        lessThan(tester.getRect(englishLabel).center.dx),
      );

      await tester.tapAt(const Offset(8, 560));
      await tester.pumpAndSettle();
      expect(english, findsNothing);
      expect(_chevron(tester).turns, 0);
    },
  );

  testWidgets(
    'selector mirrors directional indicator and changes locale in RTL',
    (tester) async {
      AppLanguage? selected;
      await tester.pumpWidget(
        _SelectorHost(
          initialLanguage: AppLanguage.ar,
          width: 240,
          onChanged: (value) => selected = value,
        ),
      );
      await tester.pumpAndSettle();

      final anchor = find.byKey(const ValueKey('test-language-hit-target'));
      expect(Directionality.of(tester.element(anchor)), TextDirection.rtl);
      final anchorRect = tester.getRect(anchor);

      await tester.tap(anchor);
      await tester.pumpAndSettle();

      final arabic = find.byKey(const ValueKey('language-option-ar'));
      final arabicLabel = find.byKey(
        const ValueKey('language-option-label-ar'),
      );
      final arabicCheck = find.byKey(
        const ValueKey('language-option-check-ar'),
      );
      final menuRect = tester.getRect(arabic);
      expect((menuRect.right - anchorRect.right).abs(), lessThanOrEqualTo(1));
      expect(
        (tester.getRect(arabicLabel).center.dx - menuRect.center.dx).abs(),
        lessThanOrEqualTo(1),
      );
      expect(
        tester.getRect(arabicCheck).center.dx,
        greaterThan(tester.getRect(arabicLabel).center.dx),
      );

      await tester.tap(find.byKey(const ValueKey('language-option-en')));
      await tester.pumpAndSettle();

      expect(selected, AppLanguage.en);
      expect(find.byKey(const ValueKey('language-option-en')), findsNothing);
      expect(
        Directionality.of(
          tester.element(find.byKey(const ValueKey('test-language-hit-target'))),
        ),
        TextDirection.ltr,
      );
    },
  );

  testWidgets('system back closes the menu without replacing the route', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _SelectorHost(initialLanguage: AppLanguage.en, width: 220),
    );
    await tester.pumpAndSettle();

    final anchor = find.byKey(const ValueKey('test-language-hit-target'));
    await tester.tap(anchor);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('language-option-en')), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.byKey(const ValueKey('language-option-en')), findsNothing);
    expect(anchor, findsOneWidget);
    expect(_chevron(tester).turns, 0);
  });

  testWidgets('narrow viewport and elevated text scale do not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(180, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const _SelectorHost(
        initialLanguage: AppLanguage.en,
        width: 156,
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();

    final anchor = find.byKey(const ValueKey('test-language-hit-target'));
    await tester.tap(anchor);
    await tester.pumpAndSettle();

    final menu = find.byKey(const ValueKey('language-option-en'));
    expect(
      (tester.getSize(menu).width - tester.getSize(anchor).width).abs(),
      lessThanOrEqualTo(1),
    );
    expect(tester.takeException(), isNull);
  });

  test('Settings and onboarding both use the shared language selector', () {
    final settings = File(
      'lib/src/features/settings/presentation/settings_screen.dart',
    ).readAsStringSync();
    final onboarding = File(
      'lib/src/features/auth/presentation/authentication_gate.dart',
    ).readAsStringSync();

    expect(settings, contains('hk_ui.LanguageSelectorDropdown('));
    expect(settings, isNot(contains('PopupMenuButton<AppLanguage>')));
    expect(onboarding, contains('hk_ui.LanguageSelectorDropdown('));
  });
}

AnimatedRotation _chevron(WidgetTester tester) {
  return tester.widget<AnimatedRotation>(
    find.byKey(const ValueKey('language-selector-chevron')),
  );
}

class _SelectorHost extends StatefulWidget {
  const _SelectorHost({
    required this.initialLanguage,
    required this.width,
    this.textScale = 1,
    this.onChanged,
  });

  final AppLanguage initialLanguage;
  final double width;
  final double textScale;
  final ValueChanged<AppLanguage>? onChanged;

  @override
  State<_SelectorHost> createState() => _SelectorHostState();
}

class _SelectorHostState extends State<_SelectorHost> {
  late AppLanguage _language = widget.initialLanguage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: Locale(_language.name),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: testLightTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(widget.textScale),
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: widget.width,
                  child: hk_ui.LanguageSelectorDropdown(
                    selectorKey: const ValueKey('test-language-selector'),
                    hitTargetKey: const ValueKey('test-language-hit-target'),
                    language: _language,
                    onChanged: (value) {
                      widget.onChanged?.call(value);
                      setState(() => _language = value);
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
