import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late LocalSyncStore store;

  setUp(() async {
    db = AppDatabase(executor: NativeDatabase.memory());
    store = LocalSyncStore(db);
    await store.account();
    await store.setEnabled(enabled: true, boundUserId: 'user-1');
    // Seed defaults enqueue their own outbox rows; tests start from a quiet
    // queue and enqueue exactly what they exercise.
    await db.delete(db.syncOutbox).go();
  });

  tearDown(() => db.close());

  SyncRecord remoteSetting({
    String key = 'theme',
    String value = 'dark',
    required DateTime modifiedAt,
    int revision = 4,
    String originDeviceId = 'remote-device',
  }) {
    return SyncRecord(
      spec: syncSpecByEntity['user_setting']!,
      recordKey: key,
      values: {
        'key': key,
        'value': value,
        'updated_at': modifiedAt.toUtc().toIso8601String(),
      },
      clientModifiedAt: modifiedAt.toUtc(),
      originDeviceId: originDeviceId,
      revision: revision,
      serverUpdatedAt: modifiedAt.toUtc(),
    );
  }

  Future<LocalSyncMutation> enqueuePendingSettingEdit(
    DateTime changedAt, {
    String key = 'theme',
  }) async {
    final mutation = LocalSyncMutation(
      entity: 'user_setting',
      recordKey: key,
      operation: 'upsert',
      changedAt: changedAt,
      attempts: 0,
      generation: 1,
    );
    await db
        .into(db.syncOutbox)
        .insertOnConflictUpdate(
          SyncOutboxCompanion.insert(
            entity: mutation.entity,
            recordKey: mutation.recordKey,
            operation: mutation.operation,
            userId: const Value('user-1'),
            changedAt: Value(changedAt),
            createdAt: Value(changedAt),
            state: const Value('pending'),
          ),
        );
    return mutation;
  }

  Future<SyncOutboxData?> outboxRow(String entity, String recordKey) {
    return (db.select(db.syncOutbox)..where(
          (row) => row.entity.equals(entity) & row.recordKey.equals(recordKey),
        ))
        .getSingleOrNull();
  }

  test(
    'remote revision winner preserves local intent as unresolved conflict',
    () async {
      final now = DateTime.now().toUtc();
      await enqueuePendingSettingEdit(now.subtract(const Duration(hours: 2)));
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: 'theme',
              value: 'system',
              updatedAt: Value(now.subtract(const Duration(hours: 2))),
            ),
          );

      final preserved = await store.markEntityMutationConflicted(
        entity: 'user_setting',
        recordKey: 'theme',
        accountId: 'user-1',
        deviceId: 'local-device',
        reason: 'pulled_remote_winner',
        remotePayloadJson: jsonEncode(
          remoteSetting(modifiedAt: DateTime.now().toUtc()).values,
        ),
        remoteRevision: 4,
      );

      expect(preserved, isTrue);
      final row = await outboxRow('user_setting', 'theme');
      expect(row, isNotNull);
      expect(row!.state, 'conflict');
      expect(
        row.generation,
        2,
        reason: 'the local edit bumped the generation before the pull',
      );

      final conflicts = await store.listSyncConflicts(
        accountId: 'user-1',
        resolutionStatus: 'unresolved',
      );
      expect(conflicts, hasLength(1));
      expect(
        conflicts.single.resolvedAt,
        isNull,
        reason: 'resolvedAt must stay null until explicit resolution',
      );
      expect(conflicts.single.remoteRevision, 4);
      expect(conflicts.single.localPayloadJson, isNotNull);
    },
  );

  test(
    'clock-skew loser keeps its intent and the server value locally',
    () async {
      final now = DateTime.now().toUtc();
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: 'theme',
              value: 'future-clock-edit',
              updatedAt: Value(now.add(const Duration(hours: 3))),
            ),
          );
      final mutation = (await store.pendingMutations()).singleWhere(
        (candidate) => candidate.recordKey == 'theme',
      );

      final conflicted = await store.markMutationConflicted(
        mutation,
        accountId: 'user-1',
        reason: 'remote_clock_skew_winner',
        localPayloadJson: store.encodeConflictPayload(
          operation: 'upsert',
          values: {'key': 'theme', 'value': 'future-clock-edit'},
        ),
        remotePayloadJson: jsonEncode(
          remoteSetting(modifiedAt: DateTime.now().toUtc()).values,
        ),
        remoteRevision: 4,
      );

      expect(conflicted, isTrue);
      final row = await outboxRow('user_setting', 'theme');
      expect(row!.state, 'conflict');
      final conflicts = await store.listSyncConflicts(
        resolutionStatus: 'unresolved',
      );
      expect(conflicts, hasLength(1));
      expect(
        jsonDecode(conflicts.single.localPayloadJson!)['record']['value'],
        'future-clock-edit',
      );
    },
  );

  test(
    'a newer same-key edit after the snapshot selection cannot be clobbered',
    () async {
      final now = DateTime.now().toUtc();
      final stale = await enqueuePendingSettingEdit(
        now.subtract(const Duration(hours: 5)),
      );

      // The pull observed generation 1; meanwhile a newer edit arrived: the
      // trigger bumps the generation and the local row changes.
      final freshChangedAt = now.subtract(const Duration(minutes: 1));
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: 'theme',
              value: 'newer-local-edit',
              updatedAt: Value(freshChangedAt),
            ),
          );
      final currentGeneration =
          await (db.select(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals('user_setting') &
                    row.recordKey.equals('theme'),
              ))
              .getSingle()
              .then((row) => row.generation);
      expect(currentGeneration, greaterThan(1));

      final clobbered = await store.markMutationConflicted(
        stale,
        accountId: 'user-1',
        reason: 'remote_revision_winner',
        remoteRevision: 9,
      );

      expect(
        clobbered,
        isFalse,
        reason: 'stale generation evidence must never overwrite newer intent',
      );
      final row = await outboxRow('user_setting', 'theme');
      expect(
        row!.state,
        'pending',
        reason: 'the newer local edit stays pushable',
      );
      expect(row.generation, currentGeneration);
      expect(await store.pendingCount(), 1);
    },
  );

  test(
    'reordered late acknowledgement of an older generation keeps newer work',
    () async {
      final now = DateTime.now().toUtc();
      final current = await enqueuePendingSettingEdit(now);
      // Simulate a response reorder: the ack belongs to generation 1 but the
      // user already edited again (generation 2).
      await (db.update(db.syncOutbox)..where(
            (row) =>
                row.entity.equals('user_setting') &
                row.recordKey.equals('theme'),
          ))
          .write(const SyncOutboxCompanion(generation: Value(2)));

      final deleted = await store.markMutationSucceeded(current, null);
      expect(deleted, isFalse);
      final row = await outboxRow('user_setting', 'theme');
      expect(
        row,
        isNotNull,
        reason: 'a stale acknowledgement must not erase newer intent',
      );
    },
  );

  test('exact server acknowledgement resolves outstanding conflicts', () async {
    final now = DateTime.now().toUtc();
    final mutation = await enqueuePendingSettingEdit(now);
    await store.markEntityMutationConflicted(
      entity: 'user_setting',
      recordKey: 'theme',
      accountId: 'user-1',
      deviceId: 'local-device',
      reason: 'pulled_remote_winner',
      remoteRevision: 4,
    );

    final acknowledged = await store.markMutationSucceeded(
      mutation,
      remoteSetting(modifiedAt: DateTime.now().toUtc()),
    );
    expect(acknowledged, isTrue);
    expect(await outboxRow('user_setting', 'theme'), isNull);
    final conflicts = await store.listSyncConflicts();
    expect(conflicts, hasLength(1));
    expect(conflicts.single.resolutionStatus, 'resolved_server_acknowledged');
    expect(conflicts.single.resolvedAt, isNotNull);
  });

  test(
    'multiple conflicts across records are preserved independently',
    () async {
      final now = DateTime.now().toUtc();
      await enqueuePendingSettingEdit(now, key: 'theme');
      await enqueuePendingSettingEdit(now, key: 'language');

      await store.markEntityMutationConflicted(
        entity: 'user_setting',
        recordKey: 'theme',
        accountId: 'user-1',
        deviceId: 'local-device',
        reason: 'pulled_remote_winner',
        remoteRevision: 4,
      );
      await store.markEntityMutationConflicted(
        entity: 'user_setting',
        recordKey: 'language',
        accountId: 'user-1',
        deviceId: 'local-device',
        reason: 'pulled_remote_winner',
        remoteRevision: 7,
      );

      final unresolved = await store.listSyncConflicts(
        accountId: 'user-1',
        resolutionStatus: 'unresolved',
      );
      expect(unresolved, hasLength(2));
      expect(
        unresolved.map((row) => row.recordKey),
        containsAll(['theme', 'language']),
      );
      expect(await store.unresolvedConflictCount(), 2);
      expect(
        await store.pendingCount(),
        0,
        reason: 'conflicted rows are excluded from automatic pushes',
      );
    },
  );

  test('repeated pulls with identical remote evidence do not duplicate ledger '
      'rows', () async {
    final now = DateTime.now().toUtc();
    await enqueuePendingSettingEdit(now);
    for (var i = 0; i < 3; i++) {
      await store.markEntityMutationConflicted(
        entity: 'user_setting',
        recordKey: 'theme',
        accountId: 'user-1',
        deviceId: 'local-device',
        reason: 'pulled_remote_winner',
        remoteRevision: 4,
      );
    }
    final unresolved = await store.listSyncConflicts(
      resolutionStatus: 'unresolved',
    );
    expect(unresolved, hasLength(1));
  });

  test('explicit keep-local resolution restores the preserved payload and '
      'requeues the mutation', () async {
    final now = DateTime.now().toUtc();
    await enqueuePendingSettingEdit(now.subtract(const Duration(hours: 2)));
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: 'theme',
            value: 'my-local-choice',
            updatedAt: Value(now.subtract(const Duration(hours: 2))),
          ),
        );
    await store.markEntityMutationConflicted(
      entity: 'user_setting',
      recordKey: 'theme',
      accountId: 'user-1',
      deviceId: 'local-device',
      reason: 'pulled_remote_winner',
      remoteRevision: 4,
    );

    // The canonical remote row was applied over the local table.
    await store.applyRemoteRecords([
      remoteSetting(value: 'dark', modifiedAt: DateTime.now().toUtc()),
    ]);

    final resolved = await store.resolveSyncConflict(
      entity: 'user_setting',
      recordKey: 'theme',
      accountId: 'user-1',
      deviceId: 'local-device',
      keepLocal: true,
    );
    expect(resolved, isTrue);

    final setting = await (db.select(
      db.settings,
    )..where((row) => row.key.equals('theme'))).getSingle();
    expect(
      setting.value,
      'my-local-choice',
      reason: 'keep-local must restore the preserved user edit',
    );
    final row = await outboxRow('user_setting', 'theme');
    expect(row!.state, 'pending');
    expect(await store.pendingCount(), 1);

    final conflicts = await store.listSyncConflicts();
    expect(conflicts.single.resolutionStatus, 'resolved_keep_local');
    expect(conflicts.single.resolvedAt, isNotNull);
  });

  test(
    'explicit keep-remote resolution discards only the conflicted intent',
    () async {
      final now = DateTime.now().toUtc();
      await enqueuePendingSettingEdit(now, key: 'theme');
      await enqueuePendingSettingEdit(now, key: 'language');
      await store.markEntityMutationConflicted(
        entity: 'user_setting',
        recordKey: 'theme',
        accountId: 'user-1',
        deviceId: 'local-device',
        reason: 'pulled_remote_winner',
        remoteRevision: 4,
      );

      final resolved = await store.resolveSyncConflict(
        entity: 'user_setting',
        recordKey: 'theme',
        accountId: 'user-1',
        deviceId: 'local-device',
        keepLocal: false,
      );
      expect(resolved, isTrue);
      expect(await outboxRow('user_setting', 'theme'), isNull);
      expect(
        await store.pendingCount(),
        1,
        reason: 'other queued work is untouched',
      );
      final conflicts = await store.listSyncConflicts();
      expect(conflicts.single.resolutionStatus, 'resolved_keep_remote');
      expect(conflicts.single.resolvedAt, isNotNull);
    },
  );

  test('preserved conflicts survive a process restart', () async {
    final root = await Directory.systemTemp.createTemp('owntend_conflict_');
    AppDatabase? first;
    AppDatabase? reopened;
    try {
      final file = File(p.join(root.path, AppDatabase.databaseFileName));
      first = AppDatabase(executor: NativeDatabase(file));
      var restartStore = LocalSyncStore(first);
      await restartStore.account();
      await restartStore.setEnabled(enabled: true, boundUserId: 'user-1');
      final now = DateTime.now().toUtc();
      await first
          .into(first.syncOutbox)
          .insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              entity: 'user_setting',
              recordKey: 'theme',
              operation: 'upsert',
              userId: const Value('user-1'),
              changedAt: Value(now),
              state: const Value('pending'),
            ),
          );
      await restartStore.markEntityMutationConflicted(
        entity: 'user_setting',
        recordKey: 'theme',
        accountId: 'user-1',
        deviceId: 'local-device',
        reason: 'pulled_remote_winner',
        remoteRevision: 4,
      );
      await first.close();
      first = null;

      reopened = AppDatabase(executor: NativeDatabase(file));
      restartStore = LocalSyncStore(reopened);
      final row =
          await (reopened.select(reopened.syncOutbox)..where(
                (row) =>
                    row.entity.equals('user_setting') &
                    row.recordKey.equals('theme'),
              ))
              .getSingleOrNull();
      expect(
        row!.state,
        'conflict',
        reason: 'unresolved intent must survive restart indefinitely',
      );
      final conflicts = await restartStore.listSyncConflicts(
        accountId: 'user-1',
        resolutionStatus: 'unresolved',
      );
      expect(conflicts, hasLength(1));
      expect(conflicts.single.resolvedAt, isNull);
    } finally {
      await first?.close();
      await reopened?.close();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });

  test(
    'a fresh local edit on a conflicted row returns it to the push queue',
    () async {
      final now = DateTime.now().toUtc();
      await enqueuePendingSettingEdit(now);
      await store.markEntityMutationConflicted(
        entity: 'user_setting',
        recordKey: 'theme',
        accountId: 'user-1',
        deviceId: 'local-device',
        reason: 'pulled_remote_winner',
        remoteRevision: 4,
      );

      // A new local edit fires the outbox trigger with ON CONFLICT DO UPDATE.
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: 'theme',
              value: 'edited-again',
              updatedAt: Value(now.add(const Duration(minutes: 1))),
            ),
          );

      final row = await outboxRow('user_setting', 'theme');
      expect(row!.state, 'pending');
      expect(row.generation, 2);
      expect(await store.pendingMutations(), isNotEmpty);
    },
  );

  test(
    'account binding changes clear conflicts together with queued intent',
    () async {
      final now = DateTime.now().toUtc();
      await enqueuePendingSettingEdit(now);
      await store.markEntityMutationConflicted(
        entity: 'user_setting',
        recordKey: 'theme',
        accountId: 'user-1',
        deviceId: 'local-device',
        reason: 'pulled_remote_winner',
        remoteRevision: 4,
      );

      await store.clearBinding();

      expect(await store.listSyncConflicts(), isEmpty);
      final conflictsOfOtherAccount = await store.listSyncConflicts(
        accountId: 'user-2',
      );
      expect(conflictsOfOtherAccount, isEmpty);
      expect(await store.pendingCount(), 0);
    },
  );

  test('conflict ledger rows are scoped to their owning account', () async {
    final now = DateTime.now().toUtc();
    await enqueuePendingSettingEdit(now);
    await store.markEntityMutationConflicted(
      entity: 'user_setting',
      recordKey: 'theme',
      accountId: 'user-1',
      deviceId: 'local-device',
      reason: 'pulled_remote_winner',
      remoteRevision: 4,
    );

    expect(
      await store.listSyncConflicts(accountId: 'user-2'),
      isEmpty,
      reason: 'another account must not see or resolve this conflict',
    );
    expect(await store.listSyncConflicts(accountId: 'user-1'), hasLength(1));

    final foreignResolution = await store.resolveSyncConflict(
      entity: 'user_setting',
      recordKey: 'theme',
      accountId: 'user-2',
      deviceId: 'attacker-device',
      keepLocal: false,
    );
    expect(
      foreignResolution,
      isFalse,
      reason: 'resolution requires the owning account',
    );
    expect(await outboxRow('user_setting', 'theme'), isNotNull);
  });

  test(
    'failed-mutation dismissal can no longer silently delete conflicts',
    () async {
      final now = DateTime.now().toUtc();
      await enqueuePendingSettingEdit(now);
      await store.markEntityMutationConflicted(
        entity: 'user_setting',
        recordKey: 'theme',
        accountId: 'user-1',
        deviceId: 'local-device',
        reason: 'pulled_remote_winner',
        remoteRevision: 4,
      );

      await store.resolveFailedMutation(
        entity: 'user_setting',
        recordKey: 'theme',
        action: 'dismiss',
      );

      final row = await outboxRow('user_setting', 'theme');
      expect(row, isNotNull);
      expect(row!.state, 'conflict');
      expect(
        await store.listSyncConflicts(resolutionStatus: 'unresolved'),
        hasLength(1),
      );
    },
  );
}
