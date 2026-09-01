import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/supabase_sync_gateway.dart';
import 'package:owntend/src/core/sync/sync_coordinator.dart';
import 'package:owntend/src/core/sync/sync_contracts.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _url = String.fromEnvironment('OWNTEND_TEST_SUPABASE_URL');
const _anonKey = String.fromEnvironment('OWNTEND_TEST_SUPABASE_ANON_KEY');
const _serviceRoleKey = String.fromEnvironment(
  'OWNTEND_TEST_SUPABASE_SERVICE_ROLE_KEY',
);

class _StaticAuthRepository implements AuthRepository {
  _StaticAuthRepository(String userId)
    : _session = AuthSession(userId: userId, providers: const {'google'});

  final AuthSession _session;

  @override
  AuthSession get currentSession => _session;

  @override
  Stream<AuthStateChange> watchAuthState() => Stream.value(
    AuthStateChange(event: AuthEventType.initialSession, session: _session),
  );

  @override
  Future<void> deleteAccount() => throw UnsupportedError('not used');

  @override
  Future<void> signInWithGoogle() => throw UnsupportedError('not used');

  @override
  Future<void> signOut({bool allDevices = false}) =>
      throw UnsupportedError('not used');
}

Future<SupabaseClient> _signedInClient(String email, String password) async {
  final client = SupabaseClient(_url, _anonKey);
  await client.auth.signInWithPassword(email: email, password: password);
  return client;
}

Map<String, dynamic> _signedOperation(Map<String, dynamic> unsigned) => {
  ...unsigned,
  'request_hash': sha256.convert(utf8.encode(jsonEncode(unsigned))).toString(),
};

void main() {
  if (_url.isEmpty || _anonKey.isEmpty || _serviceRoleKey.isEmpty) {
    test(
      'local backend integration configuration is supplied by its explicit gate',
      () {},
      skip:
          'Run the local-backend CI command with disposable Supabase defines.',
    );
    return;
  }

  late SupabaseClient admin;
  late SupabaseClient userADevice1;
  late SupabaseClient userADevice2;
  late SupabaseClient userB;
  late String userAId;
  late String userBId;

  const password = 'Owntend-local-backend-1!';
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final userAEmail = 'owntend-a-$nonce@example.invalid';
  final userBEmail = 'owntend-b-$nonce@example.invalid';

  setUpAll(() async {
    final uri = Uri.parse(_url);
    if (!const {'127.0.0.1', 'localhost', '::1'}.contains(uri.host)) {
      fail('The integration suite refuses to use a non-loopback backend.');
    }

    admin = SupabaseClient(_url, _serviceRoleKey);
    final createdA = await admin.auth.admin.createUser(
      AdminUserAttributes(
        email: userAEmail,
        password: password,
        emailConfirm: true,
      ),
    );
    final createdB = await admin.auth.admin.createUser(
      AdminUserAttributes(
        email: userBEmail,
        password: password,
        emailConfirm: true,
      ),
    );
    userAId = createdA.user!.id;
    userBId = createdB.user!.id;
    userADevice1 = await _signedInClient(userAEmail, password);
    userADevice2 = await _signedInClient(userAEmail, password);
    userB = await _signedInClient(userBEmail, password);
  });

  tearDownAll(() async {
    await userADevice1.dispose();
    await userADevice2.dispose();
    await userB.dispose();
    await admin.auth.admin.deleteUser(userAId);
    await admin.auth.admin.deleteUser(userBId);
    await admin.dispose();
  });

  test(
    'RLS isolates two users and the owner feed carries canonical payloads',
    () async {
      await userADevice1.from('areas').insert({
        'user_id': userAId,
        'id': 'backend-area',
        'name': 'Backend Area',
        'kind': 'indoor',
        'sort_order': 0,
      });

      final ownerRows = await userADevice2
          .from('areas')
          .select('id,name')
          .eq('id', 'backend-area');
      expect(ownerRows, hasLength(1));
      final otherRows = await userB
          .from('areas')
          .select('id')
          .eq('id', 'backend-area');
      expect(otherRows, isEmpty);
      await expectLater(
        userB.from('areas').insert({
          'user_id': userAId,
          'id': 'cross-user-area',
          'name': 'Forbidden Area',
          'kind': 'indoor',
          'sort_order': 0,
        }),
        throwsA(isA<PostgrestException>()),
      );

      final feed = Map<String, dynamic>.from(
        await userADevice2.rpc<Map<String, dynamic>>(
          'fetch_user_change_feed',
          params: {'p_since_seq': 0, 'p_limit': 100},
        ) as Map,
      );
      expect(feed['contract_version'], 1);
      final changes = List<Map<String, dynamic>>.from(
        (feed['changes'] as List).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      expect(
        changes,
        contains(
          isA<Map<String, dynamic>>()
              .having((entry) => entry['entity_type'], 'entity', 'area')
              .having(
                (entry) => (entry['payload'] as Map?)?['name'],
                'payload name',
                'Backend Area',
              ),
        ),
      );
    },
  );

  test(
    'two application stores converge through snapshot, outbox, and feed',
    () async {
      final database1 = AppDatabase(executor: NativeDatabase.memory());
      final database2 = AppDatabase(executor: NativeDatabase.memory());
      final store1 = LocalSyncStore(database1);
      final store2 = LocalSyncStore(database2);
      final auth = _StaticAuthRepository(userAId);
      final coordinator1 = SyncCoordinator(
        auth,
        store1,
        SupabaseSyncGateway(userADevice1),
        listenToAuthChanges: false,
      );
      final coordinator2 = SyncCoordinator(
        auth,
        store2,
        SupabaseSyncGateway(userADevice2),
        listenToAuthChanges: false,
      );
      addTearDown(() async {
        await coordinator1.dispose();
        await coordinator2.dispose();
        await database1.close();
        await database2.close();
      });

      await coordinator1.enable();
      await coordinator2.enable();
      expect(
        (await DriftAssetRepository(
          database2,
        ).listAreas()).map((area) => area.name),
        contains('Backend Area'),
      );

      await DriftAssetRepository(database1).saveArea(
        id: 'device-one-area',
        name: 'Device One',
        kind: AreaKind.indoor,
      );
      expect(await store1.pendingCount(), greaterThan(0));
      await coordinator1.syncNow();
      expect(await store1.pendingCount(), 0);

      await coordinator2.syncIncremental();
      final device2Areas = await DriftAssetRepository(database2).listAreas();
      expect(
        device2Areas,
        contains(
          isA<Area>()
              .having((area) => area.id, 'id', 'device-one-area')
              .having((area) => area.name, 'name', 'Device One'),
        ),
      );
    },
  );

  test(
    'batch creation replays are idempotent without masking unique conflicts',
    () async {
      final gateway = SupabaseSyncGateway(userADevice1);
      final createdAt = DateTime.utc(2026, 8, 26, 12);
      final record = SyncRecord(
        spec: syncSpecByEntity['tag']!,
        recordKey: 'backend-replay-tag',
        values: {
          'id': 'backend-replay-tag',
          'name': 'Backend Replay Tag',
          'created_at': createdAt.toIso8601String(),
        },
        clientModifiedAt: createdAt,
        originDeviceId: 'integration-device',
      );

      final first = await gateway.writeNewBatch(
        records: [record],
        userId: userAId,
        deviceId: 'integration-device',
      );
      expect(first, isA<BatchWriteSuccess>());
      expect((first as BatchWriteSuccess).records, hasLength(1));
      expect(first.replayedRecordKeys, isEmpty);

      final replay = await gateway.writeNewBatch(
        records: [record],
        userId: userAId,
        deviceId: 'integration-device',
      );
      expect(replay, isA<BatchWriteSuccess>());
      expect((replay as BatchWriteSuccess).records, isEmpty);
      expect(replay.replayedRecordKeys, {'backend-replay-tag'});

      final duplicateName = SyncRecord(
        spec: syncSpecByEntity['tag']!,
        recordKey: 'backend-secondary-conflict-tag',
        values: {
          'id': 'backend-secondary-conflict-tag',
          'name': 'Backend Replay Tag',
          'created_at': createdAt.toIso8601String(),
        },
        clientModifiedAt: createdAt,
        originDeviceId: 'integration-device',
      );
      final secondaryConflict = await gateway.writeNewBatch(
        records: [duplicateName],
        userId: userAId,
        deviceId: 'integration-device',
      );
      expect(secondaryConflict, isA<BatchWriteConflict>());
      expect(
        (secondaryConflict as BatchWriteConflict).isPrimaryKeyConflict,
        isFalse,
      );
    },
  );

  test('real gateway PATCH contracts update assets and plans without protected columns', () async {
    const areaId = 'patch-contract-area';
    const roomId = 'patch-contract-room';
    const assetId = 'patch-contract-asset';
    const planId = 'patch-contract-plan';
    await userB.from('areas').insert({
      'user_id': userBId,
      'id': areaId,
      'name': 'PATCH Contract Area',
      'kind': 'indoor',
      'sort_order': 0,
    });
    await userB.from('rooms').insert({
      'user_id': userBId,
      'id': roomId,
      'area_id': areaId,
      'name': 'PATCH Contract Room',
      'sort_order': 0,
    });
    await userB.rpc<void>(
      'create_asset',
      params: {
        'p_operation': _signedOperation({
          'operation_id': const Uuid().v4(),
          'asset': {
            'id': assetId,
            'room_id': roomId,
            'name': 'Before PATCH asset',
            'asset_type': 'safety',
            'placement': 'Before placement',
            'notes': 'Clear this note',
          },
          'details': <String, dynamic>{},
          'initial_plans': <Map<String, dynamic>>[],
        }),
      },
    );
    await userB.rpc<void>(
      'create_task_with_point_debit',
      params: {
        'p_operation': _signedOperation({
          'operation_id': const Uuid().v4(),
          'plan': {
            'id': planId,
            'asset_id': assetId,
            'title': 'Before PATCH plan',
            'instructions': 'Clear these instructions',
            'recurrence_interval': 1,
            'recurrence_unit': 'months',
            'priority': 'medium',
            'next_due_date': '2026-10-01T00:00:00Z',
            'reminder_days_before': 1,
            'is_enabled': true,
          },
        }),
      },
    );

    final assetSpec = syncSpecByEntity['asset']!;
    final planSpec = syncSpecByEntity['maintenance_plan']!;
    final assetBeforeRow = Map<String, dynamic>.from(
      await userB
          .from('assets')
          .select(assetSpec.selectClause)
          .eq('id', assetId)
          .single(),
    );
    final planBeforeRow = Map<String, dynamic>.from(
      await userB
          .from('maintenance_plans')
          .select(planSpec.selectClause)
          .eq('id', planId)
          .single(),
    );
    final assetBefore = SyncRecord.fromRemote(assetSpec, assetBeforeRow);
    final planBefore = SyncRecord.fromRemote(planSpec, planBeforeRow);
    final gateway = SupabaseSyncGateway(userB);

    final assetResult = await gateway.write(
      record: SyncRecord(
        spec: assetSpec,
        recordKey: assetBefore.recordKey,
        values: {
          ...assetBefore.values,
          'name': 'After PATCH asset',
          'placement': 'After placement',
          'notes': null,
        },
        clientModifiedAt: DateTime.now().toUtc(),
        revision: assetBefore.revision,
        serverUpdatedAt: assetBefore.serverUpdatedAt,
      ),
      userId: userBId,
      deviceId: 'patch-contract-device',
      expectedRevision: assetBefore.revision,
    );
    expect(assetResult.conflict, isFalse);
    expect(assetResult.canonical?.revision, assetBefore.revision! + 1);

    final planResult = await gateway.write(
      record: SyncRecord(
        spec: planSpec,
        recordKey: planBefore.recordKey,
        values: {
          ...planBefore.values,
          'title': 'After PATCH plan',
          'instructions': null,
          'recurrence_interval': 2,
          'priority': 'high',
          'reminder_days_before': 3,
        },
        clientModifiedAt: DateTime.now().toUtc(),
        revision: planBefore.revision,
        serverUpdatedAt: planBefore.serverUpdatedAt,
      ),
      userId: userBId,
      deviceId: 'patch-contract-device',
      expectedRevision: planBefore.revision,
    );
    expect(planResult.conflict, isFalse);
    expect(planResult.canonical?.revision, planBefore.revision! + 1);

    final assetAfter = Map<String, dynamic>.from(
      await userB
          .from('assets')
          .select(assetSpec.selectClause)
          .eq('id', assetId)
          .single(),
    );
    final planAfter = Map<String, dynamic>.from(
      await userB
          .from('maintenance_plans')
          .select(planSpec.selectClause)
          .eq('id', planId)
          .single(),
    );
    expect(assetAfter['name'], 'After PATCH asset');
    expect(assetAfter['placement'], 'After placement');
    expect(assetAfter['notes'], isNull);
    expect(assetAfter['revision'], (assetBeforeRow['revision'] as int) + 1);
    expect(assetAfter['user_id'], assetBeforeRow['user_id']);
    expect(assetAfter['id'], assetBeforeRow['id']);
    expect(assetAfter['asset_type'], assetBeforeRow['asset_type']);
    expect(assetAfter['room_id'], assetBeforeRow['room_id']);
    expect(assetAfter['created_at'], assetBeforeRow['created_at']);
    expect(planAfter['title'], 'After PATCH plan');
    expect(planAfter['instructions'], isNull);
    expect(planAfter['recurrence_interval'], 2);
    expect(planAfter['priority'], 'high');
    expect(planAfter['reminder_days_before'], 3);
    expect(planAfter['revision'], (planBeforeRow['revision'] as int) + 1);
    expect(planAfter['user_id'], planBeforeRow['user_id']);
    expect(planAfter['id'], planBeforeRow['id']);
    expect(planAfter['asset_id'], planBeforeRow['asset_id']);
    expect(planAfter['created_at'], planBeforeRow['created_at']);

    final staleAsset = await gateway.write(
      record: SyncRecord(
        spec: assetSpec,
        recordKey: assetBefore.recordKey,
        values: {...assetBefore.values, 'name': 'Stale PATCH asset'},
        clientModifiedAt: DateTime.now().toUtc(),
        revision: assetBefore.revision,
      ),
      userId: userBId,
      deviceId: 'patch-contract-device',
      expectedRevision: assetBefore.revision,
    );
    expect(staleAsset.conflict, isTrue);
    expect(staleAsset.canonical?.revision, assetResult.canonical?.revision);

    final crossUserAsset = await SupabaseSyncGateway(userADevice1).write(
      record: SyncRecord(
        spec: assetSpec,
        recordKey: assetBefore.recordKey,
        values: {...assetBefore.values, 'name': 'Cross-user asset'},
        clientModifiedAt: DateTime.now().toUtc(),
        revision: assetBefore.revision,
      ),
      userId: userAId,
      deviceId: 'cross-user-device',
      expectedRevision: assetBefore.revision,
    );
    final crossUserPlan = await SupabaseSyncGateway(userADevice1).write(
      record: SyncRecord(
        spec: planSpec,
        recordKey: planBefore.recordKey,
        values: {...planBefore.values, 'title': 'Cross-user plan'},
        clientModifiedAt: DateTime.now().toUtc(),
        revision: planBefore.revision,
      ),
      userId: userAId,
      deviceId: 'cross-user-device',
      expectedRevision: planBefore.revision,
    );
    expect(crossUserAsset.conflict, isTrue);
    expect(crossUserAsset.canonical, isNull);
    expect(crossUserPlan.conflict, isTrue);
    expect(crossUserPlan.canonical, isNull);
    expect(
      await userB.from('assets').select('name').eq('id', assetId).single(),
      {'name': 'After PATCH asset'},
    );
    expect(
      await userB
          .from('maintenance_plans')
          .select('title')
          .eq('id', planId)
          .single(),
      {'title': 'After PATCH plan'},
    );
  });

  test('versioned completion RPC handles applied, stale, invalid, and cross-user outcomes', () async {
    const areaId = 'completion-contract-area';
    const roomId = 'completion-contract-room';
    const assetId = 'completion-contract-asset';
    const planId = 'completion-contract-plan';
    const recordId = 'completion-contract-record';
    final now = DateTime.now().toUtc();
    var completedInstant = DateTime.utc(now.year, now.month, 15, 1);
    if (completedInstant.isAfter(now)) {
      completedInstant = DateTime.utc(now.year, now.month - 1, 15, 1);
    }
    final dueDate = completedInstant
        .subtract(const Duration(days: 1))
        .toIso8601String();
    final completedAt = completedInstant.toIso8601String();
    final nextDueDate = DateTime.utc(
      completedInstant.year,
      completedInstant.month + 1,
      completedInstant.day,
      completedInstant.hour,
    ).toIso8601String();

    await userADevice1.from('areas').insert({
      'user_id': userAId,
      'id': areaId,
      'name': 'Completion Contract Area',
      'kind': 'indoor',
      'sort_order': 0,
    });
    await userADevice1.from('rooms').insert({
      'user_id': userAId,
      'id': roomId,
      'area_id': areaId,
      'name': 'Completion Contract Room',
      'sort_order': 0,
    });
    await userADevice1.rpc<void>(
      'create_asset',
      params: {
        'p_operation': _signedOperation({
          'operation_id': const Uuid().v4(),
          'asset': {
            'id': assetId,
            'room_id': roomId,
            'name': 'Completion Contract Asset',
            'asset_type': 'general',
          },
          'details': <String, dynamic>{},
          'initial_plans': <Map<String, dynamic>>[],
        }),
      },
    );
    await userADevice1.rpc<void>(
      'create_task_with_point_debit',
      params: {
        'p_operation': _signedOperation({
          'operation_id': const Uuid().v4(),
          'plan': {
            'id': planId,
            'asset_id': assetId,
            'title': 'Completion Contract Plan',
            'instructions': null,
            'recurrence_interval': 1,
            'recurrence_unit': 'months',
            'priority': 'medium',
            'next_due_date': dueDate,
            'reminder_days_before': 1,
            'is_enabled': true,
          },
        }),
      },
    );

    final planBefore = Map<String, dynamic>.from(
      await userADevice1
          .from('maintenance_plans')
          .select()
          .eq('id', planId)
          .single(),
    );
    final operation = <String, dynamic>{
      'contract_version': 1,
      'operation_id': recordId,
      'plan_id': planId,
      'occurrence_id': planBefore['current_occurrence_id'],
      'expected_plan_revision': planBefore['revision'],
      'completed_at': completedAt,
      'time_zone_id': 'UTC',
      'notes': null,
    };
    final gateway = SupabaseSyncGateway(userADevice1);
    final applied = await gateway.completeMaintenance(
      payloadJson: jsonEncode(operation),
      userId: userAId,
      deviceId: 'completion-contract-device',
    );
    expect(applied.status, MaintenanceCompletionStatus.applied);
    expect(applied.record?.recordKey, recordId);
    expect(
      DateTime.parse(applied.plan!.values['next_due_date'] as String),
      DateTime.parse(nextDueDate),
    );

    final replay = await gateway.completeMaintenance(
      payloadJson: jsonEncode(operation),
      userId: userAId,
      deviceId: 'completion-contract-device',
    );
    expect(replay.status, MaintenanceCompletionStatus.alreadyApplied);
    expect(replay.record?.recordKey, recordId);

    final crossUser = await SupabaseSyncGateway(userB).completeMaintenance(
      payloadJson: jsonEncode({
        ...operation,
        'operation_id': 'completion-contract-cross-user',
      }),
      userId: userBId,
      deviceId: 'cross-user-device',
    );
    expect(crossUser.status, MaintenanceCompletionStatus.invalid);
    expect(crossUser.conflictReason, 'plan_unavailable');

    const stalePlanId = 'completion-contract-stale-plan';
    await userADevice1.rpc<void>(
      'create_task_with_point_debit',
      params: {
        'p_operation': _signedOperation({
          'operation_id': const Uuid().v4(),
          'plan': {
            'id': stalePlanId,
            'asset_id': assetId,
            'title': 'Stale Completion Plan',
            'recurrence_interval': 1,
            'recurrence_unit': 'months',
            'priority': 'medium',
            'next_due_date': dueDate,
            'reminder_days_before': 1,
            'is_enabled': true,
          },
        }),
      },
    );
    final staleBefore = Map<String, dynamic>.from(
      await userADevice1
          .from('maintenance_plans')
          .select()
          .eq('id', stalePlanId)
          .single(),
    );
    final staleRevision = staleBefore['revision'];
    expect(staleRevision, isA<int>());
    await userADevice1
        .from('maintenance_plans')
        .update({'title': 'Revision advanced'})
        .eq('id', stalePlanId)
        .eq('revision', staleRevision as int);
    final staleCanonical = Map<String, dynamic>.from(
      await userADevice1
          .from('maintenance_plans')
          .select()
          .eq('id', stalePlanId)
          .single(),
    );
    final stale = await gateway.completeMaintenance(
      payloadJson: jsonEncode({
        'contract_version': 1,
        'operation_id': 'completion-contract-stale-record',
        'plan_id': stalePlanId,
        'occurrence_id': staleBefore['current_occurrence_id'],
        'expected_plan_revision': staleBefore['revision'],
        'completed_at': completedAt,
        'time_zone_id': 'UTC',
        'notes': null,
      }),
      userId: userAId,
      deviceId: 'completion-contract-device',
    );
    expect(stale.status, MaintenanceCompletionStatus.applied);
    expect(stale.retryable, isFalse);
    expect(stale.plan?.values['title'], 'Revision advanced');
    expect(stale.currentPlanRevision, staleCanonical['revision'] + 1);

    final hydrationDatabase = AppDatabase(executor: NativeDatabase.memory());
    final hydrationStore = LocalSyncStore(hydrationDatabase);
    await hydrationStore.account();
    await hydrationStore.setEnabled(enabled: true, boundUserId: userAId);
    await hydrationDatabase.delete(hydrationDatabase.syncOutbox).go();
    const hydrationRecordId = 'completion-contract-hydration-record';
    await hydrationDatabase
        .into(hydrationDatabase.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            entity: 'maintenance_completion',
            recordKey: hydrationRecordId,
            operation: 'execute',
            payloadJson: Value(
              jsonEncode({
                'contract_version': 1,
                'operation_id': hydrationRecordId,
                'plan_id': stalePlanId,
                'occurrence_id': 'next:completion-contract-stale-record',
                'expected_plan_revision': stale.currentPlanRevision,
                'completed_at': nextDueDate,
                'time_zone_id': 'UTC',
                'notes': null,
              }),
            ),
            changedAt: Value(DateTime.parse(completedAt)),
            attempts: const Value(0),
          ),
        );
    final hydrationCoordinator = SyncCoordinator(
      _StaticAuthRepository(userAId),
      hydrationStore,
      gateway,
      listenToAuthChanges: false,
    );
    addTearDown(() async {
      await hydrationCoordinator.dispose();
      await hydrationDatabase.close();
    });

    await hydrationCoordinator.syncNow();

    expect((await hydrationCoordinator.status()).phase, SyncPhase.ready);
    expect(await hydrationStore.pendingCount(), 0);
    expect(
      await userADevice1
          .from('maintenance_records')
          .select('id')
          .eq('id', hydrationRecordId),
      hasLength(1),
    );
    expect(
      await userB.from('maintenance_records').select('id').inFilter('id', [
        recordId,
        hydrationRecordId,
        'completion-contract-stale-record',
      ]),
      isEmpty,
    );
  });

  test('prepare-upload-finalize verifies Storage facts and owner isolation', () async {
    await userADevice1.from('rooms').insert({
      'user_id': userAId,
      'id': 'backend-room',
      'area_id': 'backend-area',
      'name': 'Backend Room',
      'sort_order': 0,
    });
    // Asset creation has no direct client INSERT authority (MON-001): the
    // fixture must use the same server-authoritative aggregate RPC the app
    // uses, so the baseline privilege revocation is exercised end to end.
    final operationId = const Uuid().v4();
    final unsignedOperation = <String, dynamic>{
      'operation_id': operationId,
      'asset': {
        'id': 'backend-asset',
        'room_id': 'backend-room',
        'name': 'Backend Asset',
        'asset_type': 'general',
      },
      'details': <String, dynamic>{},
      'initial_plans': <Map<String, dynamic>>[],
    };
    await userADevice1.rpc<dynamic>(
      'create_asset',
      params: {
        'p_operation': {
          ...unsignedOperation,
          'request_hash': sha256
              .convert(utf8.encode(jsonEncode(unsignedOperation)))
              .toString(),
        },
      },
    );

    const digest =
        '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a';
    final prepared = Map<String, dynamic>.from(
      await userADevice1.rpc<Map<String, dynamic>>(
        'prepare_asset_photo_upload',
        params: {
          'p_asset_id': 'backend-asset',
          'p_photo_id': 'backend-photo',
          'p_object_size': 4,
          'p_mime_type': 'image/jpeg',
          'p_client_sha256_digest': digest,
          'p_idempotency_key': 'local-backend-media-0001',
        },
      ) as Map,
    );
    final stagingPath = prepared['staging_path'] as String;
    final stagingId = prepared['staging_id'] as String;
    final bytes = Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]);
    await expectLater(
      userADevice1.storage
          .from('user-media')
          .uploadBinary(
            '$userAId/media/unprepared/0.jpg',
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          ),
      throwsA(isA<StorageException>()),
    );
    await userADevice1.storage
        .from('user-media')
        .uploadBinary(
          stagingPath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );

    final finalized = Map<String, dynamic>.from(
      await userADevice1.rpc<Map<String, dynamic>>(
        'finalize_asset_photo_upload',
        params: {
          'p_staging_id': stagingId,
          'p_asset_id': 'backend-asset',
          'p_photo_id': 'backend-photo',
          'p_expected_revision': 1,
        },
      ) as Map,
    );
    expect(finalized['digest_verification'], 'client_advisory');
    expect(
      await userADevice2.storage.from('user-media').download(stagingPath),
      bytes,
    );
    await expectLater(
      userB.storage.from('user-media').download(stagingPath),
      throwsA(isA<StorageException>()),
    );
    // Storage DELETE intentionally exposes no matching rows when the caller
    // lacks a DELETE policy. The HTTP API therefore returns an empty result
    // instead of an authorization exception; prove denial by checking both
    // the result and the still-downloadable live object.
    expect(
      await userADevice1.storage.from('user-media').remove([stagingPath]),
      isEmpty,
    );
    expect(
      await userADevice2.storage.from('user-media').download(stagingPath),
      bytes,
    );
    await expectLater(
      userB.rpc<void>(
        'prepare_asset_photo_upload',
        params: {
          'p_asset_id': 'backend-asset',
          'p_photo_id': 'cross-user-photo',
          'p_object_size': 4,
          'p_mime_type': 'image/jpeg',
          'p_client_sha256_digest': digest,
          'p_idempotency_key': 'cross-user-media-0001',
        },
      ),
      throwsA(isA<PostgrestException>()),
    );

    final expiring = Map<String, dynamic>.from(
      await userADevice1.rpc<Map<String, dynamic>>(
        'prepare_asset_photo_upload',
        params: {
          'p_asset_id': 'backend-asset',
          'p_photo_id': 'backend-expired-photo',
          'p_object_size': 4,
          'p_mime_type': 'image/jpeg',
          'p_client_sha256_digest': digest,
          'p_idempotency_key': 'local-backend-media-expired-0001',
        },
      ) as Map,
    );
    await admin
        .from('media_staging_objects')
        .update({
          'created_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 2))
              .toIso8601String(),
          'expires_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 1))
              .toIso8601String(),
        })
        .eq('id', expiring['staging_id'] as String);
    final refreshed = Map<String, dynamic>.from(
      await userADevice2.rpc<Map<String, dynamic>>(
        'prepare_asset_photo_upload',
        params: {
          'p_asset_id': 'backend-asset',
          'p_photo_id': 'backend-expired-photo',
          'p_object_size': 4,
          'p_mime_type': 'image/jpeg',
          'p_client_sha256_digest': digest,
          'p_idempotency_key': 'local-backend-media-expired-0001',
        },
      ) as Map,
    );
    expect(refreshed['staging_id'], expiring['staging_id']);
    expect(refreshed['attempt'], 1);
    expect(refreshed['staging_path'], isNot(expiring['staging_path']));
    await expectLater(
      userADevice1.storage
          .from('user-media')
          .uploadBinary(
            expiring['staging_path']! as String,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          ),
      throwsA(isA<StorageException>()),
    );
    await userADevice1.storage
        .from('user-media')
        .uploadBinary(
          refreshed['staging_path']! as String,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );

    final identicalPrepares = await Future.wait([
      for (var index = 0; index < 50; index++)
        (index.isEven ? userADevice1 : userADevice2)
            .rpc<Map<String, dynamic>>(
              'prepare_asset_photo_upload',
              params: {
                'p_asset_id': 'backend-asset',
                'p_photo_id': 'backend-identical-photo',
                'p_object_size': 4,
                'p_mime_type': 'image/jpeg',
                'p_client_sha256_digest': digest,
                'p_idempotency_key': 'local-backend-media-identical-0001',
              },
            )
            .then((value) => Map<String, dynamic>.from(value)),
    ]);
    expect(
      identicalPrepares.map((result) => result['staging_id']).toSet(),
      hasLength(1),
    );
    expect(
      identicalPrepares.map((result) => result['staging_path']).toSet(),
      hasLength(1),
    );
    final identicalRows = await admin
        .from('media_staging_objects')
        .select('id')
        .eq('user_id', userAId)
        .eq('idempotency_key', 'local-backend-media-identical-0001');
    expect(identicalRows, hasLength(1));

    await admin
        .from('media_staging_objects')
        .update({'status': 'failed'})
        .eq('user_id', userAId)
        .eq('status', 'staged');
    final stageResults = await Future.wait([
      for (var index = 0; index < 21; index++)
        userADevice1
            .rpc<Map<String, dynamic>>(
              'prepare_asset_photo_upload',
              params: {
                'p_asset_id': 'backend-asset',
                'p_photo_id': 'quota-photo-$index',
                'p_object_size': 1,
                'p_mime_type': 'image/jpeg',
                'p_client_sha256_digest': digest,
                'p_idempotency_key':
                    'local-backend-quota-${index.toString().padLeft(4, '0')}',
              },
            )
            .then<Object>((value) => value)
            .catchError((Object error) => error),
    ]);
    expect(stageResults.whereType<PostgrestException>(), hasLength(1));
    expect(stageResults.whereType<Map<String, dynamic>>(), hasLength(20));

    await admin
        .from('media_staging_objects')
        .update({'status': 'failed'})
        .eq('user_id', userAId)
        .eq('status', 'staged');
    final byteQuotaResults = await Future.wait([
      for (var index = 0; index < 11; index++)
        userADevice2
            .rpc<Map<String, dynamic>>(
              'prepare_asset_photo_upload',
              params: {
                'p_asset_id': 'backend-asset',
                'p_photo_id': 'byte-quota-photo-$index',
                'p_object_size': 10 * 1024 * 1024,
                'p_mime_type': 'image/jpeg',
                'p_client_sha256_digest': digest,
                'p_idempotency_key':
                    'local-backend-byte-quota-${index.toString().padLeft(4, '0')}',
              },
            )
            .then<Object>((value) => value)
            .catchError((Object error) => error),
    ]);
    expect(byteQuotaResults.whereType<PostgrestException>(), hasLength(1));
    expect(byteQuotaResults.whereType<Map<String, dynamic>>(), hasLength(10));
  });

  test('authoritative copy, move, and type changes conserve points under concurrency', () async {
    await userADevice1.from('areas').insert({
      'user_id': userAId,
      'id': 'economy-area',
      'name': 'Economy Area',
      'kind': 'indoor',
      'sort_order': 0,
    });
    await userADevice1.from('rooms').insert({
      'user_id': userAId,
      'id': 'economy-room',
      'area_id': 'economy-area',
      'name': 'Economy Room',
      'sort_order': 0,
    });
    final sourceAssetOperation = _signedOperation({
      'operation_id': const Uuid().v4(),
      'asset': {
        'id': 'economy-safety-source',
        'room_id': 'economy-room',
        'name': 'Smoke alarm',
        'asset_type': 'safety',
      },
      'details': <String, dynamic>{},
      'initial_plans': <Map<String, dynamic>>[],
    });
    final targetAssetOperation = _signedOperation({
      'operation_id': const Uuid().v4(),
      'asset': {
        'id': 'economy-general-target',
        'room_id': 'economy-room',
        'name': 'General item',
        'asset_type': 'general',
      },
      'details': <String, dynamic>{},
      'initial_plans': <Map<String, dynamic>>[],
    });
    await userADevice1.rpc<void>(
      'create_asset',
      params: {'p_operation': sourceAssetOperation},
    );
    await userADevice1.rpc<void>(
      'create_asset',
      params: {'p_operation': targetAssetOperation},
    );
    final taskOperation = _signedOperation({
      'operation_id': const Uuid().v4(),
      'plan': {
        'id': 'economy-source-task',
        'asset_id': 'economy-safety-source',
        'title': 'Test alarm',
        'recurrence_interval': 1,
        'recurrence_unit': 'months',
        'priority': 'high',
        'next_due_date': '2026-12-01T00:00:00Z',
      },
    });
    await userADevice1.rpc<void>(
      'create_task_with_point_debit',
      params: {'p_operation': taskOperation},
    );

    final copyOperation = _signedOperation({
      'operation_id': const Uuid().v4(),
      'source_asset_id': 'economy-safety-source',
      'target_asset_id': 'economy-copy-target',
      'destination_room_id': 'economy-room',
      'include_tasks': true,
      'plan_id_map': {'economy-source-task': 'economy-copy-task'},
    });
    final copyResults = await Future.wait([
      userADevice1.rpc<Map<String, dynamic>>(
        'copy_asset',
        params: {'p_operation': copyOperation},
      ),
      userADevice2.rpc<Map<String, dynamic>>(
        'copy_asset',
        params: {'p_operation': copyOperation},
      ),
    ]);
    expect(
      copyResults.where((result) => result['already_processed'] == false),
      hasLength(1),
    );
    expect(
      await userADevice1
          .from('assets')
          .select('id')
          .eq('id', 'economy-copy-target'),
      hasLength(1),
    );
    expect(
      await userADevice1
          .from('maintenance_plans')
          .select('id')
          .eq('id', 'economy-copy-task'),
      hasLength(1),
    );

    final walletBefore = Map<String, dynamic>.from(
      await userADevice1
          .from('point_wallets')
          .select('balance')
          .eq('user_id', userAId)
          .single(),
    );
    final quote = Map<String, dynamic>.from(
      await userADevice1.rpc<Map<String, dynamic>>(
        'quote_maintenance_plan_move',
        params: {
          'p_plan_id': 'economy-copy-task',
          'p_target_asset_id': 'economy-general-target',
        },
      ) as Map,
    );
    expect(quote['charge'], 1);
    final moveOperation = _signedOperation({
      'operation_id': const Uuid().v4(),
      'plan_id': 'economy-copy-task',
      'target_asset_id': 'economy-general-target',
      'expected_plan_revision': quote['plan_revision'],
      'max_charge': quote['charge'],
    });
    final moveResults = await Future.wait([
      userADevice1.rpc<Map<String, dynamic>>(
        'move_maintenance_plan_with_point_delta',
        params: {'p_operation': moveOperation},
      ),
      userADevice2.rpc<Map<String, dynamic>>(
        'move_maintenance_plan_with_point_delta',
        params: {'p_operation': moveOperation},
      ),
    ]);
    expect(
      moveResults.where((result) => result['already_processed'] == false),
      hasLength(1),
    );
    final walletAfter = Map<String, dynamic>.from(
      await userADevice1
          .from('point_wallets')
          .select('balance')
          .eq('user_id', userAId)
          .single(),
    );
    expect(walletAfter['balance'], (walletBefore['balance'] as int) - 1);
    await expectLater(
      userADevice1
          .from('maintenance_plans')
          .update({'asset_id': 'economy-safety-source'})
          .eq('id', 'economy-copy-task'),
      throwsA(isA<PostgrestException>()),
    );
    await expectLater(
      userADevice1
          .from('assets')
          .update({'asset_type': 'safety'})
          .eq('id', 'economy-general-target'),
      throwsA(isA<PostgrestException>()),
    );

    await userADevice1.rpc<void>(
      'create_asset',
      params: {
        'p_operation': _signedOperation({
          'operation_id': const Uuid().v4(),
          'asset': {
            'id': 'economy-race-safety',
            'room_id': 'economy-room',
            'name': 'Race alarm',
            'asset_type': 'safety',
          },
          'details': <String, dynamic>{},
          'initial_plans': <Map<String, dynamic>>[],
        }),
      },
    );
    await userADevice1.rpc<void>(
      'create_task_with_point_debit',
      params: {
        'p_operation': _signedOperation({
          'operation_id': const Uuid().v4(),
          'plan': {
            'id': 'economy-race-task',
            'asset_id': 'economy-race-safety',
            'title': 'Race alarm test',
            'recurrence_interval': 1,
            'recurrence_unit': 'months',
            'priority': 'high',
            'next_due_date': '2027-01-01T00:00:00Z',
          },
        }),
      },
    );
    final raceMoveQuote = Map<String, dynamic>.from(
      await userADevice1.rpc<Map<String, dynamic>>(
        'quote_maintenance_plan_move',
        params: {
          'p_plan_id': 'economy-race-task',
          'p_target_asset_id': 'economy-race-safety',
        },
      ) as Map,
    );
    final raceTypeQuote = Map<String, dynamic>.from(
      await userADevice1.rpc<Map<String, dynamic>>(
        'quote_asset_type_change',
        params: {
          'p_asset_id': 'economy-race-safety',
          'p_target_type': 'general',
        },
      ) as Map,
    );
    expect(raceMoveQuote['charge'], 0);
    expect(raceTypeQuote['charge'], 1);
    final raceBalanceBefore = Map<String, dynamic>.from(
      await userADevice1
          .from('point_wallets')
          .select('balance')
          .eq('user_id', userAId)
          .single(),
    );
    final raceMove = _signedOperation({
      'operation_id': const Uuid().v4(),
      'plan_id': 'economy-race-task',
      'target_asset_id': 'economy-race-safety',
      'expected_plan_revision': raceMoveQuote['plan_revision'],
      'max_charge': raceMoveQuote['charge'],
    });
    final raceType = _signedOperation({
      'operation_id': const Uuid().v4(),
      'asset_id': 'economy-race-safety',
      'target_type': 'general',
      'details': <String, dynamic>{},
      'expected_asset_revision': raceTypeQuote['asset_revision'],
      'max_charge': raceTypeQuote['charge'],
    });
    final raceResults = await Future.wait([
      userADevice1.rpc<Map<String, dynamic>>(
        'move_maintenance_plan_with_point_delta',
        params: {'p_operation': raceMove},
      ),
      userADevice2.rpc<Map<String, dynamic>>(
        'change_asset_type_with_point_delta',
        params: {'p_operation': raceType},
      ),
    ]).timeout(const Duration(seconds: 15));
    expect(
      raceResults.map((result) => result['status']),
      everyElement('applied'),
    );
    expect(
      raceResults.fold<int>(
        0,
        (total, result) => total + (result['charged'] as int),
      ),
      1,
    );
    final raceBalanceAfter = Map<String, dynamic>.from(
      await userADevice1
          .from('point_wallets')
          .select('balance')
          .eq('user_id', userAId)
          .single(),
    );
    expect(
      raceBalanceAfter['balance'],
      (raceBalanceBefore['balance'] as int) - 1,
    );
    final raceDebits = await userADevice1
        .from('point_transactions')
        .select('amount,transaction_type,reference_id')
        .eq('transaction_type', 'task_entitlement_upgrade')
        .eq('reference_id', 'economy-race-safety');
    expect(raceDebits, hasLength(1));
    expect(raceDebits.single['amount'], -1);
    expect(
      (await userADevice1
          .from('maintenance_plans')
          .select('asset_id')
          .eq('id', 'economy-race-task')
          .single())['asset_id'],
      'economy-race-safety',
    );
    expect(
      (await userADevice1
          .from('assets')
          .select('asset_type')
          .eq('id', 'economy-race-safety')
          .single())['asset_type'],
      'general',
    );
  });

  test(
    'maintenance history restore merges exact rows and preserves conflicts',
    () async {
      await userADevice1.from('areas').insert({
        'user_id': userAId,
        'id': 'restore-api-area',
        'name': 'Restore API Area',
        'kind': 'indoor',
        'sort_order': 0,
      });
      await userADevice1.from('rooms').insert({
        'user_id': userAId,
        'id': 'restore-api-room',
        'area_id': 'restore-api-area',
        'name': 'Restore API Room',
        'sort_order': 0,
      });
      await userADevice1.rpc<void>(
        'create_asset',
        params: {
          'p_operation': _signedOperation({
            'operation_id': const Uuid().v4(),
            'asset': {
              'id': 'restore-api-asset',
              'room_id': 'restore-api-room',
              'name': 'Restore API Asset',
              'asset_type': 'general',
            },
            'details': <String, dynamic>{},
            'initial_plans': <Map<String, dynamic>>[],
          }),
        },
      );
      await userADevice1.rpc<void>(
        'create_task_with_point_debit',
        params: {
          'p_operation': _signedOperation({
            'operation_id': const Uuid().v4(),
            'plan': {
              'id': 'restore-api-plan',
              'asset_id': 'restore-api-asset',
              'title': 'Restore plan',
              'recurrence_interval': 1,
              'recurrence_unit': 'months',
              'priority': 'medium',
              'next_due_date': '2026-12-01T00:00:00Z',
            },
          }),
        },
      );
      final plan = Map<String, dynamic>.from(
        await userADevice1
            .from('maintenance_plans')
            .select(
              'id,asset_id,recurrence_interval,recurrence_unit,next_due_date,is_enabled,archived_at,revision',
            )
            .eq('id', 'restore-api-plan')
            .single(),
      );
      final restoreOperation = _signedOperation({
        'version': 1,
        'operation_id': const Uuid().v4(),
        'plan_id': 'restore-api-plan',
        'expected_plan_revision': plan['revision'],
        'plan_snapshot': {
          'asset_id': plan['asset_id'],
          'recurrence_interval': plan['recurrence_interval'],
          'recurrence_unit': plan['recurrence_unit'],
          'next_due_date': plan['next_due_date'],
          'is_enabled': plan['is_enabled'],
          'archived_at': plan['archived_at'],
        },
        'records': [
          {
            'id': 'restore-api-record',
            'operation_id': 'restore-api-record',
            'plan_id': 'restore-api-plan',
            'occurrence_id': 'restore-api-occurrence',
            'due_date': '2026-11-01T00:00:00Z',
            'completed_at': '2026-11-02T00:00:00Z',
            'accepted_at': '2026-11-02T00:00:00Z',
            'time_zone_id': 'UTC',
            'notes': 'exact backup note',
            'created_at': '2026-11-02T00:00:00Z',
            'revision': 1,
          },
        ],
      });
      final results = await Future.wait([
        userADevice1.rpc<Map<String, dynamic>>(
          'restore_maintenance_history',
          params: {
            'p_operation': restoreOperation,
            'p_device_id': 'restore-device-a',
          },
        ),
        userADevice2.rpc<Map<String, dynamic>>(
          'restore_maintenance_history',
          params: {
            'p_operation': restoreOperation,
            'p_device_id': 'restore-device-b',
          },
        ),
      ]);
      expect(results.every((result) => result['status'] == 'applied'), isTrue);
      expect(
        results.where((result) => result['already_processed'] == false),
        hasLength(1),
      );
      expect(
        await userADevice1
            .from('maintenance_records')
            .select('id')
            .eq('id', 'restore-api-record'),
        hasLength(1),
      );

      final conflictOperation = _signedOperation({
        ...Map<String, dynamic>.from(restoreOperation)
          ..remove('request_hash')
          ..['operation_id'] = const Uuid().v4(),
        'records': [
          {
            ...(restoreOperation['records']! as List).single as Map,
            'notes': 'divergent backup note',
          },
        ],
      });
      final conflict = await userADevice1.rpc<Map<String, dynamic>>(
        'restore_maintenance_history',
        params: {
          'p_operation': conflictOperation,
          'p_device_id': 'restore-device-a',
        },
      );
      expect(conflict['status'], 'conflict');
      expect(conflict['conflict_reason'], 'history_record_conflict');
      await expectLater(
        userADevice1.from('maintenance_records').insert({
          'user_id': userAId,
          'id': 'direct-history-bypass',
          'plan_id': 'restore-api-plan',
          'due_date': '2026-11-01T00:00:00Z',
          'completed_at': '2026-11-02T00:00:00Z',
        }),
        throwsA(isA<PostgrestException>()),
      );
      await expectLater(
        userB.rpc<Map<String, dynamic>>(
          'restore_maintenance_history',
          params: {
            'p_operation': restoreOperation,
            'p_device_id': 'cross-user-device',
          },
        ),
        throwsA(isA<PostgrestException>()),
      );
    },
  );
}
