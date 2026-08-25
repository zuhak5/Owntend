import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/sync_contracts.dart';

void main() {
  test('restore percentage is derived, bounded, and completed at 100', () {
    final timestamp = DateTime.utc(2026, 7, 20);
    final running = InitialHydrationProgress(
      runId: 'run',
      state: RestoreRunState.running,
      stage: InitialHydrationStage.restoringCloudData,
      completedUnits: 42,
      totalUnits: 100,
      startedAt: timestamp,
      updatedAt: timestamp,
    );
    expect(running.fraction, 0.42);
    expect(running.percentage, 42);

    final completed = InitialHydrationProgress(
      runId: 'run',
      state: RestoreRunState.completed,
      stage: InitialHydrationStage.finalizing,
      completedUnits: 4,
      totalUnits: 10,
      startedAt: timestamp,
      updatedAt: timestamp,
    );
    expect(completed.percentage, 100);
    expect(completed.isActive, isFalse);
  });

  test('hydration journal persists checkpoints, failure, and resume', () async {
    final database = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database);
    await store.account();

    final started = await store.beginOrResumeHydration();
    await store.setHydrationPlan(20);
    await store.addHydrationUnits(5);
    await store.setHydrationStage(InitialHydrationStage.restoringCloudData);
    // WP-010: cursor rows are arranged through Drift after the legacy
    // per-entity cursor API was deleted from LocalSyncStore.
    await store.db
        .into(store.db.syncCursors)
        .insertOnConflictUpdate(
          SyncCursorsCompanion.insert(
            entity: 'room',
            lastSyncSeq: const Value(1234),
            lastRecordKey: const Value('room-b'),
          ),
        );
    await store.failHydration('Network unavailable.');

    final relaunchedStore = LocalSyncStore(database);
    final retained = await relaunchedStore.hydrationProgress();
    expect(retained?.runId, started.runId);
    expect(retained?.state, RestoreRunState.failed);
    expect(retained?.stage, InitialHydrationStage.restoringCloudData);
    expect(retained?.completedUnits, 5);
    expect(retained?.totalUnits, 20);
    expect(retained?.percentage, 25);
    expect(retained?.failure, 'Network unavailable.');
    // WP-010: cursor rows are asserted through Drift after the legacy
    // per-entity cursor API was deleted from LocalSyncStore.
    final roomCursor = await (relaunchedStore.db.select(
      relaunchedStore.db.syncCursors,
    )..where((item) => item.entity.equals('room'))).getSingleOrNull();
    expect(roomCursor?.lastSyncSeq, 1234);
    expect(roomCursor?.lastRecordKey, 'room-b');

    final resumed = await relaunchedStore.beginOrResumeHydration();
    expect(resumed.runId, started.runId);
    expect(resumed.state, RestoreRunState.running);
    expect(resumed.percentage, 25);

    await relaunchedStore.setHydrationStage(InitialHydrationStage.connecting);
    expect(
      (await relaunchedStore.hydrationProgress())?.stage,
      InitialHydrationStage.restoringCloudData,
      reason: 'a resumed run must not visually move backwards',
    );

    await relaunchedStore.completeHydration();
    final completed = await relaunchedStore.hydrationProgress();
    expect(completed?.state, RestoreRunState.completed);
    expect(completed?.percentage, 100);
  });

  test('completed hydration is not restarted at zero', () async {
    final database = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database);
    await store.account();

    final started = await store.beginOrResumeHydration();
    await store.setHydrationPlan(4);
    await store.addHydrationUnits(4);
    await store.setHydrationStage(InitialHydrationStage.finalizing);
    await store.completeHydration();

    final resumed = await store.beginOrResumeHydration();
    expect(resumed.runId, started.runId);
    expect(resumed.state, RestoreRunState.completed);
    expect(resumed.percentage, 100);
  });

  test(
    'initial hydration finalization commits sync success atomically',
    () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      final store = LocalSyncStore(database);
      final completedAt = DateTime.utc(2026, 7, 26, 14);

      await store.account();
      final hydration = await store.beginOrResumeHydration();
      await store.setHydrationPlan(12);
      await store.addHydrationUnits(11);
      await store.setHydrationStage(InitialHydrationStage.finalizing);
      await store.completeInitialHydration(
        completedAt,
        expectedRunId: hydration.runId,
      );

      final account = await store.account();
      final progress = await store.hydrationProgress();
      expect(account.lastSyncedAt?.isAtSameMomentAs(completedAt), isTrue);
      expect(account.migrationState, 'active');
      expect(account.lastError, isNull);
      expect(account.blockedReason, isNull);
      expect(progress?.state, RestoreRunState.completed);
      expect(progress?.stage, InitialHydrationStage.finalizing);
      expect(progress?.percentage, 100);
    },
  );

  test(
    'finalization cannot publish sync success without a hydration run',
    () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      final store = LocalSyncStore(database);
      await store.account();

      await expectLater(
        store.completeInitialHydration(
          DateTime.utc(2026, 7, 26, 14),
          expectedRunId: 'missing-run',
        ),
        throwsStateError,
      );

      final account = await store.account();
      expect(account.lastSyncedAt, isNull);
      expect(await store.hydrationProgress(), isNull);
    },
  );

  test(
    'an old finalization attempt cannot commit after retry starts',
    () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      final store = LocalSyncStore(database);
      await store.account();

      final stale = await store.beginOrResumeHydration();
      await store.setHydrationPlan(10);
      await store.addHydrationUnits(9);
      await store.setHydrationStage(InitialHydrationStage.finalizing);
      await store.failHydration('Local snapshot commit timed out.');
      final current = await store.beginOrResumeHydration();

      expect(current.runId, isNot(stale.runId));
      expect(current.stage, InitialHydrationStage.finalizing);
      expect(current.percentage, greaterThanOrEqualTo(90));
      await expectLater(
        store.completeInitialHydration(
          DateTime.utc(2026, 7, 26, 14),
          expectedRunId: stale.runId,
        ),
        throwsStateError,
      );
      expect((await store.account()).lastSyncedAt, isNull);

      await store.completeInitialHydration(
        DateTime.utc(2026, 7, 26, 14, 1),
        expectedRunId: current.runId,
      );
      expect((await store.hydrationProgress())?.percentage, 100);
    },
  );

  test('same-user identity binding preserves hydration progress', () async {
    final database = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(database.close);
    final store = LocalSyncStore(database);

    await store.bindIdentity('user-a');
    final started = await store.beginOrResumeHydration();
    await store.setHydrationPlan(10);
    await store.addHydrationUnits(7);
    await store.setHydrationStage(InitialHydrationStage.syncingLocalChanges);

    await store.bindIdentity('user-a');

    final retained = await store.hydrationProgress();
    expect(retained?.runId, started.runId);
    expect(retained?.state, RestoreRunState.running);
    expect(retained?.stage, InitialHydrationStage.syncingLocalChanges);
    expect(retained?.percentage, 70);

    await store.completeHydration();
    final completed = await store.hydrationProgress();
    await store.bindIdentity('user-a');

    final afterDuplicateBind = await store.hydrationProgress();
    expect(afterDuplicateBind?.runId, completed?.runId);
    expect(afterDuplicateBind?.state, RestoreRunState.completed);
    expect(afterDuplicateBind?.percentage, 100);
  });
}
