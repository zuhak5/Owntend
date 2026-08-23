import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/config/remote_config_models.dart';
import 'package:owntend/src/core/config/remote_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RemoteConfig Model (SB-006)', () {
    test('provides safe default values', () {
      const config = RemoteConfig.defaults();
      expect(config.configVersion, equals(1));
      expect(config.adCooldownSeconds, equals(30));
      expect(config.enableWeatherAlerts, isTrue);
      expect(config.sentryTraceSampleRate, equals(0.05));
      expect(config.minSupportedBaseVersion, equals('1.0.0'));
      expect(config.remoteAssetManifestUrl, isNull);
    });

    test('parses and clamps remote JSON payload safely', () {
      final json = {
        'config_version': 2,
        'ad_cooldown_seconds': 500, // exceeds 300 -> clamp to 300
        'enable_weather_alerts': false,
        'sentry_trace_sample_rate': -0.5, // below 0 -> clamp to 0.0
        'min_supported_base_version': '1.1.0',
        'remote_asset_manifest_url': 'https://cdn.owntend.app/manifest.json',
      };

      final config = RemoteConfig.fromJson(json);
      expect(config.configVersion, equals(2));
      expect(config.adCooldownSeconds, equals(300));
      expect(config.enableWeatherAlerts, isFalse);
      expect(config.sentryTraceSampleRate, equals(0.0));
      expect(config.minSupportedBaseVersion, equals('1.1.0'));
      expect(
        config.remoteAssetManifestUrl,
        equals('https://cdn.owntend.app/manifest.json'),
      );
    });

    test('handles malformed JSON gracefully with defaults', () {
      final config = RemoteConfig.fromJsonString('invalid json {');
      expect(config.configVersion, equals(1));
      expect(config.adCooldownSeconds, equals(30));
    });
  });

  group('RemoteConfigService (SB-006)', () {
    test('fetches latest remote config successfully', () async {
      final service = RemoteConfigService(
        fetcher: () async => {'config_version': 3, 'ad_cooldown_seconds': 45},
      );

      final result = await service.fetchLatest();
      expect(result.configVersion, equals(3));
      expect(result.adCooldownSeconds, equals(45));
      expect(service.current.configVersion, equals(3));
    });

    test('falls back gracefully on network timeout', () async {
      final service = RemoteConfigService(
        fetcher: () async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return {'config_version': 99};
        },
      );

      final result = await service.fetchLatest(
        timeout: const Duration(milliseconds: 10),
      );
      expect(result.configVersion, equals(1)); // default preserved
    });

    test('falls back gracefully on network error', () async {
      final service = RemoteConfigService(
        fetcher: () async => throw StateError('network unreachable'),
      );

      final result = await service.fetchLatest();
      expect(result.configVersion, equals(1)); // default preserved
    });
  });
}
