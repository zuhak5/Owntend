import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/services/remote_asset_service.dart';
import 'package:owntend/src/ui/widgets/remote_or_bundled_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late RemoteAssetService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('remote_asset_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('RemoteAssetService (SB-007)', () {
    test('parses asset manifest correctly', () {
      final json = {
        'version': 1,
        'assets': [
          {
            'key': 'sounds/chime.wav',
            'url': 'https://cdn.owntend.app/sounds/chime.wav',
            'sha256': 'aabbccdd',
            'size_bytes': 1024,
          },
        ],
      };

      final manifest = RemoteAssetManifest.fromJson(json);
      expect(manifest.version, equals(1));
      expect(manifest.assets.containsKey('sounds/chime.wav'), isTrue);
      expect(manifest.assets['sounds/chime.wav']!.sha256, equals('aabbccdd'));
    });

    test('downloads and verifies valid asset with SHA-256 integrity', () async {
      final sampleBytes = Uint8List.fromList(utf8.encode('test-audio-content'));
      final sampleHash = sha256.convert(sampleBytes).toString();

      service = RemoteAssetService(
        cacheDirectory: tempDir,
        downloader: (url) async => sampleBytes,
      );

      final entry = RemoteAssetEntry(
        key: 'sounds/chime.wav',
        url: 'https://cdn.owntend.app/sounds/chime.wav',
        sha256: sampleHash,
        sizeBytes: sampleBytes.length,
      );

      final result = await service.downloadAndVerifyAsset(entry);
      expect(result, isNotNull);
      expect(await result!.exists(), isTrue);

      final cachedPath = await service.getCachedAssetPath('sounds/chime.wav');
      expect(cachedPath, equals(result.path));
    });

    test('rejects asset on SHA-256 hash mismatch', () async {
      final sampleBytes = Uint8List.fromList(utf8.encode('actual-content'));
      const badHash =
          '0000000000000000000000000000000000000000000000000000000000000000';

      service = RemoteAssetService(
        cacheDirectory: tempDir,
        downloader: (url) async => sampleBytes,
      );

      final entry = RemoteAssetEntry(
        key: 'sounds/bad.wav',
        url: 'https://cdn.owntend.app/sounds/bad.wav',
        sha256: badHash,
        sizeBytes: sampleBytes.length,
      );

      final result = await service.downloadAndVerifyAsset(entry);
      expect(result, isNull);
    });

    test('rejects asset exceeding 5MB max size limit', () async {
      service = RemoteAssetService(
        cacheDirectory: tempDir,
        downloader: (url) async => Uint8List(0),
      );

      final entry = RemoteAssetEntry(
        key: 'large.zip',
        url: 'https://cdn.owntend.app/large.zip',
        sha256: 'somehash',
        sizeBytes: 6 * 1024 * 1024, // 6MB
      );

      final result = await service.downloadAndVerifyAsset(entry);
      expect(result, isNull);
    });
  });

  group('RemoteOrBundledImage Widget (SB-007)', () {
    testWidgets('constructs and mounts correctly with parameters', (
      tester,
    ) async {
      const widget = RemoteOrBundledImage(
        assetPath: 'assets/brand/logo.png',
        cachedRemotePath: null,
        width: 100,
        height: 100,
        fit: BoxFit.contain,
        semanticLabel: 'Logo',
      );

      expect(widget.assetPath, equals('assets/brand/logo.png'));
      expect(widget.width, equals(100));
      expect(widget.height, equals(100));
      expect(widget.fit, equals(BoxFit.contain));
      expect(widget.semanticLabel, equals('Logo'));
    });
  });
}
