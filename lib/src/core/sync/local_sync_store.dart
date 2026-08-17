import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/categories.dart';
import '../data/repositories.dart';
import '../database/app_database.dart';
import 'sync_contracts.dart';
import 'sync_dtos.dart';

class LocalSyncStore {
  LocalSyncStore(this.db);

  final AppDatabase db;
  static const _uuid = Uuid();

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
      deviceId: _uuid.v7(),
      enabled: false,
      uploadProhibited: false,
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
            hydrationRunId: Value(_uuid.v7()),
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
        hydrationRunId: Value(_uuid.v7()),
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
WHERE relative_path LIKE ?
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
      if (current.uploadProhibited || current.migrationState == 'quarantined') {
        throw StateError(
          'Local data is quarantined. User confirmation is required before binding.',
        );
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
          uploadProhibited: const Value(false),
          quarantineReason: const Value(null),
          legacyOwnerId: const Value(null),
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

  Future<void> quarantineLegacyData({
    required String legacyUserId,
    required String reason,
  }) async {
    await account();
    await db.transaction(() async {
      await db.delete(db.syncCursors).go();
      await db.delete(db.syncShadows).go();
      await db.delete(db.syncOutbox).go();
      await db.delete(db.syncMediaCleanup).go();
      await (db.update(db.syncAccount)..where((row) => row.id.equals(1))).write(
        SyncAccountCompanion(
          enabled: const Value(false),
          boundUserId: const Value(null),
          uploadProhibited: const Value(true),
          quarantineReason: Value(reason),
          legacyOwnerId: Value(legacyUserId),
          migrationState: const Value('quarantined'),
          blockedReason: const Value('quarantined'),
          lastSyncedAt: const Value(null),
          lastSyncAttemptAt: const Value(null),
          lastSyncFailureAt: const Value(null),
          lastError: const Value(null),
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

  Future<void> resolveQuarantineWithReset() async {
    await clearAllAccountData();
  }

  Future<void> resolveQuarantineWithImport(String userId) async {
    await account();
    await db.transaction(() async {
      await (db.update(db.syncAccount)..where((row) => row.id.equals(1))).write(
        SyncAccountCompanion(
          enabled: const Value(true),
          boundUserId: Value(userId),
          uploadProhibited: const Value(false),
          quarantineReason: const Value(null),
          legacyOwnerId: const Value(null),
          migrationState: const Value('binding'),
          blockedReason: const Value(null),
          restorePending: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await enqueueInitialSnapshot();
    });
  }

  Future<void> clearBinding() async {
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
          uploadProhibited: const Value(false),
          quarantineReason: const Value(null),
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
      'notifications',
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
        'notifications',
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
        'categories',
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
        'notifications',
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
        'categories',
      ]) {
        await db.customStatement('DELETE FROM $table');
      }
      await db.customStatement('DELETE FROM search_index');
      await _seedPristineDefaults();
      await db.delete(db.syncCursors).go();
      await db.delete(db.syncShadows).go();
      await db.delete(db.syncOutbox).go();
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
    for (final c in appCategories) {
      await db.customInsert(
        '''
INSERT OR IGNORE INTO categories(id, name, health_group, icon_name, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?)
''',
        variables: [
          Variable<String>(c.id),
          Variable<String>(c.name),
          Variable<String>(c.healthGroup.name),
          Variable<String>(c.iconName),
          Variable<DateTime>(now),
          Variable<DateTime>(now),
        ],
        updates: {db.categories},
      );
    }
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

  Future<void> recordSyncSuccess(DateTime completedAt) async {
    await (db.update(db.syncAccount)..where((row) => row.id.equals(1))).write(
      SyncAccountCompanion(
        lastSyncedAt: Value(completedAt),
        lastSyncAttemptAt: Value(completedAt),
        lastError: const Value(null),
        blockedReason: const Value(null),
        migrationState: const Value('active'),
        updatedAt: Value(completedAt),
      ),
    );
  }

  Future<bool> shouldRunIntegrityCheck({
    Duration maximumAge = const Duration(hours: 24),
    DateTime? now,
  }) async {
    final lastCheck = (await account()).lastIntegrityCheckAt;
    if (lastCheck == null) return true;
    final elapsed = (now ?? DateTime.now()).difference(lastCheck);
    return elapsed.isNegative || elapsed > maximumAge;
  }

  Future<void> recordIntegrityCheck(DateTime completedAt) {
    return (db.update(db.syncAccount)..where((row) => row.id.equals(1))).write(
      SyncAccountCompanion(
        lastIntegrityCheckAt: Value(completedAt),
        updatedAt: Value(completedAt),
      ),
    );
  }

  Future<int> reconcileAuthoritativeRecordKeys({
    required SyncEntitySpec spec,
    required Set<String> remoteKeys,
  }) async {
    if (spec.keyColumns.isEmpty) return 0;
    final shadowRows = await (db.select(
      db.syncShadows,
    )..where((row) => row.entity.equals(spec.entity))).get();
    if (shadowRows.isEmpty) return 0;
    final pendingRows = await (db.select(
      db.syncOutbox,
    )..where((row) => row.entity.equals(spec.entity))).get();
    final pendingKeys = {for (final row in pendingRows) row.recordKey};
    final missing = [
      for (final shadow in shadowRows)
        if (!remoteKeys.contains(shadow.recordKey) &&
            !pendingKeys.contains(shadow.recordKey))
          shadow.recordKey,
    ];
    if (missing.isEmpty) return 0;

    await db.transaction(() async {
      await withOutboxSuppressed(() async {
        for (final recordKey in missing) {
          final parts = recordKey.split('|');
          final values = <String, Object?>{
            for (var index = 0; index < spec.keyColumns.length; index++)
              spec.keyColumns[index]: parts[index],
          };
          await _deleteLocal(
            SyncRecord(
              spec: spec,
              recordKey: recordKey,
              values: values,
              clientModifiedAt: DateTime.now().toUtc(),
              originDeviceId: 'integrity-check',
              deletedAt: DateTime.now().toUtc(),
            ),
          );
          await (db.delete(db.syncShadows)..where(
                (row) =>
                    row.entity.equals(spec.entity) &
                    row.recordKey.equals(recordKey),
              ))
              .go();
        }
      });
    });
    return missing.length;
  }

  Future<void> recordSyncAttempt(DateTime attemptedAt) async {
    await account();
    await (db.update(db.syncAccount)..where((row) => row.id.equals(1))).write(
      SyncAccountCompanion(
        lastSyncAttemptAt: Value(attemptedAt),
        updatedAt: Value(attemptedAt),
      ),
    );
  }

  Future<void> recordMigrationState(String state) async {
    await account();
    await (db.update(db.syncAccount)..where((row) => row.id.equals(1))).write(
      SyncAccountCompanion(
        migrationState: Value(state),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> recordSyncFailure(String message) async {
    await account();
    final now = DateTime.now();
    await (db.update(db.syncAccount)..where((row) => row.id.equals(1))).write(
      SyncAccountCompanion(
        lastError: Value(message),
        lastSyncFailureAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> recordSyncBlocked(String reason) async {
    await account();
    final now = DateTime.now();
    await (db.update(db.syncAccount)..where((row) => row.id.equals(1))).write(
      SyncAccountCompanion(
        lastError: Value(reason),
        blockedReason: Value(reason),
        lastSyncFailureAt: Value(now),
        migrationState: const Value('blocked'),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> recordBackgroundResult(String result) async {
    await account();
    await (db.update(db.syncAccount)..where((row) => row.id.equals(1))).write(
      SyncAccountCompanion(
        backgroundResult: Value(result),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> pendingCount() async {
    final count = db.syncOutbox.entity.count();
    final query = db.selectOnly(db.syncOutbox)
      ..addColumns([count])
      ..where(db.syncOutbox.attempts.isBiggerOrEqualValue(0));
    return (await query.map((row) => row.read(count) ?? 0).getSingle());
  }

  Future<Map<SyncMutationState, int>> mutationStateCounts() async {
    final rows = await db
        .customSelect(
          '''
SELECT state, COUNT(*) AS item_count
FROM offline_mutation_queue
GROUP BY state
''',
          readsFrom: {db.syncOutbox},
        )
        .get();
    final counts = {for (final state in SyncMutationState.values) state: 0};
    for (final row in rows) {
      counts[SyncMutationState.fromStorage(row.read<String>('state'))] = row
          .read<int>('item_count');
    }
    return counts;
  }

  Stream<int> watchPendingCount() {
    final count = db.syncOutbox.entity.count();
    final query = db.selectOnly(db.syncOutbox)
      ..addColumns([count])
      ..where(db.syncOutbox.attempts.isBiggerOrEqualValue(0));
    return query.map((row) => row.read(count) ?? 0).watchSingle().distinct();
  }

  Future<bool> hasReadyMutations() async {
    final count = db.syncOutbox.entity.count();
    final now = DateTime.now();
    final query = db.selectOnly(db.syncOutbox)
      ..addColumns([count])
      ..where(
        db.syncOutbox.attempts.isBiggerOrEqualValue(0) &
            (db.syncOutbox.nextAttemptAt.isNull() |
                db.syncOutbox.nextAttemptAt.isSmallerOrEqualValue(now)),
      );
    return (await query.map((row) => row.read(count) ?? 0).getSingle()) > 0;
  }

  Future<int> pendingMediaCleanupCount() async {
    final count = db.syncMediaCleanup.objectPath.count();
    final query = db.selectOnly(db.syncMediaCleanup)..addColumns([count]);
    return query.map((row) => row.read(count) ?? 0).getSingle();
  }

  Future<bool> acquireLease(
    String owner, {
    Duration duration = const Duration(minutes: 5),
  }) async {
    await _seedRuntimeIfNeeded();
    final now = DateTime.now();
    final expiresAt = now.add(duration);
    final updated = await db.customUpdate(
      '''
UPDATE sync_runtime
SET lease_owner = ?, lease_expires_at = ?
WHERE id = 1
  AND (
    lease_owner IS NULL
    OR lease_owner = ?
    OR lease_expires_at IS NULL
    OR lease_expires_at <= ?
  )
''',
      variables: [
        Variable<String>(owner),
        Variable<DateTime>(expiresAt),
        Variable<String>(owner),
        Variable<DateTime>(now),
      ],
      updates: {db.syncRuntime},
      updateKind: UpdateKind.update,
    );
    return updated == 1;
  }

  Future<bool> hasActiveLease({DateTime? now}) async {
    await _seedRuntimeIfNeeded();
    final currentTime = now ?? DateTime.now();
    final row = await (db.select(
      db.syncRuntime,
    )..where((runtime) => runtime.id.equals(1))).getSingleOrNull();
    final expiresAt = row?.leaseExpiresAt;
    return row?.leaseOwner != null &&
        expiresAt != null &&
        expiresAt.isAfter(currentTime);
  }

  Future<void> releaseLease(String owner) async {
    await (db.update(
      db.syncRuntime,
    )..where((row) => row.id.equals(1) & row.leaseOwner.equals(owner))).write(
      const SyncRuntimeCompanion(
        leaseOwner: Value(null),
        leaseExpiresAt: Value(null),
      ),
    );
  }

  Future<void> _seedRuntimeIfNeeded() async {
    await db
        .into(db.syncRuntime)
        .insert(
          SyncRuntimeCompanion.insert(id: const Value(1)),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<DateTime?> nextRetryAt() async {
    final outboxMinimum = db.syncOutbox.nextAttemptAt.min();
    final outboxQuery = db.selectOnly(db.syncOutbox)
      ..addColumns([outboxMinimum])
      ..where(
        db.syncOutbox.attempts.isBiggerOrEqualValue(0) &
            db.syncOutbox.nextAttemptAt.isNotNull(),
      );
    final cleanupMinimum = db.syncMediaCleanup.nextAttemptAt.min();
    final cleanupQuery = db.selectOnly(db.syncMediaCleanup)
      ..addColumns([cleanupMinimum])
      ..where(
        db.syncMediaCleanup.nextAttemptAt.isNotNull() &
            db.syncMediaCleanup.attempts.isBiggerOrEqualValue(0),
      );
    final candidates = <DateTime?>[
      await outboxQuery.map((row) => row.read(outboxMinimum)).getSingle(),
      await cleanupQuery.map((row) => row.read(cleanupMinimum)).getSingle(),
    ].whereType<DateTime>().toList();
    candidates.sort();
    return candidates.firstOrNull;
  }

  Future<void> deferPendingAfterFailure(
    String message, {
    Duration delay = const Duration(seconds: 15),
  }) async {
    await db.customUpdate(
      '''
UPDATE offline_mutation_queue
SET next_attempt_at = ?, last_error = ?
WHERE next_attempt_at IS NULL OR next_attempt_at <= ?
''',
      variables: [
        Variable<DateTime>(DateTime.now().add(delay)),
        Variable<String>(message),
        Variable<DateTime>(DateTime.now()),
      ],
      updates: {db.syncOutbox},
      updateKind: UpdateKind.update,
    );
  }

  Future<List<LocalSyncMutation>> pendingMutations({int limit = 200}) async {
    final now = DateTime.now();
    final allOutboxRows = await db.select(db.syncOutbox).get();
    final allOutboxKeys = {for (final row in allOutboxRows) row.recordKey};

    final query = db.select(db.syncOutbox)
      ..where(
        (row) =>
            row.attempts.isBiggerOrEqualValue(0) &
            (row.nextAttemptAt.isNull() |
                row.nextAttemptAt.isSmallerOrEqualValue(now)),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.changedAt)])
      ..limit(limit);
    final rows = await query.get();
    final rawMutations = [
      for (final row in rows)
        LocalSyncMutation(
          entity: row.entity,
          recordKey: row.recordKey,
          operation: row.operation,
          changedAt: row.changedAt,
          attempts: row.attempts,
          generation: row.generation,
          payloadJson: row.payloadJson,
          userId: row.userId,
          createdAt: row.createdAt,
          state: SyncMutationState.fromStorage(row.state),
          lastErrorCode: row.lastErrorCode,
          lastError: row.lastError,
          nextRetryAt: row.nextAttemptAt,
        ),
    ];

    final mutations = <LocalSyncMutation>[];
    for (final mutation in rawMutations) {
      if (mutation.entity == 'maintenance_completion' &&
          mutation.payloadJson != null) {
        try {
          final decoded =
              jsonDecode(mutation.payloadJson!) as Map<String, dynamic>;
          final dependsOn = decoded['depends_on_operation_id'] as String?;
          if (dependsOn != null &&
              dependsOn.isNotEmpty &&
              allOutboxKeys.contains(dependsOn)) {
            continue;
          }
        } catch (_) {}
      }
      mutations.add(mutation);
    }

    final dependencyOrder = {
      for (var index = 0; index < syncEntitySpecs.length; index++)
        syncEntitySpecs[index].entity: index,
      profileSyncSpec.entity: syncEntitySpecs.length,
    };

    dependencyOrder['asset_photo_primary'] = syncEntitySpecs.length + 1;

    final maintenancePlanOrder = dependencyOrder['maintenance_plan'];
    if (maintenancePlanOrder != null) {
      dependencyOrder['maintenance_completion'] = maintenancePlanOrder;
      dependencyOrder['maintenance_undo'] = maintenancePlanOrder;
    }

    mutations.sort((a, b) {
      if (a.entity == 'maintenance_undo' && b.entity != 'maintenance_undo') {
        return -1;
      }
      if (b.entity == 'maintenance_undo' && a.entity != 'maintenance_undo') {
        return 1;
      }

      final aDelete = a.operation == 'delete';
      final bDelete = b.operation == 'delete';
      if (aDelete != bDelete) {
        return aDelete ? -1 : 1;
      }

      final aOrder = dependencyOrder[a.entity] ?? dependencyOrder.length;
      final bOrder = dependencyOrder[b.entity] ?? dependencyOrder.length;
      final dependencyComparison = aDelete
          ? bOrder.compareTo(aOrder)
          : aOrder.compareTo(bOrder);
      if (dependencyComparison != 0) return dependencyComparison;

      final changedComparison = a.changedAt.compareTo(b.changedAt);
      if (changedComparison != 0) return changedComparison;

      if (a.entity == b.entity) return 0;
      if (a.entity == 'maintenance_completion') return -1;
      if (b.entity == 'maintenance_completion') return 1;
      return a.entity.compareTo(b.entity);
    });
    return mutations.take(limit).toList(growable: false);
  }

  Future<void> enqueueInitialSnapshot() async {
    for (final spec in syncEntitySpecs) {
      final keyExpression = spec.keyColumns
          .map((column) => 'CAST($column AS TEXT)')
          .join(" || '|' || ");
      await db.customStatement('''
INSERT OR IGNORE INTO offline_mutation_queue(
  entity,
  record_key,
  operation,
  changed_at,
  attempts
)
SELECT
  '${spec.entity}',
  $keyExpression,
  'upsert',
  COALESCE(${spec.modifiedExpression}, CAST(strftime('%s', 'now') AS INTEGER)),
  0
FROM ${spec.localTable}
${spec.localWhere == null ? '' : 'WHERE ${spec.localWhere}'}
''');
    }
    await db.customStatement('''
INSERT OR IGNORE INTO offline_mutation_queue(
  entity,
  record_key,
  operation,
  changed_at,
  attempts
)
SELECT
  'profile',
  'profile',
  'upsert',
  updated_at,
  0
FROM settings
WHERE key = 'profile'
''');
    db.markTablesUpdated([db.syncOutbox]);
  }

  Future<void> enqueueReconciliationSnapshot() async {
    for (final spec in syncEntitySpecs) {
      final keyExpression = spec.keyColumns
          .map((column) => 'CAST($column AS TEXT)')
          .join(" || '|' || ");
      await db.customStatement('''
INSERT OR IGNORE INTO offline_mutation_queue(
  entity,
  record_key,
  operation,
  changed_at,
  attempts
)
SELECT
  '${spec.entity}',
  $keyExpression,
  'upsert',
  COALESCE(${spec.modifiedExpression}, CAST(strftime('%s', 'now') AS INTEGER)),
  0
FROM ${spec.localTable} AS local_row
WHERE ${spec.localWhere ?? '1 = 1'}
  AND (
    NOT EXISTS (
      SELECT 1
      FROM sync_shadows AS shadow
      WHERE shadow.entity = '${spec.entity}'
        AND shadow.record_key = $keyExpression
    )
    OR COALESCE(${spec.modifiedExpression}, 0) > COALESCE((
      SELECT shadow.remote_modified_at
      FROM sync_shadows AS shadow
      WHERE shadow.entity = '${spec.entity}'
        AND shadow.record_key = $keyExpression
    ), 0)
  )
''');
      await db.customStatement('''
INSERT OR IGNORE INTO offline_mutation_queue(
  entity,
  record_key,
  operation,
  changed_at,
  attempts
)
SELECT
  '${spec.entity}',
  shadow.record_key,
  'delete',
  CAST(strftime('%s', 'now') AS INTEGER),
  0
FROM sync_shadows AS shadow
WHERE shadow.entity = '${spec.entity}'
  AND NOT EXISTS (
    SELECT 1
    FROM ${spec.localTable}
    WHERE $keyExpression = shadow.record_key
      ${spec.localWhere == null ? '' : 'AND ${spec.localWhere}'}
  )
''');
    }
    await db.customStatement('''
INSERT OR IGNORE INTO offline_mutation_queue(
  entity,
  record_key,
  operation,
  changed_at,
  attempts
)
SELECT
  'profile',
  'profile',
  'upsert',
  updated_at,
  0
FROM settings
WHERE key = 'profile'
  AND (
    NOT EXISTS (
      SELECT 1 FROM sync_shadows
      WHERE entity = 'profile' AND record_key = 'profile'
    )
    OR updated_at > COALESCE((
      SELECT remote_modified_at FROM sync_shadows
      WHERE entity = 'profile' AND record_key = 'profile'
    ), 0)
  )
''');
    await db.customStatement('''
INSERT OR IGNORE INTO offline_mutation_queue(
  entity,
  record_key,
  operation,
  changed_at,
  attempts
)
SELECT
  'profile',
  'profile',
  'delete',
  CAST(strftime('%s', 'now') AS INTEGER),
  0
FROM sync_shadows
WHERE entity = 'profile'
  AND record_key = 'profile'
  AND NOT EXISTS (SELECT 1 FROM settings WHERE key = 'profile')
''');
    db.markTablesUpdated([db.syncOutbox]);
  }

  Future<void> enqueueRestoreSnapshot(DateTime restoredAt) async {
    await db.transaction(() async {
      await enqueueInitialSnapshot();
      await enqueueReconciliationSnapshot();
      await db
          .update(db.syncOutbox)
          .write(
            SyncOutboxCompanion(
              changedAt: Value(restoredAt),
              attempts: const Value(0),
              nextAttemptAt: const Value(null),
              lastError: const Value(null),
            ),
          );
    });
  }

  Future<SyncRecord?> readMutation(
    LocalSyncMutation mutation,
    String deviceId,
  ) async {
    final spec = syncSpecByEntity[mutation.entity];
    if (spec == null) {
      return null;
    }
    if (mutation.operation == 'delete') {
      final values = <String, dynamic>{};
      if (spec.entity != 'profile') {
        final keyParts = mutation.recordKey.split('|');
        for (var index = 0; index < spec.keyColumns.length; index++) {
          values[spec.keyColumns[index]] = keyParts[index];
        }
      }
      return SyncRecord(
        spec: spec,
        recordKey: mutation.recordKey,
        values: values,
        clientModifiedAt: mutation.changedAt.toUtc(),
        originDeviceId: deviceId,
        deletedAt: mutation.changedAt.toUtc(),
      );
    }
    if (spec.entity == 'profile') {
      return _readProfile(mutation, deviceId);
    }

    final parts = mutation.recordKey.split('|');
    final where = <String>[];
    final variables = <Variable<Object>>[];
    for (var index = 0; index < spec.keyColumns.length; index++) {
      where.add('${spec.keyColumns[index]} = ?');
      variables.add(Variable<String>(parts[index]));
    }
    final result = await db
        .customSelect(
          'SELECT ${spec.localColumns.join(', ')} '
          'FROM ${spec.localTable} WHERE ${where.join(' AND ')} LIMIT 1',
          variables: variables,
        )
        .getSingleOrNull();
    if (result == null) {
      return SyncRecord(
        spec: spec,
        recordKey: mutation.recordKey,
        values: {
          for (var index = 0; index < spec.keyColumns.length; index++)
            spec.keyColumns[index]: parts[index],
        },
        clientModifiedAt: mutation.changedAt.toUtc(),
        originDeviceId: deviceId,
        deletedAt: mutation.changedAt.toUtc(),
      );
    }
    final values = _toRemoteCompatible(spec, result.data);
    final semanticModifiedAt =
        _semanticClientModifiedAt(spec, values) ?? mutation.changedAt.toUtc();
    return SyncRecord(
      spec: spec,
      recordKey: mutation.recordKey,
      values: values,
      clientModifiedAt: semanticModifiedAt,
      originDeviceId: deviceId,
    );
  }

  Future<SyncRecord?> _readProfile(
    LocalSyncMutation mutation,
    String deviceId,
  ) async {
    final row = await db
        .customSelect(
          "SELECT value, updated_at FROM settings WHERE key = 'profile' LIMIT 1",
        )
        .getSingleOrNull();
    if (row == null) {
      return SyncRecord(
        spec: profileSyncSpec,
        recordKey: 'profile',
        values: const {},
        clientModifiedAt: mutation.changedAt.toUtc(),
        originDeviceId: deviceId,
        deletedAt: mutation.changedAt.toUtc(),
      );
    }
    final decoded =
        jsonDecode(row.read<String>('value')) as Map<String, dynamic>;
    return SyncRecord(
      spec: profileSyncSpec,
      recordKey: 'profile',
      values: {'nickname': decoded['nickname'] as String?},
      clientModifiedAt:
          _dateTimeFromStorage(row.data['updated_at']) ??
          mutation.changedAt.toUtc(),
      originDeviceId: deviceId,
    );
  }

  Future<SyncShadow?> shadow(String entity, String recordKey) {
    return (db.select(db.syncShadows)..where(
          (row) => row.entity.equals(entity) & row.recordKey.equals(recordKey),
        ))
        .getSingleOrNull();
  }

  Future<DateTime?> pendingChangedAt(String entity, String recordKey) async {
    final row =
        await (db.select(db.syncOutbox)..where(
              (item) =>
                  item.entity.equals(entity) & item.recordKey.equals(recordKey),
            ))
            .getSingleOrNull();
    return row?.changedAt;
  }

  Future<bool> isUntouchedSeed(SyncRecord record) async {
    final expected = _seedValues[record.spec.entity]?[record.recordKey];
    if (expected == null) return false;
    final where = <String>[];
    final variables = <Variable<Object>>[];
    final parts = record.recordKey.split('|');
    for (var index = 0; index < record.spec.keyColumns.length; index++) {
      where.add('${record.spec.keyColumns[index]} = ?');
      variables.add(Variable<String>(parts[index]));
    }
    final row = await db
        .customSelect(
          'SELECT ${expected.keys.join(', ')} '
          'FROM ${record.spec.localTable} '
          'WHERE ${where.join(' AND ')} LIMIT 1',
          variables: variables,
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
    return true;
  }

  Future<int> cursor(String entity) async {
    return (await cursorCheckpoint(entity)).$1;
  }

  Future<(int, String?)> cursorCheckpoint(String entity) async {
    final row = await (db.select(
      db.syncCursors,
    )..where((item) => item.entity.equals(entity))).getSingleOrNull();
    return (row?.lastSyncSeq ?? 0, row?.lastRecordKey);
  }

  Future<void> setCursor(
    String entity,
    int lastSyncSeq, {
    String? lastRecordKey,
  }) async {
    final current = await cursorCheckpoint(entity);
    final currentSeq = current.$1;
    final currentKey = current.$2;
    if (lastSyncSeq < currentSeq) return;
    if (lastSyncSeq == currentSeq &&
        currentKey != null &&
        lastRecordKey != null &&
        lastRecordKey.compareTo(currentKey) <= 0) {
      return;
    }
    await db
        .into(db.syncCursors)
        .insertOnConflictUpdate(
          SyncCursorsCompanion.insert(
            entity: entity,
            lastSyncSeq: Value(lastSyncSeq),
            lastRecordKey: Value(lastRecordKey),
          ),
        );
  }

  Future<int> getFeedCursor() async {
    final row =
        await (db.select(db.syncCursors)
              ..where((item) => item.entity.equals('server_change_feed')))
            .getSingleOrNull();
    return row?.lastSyncSeq ?? 0;
  }

  Future<void> setFeedCursor(int lastSyncSeq) async {
    final current = await getFeedCursor();
    if (lastSyncSeq < current) return;
    await db
        .into(db.syncCursors)
        .insertOnConflictUpdate(
          SyncCursorsCompanion.insert(
            entity: 'server_change_feed',
            lastSyncSeq: Value(lastSyncSeq),
          ),
        );
  }

  Future<bool> hasPendingLocalMutation(String entity, String recordKey) async {
    final row =
        await (db.select(db.syncOutbox)..where(
              (r) => r.entity.equals(entity) & r.recordKey.equals(recordKey),
            ))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> applyRemoteFeedRecord(SyncRecord record) async {
    final hasPending = await hasPendingLocalMutation(
      record.spec.entity,
      record.recordKey,
    );
    await db.transaction(() async {
      await withOutboxSuppressed(() async {
        await _saveShadow(record);
        if (!hasPending) {
          await _upsertLocal(record);
        }
      });
    });
  }

  Future<void> applyRemoteFeedDelete(SyncRecord record) async {
    final hasPending = await hasPendingLocalMutation(
      record.spec.entity,
      record.recordKey,
    );
    await db.transaction(() async {
      await withOutboxSuppressed(() async {
        await (db.delete(db.syncShadows)..where(
              (row) =>
                  row.entity.equals(record.spec.entity) &
                  row.recordKey.equals(record.recordKey),
            ))
            .go();
        if (!hasPending) {
          await _deleteLocal(record);
        }
      });
    });
  }

  Future<void> applyRemoteFeedPageAndCheckpoint({
    required List<SyncRecord> records,
    required int lastSyncSeq,
  }) async {
    await db.transaction(() async {
      for (final record in records) {
        if (record.isDeleted) {
          await applyRemoteFeedDelete(record);
        } else {
          await applyRemoteFeedRecord(record);
        }
      }
      await setFeedCursor(lastSyncSeq);
    });
  }

  Future<void> applyRemoteRecordsAndCheckpoints({
    required List<SyncRecord> records,
    required Map<String, (int, String?)> checkpoints,
  }) async {
    await db.transaction(() async {
      await applyRemoteRecords(records);
      for (final entry in checkpoints.entries) {
        final checkpoint = entry.value;
        await setCursor(entry.key, checkpoint.$1, lastRecordKey: checkpoint.$2);
      }
    });
  }

  Future<void> applyRemoteRecords(List<SyncRecord> records) async {
    if (records.isEmpty) return;
    final invalidatesWeather = records.any(
      (record) =>
          record.spec.entity == 'user_setting' &&
          record.recordKey == 'home_location',
    );
    final inboxChanged = records.any(
      (record) => record.spec.entity == 'notification_inbox',
    );
    final specOrder = {
      for (var index = 0; index < syncEntitySpecs.length; index++)
        syncEntitySpecs[index].entity: index,
      'profile': syncEntitySpecs.length,
    };
    final deletes = records.where((record) => record.isDeleted).toList()
      ..sort(
        (a, b) => (specOrder[b.spec.entity] ?? 0).compareTo(
          specOrder[a.spec.entity] ?? 0,
        ),
      );
    final upserts = records.where((record) => !record.isDeleted).toList()
      ..sort(
        (a, b) => (specOrder[a.spec.entity] ?? 0).compareTo(
          specOrder[b.spec.entity] ?? 0,
        ),
      );

    await db.transaction(() async {
      await withOutboxSuppressed(() async {
        for (final record in deletes) {
          await _deleteLocal(record);
          await _saveShadow(record);
        }
        for (final record in upserts) {
          await _upsertLocal(record);
          await _saveShadow(record);
        }
      });
    });
    if (invalidatesWeather) {
      await db.customUpdate(
        "DELETE FROM settings WHERE key = 'weather_cache'",
        updates: {db.settings},
        updateKind: UpdateKind.delete,
      );
    }
    if (inboxChanged) {
      await enforceInboxRetention();
    }
  }

  Future<bool> applyRemoteHardDelete({
    required SyncEntitySpec spec,
    required Map<String, dynamic> oldRecord,
    required String userId,
    required String deviceId,
  }) async {
    if (spec.scope != SyncScope.catalog && oldRecord['user_id'] != userId) {
      return false;
    }
    if (spec.scope == SyncScope.deviceScoped &&
        oldRecord['device_id'] != deviceId) {
      return false;
    }
    final values = <String, dynamic>{
      for (final column in spec.keyColumns)
        column: oldRecord[spec.remoteColumnFor(column)],
    };
    if (values.values.any((value) => value == null)) return false;
    final recordKey = spec.keyColumns.isEmpty
        ? spec.entity
        : spec.keyColumns.map((column) => values[column]).join('|');
    final record = SyncRecord(
      spec: spec,
      recordKey: recordKey,
      values: values,
      clientModifiedAt: DateTime.now().toUtc(),
      originDeviceId: 'supabase-hard-delete',
      deletedAt: DateTime.now().toUtc(),
    );
    await db.transaction(() async {
      await _setOutboxSuppressed(true);
      try {
        await _deleteLocal(record);
        await (db.delete(db.syncOutbox)..where(
              (row) =>
                  row.entity.equals(spec.entity) &
                  row.recordKey.equals(recordKey),
            ))
            .go();
        await (db.delete(db.syncShadows)..where(
              (row) =>
                  row.entity.equals(spec.entity) &
                  row.recordKey.equals(recordKey),
            ))
            .go();
      } finally {
        await _setOutboxSuppressed(false);
      }
    });
    if (spec.entity == 'user_setting' && recordKey == 'home_location') {
      await db.customUpdate(
        "DELETE FROM settings WHERE key = 'weather_cache'",
        updates: {db.settings},
        updateKind: UpdateKind.delete,
      );
    }
    return true;
  }

  Future<void> enforceInboxRetention() {
    return db
        .customUpdate(
          '''
DELETE FROM notification_inbox
WHERE id NOT IN (
  SELECT id
  FROM notification_inbox
  ORDER BY created_at DESC
  LIMIT 250
)
''',
          updates: {db.inboxNotifications},
          updateKind: UpdateKind.delete,
        )
        .then((_) {});
  }

  Future<void> recalculateStreak() {
    return DatabaseStreakService(db).refresh(DateTime.now()).then((_) {});
  }

  Future<void> _deleteLocal(SyncRecord record) async {
    if (record.spec.entity == 'profile') {
      await db.customUpdate(
        "DELETE FROM settings WHERE key = 'profile'",
        updates: {db.settings},
        updateKind: UpdateKind.delete,
      );
      return;
    }
    final where = <String>[];
    final variables = <dynamic>[];
    for (final column in record.spec.keyColumns) {
      where.add('$column = ?');
      variables.add(record.values[column].toString());
    }
    String? localMediaPath;
    if (record.spec.entity == 'asset_photo') {
      final existing = await db
          .customSelect(
            'SELECT relative_path FROM ${record.spec.localTable} '
            'WHERE ${where.join(' AND ')} LIMIT 1',
            variables: [
              for (final variable in variables)
                Variable<Object>(variable as Object),
            ],
          )
          .getSingleOrNull();
      localMediaPath = existing?.read<String>('relative_path');
    }
    await db.customUpdate(
      'DELETE FROM ${record.spec.localTable} WHERE ${where.join(' AND ')}',
      variables: [
        for (final variable in variables) Variable<Object>(variable as Object),
      ],
      updates: {_localTable(record.spec.localTable)},
      updateKind: UpdateKind.delete,
    );
    if (localMediaPath != null && localMediaPath.isNotEmpty) {
      await _deleteLocalMediaFile(localMediaPath);
    }
  }

  Future<void> _upsertLocal(SyncRecord record) async {
    if (record.spec.entity == 'profile') {
      final current = await db
          .customSelect(
            "SELECT value FROM settings WHERE key = 'profile' LIMIT 1",
          )
          .getSingleOrNull();
      String? localAvatar;
      if (current != null) {
        final json =
            jsonDecode(current.read<String>('value')) as Map<String, dynamic>;
        if (json['avatarPath'] is String) {
          localAvatar = json['avatarPath'] as String;
        }
      }
      final value = jsonEncode({
        'nickname': record.values['nickname'] as String?,
        // ignore: use_null_aware_elements
        if (localAvatar != null) 'avatarPath': localAvatar,
      });
      await db.customInsert(
        '''
INSERT INTO settings(key, value, updated_at)
VALUES ('profile', ?, CAST(strftime('%s', 'now') AS INTEGER))
ON CONFLICT(key) DO UPDATE SET
  value = excluded.value,
  updated_at = excluded.updated_at
''',
        variables: [Variable<String>(value)],
        updates: {db.settings},
      );
      return;
    }
    final columns = record.spec.localColumns
        .where(record.values.containsKey)
        .toList();
    final valuesByColumn = <String, dynamic>{};
    for (final column in columns) {
      valuesByColumn[column] = _toLocalValue(
        record.spec,
        column,
        record.values[column],
      );
    }
    final keyWhere = record.spec.keyColumns
        .map((column) => '$column = ?')
        .join(' AND ');
    final keyValues = [
      for (final column in record.spec.keyColumns) valuesByColumn[column],
    ];
    final existing = await db
        .customSelect(
          'SELECT * FROM ${record.spec.localTable} '
          'WHERE $keyWhere LIMIT 1',
          variables: [for (final value in keyValues) Variable<Object>(value)],
        )
        .getSingleOrNull();
    final updateColumns = columns
        .where((column) => !record.spec.keyColumns.contains(column))
        .toList();
    if (existing != null) {
      if (updateColumns.isEmpty) return;
      await db.customUpdate(
        'UPDATE ${record.spec.localTable} SET '
        '${updateColumns.map((column) => '$column = ?').join(', ')} '
        'WHERE $keyWhere',
        variables: [
          for (final column in updateColumns) valuesByColumn[column],
          ...keyValues,
        ].map((value) => Variable<Object>(value)).toList(),
        updates: {_localTable(record.spec.localTable)},
        updateKind: UpdateKind.update,
      );
      if (record.spec.entity == 'asset_photo') {
        final previousPath = existing.read<String>('relative_path');
        final nextPath = valuesByColumn['relative_path'] as String?;
        if (nextPath != null &&
            previousPath.isNotEmpty &&
            previousPath != nextPath) {
          await _deleteLocalMediaFile(previousPath);
        }
      }
      return;
    }
    await db.customInsert(
      'INSERT INTO ${record.spec.localTable} (${columns.join(', ')}) '
      'VALUES (${List.filled(columns.length, '?').join(', ')})',
      variables: [
        for (final column in columns) Variable<Object>(valuesByColumn[column]),
      ],
      updates: {_localTable(record.spec.localTable)},
    );
  }

  ResultSetImplementation<dynamic, dynamic> _localTable(String tableName) {
    return db.allTables.firstWhere(
      (table) => table.actualTableName == tableName,
    );
  }

  Future<void> markAssetPhotoPrimarySucceeded(
    LocalSyncMutation mutation, {
    required List<SyncRecord> photos,
  }) async {
    if (mutation.entity != 'asset_photo_primary' ||
        photos.any((record) => record.spec.entity != 'asset_photo')) {
      throw StateError('Invalid primary-photo acknowledgement.');
    }
    await db.transaction(() async {
      await withOutboxSuppressed(() async {
        for (final canonical in photos) {
          final local =
              await (db.select(db.assetPhotos)
                    ..where((row) => row.id.equals(canonical.recordKey)))
                  .getSingleOrNull();
          if (local == null) {
            // A photo created by another device will be materialized by the
            // normal pull path. Remembering its remote row here is unnecessary.
            continue;
          }
          final localized = SyncRecord(
            spec: canonical.spec,
            recordKey: canonical.recordKey,
            values: {...canonical.values, 'relative_path': local.relativePath},
            clientModifiedAt: canonical.clientModifiedAt,
            originDeviceId: canonical.originDeviceId,
            revision: canonical.revision,
            syncSeq: canonical.syncSeq,
            serverUpdatedAt: canonical.serverUpdatedAt,
            deletedAt: canonical.deletedAt,
          );
          await _upsertLocal(localized);
          await _saveShadow(localized);
        }
      });
      await (db.delete(db.syncOutbox)..where(
            (row) =>
                row.entity.equals('asset_photo_primary') &
                row.recordKey.equals(mutation.recordKey),
          ))
          .go();
    });
  }

  Future<void> markMaintenanceUndoSucceeded(
    LocalSyncMutation mutation, {
    required SyncRecord plan,
    required String completionId,
  }) async {
    if (mutation.entity != 'maintenance_undo' ||
        plan.spec.entity != 'maintenance_plan' ||
        mutation.recordKey != completionId) {
      throw StateError('Invalid maintenance undo acknowledgement.');
    }
    await db.transaction(() async {
      await (db.delete(db.syncOutbox)..where(
            (row) =>
                (row.entity.equals('maintenance_undo') &
                    row.recordKey.equals(completionId)) |
                (row.entity.equals('maintenance_plan') &
                    row.recordKey.equals(plan.recordKey)) |
                (row.entity.equals('maintenance_record') &
                    row.recordKey.equals(completionId)),
          ))
          .go();
      await withOutboxSuppressed(() async {
        await _upsertLocal(plan);
        await _saveShadow(plan);
        await (db.delete(
          db.maintenanceRecords,
        )..where((row) => row.id.equals(completionId))).go();
        await (db.delete(db.syncShadows)..where(
              (row) =>
                  row.entity.equals('maintenance_record') &
                  row.recordKey.equals(completionId),
            ))
            .go();
      });
    });
  }

  Future<void> markMaintenanceCompletionSucceeded(
    LocalSyncMutation mutation, {
    required SyncRecord plan,
    required SyncRecord record,
  }) async {
    if (mutation.entity != 'maintenance_completion' ||
        plan.spec.entity != 'maintenance_plan' ||
        record.spec.entity != 'maintenance_record' ||
        record.recordKey != mutation.recordKey) {
      throw StateError('Invalid maintenance completion acknowledgement.');
    }

    await db.transaction(() async {
      Future<void> recordCanonicalWithoutApplying(SyncRecord canonical) async {
        await _saveShadow(canonical);
      }

      final pendingOperation =
          await (db.select(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals(mutation.entity) &
                    row.recordKey.equals(mutation.recordKey),
              ))
              .getSingleOrNull();

      if (pendingOperation == null) {
        // Undo can remove the composite mutation while its RPC is in flight.
        // Retain the locally undone state and only record what reached cloud;
        // the compensating generic mutations remain queued.
        await recordCanonicalWithoutApplying(plan);
        await recordCanonicalWithoutApplying(record);
        return;
      }

      final currentPlan = await (db.select(
        db.maintenancePlans,
      )..where((row) => row.id.equals(plan.recordKey))).getSingleOrNull();

      final otherPendingRows =
          await (db.select(db.syncOutbox)..where(
                (row) =>
                    row.recordKey.equals(mutation.recordKey).not() &
                    (row.entity.equals('maintenance_plan') |
                        row.entity.equals('maintenance_completion')),
              ))
              .get();
      var hasLaterPendingPlanMutation = false;
      for (final row in otherPendingRows) {
        if (row.entity == 'maintenance_plan' &&
            row.recordKey == plan.recordKey) {
          hasLaterPendingPlanMutation = true;
          break;
        }
        if (row.entity == 'maintenance_completion' && row.payloadJson != null) {
          try {
            final decoded =
                jsonDecode(row.payloadJson!) as Map<String, dynamic>;
            final compPlanId =
                decoded['plan_id'] as String? ??
                (decoded['plan'] as Map<String, dynamic>?)?['id'] as String?;
            if (compPlanId == plan.recordKey) {
              hasLaterPendingPlanMutation = true;
              break;
            }
          } catch (_) {}
        }
      }

      final preserveNewerLocalPlan =
          currentPlan != null &&
          (currentPlan.updatedAt.isAfter(mutation.changedAt) ||
              hasLaterPendingPlanMutation);

      await applyRemoteRecords([if (!preserveNewerLocalPlan) plan, record]);

      if (preserveNewerLocalPlan) {
        // A later offline completion or edit already changed this plan.
        // Keep that local value while remembering the canonical cloud row for
        // conflict detection. Inbound pull processing exclusively owns cursors.
        await recordCanonicalWithoutApplying(plan);
      }

      await (db.delete(db.syncOutbox)..where(
            (row) =>
                row.entity.equals(mutation.entity) &
                row.recordKey.equals(mutation.recordKey),
          ))
          .go();
    });
  }

  Future<bool> markMutationInFlight(
    LocalSyncMutation mutation, {
    required String userId,
  }) async {
    if (mutation.userId != null && mutation.userId != userId) {
      throw StateError('Queued mutation belongs to another cloud account.');
    }
    final count =
        await (db.update(db.syncOutbox)..where(
              (row) =>
                  row.entity.equals(mutation.entity) &
                  row.recordKey.equals(mutation.recordKey) &
                  row.generation.equals(mutation.generation),
            ))
            .write(
              SyncOutboxCompanion(
                userId: Value(mutation.userId ?? userId),
                state: const Value('inFlight'),
                nextAttemptAt: const Value(null),
              ),
            );
    return count > 0;
  }

  Future<bool> isMutationFailedVisible(LocalSyncMutation mutation) async {
    final row =
        await (db.select(db.syncOutbox)..where(
              (candidate) =>
                  candidate.entity.equals(mutation.entity) &
                  candidate.recordKey.equals(mutation.recordKey),
            ))
            .getSingleOrNull();
    return row?.state == SyncMutationState.failedVisible.name;
  }

  Future<void> markMaintenanceConflictRecovery(
    LocalSyncMutation mutation, {
    required String payloadJson,
    required String errorCode,
    required String message,
  }) async {
    await (db.update(db.syncOutbox)..where(
          (row) =>
              row.entity.equals(mutation.entity) &
              row.recordKey.equals(mutation.recordKey),
        ))
        .write(
          SyncOutboxCompanion(
            payloadJson: Value(payloadJson),
            state: const Value('conflictRecovery'),
            nextAttemptAt: const Value(null),
            lastErrorCode: Value(errorCode),
            lastError: Value(message),
          ),
        );
  }

  Future<void> markMaintenanceCompletionFailedVisible(
    LocalSyncMutation mutation, {
    required String errorCode,
    required String message,
    SyncRecord? plan,
    SyncRecord? record,
  }) async {
    await db.transaction(() async {
      await withOutboxSuppressed(() async {
        await (db.delete(
          db.maintenanceRecords,
        )..where((row) => row.id.equals(mutation.operationId))).go();
        await applyRemoteRecords([
          ?plan,
          if (record != null && record.recordKey != mutation.operationId)
            record,
        ]);
        if (plan == null) {
          await _restoreRejectedMaintenanceCompletionPreimage(mutation);
        }
      });
      await (db.update(db.syncOutbox)..where(
            (row) =>
                row.entity.equals(mutation.entity) &
                row.recordKey.equals(mutation.recordKey),
          ))
          .write(
            SyncOutboxCompanion(
              attempts: const Value(-1),
              state: const Value('failedVisible'),
              nextAttemptAt: const Value(null),
              lastErrorCode: Value(errorCode),
              lastError: Value(message),
            ),
          );
    });
  }

  Future<List<Map<String, dynamic>>> exportFailedMutationDiagnostics() async {
    final rows =
        await (db.select(db.syncOutbox)..where(
              (row) =>
                  row.state.equals('failedVisible') | row.attempts.equals(-1),
            ))
            .get();
    return [
      for (final row in rows)
        {
          'mutation_type': row.entity,
          'state': row.state,
          'operation_fingerprint': sha256
              .convert(utf8.encode(row.recordKey))
              .toString()
              .substring(0, 12),
          'changed_at': row.changedAt.toUtc().toIso8601String(),
          'created_at': row.createdAt?.toUtc().toIso8601String(),
          'attempt_count': row.attempts,
          'last_error_code': row.lastErrorCode ?? 'unknown',
          'sanitized_reason': row.lastError ?? 'none',
          'retryable': false,
          'payload_hash': row.payloadJson != null
              ? sha256.convert(utf8.encode(row.payloadJson!)).toString()
              : null,
          'supported_actions': const ['retry', 'acknowledge', 'dismiss'],
        },
    ];
  }

  Future<List<Map<String, String>>> listFailedVisibleDetails() async {
    final rows =
        await (db.select(db.syncOutbox)..where(
              (row) =>
                  row.state.equals('failedVisible') | row.attempts.equals(-1),
            ))
            .get();
    return [
      for (final row in rows)
        {
          'entity': row.entity,
          'operation': row.operation,
          'error_code': row.lastErrorCode ?? 'unknown',
        },
    ];
  }

  Future<int> abandonStaleFailedVisibleMutations({
    Duration maxAge = const Duration(days: 7),
  }) async {
    final cutoff = DateTime.now().subtract(maxAge);
    return (db.delete(db.syncOutbox)..where(
          (row) =>
              (row.state.equals('failedVisible') | row.attempts.equals(-1)) &
              row.changedAt.isSmallerThanValue(cutoff),
        ))
        .go();
  }

  Future<void> resolveFailedMutation({
    required String entity,
    required String recordKey,
    required String action,
  }) async {
    await db.transaction(() async {
      Expression<bool> target(SyncOutbox row) =>
          row.entity.equals(entity) & row.recordKey.equals(recordKey);
      if (action == 'dismiss' || action == 'acknowledge') {
        await (db.delete(db.syncOutbox)..where(target)).go();
      } else if (action == 'retry') {
        await (db.update(db.syncOutbox)..where(target)).write(
          const SyncOutboxCompanion(
            attempts: Value(0),
            state: Value('pending'),
            nextAttemptAt: Value(null),
          ),
        );
      }
    });
  }

  Future<void> reconcileTaskCreationComposite({
    required String planId,
    Map<String, dynamic>? planJson,
    Map<String, dynamic>? metadataJson,
  }) async {
    final records = <SyncRecord>[];
    final planSpec = syncEntitySpecs.firstWhere(
      (s) => s.entity == 'maintenance_plan',
    );
    final metaSpec = syncEntitySpecs.firstWhere(
      (s) => s.entity == 'maintenance_plan_metadata',
    );
    if (planJson != null) {
      final parsed = SyncRecord.fromRemote(planSpec, planJson);
      if (parsed.recordKey == planId) {
        records.add(parsed);
      }
    }
    if (metadataJson != null && metadataJson.isNotEmpty) {
      final parsedMeta = SyncRecord.fromRemote(metaSpec, metadataJson);
      if (parsedMeta.recordKey == planId) {
        records.add(parsedMeta);
      }
    }

    await db.transaction(() async {
      final currentPlan = await (db.select(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).getSingleOrNull();

      final planOutbox =
          await (db.select(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals('maintenance_plan') &
                    row.recordKey.equals(planId),
              ))
              .getSingleOrNull();

      final preserveNewerLocalPlan = planOutbox != null && currentPlan != null;

      if (records.isNotEmpty) {
        await applyRemoteRecords([
          if (!preserveNewerLocalPlan)
            ...records.where((r) => r.spec.entity == 'maintenance_plan'),
          ...records.where((r) => r.spec.entity != 'maintenance_plan'),
        ]);
        if (preserveNewerLocalPlan) {
          for (final canonical in records.where(
            (r) => r.spec.entity == 'maintenance_plan',
          )) {
            await _saveShadow(canonical);
          }
        }
      }

      if (!preserveNewerLocalPlan) {
        await (db.delete(db.syncOutbox)..where(
              (row) =>
                  (row.entity.equals('maintenance_plan') &
                      row.recordKey.equals(planId)) |
                  (row.entity.equals('maintenance_plan_metadata') &
                      row.recordKey.equals(planId)),
            ))
            .go();
      }
    });
  }

  Future<void> acknowledgeTaskCreationComposite({
    required String planId,
    Map<String, dynamic>? planJson,
    Map<String, dynamic>? metadataJson,
  }) {
    return reconcileTaskCreationComposite(
      planId: planId,
      planJson: planJson,
      metadataJson: metadataJson,
    );
  }

  Future<void> reconcileAssetCreationComposite({
    required String assetId,
    Map<String, dynamic>? assetJson,
  }) async {
    if (assetJson == null || assetJson.isEmpty) return;
    final spec = syncEntitySpecs.firstWhere((s) => s.entity == 'asset');
    final parsed = SyncRecord.fromRemote(spec, assetJson);
    if (parsed.recordKey != assetId) return;

    await db.transaction(() async {
      await applyRemoteRecords([parsed]);
      await (db.delete(db.syncOutbox)..where(
            (row) => row.entity.equals('asset') & row.recordKey.equals(assetId),
          ))
          .go();
    });
  }

  Future<void> reconcileMaintenanceOccurrenceCompletedElsewhere(
    LocalSyncMutation mutation, {
    required SyncRecord plan,
    required SyncRecord record,
  }) async {
    await db.transaction(() async {
      await withOutboxSuppressed(() async {
        await (db.delete(
          db.maintenanceRecords,
        )..where((row) => row.id.equals(mutation.operationId))).go();
      });
      await applyRemoteRecords([plan, record]);

      await db
          .into(db.notificationReconciliationRequests)
          .insertOnConflictUpdate(
            NotificationReconciliationRequestsCompanion.insert(
              scopeKey: 'plan:${plan.recordKey}',
              planId: Value(plan.recordKey),
              reason: 'occurrence_completed_elsewhere',
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      await (db.delete(db.syncOutbox)..where(
            (row) =>
                row.entity.equals(mutation.entity) &
                row.recordKey.equals(mutation.recordKey),
          ))
          .go();
    });
  }

  Future<void> reconcileRejectedMaintenanceCompletion(
    LocalSyncMutation mutation, {
    required String errorCode,
    required String message,
    SyncRecord? plan,
  }) async {
    await db.transaction(() async {
      await withOutboxSuppressed(() async {
        await (db.delete(
          db.maintenanceRecords,
        )..where((row) => row.id.equals(mutation.operationId))).go();
        if (plan != null) {
          await applyRemoteRecords([plan]);
        } else {
          await _restoreRejectedMaintenanceCompletionPreimage(mutation);
        }
      });

      final planId = plan?.recordKey ?? _extractPlanIdFromMutation(mutation);
      if (planId != null) {
        await db
            .into(db.notificationReconciliationRequests)
            .insertOnConflictUpdate(
              NotificationReconciliationRequestsCompanion.insert(
                scopeKey: 'plan:$planId',
                planId: Value(planId),
                reason: 'completion_rejected',
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            );
      }

      await (db.delete(db.syncOutbox)..where(
            (row) =>
                row.entity.equals(mutation.entity) &
                row.recordKey.equals(mutation.recordKey),
          ))
          .go();
    });
  }

  String? _extractPlanIdFromMutation(LocalSyncMutation mutation) {
    if (mutation.payloadJson == null) return null;
    try {
      final decoded = jsonDecode(mutation.payloadJson!) as Map<String, dynamic>;
      return decoded['plan_id'] as String? ??
          (decoded['plan'] as Map<String, dynamic>?)?['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  bool validateUserSettingKey(String key) {
    if (!allowedRemoteSettingKeys.contains(key)) {
      throw ArgumentError.value(
        key,
        'key',
        'Undeclared remote setting key cannot be enqueued for sync.',
      );
    }
    return true;
  }

  Future<void> _restoreRejectedMaintenanceCompletionPreimage(
    LocalSyncMutation mutation,
  ) async {
    final payloadJson = mutation.payloadJson;
    if (mutation.entity != 'maintenance_completion' ||
        payloadJson == null ||
        payloadJson.trim().isEmpty) {
      return;
    }

    final payload = _decodeMaintenancePayload(payloadJson);
    if (payload == null) return;
    final planValues = _maintenanceCompletionPlanPreimage(payload);
    if (planValues == null) return;
    final planId = planValues['id']?.toString();
    if (planId == null || planId.isEmpty) return;

    final current = await (db.select(
      db.maintenancePlans,
    )..where((row) => row.id.equals(planId))).getSingleOrNull();
    if (current == null || current.updatedAt.isAfter(mutation.changedAt)) {
      return;
    }

    await (db.update(
      db.maintenancePlans,
    )..where((row) => row.id.equals(planId))).write(
      MaintenancePlansCompanion(
        assetId: Value(_stringValue(planValues, 'asset_id', current.assetId)),
        title: Value(_stringValue(planValues, 'title', current.title)),
        instructions: Value(
          _nullableStringValue(
            planValues,
            'instructions',
            current.instructions,
          ),
        ),
        recurrenceInterval: Value(
          _intValue(
            planValues,
            'recurrence_interval',
            current.recurrenceInterval,
          ),
        ),
        recurrenceUnit: Value(
          _stringValue(planValues, 'recurrence_unit', current.recurrenceUnit),
        ),
        priority: Value(_stringValue(planValues, 'priority', current.priority)),
        nextDueDate: Value(
          _dateValue(planValues, 'next_due_date', current.nextDueDate),
        ),
        reminderDaysBefore: Value(
          _intValue(
            planValues,
            'reminder_days_before',
            current.reminderDaysBefore,
          ),
        ),
        isEnabled: Value(
          _boolValue(planValues, 'is_enabled', current.isEnabled),
        ),
        healthGroup: Value(
          _stringValue(planValues, 'health_group', current.healthGroup),
        ),
        createdAt: Value(
          _dateValue(planValues, 'created_at', current.createdAt),
        ),
        updatedAt: Value(
          _dateValue(planValues, 'updated_at', current.updatedAt),
        ),
        archivedAt: Value(
          _nullableDateValue(planValues, 'archived_at', current.archivedAt),
        ),
      ),
    );
  }

  Future<bool> markMutationSucceeded(
    LocalSyncMutation mutation,
    SyncRecord? canonical,
  ) async {
    return await db.transaction(() async {
      if (canonical != null) {
        await _saveShadow(canonical);
      }
      if (mutation.operation == 'delete') {
        await (db.delete(db.syncShadows)..where(
              (row) =>
                  row.entity.equals(mutation.entity) &
                  row.recordKey.equals(mutation.recordKey),
            ))
            .go();
      }
      final deletedCount =
          await (db.delete(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals(mutation.entity) &
                    row.recordKey.equals(mutation.recordKey) &
                    row.generation.equals(mutation.generation),
              ))
              .go();
      return deletedCount > 0;
    });
  }

  Future<void> discardMutation(String entity, String recordKey) async {
    await (db.delete(db.syncOutbox)..where(
          (row) => row.entity.equals(entity) & row.recordKey.equals(recordKey),
        ))
        .go();
  }

  Future<bool> markMutationFailed(
    LocalSyncMutation mutation,
    String message,
  ) async {
    const maxAutomaticAttempts = 24;
    const minimumDelaySeconds = 15;
    const maximumDelaySeconds = 3600;

    final attempts = mutation.attempts + 1;

    final update = db.update(db.syncOutbox)
      ..where(
        (row) =>
            row.entity.equals(mutation.entity) &
            row.recordKey.equals(mutation.recordKey) &
            row.generation.equals(mutation.generation),
      );

    if (attempts >= maxAutomaticAttempts) {
      final updated = await update.write(
        SyncOutboxCompanion(
          attempts: const Value(-1),
          state: const Value('failedVisible'),
          nextAttemptAt: const Value(null),
          lastErrorCode: const Value('retry_exhausted'),
          lastError: Value(
            '$message Automatic sync paused after '
            '$maxAutomaticAttempts failed attempts.',
          ),
        ),
      );
      return updated > 0;
    }

    final baseSeconds = math
        .min(
          minimumDelaySeconds * math.pow(2, attempts - 1).toInt(),
          maximumDelaySeconds,
        )
        .toInt();

    final jitterRange = math.max(1, baseSeconds ~/ 5).toInt();
    final jitterSeconds =
        math.Random().nextInt((jitterRange * 2) + 1) - jitterRange;

    final seconds = math
        .min(
          math.max(baseSeconds + jitterSeconds, minimumDelaySeconds),
          maximumDelaySeconds,
        )
        .toInt();

    final updated = await update.write(
      SyncOutboxCompanion(
        attempts: Value(attempts),
        state: const Value('pending'),
        nextAttemptAt: Value(DateTime.now().add(Duration(seconds: seconds))),
        lastErrorCode: const Value('transient'),
        lastError: Value(message),
      ),
    );
    return updated > 0;
  }

  Future<bool> markMutationTerminal(
    LocalSyncMutation mutation,
    String message,
  ) async {
    final updated =
        await (db.update(db.syncOutbox)..where(
              (row) =>
                  row.entity.equals(mutation.entity) &
                  row.recordKey.equals(mutation.recordKey) &
                  row.generation.equals(mutation.generation),
            ))
            .write(
              SyncOutboxCompanion(
                attempts: const Value(-1),
                state: const Value('failedVisible'),
                nextAttemptAt: const Value(null),
                lastErrorCode: const Value('terminal'),
                lastError: Value(message),
              ),
            );
    return updated > 0;
  }

  Future<void> enqueueMediaCleanup({
    required String objectPath,
    required String userId,
    required String entity,
    required String recordKey,
  }) async {
    if (objectPath.isEmpty || !objectPath.startsWith('$userId/')) return;
    await db
        .into(db.syncMediaCleanup)
        .insertOnConflictUpdate(
          SyncMediaCleanupCompanion.insert(
            objectPath: objectPath,
            userId: userId,
            entity: entity,
            recordKey: recordKey,
          ),
        );
  }

  Future<List<SyncMediaCleanupData>> pendingMediaCleanup({int limit = 50}) {
    final now = DateTime.now();
    final query = db.select(db.syncMediaCleanup)
      ..where(
        (row) =>
            row.attempts.isBiggerOrEqualValue(0) &
            (row.nextAttemptAt.isNull() |
                row.nextAttemptAt.isSmallerOrEqualValue(now)),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
      ..limit(limit);
    return query.get();
  }

  Future<void> markMediaCleanupSucceeded(String objectPath) async {
    await (db.delete(
      db.syncMediaCleanup,
    )..where((row) => row.objectPath.equals(objectPath))).go();
  }

  Future<void> markMediaCleanupFailed(
    SyncMediaCleanupData cleanup,
    String message,
  ) async {
    final attempts = cleanup.attempts + 1;
    final seconds = math
        .min(15 * math.pow(2, attempts - 1).toInt(), 3600)
        .toInt();
    await (db.update(
      db.syncMediaCleanup,
    )..where((row) => row.objectPath.equals(cleanup.objectPath))).write(
      SyncMediaCleanupCompanion(
        attempts: Value(attempts),
        nextAttemptAt: Value(DateTime.now().add(Duration(seconds: seconds))),
        lastError: Value(message),
      ),
    );
  }

  Future<void> markMediaCleanupTerminal(
    SyncMediaCleanupData cleanup,
    String message,
  ) async {
    await (db.update(
      db.syncMediaCleanup,
    )..where((row) => row.objectPath.equals(cleanup.objectPath))).write(
      SyncMediaCleanupCompanion(
        attempts: const Value(-1),
        nextAttemptAt: const Value(null),
        lastError: Value(message),
      ),
    );
  }

  Future<void> _saveShadow(SyncRecord record) async {
    if (record.revision == null) return;
    await db
        .into(db.syncShadows)
        .insertOnConflictUpdate(
          SyncShadowsCompanion.insert(
            entity: record.spec.entity,
            recordKey: record.recordKey,
            remoteRevision: record.revision!,
            remoteModifiedAt: Value(record.clientModifiedAt),
            payloadHash: Value(_payloadHash(record.values)),
            lastSyncedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<T> withOutboxSuppressed<T>(Future<T> Function() action) async {
    await _setOutboxSuppressed(true);
    try {
      return await action();
    } finally {
      await _setOutboxSuppressed(false);
    }
  }

  Future<void> _setOutboxSuppressed(bool suppressed) {
    return (db.update(db.syncRuntime)..where((row) => row.id.equals(1))).write(
      SyncRuntimeCompanion(suppressOutbox: Value(suppressed)),
    );
  }

  Future<void> _deleteLocalMediaFile(String relativePath) async {
    try {
      final documents = await getApplicationDocumentsDirectory();
      final file = File(
        p.normalize(p.joinAll([documents.path, ...relativePath.split('/')])),
      );
      if (p.isWithin(documents.path, file.path) && await file.exists()) {
        await file.delete();
      }
    } on Object {
      // Database state is authoritative; stale local media is best-effort.
    }
  }
}

Map<String, dynamic>? _decodeMaintenancePayload(String payloadJson) {
  try {
    final decoded = jsonDecode(payloadJson);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  } on Object {
    return null;
  }
}

Map<String, dynamic>? _maintenanceCompletionPlanPreimage(
  Map<String, dynamic> payload,
) {
  final rawPreimage = payload['preimage'];
  if (rawPreimage is Map) {
    final rawPlan = rawPreimage['plan'];
    if (rawPlan is Map) {
      return Map<String, dynamic>.from(rawPlan);
    }
  }

  final rawPlan = payload['plan'];
  final expectedDueDate = payload['expected_next_due_date'];
  if (rawPlan is! Map || expectedDueDate == null) return null;
  return {
    ...Map<String, dynamic>.from(rawPlan),
    'next_due_date': expectedDueDate,
  };
}

String _stringValue(Map<String, dynamic> values, String key, String fallback) {
  final value = values[key];
  return value == null ? fallback : value.toString();
}

String? _nullableStringValue(
  Map<String, dynamic> values,
  String key,
  String? fallback,
) {
  if (!values.containsKey(key)) return fallback;
  final value = values[key];
  return value?.toString();
}

int _intValue(Map<String, dynamic> values, String key, int fallback) {
  final value = values[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

bool _boolValue(Map<String, dynamic> values, String key, bool fallback) {
  final value = values[key];
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.toLowerCase() == 'true';
  return fallback;
}

DateTime _dateValue(
  Map<String, dynamic> values,
  String key,
  DateTime fallback,
) {
  return _nullableDateValue(values, key, fallback) ?? fallback;
}

DateTime? _nullableDateValue(
  Map<String, dynamic> values,
  String key,
  DateTime? fallback,
) {
  if (!values.containsKey(key)) return fallback;
  final value = values[key];
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  return DateTime.tryParse(value.toString())?.toUtc() ?? fallback;
}

DateTime? _dateTimeFromStorage(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
  }
  return DateTime.tryParse(value.toString())?.toUtc();
}

DateTime? _semanticClientModifiedAt(
  SyncEntitySpec spec,
  Map<String, dynamic> values,
) {
  final expression = spec.modifiedExpression.trim();
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(expression)) {
    return null;
  }
  return _dateTimeFromStorage(values[expression]);
}

Map<String, dynamic> _toRemoteCompatible(
  SyncEntitySpec spec,
  Map<String, dynamic> source,
) {
  return {
    for (final entry in source.entries)
      entry.key: spec.dateColumns.contains(entry.key)
          ? _dateToIso(entry.value)
          : spec.boolColumns.contains(entry.key)
          ? entry.value == true || entry.value == 1
          : spec.jsonColumns.contains(entry.key) && entry.value is String
          ? jsonDecode(entry.value as String)
          : entry.value,
  };
}

String? _dateToIso(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(
      value * 1000,
      isUtc: true,
    ).toIso8601String();
  }
  return DateTime.parse(value.toString()).toUtc().toIso8601String();
}

Object? _toLocalValue(SyncEntitySpec spec, String column, dynamic value) {
  if (value == null) return null;
  if (spec.dateColumns.contains(column)) {
    final date = value is DateTime ? value : DateTime.parse(value.toString());
    return date.toUtc().millisecondsSinceEpoch ~/ 1000;
  }
  if (spec.boolColumns.contains(column)) {
    return value == true ? 1 : 0;
  }
  if (spec.jsonColumns.contains(column)) {
    return jsonEncode(value);
  }
  return value as Object;
}

String _payloadHash(Map<String, dynamic> values) {
  final keys = values.keys.toList()..sort();
  final canonical = jsonEncode({for (final key in keys) key: values[key]});
  return sha256.convert(utf8.encode(canonical)).toString();
}

const _seedValues = <String, Map<String, Map<String, Object?>>>{
  'user_setting': {
    'theme': {'key': 'theme', 'value': 'system'},
    'app_language': {'key': 'app_language', 'value': 'en'},
    'app_language_explicit': {'key': 'app_language_explicit', 'value': 'false'},
    'theme_time_of_day_enabled': {
      'key': 'theme_time_of_day_enabled',
      'value': 'false',
    },
    'notifications_enabled': {'key': 'notifications_enabled', 'value': 'true'},
    'onboarding_completed': {'key': 'onboarding_completed', 'value': 'false'},
    'permission_education_seen': {
      'key': 'permission_education_seen',
      'value': 'false',
    },
    'permission_education_seen_v2': {
      'key': 'permission_education_seen_v2',
      'value': 'false',
    },
  },
  'streak': {
    'default': {
      'id': 'default',
      'current_streak': 0,
      'best_streak': 0,
      'last_completed_date': null,
    },
  },
};
