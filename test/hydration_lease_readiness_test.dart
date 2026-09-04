import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/wait_for.dart';

import 'package:mocktail/mocktail.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/supabase/supabase_failure.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/supabase_sync_gateway.dart';
import 'package:owntend/src/core/sync/sync_coordinator.dart';
import 'package:owntend/src/core/sync/sync_contracts.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';

class _MockGateway extends Mock implements SupabaseSyncGateway {}

class _MutableAuthRepository implements AuthRepository {
  _MutableAuthRepository(this.session);

  AuthSession? session;
  final _controller = StreamController<AuthStateChange>.broadcast();

  @override
  AuthSession? get currentSession => session;

  @override
  Stream<AuthStateChange> watchAuthState() => _controller.stream;

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut({bool allDevices = false}) async {
    session = null;
  }

  @override
  Future<void> deleteAccount() async {
    session = null;
  }

  Future<void> dispose() => _controller.close();
}

void main() {
  setUpAll(() {
    registerFallbackValue(syncEntitySpecs.first);
    registerFallbackValue(
      SyncRecord(
        spec: syncEntitySpecs.first,
        recordKey: 'fallback',
        values: const {},
        clientModifiedAt: DateTime.utc(2026),
        originDeviceId: 'fallback-device',
      ),
    );
    registerFallbackValue(<SyncRecord>[]);
  });

  test('lease miss waits for durable hydration completed elsewhere', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.bindIdentity('user-a');
    expect(
      await store.acquireLease(
        'background-worker',
        duration: const Duration(seconds: 2),
      ),
      isTrue,
    );

    final auth = _MutableAuthRepository(const AuthSession(userId: 'user-a'));
    addTearDown(auth.dispose);
    final gateway = _MockGateway();
    final coordinator = SyncCoordinator(
      auth,
      store,
      gateway,
      listenToAuthChanges: false,
      autoEnableOnAuthChange: false,
      initialHydrationLeaseRetryDelay: const Duration(milliseconds: 10),
      initialHydrationLeaseWaitTimeout: const Duration(seconds: 1),
    );
    addTearDown(coordinator.dispose);

    var completed = false;
    final enableFuture = coordinator.enable().then((_) {
      completed = true;
    });
    await _waitForPhase(coordinator, SyncPhase.waitingForSyncLease);

    expect(completed, isFalse);
    expect(await store.hasCompleteSnapshotForUser('user-a'), isFalse);

    final hydration = await store.beginOrResumeHydration();
    await store.completeInitialHydration(
      DateTime.now().toUtc(),
      expectedRunId: hydration.runId,
    );

    await enableFuture.timeout(const Duration(seconds: 1));
    expect(completed, isTrue);
    expect(await store.hasCompleteSnapshotForUser('user-a'), isTrue);
    expect((await coordinator.status()).phase, SyncPhase.ready);
  });

  test(
    'expired competing lease is retried and foreground hydration completes',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = LocalSyncStore(db);
      await store.bindIdentity('user-a');
      expect(
        await store.acquireLease(
          'crashed-background-worker',
          duration: const Duration(seconds: 1),
        ),
        isTrue,
      );

      final auth = _MutableAuthRepository(const AuthSession(userId: 'user-a'));
      addTearDown(auth.dispose);
      final gateway = _MockGateway();
      _stubEmptyCloud(gateway);
      final coordinator = SyncCoordinator(
        auth,
        store,
        gateway,
        listenToAuthChanges: false,
        autoEnableOnAuthChange: false,
        initialHydrationLeaseRetryDelay: const Duration(milliseconds: 10),
        initialHydrationLeaseWaitTimeout: const Duration(seconds: 3),
      );
      addTearDown(coordinator.dispose);

      var completed = false;
      final enableFuture = coordinator.enable().then((_) {
        completed = true;
      });
      await _waitForPhase(coordinator, SyncPhase.waitingForSyncLease);
      expect(completed, isFalse);
      expect(await store.hasCompleteSnapshotForUser('user-a'), isFalse);

      await enableFuture.timeout(const Duration(seconds: 3));

      expect(completed, isTrue);
      expect(await store.hasCompleteSnapshotForUser('user-a'), isTrue);
      expect((await coordinator.status()).phase, SyncPhase.ready);
    },
  );

  test(
    'bounded lease wait fails without publishing durable readiness',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = LocalSyncStore(db);
      await store.bindIdentity('user-a');
      expect(
        await store.acquireLease(
          'stuck-background-worker',
          duration: const Duration(seconds: 2),
        ),
        isTrue,
      );

      final auth = _MutableAuthRepository(const AuthSession(userId: 'user-a'));
      addTearDown(auth.dispose);
      final gateway = _MockGateway();
      final coordinator = SyncCoordinator(
        auth,
        store,
        gateway,
        listenToAuthChanges: false,
        autoEnableOnAuthChange: false,
        initialHydrationLeaseRetryDelay: const Duration(milliseconds: 10),
        initialHydrationLeaseWaitTimeout: const Duration(milliseconds: 80),
      );
      addTearDown(coordinator.dispose);

      await expectLater(
        coordinator.enable(),
        throwsA(
          isA<SupabaseFailure>()
              .having((failure) => failure.retryable, 'retryable', isTrue)
              .having(
                (failure) => failure.message,
                'message',
                contains('Another sync operation is still running'),
              ),
        ),
      );

      expect(await store.hasCompleteSnapshotForUser('user-a'), isFalse);
      expect((await coordinator.status()).phase, SyncPhase.waitingForSyncLease);
    },
  );

  test(
    'account switch while waiting for hydration lease fails closed',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = LocalSyncStore(db);
      await store.bindIdentity('user-a');
      expect(
        await store.acquireLease(
          'background-worker',
          duration: const Duration(seconds: 2),
        ),
        isTrue,
      );

      final auth = _MutableAuthRepository(const AuthSession(userId: 'user-a'));
      addTearDown(auth.dispose);
      final gateway = _MockGateway();
      final coordinator = SyncCoordinator(
        auth,
        store,
        gateway,
        listenToAuthChanges: false,
        autoEnableOnAuthChange: false,
        initialHydrationLeaseRetryDelay: const Duration(milliseconds: 10),
        initialHydrationLeaseWaitTimeout: const Duration(seconds: 1),
      );
      addTearDown(coordinator.dispose);

      final expectation = expectLater(
        coordinator.enable(),
        throwsA(
          isA<SupabaseFailure>().having(
            (failure) => failure.kind,
            'kind',
            SupabaseFailureKind.authentication,
          ),
        ),
      );
      await _waitForPhase(coordinator, SyncPhase.waitingForSyncLease);

      auth.session = const AuthSession(userId: 'user-b');
      await expectation;

      expect(await store.hasCompleteSnapshotForUser('user-a'), isFalse);
      expect(await store.hasCompleteSnapshotForUser('user-b'), isFalse);
      expect((await store.existingAccount())?.boundUserId, 'user-a');
    },
  );
}

void _stubEmptyCloud(_MockGateway gateway) {
  when(() => gateway.fetchUserChangeFeedHighWater())
      .thenAnswer((_) async => const UserChangeFeedWatermark(highWaterSeq: 0));
  when(
    () => gateway.fetchAuthoritativeRecordKeys(
      spec: any(named: 'spec'),
      userId: any(named: 'userId'),
      deviceId: any(named: 'deviceId'),
    ),
  ).thenAnswer((_) async => const {});
  when(
    () => gateway.pullAuthoritativeSnapshotPage(
      spec: any(named: 'spec'),
      userId: any(named: 'userId'),
      deviceId: any(named: 'deviceId'),
      afterRecordKey: any(named: 'afterRecordKey'),
      onExactCount: any(named: 'onExactCount'),
      materializeMedia: any(named: 'materializeMedia'),
    ),
  ).thenAnswer((invocation) async {
    final callback =
        invocation.namedArguments[#onExactCount] as void Function(int)?;
    callback?.call(0);
    return <SyncRecord>[];
  });

  when(
    () => gateway.writeNewBatch(
      records: any(named: 'records'),
      userId: any(named: 'userId'),
      deviceId: any(named: 'deviceId'),
    ),
  ).thenAnswer((invocation) async {
    final records = invocation.namedArguments[#records] as List<SyncRecord>;
    return BatchWriteSuccess(records);
  });

  when(
    () => gateway.write(
      record: any(named: 'record'),
      userId: any(named: 'userId'),
      deviceId: any(named: 'deviceId'),
      expectedRevision: any(named: 'expectedRevision'),
    ),
  ).thenAnswer((invocation) async {
    return RemoteWriteResult.applied(
      invocation.namedArguments[#record] as SyncRecord,
    );
  });
}

Future<void> _waitForPhase(
  SyncCoordinator coordinator,
  SyncPhase expected,
) async {
  // WP-015 (F-024): shared bounded helper replaces the wall-clock loop.
  await waitFor(
    () async => (await coordinator.status()).phase == expected,
    timeout: const Duration(seconds: 5),
    because: 'Sync phase did not become ${expected.name} before the timeout.',
  );
}
