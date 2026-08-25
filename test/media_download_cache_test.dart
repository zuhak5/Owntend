import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/sync/media_download_cache.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('owntend-media-test-');
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test(
    'concurrent identical requests share one download and then hit cache',
    () async {
      var downloads = 0;
      final gate = Completer<Uint8List>();
      final downloadStarted = Completer<void>();
      final cache = MediaDownloadCache(
        download: (_) {
          downloads++;
          downloadStarted.complete();
          return gate.future;
        },
        rootProvider: () async => temporary,
      );

      final first = cache.materialize(
        objectPath: 'user/media/photo.jpg',
        version: '1',
        assetId: 'asset-a',
      );
      final second = cache.materialize(
        objectPath: 'user/media/photo.jpg',
        version: '1',
        assetId: 'asset-a',
      );
      await downloadStarted.future;
      expect(downloads, 1);
      gate.complete(Uint8List.fromList([1, 2, 3]));

      final results = await Future.wait([first, second]);
      expect(results[0].relativePath, results[1].relativePath);
      expect(downloads, 1);

      final cached = await cache.materialize(
        objectPath: 'user/media/photo.jpg',
        version: '1',
        assetId: 'asset-a',
      );
      expect(cached.cacheHit, isTrue);
      expect(downloads, 1);
    },
  );

  test('a changed version uses a new cache entry', () async {
    var downloads = 0;
    final cache = MediaDownloadCache(
      download: (_) async {
        downloads++;
        return Uint8List.fromList([downloads]);
      },
      rootProvider: () async => temporary,
    );

    final first = await cache.materialize(
      objectPath: 'user/media/photo.jpg',
      version: '1',
      assetId: 'asset-a',
    );
    final second = await cache.materialize(
      objectPath: 'user/media/photo.jpg',
      version: '2',
      assetId: 'asset-a',
    );

    expect(downloads, 2);
    expect(second.relativePath, isNot(first.relativePath));
  });

  test('failure removes partial files and permits retry', () async {
    var downloads = 0;
    final cache = MediaDownloadCache(
      download: (_) async {
        downloads++;
        if (downloads == 1) throw StateError('network failed');
        return Uint8List.fromList([9]);
      },
      rootProvider: () async => temporary,
    );

    await expectLater(
      cache.materialize(
        objectPath: 'user/media/photo.jpg',
        version: '1',
        assetId: 'asset-a',
      ),
      throwsStateError,
    );
    expect(
      temporary
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.contains('.part-')),
      isEmpty,
    );

    final retried = await cache.materialize(
      objectPath: 'user/media/photo.jpg',
      version: '1',
      assetId: 'asset-a',
    );
    expect(downloads, 2);
    expect(retried.cacheHit, isFalse);
  });
}
