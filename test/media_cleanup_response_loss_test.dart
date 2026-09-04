import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/supabase/supabase_failure.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/supabase_sync_gateway.dart';
import 'package:owntend/src/core/sync/sync_coordinator.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';

const _userId = '00000000-0000-0000-0000-000000000009';
const _assetId = 'asset-cleanup-loss';
const _photoId = 'photo-cleanup-loss';
const _cleanupPath = '$_userId/media/$_photoId.jpg';

class _AuthRepository implements AuthRepository {
  const _AuthRepository();

  @override
  AuthSession? get currentSession => const AuthSession(userId: _userId);

  @override
  Stream<AuthStateChange> watchAuthState() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PhotoDeleteResponseLossGateway implements SupabaseSyncGateway {
  var remotePhotoExists = true;
  var storageObjectExists = true;
  var loseDeleteResponseOnce = true;
  var loseStorageResponseOnce = true;
  var photoDeleteCalls = 0;
  var storageDeleteCalls = 0;

  @override
  Future<UserChangeFeedWatermark> fetchUserChangeFeedHighWater() async =>
      const UserChangeFeedWatermark(highWaterSeq: 0);

  @override
  Future<UserChangeFeedPage> fetchUserChangeFeed({
    int sinceSeq = 0,
    int limit = 100,
    int? expectedGeneration,
  }) async => UserChangeFeedPage(
    entries: const [],
    highWaterSeq: sinceSeq,
    nextSeq: sinceSeq,
    hasMore: false,
    resnapshotRequired: false,
  );

  @override
  Future<List<SyncRecord>> pullAuthoritativeSnapshotPage({
    required SyncEntitySpec spec,
    required String userId,
    required String deviceId,
    String? afterRecordKey,
    void Function(int exactCount)? onExactCount,
    bool materializeMedia = true,
  }) async {
    onExactCount?.call(0);
    return const [];
  }

  @override
  Future<Set<String>> fetchAuthoritativeRecordKeys({
    required SyncEntitySpec spec,
    required String userId,
    required String deviceId,
  }) async => const {};

  @override
  Future<RemoteWriteResult> write({
    required SyncRecord record,
    required String userId,
    required String deviceId,
    required int? expectedRevision,
    Map<String, dynamic>? bundledPayload,
  }) async {
    if (record.spec.entity != 'asset_photo' || !record.isDeleted) {
      return RemoteWriteResult.applied(record);
    }
    photoDeleteCalls++;
    expect(record.values['cleanup_object_path'], _cleanupPath);
    if (remotePhotoExists) {
      remotePhotoExists = false;
      if (loseDeleteResponseOnce) {
        loseDeleteResponseOnce = false;
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.offline,
          message: 'Photo delete committed but its response was lost.',
          retryable: true,
        );
      }
    }
    return const RemoteWriteResult.applied(
      null,
      cleanupObjectPaths: [_cleanupPath],
    );
  }

  @override
  Future<void> removeMediaObject(String objectPath, String userId) async {
    expect(userId, _userId);
    expect(objectPath, _cleanupPath);
    storageDeleteCalls++;
    if (storageObjectExists) {
      storageObjectExists = false;
      if (loseStorageResponseOnce) {
        loseStorageResponseOnce = false;
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.storage,
          message: 'Storage delete committed but its response was lost.',
          retryable: true,
        );
      }
    }
    // A repeated delete sees an already-absent object and succeeds, matching
    // the production gateway's Storage 404 normalization.
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _seedPhoto(AppDatabase db, LocalSyncStore store) async {
  await store.withOutboxSuppressed(() async {
    await db
        .into(db.areas)
        .insert(
          AreasCompanion.insert(
            id: 'area-cleanup-loss',
            name: 'Cleanup loss area',
            kind: 'indoor',
          ),
        );
    await db
        .into(db.rooms)
        .insert(
          RoomsCompanion.insert(
            id: 'room-cleanup-loss',
            areaId: 'area-cleanup-loss',
            name: 'Cleanup loss room',
          ),
        );
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: _assetId,
            name: 'Cleanup loss asset',
            roomId: 'room-cleanup-loss',
          ),
        );
    await db
        .into(db.assetPhotos)
        .insert(
          AssetPhotosCompanion.insert(
            id: _photoId,
            assetId: _assetId,
            relativePath: Value('media/$_assetId/$_photoId.jpeg'),
            cloudObjectPath: const Value(_cleanupPath),
          ),
        );
  });
  await db.delete(db.syncOutbox).go();
}

Future<void> _makeOutboxImmediatelyRetryable(AppDatabase db) async {
  await (db.update(db.syncOutbox)..where(
        (row) =>
            row.entity.equals('asset_photo') & row.recordKey.equals(_photoId),
      ))
      .write(
        const SyncOutboxCompanion(
          state: Value('pending'),
          nextAttemptAt: Value(null),
        ),
      );
}

Future<void> _makeCleanupImmediatelyRetryable(AppDatabase db) async {
  await (db.update(db.syncMediaCleanup)
        ..where((row) => row.objectPath.equals(_cleanupPath)))
      .write(const SyncMediaCleanupCompanion(nextAttemptAt: Value(null)));
}

void main() {
  test('photo delete survives server response loss, restart, and duplicate cleanup', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    var store = LocalSyncStore(db);
    await store.account();
    await store.setEnabled(
      enabled: true,
      boundUserId: _userId,
      migrationState: 'active',
    );
    await store.recordSyncSuccess(DateTime.utc(2026, 8, 17, 18));
    await store.recordIntegrityCheck(DateTime.utc(2026, 8, 17, 18));
    await _seedPhoto(db, store);

    await (db.delete(
      db.assetPhotos,
    )..where((row) => row.id.equals(_photoId))).go();
    final queued = (await store.pendingMutations()).singleWhere(
      (mutation) =>
          mutation.entity == 'asset_photo' && mutation.recordKey == _photoId,
    );
    final payload = jsonDecode(queued.payloadJson!) as Map<String, dynamic>;
    expect(payload['cleanup_object_path'], _cleanupPath);
    final tombstone = await store.readMutation(
      queued,
      (await store.account()).deviceId,
    );
    expect(tombstone?.values['cleanup_object_path'], _cleanupPath);

    final gateway = _PhotoDeleteResponseLossGateway();
    var coordinator = SyncCoordinator(
      const _AuthRepository(),
      store,
      gateway,
      listenToAuthChanges: false,
    );

    await expectLater(
      coordinator.syncIncremental(),
      throwsA(
        isA<SupabaseFailure>()
            .having((failure) => failure.retryable, 'retryable', isTrue)
            .having(
              (failure) => failure.message,
              'message',
              contains('response was lost'),
            ),
      ),
    );
    expect(gateway.remotePhotoExists, isFalse);
    expect(gateway.photoDeleteCalls, 1);
    expect(await store.pendingMediaCleanupCount(), 0);
    expect(
      await store.pendingCount(),
      1,
      reason: 'remote commit without local ACK must retain the tombstone',
    );

    await coordinator.dispose();
    await _makeOutboxImmediatelyRetryable(db);
    store = LocalSyncStore(db);
    final restartedMutation = (await store.pendingMutations()).singleWhere(
      (mutation) =>
          mutation.entity == 'asset_photo' && mutation.recordKey == _photoId,
    );
    final restartedRecord = await store.readMutation(
      restartedMutation,
      (await store.account()).deviceId,
    );
    expect(restartedRecord?.values['cleanup_object_path'], _cleanupPath);

    coordinator = SyncCoordinator(
      const _AuthRepository(),
      store,
      gateway,
      listenToAuthChanges: false,
    );
    addTearDown(coordinator.dispose);
    await coordinator.syncIncremental();

    expect(gateway.photoDeleteCalls, 2);
    expect(await store.pendingCount(), 0);
    final cleanupAfterAck = await db.select(db.syncMediaCleanup).get();
    expect(cleanupAfterAck, hasLength(1));
    expect(cleanupAfterAck.single.objectPath, _cleanupPath);
    expect(gateway.storageDeleteCalls, 1);
    expect(gateway.storageObjectExists, isFalse);
    expect(cleanupAfterAck.single.attempts, 1);

    await _makeCleanupImmediatelyRetryable(db);
    await coordinator.syncIncremental();
    expect(gateway.storageDeleteCalls, 2);
    expect(await store.pendingMediaCleanupCount(), 0);
  });

  test(
    'stale outbox generation cannot enqueue cleanup or erase newer intent',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = LocalSyncStore(db);
      await store.account();
      await store.setEnabled(
        enabled: true,
        boundUserId: _userId,
        migrationState: 'active',
      );
      await _seedPhoto(db, store);
      await (db.delete(
        db.assetPhotos,
      )..where((row) => row.id.equals(_photoId))).go();
      final stale = (await store.pendingMutations()).singleWhere(
        (mutation) => mutation.entity == 'asset_photo',
      );

      await (db.update(db.syncOutbox)..where(
            (row) =>
                row.entity.equals(stale.entity) &
                row.recordKey.equals(stale.recordKey),
          ))
          .write(SyncOutboxCompanion(generation: Value(stale.generation + 1)));

      final acknowledged = await store
          .markMutationSucceededAndEnqueueMediaCleanup(
            stale,
            null,
            userId: _userId,
            objectPaths: const [_cleanupPath],
          );

      expect(acknowledged, isFalse);
      expect(await store.pendingMediaCleanupCount(), 0);
      final current = (await store.pendingMutations()).singleWhere(
        (mutation) => mutation.entity == 'asset_photo',
      );
      expect(current.generation, stale.generation + 1);
    },
  );

  test(
    'gateway reuses durable cleanup path when remote photo row is absent',
    () {
      final record = SyncRecord(
        spec: syncSpecByEntity['asset_photo']!,
        recordKey: _photoId,
        values: const {'id': _photoId, 'cleanup_object_path': _cleanupPath},
        clientModifiedAt: DateTime.utc(2026, 8, 17),
        originDeviceId: 'device-1',
        deletedAt: DateTime.utc(2026, 8, 17),
      );

      expect(deleteCleanupObjectPaths(record: record, userId: _userId), const [
        _cleanupPath,
      ]);
      expect(
        deleteCleanupObjectPaths(
          record: record,
          userId: _userId,
          deletedValues: const {'object_path': _cleanupPath},
        ),
        const [_cleanupPath],
        reason: 'server and tombstone copies of the same identity must dedupe',
      );
      expect(
        () => deleteCleanupObjectPaths(
          record: SyncRecord(
            spec: syncSpecByEntity['asset_photo']!,
            recordKey: _photoId,
            values: const {
              'id': _photoId,
              'cleanup_object_path': 'other-user/media/p.jpg',
            },
            clientModifiedAt: DateTime.utc(2026, 8, 17),
            originDeviceId: 'device-1',
            deletedAt: DateTime.utc(2026, 8, 17),
          ),
          userId: _userId,
        ),
        throwsA(
          isA<SupabaseFailure>().having(
            (failure) => failure.kind,
            'kind',
            SupabaseFailureKind.storage,
          ),
        ),
      );
    },
  );

  test(
    'Storage object-not-found is classified as successful idempotent delete',
    () {
      expect(isStorageObjectMissingStatus('404'), isTrue);
      expect(isStorageObjectMissingStatus('403'), isFalse);
      expect(isStorageObjectMissingStatus(null), isFalse);
    },
  );
}
