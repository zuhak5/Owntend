import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/sync/observed_sync_repository.dart';
import 'package:owntend/src/core/sync/sync_contracts.dart';

void main() {
  test('forwards public sync operations without changing behavior', () async {
    final delegate = _FakeCloudSyncRepository();
    final repository = ObservedCloudSyncRepository(delegate);

    expect((await repository.status()).phase, SyncPhase.ready);
    await repository.enable();
    await repository.disable();
    await repository.unlink();
    await repository.retry();
    await repository.fullReconcile();
    await repository.syncNow();

    expect(delegate.calls, [
      'status',
      'enable',
      'disable',
      'unlink',
      'retry',
      'fullReconcile',
      'syncNow',
    ]);
  });

  test('forwards status stream values', () async {
    final delegate = _FakeCloudSyncRepository();
    final repository = ObservedCloudSyncRepository(delegate);

    final statuses = await repository.watchStatus().toList();

    expect(statuses, hasLength(1));
    expect(statuses.single.phase, SyncPhase.ready);
    expect(delegate.calls, ['watchStatus']);
  });

  test('preserves delegate failures', () async {
    final delegate = _FakeCloudSyncRepository(failSyncNow: true);
    final repository = ObservedCloudSyncRepository(delegate);

    await expectLater(repository.syncNow(), throwsA(isA<StateError>()));
  });
}

class _FakeCloudSyncRepository implements CloudSyncRepository {
  _FakeCloudSyncRepository({this.failSyncNow = false});

  final bool failSyncNow;
  final List<String> calls = [];

  @override
  Future<void> disable() async {
    calls.add('disable');
  }

  @override
  Future<void> enable() async {
    calls.add('enable');
  }

  @override
  Future<void> fullReconcile() async {
    calls.add('fullReconcile');
  }

  @override
  Future<void> resumeRestoredSnapshotToCloud() async {
    calls.add('resumeRestoredSnapshotToCloud');
  }

  @override
  Future<void> retry() async {
    calls.add('retry');
  }

  @override
  Future<SyncStatus> status() async {
    calls.add('status');
    return const SyncStatus(phase: SyncPhase.ready, enabled: true);
  }

  @override
  Future<void> syncNow() async {
    calls.add('syncNow');
    if (failSyncNow) throw StateError('controlled sync failure');
  }

  @override
  Future<void> unlink() async {
    calls.add('unlink');
  }

  @override
  Stream<SyncStatus> watchStatus() async* {
    calls.add('watchStatus');
    yield const SyncStatus(phase: SyncPhase.ready, enabled: true);
  }
}
