from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text and old not in text:
        return
    if old not in text:
        raise SystemExit(f"expected snippet not found in {path}: {old[:160]!r}")
    file.write_text(text.replace(old, new, 1))


replace_once(
    "lib/src/core/domain/contracts.dart",
    """  Future<void> undoLastCompletion(String planId, DateTime previousDueDate);
""",
    """  Future<void> undoCompletion({
    required String planId,
    required String completionId,
    required DateTime previousDueDate,
    required DateTime expectedCurrentNextDueDate,
  });
""",
)

old_undo = """  @override
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
"""
new_undo = """  @override
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
          canonicalSyncSecond(plan.nextDueDate).isAtSameMomentAs(
            canonicalExpectedCurrent,
          );

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
        'completion_completed_at': canonicalSyncSecond(
          target.completedAt,
        ).toUtc().toIso8601String(),
        'previous_due_date': canonicalPreviousDue.toUtc().toIso8601String(),
        'expected_current_next_due_date': canonicalExpectedCurrent
            .toUtc()
            .toIso8601String(),
      });
      await db.into(db.syncOutbox).insertOnConflictUpdate(
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
  }
"""
replace_once("lib/src/core/data/maintenance_repository.dart", old_undo, new_undo)

replace_once(
    "lib/src/core/data/maintenance_repository.dart",
    """  Future<void> _markPlanInboxRead(String planId) async {
    await (db.update(db.inboxNotifications)
          ..where((row) => row.planId.equals(planId) & row.readAt.isNull()))
        .write(InboxNotificationsCompanion(readAt: Value(DateTime.now())));
  }
""",
    """  Future<void> _markPlanInboxRead(String planId) async {
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
""",
)

replace_once(
    "lib/src/features/backup/presentation/backup_screen.dart",
    """        await ref
            .read(maintenanceRepositoryProvider)
            .undoLastCompletion(task.plan.id, previousDueDate);
""",
    """        final completionId = result.operationId;
        final completedNextDue = result.nextDueDate;
        if (completionId == null || completedNextDue == null) {
          throw StateError('Completion acknowledgement is missing undo identity.');
        }
        await ref.read(maintenanceRepositoryProvider).undoCompletion(
          planId: task.plan.id,
          completionId: completionId,
          previousDueDate: result.previousDueDate ?? previousDueDate,
          expectedCurrentNextDueDate: completedNextDue,
        );
""",
)

replace_once(
    "lib/src/core/sync/supabase_sync_gateway.dart",
    """class MaintenanceCompletionResult {
""",
    """class MaintenanceUndoResult {
  const MaintenanceUndoResult({
    required this.status,
    required this.retryable,
    this.plan,
    this.rewound = false,
    this.conflictReason,
  });

  final MaintenanceCompletionStatus status;
  final bool retryable;
  final SyncRecord? plan;
  final bool rewound;
  final String? conflictReason;

  bool get acknowledged =>
      status == MaintenanceCompletionStatus.applied ||
      status == MaintenanceCompletionStatus.alreadyApplied;
}

class MaintenanceCompletionResult {
""",
)

complete_method_end = """  Future<SyncRecord?> fetch({
"""
undo_method = """  Future<MaintenanceUndoResult> undoMaintenanceCompletion({
    required String payloadJson,
    required String userId,
    required String deviceId,
  }) async {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) {
        throw const FormatException(
          'The queued maintenance undo payload is invalid.',
        );
      }
      final operation = Map<String, dynamic>.from(decoded);
      final Object? response = await _withDataTimeout<Object?>(
        () async => _client.rpc<Map<String, dynamic>>(
          'undo_maintenance_completion',
          params: {'p_operation': operation, 'p_device_id': deviceId},
        ),
      );
      if (response is! Map) {
        throw const FormatException(
          'The maintenance undo RPC returned an invalid result.',
        );
      }
      final body = Map<String, dynamic>.from(response);
      final status = _maintenanceCompletionStatus(body['status']);
      final rawPlan = body['plan'];
      final planData = rawPlan is Map
          ? Map<String, dynamic>.from(rawPlan)
          : null;
      if (planData != null && planData['user_id'] != userId) {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.permissionDenied,
          message: 'The cloud returned maintenance data for another account.',
        );
      }
      if ((status == MaintenanceCompletionStatus.applied ||
              status == MaintenanceCompletionStatus.alreadyApplied) &&
          planData == null) {
        throw const FormatException(
          'The maintenance undo RPC omitted the canonical plan.',
        );
      }
      return MaintenanceUndoResult(
        status: status,
        retryable: body['retryable'] == true,
        plan: planData == null
            ? null
            : SyncRecord.fromRemote(
                syncSpecByEntity['maintenance_plan']!,
                planData,
              ),
        rewound: body['rewound'] == true,
        conflictReason: body['conflict_reason'] as String?,
      );
    } on Object catch (error) {
      throw SupabaseFailure.from(error);
    }
  }

""" + complete_method_end
replace_once(
    "lib/src/core/sync/supabase_sync_gateway.dart",
    complete_method_end,
    undo_method,
)

replace_once(
    "lib/src/core/sync/local_sync_store.dart",
    """    if (maintenancePlanOrder != null) {
      dependencyOrder['maintenance_completion'] = maintenancePlanOrder;
    }
""",
    """    if (maintenancePlanOrder != null) {
      dependencyOrder['maintenance_completion'] = maintenancePlanOrder;
      dependencyOrder['maintenance_undo'] = maintenancePlanOrder;
    }
""",
)

replace_once(
    "lib/src/core/sync/local_sync_store.dart",
    """      if (a.entity == b.entity) return 0;
      if (a.entity == 'maintenance_completion') return -1;
      if (b.entity == 'maintenance_completion') return 1;
""",
    """      if (a.entity == b.entity) return 0;
      if (a.entity == 'maintenance_undo') return -1;
      if (b.entity == 'maintenance_undo') return 1;
      if (a.entity == 'maintenance_completion') return -1;
      if (b.entity == 'maintenance_completion') return 1;
""",
)

replace_once(
    "lib/src/core/sync/local_sync_store.dart",
    """  Future<void> markMaintenanceCompletionSucceeded(
""",
    """  Future<void> markMaintenanceUndoSucceeded(
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
        await (db.delete(db.maintenanceRecords)..where(
              (row) => row.id.equals(completionId),
            ))
            .go();
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
""",
)

special_marker = """        if (mutation.operation == 'upsert') {
"""
special_branch = """        if (mutation.entity == 'maintenance_undo') {
          final payloadJson = mutation.payloadJson;
          if (mutation.operation != 'execute' ||
              payloadJson == null ||
              payloadJson.trim().isEmpty) {
            const failure = SupabaseFailure(
              kind: SupabaseFailureKind.incompatibleSchema,
              message:
                  'A queued maintenance undo has an invalid payload. '
                  'Update Owntend before synchronizing again.',
            );
            await _recordMutationFailure(mutation, failure);
            throw failure;
          }
          try {
            await _pushMaintenanceUndo(
              mutation,
              payloadJson: payloadJson,
              userId: userId,
              deviceId: deviceId,
              scope: scope,
            );
            if (trackHydration) {
              await _localStore.addHydrationUnits(1);
            }
            // The undo acknowledgement removes any generic plan/delete guard
            // rows that were already present in this in-memory batch. Re-read
            // the outbox on the next sync pass rather than pushing stale rows.
            return true;
          } on _AccountScopeInactive {
            rethrow;
          } on Object catch (error) {
            final failure = SupabaseFailure.from(error);
            await _recordMutationFailure(mutation, failure);
            rethrow;
          }
        }

""" + special_marker
replace_once("lib/src/core/sync/sync_coordinator.dart", special_marker, special_branch)

push_marker = """  Future<void> _pushMaintenanceCompletion(
"""
push_undo = """  Future<void> _pushMaintenanceUndo(
    LocalSyncMutation mutation, {
    required String payloadJson,
    required String userId,
    required String deviceId,
    required _ActiveAccountScope scope,
  }) async {
    await _localStore.markMutationInFlight(mutation, userId: userId);
    final result = await _remoteGateway.undoMaintenanceCompletion(
      payloadJson: payloadJson,
      userId: userId,
      deviceId: deviceId,
    );
    await _ensureActiveAccountScope(scope);
    if (result.acknowledged && result.plan != null) {
      await _localStore.markMaintenanceUndoSucceeded(
        mutation,
        plan: result.plan!,
        completionId: mutation.recordKey,
      );
      await _reconcileMaintenanceCompletionReminders(mutation);
      return;
    }
    throw SupabaseFailure(
      kind: result.status == MaintenanceCompletionStatus.unauthorized
          ? SupabaseFailureKind.permissionDenied
          : result.status == MaintenanceCompletionStatus.invalid
          ? SupabaseFailureKind.incompatibleSchema
          : SupabaseFailureKind.conflict,
      message:
          result.conflictReason ?? 'The completion undo could not be reconciled.',
      retryable: result.retryable,
    );
  }

""" + push_marker
replace_once("lib/src/core/sync/sync_coordinator.dart", push_marker, push_undo)

migration = Path(
    "supabase/migrations/20260816163000_preproduction_completion_integrity.sql"
)
text = migration.read_text()
if "CREATE OR REPLACE FUNCTION public.undo_maintenance_completion" not in text:
    rpc = r'''

CREATE OR REPLACE FUNCTION public.undo_maintenance_completion(
  p_operation JSONB,
  p_device_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  request_user UUID := auth.uid();
  operation_id_value TEXT;
  plan_id_value TEXT;
  completion_id_value TEXT;
  target_completed_at TIMESTAMPTZ;
  previous_due_date_value TIMESTAMPTZ;
  expected_current_due TIMESTAMPTZ;
  current_plan public.maintenance_plans%ROWTYPE;
  target_record public.maintenance_records%ROWTYPE;
  latest_record public.maintenance_records%ROWTYPE;
  has_newer BOOLEAN := false;
  rewound_value BOOLEAN := false;
  target_existed BOOLEAN := false;
BEGIN
  IF request_user IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'unauthorized',
      'retryable', false,
      'conflict_reason', 'authentication_required'
    );
  END IF;
  IF p_operation IS NULL
     OR jsonb_typeof(p_operation) <> 'object'
     OR COALESCE((p_operation ->> 'version')::integer, 0) <> 1
     OR NULLIF(TRIM(COALESCE(p_device_id, '')), '') IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'invalid_payload'
    );
  END IF;

  operation_id_value := NULLIF(TRIM(p_operation ->> 'operation_id'), '');
  plan_id_value := NULLIF(TRIM(p_operation ->> 'plan_id'), '');
  completion_id_value := NULLIF(TRIM(p_operation ->> 'completion_id'), '');
  BEGIN
    target_completed_at := date_trunc(
      'second',
      NULLIF(TRIM(p_operation ->> 'completion_completed_at'), '')::timestamptz
    );
    previous_due_date_value := date_trunc(
      'second',
      NULLIF(TRIM(p_operation ->> 'previous_due_date'), '')::timestamptz
    );
    expected_current_due := date_trunc(
      'second',
      NULLIF(TRIM(p_operation ->> 'expected_current_next_due_date'), '')::timestamptz
    );
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'invalid_timestamp'
    );
  END;
  IF operation_id_value IS NULL
     OR plan_id_value IS NULL
     OR completion_id_value IS NULL
     OR target_completed_at IS NULL
     OR previous_due_date_value IS NULL
     OR expected_current_due IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'missing_fields'
    );
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(request_user::text || ':maintenance:' || plan_id_value, 0)
  );

  SELECT * INTO current_plan
  FROM public.maintenance_plans
  WHERE user_id = request_user
    AND id = plan_id_value
  FOR UPDATE;
  IF current_plan.id IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'plan_missing'
    );
  END IF;

  SELECT * INTO target_record
  FROM public.maintenance_records
  WHERE user_id = request_user
    AND id = completion_id_value
    AND plan_id = plan_id_value
  FOR UPDATE;
  target_existed := target_record.id IS NOT NULL;
  IF target_existed THEN
    DELETE FROM public.maintenance_records
    WHERE user_id = request_user
      AND id = completion_id_value;
  END IF;

  SELECT * INTO latest_record
  FROM public.maintenance_records
  WHERE user_id = request_user
    AND plan_id = plan_id_value
  ORDER BY completed_at DESC, id DESC
  LIMIT 1;

  has_newer := latest_record.id IS NOT NULL AND (
    latest_record.completed_at > target_completed_at OR
    (
      latest_record.completed_at = target_completed_at AND
      latest_record.id > completion_id_value
    )
  );

  IF NOT has_newer
     AND current_plan.next_due_date IS NOT DISTINCT FROM expected_current_due THEN
    UPDATE public.maintenance_plans
    SET next_due_date = previous_due_date_value,
        updated_at = date_trunc('second', clock_timestamp()),
        revision = current_plan.revision + 1
    WHERE user_id = request_user
      AND id = plan_id_value
    RETURNING * INTO current_plan;
    rewound_value := true;
  END IF;

  UPDATE public.notification_inbox
  SET read_at = NULL,
      updated_at = clock_timestamp()
  WHERE user_id = request_user
    AND id = (
      SELECT id
      FROM public.notification_inbox
      WHERE user_id = request_user
        AND plan_id = plan_id_value
        AND kind = 'task'
      ORDER BY created_at DESC, id DESC
      LIMIT 1
    );

  RETURN jsonb_build_object(
    'status', CASE
      WHEN target_existed OR rewound_value THEN 'applied'
      ELSE 'already_applied'
    END,
    'retryable', false,
    'conflict_reason', null,
    'rewound', rewound_value,
    'plan', to_jsonb(current_plan)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.undo_maintenance_completion(JSONB, TEXT)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.undo_maintenance_completion(JSONB, TEXT)
  TO authenticated;
'''
    text = text.replace("\nCOMMIT;", rpc + "\n\nCOMMIT;", 1)
    migration.write_text(text)
