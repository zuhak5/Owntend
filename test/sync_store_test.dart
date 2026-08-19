import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/services/reminder_schedule_reconciler.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';

void main() {
  late AppDatabase db;
  late LocalSyncStore store;

  setUp(() async {
    db = AppDatabase(executor: NativeDatabase.memory());
    store = LocalSyncStore(db);
    await store.account();
  });

  tearDown(() => db.close());

  test('concurrent account initialization creates one stable row', () async {
    await db.delete(db.syncAccount).go();

    final accounts = await Future.wait(
      List<Future<SyncAccountData>>.generate(20, (_) => store.account()),
    );

    expect(await db.select(db.syncAccount).get(), hasLength(1));
    expect(accounts.map((account) => account.deviceId).toSet(), hasLength(1));
  });

  test(
    'account watcher emits null for zero rows and survives reinsertion',
    () async {
      final emissions = <SyncAccountData?>[];
      final errors = <Object>[];
      final subscription = store.watchAccount().listen(
        emissions.add,
        onError: errors.add,
      );
      addTearDown(subscription.cancel);

      await _waitForSyncStoreTest(() => emissions.isNotEmpty);
      expect(emissions.removeAt(0), isA<SyncAccountData>());

      await db.delete(db.syncAccount).go();

      await _waitForSyncStoreTest(() => emissions.isNotEmpty);
      expect(emissions.removeAt(0), isNull);

      final now = DateTime.utc(2026, 8, 3, 12);
      await db
          .into(db.syncAccount)
          .insert(
            SyncAccountData(
              id: 1,
              deviceId: 'replacement-device',
              enabled: false,
              uploadProhibited: false,
              migrationState: 'localOnly',
              restorePending: false,
              hydrationCompletedUnits: 0,
              hydrationTotalUnits: 0,
              updatedAt: now,
            ),
          );

      await _waitForSyncStoreTest(() => emissions.isNotEmpty);
      final replacement = emissions.removeAt(0);
      expect(replacement?.deviceId, 'replacement-device');
      expect(errors, isEmpty);
    },
  );

  test('outbox suppression is restored after a failed remote apply', () async {
    await expectLater(
      store.withOutboxSuppressed<void>(() async {
        throw StateError('forced apply failure');
      }),
      throwsStateError,
    );

    await _seedTestAreas(db, store);
    await DriftAssetRepository(db)
        .saveRoom(areaId: 'area_first_floor', name: 'Queued after failure');

    expect(
      (await store.pendingMutations()).any((item) => item.entity == 'room'),
      isTrue,
    );
  });

  test(
    'maintenance mutation state survives conflict recovery and restart',
    () async {
      final createdAt = DateTime.utc(2026, 7, 28, 12);
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              entity: 'maintenance_completion',
              recordKey: 'operation-1',
              operation: 'execute',
              payloadJson: const Value('{"version":1}'),
              userId: const Value('user-a'),
              changedAt: Value(createdAt),
              createdAt: Value(createdAt),
              state: const Value('pending'),
            ),
          );
      final pending = (await store.pendingMutations()).singleWhere(
        (mutation) => mutation.entity == 'maintenance_completion',
      );

      await store.markMutationInFlight(pending, userId: 'user-a');
      await store.markMaintenanceConflictRecovery(
        pending,
        payloadJson: '{"version":1,"expected_plan_revision":7}',
        errorCode: 'stale_plan_revision',
        message: 'Safe retry required.',
      );

      final persisted = (await store.pendingMutations()).singleWhere(
        (mutation) => mutation.entity == 'maintenance_completion',
      );
      expect(persisted.operationId, 'operation-1');
      expect(persisted.userId, 'user-a');
      expect(persisted.createdAt?.toUtc(), createdAt);
      expect(persisted.state, SyncMutationState.conflictRecovery);
      expect(persisted.lastErrorCode, 'stale_plan_revision');
      expect(persisted.payloadJson, contains('"expected_plan_revision":7'));
    },
  );

  test(
    'rejected maintenance completion rolls back committed local state',
    () async {
      final repository = DriftAssetRepository(db);
      await _seedTestAreas(db, store);
      final roomId = await repository.saveRoom(
        areaId: 'area_first_floor',
        name: 'Maintenance rollback room',
      );
      final assetId = await repository.saveAsset(
        name: 'Maintenance rollback asset',
        roomId: roomId,
      );

      final initialDueDate = DateTime.utc(2026, 7, 28);
      final initialUpdatedAt = DateTime.utc(2026, 7, 1, 8);
      await store.withOutboxSuppressed(() async {
        await db
            .into(db.maintenancePlans)
            .insert(
              MaintenancePlansCompanion.insert(
                id: 'rejected-maintenance-plan',
                assetId: assetId,
                title: 'Rejected completion task',
                recurrenceInterval: 1,
                recurrenceUnit: 'months',
                priority: 'medium',
                nextDueDate: initialDueDate,
                reminderDaysBefore: const Value(1),
                updatedAt: Value(initialUpdatedAt),
              ),
            );
      });
      await db.delete(db.syncOutbox).go();

      final initialReminder = ReminderScheduleEntry(
        identity: 'task:rejected-maintenance-plan',
        notificationId: 10123,
        planRevision: initialUpdatedAt.toIso8601String(),
        scheduledAt: DateTime.utc(2026, 7, 27, 9),
        timezone: 'Asia/Baghdad',
        localComponents: '2026-07-27T12:00:00',
        scheduleMode: 'inexactAllowWhileIdle',
        contentVersion: 'initial',
      );
      await DriftReminderScheduleStore(db).replaceAll([initialReminder]);

      final maintenance = DriftMaintenanceRepository(
        db,
        now: () => DateTime.utc(2026, 7, 28, 9),
      );
      expect(
        await maintenance.completePlan(
          'rejected-maintenance-plan',
          completedAt: initialDueDate,
          expectedNextDueDate: initialDueDate,
        ),
        isTrue,
      );

      final mutation = (await store.pendingMutations()).singleWhere(
        (item) => item.entity == 'maintenance_completion',
      );
      final queuedPayload =
          jsonDecode(mutation.payloadJson!) as Map<String, dynamic>;
      expect(queuedPayload['idempotency_key'], mutation.operationId);
      expect(queuedPayload['expected_next_due_date'], isNotNull);
      final preimage = queuedPayload['preimage'] as Map<String, dynamic>;
      final preimagePlan = preimage['plan'] as Map<String, dynamic>;
      expect(preimagePlan['next_due_date'], initialDueDate.toIso8601String());
      expect(
        await (db.select(
          db.maintenanceRecords,
        )..where((row) => row.id.equals(mutation.operationId))).get(),
        hasLength(1),
        reason: 'the current implementation is optimistic before sync',
      );

      await store.markMaintenanceCompletionFailedVisible(
        mutation,
        errorCode: 'occurrence_changed',
        message: 'The maintenance plan changed on another device.',
      );

      final restoredPlan =
          await (db.select(db.maintenancePlans)
                ..where((row) => row.id.equals('rejected-maintenance-plan')))
              .getSingle();
      expect(restoredPlan.nextDueDate.toUtc(), initialDueDate);
      expect(
        await (db.select(
          db.maintenanceRecords,
        )..where((row) => row.id.equals(mutation.operationId))).get(),
        isEmpty,
      );

      final failedRows = await (db.select(
        db.syncOutbox,
      )..where((row) => row.entity.equals('maintenance_completion'))).get();
      final failed = failedRows.singleWhere(
        (row) => row.recordKey == mutation.operationId,
      );
      expect(failed.state, SyncMutationState.failedVisible.name);
      expect(failed.lastErrorCode, 'occurrence_changed');

      final reminders = await DriftReminderScheduleStore(db).readAll();
      expect(reminders, hasLength(1));
      expect(reminders.single.identity, initialReminder.identity);
      expect(reminders.single.scheduledAt.toUtc(), initialReminder.scheduledAt);
      expect(reminders.single.planRevision, initialReminder.planRevision);
    },
  );

  test(
    'unlink clears account sync metadata but preserves domain rows',
    () async {
      final repository = DriftAssetRepository(db);
      await _seedTestAreas(db, store);
      final roomId = await repository.saveRoom(
        areaId: 'area_first_floor',
        name: 'Preserved room',
      );
      await store.setEnabled(
        enabled: true,
        boundUserId: 'user-a',
        migrationState: 'active',
      );
      await store.setCursor('room', 42);
      final before = await store.account();

      await store.clearBinding();

      final after = await store.account();
      expect(after.deviceId, before.deviceId);
      expect(after.boundUserId, isNull);
      expect(after.enabled, isFalse);
      expect(after.migrationState, 'localOnly');
      expect(await store.cursor('room'), 0);
      expect(await store.pendingCount(), 0);
      expect(await repository.getAsset(roomId), isNull);
      expect(
        (await repository.listRooms()).any((room) => room.id == roomId),
        isTrue,
      );
    },
  );

  test('sync lease prevents overlapping runners', () async {
    expect(await store.acquireLease('foreground'), isTrue);
    expect(await store.hasActiveLease(), isTrue);
    expect(await store.acquireLease('background'), isFalse);
    await store.releaseLease('foreground');
    expect(await store.hasActiveLease(), isFalse);
    expect(await store.acquireLease('background'), isTrue);
  });

  test('expired sync lease can be replaced by a new runner', () async {
    expect(
      await store.acquireLease(
        'expired-runner',
        duration: const Duration(milliseconds: -1),
      ),
      isTrue,
    );

    expect(await store.hasActiveLease(), isFalse);
    expect(await store.acquireLease('replacement-runner'), isTrue);
    expect(await store.hasActiveLease(), isTrue);
  });

  test('new identity binding discards stale account metadata only', () async {
    final repository = DriftAssetRepository(db);
    await _seedTestAreas(db, store);
    final roomId = await repository.saveRoom(
      areaId: 'area_first_floor',
      name: 'Local room to preserve',
    );
    await store.setCursor('room', 99);
    final originalDeviceId = (await store.account()).deviceId;

    await store.bindIdentity('new-user');

    final account = await store.account();
    expect(account.boundUserId, 'new-user');
    expect(account.deviceId, originalDeviceId);
    expect(await store.cursor('room'), 0);
    expect(await store.pendingCount(), 0);
    expect(
      (await repository.listRooms()).map((room) => room.id),
      contains(roomId),
    );

    await store.enqueueInitialSnapshot();
    expect(await store.pendingCount(), greaterThan(0));
  });

  test(
    'local-only restore pause clears sync metadata and keeps data',
    () async {
      final repository = DriftAssetRepository(db);
      await _seedTestAreas(db, store);
      final roomId = await repository.saveRoom(
        areaId: 'area_first_floor',
        name: 'Restored local room',
      );
      await store.bindIdentity('user-a');
      await store.setCursor('room', 8);

      await store.pauseAfterLocalRestore();

      final account = await store.account();
      expect(account.enabled, isFalse);
      expect(account.boundUserId, isNull);
      expect(account.migrationState, 'restorePaused');
      expect(account.restorePending, isTrue);
      expect(await store.cursor('room'), 0);
      expect(await store.pendingCount(), 0);
      expect(
        (await repository.listRooms()).map((room) => room.id),
        contains(roomId),
      );
    },
  );

  test('complete snapshot eligibility rejects unsafe caches', () async {
    final syncedAt = DateTime.utc(2026, 7, 26, 8);

    expect(await store.hasCompleteSnapshotForUser('user-a'), isFalse);

    await store.setEnabled(
      enabled: true,
      boundUserId: 'user-a',
      migrationState: 'active',
    );
    expect(await store.hasCompleteSnapshotForUser('user-a'), isFalse);

    await store.recordSyncSuccess(syncedAt);
    expect(await store.hasCompleteSnapshotForUser('user-a'), isTrue);
    expect(await store.hasCompleteSnapshotForUser('user-b'), isFalse);

    await store.recordMigrationState('migrating');
    expect(await store.hasCompleteSnapshotForUser('user-a'), isFalse);

    await store.recordSyncSuccess(syncedAt.add(const Duration(minutes: 1)));
    expect(await store.hasCompleteSnapshotForUser('user-a'), isTrue);

    await store.recordSyncBlocked('schema mismatch');
    expect(await store.hasCompleteSnapshotForUser('user-a'), isFalse);

    await store.recordSyncSuccess(syncedAt.add(const Duration(minutes: 2)));
    expect(await store.hasCompleteSnapshotForUser('user-a'), isTrue);

    await store.beginOrResumeHydration();
    expect(await store.hasCompleteSnapshotForUser('user-a'), isFalse);

    await store.completeHydration();
    expect(await store.hasCompleteSnapshotForUser('user-a'), isTrue);
  });

  test(
    'partial bootstrap cleanup clears cloud data and reseeds defaults',
    () async {
      final repository = DriftAssetRepository(db);
      await store.bindIdentity('user-a');
      await _seedTestAreas(db, store);
      final roomId = await repository.saveRoom(
        areaId: 'area_first_floor',
        name: 'Partially restored room',
      );
      await store.setCursor('room', 9);
      await store.beginOrResumeHydration();

      await store.clearPartialBootstrapForUser('user-a');

      final account = await store.account();
      expect(account.enabled, isFalse);
      expect(account.boundUserId, isNull);
      expect(account.migrationState, 'localOnly');
      expect(account.restorePending, isFalse);
      expect(await store.cursor('room'), 0);
      expect(await store.pendingCount(), 0);
      expect(
        (await repository.listRooms()).map((room) => room.id),
        isNot(contains(roomId)),
      );
      expect(await store.isDomainDataPristine(), isTrue);
    },
  );

  test('database triggers enqueue repository writes', () async {
    final repository = DriftAssetRepository(db);
    await _seedTestAreas(db, store);
    final before = await store.pendingCount();

    await repository.saveRoom(
      areaId: 'area_first_floor',
      name: 'Cloud test room',
      roomType: RoomType.office,
    );

    expect(await store.pendingCount(), before + 1);
    final pending = await store.pendingMutations();
    expect(pending.any((item) => item.entity == 'room'), isTrue);
  });

  test('database trigger writes wake the pending-count stream', () async {
    await _seedTestAreas(db, store);
    await db.delete(db.syncOutbox).go();
    final pendingChanged = store.watchPendingCount().firstWhere(
      (count) => count > 0,
    );

    await DriftAssetRepository(db).saveRoom(
      areaId: 'area_first_floor',
      name: 'Automatic upload room',
      roomType: RoomType.office,
    );

    expect(await pendingChanged.timeout(const Duration(seconds: 2)), 1);
  });

  test('pending writes follow foreign-key dependency order', () async {
    final repository = DriftAssetRepository(db);
    await _seedTestAreas(db, store);
    final roomId = await repository.saveRoom(
      areaId: 'area_first_floor',
      name: 'Dependency room',
    );
    await repository.saveAsset(
      name: 'Tagged cloud asset',
      roomId: roomId,
      tagNames: const ['Cloud'],
    );

    final pending = await store.pendingMutations();
    final assetIndex = pending.indexWhere((item) => item.entity == 'asset');
    final tagIndex = pending.indexWhere((item) => item.entity == 'tag');
    final relationIndex = pending.indexWhere(
      (item) => item.entity == 'asset_tag',
    );

    expect(assetIndex, isNonNegative);
    expect(tagIndex, isNonNegative);
    expect(relationIndex, isNonNegative);
    expect(assetIndex, lessThan(relationIndex));
    expect(tagIndex, lessThan(relationIndex));
  });

  test('tag names are reused case-insensitively', () async {
    final repository = DriftAssetRepository(db);
    await _seedTestAreas(db, store);
    final roomId = await repository.saveRoom(
      areaId: 'area_first_floor',
      name: 'Tag room',
    );
    await repository.saveAsset(
      name: 'First tagged asset',
      roomId: roomId,
      tagNames: const ['Home'],
    );
    await repository.saveAsset(
      name: 'Second tagged asset',
      roomId: roomId,
      tagNames: const ['home'],
    );

    expect(await db.select(db.tags).get(), hasLength(1));
    expect(await db.select(db.assetTags).get(), hasLength(2));
  });

  test(
    'remote application suppresses outbox feedback without owning pull cursor',
    () async {
      await store.discardMutation('area', 'area_first_floor');
      final before = await store.pendingCount();
      final spec = syncSpecByEntity['area']!;

      await store.applyRemoteRecords([
        SyncRecord(
          spec: spec,
          recordKey: 'area_first_floor',
          values: {
            'id': 'area_first_floor',
            'name': 'Remote floor',
            'kind': 'indoor',
            'sort_order': 0,
            'created_at': '2026-06-01T00:00:00.000Z',
            'updated_at': '2026-06-28T00:00:00.000Z',
            'archived_at': null,
          },
          clientModifiedAt: DateTime.utc(2026, 6, 28),
          originDeviceId: 'remote-device',
          revision: 2,
          syncSeq: 20,
          serverUpdatedAt: DateTime.utc(2026, 6, 28),
        ),
      ]);

      final area = await (db.select(
        db.areas,
      )..where((row) => row.id.equals('area_first_floor'))).getSingle();
      expect(area.name, 'Remote floor');
      expect(await store.pendingCount(), before);
      expect(await store.cursor('area'), 0);
    },
  );

  test(
    'remote application immediately refreshes Drift query streams',
    () async {
      final roomChanged = db
          .select(db.rooms)
          .watch()
          .firstWhere(
            (rows) => rows.any((row) => row.id == 'remote-reactive-room'),
          );
      final now = DateTime.utc(2026, 6, 30);

      await store.applyRemoteRecords([
        SyncRecord(
          spec: syncSpecByEntity['area']!,
          recordKey: 'area_first_floor',
          values: {
            'id': 'area_first_floor',
            'name': 'Remote floor',
            'kind': 'indoor',
            'sort_order': 0,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
            'archived_at': null,
          },
          clientModifiedAt: now,
          originDeviceId: 'remote-device',
          revision: 1,
          syncSeq: 20,
          serverUpdatedAt: now,
        ),
        SyncRecord(
          spec: syncSpecByEntity['room']!,
          recordKey: 'remote-reactive-room',
          values: {
            'id': 'remote-reactive-room',
            'area_id': 'area_first_floor',
            'name': 'Remote reactive room',
            'room_type': 'office',
            'notes': null,
            'sort_order': 1,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
            'archived_at': null,
          },
          clientModifiedAt: now,
          originDeviceId: 'remote-device',
          revision: 1,
          syncSeq: 21,
          serverUpdatedAt: now,
        ),
      ]);

      final rows = await roomChanged.timeout(const Duration(seconds: 2));
      expect(
        rows.singleWhere((row) => row.id == 'remote-reactive-room').name,
        'Remote reactive room',
      );
    },
  );

  test('remote tombstones delete children before parents', () async {
    final repository = DriftAssetRepository(db);
    await _seedTestAreas(db, store);
    final roomId = await repository.saveRoom(
      areaId: 'area_second_floor',
      name: 'Remote deletion room',
    );
    await store.discardMutation('room', roomId);
    await store.discardMutation('area', 'area_second_floor');
    final deletedAt = DateTime.utc(2026, 6, 28);

    await store.applyRemoteRecords([
      SyncRecord(
        spec: syncSpecByEntity['area']!,
        recordKey: 'area_second_floor',
        values: const {'id': 'area_second_floor'},
        clientModifiedAt: deletedAt,
        originDeviceId: 'remote-device',
        revision: 3,
        syncSeq: 30,
        serverUpdatedAt: deletedAt,
        deletedAt: deletedAt,
      ),
      SyncRecord(
        spec: syncSpecByEntity['room']!,
        recordKey: roomId,
        values: {'id': roomId},
        clientModifiedAt: deletedAt,
        originDeviceId: 'remote-device',
        revision: 3,
        syncSeq: 31,
        serverUpdatedAt: deletedAt,
        deletedAt: deletedAt,
      ),
    ]);

    expect(
      await (db.select(
        db.rooms,
      )..where((row) => row.id.equals(roomId))).getSingleOrNull(),
      isNull,
    );
    expect(
      await (db.select(
        db.areas,
      )..where((row) => row.id.equals('area_second_floor'))).getSingleOrNull(),
      isNull,
    );
  });

  test(
    'authoritative integrity check removes a missed remote hard delete',
    () async {
      final now = DateTime.utc(2026, 7, 28);
      final spec = syncSpecByEntity['area']!;
      await store.applyRemoteRecords([
        SyncRecord(
          spec: spec,
          recordKey: 'remote-deleted-area',
          values: {
            'id': 'remote-deleted-area',
            'name': 'Deleted elsewhere',
            'kind': 'indoor',
            'sort_order': 5,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
            'archived_at': null,
          },
          clientModifiedAt: now,
          originDeviceId: 'remote-device',
          revision: 1,
          syncSeq: now.microsecondsSinceEpoch,
          serverUpdatedAt: now,
        ),
      ]);

      final removed = await store.reconcileAuthoritativeRecordKeys(
        spec: spec,
        remoteKeys: const {},
      );

      expect(removed, 1);
      expect(
        await (db.select(db.areas)
              ..where((row) => row.id.equals('remote-deleted-area')))
            .getSingleOrNull(),
        isNull,
      );
    },
  );

  test(
    'authoritative integrity check never deletes a pending local change',
    () async {
      final now = DateTime.utc(2026, 7, 28);
      final spec = syncSpecByEntity['area']!;
      await store.applyRemoteRecords([
        SyncRecord(
          spec: spec,
          recordKey: 'locally-edited-area',
          values: {
            'id': 'locally-edited-area',
            'name': 'Remote name',
            'kind': 'indoor',
            'sort_order': 6,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
            'archived_at': null,
          },
          clientModifiedAt: now,
          originDeviceId: 'remote-device',
          revision: 1,
          syncSeq: now.microsecondsSinceEpoch,
          serverUpdatedAt: now,
        ),
      ]);
      await DriftAssetRepository(db).saveArea(
        id: 'locally-edited-area',
        name: 'Pending local name',
        kind: AreaKind.indoor,
        sortOrder: 6,
      );

      final removed = await store.reconcileAuthoritativeRecordKeys(
        spec: spec,
        remoteKeys: const {},
      );

      expect(removed, 0);
      expect(
        await (db.select(db.areas)
              ..where((row) => row.id.equals('locally-edited-area')))
            .getSingleOrNull(),
        isNotNull,
      );
    },
  );

  test('backup-only tables enqueue scoped sync mutations', () async {
    await db.delete(db.syncOutbox).go();
    final settings = DriftSettingsRepository(db);
    final inbox = DriftNotificationInboxRepository(db);

    await settings.setThemePreference(ThemePreference.dark);
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: 'weather_cache',
            value: '{"temperature":24}',
          ),
        );
    await inbox.createNotification(
      title: 'Task due',
      body: 'Water the plant',
      kind: 'task',
    );
    await inbox.createNotification(
      title: 'Task due',
      body: 'Water the plant',
      kind: 'task',
    );

    final pending = await store.pendingMutations();
    expect(
      pending.map((item) => item.entity),
      containsAll({'user_setting', 'notification_inbox'}),
    );
    final inboxRows = await db.select(db.inboxNotifications).get();
    expect(inboxRows, hasLength(1));
    expect(inboxRows.single.id, inboxRows.single.dedupeKey);
  });

  test('permission education setting defaults, watches, and syncs', () async {
    final settings = DriftSettingsRepository(db);
    final emissions = <bool>[];
    final subscription = settings.watchPermissionEducationSeen().listen(
      emissions.add,
    );
    addTearDown(subscription.cancel);

    expect(await settings.permissionEducationSeen(), isFalse);
    await _waitForSyncStoreTest(() => emissions.isNotEmpty);
    expect(emissions.last, isFalse);

    await db.delete(db.syncOutbox).go();
    await settings.setPermissionEducationSeen(true);

    await _waitForSyncStoreTest(() => emissions.lastOrNull == true);
    expect(await settings.permissionEducationSeen(), isTrue);
    expect(
      await store.pendingMutations(),
      contains(
        isA<LocalSyncMutation>()
            .having((item) => item.entity, 'entity', 'user_setting')
            .having(
              (item) => item.recordKey,
              'record key',
              'permission_education_seen_v2',
            )
            .having((item) => item.operation, 'operation', 'upsert'),
      ),
    );
    expect(
      syncSpecByEntity['user_setting']!.localWhere,
      contains("'permission_education_seen'"),
    );
    expect(
      syncSpecByEntity['user_setting']!.localWhere,
      contains("'permission_education_seen_v2'"),
    );
  });

  test('remote payloads omit local installation identity', () {
    final spec = syncSpecByEntity['user_setting']!;
    final record = SyncRecord(
      spec: spec,
      recordKey: 'theme',
      values: {
        'key': 'theme',
        'value': 'dark',
        'updated_at': '2026-06-29T00:00:00.000Z',
      },
      clientModifiedAt: DateTime.utc(2026, 6, 29),
      originDeviceId: '',
    );

    final payload = record.toRemotePayload('user-1', deviceId: 'device-a');

    expect(spec.scope, SyncScope.shared);
    expect(payload['user_id'], 'user-1');
    expect(payload.containsKey('device_id'), isFalse);
    expect(payload.containsKey('origin_device_id'), isFalse);
  });

  test('every supported sync entity has a table representation', () {
    final representedTables = {
      for (final spec in syncEntitySpecs) spec.localTable,
      profileSyncSpec.localTable,
    };

    expect(
      representedTables,
      containsAll({
        'areas',
        'rooms',
        'assets',
        'device_details',
        'pet_details',
        'plant_details',
        'safety_details',
        'tags',
        'asset_tags',
        'asset_photos',
        'maintenance_plans',
        'maintenance_records',
        'notification_inbox',
        'settings',
        'streaks',
      }),
    );
  });

  test('maintenance plan sync payload includes enabled state as a bool', () {
    final spec = syncSpecByEntity['maintenance_plan']!;

    expect(spec.localColumns, contains('is_enabled'));
    expect(spec.boolColumns, contains('is_enabled'));
  });

  test('manual reconciliation repairs missed upserts and deletes', () async {
    await db.delete(db.syncOutbox).go();

    await db
        .into(db.tags)
        .insert(TagsCompanion.insert(id: 'missing-upsert', name: 'Queued'));
    await db.delete(db.syncOutbox).go();
    await db
        .into(db.syncShadows)
        .insert(
          SyncShadowsCompanion.insert(
            entity: 'tag',
            recordKey: 'missing-delete',
            remoteRevision: 1,
          ),
        );

    await store.enqueueReconciliationSnapshot();

    final mutations = await store.pendingMutations();
    expect(
      mutations,
      contains(
        isA<LocalSyncMutation>()
            .having((item) => item.entity, 'entity', 'tag')
            .having((item) => item.recordKey, 'key', 'missing-upsert')
            .having((item) => item.operation, 'operation', 'upsert'),
      ),
    );
    expect(
      mutations,
      contains(
        isA<LocalSyncMutation>()
            .having((item) => item.entity, 'entity', 'tag')
            .having((item) => item.recordKey, 'key', 'missing-delete')
            .having((item) => item.operation, 'operation', 'delete'),
      ),
    );
  });

  test(
    'remote settings and catalog rows apply without outbox feedback',
    () async {
      await db.delete(db.syncOutbox).go();
      final now = DateTime.utc(2026, 6, 29);

      await store.applyRemoteRecords([
        SyncRecord(
          spec: syncSpecByEntity['user_setting']!,
          recordKey: 'theme',
          values: {
            'key': 'theme',
            'value': 'dark',
            'updated_at': now.toIso8601String(),
          },
          clientModifiedAt: now,
          originDeviceId: 'device-b',
          revision: 1,
          syncSeq: 100,
          serverUpdatedAt: now,
        ),
      ]);

      expect(
        await DriftSettingsRepository(db).themePreference(),
        ThemePreference.dark,
      );
      expect(await store.pendingCount(), 0);
    },
  );

  test('untouched defaults are recognized only while unchanged', () async {
    final now = DateTime.utc(2026, 6, 29);
    final themeRecord = SyncRecord(
      spec: syncSpecByEntity['user_setting']!,
      recordKey: 'theme',
      values: {
        'key': 'theme',
        'value': 'dark',
        'updated_at': now.toIso8601String(),
      },
      clientModifiedAt: now,
      originDeviceId: 'device-b',
      revision: 1,
      syncSeq: 1,
      serverUpdatedAt: now,
    );
    final areaRecord = SyncRecord(
      spec: syncSpecByEntity['area']!,
      recordKey: 'area_first_floor',
      values: {
        'id': 'area_first_floor',
        'name': 'Main Floor',
        'kind': 'indoor',
        'sort_order': 0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'archived_at': null,
      },
      clientModifiedAt: now,
      originDeviceId: 'device-b',
      revision: 1,
      syncSeq: 2,
      serverUpdatedAt: now,
    );

    expect(await store.isUntouchedSeed(themeRecord), isTrue);
    expect(await store.isUntouchedSeed(areaRecord), isFalse);

    await DriftSettingsRepository(db).setThemePreference(ThemePreference.dark);

    expect(await store.isUntouchedSeed(themeRecord), isFalse);
  });

  test(
    'fresh-install detection accepts defaults and rejects local edits',
    () async {
      expect(await store.isPristineForCloudBootstrap(), isTrue);

      await DriftSettingsRepository(db)
          .setThemePreference(ThemePreference.dark);

      expect(await store.isPristineForCloudBootstrap(), isFalse);
    },
  );

  test('fresh-install detection rejects deleted user-created data', () async {
    final repository = DriftAssetRepository(db);
    await repository.saveArea(
      id: 'area_created_then_deleted',
      name: 'Created then deleted',
      kind: AreaKind.indoor,
      sortOrder: 0,
    );
    await repository.deleteArea('area_created_then_deleted');

    expect(await store.isPristineForCloudBootstrap(), isFalse);
  });

  test(
    'remote home location invalidates and tombstones device weather cache',
    () async {
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: 'weather_cache',
              value: '{"temperature":24}',
            ),
          );
      await db.delete(db.syncOutbox).go();
      final now = DateTime.utc(2026, 6, 29);

      await store.applyRemoteRecords([
        SyncRecord(
          spec: syncSpecByEntity['user_setting']!,
          recordKey: 'home_location',
          values: {
            'key': 'home_location',
            'value': '{"label":"Baghdad","latitude":33.3,"longitude":44.4}',
            'updated_at': now.toIso8601String(),
          },
          clientModifiedAt: now,
          originDeviceId: 'device-b',
          revision: 1,
          syncSeq: 50,
          serverUpdatedAt: now,
        ),
      ]);

      expect(
        await (db.select(
          db.settings,
        )..where((row) => row.key.equals('weather_cache'))).getSingleOrNull(),
        isNull,
      );
      final pending = await store.pendingMutations();
      expect(
        pending,
        contains(
          isA<LocalSyncMutation>()
              .having((item) => item.entity, 'entity', 'device_setting')
              .having((item) => item.recordKey, 'record key', 'weather_cache')
              .having((item) => item.operation, 'operation', 'delete'),
        ),
      );
    },
  );

  test('remote inbox pulls retain 250 rows and queue tombstones', () async {
    final base = DateTime.utc(2026, 6, 1);
    await db.batch((batch) {
      batch.insertAll(db.inboxNotifications, [
        for (var index = 0; index < 251; index++)
          InboxNotificationsCompanion.insert(
            id: 'inbox-$index',
            title: 'Notification $index',
            body: 'Body $index',
            kind: 'system',
            dedupeKey: Value('dedupe-$index'),
            createdAt: Value(base.add(Duration(minutes: index))),
            updatedAt: Value(base.add(Duration(minutes: index))),
          ),
      ]);
    });
    await db.delete(db.syncOutbox).go();
    final now = DateTime.utc(2026, 6, 29);

    await store.applyRemoteRecords([
      SyncRecord(
        spec: syncSpecByEntity['notification_inbox']!,
        recordKey: 'remote-newest',
        values: {
          'id': 'remote-newest',
          'title': 'Newest',
          'body': 'Newest body',
          'kind': 'system',
          'route': null,
          'plan_id': null,
          'dedupe_key': 'remote-newest',
          'read_at': null,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
        clientModifiedAt: now,
        originDeviceId: 'device-b',
        revision: 1,
        syncSeq: 75,
        serverUpdatedAt: now,
      ),
    ]);

    expect(await db.select(db.inboxNotifications).get(), hasLength(250));
    final tombstones = (await store.pendingMutations())
        .where(
          (item) =>
              item.entity == 'notification_inbox' && item.operation == 'delete',
        )
        .toList();
    expect(tombstones, hasLength(2));
  });
}

Future<void> _waitForSyncStoreTest(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for sync store test condition.');
}

Future<void> _seedTestAreas(AppDatabase db, LocalSyncStore store) async {
  await store.withOutboxSuppressed(() async {
    final repository = DriftAssetRepository(db);
    await repository.saveArea(
      id: 'area_first_floor',
      name: 'First Floor',
      kind: AreaKind.indoor,
      sortOrder: 0,
    );
    await repository.saveArea(
      id: 'area_second_floor',
      name: 'Second Floor',
      kind: AreaKind.indoor,
      sortOrder: 1,
    );
  });
}
