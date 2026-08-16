part of 'repositories.dart';

class DriftMaintenanceRepository
    implements MaintenanceRepository, CalendarRepository {
  DriftMaintenanceRepository(
    this.db, {
    this._recurrenceEngine = const OwntendRecurrenceEngine(),
    DateTime Function()? now,
    Duration Function()? actionElapsed,
  }) : _now = now ?? DateTime.now,
       _actionElapsedOverride = actionElapsed;

  final AppDatabase db;
  final RecurrenceEngine _recurrenceEngine;
  final DateTime Function() _now;
  final Duration Function()? _actionElapsedOverride;
  final Stopwatch _completionActionClock = Stopwatch()..start();
  static const _completionDuplicateWindow = Duration(seconds: 4);
  final Map<String, Duration> _lastCompletionActionAt = {};
  final Map<String, LocalMaintenanceCompletionResult> _lastCompletionResult =
      {};

  Duration get _actionElapsed =>
      _actionElapsedOverride?.call() ?? _completionActionClock.elapsed;

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
        } else {
          await (db.delete(
            db.maintenancePlanMetadata,
          )..where((row) => row.planId.equals(planId))).go();
        }
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
    return result.isApplied && !result.duplicateIgnored;
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
      final actionAt = _now();
      final actionElapsed = _actionElapsed;
      final lastActionAt = _lastCompletionActionAt[planId];
      final lastResult = _lastCompletionResult[planId];
      if (lastActionAt != null && lastResult != null) {
        final sinceLastAction = actionElapsed - lastActionAt;
        if (!sinceLastAction.isNegative &&
            sinceLastAction < _completionDuplicateWindow) {
          return LocalMaintenanceCompletionResult(
            status: lastResult.status,
            operationId: lastResult.operationId,
            previousDueDate: lastResult.previousDueDate,
            nextDueDate: lastResult.nextDueDate,
            duplicateIgnored: true,
          );
        }
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
      final completionId = _uuid.v7();
      final completionNotes = _blankToNull(notes);
      final planUpdatedAt = canonicalSyncSecond(actionAt);

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

      final result = LocalMaintenanceCompletionResult(
        status: LocalMaintenanceCompletionStatus.applied,
        operationId: completionId,
        previousDueDate: previousDueDate,
        nextDueDate: nextDue,
      );
      _lastCompletionActionAt[planId] = actionElapsed;
      _lastCompletionResult[planId] = result;
      return result;
    });
  }

  @override
  Future<void> undoCompletion({
    required String planId,
    required String completionId,
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
            nextDueDate: Value(canonicalPreviousDue),
            updatedAt: Value(now),
          ),
        );
      }

      final syncAccount = await (db.select(
        db.syncAccount,
      )..where((row) => row.id.equals(1))).getSingleOrNull();
      final payload = jsonEncode({
        'version': 1,
        'operation_id': 'undo:$completionId',
        'plan_id': planId,
        'completion_id': completionId,
        'completion_completed_at': canonicalSyncSecond(target.completedAt)
            .toUtc()
            .toIso8601String(),
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
              reason: 'undo_completion',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    });
    if (_lastCompletionResult[planId]?.operationId == completionId) {
      _lastCompletionActionAt.remove(planId);
      _lastCompletionResult.remove(planId);
    }
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
      final now = _now();
      if (!nextDueDate.isAfter(now) || !nextDueDate.isAfter(plan.nextDueDate)) {
        throw const MaintenancePlanValidationException(
          'Postpone must move the task to a later future time.',
          code: 'invalid_postpone',
        );
      }
      await (db.update(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).write(
        MaintenancePlansCompanion(
          nextDueDate: Value(nextDueDate),
          updatedAt: Value(now),
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
