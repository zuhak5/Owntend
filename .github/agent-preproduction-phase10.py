from pathlib import Path

# Production conflict handling: only implausibly future client clocks are skew.
# Old offline edits are not skew merely because they sync later.
path = Path('lib/src/core/sync/sync_coordinator.dart')
text = path.read_text()
old = """    final remote = result.canonical;
    final hasClockSkew = remote != null && _hasClockSkew(local, remote);
    if (hasClockSkew) {
      _clockSkewConflicts++;
    }
    if (remote != null &&
        ((shadow == null && await _localStore.isUntouchedSeed(local)) ||
            _sameRecordData(local, remote))) {
      await _ensureActiveAccountScope(scope);
      await _localStore.applyRemoteRecords([remote]);
      await _localStore.markMutationSucceeded(mutation, remote);
      return;
    } else if (remote == null) {
      result = await _remoteGateway.write(
        record: local,
        userId: userId,
        deviceId: deviceId,
        expectedRevision: null,
      );
      await _ensureActiveAccountScope(scope);
    } else if (hasClockSkew) {
      await _localStore.applyRemoteRecords([remote]);
      await _localStore.markMutationSucceeded(mutation, remote);
      return;
    } else if (hasClockSkew) {
      await _localStore.applyRemoteRecords([remote]);
      await _localStore.markMutationSucceeded(mutation, remote);
      return;
    } else if (local.clientModifiedAt.isAfter(remote.clientModifiedAt) ||
        (local.clientModifiedAt.isAtSameMomentAs(remote.clientModifiedAt) &&
            local.originDeviceId.compareTo(remote.originDeviceId) > 0)) {
      result = await _remoteGateway.write(
        record: local,
        userId: userId,
        deviceId: deviceId,
        expectedRevision: remote.revision,
      );
      await _ensureActiveAccountScope(scope);
    } else {
      await _ensureActiveAccountScope(scope);
      await _localStore.applyRemoteRecords([remote]);
      await _localStore.markMutationSucceeded(mutation, remote);
      return;
    }
"""
new = """    final remote = result.canonical;
    final now = DateTime.now().toUtc();
    final localFutureClock = remote != null &&
        _isFutureClockSkew(local.clientModifiedAt, now);
    final remoteFutureClock = remote != null &&
        remote.serverUpdatedAt != null &&
        _isFutureClockSkew(
          remote.clientModifiedAt,
          remote.serverUpdatedAt!,
        );
    if (localFutureClock || remoteFutureClock) {
      _clockSkewConflicts++;
    }
    if (remote != null &&
        ((shadow == null && await _localStore.isUntouchedSeed(local)) ||
            _sameRecordData(local, remote))) {
      await _ensureActiveAccountScope(scope);
      await _localStore.applyRemoteRecords([remote]);
      await _localStore.markMutationSucceeded(mutation, remote);
      return;
    } else if (remote == null) {
      result = await _remoteGateway.write(
        record: local,
        userId: userId,
        deviceId: deviceId,
        expectedRevision: null,
      );
      await _ensureActiveAccountScope(scope);
    } else if (localFutureClock) {
      // A fast local clock must not make an older local edit win solely by
      // timestamp. Keep the server-authoritative conflicting revision.
      await _localStore.applyRemoteRecords([remote]);
      await _localStore.markMutationSucceeded(mutation, remote);
      return;
    } else if (remoteFutureClock) {
      // Conversely, do not let a remote client's future clock dominate a
      // legitimate local mutation. Retry against the server revision once.
      result = await _remoteGateway.write(
        record: local,
        userId: userId,
        deviceId: deviceId,
        expectedRevision: remote.revision,
      );
      await _ensureActiveAccountScope(scope);
    } else if (local.clientModifiedAt.isAfter(remote.clientModifiedAt) ||
        (local.clientModifiedAt.isAtSameMomentAs(remote.clientModifiedAt) &&
            local.originDeviceId.compareTo(remote.originDeviceId) > 0)) {
      result = await _remoteGateway.write(
        record: local,
        userId: userId,
        deviceId: deviceId,
        expectedRevision: remote.revision,
      );
      await _ensureActiveAccountScope(scope);
    } else {
      await _ensureActiveAccountScope(scope);
      await _localStore.applyRemoteRecords([remote]);
      await _localStore.markMutationSucceeded(mutation, remote);
      return;
    }
"""
if old not in text:
    raise SystemExit('sync conflict block did not match')
text = text.replace(old, new, 1)
old_helper = """  bool _hasClockSkew(SyncRecord local, SyncRecord remote) {
    const tolerance = Duration(minutes: 5);
    final now = DateTime.now().toUtc();
    final localDelta = local.clientModifiedAt.toUtc().difference(now).abs();
    final remoteServerTime = remote.serverUpdatedAt;
    final remoteDelta = remoteServerTime == null
        ? Duration.zero
        : remote.clientModifiedAt
              .toUtc()
              .difference(remoteServerTime.toUtc())
              .abs();
    return localDelta > tolerance || remoteDelta > tolerance;
  }
"""
new_helper = """  bool _isFutureClockSkew(DateTime clientTime, DateTime referenceTime) {
    const tolerance = Duration(minutes: 5);
    return clientTime.toUtc().isAfter(referenceTime.toUtc().add(tolerance));
  }
"""
if old_helper not in text:
    raise SystemExit('clock skew helper did not match')
path.write_text(text.replace(old_helper, new_helper, 1))

# Sync test gateway: realistic server timestamps, occurrence conflict semantics,
# and a completion gate for in-flight Undo testing.
path = Path('test/sync_coordinator_test.dart')
text = path.read_text()
text = text.replace(
    """  var maintenanceCompletionCalls = 0;
  String? maintenanceCanonicalPlanTitle;
""",
    """  var maintenanceCompletionCalls = 0;
  var maintenanceUndoCalls = 0;
  Completer<void>? maintenanceCompletionGate;
  String? maintenanceCanonicalPlanTitle;
""",
    1,
)
text = text.replace(
    """  }) async {
    maintenanceCompletionCalls++;

    if (maintenanceCompletionCalls == failMaintenanceCompletionCall) {
""",
    """  }) async {
    maintenanceCompletionCalls++;
    await maintenanceCompletionGate?.future;

    if (maintenanceCompletionCalls == failMaintenanceCompletionCall) {
""",
    1,
)
# Add same-occurrence conflict behavior before idempotent same-ID lookup.
anchor = """    final existingRecord = await fetch(
      spec: recordSpec,
      userId: userId,
      deviceId: deviceId,
      recordKey: recordKey,
    );
"""
insert = """    final planId = planValues['id']! as String;
    final expectedDue = DateTime.parse(
      payload['expected_next_due_date']! as String,
    ).toUtc();
    final existingPlan = await fetch(
      spec: planSpec,
      userId: userId,
      deviceId: deviceId,
      recordKey: planId,
    );
    if (existingPlan != null) {
      final currentDue = DateTime.parse(
        existingPlan.values['next_due_date']! as String,
      ).toUtc();
      if (!currentDue.isAtSameMomentAs(expectedDue)) {
        final matchingOccurrence = _records
            .where(
              (item) =>
                  item.userId == userId &&
                  item.record.spec.entity == 'maintenance_record' &&
                  item.record.values['plan_id'] == planId &&
                  DateTime.parse(
                    item.record.values['due_date']! as String,
                  ).toUtc().isAtSameMomentAs(expectedDue),
            )
            .map((item) => item.record)
            .firstOrNull;
        if (matchingOccurrence != null) {
          return MaintenanceCompletionResult(
            status: MaintenanceCompletionStatus.conflict,
            retryable: false,
            plan: existingPlan,
            record: matchingOccurrence,
            currentPlanRevision: existingPlan.revision,
            resultingRecordId: matchingOccurrence.recordKey,
            resultingNextDueDate: currentDue,
            conflictReason: 'occurrence_completed_elsewhere',
          );
        }
      }
    }

"""
if anchor not in text:
    raise SystemExit('gateway existing-record anchor did not match')
text = text.replace(anchor, insert + anchor, 1)
# Count undo calls.
text = text.replace(
    """  }) async {
    final payload = Map<String, dynamic>.from(jsonDecode(payloadJson) as Map);
    final planId = payload['plan_id']! as String;
""",
    """  }) async {
    maintenanceUndoCalls++;
    final payload = Map<String, dynamic>.from(jsonDecode(payloadJson) as Map);
    final planId = payload['plan_id']! as String;
""",
    1,
)
# Fake serverUpdatedAt should reflect receipt time, not a fixed historical date.
old_server_time = """      serverUpdatedAt: DateTime.utc(
        2026,
        6,
        29,
      ).add(Duration(seconds: syncSeq)),
"""
new_server_time = """      serverUpdatedAt: DateTime.now().toUtc(),
"""
if old_server_time not in text:
    raise SystemExit('fake server time did not match')
text = text.replace(old_server_time, new_server_time, 1)

# Add focused regression tests before the existing network-restoration test.
network_anchor = """  test(
    'network restoration pushes queued edits and realtime pulls remote edits',
"""
new_tests = r'''  test('offline maintenance completion syncs when connectivity returns', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.account();
    await store.setEnabled(enabled: true, boundUserId: 'user-1');
    await store.recordSyncSuccess(DateTime.now().toUtc());
    await _seedMaintenancePlanForSync(db, suffix: 'offline');
    await db.delete(db.syncOutbox).go();

    final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(auth.controller.close);
    final connectivity = _FakeConnectivity(false);
    addTearDown(connectivity.controller.close);
    final gateway = _StatefulGateway();
    final coordinator = SyncCoordinator(
      auth,
      store,
      gateway,
      connectivity: connectivity,
      realtime: gateway,
    );
    addTearDown(coordinator.dispose);

    final due = DateTime.utc(2026, 8, 18, 9);
    final completedAt = DateTime.utc(2026, 8, 13, 14, 30);
    final completion = await DriftMaintenanceRepository(db).completePlanResult(
      'maintenance-plan-offline',
      completedAt: completedAt,
      expectedNextDueDate: due,
    );
    expect(completion.isApplied, isTrue);
    expect(await store.pendingCount(), 1);
    expect(gateway.maintenanceCompletionCalls, 0);

    connectivity.setOnline(true);
    await _eventually(() async {
      return gateway.maintenanceCompletionCalls == 1 &&
          await store.pendingCount() == 0;
    });

    final remotePlan = await gateway.fetch(
      spec: syncSpecByEntity['maintenance_plan']!,
      userId: 'user-1',
      deviceId: (await store.account()).deviceId,
      recordKey: 'maintenance-plan-offline',
    );
    expect(remotePlan, isNotNull);
    expect(
      DateTime.parse(remotePlan!.values['next_due_date']! as String).toUtc(),
      DateTime.utc(2026, 9, 13, 14, 30),
    );
    final remoteRecord = gateway._records.singleWhere(
      (item) =>
          item.userId == 'user-1' &&
          item.record.spec.entity == 'maintenance_record',
    );
    expect(
      DateTime.parse(
        remoteRecord.record.values['completed_at']! as String,
      ).toUtc(),
      completedAt,
    );
  });

  test('two devices completing one occurrence converge on the first canonical completion', () async {
    final dbA = AppDatabase(executor: NativeDatabase.memory());
    final dbB = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(dbA.close);
    addTearDown(dbB.close);
    final storeA = LocalSyncStore(dbA);
    final storeB = LocalSyncStore(dbB);
    await storeA.account();
    await storeB.account();
    await storeA.setEnabled(enabled: true, boundUserId: 'user-1');
    await storeB.setEnabled(enabled: true, boundUserId: 'user-1');
    await storeA.recordSyncSuccess(DateTime.now().toUtc());
    await storeB.recordSyncSuccess(DateTime.now().toUtc());
    await _seedMaintenancePlanForSync(dbA, suffix: 'race');
    await _seedMaintenancePlanForSync(dbB, suffix: 'race');
    await dbA.delete(dbA.syncOutbox).go();
    await dbB.delete(dbB.syncOutbox).go();

    final due = DateTime.utc(2026, 8, 18, 9);
    final repoA = DriftMaintenanceRepository(dbA);
    final repoB = DriftMaintenanceRepository(dbB);
    final first = await repoA.completePlanResult(
      'maintenance-plan-race',
      completedAt: DateTime.utc(2026, 8, 18, 10),
      expectedNextDueDate: due,
    );
    final second = await repoB.completePlanResult(
      'maintenance-plan-race',
      completedAt: DateTime.utc(2026, 8, 18, 10, 5),
      expectedNextDueDate: due,
    );
    expect(first.isApplied, isTrue);
    expect(second.isApplied, isTrue);

    final authA = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    final authB = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(authA.controller.close);
    addTearDown(authB.controller.close);
    final gateway = _StatefulGateway();
    final coordinatorA = SyncCoordinator(
      authA,
      storeA,
      gateway,
      listenToAuthChanges: false,
    );
    final coordinatorB = SyncCoordinator(
      authB,
      storeB,
      gateway,
      listenToAuthChanges: false,
    );
    addTearDown(coordinatorA.dispose);
    addTearDown(coordinatorB.dispose);

    await coordinatorA.syncNow();
    await coordinatorB.syncNow();

    expect(await storeA.pendingCount(), 0);
    expect(await storeB.pendingCount(), 0);
    final recordsA = await repoA.listRecordsForPlan('maintenance-plan-race');
    final recordsB = await repoB.listRecordsForPlan('maintenance-plan-race');
    expect(recordsA, hasLength(1));
    expect(recordsB, hasLength(1));
    expect(recordsA.single.id, first.operationId);
    expect(recordsB.single.id, first.operationId);
    expect(recordsB.single.id, isNot(second.operationId));
    expect(recordsB.single.completedAt.toUtc(), DateTime.utc(2026, 8, 18, 10));
    expect(
      (await repoB.getTask('maintenance-plan-race'))!.plan.nextDueDate.toUtc(),
      (await repoA.getTask('maintenance-plan-race'))!.plan.nextDueDate.toUtc(),
    );
  });

  test('Undo while completion RPC is in flight compensates the cloud atomically', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.account();
    await store.setEnabled(enabled: true, boundUserId: 'user-1');
    await store.recordSyncSuccess(DateTime.now().toUtc());
    await _seedMaintenancePlanForSync(db, suffix: 'undo-race');
    await db.delete(db.syncOutbox).go();

    final due = DateTime.utc(2026, 8, 18, 9);
    final repo = DriftMaintenanceRepository(db);
    final completion = await repo.completePlanResult(
      'maintenance-plan-undo-race',
      completedAt: DateTime.utc(2026, 8, 18, 10),
      expectedNextDueDate: due,
    );
    expect(completion.isApplied, isTrue);

    final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(auth.controller.close);
    final gateway = _StatefulGateway()
      ..maintenanceCompletionGate = Completer<void>();
    final coordinator = SyncCoordinator(
      auth,
      store,
      gateway,
      listenToAuthChanges: false,
    );
    addTearDown(coordinator.dispose);

    final syncFuture = coordinator.syncNow();
    await _eventually(() async => gateway.maintenanceCompletionCalls == 1);

    await repo.undoCompletion(
      planId: 'maintenance-plan-undo-race',
      completionId: completion.operationId!,
      previousDueDate: completion.previousDueDate!,
      expectedCurrentNextDueDate: completion.nextDueDate!,
    );
    gateway.maintenanceCompletionGate!.complete();
    await syncFuture;
    await _eventually(() async {
      return gateway.maintenanceUndoCalls == 1 &&
          await store.pendingCount() == 0;
    });

    expect(await repo.listRecordsForPlan('maintenance-plan-undo-race'), isEmpty);
    expect(
      (await repo.getTask('maintenance-plan-undo-race'))!.plan.nextDueDate.toUtc(),
      due,
    );
    expect(
      gateway._records.where(
        (item) =>
            item.userId == 'user-1' &&
            item.record.spec.entity == 'maintenance_record',
      ),
      isEmpty,
    );
    final remotePlan = gateway._records.singleWhere(
      (item) =>
          item.userId == 'user-1' &&
          item.record.spec.entity == 'maintenance_plan' &&
          item.record.recordKey == 'maintenance-plan-undo-race',
    );
    expect(
      DateTime.parse(remotePlan.record.values['next_due_date']! as String).toUtc(),
      due,
    );
  });

  test('old offline timestamps remain normal conflicts while a fast local clock cannot win', () async {
    Future<String> runScenario({required bool fastLocalClock}) async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = LocalSyncStore(db);
      final account = await store.account();
      await store.setEnabled(enabled: true, boundUserId: 'user-1');
      await store.recordSyncSuccess(DateTime.now().toUtc());
      await db.delete(db.syncOutbox).go();
      final gateway = _StatefulGateway();
      final spec = syncSpecByEntity['user_setting']!;
      final now = DateTime.now().toUtc();
      final initialAt = now.subtract(const Duration(hours: 3));
      final remoteEditAt = now.subtract(const Duration(hours: 2));
      final localEditAt = fastLocalClock
          ? now.add(const Duration(hours: 1))
          : now.subtract(const Duration(hours: 1));

      final initialWrite = await gateway.write(
        record: SyncRecord(
          spec: spec,
          recordKey: 'theme',
          values: {
            'key': 'theme',
            'value': 'light',
            'updated_at': initialAt.toIso8601String(),
          },
          clientModifiedAt: initialAt,
          originDeviceId: 'seed-device',
        ),
        userId: 'user-1',
        deviceId: 'seed-device',
        expectedRevision: null,
      );
      await store.applyRemoteRecords([initialWrite.canonical!]);
      await db.delete(db.syncOutbox).go();

      final remoteWrite = await gateway.write(
        record: SyncRecord(
          spec: spec,
          recordKey: 'theme',
          values: {
            'key': 'theme',
            'value': 'dark',
            'updated_at': remoteEditAt.toIso8601String(),
          },
          clientModifiedAt: remoteEditAt,
          originDeviceId: 'remote-device',
        ),
        userId: 'user-1',
        deviceId: 'remote-device',
        expectedRevision: initialWrite.canonical!.revision,
      );
      expect(remoteWrite.conflict, isFalse);

      await (db.update(db.settings)..where((row) => row.key.equals('theme')))
          .write(
            SettingsCompanion(
              value: const Value('system'),
              updatedAt: Value(localEditAt),
            ),
          );
      expect(await store.pendingCount(), 1);

      final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
      addTearDown(auth.controller.close);
      final coordinator = SyncCoordinator(
        auth,
        store,
        gateway,
        listenToAuthChanges: false,
      );
      addTearDown(coordinator.dispose);
      await coordinator.syncNow();

      final remoteFinal = await gateway.fetch(
        spec: spec,
        userId: 'user-1',
        deviceId: account.deviceId,
        recordKey: 'theme',
      );
      return remoteFinal!.values['value']! as String;
    }

    expect(await runScenario(fastLocalClock: false), 'system');
    expect(await runScenario(fastLocalClock: true), 'dark');
  });

'''
if network_anchor not in text:
    raise SystemExit('network restoration test anchor did not match')
text = text.replace(network_anchor, new_tests + network_anchor, 1)

# Add a shared seed helper before _eventually.
eventually_anchor = """Future<void> _eventually(Future<bool> Function() condition) async {
"""
seed_helper = r'''Future<void> _seedMaintenancePlanForSync(
  AppDatabase db, {
  required String suffix,
}) async {
  final store = LocalSyncStore(db);
  await store.withOutboxSuppressed(() async {
    await DriftAssetRepository(db).saveArea(
      id: 'area-$suffix',
      name: 'Area $suffix',
      kind: AreaKind.indoor,
      sortOrder: 0,
    );
    await db.into(db.rooms).insert(
      RoomsCompanion.insert(
        id: 'maintenance-room-$suffix',
        areaId: 'area-$suffix',
        name: 'Maintenance room $suffix',
      ),
    );
    await db.into(db.assets).insert(
      AssetsCompanion.insert(
        id: 'maintenance-asset-$suffix',
        name: 'Maintenance asset $suffix',
        categoryId: 'category_general',
        roomId: 'maintenance-room-$suffix',
      ),
    );
    await db.into(db.maintenancePlans).insert(
      MaintenancePlansCompanion.insert(
        id: 'maintenance-plan-$suffix',
        assetId: 'maintenance-asset-$suffix',
        title: 'Maintenance task $suffix',
        recurrenceInterval: 1,
        recurrenceUnit: 'months',
        priority: 'medium',
        nextDueDate: DateTime.utc(2026, 8, 18, 9),
        healthGroup: 'other',
      ),
    );
  });
}

'''
if eventually_anchor not in text:
    raise SystemExit('eventually helper anchor did not match')
text = text.replace(eventually_anchor, seed_helper + eventually_anchor, 1)
path.write_text(text)

# Database-level two-device same-occurrence regression against the actual RPC.
path = Path('supabase/tests/database/0011_complete_maintenance_task.test.sql')
sql = path.read_text()
if 'select plan(50);' not in sql:
    raise SystemExit('expected pgTAP plan count 50')
sql = sql.replace('select plan(50);', 'select plan(52);', 1)
finish_anchor = 'select * from finish();\nrollback;\n'
if finish_anchor not in sql:
    raise SystemExit('pgTAP finish anchor did not match')
race_test = r'''set local role postgres;

insert into public.maintenance_plans (
  user_id,
  id,
  asset_id,
  title,
  interval_count,
  interval_unit,
  priority,
  next_due_date,
  reminder_days_before,
  health_group,
  is_enabled,
  revision,
  created_at,
  updated_at
)
values (
  '33333333-3333-3333-3333-333333333333',
  'rpc-race-plan',
  'rpc-asset',
  'Race completion task',
  1,
  'months',
  'medium',
  '2026-08-18 09:00:00+00',
  0,
  'other',
  true,
  1,
  '2026-08-01 00:00:00+00',
  '2026-08-01 00:00:00+00'
);

set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
set local role authenticated;

select is(
  public.complete_maintenance_task(
    jsonb_build_object(
      'version', 2,
      'operation_id', 'rpc-race-first',
      'expected_next_due_date', '2026-08-18T09:00:00.000Z',
      'plan', jsonb_build_object(
        'id', 'rpc-race-plan',
        'asset_id', 'rpc-asset',
        'title', 'Race completion task',
        'recurrence_interval', 1,
        'recurrence_unit', 'months',
        'priority', 'medium',
        'next_due_date', '2026-09-18T10:00:00.000Z',
        'reminder_days_before', 0,
        'is_enabled', true,
        'health_group', 'other',
        'created_at', '2026-08-01T00:00:00.000Z',
        'updated_at', '2026-08-18T10:00:00.000Z'
      ),
      'record', jsonb_build_object(
        'id', 'rpc-race-first',
        'plan_id', 'rpc-race-plan',
        'due_date', '2026-08-18T09:00:00.000Z',
        'completed_at', '2026-08-18T10:00:00.000Z'
      )
    ),
    'rpc-device-a'
  ) ->> 'status',
  'applied',
  'first device applies the shared occurrence'
);

select results_eq(
  $$
    select
      response ->> 'status',
      response ->> 'conflict_reason',
      response -> 'record' ->> 'id'
    from (
      select public.complete_maintenance_task(
        jsonb_build_object(
          'version', 2,
          'operation_id', 'rpc-race-second',
          'expected_next_due_date', '2026-08-18T09:00:00.000Z',
          'plan', jsonb_build_object(
            'id', 'rpc-race-plan',
            'asset_id', 'rpc-asset',
            'title', 'Race completion task',
            'recurrence_interval', 1,
            'recurrence_unit', 'months',
            'priority', 'medium',
            'next_due_date', '2026-09-18T10:05:00.000Z',
            'reminder_days_before', 0,
            'is_enabled', true,
            'health_group', 'other',
            'created_at', '2026-08-01T00:00:00.000Z',
            'updated_at', '2026-08-18T10:05:00.000Z'
          ),
          'record', jsonb_build_object(
            'id', 'rpc-race-second',
            'plan_id', 'rpc-race-plan',
            'due_date', '2026-08-18T09:00:00.000Z',
            'completed_at', '2026-08-18T10:05:00.000Z'
          )
        ),
        'rpc-device-b'
      ) as response
    ) as result
  $$,
  $$ values ('conflict'::text, 'occurrence_completed_elsewhere'::text, 'rpc-race-first'::text) $$,
  'second device converges on the canonical completion for the same occurrence'
);

'''
sql = sql.replace(finish_anchor, race_test + finish_anchor, 1)
path.write_text(sql)
