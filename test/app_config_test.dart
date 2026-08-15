import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/config/app_config.dart';

void main() {
  test('test configuration supplies local Supabase placeholders', () {
    final config = AppConfig.test(environment: AppEnvironment.dev);

    expect(config.supabaseUrl.host, '127.0.0.1');
    expect(config.redactedDescription, isNot(contains('key')));
  });

  test('production configuration requires a Google Web client', () {
    final config = AppConfig.configured(
      environment: AppEnvironment.prod,
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: 'sb_publishable_example',
      googleWebClientId: '123-example.apps.googleusercontent.com',
      sentryDsn: 'https://public@example.ingest.de.sentry.io/1234567890',
    );

    expect(config.googleWebClientId, '123-example.apps.googleusercontent.com');
  });

  test('development configuration accepts ad debug settings', () {
    final config = AppConfig.configured(
      environment: AppEnvironment.dev,
      supabaseUrl: 'http://127.0.0.1:54321',
      supabasePublishableKey: 'sb_publishable_example',
      googleWebClientId: '123-example.apps.googleusercontent.com',
      adMobTestDeviceIds: 'ABCDEF1234567890,1234567890ABCDEF',
      adConsentDebugGeography: 'regulated_us_state',
    );

    expect(config.adMobTestDeviceIds, ['ABCDEF1234567890', '1234567890ABCDEF']);
    expect(
      config.adConsentDebugGeography,
      AdConsentDebugGeography.regulatedUsState,
    );
    expect(config.redactedDescription, contains('adsDebug=enabled'));
  });

  test('environment configuration fails without Supabase values', () {
    expect(AppConfig.fromEnvironment, throwsA(isA<AppConfigException>()));
  });

  test('rejects insecure hosted URLs', () {
    expect(
      () => AppConfig.configured(
        environment: AppEnvironment.prod,
        supabaseUrl: 'http://example.supabase.co',
        supabasePublishableKey: 'sb_publishable_example',
        googleWebClientId: '123-example.apps.googleusercontent.com',
        sentryDsn: 'https://public@example.ingest.de.sentry.io/1234567890',
      ),
      throwsA(isA<AppConfigException>()),
    );
  });

  test('rejects service role JWTs', () {
    final header = base64Url.encode(utf8.encode('{"alg":"HS256"}'));
    final payload = base64Url.encode(utf8.encode('{"role":"service_role"}'));
    expect(
      () => AppConfig.configured(
        environment: AppEnvironment.dev,
        supabaseUrl: 'http://127.0.0.1:54321',
        supabasePublishableKey: '$header.$payload.signature',
        googleWebClientId: '123-example.apps.googleusercontent.com',
      ),
      throwsA(isA<AppConfigException>()),
    );
  });

  test('rejects a malformed Google OAuth client ID', () {
    expect(
      () => AppConfig.configured(
        environment: AppEnvironment.prod,
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'sb_publishable_example',
        googleWebClientId: 'not-a-google-client-id',
        sentryDsn: 'https://public@example.ingest.de.sentry.io/1234567890',
      ),
      throwsA(isA<AppConfigException>()),
    );
  });

  test('production rejects ad debug settings', () {
    expect(
      () => AppConfig.configured(
        environment: AppEnvironment.prod,
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'sb_publishable_example',
        googleWebClientId: '123-example.apps.googleusercontent.com',
        adMobTestDeviceIds: 'ABCDEF1234567890',
        sentryDsn: 'https://public@example.ingest.de.sentry.io/1234567890',
      ),
      throwsA(isA<AppConfigException>()),
    );
    expect(
      () => AppConfig.configured(
        environment: AppEnvironment.prod,
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'sb_publishable_example',
        googleWebClientId: '123-example.apps.googleusercontent.com',
        adConsentDebugGeography: 'eea',
        sentryDsn: 'https://public@example.ingest.de.sentry.io/1234567890',
      ),
      throwsA(isA<AppConfigException>()),
    );
  });

  test('development disables Sentry when the DSN is empty', () {
    final config = AppConfig.configured(
      environment: AppEnvironment.dev,
      supabaseUrl: 'http://127.0.0.1:54321',
      supabasePublishableKey: 'sb_publishable_example',
      googleWebClientId: '123-example.apps.googleusercontent.com',
    );

    expect(config.sentryEnabled, isFalse);
    expect(config.sentryDsn, isEmpty);
    expect(config.sentryTracesSampleRate, 1);
    expect(config.redactedDescription, contains('sentry=disabled'));
  });

  test('production requires an enabled HTTPS Sentry ingest DSN', () {
    AppConfig build({String dsn = '', bool enabled = true}) =>
        AppConfig.configured(
          environment: AppEnvironment.prod,
          supabaseUrl: 'https://example.supabase.co',
          supabasePublishableKey: 'sb_publishable_example',
          googleWebClientId: '123-example.apps.googleusercontent.com',
          sentryDsn: dsn,
          sentryEnabled: enabled,
        );

    expect(build, throwsA(isA<AppConfigException>()));
    expect(
      () => build(
        dsn: 'https://public@example.ingest.de.sentry.io/123',
        enabled: false,
      ),
      throwsA(isA<AppConfigException>()),
    );
    expect(
      () => build(dsn: 'http://public@example.ingest.sentry.io/123'),
      throwsA(isA<AppConfigException>()),
    );
    expect(
      () => build(dsn: 'https://public@telemetry.example.com/123'),
      throwsA(isA<AppConfigException>()),
    );
  });

  test('Sentry trace rate is bounded and redacted', () {
    AppConfig build(String? rate) => AppConfig.configured(
      environment: AppEnvironment.prod,
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: 'sb_publishable_example',
      googleWebClientId: '123-example.apps.googleusercontent.com',
      sentryDsn: 'https://public@example.ingest.de.sentry.io/123',
      sentryTracesSampleRate: rate,
    );

    expect(build('0.05').sentryTracesSampleRate, 0.05);
    expect(() => build('-0.01'), throwsA(isA<AppConfigException>()));
    expect(() => build('1.01'), throwsA(isA<AppConfigException>()));
    expect(() => build('invalid'), throwsA(isA<AppConfigException>()));
    expect(build('0.05').redactedDescription, isNot(contains('public')));
  });
}
