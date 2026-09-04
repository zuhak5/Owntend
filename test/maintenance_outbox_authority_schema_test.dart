import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';

void main() {
  group('Maintenance Outbox Authority Schema Alignment (BUG-02)', () {
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

    test('enforceMaintenanceHistoryMutationAuthority purges generic record when completion payload has operation_id', () async {
      const completionId = 'comp-789';
      final now = DateTime.now().toUtc();

      // Trigger-generated generic row:
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              entity: 'maintenance_record',
              recordKey: completionId,
              operation: 'upsert',
              changedAt: Value(now),
              payloadJson: const Value(null),
            ),
          );

      // Authoritative composite completion with top-level operation_id:
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
            ),
          );

      // Run authority enforcement:
      await store.enforceMaintenanceHistoryMutationAuthority();

      // Verify that generic maintenance_record row was deleted and NOT marked failedVisible:
      final rows = await db.select(db.syncOutbox).get();
      expect(rows.length, 1);
      expect(rows.single.entity, 'maintenance_completion');
      expect(rows.single.recordKey, completionId);
    });
  });
}
