import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/ui/app_theme.dart';

import 'test_theme.dart';

void main() {
  testWidgets('Settings row grid aligns comparable content in LTR and RTL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final locale in const [Locale('en'), Locale('ar')]) {
      await tester.pumpWidget(_GridHost(locale: locale));
      await tester.pumpAndSettle();

      final direction = locale.languageCode == 'ar'
          ? TextDirection.rtl
          : TextDirection.ltr;
      final viewportWidth = tester.view.physicalSize.width;
      final iconStarts = [
        _logicalCenter(
          tester.getRect(find.byKey(const ValueKey('grid-language-icon'))),
          viewportWidth,
          direction,
        ),
        _logicalCenter(
          tester.getRect(find.byKey(const ValueKey('grid-weather-icon'))),
          viewportWidth,
          direction,
        ),
        _logicalCenter(
          tester.getRect(find.byKey(const ValueKey('grid-alerts-icon'))),
          viewportWidth,
          direction,
        ),
      ];
      final textStarts = [
        _logicalStart(
          tester.getRect(find.byKey(const ValueKey('grid-language-title'))),
          viewportWidth,
          direction,
        ),
        _logicalStart(
          tester.getRect(find.byKey(const ValueKey('grid-weather-title'))),
          viewportWidth,
          direction,
        ),
        _logicalStart(
          tester.getRect(find.byKey(const ValueKey('grid-alerts-title'))),
          viewportWidth,
          direction,
        ),
      ];

      expect(_spread(iconStarts), lessThanOrEqualTo(1));
      expect(_spread(textStarts), lessThanOrEqualTo(1));
      expect(
        textStarts.first - iconStarts.first,
        closeTo(
          SettingsRowGrid.leadingWidth / 2 +
              SettingsRowGrid.iconToTextGap,
          1,
        ),
      );
      expect(
        Directionality.of(
          tester.element(find.byKey(const ValueKey('grid-alerts-row'))),
        ),
        direction,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'Settings grid preserves controls on narrow elevated-scale LTR and RTL',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final locale in const [Locale('en'), Locale('ar')]) {
        var enabled = false;
        await tester.pumpWidget(
          _GridHost(
            locale: locale,
            textScale: 1.8,
            onAlertsChanged: (value) => enabled = value,
          ),
        );
        await tester.pumpAndSettle();

        final alerts = find.byKey(const ValueKey('grid-alerts-row'));
        final weatherAction = find.byKey(
          const ValueKey('grid-weather-action'),
        );
        expect(tester.getSize(alerts).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(weatherAction).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(weatherAction).height, greaterThanOrEqualTo(48));

        await tester.tap(alerts);
        await tester.pump();
        expect(enabled, isTrue);
        expect(tester.takeException(), isNull);
      }
    },
  );

  test('Settings screen applies the grid without reviving physical offsets', () {
    final source = File(
      'lib/src/features/settings/presentation/settings_screen.dart',
    ).readAsStringSync();

    expect(source, contains('SettingsRowGrid('));
    expect(source, contains("ValueKey('settings-weather-row')"));
    expect(source, contains("ValueKey('settings-alerts-row')"));
    expect(source, contains('_SettingsPlainIcon('));
    expect(source, contains('EdgeInsetsDirectional.only('));
    expect(source, isNot(contains('indent: 52')));
    expect(
      SettingsRowGrid.contentInset,
      HkSpacing.md + HkSpacing.space4,
    );
  });
}

double _logicalCenter(Rect rect, double width, TextDirection direction) {
  return direction == TextDirection.ltr ? rect.center.dx : width - rect.center.dx;
}

double _logicalStart(Rect rect, double width, TextDirection direction) {
  return direction == TextDirection.ltr ? rect.left : width - rect.right;
}

double _spread(List<double> values) {
  final sorted = [...values]..sort();
  return sorted.last - sorted.first;
}

class _GridHost extends StatelessWidget {
  const _GridHost({
    required this.locale,
    this.textScale = 1,
    this.onAlertsChanged,
  });

  final Locale locale;
  final double textScale;
  final ValueChanged<bool>? onAlertsChanged;

  @override
  Widget build(BuildContext context) {
    final rtl = locale.languageCode == 'ar';
    return MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: testLightTheme(),
      home: Builder(
        builder: (context) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: SettingsRowGrid(
                child: ListView(
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: SettingsRowGrid.contentInset,
                        vertical: HkSpacing.xs,
                      ),
                      child: Row(
                        children: [
                          const _GridIcon(
                            key: ValueKey('grid-language-icon'),
                            icon: Icons.language,
                          ),
                          const SizedBox(
                            width: SettingsRowGrid.iconToTextGap,
                          ),
                          Expanded(
                            child: Text(
                              rtl ? 'اللغة' : 'Language',
                              key: const ValueKey('grid-language-title'),
                            ),
                          ),
                          const SizedBox(width: 48, height: 48),
                        ],
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsetsDirectional.symmetric(
                        horizontal: SettingsRowGrid.contentInset,
                      ),
                      leading: const _GridIcon(
                        key: ValueKey('grid-weather-icon'),
                        icon: Icons.location_on_outlined,
                      ),
                      title: Text(
                        rtl ? 'موقع الطقس' : 'Weather location',
                        key: const ValueKey('grid-weather-title'),
                      ),
                      subtitle: Text(
                        rtl
                            ? 'تعيين مدينة أو رمز بريدي أو موقع الجهاز الحالي'
                            : 'Set a city, ZIP, or current device location',
                      ),
                      trailing: IconButton(
                        key: const ValueKey('grid-weather-action'),
                        tooltip: rtl ? 'بحث' : 'Search location',
                        onPressed: () {},
                        icon: const Icon(Icons.search),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: HkSpacing.md,
                      ),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: HkSpacing.space4,
                        ),
                        child: SwitchListTile(
                          key: const ValueKey('grid-alerts-row'),
                          contentPadding: EdgeInsets.zero,
                          secondary: const _GridIcon(
                            key: ValueKey('grid-alerts-icon'),
                            icon: Icons.notifications_active_outlined,
                          ),
                          title: Text(
                            rtl ? 'تنبيهات Owntend' : 'Owntend alerts',
                            key: const ValueKey('grid-alerts-title'),
                          ),
                          subtitle: Text(
                            rtl
                                ? 'تلقي تذكيرات المهام وتحديثات الطقس'
                                : 'Receive task reminders and weather updates',
                          ),
                          value: false,
                          onChanged: onAlertsChanged ?? (_) {},
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GridIcon extends StatelessWidget {
  const _GridIcon({required this.icon, super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: SettingsRowGrid.leadingWidth,
      child: Center(child: Icon(icon)),
    );
  }
}
