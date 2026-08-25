import 'local_sync_store.dart';

const _feedCursorEntity = 'server_change_feed';
const _feedResnapshotEntity = 'server_change_feed_resnapshot';

class FeedResnapshotMarker {
  const FeedResnapshotMarker({
    required this.highWaterSeq,
    required this.feedGeneration,
  });

  final int highWaterSeq;
  final int feedGeneration;
}

extension LocalSyncStoreChangeFeed on LocalSyncStore {
  Future<int?> feedResnapshotHighWater() async {
    final marker = await feedResnapshotMarker();
    return marker?.highWaterSeq;
  }

  Future<FeedResnapshotMarker?> feedResnapshotMarker() async {
    final row = await db
        .customSelect(
          "SELECT last_sync_seq, feed_generation FROM sync_cursors "
          "WHERE entity = '$_feedResnapshotEntity' LIMIT 1",
        )
        .getSingleOrNull();
    if (row == null) return null;
    return FeedResnapshotMarker(
      highWaterSeq: row.read<int>('last_sync_seq'),
      feedGeneration: row.read<int>('feed_generation'),
    );
  }

  Future<void> resetFeedCursorForResnapshot({
    required int highWaterSeq,
    int feedGeneration = 1,
  }) async {
    if (highWaterSeq < 0) {
      throw ArgumentError.value(highWaterSeq, 'highWaterSeq');
    }
    await db.transaction(() async {
      final existing = await feedResnapshotMarker();
      if (existing != null && existing.highWaterSeq != highWaterSeq) {
        throw StateError('A different feed resnapshot is already pending.');
      }
      await db.customStatement(
        '''
INSERT INTO sync_cursors(entity, last_sync_seq, last_record_key, feed_generation, high_water_seq)
VALUES ('$_feedCursorEntity', 0, NULL, ?, ?)
ON CONFLICT(entity) DO UPDATE SET
  last_sync_seq = 0,
  last_record_key = NULL,
  feed_generation = excluded.feed_generation,
  high_water_seq = excluded.high_water_seq
''',
        [feedGeneration, highWaterSeq],
      );
      await db.customStatement(
        '''
INSERT INTO sync_cursors(entity, last_sync_seq, last_record_key, feed_generation, high_water_seq)
VALUES ('$_feedResnapshotEntity', ?, NULL, ?, ?)
ON CONFLICT(entity) DO UPDATE SET
  last_sync_seq = excluded.last_sync_seq,
  last_record_key = NULL,
  feed_generation = excluded.feed_generation,
  high_water_seq = excluded.high_water_seq
''',
        [highWaterSeq, feedGeneration, highWaterSeq],
      );
    });
  }

  Future<void> completeFeedResnapshot(
    int highWaterSeq, {
    int? feedGeneration,
  }) async {
    await db.transaction(() async {
      final marker = await feedResnapshotMarker();
      if (marker == null || marker.highWaterSeq != highWaterSeq) {
        throw StateError(
          'Feed resnapshot completion does not match its marker.',
        );
      }
      final resolvedGeneration = feedGeneration ?? marker.feedGeneration;
      await db.customStatement(
        '''
INSERT INTO sync_cursors(entity, last_sync_seq, last_record_key, feed_generation, high_water_seq)
VALUES ('$_feedCursorEntity', ?, NULL, ?, ?)
ON CONFLICT(entity) DO UPDATE SET
  last_sync_seq = excluded.last_sync_seq,
  last_record_key = NULL,
  feed_generation = excluded.feed_generation,
  high_water_seq = excluded.high_water_seq
''',
        [highWaterSeq, resolvedGeneration, highWaterSeq],
      );
      await db.customStatement(
        "DELETE FROM sync_cursors WHERE entity = '$_feedResnapshotEntity'",
      );
    });
  }
}
