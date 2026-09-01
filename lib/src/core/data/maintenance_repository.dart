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
    int reminderDaysBefore = 0,
    domain.TaskMetadata? metadata,
    String? expectedOccurrenceId,
    DateTime? expectedUpdatedAt,
  }) async {
    final cleanAssetId = assetId.trim();
    final cleanTitle = title.trim();
    validateMaintenancePlanInput(
      assetId: cleanAssetId,
      title: cleanTitle,
      instructions: instructions,
      recurrence: recurrence,
      reminderDaysBefore: reminderDaysBefore,
      metadata: metadata,
    );
    await _validatePlanTargetAsset(cleanAssetId);
    if (!_reminderLeadFitsRecurrence(recurrence, reminderDaysBefore)) {
      throw const MaintenancePlanValidationException(
        'Reminder lead time must be shorter than the recurrence interval.',
        code: 'invalid_reminder_cadence',
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
                currentOccurrenceId: Value(_uuid.v7()),
                assetId: cleanAssetId,
                title: cleanTitle,
                instructions: Value(_blankToNull(instructions)),
                recurrenceInterval: recurrence.interval,
                recurrenceUnit: recurrence.unit.name,
                priority: priority.name,
                nextDueDate: nextDueDate,
                reminderDaysBefore: Value(reminderDaysBefore),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        if (metadata != null) {
          await _savePlanMetadata(planId, metadata, now);
        }
      } else {
        final cleanExpectedOccurrenceId = expectedOccurrenceId?.trim();
        if (cleanExpectedOccurrenceId == null ||
            cleanExpectedOccurrenceId.isEmpty ||
            expectedUpdatedAt == null) {
          throw const MaintenancePlanValidationException(
            'Editing an existing task requires its current revision.',
            code: 'missing_edit_precondition',
          );
        }
        final candidateChangedAt = canonicalSyncSecond(now);
        final changedAt = candidateChangedAt.isAfter(existingPlan.updatedAt)
            ? candidateChangedAt
            : existingPlan.updatedAt.add(const Duration(seconds: 1));
        final changed =
            await (db.update(db.maintenancePlans)..where(
                  (plan) =>
                      plan.id.equals(planId) &
                      plan.currentOccurrenceId.equals(
                        cleanExpectedOccurrenceId,
                      ) &
                      plan.updatedAt.equals(expectedUpdatedAt),
                ))
                .write(
                  MaintenancePlansCompanion(
                    assetId: Value(cleanAssetId),
                    title: Value(cleanTitle),
                    instructions: Value(_blankToNull(instructions)),
                    recurrenceInterval: Value(recurrence.interval),
                    recurrenceUnit: Value(recurrence.unit.name),
                    priority: Value(priority.name),
                    nextDueDate: Value(nextDueDate),
                    reminderDaysBefore: Value(reminderDaysBefore),
                    updatedAt: Value(changedAt),
                  ),
                );
        if (changed != 1) {
          throw const MaintenancePlanValidationException(
            'This task changed while it was being edited.',
            code: 'stale_plan_edit',
          );
        }
        if (metadata != null) {
          await _savePlanMetadata(planId, metadata, changedAt);
        } else {
          await (db.delete(
            db.maintenancePlanMetadata,
          )..where((row) => row.planId.equals(planId))).go();
        }
      }
      await _enqueueScheduleReconciliation(planId, now);
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
    required String expectedOccurrenceId,
    String? operationId,
    String timeZoneId = 'UTC',
    DateTime? completedAt,
    String? notes,
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
      final cleanExpectedOccurrenceId = expectedOccurrenceId.trim();
      if (cleanExpectedOccurrenceId.isEmpty) {
        return const LocalMaintenanceCompletionResult(
          status: LocalMaintenanceCompletionStatus.failed,
          errorCode: 'invalid_occurrence_id',
        );
      }
      final canonicalPlanNextDue = canonicalSyncSecond(plan.nextDueDate);
      if (plan.currentOccurrenceId != cleanExpectedOccurrenceId) {
        final existingRecord =
            await (db.select(db.maintenanceRecords)
                  ..where(
                    (row) =>
                        row.planId.equals(planId) &
                        row.occurrenceId.equals(cleanExpectedOccurrenceId),
                  )
                  ..limit(1))
                .getSingleOrNull();
        if (existingRecord == null) {
          return LocalMaintenanceCompletionResult(
            status: LocalMaintenanceCompletionStatus.staleOccurrence,
            nextOccurrenceId: plan.currentOccurrenceId,
            nextDueDate: canonicalPlanNextDue,
          );
        }
        return LocalMaintenanceCompletionResult(
          status: operationId != null && existingRecord.id == operationId
              ? LocalMaintenanceCompletionStatus.alreadyAppliedByThisOperation
              : LocalMaintenanceCompletionStatus.completedElsewhere,
          operationId: existingRecord.id,
          completedOccurrenceId: existingRecord.occurrenceId,
          nextOccurrenceId: plan.currentOccurrenceId,
          previousDueDate: canonicalSyncSecond(existingRecord.dueDate),
          nextDueDate: canonicalPlanNextDue,
        );
      }

      final actionAt = _now();
      final completionInstant = completedAt ?? actionAt;
      final completed = canonicalSyncSecond(completionInstant);
      final previousDueDate = canonicalPlanNextDue;

      final nextDue = canonicalSyncSecond(
        _recurrenceEngine.nextDueDate(
          completionInstant,
          domain.RecurrenceRule(
            interval: plan.recurrenceInterval,
            unit: _recurrenceUnit(plan.recurrenceUnit),
          ),
        ),
      );
      final completionId = operationId?.trim().isNotEmpty == true
          ? operationId!.trim()
          : _uuid.v7();
      final nextOccurrenceId = 'next:$completionId';
      final completionNotes = _blankToNull(notes);
      final planUpdatedAt = canonicalSyncSecond(actionAt);

      final pendingCompletions =
          await (db.select(db.syncOutbox)
                ..where(
                  (row) =>
                      row.entity.equals('maintenance_completion') &
                      row.attempts.isBiggerOrEqualValue(0) &
                      row.state.isNotIn(const ['conflict', 'failedVisible']),
                )
                ..orderBy([(row) => OrderingTerm.desc(row.localSequence)]))
              .get();
      String? predecessorId;
      for (final comp in pendingCompletions) {
        final payloadJson = comp.payloadJson;
        if (payloadJson == null) continue;
        try {
          final decoded = jsonDecode(payloadJson) as Map<String, dynamic>;
          final compPlanId = decoded['plan_id'] as String?;
          if (compPlanId == planId) {
            predecessorId = comp.recordKey;
            break;
          }
        } on Object {
          // WP-006 (F-015): unreadable queue payloads are logged without
          // content; predecessor detection simply skips the row.
          AppLogger.warning(
            'sync_completion_payload_unreadable',
            fields: const {'entity': 'maintenance_completion'},
          );
        }
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
        final changed =
            await (db.update(db.maintenancePlans)..where(
                  (row) =>
                      row.id.equals(planId) &
                      row.currentOccurrenceId.equals(cleanExpectedOccurrenceId),
                ))
                .write(
                  MaintenancePlansCompanion(
                    currentOccurrenceId: Value(nextOccurrenceId),
                    nextDueDate: Value(nextDue),
                    updatedAt: Value(planUpdatedAt),
                  ),
                );
        if (changed != 1) {
          return const LocalMaintenanceCompletionResult(
            status: LocalMaintenanceCompletionStatus.staleOccurrence,
          );
        }
        await db
            .into(db.maintenanceRecords)
            .insert(
              MaintenanceRecordsCompanion.insert(
                id: completionId,
                planId: planId,
                occurrenceId: Value(cleanExpectedOccurrenceId),
                dueDate: previousDueDate,
                completedAt: Value(completed),
                timeZoneId: Value(
                  timeZoneId.trim().isEmpty ? 'UTC' : timeZoneId.trim(),
                ),
                notes: Value(completionNotes),
              ),
            );
      } finally {
        await (db.update(db.syncRuntime)..where((row) => row.id.equals(1)))
            .write(const SyncRuntimeCompanion(suppressOutbox: Value(false)));
      }

      await _markPlanInboxRead(planId);

      await db
          .into(db.notificationReconciliationRequests)
          .insertOnConflictUpdate(
            NotificationReconciliationRequestsCompanion.insert(
              scopeKey: 'plan:$planId',
              planId: Value(planId),
              reason: 'schedule_inputs_changed',
              createdAt: Value(planUpdatedAt),
              updatedAt: Value(planUpdatedAt),
            ),
          );

      final payload = jsonEncode({
        'contract_version': 1,
        'operation_id': completionId,
        'plan_id': planId,
        'occurrence_id': cleanExpectedOccurrenceId,
        'depends_on_operation_id': predecessorId,
        'expected_plan_revision': planShadow?.remoteRevision,
        'completed_at': completed.toUtc().toIso8601String(),
        'time_zone_id': timeZoneId.trim().isEmpty ? 'UTC' : timeZoneId.trim(),
        'notes': completionNotes,
        'local_preimage': {
          'current_occurrence_id': cleanExpectedOccurrenceId,
          'next_due_date': previousDueDate.toUtc().toIso8601String(),
          'updated_at': plan.updatedAt.toUtc().toIso8601String(),
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

      final result = LocalMaintenanceCompletionResult(
        status: LocalMaintenanceCompletionStatus.appliedPendingSync,
        operationId: completionId,
        completedOccurrenceId: cleanExpectedOccurrenceId,
        nextOccurrenceId: nextOccurrenceId,
        previousDueDate: previousDueDate,
        nextDueDate: nextDue,
      );
      return result;
    });
  }

  @override
  Future<void> undoCompletion({
    required String planId,
    required String completionId,
    required String completedOccurrenceId,
    required String expectedCurrentOccurrenceId,
    required DateTime previousDueDate,
    required DateTime expectedCurrentNextDueDate,
  }) async {
    final canonicalPreviousDue = canonicalSyncSecond(previousDueDate);
    final canonicalExpectedCurrent = canonicalSyncSecond(
      expectedCurrentNextDueDate,
    );
    final now = canonicalSyncSecond(_now());

    await db.transaction(() async {
      final target =
          await (db.select(db.maintenanceRecords)..where(
                (record) =>
                    record.id.equals(completionId) &
                    record.planId.equals(planId),
              ))
              .getSingleOrNull();
      if (target == null) {
        return;
      }
      final plan = await (db.select(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).getSingleOrNull();
      if (plan == null) {
        return;
      }
      final latest =
          await (db.select(db.maintenanceRecords)
                ..where((record) => record.planId.equals(planId))
                ..orderBy([
                  (record) => OrderingTerm.desc(record.completedAt),
                  (record) => OrderingTerm.desc(record.id),
                ])
                ..limit(1))
              .getSingleOrNull();
      final shouldRewind =
          latest?.id == completionId &&
          target.occurrenceId == completedOccurrenceId &&
          plan.currentOccurrenceId == expectedCurrentOccurrenceId &&
          canonicalSyncSecond(plan.nextDueDate)
              .isAtSameMomentAs(canonicalExpectedCurrent);

      await (db.delete(db.syncOutbox)..where(
            (row) =>
                row.entity.equals('maintenance_completion') &
                row.recordKey.equals(completionId),
          ))
          .go();

      // Keep ordinary outbox triggers enabled here. If the completion RPC is
      // already in flight, the exact-record delete protects local history and
      // the plan mutation protects the local rewind until the guarded undo RPC
      // reaches the server.
      await (db.delete(
        db.maintenanceRecords,
      )..where((record) => record.id.equals(completionId))).go();
      if (shouldRewind) {
        await (db.update(
          db.maintenancePlans,
        )..where((row) => row.id.equals(planId))).write(
          MaintenancePlansCompanion(
            currentOccurrenceId: Value(completedOccurrenceId),
            nextDueDate: Value(canonicalPreviousDue),
            updatedAt: Value(now),
          ),
        );
      }

      final syncAccount = await (db.select(
        db.syncAccount,
      )..where((row) => row.id.equals(1))).getSingleOrNull();
      final payload = jsonEncode({
        'contract_version': 1,
        'operation_id': 'undo:$completionId',
        'plan_id': planId,
        'completion_id': completionId,
        'completed_occurrence_id': completedOccurrenceId,
        'expected_current_occurrence_id': expectedCurrentOccurrenceId,
        'previous_due_date': canonicalPreviousDue.toUtc().toIso8601String(),
        'expected_current_next_due_date': canonicalExpectedCurrent
            .toUtc()
            .toIso8601String(),
      });
      await db
          .into(db.syncOutbox)
          .insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              entity: 'maintenance_undo',
              recordKey: completionId,
              operation: 'execute',
              changedAt: Value(now.subtract(const Duration(microseconds: 1))),
              payloadJson: Value(payload),
              userId: Value(syncAccount?.boundUserId),
            ),
          );
      await _reopenPlanInbox(planId, now);
      await db
          .into(db.notificationReconciliationRequests)
          .insertOnConflictUpdate(
            NotificationReconciliationRequestsCompanion.insert(
              scopeKey: 'plan:$planId',
              planId: Value(planId),
              reason: 'schedule_inputs_changed',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    });
  }

  @override
  Future<void> archivePlan(String planId) async {
    final now = _now();
    await db.transaction(() async {
      await (db.update(
        db.maintenancePlans,
      )..where((plan) => plan.id.equals(planId))).write(
        MaintenancePlansCompanion(
          archivedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await _markPlanInboxRead(planId);
      await _enqueueScheduleReconciliation(planId, now);
    });
  }

  @override
  Future<void> restorePlan(String planId) async {
    final now = _now();
    await db.transaction(() async {
      final plan = await (db.select(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).getSingleOrNull();
      if (plan == null || plan.archivedAt == null) return;
      final asset = await (db.select(
        db.assets,
      )..where((row) => row.id.equals(plan.assetId))).getSingleOrNull();
      final room = asset == null
          ? null
          : await (db.select(
              db.rooms,
            )..where((row) => row.id.equals(asset.roomId))).getSingleOrNull();
      final area = room == null
          ? null
          : await (db.select(
              db.areas,
            )..where((row) => row.id.equals(room.areaId))).getSingleOrNull();
      if (asset == null ||
          asset.archivedAt != null ||
          room == null ||
          room.archivedAt != null ||
          area == null ||
          area.archivedAt != null) {
        throw StateError(
          'Restore the parent item, room, and area before restoring this task.',
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
      await _enqueueScheduleReconciliation(planId, now);
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
      await (db.update(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).write(
        MaintenancePlansCompanion(
          isEnabled: Value(enabled),
          updatedAt: Value(now),
        ),
      );
      if (!enabled) {
        await _markPlanInboxRead(planId);
      }
      await _enqueueScheduleReconciliation(planId, now);
    });
  }

  @override
  Future<void> skipPlanOccurrence(
    String planId, {
    required String expectedOccurrenceId,
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
      if (plan.currentOccurrenceId != expectedOccurrenceId) {
        throw const MaintenancePlanValidationException(
          'This task occurrence changed before it could be skipped.',
          code: 'stale_occurrence',
        );
      }
      final nextDue = _recurrenceEngine.nextDueDate(
        plan.nextDueDate,
        domain.RecurrenceRule(
          interval: plan.recurrenceInterval,
          unit: _recurrenceUnit(plan.recurrenceUnit),
        ),
      );
      final now = _now();
      final changed =
          await (db.update(db.maintenancePlans)..where(
                (row) =>
                    row.id.equals(planId) &
                    row.currentOccurrenceId.equals(expectedOccurrenceId),
              ))
              .write(
                MaintenancePlansCompanion(
                  currentOccurrenceId: Value(_uuid.v7()),
                  nextDueDate: Value(nextDue),
                  updatedAt: Value(now),
                ),
              );
      if (changed != 1) {
        throw const MaintenancePlanValidationException(
          'This task occurrence changed before it could be skipped.',
          code: 'stale_occurrence',
        );
      }
      await _markPlanInboxRead(planId);
      final normalizedReason = _blankToNull(reason);
      await _recordTaskSystemNote(
        planId: planId,
        title: 'Task skipped',
        body: normalizedReason == null
            ? '${plan.title} was skipped for this occurrence.'
            : '${plan.title} was skipped: $normalizedReason',
        dedupeKey: 'skip:$planId:$expectedOccurrenceId',
        messageCode: domain.NotificationMessageCode.taskSkipped,
        messageArgs: {'task': plan.title, 'reason': ?normalizedReason},
      );
      await _enqueueScheduleReconciliation(planId, now);
    });
  }

  @override
  Future<void> postponePlan(
    String planId,
    DateTime nextDueDate, {
    required String expectedOccurrenceId,
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
      if (plan.currentOccurrenceId != expectedOccurrenceId) {
        throw const MaintenancePlanValidationException(
          'This task occurrence changed before it could be postponed.',
          code: 'stale_occurrence',
        );
      }
      final now = _now();
      if (!nextDueDate.isAfter(now) || !nextDueDate.isAfter(plan.nextDueDate)) {
        throw const MaintenancePlanValidationException(
          'Postpone must move the task to a later future time.',
          code: 'invalid_postpone',
        );
      }
      final changed =
          await (db.update(db.maintenancePlans)..where(
                (row) =>
                    row.id.equals(planId) &
                    row.currentOccurrenceId.equals(expectedOccurrenceId),
              ))
              .write(
                MaintenancePlansCompanion(
                  nextDueDate: Value(nextDueDate),
                  updatedAt: Value(now),
                ),
              );
      if (changed != 1) {
        throw const MaintenancePlanValidationException(
          'This task occurrence changed before it could be postponed.',
          code: 'stale_occurrence',
        );
      }
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
      await _enqueueScheduleReconciliation(planId, now);
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

  Future<void> _enqueueScheduleReconciliation(
    String planId,
    DateTime changedAt,
  ) {
    return db
        .into(db.notificationReconciliationRequests)
        .insertOnConflictUpdate(
          NotificationReconciliationRequestsCompanion.insert(
            scopeKey: 'plan:$planId',
            planId: Value(planId),
            reason: 'schedule_inputs_changed',
            createdAt: Value(changedAt),
            updatedAt: Value(changedAt),
          ),
        );
  }

  Future<void> _reopenPlanInbox(String planId, DateTime now) async {
    final latest =
        await (db.select(db.inboxNotifications)
              ..where(
                (row) => row.planId.equals(planId) & row.kind.equals('task'),
              )
              ..orderBy([
                (row) => OrderingTerm.desc(row.createdAt),
                (row) => OrderingTerm.desc(row.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (latest == null) return;
    await (db.update(
      db.inboxNotifications,
    )..where((row) => row.id.equals(latest.id))).write(
      InboxNotificationsCompanion(
        readAt: const Value(null),
        updatedAt: Value(now),
      ),
    );
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
    final roomRows = await db.select(db.rooms).get();
    final roomMap = {for (final row in roomRows) row.id: row};
    final now = DateTime.now();
    final items = <domain.TaskItem>[];
    for (final plan in planRows) {
      final asset = assetMap[plan.assetId];
      if (asset == null) {
        continue;
      }
      final room = roomMap[asset.roomId];
      if (room == null) {
        continue;
      }
      items.add(
        domain.TaskItem(
          plan: _planFromRow(plan, metadataMap[plan.id]),
          asset: _assetFromRow(asset),
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
        db.select(db.rooms).watch(),
      ],
      load: loader,
      fingerprint:
          fingerprint ??
          (value) => taskListFingerprint(value as List<domain.TaskItem>),
    );
  }
}

bool _reminderLeadFitsRecurrence(
  domain.RecurrenceRule recurrence,
  int reminderDaysBefore,
) {
  if (reminderDaysBefore == 0) return true;
  final leadHours = reminderDaysBefore * 24;
  final minimumCycleHours = switch (recurrence.unit) {
    domain.RecurrenceUnit.hours => recurrence.interval,
    domain.RecurrenceUnit.days => recurrence.interval * 24,
    domain.RecurrenceUnit.weeks => recurrence.interval * 7 * 24,
    domain.RecurrenceUnit.months => recurrence.interval * 28 * 24,
    domain.RecurrenceUnit.years => recurrence.interval * 365 * 24,
  };
  return leadHours < minimumCycleHours;
}
