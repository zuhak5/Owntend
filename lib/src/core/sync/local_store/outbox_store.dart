part of '../local_sync_store.dart';

mixin _LocalSyncOutboxStore on _LocalSyncStoreBase {
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
      ..where(
        db.syncOutbox.attempts.isBiggerOrEqualValue(0) &
            db.syncOutbox.state.isNotIn(const ['conflict']),
      );
    return (await query.map((row) => row.read(count) ?? 0).getSingle());
  }

  Future<int> unresolvedConflictCount() async {
    final count = db.syncOutbox.entity.count();
    final query = db.selectOnly(db.syncOutbox)
      ..addColumns([count])
      ..where(db.syncOutbox.state.equals('conflict'));
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
      ..where(
        db.syncOutbox.attempts.isBiggerOrEqualValue(0) &
            db.syncOutbox.state.isNotIn(const ['conflict']),
      );
    return query.map((row) => row.read(count) ?? 0).watchSingle().distinct();
  }

  Future<bool> hasReadyMutations() async {
    final count = db.syncOutbox.entity.count();
    final now = DateTime.now();
    final query = db.selectOnly(db.syncOutbox)
      ..addColumns([count])
      ..where(
        db.syncOutbox.attempts.isBiggerOrEqualValue(0) &
            db.syncOutbox.state.isNotIn(const ['conflict']) &
            (db.syncOutbox.nextAttemptAt.isNull() |
                db.syncOutbox.nextAttemptAt.isSmallerOrEqualValue(now)),
      );
    return (await query.map((row) => row.read(count) ?? 0).getSingle()) > 0;
  }

  Future<int> pendingMediaCleanupCount() async {
    final cloudCount = db.syncMediaCleanup.objectPath.count();
    final cloudQuery = db.selectOnly(db.syncMediaCleanup)
      ..addColumns([cloudCount]);
    final localCount = db.localMediaCleanup.relativePath.count();
    final localQuery = db.selectOnly(db.localMediaCleanup)
      ..addColumns([localCount]);
    return (await cloudQuery
            .map((row) => row.read(cloudCount) ?? 0)
            .getSingle()) +
        (await localQuery.map((row) => row.read(localCount) ?? 0).getSingle());
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
            db.syncOutbox.state.isNotIn(const ['conflict']) &
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

  /// Schedules a run-level retry backoff for every currently-due mutation.
  ///
  /// WP-006 (F-038): this deliberately does NOT stamp [lastError]. The
  /// failure that caused the deferral is run-level (connectivity, auth,
  /// server health) and is already recorded on `sync_account.last_error`;
  /// copying it onto unrelated rows forged per-row diagnostics that never
  /// described those rows' own outcomes.
  Future<void> deferPendingAfterFailure({
    Duration delay = const Duration(seconds: 15),
  }) async {
    await db.customUpdate(
      '''
UPDATE offline_mutation_queue
SET next_attempt_at = ?
WHERE (next_attempt_at IS NULL OR next_attempt_at <= ?)
  AND state <> 'conflict'
''',
      variables: [
        Variable<DateTime>(DateTime.now().add(delay)),
        Variable<DateTime>(DateTime.now()),
      ],
      updates: {db.syncOutbox},
      updateKind: UpdateKind.update,
    );
  }

  Future<void> enforceMaintenanceHistoryMutationAuthority() async {
    await db.transaction(() async {
      final rows =
          await (db.select(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals('maintenance_record') |
                    row.entity.equals('maintenance_completion') |
                    row.entity.equals('maintenance_undo'),
              ))
              .get();
      final authoritativeRecordKeys = <String>{};
      for (final row in rows) {
        if (row.operation != 'execute' || row.payloadJson == null) continue;
        try {
          final decoded = jsonDecode(row.payloadJson!);
          if (decoded is! Map) continue;
          if (row.entity == 'maintenance_completion') {
            final record = decoded['record'];
            final recordId = record is Map ? record['id'] : null;
            final operationId = decoded['operation_id'];
            if (recordId == row.recordKey || operationId == row.recordKey) {
              authoritativeRecordKeys.add(row.recordKey);
            }
          } else if (row.entity == 'maintenance_undo' &&
              (decoded['completion_id'] == row.recordKey ||
                  decoded['operation_id'] == row.recordKey)) {
            authoritativeRecordKeys.add(row.recordKey);
          }
        } on Object {
          // A malformed composite intent cannot authorize deletion of a
          // generic history row. Its ordinary push path will surface its own
          // terminal payload error.
        }
      }

      final genericRows = rows
          .where((row) => row.entity == 'maintenance_record')
          .toList(growable: false);
      for (final row in genericRows) {
        final predicate =
            (db.syncOutbox.entity.equals(row.entity) &
            db.syncOutbox.recordKey.equals(row.recordKey) &
            db.syncOutbox.generation.equals(row.generation));
        if (authoritativeRecordKeys.contains(row.recordKey)) {
          await (db.delete(db.syncOutbox)..where((_) => predicate)).go();
          continue;
        }
        if (row.state == SyncMutationState.failedVisible.name &&
            row.lastErrorCode == 'server_authority_required') {
          continue;
        }
        await (db.update(db.syncOutbox)..where((_) => predicate)).write(
          const SyncOutboxCompanion(
            attempts: Value(-1),
            state: Value('failedVisible'),
            nextAttemptAt: Value(null),
            lastErrorCode: Value('server_authority_required'),
            lastError: Value(
              'Maintenance history changes require completion, undo, or validated restore authority.',
            ),
          ),
        );
      }
    });
  }

  Future<List<LocalSyncMutation>> pendingMutations({int limit = 200}) async {
    final now = DateTime.now();
    // WP-006 (F-010): the due-window query is bounded; dependency keys are
    // resolved with one targeted lookup for the referenced operation ids
    // instead of loading every outbox row into memory on each push cycle.
    final dueQuery = db.select(db.syncOutbox)
      ..where(
        (row) =>
            row.attempts.isBiggerOrEqualValue(0) &
            row.state.isNotIn(const ['conflict']) &
            (row.nextAttemptAt.isNull() |
                row.nextAttemptAt.isSmallerOrEqualValue(now)),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.localSequence)])
      ..limit(limit);
    final rows = await dueQuery.get();

    final dependsOnByRow = <String, String?>{};
    final dependsOnIds = <String>{};
    for (final row in rows) {
      if (row.entity != 'maintenance_completion' || row.payloadJson == null) {
        continue;
      }
      try {
        final decoded = jsonDecode(row.payloadJson!) as Map<String, dynamic>;
        final dependsOn = decoded['depends_on_operation_id'] as String?;
        dependsOnByRow[row.recordKey] = dependsOn;
        if (dependsOn != null && dependsOn.isNotEmpty) {
          dependsOnIds.add(dependsOn);
        }
      } on Object {
        // F-015: corrupt payloads no longer vanish silently. The mutation
        // stays eligible (conservative, matching prior behaviour) and the
        // failure is observable through [payloadParseFailures].
        payloadParseFailures++;
        AppLogger.warning(
          'sync_outbox_payload_unreadable',
          fields: {'entity': row.entity},
        );
      }
    }

    final Set<String> blockedDependencyKeys;
    if (dependsOnIds.isEmpty) {
      blockedDependencyKeys = const <String>{};
    } else {
      final referenced = await (db.select(
        db.syncOutbox,
      )..where((row) => row.recordKey.isIn(dependsOnIds))).get();
      blockedDependencyKeys = {
        for (final row in referenced)
          if (row.attempts >= 0 &&
              const {
                'pending',
                'inFlight',
                'conflictRecovery',
              }.contains(row.state))
            row.recordKey,
      };
    }

    final rawMutations = [
      for (final row in rows)
        LocalSyncMutation(
          entity: row.entity,
          recordKey: row.recordKey,
          operation: row.operation,
          changedAt: row.changedAt,
          attempts: row.attempts,
          localSequence: row.localSequence,
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
      if (mutation.entity == 'maintenance_completion') {
        final dependsOn = dependsOnByRow[mutation.recordKey];
        if (dependsOn != null &&
            dependsOn.isNotEmpty &&
            blockedDependencyKeys.contains(dependsOn)) {
          continue;
        }
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
      dependencyOrder['maintenance_history_restore'] =
          dependencyOrder['maintenance_record'] ?? maintenancePlanOrder;
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

      final sequenceComparison = a.localSequence.compareTo(b.localSequence);
      if (sequenceComparison != 0) return sequenceComparison;

      if (a.entity == b.entity) return a.recordKey.compareTo(b.recordKey);
      if (a.entity == 'maintenance_completion') return -1;
      if (b.entity == 'maintenance_completion') return 1;
      return a.entity.compareTo(b.entity);
    });
    return mutations.take(limit).toList(growable: false);
  }

  Future<void> enqueueInitialSnapshot() async {
    for (final spec in syncEntitySpecs) {
      if (spec.entity == 'maintenance_record') continue;
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
      if (spec.entity == 'maintenance_record') continue;
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

      // Every generic history mutation generated by this restore snapshot is
      // replaced below by a bounded validated merge RPC. Unsupported history
      // writes encountered during ordinary sync still fail visibly at the
      // gateway; only restore-origin rows are converted here.
      await (db.delete(
        db.syncOutbox,
      )..where((row) => row.entity.equals('maintenance_record'))).go();

      final accountRow = await (db.select(
        db.syncAccount,
      )..where((row) => row.id.equals(1))).getSingleOrNull();
      final plans = await db.select(db.maintenancePlans).get();
      for (final plan in plans) {
        final records =
            await (db.select(db.maintenanceRecords)
                  ..where((row) => row.planId.equals(plan.id))
                  ..orderBy([
                    (row) => OrderingTerm.asc(row.completedAt),
                    (row) => OrderingTerm.asc(row.id),
                  ]))
                .get();
        for (var offset = 0; offset < records.length; offset += 100) {
          final batch = records.sublist(
            offset,
            math.min(offset + 100, records.length),
          );
          final operationId = _localSyncUuid.v7();
          final payload = <String, dynamic>{
            'version': 1,
            'operation_id': operationId,
            // Prepared immediately before the first network attempt from the
            // current canonical cloud revision, then persisted verbatim.
            'expected_plan_revision': 0,
            'plan_id': plan.id,
            'plan_snapshot': {
              'asset_id': plan.assetId,
              'recurrence_interval': plan.recurrenceInterval,
              'recurrence_unit': plan.recurrenceUnit,
              'next_due_date': _restoreSyncSecond(plan.nextDueDate)
                  .toIso8601String(),
              'is_enabled': plan.isEnabled,
              'archived_at': plan.archivedAt == null
                  ? null
                  : _restoreSyncSecond(plan.archivedAt!).toIso8601String(),
            },
            'records': [
              for (final record in batch)
                {
                  'id': record.id,
                  'operation_id': record.id,
                  'plan_id': plan.id,
                  'occurrence_id': record.occurrenceId,
                  'due_date': _restoreSyncSecond(record.dueDate)
                      .toIso8601String(),
                  'completed_at': _restoreSyncSecond(record.completedAt)
                      .toIso8601String(),
                  'accepted_at': _restoreSyncSecond(
                    record.acceptedAt ?? record.completedAt,
                  ).toIso8601String(),
                  'time_zone_id': record.timeZoneId,
                  'notes': record.notes,
                  'created_at': _restoreSyncSecond(record.completedAt)
                      .toIso8601String(),
                  'revision': 1,
                },
            ],
          };
          await db
              .into(db.syncOutbox)
              .insert(
                SyncOutboxCompanion.insert(
                  entity: 'maintenance_history_restore',
                  recordKey: operationId,
                  operation: 'execute',
                  changedAt: Value(restoredAt),
                  payloadJson: Value(jsonEncode(payload)),
                  userId: Value(accountRow?.boundUserId),
                ),
              );
        }
      }
      // WP-005 (F-009): a restore must not resurrect user-dismissed failures
      // (`failedVisible`) or unresolved conflicts (`conflict`). Only
      // retryable states have their backoff and error stamps cleared so the
      // post-restore push starts immediately without erasing terminal
      // decisions the user already made.
      await (db.update(db.syncOutbox)..where(
            (row) => row.state.isIn(const [
              'pending',
              'inFlight',
              'conflictRecovery',
            ]),
          ))
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

  @override
  Future<SyncRecord?> readMutation(
    LocalSyncMutation mutation,
    String deviceId,
  ) async {
    final spec = syncSpecByEntity[mutation.entity];
    if (spec == null) {
      throw SupabaseFailure(
        kind: SupabaseFailureKind.incompatibleSchema,
        message:
            'The local sync queue contains an unsupported entity contract: '
            '${mutation.entity}.',
      );
    }
    if (mutation.operation == 'delete') {
      final values = <String, dynamic>{};
      if (spec.entity != 'profile') {
        final keyParts = mutation.recordKey.split('|');
        for (var index = 0; index < spec.keyColumns.length; index++) {
          values[spec.keyColumns[index]] = keyParts[index];
        }
      }
      if (spec.entity == 'asset_photo') {
        final cleanupObjectPath = _photoDeleteCleanupObjectPath(mutation);
        if (cleanupObjectPath != null) {
          values['cleanup_object_path'] = cleanupObjectPath;
        }
        final assetId = _photoDeleteAssetId(mutation);
        if (assetId != null) {
          values['asset_id'] = assetId;
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

  String? _photoDeleteCleanupObjectPath(LocalSyncMutation mutation) {
    final payloadJson = mutation.payloadJson;
    if (payloadJson == null || payloadJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) return null;
      final path = decoded['cleanup_object_path'];
      return path is String && path.trim().isNotEmpty ? path : null;
    } on Object {
      return null;
    }
  }

  String? _photoDeleteAssetId(LocalSyncMutation mutation) {
    final payloadJson = mutation.payloadJson;
    if (payloadJson == null || payloadJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) return null;
      final assetId = decoded['asset_id'];
      return assetId is String && assetId.trim().isNotEmpty ? assetId : null;
    } on Object {
      return null;
    }
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

  Future<Map<String, dynamic>?> readAssetDetails(String assetId) async {
    final assetRow = await db
        .customSelect(
          'SELECT asset_type FROM assets WHERE id = ? LIMIT 1',
          variables: [Variable<String>(assetId)],
        )
        .getSingleOrNull();
    final assetType = assetRow?.read<String?>('asset_type');
    if (assetType == null || assetType == 'general') {
      return const <String, dynamic>{};
    }
    final table = switch (assetType) {
      'device' => 'device_details',
      'pet' => 'pet_details',
      'plant' => 'plant_details',
      'safety' => 'safety_details',
      _ => null,
    };
    if (table == null) return const <String, dynamic>{};
    final spec = syncSpecByEntity['${assetType}_detail'];
    if (spec == null) return const <String, dynamic>{};
    final row = await db
        .customSelect(
          'SELECT ${spec.localColumns.join(', ')} FROM $table WHERE asset_id = ? LIMIT 1',
          variables: [Variable<String>(assetId)],
        )
        .getSingleOrNull();
    if (row == null) return const <String, dynamic>{};
    return _toRemoteCompatible(spec, row.data);
  }

  Future<Map<String, dynamic>?> readPlanMetadata(String planId) async {
    final spec = syncSpecByEntity['maintenance_plan_metadata'];
    if (spec == null) return const <String, dynamic>{};
    final row = await db
        .customSelect(
          'SELECT ${spec.localColumns.join(', ')} FROM maintenance_plan_metadata WHERE plan_id = ? LIMIT 1',
          variables: [Variable<String>(planId)],
        )
        .getSingleOrNull();
    if (row == null) return const <String, dynamic>{};
    return _toRemoteCompatible(spec, row.data);
  }
}

DateTime _restoreSyncSecond(DateTime value) {
  final utc = value.toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    (utc.millisecondsSinceEpoch ~/ 1000) * 1000,
    isUtc: true,
  );
}
