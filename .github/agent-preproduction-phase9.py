from pathlib import Path

# 1) Maintenance repository: monotonic duplicate guard, clear it on Undo,
#    refuse child task restore beneath archived ancestors, remove duplicate helper.
path = Path('lib/src/core/data/maintenance_repository.dart')
text = path.read_text()
old_ctor = """  DriftMaintenanceRepository(
    this.db, {
    this._recurrenceEngine = const OwntendRecurrenceEngine(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppDatabase db;
  final RecurrenceEngine _recurrenceEngine;
  final DateTime Function() _now;
  static const _completionDuplicateWindow = Duration(seconds: 4);
  final Map<String, DateTime> _lastCompletionActionAt = {};
  final Map<String, LocalMaintenanceCompletionResult> _lastCompletionResult =
      {};
"""
new_ctor = """  DriftMaintenanceRepository(
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
"""
if old_ctor not in text:
    raise SystemExit('maintenance constructor did not match')
text = text.replace(old_ctor, new_ctor, 1)
text = text.replace('      final actionAt = _now();\n      final lastActionAt = _lastCompletionActionAt[planId];', '      final actionAt = _now();\n      final actionElapsed = _actionElapsed;\n      final lastActionAt = _lastCompletionActionAt[planId];', 1)
text = text.replace('        final sinceLastAction = actionAt.difference(lastActionAt);\n        if (!sinceLastAction.isNegative &&\n            sinceLastAction < _completionDuplicateWindow) {', '        final sinceLastAction = actionElapsed - lastActionAt;\n        if (!sinceLastAction.isNegative &&\n            sinceLastAction < _completionDuplicateWindow) {', 1)
text = text.replace('      _lastCompletionActionAt[planId] = actionAt;\n      _lastCompletionResult[planId] = result;', '      _lastCompletionActionAt[planId] = actionElapsed;\n      _lastCompletionResult[planId] = result;', 1)

old_undo_end = """    await db.transaction(() async {
      final target =
"""
# Keep transaction unchanged, but clear the per-action guard after it commits.
# Find the exact end just before archivePlan.
undo_marker = """      await db
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
"""
undo_replacement = """      await db
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
"""
if undo_marker not in text:
    raise SystemExit('undo end did not match')
text = text.replace(undo_marker, undo_replacement, 1)

old_restore = """  @override
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
"""
new_restore = """  @override
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
"""
if old_restore not in text:
    raise SystemExit('restorePlan block did not match')
text = text.replace(old_restore, new_restore, 1)

# Remove the second duplicate _reopenPlanInbox definition.
helper = """  Future<void> _reopenPlanInbox(String planId, DateTime now) async {
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

"""
if text.count(helper) != 2:
    raise SystemExit(f'expected 2 reopen helpers, found {text.count(helper)}')
first = text.find(helper)
second = text.find(helper, first + len(helper))
text = text[:second] + text[second + len(helper):]
path.write_text(text)

# 2) Streak history: compare calendar days, not elapsed local-midnight hours.
path = Path('lib/src/core/data/streak_service.dart')
text = path.read_text()
old = """      final consecutive =
          previous != null && day.difference(previous).inDays == 1;
"""
new = """      final consecutive =
          previous != null && daysBetweenDates(previous, day) == 1;
"""
if old not in text:
    raise SystemExit('streak consecutive block did not match')
path.write_text(text.replace(old, new, 1))

# 3) Asset repository analyzer style issue.
path = Path('lib/src/core/data/asset_repository.dart')
text = path.read_text()
old = """      if (planIds.isNotEmpty) await _deletePlansCascade(db, planIds);
      if (assetIds.isNotEmpty)
        await _deleteAssetsCascadeInTransaction(assetIds);
"""
new = """      if (planIds.isNotEmpty) {
        await _deletePlansCascade(db, planIds);
      }
      if (assetIds.isNotEmpty) {
        await _deleteAssetsCascadeInTransaction(assetIds);
      }
"""
if old not in text:
    raise SystemExit('asset empty-trash style block did not match')
path.write_text(text.replace(old, new, 1))

# 4) Remove duplicate sync helper definitions (keep first copy).
def remove_second_exact(path_str, block):
    p = Path(path_str)
    s = p.read_text()
    if s.count(block) != 2:
        raise SystemExit(f'{path_str}: expected duplicate block exactly twice, got {s.count(block)}')
    first = s.find(block)
    second = s.find(block, first + len(block))
    p.write_text(s[:second] + s[second + len(block):])

remove_second_exact('lib/src/core/sync/local_sync_store.dart', """  Future<void> markMaintenanceUndoSucceeded(
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

""")

remove_second_exact('lib/src/core/sync/supabase_sync_gateway.dart', """  Future<MaintenanceUndoResult> undoMaintenanceCompletion({
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

""")

remove_second_exact('lib/src/core/sync/sync_coordinator.dart', """  Future<void> _pushMaintenanceUndo(
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
          result.conflictReason ??
          'The completion undo could not be reconciled.',
      retryable: result.retryable,
    );
  }

""")

# 5) Repair accidentally nested repository tests by giving them their own group.
path = Path('test/home_structure_repository_test.dart')
text = path.read_text()
anchor = """    } finally {
      await first?.close();
      await reopened?.close();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }

    test(
      'editing clears optional metadata and does not acknowledge Inbox',
"""
replacement = """    } finally {
      await first?.close();
      await reopened?.close();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });

  group('preproduction state integrity', () {
    late AppDatabase db;
    late DriftAssetRepository repo;

    setUp(() async {
      db = AppDatabase(executor: NativeDatabase.memory());
      repo = DriftAssetRepository(db);
      await _seedTestAreas(repo);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'editing clears optional metadata and does not acknowledge Inbox',
"""
if anchor not in text:
    raise SystemExit('home structure nesting anchor did not match')
path.write_text(text.replace(anchor, replacement, 1))

# 6) Update widget test fakes for new interfaces.
path = Path('test/widget_test.dart')
text = path.read_text()
settings_anchor = """  @override
  Future<void> setNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    notificationSaveCount++;
    notificationPreferencesValue = preferences;
    _notificationPreferencesController.add(preferences);
  }

  Future<void> close() async {
"""
settings_replacement = """  @override
  Future<void> setNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    notificationSaveCount++;
    notificationPreferencesValue = preferences;
    _notificationPreferencesController.add(preferences);
  }

  @override
  Future<void> mergeNotificationPreferences({
    required NotificationPreferences baseline,
    required NotificationPreferences desired,
  }) async {
    await setNotificationPreferences(desired);
  }

  Future<void> close() async {
"""
if settings_anchor not in text:
    raise SystemExit('fake settings anchor did not match')
text = text.replace(settings_anchor, settings_replacement, 1)
old_undo_fake = """  @override
  Future<void> undoLastCompletion(
    String planId,
    DateTime previousDueDate,
  ) async {
    undoCount++;
  }
"""
new_undo_fake = """  @override
  Future<void> undoCompletion({
    required String planId,
    required String completionId,
    required DateTime previousDueDate,
    required DateTime expectedCurrentNextDueDate,
  }) async {
    undoCount++;
  }
"""
if old_undo_fake not in text:
    raise SystemExit('fake maintenance undo method did not match')
text = text.replace(old_undo_fake, new_undo_fake, 1)
path.write_text(text)

# 7) Stateful sync gateway test fake needs the new undo RPC surface.
path = Path('test/sync_coordinator_test.dart')
text = path.read_text()
insert_anchor = """  @override
  Future<void> startRealtime({
"""
undo_fake = """  @override
  Future<MaintenanceUndoResult> undoMaintenanceCompletion({
    required String payloadJson,
    required String userId,
    required String deviceId,
  }) async {
    final payload = Map<String, dynamic>.from(jsonDecode(payloadJson) as Map);
    final planId = payload['plan_id']! as String;
    final completionId = payload['completion_id']! as String;
    final previousDue = DateTime.parse(
      payload['previous_due_date']! as String,
    ).toUtc();
    final expectedCurrent = DateTime.parse(
      payload['expected_current_next_due_date']! as String,
    ).toUtc();
    final planIndex = _records.indexWhere(
      (item) =>
          item.userId == userId &&
          item.record.spec.entity == 'maintenance_plan' &&
          item.record.recordKey == planId,
    );
    if (planIndex < 0) {
      return const MaintenanceUndoResult(
        status: MaintenanceCompletionStatus.invalid,
        retryable: false,
        conflictReason: 'plan_missing',
      );
    }
    final completionIndex = _records.indexWhere(
      (item) =>
          item.userId == userId &&
          item.record.spec.entity == 'maintenance_record' &&
          item.record.recordKey == completionId,
    );
    if (completionIndex >= 0) {
      _records.removeAt(completionIndex);
    }
    var plan = _records[planIndex > completionIndex && completionIndex >= 0 ? planIndex - 1 : planIndex].record;
    final currentDue = DateTime.parse(plan.values['next_due_date']! as String).toUtc();
    var rewound = false;
    final newerCompletionExists = _records.any(
      (item) =>
          item.userId == userId &&
          item.record.spec.entity == 'maintenance_record' &&
          item.record.values['plan_id'] == planId,
    );
    if (!newerCompletionExists && currentDue.isAtSameMomentAs(expectedCurrent)) {
      final updated = SyncRecord(
        spec: plan.spec,
        recordKey: plan.recordKey,
        values: {
          ...plan.values,
          'next_due_date': previousDue.toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        clientModifiedAt: DateTime.now().toUtc(),
        originDeviceId: deviceId,
      );
      final result = await write(
        record: updated,
        userId: userId,
        deviceId: deviceId,
        expectedRevision: plan.revision,
      );
      plan = result.canonical!;
      rewound = true;
    }
    return MaintenanceUndoResult(
      status: MaintenanceCompletionStatus.applied,
      retryable: false,
      plan: plan,
      rewound: rewound,
    );
  }

"""
if insert_anchor not in text:
    raise SystemExit('stateful gateway insertion anchor did not match')
text = text.replace(insert_anchor, undo_fake + insert_anchor, 1)
path.write_text(text)

# 8) Complete -> Undo -> immediate Complete must be legitimate, and the guard
#    uses monotonic action elapsed independently of completedAt.
path = Path('test/recurring_completion_precision_test.dart')
text = path.read_text()
# Update existing rapid test to inject monotonic elapsed rather than DateTime now.
old_setup = """    var actionNow = DateTime(2026, 8, 16, 14, 30, 10);
    final guardedMaintenance = DriftMaintenanceRepository(
      db,
      now: () => actionNow,
    );
"""
new_setup = """    final actionNow = DateTime(2026, 8, 16, 14, 30, 10);
    var actionElapsed = Duration.zero;
    final guardedMaintenance = DriftMaintenanceRepository(
      db,
      now: () => actionNow,
      actionElapsed: () => actionElapsed,
    );
"""
if old_setup not in text:
    raise SystemExit('rapid guard setup did not match')
text = text.replace(old_setup, new_setup, 1)
text = text.replace("""      actionNow = firstAt.add(Duration(milliseconds: 500 * i));
      final repeat = await guardedMaintenance.completePlanResult(
""", """      actionElapsed = Duration(milliseconds: 500 * i);
      final repeat = await guardedMaintenance.completePlanResult(
""", 1)
text = text.replace("""    actionNow = afterWindowAt;
    final second = await guardedMaintenance.completePlanResult(
""", """    actionElapsed = const Duration(seconds: 5);
    final second = await guardedMaintenance.completePlanResult(
""", 1)
# Insert immediate re-completion regression before recurrence matrix.
matrix_anchor = """  test(
    'completion recurrence matrix anchors every supported unit to completedAt',
"""
immediate_test = """  test('Undo clears the duplicate guard for an immediate legitimate re-completion', () async {
    var actionElapsed = Duration.zero;
    final now = DateTime(2026, 8, 16, 14, 30);
    final guardedMaintenance = DriftMaintenanceRepository(
      db,
      now: () => now,
      actionElapsed: () => actionElapsed,
    );
    await assetRepo.saveArea(
      id: 'area_undo_guard',
      name: 'Undo guard',
      kind: AreaKind.indoor,
      sortOrder: 0,
    );
    final roomId = await assetRepo.saveRoom(
      areaId: 'area_undo_guard',
      name: 'Undo guard',
    );
    final assetId = await assetRepo.saveAsset(
      name: 'Undo guard asset',
      categoryId: (await assetRepo.listCategories()).first.id,
      roomId: roomId,
    );
    final due = DateTime(2026, 8, 18, 9);
    final planId = await guardedMaintenance.savePlan(
      id: 'plan_undo_guard',
      assetId: assetId,
      title: 'Undo guard task',
      recurrence: const RecurrenceRule(
        interval: 1,
        unit: RecurrenceUnit.months,
      ),
      priority: PriorityLevel.medium,
      nextDueDate: due,
      healthGroup: HealthGroup.other,
    );
    final first = await guardedMaintenance.completePlanResult(
      planId,
      completedAt: now,
      expectedNextDueDate: due,
    );
    expect(first.isApplied, isTrue);
    await guardedMaintenance.undoCompletion(
      planId: planId,
      completionId: first.operationId!,
      previousDueDate: first.previousDueDate!,
      expectedCurrentNextDueDate: first.nextDueDate!,
    );

    actionElapsed = const Duration(seconds: 1);
    final second = await guardedMaintenance.completePlanResult(
      planId,
      completedAt: now.add(const Duration(minutes: 1)),
      expectedNextDueDate: due,
    );
    expect(second.isApplied, isTrue);
    expect(second.duplicateIgnored, isFalse);
    expect(second.operationId, isNot(first.operationId));
    expect(await guardedMaintenance.listRecordsForPlan(planId), hasLength(1));
  });

"""
if matrix_anchor not in text:
    raise SystemExit('recurrence matrix anchor did not match')
text = text.replace(matrix_anchor, immediate_test + matrix_anchor, 1)
path.write_text(text)

# 9) Task-level restore must not resurrect independently trashed ancestors.
path = Path('test/trash_lifecycle_and_invariants_test.dart')
text = path.read_text()
account_group = """  group('Account Deletion & Data Isolation', () {
"""
restore_test = """  test('restoring a task refuses to resurrect a trashed parent hierarchy', () async {
    final areaId = await assetRepo.saveArea(
      name: 'Restore hierarchy',
      kind: AreaKind.indoor,
    );
    final roomId = await assetRepo.saveRoom(
      areaId: areaId,
      name: 'Restore hierarchy room',
    );
    final assetId = await assetRepo.saveAsset(
      name: 'Restore hierarchy asset',
      categoryId: (await assetRepo.listCategories()).first.id,
      roomId: roomId,
    );
    final planId = await maintenanceRepo.savePlan(
      assetId: assetId,
      title: 'Restore hierarchy task',
      recurrence: const RecurrenceRule(
        interval: 1,
        unit: RecurrenceUnit.months,
      ),
      priority: PriorityLevel.medium,
      nextDueDate: DateTime(2026, 9, 1, 9),
      healthGroup: HealthGroup.other,
    );

    await maintenanceRepo.archivePlan(planId);
    await assetRepo.trashAsset(assetId);
    await expectLater(
      maintenanceRepo.restorePlan(planId),
      throwsA(isA<StateError>()),
    );

    final assetRow = await (db.select(
      db.assets,
    )..where((row) => row.id.equals(assetId))).getSingle();
    final planRow = await (db.select(
      db.maintenancePlans,
    )..where((row) => row.id.equals(planId))).getSingle();
    expect(assetRow.archivedAt, isNotNull);
    expect(planRow.archivedAt, isNotNull);
  });

"""
if account_group not in text:
    raise SystemExit('trash account group anchor did not match')
text = text.replace(account_group, restore_test + account_group, 1)
path.write_text(text)
