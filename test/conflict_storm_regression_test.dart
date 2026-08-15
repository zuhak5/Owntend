import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';

void main() {
  test('terminal outbox failures are retained but never retried', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);

    final store = LocalSyncStore(db);
    await db.delete(db.syncOutbox).go();

    final changedAt = DateTime.utc(2026, 7, 28, 3);

    await db
        .into(db.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            entity: 'maintenance_completion',
            recordKey: 'completion-terminal',
            operation: 'execute',
            payloadJson: const Value('{}'),
            changedAt: Value(changedAt),
            attempts: const Value(0),
          ),
        );

    final mutation = (await store.pendingMutations()).single;

    await store.markMutationTerminal(
      mutation,
      'This maintenance completion conflicts with newer cloud data.',
    );

    expect(await store.pendingCount(), 0);
    expect(await store.hasReadyMutations(), isFalse);
    expect(await store.pendingMutations(), isEmpty);
    expect(await store.nextRetryAt(), isNull);

    final retained =
        await (db.select(db.syncOutbox)..where(
              (row) =>
                  row.entity.equals('maintenance_completion') &
                  row.recordKey.equals('completion-terminal'),
            ))
            .getSingle();

    expect(retained.attempts, -1);
    expect(retained.nextAttemptAt, isNull);
    expect(
      retained.lastError,
      'This maintenance completion conflicts with newer cloud data.',
    );
  });

  test('a delayed mutation is not ready before its backoff expires', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);

    final store = LocalSyncStore(db);
    await db.delete(db.syncOutbox).go();

    final now = DateTime.now();

    await db
        .into(db.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            entity: 'user_setting',
            recordKey: 'conflict-storm-backoff-theme',
            operation: 'upsert',
            changedAt: Value(now),
            attempts: const Value(1),
            nextAttemptAt: Value(now.add(const Duration(minutes: 5))),
            lastError: const Value('Temporary cloud failure.'),
          ),
        );

    expect(await store.pendingCount(), 1);
    expect(await store.hasReadyMutations(), isFalse);
    expect(await store.pendingMutations(), isEmpty);
    expect(await store.nextRetryAt(), isNotNull);

    await (db.update(db.syncOutbox)..where(
          (row) =>
              row.entity.equals('user_setting') &
              row.recordKey.equals('conflict-storm-backoff-theme'),
        ))
        .write(
          SyncOutboxCompanion(
            nextAttemptAt: Value(now.subtract(const Duration(seconds: 1))),
          ),
        );

    expect(await store.hasReadyMutations(), isTrue);
    expect(await store.pendingMutations(), hasLength(1));
  });

  test('retry backoff is delayed and bounded with jitter', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);

    final store = LocalSyncStore(db);
    await db.delete(db.syncOutbox).go();

    final startedAt = DateTime.now();

    await db
        .into(db.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            entity: 'user_setting',
            recordKey: 'conflict-storm-jitter',
            operation: 'upsert',
            changedAt: Value(startedAt),
            attempts: const Value(0),
          ),
        );

    final mutation = (await store.pendingMutations()).single;

    await store.markMutationFailed(mutation, 'Temporary cloud failure.');

    final retained =
        await (db.select(db.syncOutbox)..where(
              (row) =>
                  row.entity.equals('user_setting') &
                  row.recordKey.equals('conflict-storm-jitter'),
            ))
            .getSingle();

    expect(retained.attempts, 1);
    expect(retained.nextAttemptAt, isNotNull);

    final observedDelaySeconds = retained.nextAttemptAt!
        .difference(startedAt)
        .inSeconds;

    // SQLite DateTime persistence may truncate subsecond precision.
    expect(observedDelaySeconds, greaterThanOrEqualTo(14));
    expect(observedDelaySeconds, lessThanOrEqualTo(19));

    expect(await store.pendingCount(), 1);
    expect(await store.hasReadyMutations(), isFalse);
    expect(await store.pendingMutations(), isEmpty);
  });

  test('automatic retries stop after twenty-four failures', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);

    final store = LocalSyncStore(db);
    await db.delete(db.syncOutbox).go();

    final changedAt = DateTime.now();

    await db
        .into(db.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            entity: 'user_setting',
            recordKey: 'conflict-storm-attempt-cap',
            operation: 'upsert',
            changedAt: Value(changedAt),
            attempts: const Value(23),
          ),
        );

    final mutation = (await store.pendingMutations()).single;

    await store.markMutationFailed(mutation, 'Temporary cloud failure.');

    final retained =
        await (db.select(db.syncOutbox)..where(
              (row) =>
                  row.entity.equals('user_setting') &
                  row.recordKey.equals('conflict-storm-attempt-cap'),
            ))
            .getSingle();

    expect(retained.attempts, -1);
    expect(retained.nextAttemptAt, isNull);
    expect(
      retained.lastError,
      contains('Automatic sync paused after 24 failed attempts.'),
    );

    expect(await store.pendingCount(), 0);
    expect(await store.hasReadyMutations(), isFalse);
    expect(await store.pendingMutations(), isEmpty);
    expect(await store.nextRetryAt(), isNull);
  });
}
