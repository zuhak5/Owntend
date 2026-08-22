import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/supabase/supabase_failure.dart';
import 'package:owntend/src/core/sync/change_feed_contract.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/local_sync_store_change_feed.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';

void main() {
  group('change-feed wire contract', () {
    test(
      'every client sync entity has one strict feed identifier and key set',
      () {
        final specs = [...syncEntitySpecs, profileSyncSpec];
        expect(specs.map((spec) => spec.entity).toSet().length, specs.length);

        for (final spec in specs) {
          final keyData = <String, dynamic>{
            for (final column in spec.keyColumns) column: 'value-$column',
          };
          final recordKey = spec.keyColumns.isEmpty
              ? spec.entity
              : spec.keyColumns.map((column) => keyData[column]).join('|');
          final parsed = parseSyncFeedChange(
            _deleteChange({
              'entity_type': spec.entity,
              'record_id': recordKey,
              'key_data': keyData,
            }),
          );

          expect(parsed.record.spec, same(spec));
          expect(parsed.record.recordKey, recordKey);
          expect(parsed.record.values, keyData);
          expect(parsed.record.isDeleted, isTrue);
        }
      },
    );

    test('composite key JSON order does not change canonical record key', () {
      final parsed = parseSyncFeedChange(
        _deleteChange({
          'entity_type': 'asset_tag',
          'record_id': 'asset-1|tag-1',
          'key_data': {'tag_id': 'tag-1', 'asset_id': 'asset-1'},
        }),
      );

      expect(parsed.record.recordKey, 'asset-1|tag-1');
      expect(parsed.record.values, {'asset_id': 'asset-1', 'tag_id': 'tag-1'});
    });

    test('unknown entity fails closed', () {
      expect(
        () => parseSyncFeedChange(
          _deleteChange({
            'entity_type': 'future_entity',
            'record_id': 'future-1',
            'key_data': {'id': 'future-1'},
          }),
        ),
        _isProtocolFailure,
      );
    });

    test('missing, extra, empty, or mismatched keys fail closed', () {
      for (final change in <Map<String, dynamic>>[
        {
          'entity_type': 'asset_tag',
          'record_id': 'asset-1|tag-1',
          'key_data': {'asset_id': 'asset-1'},
        },
        {
          'entity_type': 'asset_tag',
          'record_id': 'asset-1|tag-1',
          'key_data': {
            'asset_id': 'asset-1',
            'tag_id': 'tag-1',
            'other': 'nope',
          },
        },
        {
          'entity_type': 'area',
          'record_id': 'area-1',
          'key_data': {'id': ''},
        },
        {
          'entity_type': 'asset_tag',
          'record_id': 'wrong-order',
          'key_data': {'asset_id': 'asset-1', 'tag_id': 'tag-1'},
        },
      ]) {
        expect(
          () => parseSyncFeedChange(_deleteChange(change)),
          _isProtocolFailure,
        );
      }
    });

    test('canonical upsert payload is parsed without a point fetch', () {
      final parsed = parseSyncFeedChange({
        'contract_version': 1,
        'change_seq': 8,
        'entity_type': 'user_setting',
        'record_id': 'theme',
        'op_type': 'UPDATE',
        'key_data': {'key': 'theme'},
        'client_updated_at': '2026-08-21T10:00:00Z',
        'created_at': '2026-08-21T10:00:01Z',
        'revision': 4,
        'payload': {
          'user_id': 'user-1',
          'key': 'theme',
          'value': 'dark',
          'updated_at': '2026-08-21T10:00:00Z',
          'revision': 4,
        },
      });

      expect(parsed.changeSeq, 8);
      expect(parsed.record.values['value'], 'dark');
      expect(parsed.changeSeq, 8);
      expect(parsed.record.revision, 4);
      expect(parsed.record.isDeleted, isFalse);
    });

    test('unsupported contract version fails closed', () {
      expect(() => requireSyncFeedContractVersion(2), _isProtocolFailure);
      expect(
        () => requireSyncFeedContractVersion(syncFeedContractVersion),
        returnsNormally,
      );
    });
  });

  group('retention-gap cursor recovery', () {
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

    test(
      'resnapshot reset can move 100 to zero and persists restart marker',
      () async {
        await store.setFeedCursor(100);
        await store.resetFeedCursorForResnapshot(highWaterSeq: 240);

        expect(await store.getFeedCursor(), 0);
        expect(await store.feedResnapshotHighWater(), 240);

        final restarted = LocalSyncStore(db);
        expect(await restarted.getFeedCursor(), 0);
        expect(await restarted.feedResnapshotHighWater(), 240);
      },
    );

    test(
      'successful resnapshot advances to captured high-water and clears marker',
      () async {
        await store.setFeedCursor(100);
        await store.resetFeedCursorForResnapshot(highWaterSeq: 240);
        await store.completeFeedResnapshot(240);

        expect(await store.getFeedCursor(), 240);
        expect(await store.feedResnapshotHighWater(), isNull);
        await store.setFeedCursor(200);
        expect(await store.getFeedCursor(), 240);
      },
    );

    test(
      'unsupported outbox entities fail closed and remain durable',
      () async {
        final changedAt = DateTime.utc(2026, 8, 21);
        await db.customStatement(
          '''
INSERT INTO offline_mutation_queue(
  entity, record_key, operation, changed_at, state, attempts, generation
) VALUES (?, ?, 'upsert', ?, 'pending', 0, 1)
''',
          [
            'future_entity',
            'record-1',
            changedAt.millisecondsSinceEpoch ~/ 1000,
          ],
        );
        final mutation = LocalSyncMutation(
          entity: 'future_entity',
          recordKey: 'record-1',
          operation: 'upsert',
          changedAt: changedAt,
          attempts: 0,
        );

        await expectLater(
          store.readMutation(mutation, 'device-1'),
          _isProtocolFailure,
        );
        final retained =
            await (db.select(db.syncOutbox)
                  ..where((row) => row.entity.equals('future_entity')))
                .getSingleOrNull();
        expect(retained, isNotNull);
      },
    );
  });
}

Map<String, dynamic> _deleteChange(Map<String, dynamic> values) => {
  'contract_version': 1,
  'change_seq': 7,
  'op_type': 'DELETE',
  'client_updated_at': '2026-08-21T10:00:00Z',
  'created_at': '2026-08-21T10:00:01Z',
  'revision': 2,
  'payload': null,
  ...values,
};

final _isProtocolFailure = throwsA(
  isA<SupabaseFailure>().having(
    (failure) => failure.kind,
    'kind',
    SupabaseFailureKind.incompatibleSchema,
  ),
);
