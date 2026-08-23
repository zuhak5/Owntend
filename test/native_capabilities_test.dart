import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/services/native_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeCapabilitySnapshot', () {
    test('parses full capability map correctly', () {
      final snapshot = NativeCapabilitySnapshot.fromMap({
        'shellVersion': 2,
        'capabilities': {'systemUi': 2, 'nativeAds': 2, 'platformEnv': 1},
      });

      expect(snapshot.shellVersion, equals(2));
      expect(snapshot.supports('systemUi', minVersion: 2), isTrue);
      expect(snapshot.supports('systemUi', minVersion: 3), isFalse);
      expect(snapshot.supports('nativeAds', minVersion: 2), isTrue);
      expect(snapshot.supports('platformEnv', minVersion: 1), isTrue);
      expect(snapshot.supports('unknownFeature'), isFalse);
    });

    test('falls back safely when input map is null or malformed', () {
      final fallback = NativeCapabilitySnapshot.fromMap(null);
      expect(fallback.shellVersion, equals(1));
      expect(fallback.supports('systemUi', minVersion: 1), isTrue);
      expect(fallback.supports('systemUi', minVersion: 2), isFalse);
    });
  });

  group('NativeCapabilities service', () {
    const channel = MethodChannel('owntend/capabilities');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('returns live capabilities when channel is available', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getCapabilities') {
              return {
                'shellVersion': 2,
                'capabilities': {'systemUi': 2, 'nativeAds': 2},
              };
            }
            if (call.method == 'getTimeZoneId') {
              return 'Asia/Baghdad';
            }
            return null;
          });

      final service = NativeCapabilities(channel: channel);
      final snapshot = await service.getInfo();
      expect(snapshot.shellVersion, equals(2));
      expect(snapshot.supports('systemUi', minVersion: 2), isTrue);
    });

    test('falls back safely on MissingPluginException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw MissingPluginException();
          });

      final service = NativeCapabilities(channel: channel);
      final snapshot = await service.getInfo();
      expect(snapshot.shellVersion, equals(1));
      expect(snapshot.supports('systemUi', minVersion: 1), isTrue);
    });
  });
}
