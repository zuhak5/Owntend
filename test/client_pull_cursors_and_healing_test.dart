import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';

import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues(<String, String>{});

  late AppDatabase db;
  late LocalSyncStore store;

  setUp(() async {
    db = AppDatabase(executor: NativeDatabase.memory());
    store = LocalSyncStore(db);
    await db.customStatement('PRAGMA foreign_keys = ON;');
    await db.delete(db.syncCursors).go();
    await db.delete(db.syncOutbox).go();
  });

  tearDown(() async {
    await db.close();
  });

  group('Task 20 - Client Pull-Only Cursors & Healing Scan Tests', () {
    test('only completed feed pull advances feed cursor', () async {
      final initialCursor = await store.getFeedCursor();
      expect(initialCursor, 0);

      await store.setFeedCursor(42);
      final updatedCursor = await store.getFeedCursor();
      expect(updatedCursor, 42);

      // Attempting to set lower cursor is ignored
      await store.setFeedCursor(10);
      expect(await store.getFeedCursor(), 42);
    });

    test('push ACK does not move feed cursor', () async {
      await store.setFeedCursor(100);

      final now = DateTime.now();
      final spec = syncEntitySpecs.firstWhere((s) => s.entity == 'area');
      final canonical = SyncRecord(
        spec: spec,
        recordKey: 'area-push-ack-1',
        clientModifiedAt: now,
        originDeviceId: 'device-1',
        syncSeq: 500,
        values: {
          'id': 'area-push-ack-1',
          'user_id': 'user-1',
          'name': 'Pushed Area',
          'kind': 'indoor',
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'revision': 1,
        },
      );

      final mutation = LocalSyncMutation(
        entity: 'area',
        recordKey: 'area-push-ack-1',
        operation: 'create',
        payloadJson: '{}',
        generation: 1,
        createdAt: now,
        changedAt: now,
        attempts: 1,
      );

      await store.markMutationSucceeded(mutation, canonical);

      // Feed cursor remains unchanged at 100
      expect(await store.getFeedCursor(), 100);
    });

    test(
      'applyRemoteFeedRecord preserves local pending mutation intent',
      () async {
        final now = DateTime.now();
        await db
            .into(db.areas)
            .insert(
              AreasCompanion.insert(
                id: 'area-pending-local-1',
                name: 'Local Edited Name',
                kind: 'indoor',
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );

        final pending = await store.pendingMutations();
        final targetPending = pending.firstWhere(
          (m) => m.recordKey == 'area-pending-local-1',
        );
        expect(targetPending.generation, 1);

        final spec = syncEntitySpecs.firstWhere((s) => s.entity == 'area');
        final remoteRecord = SyncRecord(
          spec: spec,
          recordKey: 'area-pending-local-1',
          clientModifiedAt: now,
          originDeviceId: 'device-1',
          revision: 2,
          values: {
            'id': 'area-pending-local-1',
            'user_id': 'user-1',
            'name': 'Remote Stale Name',
            'kind': 'indoor',
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
            'revision': 2,
          },
        );

        await store.applyRemoteFeedRecord(remoteRecord);

        // Local SQLite row preserves local edit
        final localRow = await (db.select(
          db.areas,
        )..where((r) => r.id.equals('area-pending-local-1'))).getSingle();
        expect(localRow.name, 'Local Edited Name');

        // Shadow is updated
        final shadow =
            await (db.select(db.syncShadows)
                  ..where((r) => r.recordKey.equals('area-pending-local-1')))
                .getSingleOrNull();
        expect(shadow, isNotNull);
        expect(shadow!.remoteRevision, 2);
      },
    );
  });
}
