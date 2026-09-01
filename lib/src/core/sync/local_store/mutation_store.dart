part of '../local_sync_store.dart';

mixin _LocalSyncMutationStore on _LocalSyncStoreBase {
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

  Future<void> prepareMaintenanceHistoryRestore(
    LocalSyncMutation mutation, {
    required String payloadJson,
    required String userId,
  }) async {
    if (mutation.entity != 'maintenance_history_restore' ||
        mutation.operation != 'execute') {
      throw StateError('Invalid maintenance history restore mutation.');
    }
    final updated =
        await (db.update(db.syncOutbox)..where(
              (row) =>
                  row.entity.equals(mutation.entity) &
                  row.recordKey.equals(mutation.recordKey) &
                  row.generation.equals(mutation.generation),
            ))
            .write(
              SyncOutboxCompanion(
                payloadJson: Value(payloadJson),
                userId: Value(mutation.userId ?? userId),
                state: const Value('inFlight'),
                nextAttemptAt: const Value(null),
              ),
            );
    if (updated != 1) {
      throw StateError('Maintenance history restore intent changed.');
    }
  }

  Future<void> markMaintenanceHistoryRestoreSucceeded(
    LocalSyncMutation mutation, {
    SyncRecord? plan,
  }) async {
    await db.transaction(() async {
      if (plan != null) await applyRemoteRecords([plan]);
      await (db.delete(db.syncOutbox)..where(
            (row) =>
                row.entity.equals(mutation.entity) &
                row.recordKey.equals(mutation.recordKey) &
                row.generation.equals(mutation.generation),
          ))
          .go();
    });
  }

  Future<bool> markMaintenanceHistoryRestoreConflict(
    LocalSyncMutation mutation, {
    required String conflictReason,
    required String message,
  }) async {
    if (mutation.entity != 'maintenance_history_restore' ||
        mutation.operation != 'execute') {
      throw StateError('Invalid maintenance history restore mutation.');
    }
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
                lastErrorCode: Value(conflictReason),
                lastError: Value(message),
              ),
            );
    return updated > 0;
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
                  row.state.equals('failedVisible') |
                  row.state.equals('conflict') |
                  row.attempts.equals(-1),
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
          'supported_actions': row.state == 'conflict'
              ? const ['retry', 'keep_local', 'keep_remote']
              : const ['retry', 'acknowledge', 'dismiss'],
        },
    ];
  }

  Future<List<FailedSyncMutationSummary>> listFailedVisibleMutations() async {
    final rows =
        await (db.select(db.syncOutbox)..where(
              (row) =>
                  row.state.equals('failedVisible') |
                  (row.attempts.equals(-1) &
                      row.state.isNotValue(SyncMutationState.conflict.name)),
            ))
            .get();
    return [
      for (final row in rows)
        FailedSyncMutationSummary(
          entity: row.entity,
          recordKey: row.recordKey,
          operation: row.operation,
          errorCode: row.lastErrorCode ?? 'unknown',
        ),
    ];
  }

  Future<List<SyncConflictRow>> listSyncConflicts({
    String? accountId,
    String? resolutionStatus,
  }) async {
    final query = db.select(db.syncConflicts);
    if (accountId != null) {
      query.where((row) => row.accountId.equals(accountId));
    }
    if (resolutionStatus != null) {
      query.where((row) => row.resolutionStatus.equals(resolutionStatus));
    }
    return query.get();
  }

  Future<List<SyncConflictSummary>> listUnresolvedSyncConflictSummaries({
    required String accountId,
  }) async {
    final rows =
        await (db.select(db.syncConflicts)
              ..where(
                (row) =>
                    row.accountId.equals(accountId) &
                    row.resolutionStatus.equals('unresolved') &
                    row.resolvedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
            .get();
    final seen = <String>{};
    return [
      for (final row in rows)
        if (seen.add('${row.entity}\u0000${row.recordKey}'))
          SyncConflictSummary(
            entity: row.entity,
            recordKey: row.recordKey,
            createdAt: row.createdAt,
          ),
    ];
  }

  /// Reads the transactional restore-generation marker written inside the
  /// restore import transaction. The value equals the active journal id only
  /// when SQLite actually committed; recovery must consult this instead of
  /// trusting journal phase labels.
  Future<String?> readRestoreGenerationMarker() async {
    final row = await db
        .customSelect(
          'SELECT value FROM settings WHERE key = ? LIMIT 1',
          variables: [Variable<String>(restoreGenerationSettingKey)],
        )
        .getSingleOrNull();
    return row?.read<String?>('value');
  }

  Future<void> resolveFailedMutation({
    required String entity,
    required String recordKey,
    required String action,
  }) async {
    await db.transaction(() async {
      Expression<bool> target(SyncOutbox row) =>
          row.entity.equals(entity) &
          row.recordKey.equals(recordKey) &
          row.state.isNotIn([SyncMutationState.conflict.name]);
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

  Future<void> reconcileAssetCopyComposite({
    required String assetId,
    Map<String, dynamic>? assetJson,
    List<Map<String, dynamic>> plans = const [],
    List<Map<String, dynamic>> planMetadata = const [],
    List<Map<String, dynamic>> detailRows = const [],
  }) async {
    if (assetJson == null || assetJson.isEmpty) return;
    final assetSpec = syncSpecByEntity['asset']!;
    final asset = SyncRecord.fromRemote(assetSpec, assetJson);
    if (asset.recordKey != assetId) {
      throw const FormatException('The copy RPC returned the wrong asset.');
    }

    final records = <SyncRecord>[asset];
    final planIds = <String>{};
    for (final row in plans) {
      final record = SyncRecord.fromRemote(
        syncSpecByEntity['maintenance_plan']!,
        row,
      );
      if (row['asset_id'] != assetId || !planIds.add(record.recordKey)) {
        throw const FormatException('The copy RPC returned invalid tasks.');
      }
      records.add(record);
    }
    for (final row in planMetadata) {
      final record = SyncRecord.fromRemote(
        syncSpecByEntity['maintenance_plan_metadata']!,
        row,
      );
      if (!planIds.contains(record.recordKey)) {
        throw const FormatException(
          'The copy RPC returned metadata for an unknown task.',
        );
      }
      records.add(record);
    }
    final detailEntities = <String>{};
    for (final envelope in detailRows) {
      final entity = envelope['entity'] as String?;
      final rawRow = envelope['row'];
      final spec = entity == null ? null : syncSpecByEntity[entity];
      if (entity == null ||
          spec == null ||
          !const {
            'device_detail',
            'pet_detail',
            'plant_detail',
            'safety_detail',
          }.contains(entity) ||
          rawRow is! Map ||
          !detailEntities.add(entity)) {
        throw const FormatException('The copy RPC returned invalid details.');
      }
      final row = Map<String, dynamic>.from(rawRow);
      final record = SyncRecord.fromRemote(spec, row);
      if (record.recordKey != assetId) {
        throw const FormatException('The copy RPC returned foreign details.');
      }
      records.add(record);
    }

    await db.transaction(() async {
      await applyRemoteRecords(records);
      await (db.delete(db.syncOutbox)..where(
            (row) =>
                (row.entity.equals('asset') & row.recordKey.equals(assetId)) |
                (row.entity.equals('maintenance_plan') &
                    row.recordKey.isIn(planIds)) |
                (row.entity.equals('maintenance_plan_metadata') &
                    row.recordKey.isIn(planIds)) |
                (row.entity.isIn(detailEntities) &
                    row.recordKey.equals(assetId)),
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
    } on Object {
      // WP-006 (F-015): unreadable payloads are observable, never silent.
      // The plan id stays unknown (matching prior behaviour) so callers
      // treat the mutation conservatively.
      payloadParseFailures++;
      AppLogger.warning(
        'sync_mutation_payload_unreadable',
        fields: {'entity': mutation.entity},
      );
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
    final planId = payload['plan_id']?.toString();
    if (planId == null || planId.isEmpty) return;

    final current = await (db.select(
      db.maintenancePlans,
    )..where((row) => row.id.equals(planId))).getSingleOrNull();
    if (current == null ||
        current.currentOccurrenceId != 'next:${mutation.operationId}' ||
        current.updatedAt.isAfter(mutation.changedAt)) {
      return;
    }

    await (db.update(
      db.maintenancePlans,
    )..where((row) => row.id.equals(planId))).write(
      MaintenancePlansCompanion(
        currentOccurrenceId: Value(
          planValues['current_occurrence_id']?.toString() ??
              current.currentOccurrenceId,
        ),
        nextDueDate: Value(
          _dateValue(planValues, 'next_due_date', current.nextDueDate),
        ),
        updatedAt: Value(
          _dateValue(planValues, 'updated_at', current.updatedAt),
        ),
      ),
    );
  }

  Future<bool> markMutationSucceeded(
    LocalSyncMutation mutation,
    SyncRecord? canonical,
  ) async {
    return await db.transaction(() async {
      await _resolveConflictsForAcknowledgedKey(
        mutation.entity,
        mutation.recordKey,
      );
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

  Future<bool> markMutationSucceededAndEnqueueMediaCleanup(
    LocalSyncMutation mutation,
    SyncRecord? canonical, {
    required String userId,
    required List<String> objectPaths,
  }) async {
    final cleanupPaths = objectPaths.where((path) => path.isNotEmpty).toSet();
    for (final objectPath in cleanupPaths) {
      if (!objectPath.startsWith('$userId/')) {
        throw StateError(
          'Media cleanup path belongs to another cloud account.',
        );
      }
    }

    return db.transaction(() async {
      final pending =
          await (db.select(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals(mutation.entity) &
                    row.recordKey.equals(mutation.recordKey) &
                    row.generation.equals(mutation.generation),
              ))
              .getSingleOrNull();
      if (pending == null) return false;
      if (pending.userId != null && pending.userId != userId) {
        throw StateError('Queued mutation belongs to another cloud account.');
      }

      await _resolveConflictsForAcknowledgedKey(
        mutation.entity,
        mutation.recordKey,
      );
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

      for (final objectPath in cleanupPaths) {
        await db
            .into(db.syncMediaCleanup)
            .insertOnConflictUpdate(
              SyncMediaCleanupCompanion.insert(
                objectPath: objectPath,
                userId: userId,
                entity: mutation.entity,
                recordKey: mutation.recordKey,
              ),
            );
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

  /// Preserves an unresolved push conflict without deleting the durable local
  /// intent. The outbox row enters the `conflict` state and stays there across
  /// restarts until the exact server acknowledges a newer generation or the
  /// user explicitly resolves the conflict. `resolvedAt` remains null until
  /// that explicit resolution.
  Future<bool> markMutationConflicted(
    LocalSyncMutation mutation, {
    required String accountId,
    required String reason,
    String? localPayloadJson,
    String? remotePayloadJson,
    int? remoteRevision,
  }) async {
    return _preserveConflictIntent(
      entity: mutation.entity,
      recordKey: mutation.recordKey,
      accountId: accountId,
      reason: reason,
      localPayloadJson: localPayloadJson ?? mutation.payloadJson,
      remotePayloadJson: remotePayloadJson,
      remoteRevision: remoteRevision,
      expectedGeneration: mutation.generation,
    );
  }

  /// Pull-path variant of [markMutationConflicted] for callers that only know
  /// the entity key. The current local record values are snapshotted so an
  /// explicit keep-local resolution can still restore the user's edit after
  /// the canonical remote row has been applied, and the outbox generation is
  /// read transactionally so a newer same-key edit can never be clobbered by
  /// stale pull evidence.
  Future<bool> markEntityMutationConflicted({
    required String entity,
    required String recordKey,
    required String accountId,
    required String deviceId,
    required String reason,
    String? remotePayloadJson,
    int? remoteRevision,
  }) async {
    return db.transaction(() async {
      final row =
          await (db.select(db.syncOutbox)..where(
                (candidate) =>
                    candidate.entity.equals(entity) &
                    candidate.recordKey.equals(recordKey),
              ))
              .getSingleOrNull();
      if (row == null) return false;
      String? localPayloadJson = row.payloadJson;
      if (localPayloadJson == null || localPayloadJson.trim().isEmpty) {
        try {
          final record = await readMutation(
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
            ),
            deviceId,
          );
          if (record != null) {
            localPayloadJson = encodeConflictPayload(
              operation: row.operation,
              values: record.values,
            );
          }
        } on Object {
          localPayloadJson = row.payloadJson;
        }
      }
      return _preserveConflictIntent(
        entity: entity,
        recordKey: recordKey,
        accountId: accountId,
        reason: reason,
        localPayloadJson: localPayloadJson,
        remotePayloadJson: remotePayloadJson,
        remoteRevision: remoteRevision,
        expectedGeneration: row.generation,
        skipIfAlreadyConflicted: true,
      );
    });
  }

  String encodeConflictPayload({
    required String operation,
    required Map<String, dynamic> values,
  }) {
    return jsonEncode({'operation': operation, 'record': values});
  }

  Future<bool> _preserveConflictIntent({
    required String entity,
    required String recordKey,
    required String accountId,
    required String reason,
    required String? localPayloadJson,
    required String? remotePayloadJson,
    required int? remoteRevision,
    required int expectedGeneration,
    bool skipIfAlreadyConflicted = false,
  }) async {
    return db.transaction(() async {
      final currentState =
          await (db.select(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals(entity) & row.recordKey.equals(recordKey),
              ))
              .getSingleOrNull();
      if (currentState == null) return false;
      final alreadyConflicted =
          currentState.state == SyncMutationState.conflict.name;
      if (!alreadyConflicted ||
          !skipIfAlreadyConflicted ||
          remoteRevision != null) {
        final existingUnresolved =
            await (db.select(db.syncConflicts)..where(
                  (row) =>
                      row.accountId.equals(accountId) &
                      row.entity.equals(entity) &
                      row.recordKey.equals(recordKey) &
                      row.resolutionStatus.equals('unresolved') &
                      row.resolvedAt.isNull(),
                ))
                .get();
        final alreadyRecorded = existingUnresolved.any(
          (row) => row.remoteRevision == remoteRevision,
        );
        if (!alreadyRecorded) {
          await db
              .into(db.syncConflicts)
              .insert(
                SyncConflictsCompanion.insert(
                  id: _localSyncUuid.v4(),
                  accountId: accountId,
                  entity: entity,
                  recordKey: recordKey,
                  operationId: Value(currentState.recordKey),
                  localPayloadJson: Value(localPayloadJson),
                  remotePayloadJson: Value(remotePayloadJson),
                  remoteRevision: Value(remoteRevision),
                  resolutionStatus: const Value('unresolved'),
                  createdAt: Value(DateTime.now().toUtc()),
                ),
              );
        }
      }
      if (alreadyConflicted) return true;
      final updated =
          await (db.update(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals(entity) &
                    row.recordKey.equals(recordKey) &
                    row.generation.equals(expectedGeneration),
              ))
              .write(
                SyncOutboxCompanion(
                  state: const Value('conflict'),
                  nextAttemptAt: const Value(null),
                  lastErrorCode: const Value('conflict_unresolved'),
                  lastError: Value(
                    'Sync conflict ($reason): the local change is '
                    'preserved for review.',
                  ),
                ),
              );
      return updated > 0;
    });
  }

  /// Explicit user resolution of preserved conflicts. `keepLocal` restores
  /// the newest preserved local payload into the local table and returns the
  /// mutation to the automatic push queue; `keepRemote` discards the outbox
  /// intent. Only this method (or exact server acknowledgement) may clear
  /// unresolved conflicts.
  Future<bool> resolveSyncConflict({
    required String entity,
    required String recordKey,
    required String accountId,
    required String deviceId,
    required bool keepLocal,
  }) async {
    return db.transaction(() async {
      final resolvedAt = DateTime.now().toUtc();
      final unresolved =
          await (db.select(db.syncConflicts)..where(
                (row) =>
                    row.accountId.equals(accountId) &
                    row.entity.equals(entity) &
                    row.recordKey.equals(recordKey) &
                    row.resolutionStatus.equals('unresolved') &
                    row.resolvedAt.isNull(),
              ))
              .get();
      if (unresolved.isEmpty) {
        // A non-owning account has nothing to resolve and must never touch
        // another account's preserved intent.
        return false;
      }
      await (db.update(db.syncConflicts)..where(
            (row) =>
                row.accountId.equals(accountId) &
                row.entity.equals(entity) &
                row.recordKey.equals(recordKey) &
                row.resolutionStatus.equals('unresolved') &
                row.resolvedAt.isNull(),
          ))
          .write(
            SyncConflictsCompanion(
              resolutionStatus: Value(
                keepLocal ? 'resolved_keep_local' : 'resolved_keep_remote',
              ),
              resolvedAt: Value(resolvedAt),
            ),
          );
      if (!keepLocal) {
        final deleted =
            await (db.delete(db.syncOutbox)..where(
                  (row) =>
                      row.entity.equals(entity) &
                      row.recordKey.equals(recordKey) &
                      row.state.equals(SyncMutationState.conflict.name),
                ))
                .go();
        return deleted > 0;
      }
      String? newestLocalPayload;
      for (final conflict in unresolved) {
        final payload = conflict.localPayloadJson;
        if (payload != null && payload.trim().isNotEmpty) {
          newestLocalPayload = payload;
        }
      }
      if (newestLocalPayload != null) {
        try {
          final decoded = jsonDecode(newestLocalPayload);
          if (decoded is Map &&
              decoded['operation'] == 'upsert' &&
              decoded['record'] is Map) {
            final spec = syncSpecByEntity[entity];
            if (spec != null) {
              await withOutboxSuppressed<void>(() {
                return _upsertLocal(
                  SyncRecord(
                    spec: spec,
                    recordKey: recordKey,
                    values: Map<String, dynamic>.from(decoded['record'] as Map),
                    clientModifiedAt: resolvedAt,
                    originDeviceId: deviceId,
                  ),
                );
              });
            }
          }
        } on Object {
          // A malformed preserved payload must not block resolution; the
          // queued mutation remains available for retry or dismissal.
        }
      }
      final restored =
          await (db.update(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals(entity) &
                    row.recordKey.equals(recordKey) &
                    row.state.equals(SyncMutationState.conflict.name),
              ))
              .write(
                const SyncOutboxCompanion(
                  state: Value('pending'),
                  attempts: Value(0),
                  nextAttemptAt: Value(null),
                  lastErrorCode: Value(null),
                  lastError: Value(null),
                ),
              );
      return restored > 0;
    });
  }

  Future<void> _resolveConflictsForAcknowledgedKey(
    String entity,
    String recordKey,
  ) async {
    await (db.update(db.syncConflicts)..where(
          (row) =>
              row.entity.equals(entity) &
              row.recordKey.equals(recordKey) &
              row.resolutionStatus.equals('unresolved') &
              row.resolvedAt.isNull(),
        ))
        .write(
          const SyncConflictsCompanion(
            resolutionStatus: Value('resolved_server_acknowledged'),
          ),
        );
    await (db.update(db.syncConflicts)..where(
          (row) =>
              row.entity.equals(entity) &
              row.recordKey.equals(recordKey) &
              row.resolutionStatus.equals('resolved_server_acknowledged') &
              row.resolvedAt.isNull(),
        ))
        .write(
          SyncConflictsCompanion(resolvedAt: Value(DateTime.now().toUtc())),
        );
  }

  Future<bool> markMutationFailed(
    LocalSyncMutation mutation,
    String message, {
    String? errorCode,
  }) async {
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
          lastErrorCode: Value(errorCode ?? 'retry_exhausted'),
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
        lastErrorCode: Value(errorCode ?? 'transient'),
        lastError: Value(message),
      ),
    );
    return updated > 0;
  }

  Future<bool> markMutationTerminal(
    LocalSyncMutation mutation,
    String message, {
    String? errorCode,
  }) async {
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
                lastErrorCode: Value(errorCode ?? 'terminal'),
                lastError: Value(message),
              ),
            );
    return updated > 0;
  }
}
