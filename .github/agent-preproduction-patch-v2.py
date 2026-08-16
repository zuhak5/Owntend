from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text and old not in text:
        return
    if old not in text:
        raise SystemExit(f"expected snippet not found in {path}: {old[:140]!r}")
    file.write_text(text.replace(old, new, 1))


replace_once(
    "lib/src/core/domain/contracts.dart",
    """    this.nextDueDate,
  });

  final LocalMaintenanceCompletionStatus status;
  final String? operationId;
  final DateTime? previousDueDate;
  final DateTime? nextDueDate;

  bool get isApplied => status == LocalMaintenanceCompletionStatus.applied;
""",
    """    this.nextDueDate,
    this.duplicateIgnored = false,
  });

  final LocalMaintenanceCompletionStatus status;
  final String? operationId;
  final DateTime? previousDueDate;
  final DateTime? nextDueDate;
  final bool duplicateIgnored;

  bool get isApplied => status == LocalMaintenanceCompletionStatus.applied;
""",
)

replace_once(
    "lib/src/core/data/maintenance_repository.dart",
    """  final DateTime Function() _now;

  @override
""",
    """  final DateTime Function() _now;
  static const _completionDuplicateWindow = Duration(seconds: 4);

  @override
""",
)

replace_once(
    "lib/src/core/data/maintenance_repository.dart",
    """      final completed = canonicalSyncSecond(completedAt ?? _now());
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
""",
    """      final completionInstant = completedAt ?? _now();
      final completed = canonicalSyncSecond(completionInstant);
      final previousDueDate = canonicalPlanNextDue;

      final latestRecord =
          await (db.select(db.maintenanceRecords)
                ..where((record) => record.planId.equals(planId))
                ..orderBy([
                  (record) => OrderingTerm.desc(record.completedAt),
                  (record) => OrderingTerm.desc(record.id),
                ])
                ..limit(1))
              .getSingleOrNull();
      if (latestRecord != null) {
        final sinceLatest = completed.difference(
          canonicalSyncSecond(latestRecord.completedAt),
        );
        if (sinceLatest.compareTo(Duration.zero) >= 0 &&
            sinceLatest.compareTo(_completionDuplicateWindow) < 0) {
          return LocalMaintenanceCompletionResult(
            status: LocalMaintenanceCompletionStatus.applied,
            operationId: latestRecord.id,
            previousDueDate: canonicalSyncSecond(latestRecord.dueDate),
            nextDueDate: canonicalPlanNextDue,
            duplicateIgnored: true,
          );
        }
      }

      final nextDue = canonicalSyncSecond(
        _recurrenceEngine.nextDueDate(
          completionInstant,
          domain.RecurrenceRule(
            interval: plan.recurrenceInterval,
            unit: _recurrenceUnit(plan.recurrenceUnit),
          ),
        ),
      );
""",
)

replace_once(
    "lib/src/core/data/maintenance_repository.dart",
    """      final recurrence = domain.RecurrenceRule(
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
""",
    """      await (db.update(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).write(
        MaintenancePlansCompanion(
          isEnabled: Value(enabled),
          updatedAt: Value(now),
        ),
      );
""",
)

replace_once(
    "lib/src/features/backup/presentation/backup_screen.dart",
    """  if (!context.mounted) {
    return true;
  }
  hk_ui.showUndoToast(
""",
    """  if (result.duplicateIgnored) {
    return true;
  }
  if (!context.mounted) {
    return true;
  }
  hk_ui.showUndoToast(
""",
)

replace_once(
    "lib/src/features/monetization/monetization.dart",
    """    } on Object catch (error) {
      AppLogger.warning('offline_creation_draft_save', error: error);
    }
""",
    """    } on Object catch (error) {
      AppLogger.warning('offline_creation_draft_save', error: error);
      rethrow;
    }
""",
)

replace_once(
    "lib/src/features/monetization/charged_operation_resolver.dart",
    """          final status = await monetizationRepo.getChargedOperationStatus(
            op.operationId,
            requestHash: op.requestHash,
          );
          if (status.status == 'completed') {
""",
    """          final status = await monetizationRepo.getChargedOperationStatus(
            op.operationId,
          );
          if (status.status == 'completed') {
            final expectsTask = op.requestPayload.containsKey('plan');
            final expectedType = expectsTask ? 'task' : 'asset';
            if (status.entityType != expectedType || status.entityId != op.planId) {
              await operationStore.saveOperation(
                op.copyWith(
                  state: TaskCreationOperationState.permanentRejected,
                  updatedAt: DateTime.now(),
                  lastErrorCode: 'operation_identity_mismatch',
                  lastErrorMessage:
                      'Recovered operation identity did not match the local request.',
                ),
              );
              continue;
            }
""",
)

replace_once(
    "lib/src/core/sync/sync_coordinator.dart",
    """    final remote = result.canonical;
    if (remote != null && _hasClockSkew(local, remote)) {
      _clockSkewConflicts++;
    }
    if (remote != null &&
        ((shadow == null && await _localStore.isUntouchedSeed(local)) ||
            _sameRecordData(local, remote))) {
""",
    """    final remote = result.canonical;
    final hasClockSkew = remote != null && _hasClockSkew(local, remote);
    if (hasClockSkew) {
      _clockSkewConflicts++;
    }
    if (remote != null &&
        ((shadow == null && await _localStore.isUntouchedSeed(local)) ||
            _sameRecordData(local, remote))) {
""",
)

replace_once(
    "lib/src/core/sync/sync_coordinator.dart",
    """    } else if (local.clientModifiedAt.isAfter(remote.clientModifiedAt) ||
""",
    """    } else if (hasClockSkew) {
      await _localStore.applyRemoteRecords([remote]);
      await _localStore.markMutationSucceeded(mutation, remote);
      return;
    } else if (local.clientModifiedAt.isAfter(remote.clientModifiedAt) ||
""",
)

migration_path = Path(
    "supabase/migrations/20260816163000_preproduction_completion_integrity.sql"
)
if not migration_path.exists():
    source = Path(
        "supabase/migrations/20260815000004_task_completion_and_rpc.sql"
    ).read_text()
    start = source.index("CREATE OR REPLACE FUNCTION public.complete_maintenance_task(")
    revoke = source.index(
        "REVOKE ALL ON FUNCTION public.complete_maintenance_task", start
    )
    function_sql = source[start:revoke].rstrip()
    clamp = """  IF record_completed_at IS NOT NULL AND record_completed_at > date_trunc('second', clock_timestamp()) THEN
    record_completed_at := date_trunc('second', clock_timestamp());
  END IF;

"""
    if clamp not in function_sql:
        raise SystemExit("completion timestamp clamp not found")
    function_sql = function_sql.replace(clamp, "", 1)
    old_check = "      OR plan_next_due_date <= record_due_date\n"
    if old_check not in function_sql:
        raise SystemExit("completion next-due validation not found")
    function_sql = function_sql.replace(
        old_check,
        "      OR plan_next_due_date <= record_completed_at\n",
        1,
    )
    migration_path.write_text(
        """-- Forward fixes for pre-production maintenance completion integrity.
BEGIN;

ALTER TABLE public.maintenance_plans
  DROP CONSTRAINT IF EXISTS maintenance_plans_interval_unit_check;
ALTER TABLE public.maintenance_plans
  ADD CONSTRAINT maintenance_plans_interval_unit_check
  CHECK (interval_unit IN ('hours', 'days', 'weeks', 'months', 'years'));

"""
        + function_sql
        + """

REVOKE ALL ON FUNCTION public.complete_maintenance_task(JSONB, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.complete_maintenance_task(JSONB, TEXT)
  TO authenticated;

COMMIT;
"""
    )

test_path = Path("test/recurring_completion_precision_test.dart")
text = test_path.read_text()
addition = r'''

  test('early completion resets recurrence from actual completion time', () async {
    await assetRepo.saveArea(
      id: 'area_early',
      name: 'Early',
      kind: AreaKind.indoor,
      sortOrder: 0,
    );
    final roomId = await assetRepo.saveRoom(
      areaId: 'area_early',
      name: 'Early',
    );
    final categoryId = (await assetRepo.listCategories()).first.id;
    final assetId = await assetRepo.saveAsset(
      name: 'Monthly filter',
      assetType: AssetType.device,
      categoryId: categoryId,
      roomId: roomId,
    );
    final due = DateTime(2026, 8, 18, 9);
    final planId = await maintenance.savePlan(
      assetId: assetId,
      title: 'Monthly filter',
      recurrence: const RecurrenceRule(
        interval: 1,
        unit: RecurrenceUnit.months,
      ),
      priority: PriorityLevel.medium,
      nextDueDate: due,
      healthGroup: HealthGroup.appliances,
    );
    final completedAt = DateTime(2026, 8, 13, 14, 30);
    final result = await maintenance.completePlanResult(
      planId,
      completedAt: completedAt,
      expectedNextDueDate: due,
    );
    expect(result.isApplied, isTrue);
    expect(result.duplicateIgnored, isFalse);
    expect(
      (await maintenance.getTask(planId))!.plan.nextDueDate.toLocal(),
      DateTime(2026, 9, 13, 14, 30),
    );
    final record = (await maintenance.listRecordsForPlan(planId)).single;
    expect(record.completedAt.toLocal(), DateTime(2026, 8, 13, 14, 30));
    expect(record.dueDate.toLocal(), due);
  });

  test(
    'rapid repeated completions are idempotent but a later completion is allowed',
    () async {
      await assetRepo.saveArea(
        id: 'area_repeat',
        name: 'Repeat',
        kind: AreaKind.indoor,
        sortOrder: 0,
      );
      final roomId = await assetRepo.saveRoom(
        areaId: 'area_repeat',
        name: 'Repeat',
      );
      final categoryId = (await assetRepo.listCategories()).first.id;
      final assetId = await assetRepo.saveAsset(
        name: 'Rapid task',
        categoryId: categoryId,
        roomId: roomId,
      );
      final due = DateTime(2026, 8, 17, 9);
      final planId = await maintenance.savePlan(
        assetId: assetId,
        title: 'Rapid task',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.days,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: due,
        healthGroup: HealthGroup.other,
      );
      final firstAt = DateTime(2026, 8, 16, 14, 30, 10);
      final first = await maintenance.completePlanResult(
        planId,
        completedAt: firstAt,
        expectedNextDueDate: due,
      );
      expect(first.isApplied, isTrue);
      for (var i = 1; i <= 4; i++) {
        final repeat = await maintenance.completePlanResult(
          planId,
          completedAt: firstAt.add(Duration(milliseconds: 500 * i)),
          expectedNextDueDate: first.nextDueDate,
        );
        expect(repeat.isApplied, isTrue);
        expect(repeat.duplicateIgnored, isTrue);
        expect(repeat.operationId, first.operationId);
      }
      expect(await maintenance.listRecordsForPlan(planId), hasLength(1));
      expect(
        (await maintenance.getTask(planId))!.plan.nextDueDate.toLocal(),
        DateTime(2026, 8, 17, 14, 30, 10),
      );

      final afterWindowAt = firstAt.add(const Duration(seconds: 5));
      final second = await maintenance.completePlanResult(
        planId,
        completedAt: afterWindowAt,
        expectedNextDueDate: first.nextDueDate,
      );
      expect(second.isApplied, isTrue);
      expect(second.duplicateIgnored, isFalse);
      expect(await maintenance.listRecordsForPlan(planId), hasLength(2));
      expect(
        (await maintenance.getTask(planId))!.plan.nextDueDate.toLocal(),
        DateTime(2026, 8, 17, 14, 30, 15),
      );
    },
  );
'''
if "early completion resets recurrence from actual completion time" not in text:
    marker = "\n}\n"
    index = text.rfind(marker)
    if index < 0:
        raise SystemExit("test file closing brace not found")
    test_path.write_text(text[:index] + addition + text[index:])
