part of '../local_sync_store.dart';

mixin _LocalSyncAccountStore on _LocalSyncStoreBase {
  @override
  Future<SyncAccountData> account() async {
    final existing = await (db.select(
      db.syncAccount,
    )..where((row) => row.id.equals(1))).getSingleOrNull();
    if (existing != null) {
      return existing;
    }
    final now = DateTime.now();
    final row = SyncAccountData(
      id: 1,
      deviceId: _localSyncUuid.v7(),
      enabled: false,
      migrationState: 'localOnly',
      restorePending: false,
      hydrationCompletedUnits: 0,
      hydrationTotalUnits: 0,
      updatedAt: now,
    );
    await db.into(db.syncAccount).insert(row, mode: InsertMode.insertOrIgnore);
    return (db.select(
      db.syncAccount,
    )..where((account) => account.id.equals(1))).getSingle();
  }

  Future<SyncAccountData?> existingAccount() {
    return (db.select(
      db.syncAccount,
    )..where((row) => row.id.equals(1))).getSingleOrNull();
  }

  Stream<SyncAccountData?> watchAccount() async* {
    await account();
    yield* (db.select(
      db.syncAccount,
    )..where((row) => row.id.equals(1))).watchSingleOrNull();
  }

  Future<InitialHydrationProgress?> hydrationProgress() async {
    final row = await account();
    final runId = row.hydrationRunId;
    final stateName = row.hydrationState;
    final stageName = row.hydrationStage;
    if (runId == null || stateName == null || stageName == null) return null;
    return InitialHydrationProgress(
      runId: runId,
      state: RestoreRunState.values.firstWhere(
        (value) => value.name == stateName,
        orElse: () => RestoreRunState.failed,
      ),
      stage: InitialHydrationStage.values.firstWhere(
        (value) => value.name == stageName,
        orElse: () => InitialHydrationStage.connecting,
      ),
      completedUnits: row.hydrationCompletedUnits,
      totalUnits: row.hydrationTotalUnits,
      startedAt: row.hydrationStartedAt ?? row.updatedAt,
      updatedAt: row.hydrationUpdatedAt ?? row.updatedAt,
      failure: row.hydrationError,
    );
  }

  Future<InitialHydrationProgress> beginOrResumeHydration() async {
    final current = await hydrationProgress();
    final now = DateTime.now();
    if (current != null && current.state == RestoreRunState.completed) {
      return current;
    }
    if (current != null && current.state != RestoreRunState.completed) {
      final retryingFinalization =
          current.state == RestoreRunState.failed &&
          current.stage == InitialHydrationStage.finalizing;
      if (retryingFinalization) {
        final now = DateTime.now();
        await (db.update(
          db.syncAccount,
        )..where((row) => row.id.equals(1))).write(
          SyncAccountCompanion(
            hydrationRunId: Value(_localSyncUuid.v7()),
            hydrationState: Value(RestoreRunState.running.name),
            hydrationStage: Value(InitialHydrationStage.finalizing.name),
            hydrationUpdatedAt: Value(now),
            hydrationError: const Value(null),
            updatedAt: Value(now),
          ),
        );
      } else {
        await _writeHydration(
          state: RestoreRunState.running,
          stage: current.stage,
          error: const Value(null),
        );
      }
      return (await hydrationProgress())!;
    }
    await (db.update(db.syncAccount)..where((row) => row.id.equals(1))).write(
      SyncAccountCompanion(
        hydrationRunId: Value(_localSyncUuid.v7()),
        hydrationState: Value(RestoreRunState.running.name),
        hydrationStage: Value(InitialHydrationStage.connecting.name),
        hydrationCompletedUnits: const Value(0),
        hydrationTotalUnits: const Value(0),
        hydrationStartedAt: Value(now),
        hydrationUpdatedAt: Value(now),
        hydrationError: const Value(null),
        updatedAt: Value(now),
      ),
    );
    return (await hydrationProgress())!;
  }

  Future<void> setHydrationPlan(int totalUnits) async {
    final current = await hydrationProgress();
    if (current == null || current.state == RestoreRunState.completed) return;
    if (current.totalUnits > 0) return;
    final monotonicTotal = math.max(
      math.max(totalUnits, 1),
      current.completedUnits,
    );
    await _writeHydration(totalUnits: monotonicTotal);
  }

  Future<void> addHydrationUnits(int units) async {
    if (units <= 0) return;
    final current = await hydrationProgress();
    if (current == null || current.state == RestoreRunState.completed) return;
    final completed = current.completedUnits + units;
    await _writeHydration(
      completedUnits: math.min(
        completed,
        math.max(current.totalUnits, completed),
      ),
      totalUnits: math.max(current.totalUnits, completed),
    );
  }

  Future<void> setHydrationStage(InitialHydrationStage stage) async {
    final current = await hydrationProgress();
    if (current == null || current.state == RestoreRunState.completed) return;
    if (stage.index < current.stage.index) return;
    await _writeHydration(
      state: RestoreRunState.running,
      stage: stage,
      error: const Value(null),
    );
  }

  Future<void> failHydration(String message) async {
    final current = await hydrationProgress();
    if (current == null || current.state == RestoreRunState.completed) return;
    await _writeHydration(state: RestoreRunState.failed, error: Value(message));
  }

  Future<void> completeHydration() async {
    final current = await hydrationProgress();
    if (current == null) return;
    final total = math.max(
      current.totalUnits,
      math.max(current.completedUnits, 1),
    );
    await _writeHydration(
      state: RestoreRunState.completed,
      completedUnits: total,
      totalUnits: total,
      error: const Value(null),
    );
  }

  Future<void> completeInitialHydration(
    DateTime completedAt, {
    required String expectedRunId,
  }) async {
    final current = await hydrationProgress();
    if (current == null) {
      throw StateError(
        'Initial hydration cannot be finalized before it starts.',
      );
    }
    if (current.runId != expectedRunId) {
      throw StateError('A newer restoration attempt replaced this one.');
    }
    if (current.state == RestoreRunState.completed) return;
    final total = math.max(
      current.totalUnits,
      math.max(current.completedUnits, 1),
    );
    final updated =
        await (db.update(db.syncAccount)..where(
              (row) =>
                  row.id.equals(1) &
                  row.hydrationRunId.equals(expectedRunId) &
                  row.hydrationState.equals(RestoreRunState.running.name),
            ))
            .write(
              SyncAccountCompanion(
                lastSyncedAt: Value(completedAt),
                lastSyncAttemptAt: Value(completedAt),
                lastSyncFailureAt: const Value(null),
                lastError: const Value(null),
                blockedReason: const Value(null),
                migrationState: const Value('active'),
                hydrationState: Value(RestoreRunState.completed.name),
                hydrationStage: Value(InitialHydrationStage.finalizing.name),
                hydrationCompletedUnits: Value(total),
                hydrationTotalUnits: Value(total),
                hydrationUpdatedAt: Value(completedAt),
                hydrationError: const Value(null),
                updatedAt: Value(completedAt),
              ),
            );
    if (updated != 1) {
      throw StateError('A newer restoration attempt replaced this one.');
    }
  }

  Future<List<String>> remotePhotoRecordKeys(String userId) async {
    final rows = await db
        .customSelect(
          '''
SELECT id
FROM asset_photos
WHERE cloud_object_path IS NOT NULL
  AND cloud_object_path LIKE ?
  AND (relative_path IS NULL OR relative_path = '')
ORDER BY created_at DESC, id DESC
''',
          variables: [Variable<String>('$userId/%')],
          readsFrom: {db.assetPhotos},
        )
        .get();
    return [for (final row in rows) row.read<String>('id')];
  }

  Future<void> _writeHydration({
    RestoreRunState? state,
    InitialHydrationStage? stage,
    int? completedUnits,
    int? totalUnits,
    Value<String?> error = const Value.absent(),
  }) async {
    final now = DateTime.now();
    await (db.update(db.syncAccount)..where((row) => row.id.equals(1))).write(
      SyncAccountCompanion(
        hydrationState: state == null
            ? const Value.absent()
            : Value(state.name),
        hydrationStage: stage == null
            ? const Value.absent()
            : Value(stage.name),
        hydrationCompletedUnits: completedUnits == null
            ? const Value.absent()
            : Value(completedUnits),
        hydrationTotalUnits: totalUnits == null
            ? const Value.absent()
            : Value(totalUnits),
        hydrationUpdatedAt: Value(now),
        hydrationError: error,
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> setEnabled({
    required bool enabled,
    String? boundUserId,
    String? migrationState,
    bool clearError = true,
  }) async {
    await account();
    await (db.update(db.syncAccount)..where((row) => row.id.equals(1))).write(
      SyncAccountCompanion(
        enabled: Value(enabled),
        boundUserId: boundUserId == null
            ? const Value.absent()
            : Value(boundUserId),
        migrationState: migrationState == null
            ? const Value.absent()
            : Value(migrationState),
        lastError: clearError ? const Value(null) : const Value.absent(),
        blockedReason: clearError ? const Value(null) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> bindIdentity(String userId) async {
    await db.transaction(() async {
      final current = await account();
      if (current.boundUserId != null && current.boundUserId != userId) {
        throw StateError('Local data is bound to another cloud identity.');
      }
      if (current.boundUserId == userId) {
        await (db.update(
          db.syncAccount,
        )..where((row) => row.id.equals(1))).write(
          SyncAccountCompanion(
            enabled: const Value(true),
            migrationState: Value(
              current.migrationState == 'localOnly'
                  ? 'binding'
                  : current.migrationState,
            ),
            lastError: const Value(null),
            blockedReason: const Value(null),
            restorePending: const Value(false),
            updatedAt: Value(DateTime.now()),
          ),
        );
        return;
      }
      if (current.boundUserId == null) {
        await db.delete(db.syncCursors).go();
        await db.delete(db.syncShadows).go();
        await db.delete(db.syncOutbox).go();
        await db.delete(db.syncMediaCleanup).go();
        await (db.update(
          db.syncRuntime,
        )..where((row) => row.id.equals(1))).write(
          const SyncRuntimeCompanion(
            suppressOutbox: Value(false),
            leaseOwner: Value(null),
            leaseExpiresAt: Value(null),
          ),
        );
      }
      await (db.update(db.syncAccount)..where((row) => row.id.equals(1))).write(
        SyncAccountCompanion(
          enabled: const Value(true),
          boundUserId: Value(userId),
          migrationState: const Value('binding'),
          lastError: const Value(null),
          blockedReason: const Value(null),
          restorePending: const Value(false),
          hydrationRunId: const Value(null),
          hydrationState: const Value(null),
          hydrationStage: const Value(null),
          hydrationCompletedUnits: const Value(0),
          hydrationTotalUnits: const Value(0),
          hydrationStartedAt: const Value(null),
          hydrationUpdatedAt: const Value(null),
          hydrationError: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  Future<void> clearBinding() async {
    await account();
    await db.transaction(() async {
      await db.delete(db.syncCursors).go();
      await db.delete(db.syncShadows).go();
      await db.delete(db.syncOutbox).go();
      await db.delete(db.syncConflicts).go();
      await db.delete(db.syncMediaCleanup).go();
      await (db.update(db.syncRuntime)..where((row) => row.id.equals(1))).write(
        const SyncRuntimeCompanion(
          suppressOutbox: Value(false),
          leaseOwner: Value(null),
          leaseExpiresAt: Value(null),
        ),
      );
      await (db.update(db.syncAccount)..where((row) => row.id.equals(1))).write(
        SyncAccountCompanion(
          enabled: const Value(false),
          boundUserId: const Value(null),
          migrationState: const Value('localOnly'),
          lastSyncedAt: const Value(null),
          lastSyncAttemptAt: const Value(null),
          lastSyncFailureAt: const Value(null),
          lastError: const Value(null),
          blockedReason: const Value(null),
          restorePending: const Value(false),
          backgroundResult: const Value(null),
          hydrationRunId: const Value(null),
          hydrationState: const Value(null),
          hydrationStage: const Value(null),
          hydrationCompletedUnits: const Value(0),
          hydrationTotalUnits: const Value(0),
          hydrationStartedAt: const Value(null),
          hydrationUpdatedAt: const Value(null),
          hydrationError: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  Future<void> pauseAfterLocalRestore() async {
    await account();
    await db.transaction(() async {
      await db.delete(db.syncCursors).go();
      await db.delete(db.syncShadows).go();
      await db.delete(db.syncOutbox).go();
      await db.delete(db.syncMediaCleanup).go();
      await (db.update(db.syncRuntime)..where((row) => row.id.equals(1))).write(
        const SyncRuntimeCompanion(
          suppressOutbox: Value(false),
          leaseOwner: Value(null),
          leaseExpiresAt: Value(null),
        ),
      );
      await (db.update(db.syncAccount)..where((row) => row.id.equals(1))).write(
        SyncAccountCompanion(
          enabled: const Value(false),
          boundUserId: const Value(null),
          migrationState: const Value('restorePaused'),
          restorePending: const Value(true),
          lastSyncedAt: const Value(null),
          lastSyncAttemptAt: const Value(null),
          lastSyncFailureAt: const Value(null),
          lastError: const Value(null),
          blockedReason: const Value(null),
          backgroundResult: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  Future<bool> isPristineForCloudBootstrap() async {
    final syncAccount = await account();
    if (syncAccount.boundUserId != null ||
        syncAccount.lastSyncedAt != null ||
        await _tableHasRows('sync_cursors') ||
        await _tableHasRows('sync_shadows')) {
      return false;
    }

    return isDomainDataPristine();
  }

  Future<bool> isDomainDataPristine() async {
    for (final table in const [
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
    ]) {
      if (await _tableHasRows(table)) return false;
    }

    if (!await _tableExactlyMatchesSeeds('areas', const {})) {
      return false;
    }
    if (!await _tableExactlyMatchesSeeds('streaks', _seedValues['streak']!)) {
      return false;
    }

    return await _tableExactlyMatchesSeeds(
          'settings',
          _seedValues['user_setting']!,
        ) &&
        await _outboxContainsOnlySeedUpserts();
  }

  Future<bool> _outboxContainsOnlySeedUpserts() async {
    final allowed = <String>{
      for (final key in _seedValues['user_setting']!.keys) 'user_setting|$key',
      for (final key in _seedValues['streak']!.keys) 'streak|$key',
    };
    final rows = await db.select(db.syncOutbox).get();
    return rows.every(
      (row) =>
          row.operation == 'upsert' &&
          allowed.contains('${row.entity}|${row.recordKey}'),
    );
  }

  Future<bool> _tableHasRows(String table) async {
    return await db
            .customSelect('SELECT 1 FROM $table LIMIT 1')
            .getSingleOrNull() !=
        null;
  }

  Future<bool> _tableExactlyMatchesSeeds(
    String table,
    Map<String, Map<String, Object?>> expectedRows,
  ) async {
    final count = await db
        .customSelect('SELECT COUNT(*) AS count FROM $table')
        .getSingle();
    if (count.read<int>('count') != expectedRows.length) return false;
    for (final expected in expectedRows.values) {
      final key = expected.entries.first;
      final row = await db
          .customSelect(
            'SELECT ${expected.keys.join(', ')} FROM $table '
            'WHERE ${key.key} = ? LIMIT 1',
            variables: [Variable<Object>(key.value as Object)],
          )
          .getSingleOrNull();
      if (row == null) return false;
      for (final entry in expected.entries) {
        final actual = row.data[entry.key];
        if (entry.value is bool) {
          if ((actual == true || actual == 1) != entry.value) return false;
        } else if (actual != entry.value) {
          return false;
        }
      }
    }
    return true;
  }

  Future<bool> hasCompleteSnapshotForUser(String userId) async {
    final syncAccount = await account();
    if (!syncAccount.enabled ||
        syncAccount.boundUserId != userId ||
        syncAccount.lastSyncedAt == null ||
        syncAccount.restorePending ||
        syncAccount.migrationState != 'active' ||
        syncAccount.blockedReason != null) {
      return false;
    }
    final hydration = await hydrationProgress();
    if (hydration != null && hydration.state != RestoreRunState.completed) {
      return false;
    }
    return true;
  }

  Future<void> validateCriticalHomeData() async {
    final foreignKeyFailures = await db
        .customSelect('PRAGMA foreign_key_check')
        .get();
    if (foreignKeyFailures.isNotEmpty) {
      throw StateError(
        'The restored local Home snapshot has invalid relationships.',
      );
    }
    for (final table in const [
      'settings',
      'rooms',
      'assets',
      'maintenance_plans',
    ]) {
      await db.customSelect('SELECT COUNT(*) FROM $table').getSingle();
    }
  }

  Future<void> clearPartialBootstrapForUser(String userId) async {
    final syncAccount = await account();
    if (syncAccount.boundUserId != userId || syncAccount.lastSyncedAt != null) {
      return;
    }
    await db.transaction(() async {
      for (final table in const [
        'notification_inbox',
        'maintenance_records',
        'maintenance_plan_metadata',
        'maintenance_plans',
        'asset_photos',
        'asset_tags',
        'tags',
        'device_details',
        'pet_details',
        'plant_details',
        'safety_details',
        'assets',
        'rooms',
        'areas',
        'settings',
        'streaks',
      ]) {
        await db.customStatement('DELETE FROM $table');
      }
      await _seedPristineDefaults();
      await clearBinding();
    });
  }

  Future<void> clearAllAccountData({String? expectedUserId}) async {
    final syncAccount = await account();
    if (expectedUserId != null &&
        syncAccount.boundUserId != null &&
        syncAccount.boundUserId != expectedUserId) {
      throw StateError('Local data is bound to a different cloud identity.');
    }

    await db.transaction(() async {
      await (db.update(db.syncRuntime)..where((row) => row.id.equals(1))).write(
        const SyncRuntimeCompanion(suppressOutbox: Value(true)),
      );
      for (final table in const [
        'notification_reconciliation_requests',
        'notification_inbox',
        'reminder_schedule_snapshot',
        'maintenance_records',
        'maintenance_plan_metadata',
        'maintenance_plans',
        'asset_photos',
        'asset_tags',
        'tags',
        'device_details',
        'pet_details',
        'plant_details',
        'safety_details',
        'assets',
        'rooms',
        'areas',
        'settings',
        'streaks',
      ]) {
        await db.customStatement('DELETE FROM $table');
      }
      await db.customStatement('DELETE FROM search_index');
      await _seedPristineDefaults();
      await db.delete(db.syncCursors).go();
      await db.delete(db.syncShadows).go();
      await db.delete(db.syncOutbox).go();
      await db.delete(db.syncConflicts).go();
      await db.delete(db.syncMediaCleanup).go();
      await db.delete(db.syncAccount).go();
      await (db.update(db.syncRuntime)..where((row) => row.id.equals(1))).write(
        const SyncRuntimeCompanion(
          suppressOutbox: Value(false),
          leaseOwner: Value(null),
          leaseExpiresAt: Value(null),
        ),
      );
    });
  }

  Future<void> _seedPristineDefaults() async {
    final now = DateTime.now();
    for (final row in _seedValues['user_setting']!.values) {
      await db.customInsert(
        '''
INSERT OR IGNORE INTO settings(key, value, updated_at)
VALUES (?, ?, ?)
''',
        variables: [
          Variable<String>(row['key']! as String),
          Variable<String>(row['value']! as String),
          Variable<DateTime>(now),
        ],
        updates: {db.settings},
      );
    }
    for (final row in _seedValues['streak']!.values) {
      await db.customInsert(
        '''
INSERT OR IGNORE INTO streaks(id, current_streak, best_streak, updated_at)
VALUES (?, ?, ?, ?)
''',
        variables: [
          Variable<String>(row['id']! as String),
          Variable<int>(row['current_streak']! as int),
          Variable<int>(row['best_streak']! as int),
          Variable<DateTime>(now),
        ],
        updates: {db.streaks},
      );
    }
  }
}
