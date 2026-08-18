import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/supabase/supabase_failure.dart';
import 'package:owntend/src/core/sync/change_feed_contract.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/local_sync_store_change_feed.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';

void main() {
  group('ENV-001/002 change-feed wire contract', () {
    test('every client sync entity has one strict feed identifier and key set', () {
      final specs = [...syncEntitySpecs, profileSyncSpec];
      expect(specs.map((spec) => spec.entity).toSet().length, specs.length);

      for (final spec in specs) {
        final keyData = <String, dynamic>{
          for (final column in spec.keyColumns) column: 'value-$column',
        };
        final recordKey = spec.keyColumns.isEmpty
            ? spec.entity
            : spec.keyColumns.map((column) => keyData[column]).join('|');
        final parsed = parseSyncFeedChange({
          'entity_type': spec.entity,
          'record_id': recordKey,
          'op_type': 'DELETE',
          'key_data': keyData,
        });

        expect(parsed.spec, same(spec));
        expect(parsed.recordKey, recordKey);
        expect(parsed.keyValues, keyData);
      }
    });

    test('composite key JSON order does not change canonical record key', () {
      final parsed = parseSyncFeedChange({
        'entity_type': 'asset_tag',
        'record_id': 'asset-1|tag-1',
        'op_type': 'DELETE',
        'key_data': {'tag_id': 'tag-1', 'asset_id': 'asset-1'},
      });

      expect(parsed.recordKey, 'asset-1|tag-1');
      expect(parsed.keyValues, {'asset_id': 'asset-1', 'tag_id': 'tag-1'});
    });

    test('unknown entity fails closed', () {
      expect(
        () => parseSyncFeedChange({
          'entity_type': 'future_entity',
          'record_id': 'future-1',
          'op_type': 'UPDATE',
          'key_data': {'id': 'future-1'},
        }),
        _isProtocolFailure,
      );
    });

    test('missing, extra, empty, or mismatched keys fail closed', () {
      for (final change in <Map<String, dynamic>>[
        {
          'entity_type': 'asset_tag',
          'record_id': 'asset-1|tag-1',
          'op_type': 'DELETE',
          'key_data': {'asset_id': 'asset-1'},
        },
        {
          'entity_type': 'asset_tag',
          'record_id': 'asset-1|tag-1',
          'op_type': 'DELETE',
          'key_data': {
            'asset_id': 'asset-1',
            'tag_id': 'tag-1',
            'other': 'nope',
          },
        },
        {
          'entity_type': 'area',
          'record_id': 'area-1',
          'op_type': 'DELETE',
          'key_data': {'id': ''},
        },
        {
          'entity_type': 'asset_tag',
          'record_id': 'wrong-order',
          'op_type': 'DELETE',
          'key_data': {'asset_id': 'asset-1', 'tag_id': 'tag-1'},
        },
      ]) {
        expect(() => parseSyncFeedChange(change), _isProtocolFailure);
      }
    });

    test('unsupported capability version fails closed', () {
      expect(() => requireSyncFeedContractVersion('1.0.0'), _isProtocolFailure);
      expect(
        () => requireSyncFeedContractVersion(syncFeedContractVersion),
        returnsNormally,
      );
    });
  });

  group('ENV-003 retention-gap cursor recovery', () {
    late AppDatabase db;
    late LocalSyncStore store;

    setUp(() {
      db = AppDatabase(executor: NativeDatabase.memory());
      store = LocalSyncStore(db);
    });

    tearDown(() => db.close());

    test('ordinary cursor remains monotonic', () async {
      await store.setFeedCursor(100);
      await store.setFeedCursor(50);
      expect(await store.getFeedCursor(), 100);
    });

    test('resnapshot reset can move 100 to zero and persists restart marker', () async {
      await store.setFeedCursor(100);
      await store.resetFeedCursorForResnapshot(highWaterSeq: 240);

      expect(await store.getFeedCursor(), 0);
      expect(await store.feedResnapshotHighWater(), 240);

      final restarted = LocalSyncStore(db);
      expect(await restarted.getFeedCursor(), 0);
      expect(await restarted.feedResnapshotHighWater(), 240);
    });

    test('successful resnapshot advances to captured high-water and clears marker', () async {
      await store.setFeedCursor(100);
      await store.resetFeedCursorForResnapshot(highWaterSeq: 240);
      await store.completeFeedResnapshot(240);

      expect(await store.getFeedCursor(), 240);
      expect(await store.feedResnapshotHighWater(), isNull);
      await store.setFeedCursor(200);
      expect(await store.getFeedCursor(), 240);
    });
  });
}

final _isProtocolFailure = throwsA(
  isA<SupabaseFailure>().having(
    (failure) => failure.kind,
    'kind',
    SupabaseFailureKind.incompatibleSchema,
  ),
);
