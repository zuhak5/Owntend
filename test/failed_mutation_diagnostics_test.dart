import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';

void main() {
  group('Failed mutation diagnostics and resolution', () {
    late AppDatabase db;
    late LocalSyncStore store;

    setUp(() async {
      db = AppDatabase(executor: NativeDatabase.memory());
      store = LocalSyncStore(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('exportFailedMutationDiagnostics returns privacy-safe fields without raw user payload', () async {
      final now = DateTime.now().toUtc();
      await db
          .into(db.syncOutbox)
          .insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              entity: 'maintenance_completion',
              recordKey: 'comp-1234-uuid',
              operation: 'execute',
              payloadJson: const Value(
                '{"secret_note": "private information"}',
              ),
              changedAt: Value(now),
              state: const Value('failedVisible'),
              attempts: const Value(-1),
              lastErrorCode: const Value('occurrence_changed'),
              lastError: const Value('The occurrence schedule changed.'),
            ),
          );

      final export = await store.exportFailedMutationDiagnostics();
      expect(export.length, 1);
      final item = export.first;

      expect(item['mutation_type'], 'maintenance_completion');
      expect(item['state'], 'failedVisible');
      expect(item['attempt_count'], -1);
      expect(item['last_error_code'], 'occurrence_changed');
      expect(item['sanitized_reason'], 'The occurrence schedule changed.');
      expect(item['supported_actions'], contains('dismiss'));

      final jsonString = item.toString();
      expect(jsonString.contains('private information'), isFalse);
      expect(jsonString.contains('comp-1234-uuid'), isFalse);
    });

    test('resolveFailedMutation dismisses only the selected row and leaves others intact', () async {
      final now = DateTime.now().toUtc();
      await db
          .into(db.syncOutbox)
          .insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              entity: 'maintenance_completion',
              recordKey: 'comp-1',
              operation: 'execute',
              changedAt: Value(now),
              state: const Value('failedVisible'),
              attempts: const Value(-1),
            ),
          );
      await db
          .into(db.syncOutbox)
          .insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              entity: 'user_setting',
              recordKey: 'theme',
              operation: 'upsert',
              changedAt: Value(now),
              state: const Value('failedVisible'),
              attempts: const Value(-1),
            ),
          );

      expect((await store.exportFailedMutationDiagnostics()).length, 2);

      await store.resolveFailedMutation(
        entity: 'maintenance_completion',
        recordKey: 'comp-1',
        action: 'dismiss',
      );

      final remaining = await store.exportFailedMutationDiagnostics();
      expect(remaining.length, 1);
      expect(remaining.first['mutation_type'], 'user_setting');
      expect(remaining.first['operation_fingerprint'], isNotNull);
    });

    test(
      'resolveFailedMutation retry resets mutation state to pending for retry',
      () async {
        final now = DateTime.now().toUtc();
        await db
            .into(db.syncOutbox)
            .insertOnConflictUpdate(
              SyncOutboxCompanion.insert(
                entity: 'user_setting',
                recordKey: 'permission_education_seen',
                operation: 'upsert',
                changedAt: Value(now),
                state: const Value('failedVisible'),
                attempts: const Value(-1),
              ),
            );

        await store.resolveFailedMutation(
          entity: 'user_setting',
          recordKey: 'permission_education_seen',
          action: 'retry',
        );

        final pending = await store.pendingMutations();
        final retried = pending.firstWhere(
          (m) =>
              m.entity == 'user_setting' &&
              m.recordKey == 'permission_education_seen',
        );
        expect(retried.state.name, 'pending');
      },
    );
  });
}
