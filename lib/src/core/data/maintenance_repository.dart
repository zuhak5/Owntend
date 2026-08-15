part of 'repositories.dart';

class DriftMaintenanceRepository
    implements MaintenanceRepository, CalendarRepository {
  DriftMaintenanceRepository(
    this.db, {
    this._recurrenceEngine = const OwntendRecurrenceEngine(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppDatabase db;
  final RecurrenceEngine _recurrenceEngine;
  final DateTime Function() _now;

  @override
  Stream<List<domain.TaskItem>> watchTasks() {
    return _watchTaskDependencies(listTasks);
  }

  @override
  Stream<List<domain.TaskItem>> watchSavedTasks() {
    return _watchTaskDependencies(
      listSavedTasks,
      fingerprint: taskListFingerprint,
    );
  }

  @override
  Stream<List<domain.TaskItem>> watchArchivedTasks() {
    return _watchTaskDependencies(
      listArchivedTasks,
      fingerprint: taskListFingerprint,
    );
  }

  @override
  Future<List<domain.TaskItem>> listTasks() async {
    final planRows =
        await (db.select(db.maintenancePlans)
              ..where(
                (plan) =>
                    plan.archivedAt.isNull() & plan.isEnabled.equals(true),
              )
              ..orderBy([(plan) => OrderingTerm.asc(plan.nextDueDate)]))
            .get();
    return _hydrateTasks(planRows);
  }

  @override
  Future<List<domain.TaskItem>> listSavedTasks() async {
    final planRows =
        await (db.select(db.maintenancePlans)
              ..where((plan) => plan.archivedAt.isNull())
              ..orderBy([(plan) => OrderingTerm.asc(plan.nextDueDate)]))
            .get();
    return _hydrateTasks(planRows);
  }

  @override
  Future<List<domain.TaskItem>> listArchivedTasks() async {
    final planRows =
        await (db.select(db.maintenancePlans)
              ..where((plan) => plan.archivedAt.isNotNull())
              ..orderBy([(plan) => OrderingTerm.desc(plan.archivedAt)]))
            .get();
    return _hydrateTasks(planRows, includeArchivedAssets: true);
  }

  @override
  Stream<domain.TaskItem?> watchTask(String planId) {
    return _watchTaskDependencies(
      () => getTask(planId),
      fingerprint: (task) => task == null ? 0 : taskFingerprint(task),
    );
  }

  @override
  Future<domain.TaskItem?> getTask(String planId) async {
    final planRow = await (db.select(
      db.maintenancePlans,
    )..where((plan) => plan.id.equals(planId))).getSingleOrNull();
    if (planRow == null) {
      return null;
    }
    return (await _hydrateTasks([planRow])).firstOrNull;
  }

  @override
  Stream<List<domain.TaskItem>> watchTasksForAsset(String assetId) {
    return _watchTaskDependencies(
      () => listTasksForAsset(assetId),
      fingerprint: taskListFingerprint,
    );
  }

  @override
  Stream<List<domain.TaskItem>> watchSavedTasksForAsset(String assetId) {
    return _watchTaskDependencies(
      () => listSavedTasksForAsset(assetId),
      fingerprint: taskListFingerprint,
    );
  }

  @override
  Future<List<domain.TaskItem>> listTasksForAsset(String assetId) async {
    final planRows =
        await (db.select(db.maintenancePlans)
              ..where(
                (plan) =>
                    plan.assetId.equals(assetId) &
                    plan.archivedAt.isNull() &
                    plan.isEnabled.equals(true),
              )
              ..orderBy([(plan) => OrderingTerm.asc(plan.nextDueDate)]))
            .get();
    return _hydrateTasks(planRows);
  }

  @override
  Future<List<domain.TaskItem>> listSavedTasksForAsset(String assetId) async {
    final planRows =
        await (db.select(db.maintenancePlans)
              ..where(
                (plan) =>
                    plan.assetId.equals(assetId) & plan.archivedAt.isNull(),
              )
              ..orderBy([(plan) => OrderingTerm.asc(plan.nextDueDate)]))
            .get();
    return _hydrateTasks(planRows);
  }

  @override
  Future<List<domain.TaskItem>> tasksBetween(
    DateTime startInclusive,
    DateTime endInclusive,
  ) async {
    final start = dateOnly(startInclusive);
    final end = DateTime(
      endInclusive.year,
      endInclusive.month,
      endInclusive.day,
      23,
      59,
      59,
      999,
      999,
    );
    final planRows =
        await (db.select(db.maintenancePlans)
              ..where(
                (plan) =>
                    plan.archivedAt.isNull() &
                    plan.isEnabled.equals(true) &
                    plan.nextDueDate.isBiggerOrEqualValue(start) &
                    plan.nextDueDate.isSmallerOrEqualValue(end),
              )
              ..orderBy([(plan) => OrderingTerm.asc(plan.nextDueDate)]))
            .get();
    return _hydrateTasks(planRows);
  }

  @override
  Future<String> savePlan({
    String? id,
    required String assetId,
    required String title,
    String? instructions,
    required domain.RecurrenceRule recurrence,
    required domain.PriorityLevel priority,
    required DateTime nextDueDate,
    required domain.HealthGroup healthGroup,
    int reminderDaysBefore = 0,
    domain.TaskMetadata? metadata,
  }) async {
    final cleanAssetId = assetId.trim();
    final cleanTitle = title.trim();
    await _validatePlanTargetAsset(cleanAssetId);
    if (recurrence.interval < 1) {
      throw const MaintenancePlanValidationException(
        'Task recurrence must be greater than zero.',
        code: 'invalid_recurrence',
      );
    }
    if (cleanTitle.isEmpty) {
      throw const MaintenancePlanValidationException(
        'Task title is required.',
        code: 'missing_title',
      );
    }
    if (reminderDaysBefore < 0) {
      throw const MaintenancePlanValidationException(
        'Reminder lead time cannot be negative.',
        code: 'invalid_reminder',
      );
    }
    final planId = id ?? _uuid.v7();
    final now = _now();
    await db.transaction(() async {
      final existingPlan = await (db.select(
        db.maintenancePlans,
      )..where((plan) => plan.id.equals(planId))).getSingleOrNull();
      if (existingPlan == null) {
        await db
            .into(db.maintenancePlans)
            .insert(
              MaintenancePlansCompanion.insert(
                id: planId,
                assetId: cleanAssetId,
                title: cleanTitle,
                instructions: Value(_blankToNull(instructions)),
                recurrenceInterval: recurrence.interval,
                recurrenceUnit: recurrence.unit.name,
                priority: priority.name,
                nextDueDate: nextDueDate,
                reminderDaysBefore: Value(reminderDaysBefore),
                healthGroup: healthGroup.name,
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        if (metadata != null) {
          await _savePlanMetadata(planId, metadata, now);
        }
      } else {
        await (db.update(
          db.maintenancePlans,
        )..where((plan) => plan.id.equals(planId))).write(
          MaintenancePlansCompanion(
            assetId: Value(cleanAssetId),
            title: Value(cleanTitle),
            instructions: Value(_blankToNull(instructions)),
            recurrenceInterval: Value(recurrence.interval),
            recurrenceUnit: Value(recurrence.unit.name),
            priority: Value(priority.name),
            nextDueDate: Value(nextDueDate),
            reminderDaysBefore: Value(reminderDaysBefore),
            healthGroup: Value(healthGroup.name),
            updatedAt: Value(now),
          ),
        );
        if (metadata != null) {
          await _savePlanMetadata(planId, metadata, now);
        }
        await _markPlanInboxRead(planId);
      }
    });
    return planId;
  }

  Future<void> _savePlanMetadata(
    String planId,
    domain.TaskMetadata metadata,
    DateTime now,
  ) async {
    await db
        .into(db.maintenancePlanMetadata)
        .insertOnConflictUpdate(
          MaintenancePlanMetadataCompanion.insert(
            planId: planId,
            taskType: Value(_blankToNull(metadata.taskType)),
            locationLabel: Value(_blankToNull(metadata.locationLabel)),
            estimatedDurationMinutes: Value(metadata.estimatedDurationMinutes),
            requiredMaterialsJson: Value(
              jsonEncode(metadata.requiredMaterials),
            ),
            reminderRecommendation: Value(
              _blankToNull(metadata.reminderRecommendation),
            ),
            sortOrder: Value(metadata.sortOrder),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> _validatePlanTargetAsset(String assetId) async {
    if (assetId.isEmpty) {
      throw const MaintenancePlanValidationException(
        'Suggestion not applied. The related item could not be found.',
        code: 'missing_asset',
      );
    }
    final asset =
        await (db.select(
              db.assets,
            )..where((row) => row.id.equals(assetId) & row.archivedAt.isNull()))
            .getSingleOrNull();
    if (asset == null) {
      throw const MaintenancePlanValidationException(
        'Suggestion not applied. The related item could not be found.',
        code: 'invalid_asset',
      );
    }
  }

  @override
  Future<bool> completePlan(
    String planId, {
    DateTime? completedAt,
    String? notes,
    DateTime? expectedNextDueDate,
  }) async {
    final result = await completePlanResult(
      planId,
      completedAt: completedAt,
      notes: notes,
      expectedNextDueDate: expectedNextDueDate,
    );
    return result.isApplied;
  }

  DateTime canonicalSyncSecond(DateTime value) {
    final utc = value.toUtc();
    final micros =
        (utc.microsecondsSinceEpoch ~/ Duration.microsecondsPerSecond) *
        Duration.microsecondsPerSecond;

    return DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
  }

  @override
  Future<LocalMaintenanceCompletionResult> completePlanResult(
    String planId, {
    DateTime? completedAt,
    String? notes,
    DateTime? expectedNextDueDate,
  }) {
    return db.transaction(() async {
      final plan = await (db.select(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).getSingleOrNull();
      if (plan == null) {
        return const LocalMaintenanceCompletionResult(
          status: LocalMaintenanceCompletionStatus.planUnavailable,
        );
      }
      if (plan.archivedAt != null || !plan.isEnabled) {
        return const LocalMaintenanceCompletionResult(
          status: LocalMaintenanceCompletionStatus.planInactive,
        );
      }
      final canonicalExpectedNextDue = expectedNextDueDate != null
          ? canonicalSyncSecond(expectedNextDueDate)
          : null;
      final canonicalPlanNextDue = canonicalSyncSecond(plan.nextDueDate);

      if (canonicalExpectedNextDue != null &&
          !canonicalPlanNextDue.isAtSameMomentAs(canonicalExpectedNextDue)) {
        return const LocalMaintenanceCompletionResult(
          status: LocalMaintenanceCompletionStatus.occurrenceChanged,
        );
      }

      final completed = canonicalSyncSecond(completedAt ?? _now());
      final previousDueDate = canonicalPlanNextDue;
      final baseDate = completed.isAfter(previousDueDate)
          ? completed
          : previousDueDate;
      final nextDue = canonicalSyncSecond(
        _recurrenceEngine.nextDueDate(
          baseDate,
          domain.RecurrenceRule(
            interval: plan.recurrenceInterval,
            unit: _recurrenceUnit(plan.recurrenceUnit),
          ),
        ),
      );
      final completionId = _uuid.v7();
      final completionNotes = _blankToNull(notes);
      final planUpdatedAt = canonicalSyncSecond(_now());

      // Identify unresolved predecessor for same plan for CT-003 causal ordering
      final pendingCompletions =
          await (db.select(db.syncOutbox)
                ..where((row) => row.entity.equals('maintenance_completion'))
                ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
              .get();
      String? predecessorId;
      for (final comp in pendingCompletions) {
        final payloadJson = comp.payloadJson;
        if (payloadJson == null) continue;
        try {
          final decoded = jsonDecode(payloadJson) as Map<String, dynamic>;
          final compPlanId =
              decoded['plan_id'] as String? ??
              (decoded['plan'] as Map<String, dynamic>?)?['id'] as String?;
          if (compPlanId == planId) {
            predecessorId = comp.recordKey;
            break;
          }
        } catch (_) {}
      }

      final planShadow =
          await (db.select(db.syncShadows)..where(
                (row) =>
                    row.entity.equals('maintenance_plan') &
                    row.recordKey.equals(planId),
              ))
              .getSingleOrNull();
      final syncAccount = await (db.select(
        db.syncAccount,
      )..where((row) => row.id.equals(1))).getSingleOrNull();

      await (db.update(db.syncRuntime)..where((row) => row.id.equals(1))).write(
        const SyncRuntimeCompanion(suppressOutbox: Value(true)),
      );
      try {
        await db
            .into(db.maintenanceRecords)
            .insert(
              MaintenanceRecordsCompanion.insert(
                id: completionId,
                planId: planId,
                dueDate: previousDueDate,
                completedAt: Value(completed),
                notes: Value(completionNotes),
              ),
            );

        await (db.update(
          db.maintenancePlans,
        )..where((row) => row.id.equals(planId))).write(
          MaintenancePlansCompanion(
            nextDueDate: Value(nextDue),
            updatedAt: Value(planUpdatedAt),
          ),
        );
      } finally {
        await (db.update(db.syncRuntime)..where((row) => row.id.equals(1)))
            .write(const SyncRuntimeCompanion(suppressOutbox: Value(false)));
      }

      await _markPlanInboxRead(planId);

      // CT-004 & CT-005: Upsert durable notification reconciliation request
      await db
          .into(db.notificationReconciliationRequests)
          .insertOnConflictUpdate(
            NotificationReconciliationRequestsCompanion.insert(
              scopeKey: 'plan:$planId',
              planId: Value(planId),
              reason: 'local_completion',
              createdAt: Value(planUpdatedAt),
              updatedAt: Value(planUpdatedAt),
            ),
          );

      // Payload v2 with depends_on_operation_id for CT-003 causal ordering
      final payload = jsonEncode({
        'version': 2,
        'operation_id': completionId,
        'idempotency_key': completionId,
        'plan_id': planId,
        'depends_on_operation_id': predecessorId,
        'expected_plan_revision': planShadow?.remoteRevision,
        'expected_next_due_date': previousDueDate.toUtc().toIso8601String(),
        'preimage': {
          'plan': {
            'id': plan.id,
            'asset_id': plan.assetId,
            'title': plan.title,
            'instructions': plan.instructions,
            'recurrence_interval': plan.recurrenceInterval,
            'recurrence_unit': plan.recurrenceUnit,
            'priority': plan.priority,
            'next_due_date': previousDueDate.toUtc().toIso8601String(),
            'reminder_days_before': plan.reminderDaysBefore,
            'is_enabled': plan.isEnabled,
            'health_group': plan.healthGroup,
            'created_at': plan.createdAt.toUtc().toIso8601String(),
            'updated_at': plan.updatedAt.toUtc().toIso8601String(),
            'archived_at': plan.archivedAt?.toUtc().toIso8601String(),
          },
        },
        'plan': {
          'id': plan.id,
          'asset_id': plan.assetId,
          'title': plan.title,
          'instructions': plan.instructions,
          'recurrence_interval': plan.recurrenceInterval,
          'recurrence_unit': plan.recurrenceUnit,
          'priority': plan.priority,
          'next_due_date': nextDue.toUtc().toIso8601String(),
          'reminder_days_before': plan.reminderDaysBefore,
          'is_enabled': plan.isEnabled,
          'health_group': plan.healthGroup,
          'created_at': plan.createdAt.toUtc().toIso8601String(),
          'updated_at': planUpdatedAt.toUtc().toIso8601String(),
          'archived_at': plan.archivedAt?.toUtc().toIso8601String(),
        },
        'record': {
          'id': completionId,
          'plan_id': planId,
          'due_date': previousDueDate.toUtc().toIso8601String(),
          'completed_at': completed.toUtc().toIso8601String(),
          'notes': completionNotes,
        },
      });

      await (db.into(db.syncOutbox)).insert(
        SyncOutboxCompanion.insert(
          entity: 'maintenance_completion',
          recordKey: completionId,
          operation: 'execute',
          changedAt: Value(planUpdatedAt),
          payloadJson: Value(payload),
          userId: Value(syncAccount?.boundUserId),
        ),
      );

      return LocalMaintenanceCompletionResult(
        status: LocalMaintenanceCompletionStatus.applied,
        operationId: completionId,
        previousDueDate: previousDueDate,
        nextDueDate: nextDue,
      );
    });
  }

  @override
  Future<void> undoLastCompletion(
    String planId,
    DateTime previousDueDate,
  ) async {
    final latestRecord =
        await (db.select(db.maintenanceRecords)
              ..where((record) => record.planId.equals(planId))
              ..orderBy([(record) => OrderingTerm.desc(record.completedAt)])
              ..limit(1))
            .getSingleOrNull();
    if (latestRecord == null) {
      return;
    }
    final canonicalPreviousDue = canonicalSyncSecond(previousDueDate);
    final now = canonicalSyncSecond(_now());
    await db.transaction(() async {
      final outboxDeleted =
          await (db.delete(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals('maintenance_completion') &
                    row.recordKey.equals(latestRecord.id),
              ))
              .go();
      if (outboxDeleted > 0) {
        await (db.update(db.syncRuntime)..where((row) => row.id.equals(1)))
            .write(const SyncRuntimeCompanion(suppressOutbox: Value(true)));
        try {
          await (db.delete(
            db.maintenanceRecords,
          )..where((record) => record.id.equals(latestRecord.id))).go();
          await (db.update(
            db.maintenancePlans,
          )..where((plan) => plan.id.equals(planId))).write(
            MaintenancePlansCompanion(
              nextDueDate: Value(canonicalPreviousDue),
              updatedAt: Value(now),
            ),
          );
        } finally {
          await (db.update(db.syncRuntime)..where((row) => row.id.equals(1)))
              .write(const SyncRuntimeCompanion(suppressOutbox: Value(false)));
        }
      } else {
        await (db.delete(
          db.maintenanceRecords,
        )..where((record) => record.id.equals(latestRecord.id))).go();
        await (db.update(
          db.maintenancePlans,
        )..where((plan) => plan.id.equals(planId))).write(
          MaintenancePlansCompanion(
            nextDueDate: Value(canonicalPreviousDue),
            updatedAt: Value(now),
          ),
        );
      }
      await _markPlanInboxRead(planId);

      await db
          .into(db.notificationReconciliationRequests)
          .insertOnConflictUpdate(
            NotificationReconciliationRequestsCompanion.insert(
              scopeKey: 'plan:$planId',
              planId: Value(planId),
              reason: 'undo_completion',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    });
  }

  @override
  Future<void> archivePlan(String planId) async {
    await (db.update(
      db.maintenancePlans,
    )..where((plan) => plan.id.equals(planId))).write(
      MaintenancePlansCompanion(
        archivedAt: Value(_now()),
        updatedAt: Value(_now()),
      ),
    );
  }

  @override
  Future<void> restorePlan(String planId) async {
    final now = _now();
    final plan = await (db.select(
      db.maintenancePlans,
    )..where((row) => row.id.equals(planId))).getSingleOrNull();
    if (plan == null) return;
    final asset = await (db.select(
      db.assets,
    )..where((row) => row.id.equals(plan.assetId))).getSingleOrNull();
    final room = asset == null
        ? null
        : await (db.select(
            db.rooms,
          )..where((row) => row.id.equals(asset.roomId))).getSingleOrNull();
    await db.transaction(() async {
      if (asset != null) {
        await (db.update(
          db.assets,
        )..where((row) => row.id.equals(asset.id))).write(
          AssetsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
      }
      if (room != null) {
        await (db.update(
          db.rooms,
        )..where((row) => row.id.equals(room.id))).write(
          RoomsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
        await (db.update(
          db.areas,
        )..where((row) => row.id.equals(room.areaId))).write(
          AreasCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
      }
      await (db.update(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).write(
        MaintenancePlansCompanion(
          archivedAt: const Value(null),
          updatedAt: Value(now),
        ),
      );
    });
  }

  @override
  Future<void> setTaskEnabled(String planId, bool enabled) async {
    await db.transaction(() async {
      final plan =
          await (db.select(db.maintenancePlans)..where(
                (row) => row.id.equals(planId) & row.archivedAt.isNull(),
              ))
              .getSingleOrNull();
      if (plan == null || plan.isEnabled == enabled) {
        return;
      }
      final now = _now();
      final recurrence = domain.RecurrenceRule(
        interval: plan.recurrenceInterval,
        unit: _recurrenceUnit(plan.recurrenceUnit),
      );
      final nextDueDate = enabled && !plan.nextDueDate.isAfter(now)
          ? _recurrenceEngine.nextDueDate(now, recurrence)
          : plan.nextDueDate;
      await (db.update(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).write(
        MaintenancePlansCompanion(
          isEnabled: Value(enabled),
          nextDueDate: Value(nextDueDate),
          updatedAt: Value(now),
        ),
      );
      if (!enabled) {
        await _markPlanInboxRead(planId);
      }
    });
  }

  @override
  Future<void> skipPlanOccurrence(
    String planId, {
    DateTime? skippedAt,
    String? reason,
  }) async {
    await db.transaction(() async {
      final plan =
          await (db.select(db.maintenancePlans)..where(
                (row) =>
                    row.id.equals(planId) &
                    row.archivedAt.isNull() &
                    row.isEnabled.equals(true),
              ))
              .getSingleOrNull();
      if (plan == null) return;
      final nextDue = _recurrenceEngine.nextDueDate(
        plan.nextDueDate,
        domain.RecurrenceRule(
          interval: plan.recurrenceInterval,
          unit: _recurrenceUnit(plan.recurrenceUnit),
        ),
      );
      await (db.update(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).write(
        MaintenancePlansCompanion(
          nextDueDate: Value(nextDue),
          updatedAt: Value(_now()),
        ),
      );
      await _markPlanInboxRead(planId);
      final normalizedReason = _blankToNull(reason);
      await _recordTaskSystemNote(
        planId: planId,
        title: 'Task skipped',
        body: normalizedReason == null
            ? '${plan.title} was skipped for this occurrence.'
            : '${plan.title} was skipped: $normalizedReason',
        dedupeKey:
            'skip:$planId:${(skippedAt ?? _now()).millisecondsSinceEpoch}',
        messageCode: domain.NotificationMessageCode.taskSkipped,
        messageArgs: {'task': plan.title, 'reason': ?normalizedReason},
      );
    });
  }

  @override
  Future<void> postponePlan(
    String planId,
    DateTime nextDueDate, {
    String? reason,
  }) async {
    await db.transaction(() async {
      final plan =
          await (db.select(db.maintenancePlans)..where(
                (row) =>
                    row.id.equals(planId) &
                    row.archivedAt.isNull() &
                    row.isEnabled.equals(true),
              ))
              .getSingleOrNull();
      if (plan == null) return;
      await (db.update(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).write(
        MaintenancePlansCompanion(
          nextDueDate: Value(nextDueDate),
          updatedAt: Value(_now()),
        ),
      );
      await _markPlanInboxRead(planId);
      final normalizedReason = _blankToNull(reason);
      await _recordTaskSystemNote(
        planId: planId,
        title: 'Task postponed',
        body: normalizedReason == null
            ? '${plan.title} was postponed to ${nextDueDate.toLocal()}.'
            : '${plan.title} was postponed: $normalizedReason',
        dedupeKey:
            'postpone:$planId:${nextDueDate.toUtc().millisecondsSinceEpoch}',
        messageCode: domain.NotificationMessageCode.taskPostponed,
        messageArgs: {
          'task': plan.title,
          'date': nextDueDate.toUtc().toIso8601String(),
          'reason': ?normalizedReason,
        },
      );
    });
  }

  @override
  Future<void> deletePlan(String planId) async {
    await db.transaction(() async {
      await _deletePlansCascade(db, [planId]);
    });
  }

  @override
  Stream<List<domain.MaintenanceRecord>> watchRecordsForPlan(String planId) {
    return (db.select(db.maintenanceRecords)
          ..where((record) => record.planId.equals(planId))
          ..orderBy([(record) => OrderingTerm.desc(record.completedAt)]))
        .watch()
        .map((rows) => rows.map(_recordFromRow).toList())
        .distinctByFingerprint(maintenanceRecordListFingerprint);
  }

  @override
  Future<List<domain.MaintenanceRecord>> listRecordsForPlan(
    String planId,
  ) async {
    final rows =
        await (db.select(db.maintenanceRecords)
              ..where((record) => record.planId.equals(planId))
              ..orderBy([(record) => OrderingTerm.desc(record.completedAt)]))
            .get();
    return rows.map(_recordFromRow).toList();
  }

  @override
  Stream<List<domain.MaintenanceRecord>> watchRecordsForAsset(String assetId) {
    return watchReloaded(
      triggers: [
        db.select(db.maintenancePlans).watch(),
        db.select(db.maintenanceRecords).watch(),
      ],
      load: () => listRecordsForAsset(assetId),
      fingerprint: maintenanceRecordListFingerprint,
    );
  }

  @override
  Future<List<domain.MaintenanceRecord>> listRecordsForAsset(
    String assetId,
  ) async {
    final plans = await (db.select(
      db.maintenancePlans,
    )..where((plan) => plan.assetId.equals(assetId))).get();
    final planIds = plans.map((plan) => plan.id).toList();
    if (planIds.isEmpty) {
      return const [];
    }
    final rows =
        await (db.select(db.maintenanceRecords)
              ..where((record) => record.planId.isIn(planIds))
              ..orderBy([(record) => OrderingTerm.desc(record.completedAt)]))
            .get();
    return rows.map(_recordFromRow).toList();
  }

  Future<void> _markPlanInboxRead(String planId) async {
    await (db.update(db.inboxNotifications)
          ..where((row) => row.planId.equals(planId) & row.readAt.isNull()))
        .write(InboxNotificationsCompanion(readAt: Value(DateTime.now())));
  }

  Future<void> _recordTaskSystemNote({
    required String planId,
    required String title,
    required String body,
    required String dedupeKey,
    required domain.NotificationMessageCode messageCode,
    required Map<String, dynamic> messageArgs,
  }) async {
    final now = _now();
    await db
        .into(db.inboxNotifications)
        .insert(
          InboxNotificationsCompanion.insert(
            id: _uuid.v7(),
            title: title,
            body: body,
            kind: 'task',
            route: Value('/maintenance/$planId'),
            planId: Value(planId),
            dedupeKey: Value(dedupeKey),
            messageCode: Value(messageCode.wireValue),
            messageArgs: Value(jsonEncode(messageArgs)),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<List<domain.TaskItem>> _hydrateTasks(
    List<MaintenancePlanRow> planRows, {
    bool includeArchivedAssets = false,
  }) async {
    if (planRows.isEmpty) {
      return [];
    }
    final assetIds = planRows.map((plan) => plan.assetId).toSet().toList();
    final planIds = planRows.map((plan) => plan.id).toList();
    final assetRows =
        await (db.select(db.assets)..where(
              (asset) =>
                  asset.id.isIn(assetIds) &
                  (includeArchivedAssets
                      ? const Constant(true)
                      : asset.archivedAt.isNull()),
            ))
            .get();
    final metadataRows = await (db.select(
      db.maintenancePlanMetadata,
    )..where((metadata) => metadata.planId.isIn(planIds))).get();
    final metadataMap = {for (final row in metadataRows) row.planId: row};
    final assetMap = {for (final row in assetRows) row.id: row};
    final categoryRows = await db.select(db.categories).get();
    final categoryMap = {for (final row in categoryRows) row.id: row};
    final roomRows = await db.select(db.rooms).get();
    final roomMap = {for (final row in roomRows) row.id: row};
    final now = DateTime.now();
    final items = <domain.TaskItem>[];
    for (final plan in planRows) {
      final asset = assetMap[plan.assetId];
      if (asset == null) {
        continue;
      }
      final category = categoryMap[asset.categoryId];
      final room = roomMap[asset.roomId];
      if (category == null || room == null) {
        continue;
      }
      items.add(
        domain.TaskItem(
          plan: _planFromRow(plan, metadataMap[plan.id]),
          asset: _assetFromRow(asset),
          category: _categoryFromRow(category),
          room: _roomFromRow(room),
          status: _statusFor(plan.nextDueDate, now),
        ),
      );
    }
    items.sort((a, b) => a.plan.nextDueDate.compareTo(b.plan.nextDueDate));
    return items;
  }

  Stream<T> _watchTaskDependencies<T>(
    Future<T> Function() loader, {
    int Function(T value)? fingerprint,
  }) {
    return watchReloaded(
      triggers: [
        db.select(db.maintenancePlans).watch(),
        db.select(db.maintenancePlanMetadata).watch(),
        db.select(db.assets).watch(),
        db.select(db.categories).watch(),
        db.select(db.rooms).watch(),
      ],
      load: loader,
      fingerprint:
          fingerprint ??
          (value) => taskListFingerprint(value as List<domain.TaskItem>),
    );
  }
}
