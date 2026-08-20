import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/data/reactive_stream.dart';
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/supabase_sync_gateway.dart';
import 'package:owntend/src/core/sync/sync_connectivity.dart';
import 'package:owntend/src/core/sync/sync_coordinator.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('local domain mutations propagate through Drift providers without a loading gap', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final assets = DriftAssetRepository(db);
    final maintenance = DriftMaintenanceRepository(db);

    final areaId = await assets.saveArea(name: 'Home', kind: AreaKind.indoor);
    final roomId = await assets.saveRoom(areaId: areaId, name: 'Utility');
    final assetId = await assets.saveAsset(
      name: 'Water heater',
      roomId: roomId,
    );
    final due = DateTime.utc(2026, 8, 20, 9);
    final planId = await maintenance.savePlan(
      assetId: assetId,
      title: 'Inspect heater',
      recurrence: const RecurrenceRule(
        interval: 1,
        unit: RecurrenceUnit.months,
      ),
      priority: PriorityLevel.medium,
      nextDueDate: due,
    );

    final container = ProviderContainer(
      overrides: [
        assetRepositoryProvider.overrideWithValue(assets),
        maintenanceRepositoryProvider.overrideWithValue(maintenance),
      ],
    );
    addTearDown(container.dispose);

    final roomStates = <AsyncValue<List<Room>>>[];
    final assetStates = <AsyncValue<List<Asset>>>[];
    final taskStates = <AsyncValue<List<TaskItem>>>[];
    final roomSubscription = container.listen(
      roomsProvider,
      (_, next) => roomStates.add(next),
      fireImmediately: true,
    );
    final assetSubscription = container.listen(
      assetsProvider,
      (_, next) => assetStates.add(next),
      fireImmediately: true,
    );
    final taskSubscription = container.listen(
      tasksProvider,
      (_, next) => taskStates.add(next),
      fireImmediately: true,
    );
    final recordSubscription = container.listen(
      taskRecordsProvider(planId),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(roomSubscription.close);
    addTearDown(assetSubscription.close);
    addTearDown(taskSubscription.close);
    addTearDown(recordSubscription.close);

    await _eventually(() {
      return container.read(roomsProvider).value?.single.name == 'Utility' &&
          container.read(assetsProvider).value?.single.name == 'Water heater' &&
          container.read(tasksProvider).value?.single.plan.id == planId;
    });

    final roomPopulatedAt = _firstPopulatedIndex(roomStates);
    final assetPopulatedAt = _firstPopulatedIndex(assetStates);
    final taskPopulatedAt = _firstPopulatedIndex(taskStates);

    await assets.saveRoom(id: roomId, areaId: areaId, name: 'Mechanical room');
    await assets.saveAsset(
      name: 'Leak sensor',
      roomId: roomId,
      assetType: AssetType.safety,
    );
    final completion = await maintenance.completePlanResult(
      planId,
      completedAt: DateTime.utc(2026, 8, 20, 10),
      expectedNextDueDate: due,
    );
    expect(completion.isApplied, isTrue);

    await _eventually(() {
      final liveRooms = container.read(roomsProvider).value;
      final liveAssets = container.read(assetsProvider).value;
      final liveTasks = container.read(tasksProvider).value;
      final liveRecords = container.read(taskRecordsProvider(planId)).value;
      return liveRooms?.single.name == 'Mechanical room' &&
          liveAssets?.length == 2 &&
          liveTasks?.single.plan.nextDueDate.isAfter(due) == true &&
          liveRecords?.length == 1;
    });

    _expectNoPostPopulationGap(roomStates, roomPopulatedAt, 'rooms');
    _expectNoPostPopulationGap(assetStates, assetPopulatedAt, 'assets');
    _expectNoPostPopulationGap(taskStates, taskPopulatedAt, 'tasks');
  });

  test(
    'repository settle coalescing emits only the coherent aggregate',
    () async {
      final roomsChanged = StreamController<Object?>.broadcast();
      final assetsChanged = StreamController<Object?>.broadcast();
      addTearDown(roomsChanged.close);
      addTearDown(assetsChanged.close);

      var aggregate = const _AggregateSnapshot(room: 'old', asset: 'old');
      final emissions = <_AggregateSnapshot>[];
      final subscription = watchReloaded<_AggregateSnapshot>(
        triggers: [roomsChanged.stream, assetsChanged.stream],
        load: () async => aggregate,
        fingerprint: (value) => Object.hash(value.room, value.asset),
      ).listen(emissions.add);
      addTearDown(subscription.cancel);

      await _eventually(() => emissions.length == 1);
      expect(
        emissions.single,
        const _AggregateSnapshot(room: 'old', asset: 'old'),
      );

      aggregate = const _AggregateSnapshot(room: 'new', asset: 'old');
      roomsChanged.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      aggregate = const _AggregateSnapshot(room: 'new', asset: 'new');
      assetsChanged.add(null);

      await _eventually(() => emissions.length == 2);
      expect(emissions, const [
        _AggregateSnapshot(room: 'old', asset: 'old'),
        _AggregateSnapshot(room: 'new', asset: 'new'),
      ]);
    },
  );

  test(
    'Home and Rooms keep runtime domain authority in live providers',
    () async {
      final dashboard = await File(
        'lib/src/features/dashboard/presentation/dashboard_screen.dart',
      ).readAsString();
      final rooms = await File(
        'lib/src/features/rooms/presentation/rooms_screen.dart',
      ).readAsString();
      final reactiveStream = await File(
        'lib/src/core/data/reactive_stream.dart',
      ).readAsString();

      expect(dashboard, isNot(contains('_HomeRenderData')));
      expect(dashboard, isNot(contains('_homeDataTimer')));
      expect(dashboard, isNot(contains('_homeDataSettleDuration')));
      expect(dashboard, isNot(contains('ref.listenManual(tasksProvider')));
      expect(dashboard, isNot(contains('ref.listenManual(assetsProvider')));
      expect(dashboard, isNot(contains('ref.listenManual(roomsProvider')));

      final taskLiveRead = dashboard.indexOf('ref.watch(tasksProvider).value');
      final taskSeedFallback = dashboard.indexOf('startupSnapshot?.tasks');
      final assetLiveRead = dashboard.indexOf(
        'ref.watch(assetsProvider).value',
      );
      final assetSeedFallback = dashboard.indexOf('startupSnapshot?.assets');
      final roomLiveRead = dashboard.indexOf('ref.watch(roomsProvider).value');
      final roomSeedFallback = dashboard.indexOf('startupSnapshot?.rooms');
      expect(taskLiveRead, greaterThanOrEqualTo(0));
      expect(taskLiveRead, lessThan(taskSeedFallback));
      expect(assetLiveRead, lessThan(assetSeedFallback));
      expect(roomLiveRead, lessThan(roomSeedFallback));

      expect(rooms, isNot(contains('_RoomsRenderData')));
      expect(rooms, isNot(contains('_roomsDataTimer')));
      expect(rooms, isNot(contains('_roomsDataSettleDuration')));
      expect(rooms, contains('ref.watch(areasProvider)'));
      expect(rooms, contains('ref.watch(roomsProvider).value'));
      expect(rooms, contains('ref.watch(assetsProvider).value'));
      expect(rooms, contains('ref.watch(tasksProvider).value'));

      expect(
        reactiveStream,
        contains('const databaseSettleDuration = Duration(milliseconds: 120);'),
        reason:
            'Problem #8 removes the duplicate screen delay before changing the '
            'repository transaction-coalescing boundary.',
      );
    },
  );

  test('recent-sync resume performs a broad pull and repairs a missed remote change', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.account();
    await store.setEnabled(enabled: true, boundUserId: 'user-1');
    await store.recordSyncSuccess(
      DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
    );
    await store.recordIntegrityCheck(DateTime.now().toUtc());
    await db.delete(db.syncOutbox).go();

    final gateway = _RecordingSyncGateway();
    final coordinator = SyncCoordinator(
      _TestAuthRepository(const AuthSession(userId: 'user-1')),
      store,
      gateway,
      connectivity: const AlwaysOnlineSyncConnectivity(),
      listenToAuthChanges: false,
    );
    addTearDown(coordinator.dispose);

    // Let the coordinator's normal startup automatic pass finish first so
    // the change below is genuinely missed until the explicit resume hook.
    await coordinator.syncNow();
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    gateway.resetCounters();

    final changedAt = DateTime.now().toUtc();
    gateway.remoteSetting = SyncRecord(
      spec: userSettingSyncSpec,
      recordKey: 'theme',
      values: {
        'key': 'theme',
        'value': 'dark',
        'updated_at': changedAt.toIso8601String(),
      },
      clientModifiedAt: changedAt,
      originDeviceId: 'peer-device',
      revision: 2,
      syncSeq: changedAt.microsecondsSinceEpoch,
      serverUpdatedAt: changedAt,
    );

    await coordinator.onAppResumed();

    await _eventually(() async {
      final row = await db
          .customSelect("SELECT value FROM settings WHERE key = 'theme'")
          .getSingleOrNull();
      return gateway.feedCapabilityCalls > 0 &&
          gateway.pullCalls > 0 &&
          row?.read<String>('value') == 'dark';
    });

    expect(
      gateway.pulledTables,
      contains(userSettingSyncSpec.remoteTable),
      reason:
          'A lastSyncedAt inside the old 15-minute window must not turn '
          'resume convergence into push-only work.',
    );
  });
}

int _firstPopulatedIndex<T>(List<AsyncValue<List<T>>> states) {
  final index = states.indexWhere((state) => state.value?.isNotEmpty == true);
  expect(index, greaterThanOrEqualTo(0));
  return index;
}

void _expectNoPostPopulationGap<T>(
  List<AsyncValue<List<T>>> states,
  int populatedAt,
  String label,
) {
  for (final state in states.skip(populatedAt)) {
    expect(
      state.value,
      isNotNull,
      reason: '$label must retain its last-good data during live updates.',
    );
    expect(
      state.value,
      isNotEmpty,
      reason:
          '$label must not flash an empty collection after it is populated.',
    );
  }
}

Future<void> _eventually(FutureOr<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('Condition was not met before the timeout.');
}

class _AggregateSnapshot {
  const _AggregateSnapshot({required this.room, required this.asset});

  final String room;
  final String asset;

  @override
  bool operator ==(Object other) {
    return other is _AggregateSnapshot &&
        other.room == room &&
        other.asset == asset;
  }

  @override
  int get hashCode => Object.hash(room, asset);
}

class _TestAuthRepository implements AuthRepository {
  const _TestAuthRepository(this.session);

  final AuthSession session;

  @override
  AuthSession? get currentSession => session;

  @override
  Stream<AuthStateChange> watchAuthState() => const Stream.empty();

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut({bool allDevices = false}) async {}
}

class _RecordingSyncGateway extends SupabaseSyncGateway {
  _RecordingSyncGateway()
    : super(SupabaseClient('http://localhost', 'problem-008-test-key'));

  SyncRecord? remoteSetting;
  int feedCapabilityCalls = 0;
  int pullCalls = 0;
  final Set<String> pulledTables = <String>{};

  void resetCounters() {
    feedCapabilityCalls = 0;
    pullCalls = 0;
    pulledTables.clear();
  }

  @override
  Future<SyncFeedCapability> getSyncFeedCapability() async {
    feedCapabilityCalls++;
    return const SyncFeedCapability(
      enabled: false,
      capabilityVersion: '1.0.1',
      minRetainedSeq: 0,
    );
  }

  @override
  Future<List<SyncRecord>> pullChanges({
    required SyncEntitySpec spec,
    required String userId,
    required String deviceId,
    required int afterSyncSeq,
    String? afterRecordKey,
    void Function(int exactCount)? onExactCount,
    bool materializeMedia = true,
  }) async {
    pullCalls++;
    pulledTables.add(spec.remoteTable);
    final candidate = remoteSetting;
    final records =
        candidate != null &&
            spec.entity == userSettingSyncSpec.entity &&
            (candidate.syncSeq ?? 0) > afterSyncSeq
        ? <SyncRecord>[candidate]
        : const <SyncRecord>[];
    onExactCount?.call(records.length);
    return records;
  }
}
