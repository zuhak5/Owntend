import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _paletteKeys = <String>[
  'backgroundColor',
  'borderColor',
  'headlineColor',
  'bodyColor',
  'advertiserColor',
  'sponsoredColor',
  'adBadgeBackgroundColor',
  'adBadgeTextColor',
  'callToActionBackgroundColor',
  'callToActionTextColor',
];

void main() {
  test('Flutter and Android share the complete schema-v2 palette contract', () {
    final flutter = File('lib/src/features/monetization/monetization.dart')
        .readAsStringSync();
    final kotlin = File(
      'android/app/src/main/kotlin/app/owntend/mobile/'
      'OwntendNativeAdFactory.kt',
    ).readAsStringSync();

    expect(flutter, contains("'schemaVersion': 2"));
    expect(kotlin, contains('private const val SCHEMA_VERSION = 2'));
    for (final key in _paletteKeys) {
      expect(flutter, contains("'$key'"), reason: 'Flutter must emit $key.');
      expect(kotlin, contains('"$key"'), reason: 'Android must consume $key.');
    }
    expect(kotlin, isNot(contains('customOptions?.get("textColor")')));
  });

  test('factory validates and applies one complete palette before binding', () {
    final kotlin = File(
      'android/app/src/main/kotlin/app/owntend/mobile/'
      'OwntendNativeAdFactory.kt',
    ).readAsStringSync();

    final validation = kotlin.indexOf(
      'NativeAdPalette.fromOptions(customOptions)',
    );
    final fallback = kotlin.indexOf(
      'NativeAdPalette.fromResources(context)',
      validation,
    );
    final application = kotlin.indexOf('applyPalette(', fallback);
    final binding = kotlin.indexOf('view.setNativeAd(nativeAd)', application);

    expect(validation, greaterThanOrEqualTo(0));
    expect(fallback, greaterThan(validation));
    expect(application, greaterThan(fallback));
    expect(binding, greaterThan(application));
    expect(kotlin, contains(r'Regex("^#[0-9A-Fa-f]{6}$"'));
    expect(kotlin, contains('Color.parseColor(encoded)'));
    expect(kotlin, contains('catch (_: IllegalArgumentException)'));
    expect(kotlin, contains('GradientDrawable'));
    expect(kotlin, contains('setStroke('));
    expect(kotlin, contains('cornerRadius = dp(cornerRadiusDp)'));
    expect(kotlin, isNot(contains('view.setBackgroundColor(')));
    expect(kotlin, isNot(contains('android.util.Log')));
    expect(kotlin, isNot(contains('println(')));
  });

  test(
    'factory preserves registered creative assets and hides absent data',
    () {
      final kotlin = File(
        'android/app/src/main/kotlin/app/owntend/mobile/'
        'OwntendNativeAdFactory.kt',
      ).readAsStringSync();
      final layout = File(
        'android/app/src/main/res/layout/owntend_native_ad.xml',
      ).readAsStringSync();

      for (final registration in const [
        'view.iconView = icon',
        'view.headlineView = headline',
        'view.bodyView = body',
        'view.advertiserView = advertiser',
        'view.callToActionView = callToAction',
        'view.adChoicesView = adChoices',
      ]) {
        expect(kotlin, contains(registration));
      }
      expect(kotlin, contains('body.bindOptional(nativeAd.body)'));
      expect(kotlin, contains('advertiser.bindOptional(nativeAd.advertiser)'));
      expect(
        kotlin,
        contains('callToAction.bindOptional(nativeAd.callToAction)'),
      );
      expect(kotlin, contains('icon.setImageDrawable(null)'));
      expect(kotlin, contains('View.GONE'));
      expect(layout, contains('@+id/owntend_ad_badge'));
      expect(layout, contains('@+id/owntend_ad_sponsored'));
      expect(layout, contains('@+id/owntend_ad_choices'));
      expect(layout, contains('android:paddingStart="12dp"'));
      expect(layout, contains('android:paddingEnd="12dp"'));
    },
  );

  test('system fallback resources provide complete light and dark chrome', () {
    final light = File('android/app/src/main/res/values/colors.xml')
        .readAsStringSync();
    final dark = File('android/app/src/main/res/values-night/colors.xml')
        .readAsStringSync();
    final background = File(
      'android/app/src/main/res/drawable/owntend_native_ad_background.xml',
    ).readAsStringSync();
    final badge = File(
      'android/app/src/main/res/drawable/owntend_native_ad_badge.xml',
    ).readAsStringSync();
    final cta = File(
      'android/app/src/main/res/drawable/owntend_native_ad_cta.xml',
    ).readAsStringSync();

    for (final resource in const [
      'owntend_ad_surface',
      'owntend_ad_border',
      'owntend_ad_text_primary',
      'owntend_ad_text_secondary',
      'owntend_ad_badge_background',
      'owntend_ad_badge_text',
      'owntend_ad_cta_background',
      'owntend_ad_cta_text',
    ]) {
      expect(light, contains('name="$resource"'));
      expect(dark, contains('name="$resource"'));
    }
    expect(background, contains('@color/owntend_ad_surface'));
    expect(background, contains('@color/owntend_ad_border'));
    expect(background, contains('<stroke'));
    expect(background, contains('<corners'));
    expect(badge, contains('@color/owntend_ad_badge_background'));
    expect(badge, contains('@color/owntend_ad_badge_text'));
    expect(cta, contains('@color/owntend_ad_cta_background'));
  });

  test('native ads are constructed only through the shared component', () {
    final constructorOwners = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (RegExp(r'\bNativeAd\s*\(').hasMatch(entity.readAsStringSync())) {
        constructorOwners.add(entity.path.replaceAll('\\', '/'));
      }
    }

    expect(constructorOwners, [
      'lib/src/features/monetization/monetization.dart',
    ]);
  });

  test('every routed content screen declares a native ad placement', () {
    final sources = [
      File('lib/main.dart').readAsStringSync(),
      for (final entity in Directory('lib/src').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          entity.readAsStringSync(),
    ].join('\n');
    for (final placement in const [
      'home',
      'assets',
      'room_detail',
      'thing_detail',
      'task_detail',
      'maintenance',
      'calendar',
      'more',
      'search',
      'trash',
      'statistics',
      'account',
      'backup',
      'notifications',
      'settings',
      'permission_setup',
    ]) {
      expect(
        sources,
        contains("placement: '$placement'"),
        reason: 'Missing native ad placement for $placement.',
      );
    }
  });

  test('mounted native ads enforce the shared cache expiry deadline', () {
    final flutter = File('lib/src/features/monetization/monetization.dart')
        .readAsStringSync();

    expect(flutter, contains('Timer? _expiryTimer;'));
    expect(flutter, contains('_expiryTimer = Timer(kAdCacheMaxAge'));
    expect(flutter, contains('!identical(_displayLease, lease)'));
    expect(flutter, contains('_displayLease = null;'));
    expect(flutter, contains('lease.release();'));
    expect(flutter, contains('if (shouldReload) _scheduleSynchronize();'));
    expect(
      RegExp(r'_expiryTimer\?\.cancel\(\);').allMatches(flutter).length,
      greaterThanOrEqualTo(3),
      reason: 'Expiry must be cancelled on dispose, replacement, and teardown.',
    );
  });

  test('permission education tears down native ads before overlays', () {
    final dashboard = [
      File('lib/main.dart').readAsStringSync(),
      for (final entity in Directory('lib/src').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          entity.readAsStringSync(),
    ].join('\n');

    expect(
      dashboard,
      contains('next.isVisible && next.activeCapability != null'),
    );
    expect(dashboard, contains('deferProviderUpdate: true'));
    expect(
      dashboard,
      contains('onChooseLocationManually: () => runWithNativeAdsSuspended('),
    );
  });

  test('app-ads.txt contains the authoritative publisher declaration', () {
    final appAds = File('download-site/app-ads.txt').readAsStringSync();
    expect(
      appAds,
      contains('google.com, pub-5274007212820203, DIRECT, f08c47fec0942fa0'),
    );
  });

  test(
    'Android ProGuard rules keep Google Mobile Ads and Native Ad Factory',
    () {
      final proguard = File('android/app/proguard-rules.pro')
          .readAsStringSync();
      expect(
        proguard,
        contains('-keep class com.google.android.gms.ads.** { *; }'),
      );
      expect(
        proguard,
        contains('-keep class com.google.ads.mediation.** { *; }'),
      );
      expect(
        proguard,
        contains(
          '-keep class app.owntend.mobile.OwntendNativeAdFactory { *; }',
        ),
      );
    },
  );
}
