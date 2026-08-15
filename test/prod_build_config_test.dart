import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/config/app_config.dart';

void main() {
  const verifyProductionConfig = bool.fromEnvironment(
    'VERIFY_PRODUCTION_CONFIG',
  );

  test(
    'production build enables the configured Supabase project',
    () {
      final config = AppConfig.fromEnvironment();

      expect(config.environment, AppEnvironment.prod);
      expect(config.supabaseUrl.scheme, 'https');
      expect(config.supabaseUrl.host, isNotEmpty);
      expect(config.supabasePublishableKey, startsWith('sb_publishable_'));
      expect(config.googleWebClientId, endsWith('.apps.googleusercontent.com'));
      expect(config.adMobTestDeviceIds, isEmpty);
      expect(config.adConsentDebugGeography, isNull);
      expect(config.sentryEnabled, isTrue);
      expect(config.sentryDsn, isNotEmpty);
      expect(config.sentryTracesSampleRate, inInclusiveRange(0, 1));
      expect(config.redactedDescription, isNot(contains(config.sentryDsn)));
    },
    tags: 'production-config',
    skip: verifyProductionConfig
        ? false
        : 'Run with config/prod.json to validate production packaging.',
  );
}
