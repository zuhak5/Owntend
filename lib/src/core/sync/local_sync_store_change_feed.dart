import 'local_sync_store.dart';

const _feedCursorEntity = 'server_change_feed';
const _feedResnapshotEntity = 'server_change_feed_resnapshot';

extension LocalSyncStoreChangeFeed on LocalSyncStore {
  Future<int?> feedResnapshotHighWater() async {
    final row = await db
        .customSelect(
          "SELECT last_sync_seq FROM sync_cursors "
          "WHERE entity = '$_feedResnapshotEntity' LIMIT 1",
        )
        .getSingleOrNull();
    return row?.read<int>('last_sync_seq');
  }

  Future<void> resetFeedCursorForResnapshot({
    required int highWaterSeq,
  }) async {
    if (highWaterSeq < 0) {
      throw ArgumentError.value(highWaterSeq, 'highWaterSeq');
    }
    await db.transaction(() async {
      final existing = await feedResnapshotHighWater();
      if (existing != null && existing != highWaterSeq) {
        throw StateError('A different feed resnapshot is already pending.');
      }
      await db.customStatement('''
INSERT INTO sync_cursors(entity, last_sync_seq, last_record_key)
VALUES ('$_feedCursorEntity', 0, NULL)
ON CONFLICT(entity) DO UPDATE SET
  last_sync_seq = 0,
  last_record_key = NULL
''');
      await db.customStatement(
        '''
INSERT INTO sync_cursors(entity, last_sync_seq, last_record_key)
VALUES ('$_feedResnapshotEntity', ?, NULL)
ON CONFLICT(entity) DO UPDATE SET
  last_sync_seq = excluded.last_sync_seq,
  last_record_key = NULL
''',
        [highWaterSeq],
      );
    });
  }

  Future<void> completeFeedResnapshot(int highWaterSeq) async {
    await db.transaction(() async {
      final pending = await feedResnapshotHighWater();
      if (pending != highWaterSeq) {
        throw StateError('Feed resnapshot completion does not match its marker.');
      }
      await db.customStatement(
        '''
INSERT INTO sync_cursors(entity, last_sync_seq, last_record_key)
VALUES ('$_feedCursorEntity', ?, NULL)
ON CONFLICT(entity) DO UPDATE SET
  last_sync_seq = excluded.last_sync_seq,
  last_record_key = NULL
''',
        [highWaterSeq],
      );
      await db.customStatement(
        "DELETE FROM sync_cursors WHERE entity = '$_feedResnapshotEntity'",
      );
    });
  }
}
