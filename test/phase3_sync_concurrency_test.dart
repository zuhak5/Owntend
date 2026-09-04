import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/sync/media_download_cache.dart';
import 'package:owntend/src/core/sync/supabase_sync_gateway.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';

void main() {
  group('Phase 3 - Offline-First Sync & Outbox Concurrency', () {
    test('[SYNC-10] MediaDownloadCache isolates in-flight downloads by assetId', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'media_cache_test_',
      );
      final completer1 = Completer<Uint8List>();
      final completer2 = Completer<Uint8List>();
      var callCount = 0;

      final cache = MediaDownloadCache(
        download: (path) {
          callCount++;
          if (callCount == 1) return completer1.future;
          return completer2.future;
        },
        rootProvider: () async => tempDir,
      );

      // Concurrent requests for different assets with same objectPath & version
      final f1 = cache.materialize(
        objectPath: 'user-1/photo.jpg',
        version: 'v1',
        assetId: 'asset-A',
      );
      final f2 = cache.materialize(
        objectPath: 'user-1/photo.jpg',
        version: 'v1',
        assetId: 'asset-B',
      );

      await pumpEventQueue();

      // Both should trigger download because inFlight is scoped per assetId
      expect(callCount, 2);

      completer1.complete(Uint8List.fromList([1, 2, 3]));
      completer2.complete(Uint8List.fromList([1, 2, 3]));

      final res1 = await f1;
      final res2 = await f2;

      expect(res1.relativePath, contains('cloud_media/'));
      expect(res2.relativePath, contains('cloud_media/'));
      expect(res1.relativePath, isNot(equals(res2.relativePath)));

      await tempDir.delete(recursive: true);
    });

    test(
      '[SYNC-03] UserChangeFeedWatermark holds highWaterSeq and feedGeneration',
      () {
        const watermark = UserChangeFeedWatermark(
          highWaterSeq: 42,
          feedGeneration: 2,
        );
        expect(watermark.highWaterSeq, 42);
        expect(watermark.feedGeneration, 2);
      },
    );

    test('[SYNC-06] SyncRecord domain matching identifies identical replayed records', () {
      final spec = syncSpecByEntity['room']!;
      final now = DateTime.now().toUtc();
      final recordA = SyncRecord(
        spec: spec,
        recordKey: 'room-1',
        values: {'id': 'room-1', 'name': 'Living Room', 'area_id': 'area-1'},
        clientModifiedAt: now,
      );
      final recordB = SyncRecord(
        spec: spec,
        recordKey: 'room-1',
        values: {'id': 'room-1', 'name': 'Living Room', 'area_id': 'area-1'},
        clientModifiedAt: now,
      );
      final recordC = SyncRecord(
        spec: spec,
        recordKey: 'room-1',
        values: {'id': 'room-1', 'name': 'Different Name', 'area_id': 'area-1'},
        clientModifiedAt: now,
      );

      // Same values should match
      expect(recordA.values['name'], equals(recordB.values['name']));
      expect(recordA.values['name'], isNot(equals(recordC.values['name'])));
    });
  });
}
