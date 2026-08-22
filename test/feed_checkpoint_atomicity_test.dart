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

  group('feed checkpoint atomicity', () {
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

    test('push ACK does not move any inbound pull cursor', () async {
      await store.setFeedCursor(100);
      await store.setCursor('area', 100, lastRecordKey: 'area-existing');

      final now = DateTime.now();
      final spec = syncEntitySpecs.firstWhere((s) => s.entity == 'area');
      final canonical = SyncRecord(
        spec: spec,
        recordKey: 'area-push-ack-1',
        clientModifiedAt: now,
        originDeviceId: 'device-1',
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

      expect(await store.getFeedCursor(), 100);
      expect(await store.cursorCheckpoint('area'), (100, 'area-existing'));
    });

    test(
      'maintenance completion ACK records canonical shadows without cursors',
      () async {
        await store.setCursor(
          'maintenance_plan',
          10,
          lastRecordKey: 'plan-before',
        );
        await store.setCursor(
          'maintenance_record',
          11,
          lastRecordKey: 'record-before',
        );
        final now = DateTime.utc(2026, 8, 17, 8);
        final mutation = LocalSyncMutation(
          entity: 'maintenance_completion',
          recordKey: 'completion-ack-1',
          operation: 'execute',
          payloadJson: '{}',
          generation: 1,
          createdAt: now,
          changedAt: now,
          attempts: 1,
        );
        final plan = SyncRecord(
          spec: syncEntitySpecs.firstWhere(
            (spec) => spec.entity == 'maintenance_plan',
          ),
          recordKey: 'plan-ack-1',
          clientModifiedAt: now,
          originDeviceId: 'remote-device',
          revision: 5,
          values: const {'id': 'plan-ack-1'},
        );
        final record = SyncRecord(
          spec: syncEntitySpecs.firstWhere(
            (spec) => spec.entity == 'maintenance_record',
          ),
          recordKey: 'completion-ack-1',
          clientModifiedAt: now,
          originDeviceId: 'remote-device',
          revision: 6,
          values: const {'id': 'completion-ack-1'},
        );

        await store.markMaintenanceCompletionSucceeded(
          mutation,
          plan: plan,
          record: record,
        );

        expect(await store.cursorCheckpoint('maintenance_plan'), (
          10,
          'plan-before',
        ));
        expect(await store.cursorCheckpoint('maintenance_record'), (
          11,
          'record-before',
        ));
        expect(await store.shadow('maintenance_plan', 'plan-ack-1'), isNotNull);
        expect(
          await store.shadow('maintenance_record', 'completion-ack-1'),
          isNotNull,
        );
      },
    );

    test('snapshot mutations roll back when checkpoint commit fails', () async {
      final now = DateTime.utc(2026, 8, 17, 9);
      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(
              id: 'atomic-existing-area',
              name: 'Existing area',
              kind: 'indoor',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await db.delete(db.syncOutbox).go();
      final spec = syncEntitySpecs.firstWhere((s) => s.entity == 'area');
      final deletion = SyncRecord(
        spec: spec,
        recordKey: 'atomic-existing-area',
        clientModifiedAt: now,
        originDeviceId: 'remote-device',
        revision: 2,
        serverUpdatedAt: now,
        deletedAt: now,
        values: const {'id': 'atomic-existing-area'},
      );
      final upsert = SyncRecord(
        spec: spec,
        recordKey: 'atomic-new-area',
        clientModifiedAt: now,
        originDeviceId: 'remote-device',
        revision: 3,
        serverUpdatedAt: now,
        values: {
          'id': 'atomic-new-area',
          'name': 'Atomic new area',
          'kind': 'indoor',
          'sort_order': 0,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'archived_at': null,
        },
      );
      await db.customStatement('''
CREATE TRIGGER fail_area_checkpoint
BEFORE INSERT ON sync_cursors
WHEN NEW.entity = 'area'
BEGIN
  SELECT RAISE(ABORT, 'forced checkpoint failure');
END;
''');

      await expectLater(
        store.applyRemoteRecordsAndCheckpoints(
          records: [deletion, upsert],
          checkpoints: const {'area': (41, 'atomic-new-area')},
        ),
        throwsA(anything),
      );

      expect(await store.cursor('area'), 0);
      expect(
        await (db.select(db.areas)
              ..where((row) => row.id.equals('atomic-existing-area')))
            .getSingleOrNull(),
        isNotNull,
      );
      expect(
        await (db.select(
          db.areas,
        )..where((row) => row.id.equals('atomic-new-area'))).getSingleOrNull(),
        isNull,
      );
      expect(await store.shadow('area', 'atomic-existing-area'), isNull);
      expect(await store.shadow('area', 'atomic-new-area'), isNull);
    });

    test('feed page mutations roll back when feed checkpoint fails', () async {
      final now = DateTime.utc(2026, 8, 17, 10);
      final spec = syncEntitySpecs.firstWhere((s) => s.entity == 'area');
      final record = SyncRecord(
        spec: spec,
        recordKey: 'atomic-feed-area',
        clientModifiedAt: now,
        originDeviceId: 'remote-device',
        revision: 4,
        values: {
          'id': 'atomic-feed-area',
          'name': 'Atomic feed area',
          'kind': 'indoor',
          'sort_order': 0,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'archived_at': null,
        },
      );
      await db.customStatement('''
CREATE TRIGGER fail_feed_checkpoint
BEFORE INSERT ON sync_cursors
WHEN NEW.entity = 'server_change_feed'
BEGIN
  SELECT RAISE(ABORT, 'forced feed checkpoint failure');
END;
''');

      await expectLater(
        store.applyRemoteFeedPageAndCheckpoint(
          records: [record],
          lastSyncSeq: 77,
        ),
        throwsA(anything),
      );

      expect(await store.getFeedCursor(), 0);
      expect(
        await (db.select(
          db.areas,
        )..where((row) => row.id.equals('atomic-feed-area'))).getSingleOrNull(),
        isNull,
      );
      expect(await store.shadow('area', 'atomic-feed-area'), isNull);
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

        // The prior cloud shadow remains untouched so the pending mutation
        // retains its expected server revision for conflict resolution.
        final shadow =
            await (db.select(db.syncShadows)
                  ..where((r) => r.recordKey.equals('area-pending-local-1')))
                .getSingleOrNull();
        expect(shadow, isNull);
      },
    );
  });
}
