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
}
