import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/config/app_config.dart';
import 'package:owntend/src/core/observability/observability_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test('release, dist, and base patch use package-qualified metadata', () {
    final appConfig = AppConfig.configured(
      environment: AppEnvironment.prod,
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: 'sb_publishable_example',
      googleWebClientId: '123-example.apps.googleusercontent.com',
      sentryDsn: 'https://public@example.ingest.de.sentry.io/123',
      sentryTracesSampleRate: '0.05',
    );

    final config = ObservabilityConfig.fromPackageInfo(
      appConfig,
      PackageInfo(
        appName: 'Owntend',
        packageName: 'app.owntend.mobile',
        version: '1.3.4',
        buildNumber: '19',
      ),
    );

    expect(config.enabled, isTrue);
    expect(config.environment, 'prod');
    expect(config.release, 'app.owntend.mobile@1.3.4+19');
    expect(config.dist, '19');
    expect(config.appVersion, '1.3.4');
    expect(config.shorebirdPatchNumber, 'base');
    expect(config.tracesSampleRate, 0.05);
  });

  test('current Shorebird patch number is preserved as a technical tag', () {
    final config = ObservabilityConfig.fromPackageInfo(
      AppConfig.test(),
      PackageInfo(
        appName: 'Owntend',
        packageName: 'app.owntend.mobile.dev',
        version: '1.3.4',
        buildNumber: '19',
      ),
      shorebirdPatchNumber: 7,
    );

    expect(config.shorebirdPatchNumber, '7');
  });

  test('disabled development config has no transport', () {
    final config = ObservabilityConfig.fromPackageInfo(
      AppConfig.test(),
      PackageInfo(
        appName: 'Owntend',
        packageName: 'app.owntend.mobile.dev',
        version: '1.3.4',
        buildNumber: '19',
      ),
    );

    expect(config.enabled, isFalse);
    expect(config.dsn, isEmpty);
  });
}
