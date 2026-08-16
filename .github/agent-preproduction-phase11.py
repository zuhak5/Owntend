from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if new in text:
        return
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one old match, found {count}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


# Legacy bool callers must distinguish a suppressed rapid duplicate from a new completion.
replace_once(
    "lib/src/core/data/maintenance_repository.dart",
    """    return result.isApplied;\n  }\n\n  DateTime canonicalSyncSecond""",
    """    return result.isApplied && !result.duplicateIgnored;\n  }\n\n  DateTime canonicalSyncSecond""",
)

# Cascade provenance uses archived_at equality, so make each cascade timestamp unique at
# SQLite's second storage precision rather than relying on OS clock tick resolution.
replace_once(
    "lib/src/core/data/asset_repository.dart",
    """  final AppDatabase db;\n\n  @override\n  Stream<List<domain.Area>> watchAreas()""",
    """  final AppDatabase db;\n\n  Future<DateTime> _nextTrashCascadeTimestamp() async {\n    final usedSeconds = <int>{};\n    void remember(DateTime? value) {\n      if (value != null) {\n        usedSeconds.add(value.millisecondsSinceEpoch ~/ 1000);\n      }\n    }\n\n    for (final row in await (db.select(db.areas)\n          ..where((row) => row.archivedAt.isNotNull()))\n        .get()) {\n      remember(row.archivedAt);\n    }\n    for (final row in await (db.select(db.rooms)\n          ..where((row) => row.archivedAt.isNotNull()))\n        .get()) {\n      remember(row.archivedAt);\n    }\n    for (final row in await (db.select(db.assets)\n          ..where((row) => row.archivedAt.isNotNull()))\n        .get()) {\n      remember(row.archivedAt);\n    }\n    for (final row in await (db.select(db.maintenancePlans)\n          ..where((row) => row.archivedAt.isNotNull()))\n        .get()) {\n      remember(row.archivedAt);\n    }\n\n    var candidateSecond = DateTime.now().millisecondsSinceEpoch ~/ 1000;\n    while (usedSeconds.contains(candidateSecond)) {\n      candidateSecond += 1;\n    }\n    return DateTime.fromMillisecondsSinceEpoch(candidateSecond * 1000);\n  }\n\n  @override\n  Stream<List<domain.Area>> watchAreas()""",
)
for method in ("trashArea", "trashRoom", "trashAsset"):
    replace_once(
        "lib/src/core/data/asset_repository.dart",
        f"""  Future<void> {method}(String id) async {{\n    final now = DateTime.now();\n    await db.transaction(() async {{""",
        f"""  Future<void> {method}(String id) async {{\n    await db.transaction(() async {{\n      final now = await _nextTrashCascadeTimestamp();""",
    )

# A losing multi-device completion must not create a generic maintenance_record delete.
replace_once(
    "lib/src/core/sync/local_sync_store.dart",
    """    await db.transaction(() async {\n      await (db.delete(\n        db.maintenanceRecords,\n      )..where((row) => row.id.equals(mutation.operationId))).go();\n      await applyRemoteRecords([plan, record]);\n\n      await db""",
    """    await db.transaction(() async {\n      await withOutboxSuppressed(() async {\n        await (db.delete(\n          db.maintenanceRecords,\n        )..where((row) => row.id.equals(mutation.operationId))).go();\n      });\n      await applyRemoteRecords([plan, record]);\n\n      await db""",
)

# Generic upserts use the row's semantic modified timestamp for conflict/clock-skew
# decisions. Trigger enqueue time remains the fallback for expressions that are not a
# direct selected column and for deletes.
replace_once(
    "lib/src/core/sync/local_sync_store.dart",
    """    final values = _toRemoteCompatible(spec, result.data);\n    return SyncRecord(\n      spec: spec,\n      recordKey: mutation.recordKey,\n      values: values,\n      clientModifiedAt: mutation.changedAt.toUtc(),\n      originDeviceId: deviceId,\n    );""",
    """    final values = _toRemoteCompatible(spec, result.data);\n    final semanticModifiedAt =\n        _semanticClientModifiedAt(spec, values) ?? mutation.changedAt.toUtc();\n    return SyncRecord(\n      spec: spec,\n      recordKey: mutation.recordKey,\n      values: values,\n      clientModifiedAt: semanticModifiedAt,\n      originDeviceId: deviceId,\n    );""",
)
replace_once(
    "lib/src/core/sync/local_sync_store.dart",
    """          \"SELECT value FROM settings WHERE key = 'profile' LIMIT 1\",\n        )""",
    """          \"SELECT value, updated_at FROM settings WHERE key = 'profile' LIMIT 1\",\n        )""",
)
replace_once(
    "lib/src/core/sync/local_sync_store.dart",
    """      values: {'nickname': decoded['nickname'] as String?},\n      clientModifiedAt: mutation.changedAt.toUtc(),\n      originDeviceId: deviceId,\n    );\n  }\n\n  Future<SyncShadow?> shadow""",
    """      values: {'nickname': decoded['nickname'] as String?},\n      clientModifiedAt:\n          _dateTimeFromStorage(row.data['updated_at']) ?? mutation.changedAt.toUtc(),\n      originDeviceId: deviceId,\n    );\n  }\n\n  Future<SyncShadow?> shadow""",
)
replace_once(
    "lib/src/core/sync/local_sync_store.dart",
    """Map<String, dynamic> _toRemoteCompatible(\n  SyncEntitySpec spec,""",
    """DateTime? _dateTimeFromStorage(dynamic value) {\n  if (value == null) return null;\n  if (value is DateTime) return value.toUtc();\n  if (value is int) {\n    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);\n  }\n  return DateTime.tryParse(value.toString())?.toUtc();\n}\n\nDateTime? _semanticClientModifiedAt(\n  SyncEntitySpec spec,\n  Map<String, dynamic> values,\n) {\n  final expression = spec.modifiedExpression.trim();\n  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(expression)) {\n    return null;\n  }\n  return _dateTimeFromStorage(values[expression]);\n}\n\nMap<String, dynamic> _toRemoteCompatible(\n  SyncEntitySpec spec,""",
)

# Re-read the outbox after an undo acknowledgement and after any short batch, because a
# local Undo can enqueue compensation while a completion RPC is in flight.
replace_once(
    "lib/src/core/sync/sync_coordinator.dart",
    """            // The undo acknowledgement removes any generic plan/delete guard\n            // rows that were already present in this in-memory batch. Re-read\n            // the outbox on the next sync pass rather than pushing stale rows.\n            return true;""",
    """            // The undo acknowledgement removes generic guard rows that may\n            // already be present in this in-memory batch. Stop using this snapshot\n            // and re-read the outbox immediately.\n            break;""",
)
replace_once(
    "lib/src/core/sync/sync_coordinator.dart",
    """      if (mutations.length < 200) return pushedSomething;\n    }\n  }""",
    """      if (mutations.length < 200) {\n        final remaining = await _localStore.pendingMutations();\n        if (remaining.isEmpty) return pushedSomething;\n      }\n    }\n  }""",
)

# Remove duplicated presentation branch while preserving duplicate suppression behavior.
replace_once(
    "lib/src/features/backup/presentation/backup_screen.dart",
    """  if (result.duplicateIgnored) {\n    return true;\n  }\n  if (result.duplicateIgnored) {\n    return true;\n  }""",
    """  if (result.duplicateIgnored) {\n    return true;\n  }""",
)

# Home repository regressions: preserve overdue due date, use deterministic postpone time,
# and satisfy the notification FK with a real plan fixture.
replace_once(
    "test/home_structure_repository_test.dart",
    """      expect(active.plan.isEnabled, isTrue);\n      expect(active.plan.nextDueDate.isAfter(clock), isTrue);\n      expect(active.plan.nextDueDate, DateTime(2026, 6, 19, 12));""",
    """      expect(active.plan.isEnabled, isTrue);\n      expect(active.plan.nextDueDate, originalDue);""",
)
replace_once(
    "test/home_structure_repository_test.dart",
    """    test('skips and postpones one task occurrence with reason notes', () async {\n      final maintenance = DriftMaintenanceRepository(db);""",
    """    test('skips and postpones one task occurrence with reason notes', () async {\n      final maintenance = DriftMaintenanceRepository(\n        db,\n        now: () => DateTime(2026, 1, 1, 8),\n      );""",
)
replace_once(
    "test/home_structure_repository_test.dart",
    """      () async {\n        final inbox = DriftNotificationInboxRepository(db);\n        await inbox.createNotification(\n          title: 'Task due',\n          body: 'Open Owntend',\n          kind: 'task',\n          route: '/maintenance/plan-dedupe',\n          planId: 'plan-dedupe',\n        );""",
    """      () async {\n        final roomId = await repo.saveRoom(\n          areaId: 'area_first_floor',\n          name: 'Dedupe room',\n        );\n        final categoryId = (await repo.listCategories()).first.id;\n        final assetId = await repo.saveAsset(\n          name: 'Dedupe asset',\n          categoryId: categoryId,\n          roomId: roomId,\n        );\n        final planId = await DriftMaintenanceRepository(db).savePlan(\n          id: 'plan-dedupe',\n          assetId: assetId,\n          title: 'Dedupe task',\n          recurrence: const RecurrenceRule(\n            interval: 1,\n            unit: RecurrenceUnit.days,\n          ),\n          priority: PriorityLevel.medium,\n          nextDueDate: DateTime(2026, 8, 17, 9),\n          healthGroup: HealthGroup.other,\n        );\n        final inbox = DriftNotificationInboxRepository(db);\n        await inbox.createNotification(\n          title: 'Task due',\n          body: 'Open Owntend',\n          kind: 'task',\n          route: '/maintenance/$planId',\n          planId: planId,\n        );""",
)
replace_once(
    "test/home_structure_repository_test.dart",
    """          route: '/maintenance/plan-dedupe',\n          planId: 'plan-dedupe',\n        );\n        expect(await inbox.unreadCount(), 1);""",
    """          route: '/maintenance/$planId',\n          planId: planId,\n        );\n        expect(await inbox.unreadCount(), 1);""",
)

# Sync fake must honor idempotency before classifying a retry as another-device conflict.
sync_path = ROOT / "test/sync_coordinator_test.dart"
sync_text = sync_path.read_text(encoding="utf-8")
old_idempotent = """    final existingRecord = await fetch(\n      spec: recordSpec,\n      userId: userId,\n      deviceId: deviceId,\n      recordKey: recordKey,\n    );\n    if (existingRecord != null) {\n      final existingPlan = await fetch(\n        spec: planSpec,\n        userId: userId,\n        deviceId: deviceId,\n        recordKey: planValues['id']! as String,\n      );\n      if (existingPlan == null) {\n        throw StateError('The idempotent completion lost its plan.');\n      }\n      return MaintenanceCompletionResult(\n        status: MaintenanceCompletionStatus.alreadyApplied,\n        retryable: false,\n        plan: existingPlan,\n        record: existingRecord,\n      );\n    }\n\n"""
if old_idempotent in sync_text:
    sync_text = sync_text.replace(old_idempotent, "", 1)
    anchor = """    final planId = planValues['id']! as String;\n    final expectedDue = DateTime.parse(\n      payload['expected_next_due_date']! as String,\n    ).toUtc();\n"""
    if sync_text.count(anchor) != 1:
        raise SystemExit("sync_coordinator_test.dart: idempotency anchor mismatch")
    sync_text = sync_text.replace(anchor, anchor + old_idempotent, 1)
elif anchor if False else False:
    pass
else:
    # Idempotent rerun: require already-applied lookup to precede existingPlan occurrence logic.
    marker = "final existingRecord = await fetch("
    plan_marker = "final existingPlan = await fetch("
    if marker not in sync_text:
        raise SystemExit("sync_coordinator_test.dart: missing idempotency block")
sync_path.write_text(sync_text, encoding="utf-8")

# Advance the injected monotonic action clock beyond the duplicate window for a true next occurrence.
replace_once(
    "test/sync_coordinator_test.dart",
    """      var repositoryNow = DateTime.utc(2026, 7, 1, 10);\n\n      final maintenance = DriftMaintenanceRepository(\n        db,\n        now: () {\n          final value = repositoryNow;\n          repositoryNow = repositoryNow.add(const Duration(hours: 1));\n          return value;\n        },\n      );""",
    """      var repositoryNow = DateTime.utc(2026, 7, 1, 10);\n      var actionElapsed = Duration.zero;\n\n      final maintenance = DriftMaintenanceRepository(\n        db,\n        now: () {\n          final value = repositoryNow;\n          repositoryNow = repositoryNow.add(const Duration(hours: 1));\n          return value;\n        },\n        actionElapsed: () => actionElapsed,\n      );""",
)
replace_once(
    "test/sync_coordinator_test.dart",
    """      expect(firstApplied, isTrue);\n\n      final afterFirst =\n          await (db.select(db.maintenancePlans)""",
    """      expect(firstApplied, isTrue);\n      actionElapsed += const Duration(seconds: 5);\n\n      final afterFirst =\n          await (db.select(db.maintenancePlans)""",
)

# Widget fake completion result must provide the operation identity required by causal Undo.
replace_once(
    "test/widget_test.dart",
    """    return LocalMaintenanceCompletionResult(\n      status: ok\n          ? LocalMaintenanceCompletionStatus.applied\n          : LocalMaintenanceCompletionStatus.occurrenceChanged,\n    );""",
    """    final completed = completedAt ?? DateTime.now();\n    final previousDue = expectedNextDueDate ?? completed;\n    return LocalMaintenanceCompletionResult(\n      status: ok\n          ? LocalMaintenanceCompletionStatus.applied\n          : LocalMaintenanceCompletionStatus.occurrenceChanged,\n      operationId: ok ? 'fake-completion-$planId' : null,\n      previousDueDate: ok ? previousDue : null,\n      nextDueDate: ok ? previousDue.add(const Duration(days: 1)) : null,\n    );""",
)

print("phase11 preproduction repair patch applied")
