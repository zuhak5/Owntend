import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';

void main() {
  group('Offline Maintenance Account Binding Preservation (BUG-01)', () {
    late AppDatabase db;
    late LocalSyncStore store;

    setUp(() async {
      db = AppDatabase(executor: NativeDatabase.memory());
      await db.delete(db.syncOutbox).go();
      store = LocalSyncStore(
        db,
        documentsDirectory: () async => Directory.systemTemp.createTemp(),
        deleteFile: (file) async {},
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('preserves offline maintenance completion and retargets userId on bindIdentity', () async {
      const completionId = 'offline-completion-1';
      final now = DateTime.now().toUtc();

      // Seed an offline maintenance completion intent:
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              entity: 'maintenance_completion',
              recordKey: completionId,
              operation: 'execute',
              changedAt: Value(now),
              payloadJson: Value(
                jsonEncode({
                  'contract_version': 1,
                  'operation_id': completionId,
                  'plan_id': 'plan-1',
                }),
              ),
              userId: const Value(null),
            ),
          );

      // Seed a generic CRUD entity that should be wiped because snapshot re-enqueues it:
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              entity: 'asset',
              recordKey: 'asset-1',
              operation: 'upsert',
              changedAt: Value(now),
              payloadJson: const Value('{}'),
              userId: const Value(null),
            ),
          );

      // Verify both are initially present:
      final before = await db.select(db.syncOutbox).get();
      expect(before.length, 2);

      // Bind identity:
      await store.bindIdentity('user-google-999');

      // Assert that generic CRUD row is wiped, while maintenance_completion is preserved and retargeted:
      final after = await db.select(db.syncOutbox).get();
      expect(after.length, 1);
      final completion = after.single;
      expect(completion.entity, 'maintenance_completion');
      expect(completion.recordKey, completionId);
      expect(completion.userId, 'user-google-999');
      expect(completion.attempts, 0);
    });
  });
}
