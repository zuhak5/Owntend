from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


# 1. Preserve the exact cloud object identity in the durable asset-photo
# delete tombstone carried by the existing offline outbox payload column.
path = Path('lib/src/core/database/app_database.dart')
text = path.read_text(encoding='utf-8')
anchor = "  Future<void> _createSyncTriggers() async {\n"
payload_constant = r'''  static const _assetPhotoDeletePayloadExpression = '''
CASE
  WHEN (SELECT bound_user_id FROM sync_account WHERE id = 1) IS NULL THEN NULL
  WHEN lower(OLD.relative_path) LIKE '%.jpeg' THEN json_object(
    'cleanup_object_path',
    (SELECT bound_user_id FROM sync_account WHERE id = 1) ||
      '/assets/' || OLD.asset_id || '/' || OLD.id || '.jpg'
  )
  WHEN lower(OLD.relative_path) LIKE '%.jpg' THEN json_object(
    'cleanup_object_path',
    (SELECT bound_user_id FROM sync_account WHERE id = 1) ||
      '/assets/' || OLD.asset_id || '/' || OLD.id || '.jpg'
  )
  WHEN lower(OLD.relative_path) LIKE '%.png' THEN json_object(
    'cleanup_object_path',
    (SELECT bound_user_id FROM sync_account WHERE id = 1) ||
      '/assets/' || OLD.asset_id || '/' || OLD.id || '.png'
  )
  WHEN lower(OLD.relative_path) LIKE '%.webp' THEN json_object(
    'cleanup_object_path',
    (SELECT bound_user_id FROM sync_account WHERE id = 1) ||
      '/assets/' || OLD.asset_id || '/' || OLD.id || '.webp'
  )
  ELSE NULL
END
''';

'''
text = replace_once(text, anchor, payload_constant + anchor, 'photo delete payload constant')

old = """      await _createSyncTrigger(
        table: table,
        entity: entity,
        keyExpression: keyExpression,
        event: 'DELETE',
        rowPrefix: 'OLD',
        operation: 'delete',
      );
"""
new = """      await _createSyncTrigger(
        table: table,
        entity: entity,
        keyExpression: keyExpression,
        event: 'DELETE',
        rowPrefix: 'OLD',
        operation: 'delete',
        payloadExpression: table == 'asset_photos'
            ? _assetPhotoDeletePayloadExpression
            : null,
      );
"""
text = replace_once(text, old, new, 'asset photo delete trigger payload')

old = """    required String rowPrefix,
    required String operation,
    String? extraWhen,
  }) async {
"""
new = """    required String rowPrefix,
    required String operation,
    String? extraWhen,
    String? payloadExpression,
  }) async {
"""
text = replace_once(text, old, new, 'sync trigger signature')

old = """    final conditions = [
      'COALESCE((SELECT suppress_outbox FROM sync_runtime WHERE id = 1), 0) = 0',
      ?extraWhen,
    ].join(' AND ');
"""
new = """    final conditions = [
      'COALESCE((SELECT suppress_outbox FROM sync_runtime WHERE id = 1), 0) = 0',
      ?extraWhen,
    ].join(' AND ');
    final payload = payloadExpression ?? 'NULL';
"""
text = replace_once(text, old, new, 'sync trigger payload local')

old = """    operation,
    changed_at,
    attempts,
"""
new = """    operation,
    payload_json,
    changed_at,
    attempts,
"""
text = replace_once(text, old, new, 'sync trigger payload column')

old = """    '$operation',
    CAST(strftime('%s', 'now') AS INTEGER),
    0,
"""
new = """    '$operation',
    $payload,
    CAST(strftime('%s', 'now') AS INTEGER),
    0,
"""
text = replace_once(text, old, new, 'sync trigger payload value')

old = """  ON CONFLICT(entity, record_key) DO UPDATE SET
    operation = excluded.operation,
    changed_at = excluded.changed_at,
"""
new = """  ON CONFLICT(entity, record_key) DO UPDATE SET
    operation = excluded.operation,
    payload_json = excluded.payload_json,
    changed_at = excluded.changed_at,
"""
text = replace_once(text, old, new, 'sync trigger payload coalesce')
path.write_text(text, encoding='utf-8')


# 2. Rehydrate the tombstone cleanup identity on restart and make local ACK +
# cleanup enqueue one SQLite transaction guarded by outbox generation.
path = Path('lib/src/core/sync/local_sync_store.dart')
text = path.read_text(encoding='utf-8')
old = """      for (var index = 0; index < spec.keyColumns.length; index++) {
        values[spec.keyColumns[index]] = parts[index];
      }
      return SyncRecord(
        spec: spec,
"""
new = """      for (var index = 0; index < spec.keyColumns.length; index++) {
        values[spec.keyColumns[index]] = parts[index];
      }
      if (spec.entity == 'asset_photo') {
        final cleanupObjectPath = _photoDeleteCleanupObjectPath(mutation);
        if (cleanupObjectPath != null) {
          values['cleanup_object_path'] = cleanupObjectPath;
        }
      }
      return SyncRecord(
        spec: spec,
"""
text = replace_once(text, old, new, 'delete tombstone hydration')

anchor = "  Future<SyncRecord?> _readProfile(\n"
helper = """  String? _photoDeleteCleanupObjectPath(LocalSyncMutation mutation) {
    final payloadJson = mutation.payloadJson;
    if (payloadJson == null || payloadJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) return null;
      final path = decoded['cleanup_object_path'];
      return path is String && path.trim().isNotEmpty ? path : null;
    } on Object {
      return null;
    }
  }

"""
text = replace_once(text, anchor, helper + anchor, 'photo delete tombstone helper')

anchor = "  Future<void> discardMutation(String entity, String recordKey) async {\n"
atomic_method = """  Future<bool> markMutationSucceededAndEnqueueMediaCleanup(
    LocalSyncMutation mutation,
    SyncRecord? canonical, {
    required String userId,
    required List<String> objectPaths,
  }) async {
    final cleanupPaths = objectPaths.where((path) => path.isNotEmpty).toSet();
    for (final objectPath in cleanupPaths) {
      if (!objectPath.startsWith('$userId/')) {
        throw StateError('Media cleanup path belongs to another cloud account.');
      }
    }

    return db.transaction(() async {
      final pending =
          await (db.select(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals(mutation.entity) &
                    row.recordKey.equals(mutation.recordKey) &
                    row.generation.equals(mutation.generation),
              ))
              .getSingleOrNull();
      if (pending == null) return false;
      if (pending.userId != null && pending.userId != userId) {
        throw StateError('Queued mutation belongs to another cloud account.');
      }

      if (canonical != null) {
        await _saveShadow(canonical);
      }
      if (mutation.operation == 'delete') {
        await (db.delete(db.syncShadows)..where(
              (row) =>
                  row.entity.equals(mutation.entity) &
                  row.recordKey.equals(mutation.recordKey),
            ))
            .go();
      }

      for (final objectPath in cleanupPaths) {
        await db
            .into(db.syncMediaCleanup)
            .insertOnConflictUpdate(
              SyncMediaCleanupCompanion.insert(
                objectPath: objectPath,
                userId: userId,
                entity: mutation.entity,
                recordKey: mutation.recordKey,
              ),
            );
      }

      final deletedCount =
          await (db.delete(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals(mutation.entity) &
                    row.recordKey.equals(mutation.recordKey) &
                    row.generation.equals(mutation.generation),
              ))
              .go();
      return deletedCount > 0;
    });
  }

"""
text = replace_once(text, anchor, atomic_method + anchor, 'atomic media cleanup acknowledgement')
path.write_text(text, encoding='utf-8')


# 3. Make absent-row retries return the durable cleanup identity, validate its
# account scope, and normalize Storage object-not-found to idempotent success.
path = Path('lib/src/core/sync/supabase_sync_gateway.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import 'package:crypto/crypto.dart';\n",
    "import 'package:crypto/crypto.dart';\nimport 'package:flutter/foundation.dart';\n",
    'gateway testing annotation import',
)
old = """          if (existing == null) {
            return const RemoteWriteResult.applied(null);
          }
"""
new = """          if (existing == null) {
            return _appliedDeleteResult(
              record: record,
              userId: userId,
            );
          }
"""
text = replace_once(text, old, new, 'absent delete retry cleanup result')

old = """        if (deleted != null) {
          final cleanupPath = _remoteMediaPath(
            record.spec,
            Map<String, dynamic>.from(deleted),
          );
          return RemoteWriteResult.applied(
            null,
            cleanupObjectPaths: cleanupPath == null ? const [] : [cleanupPath],
          );
        }
"""
new = """        if (deleted != null) {
          return _appliedDeleteResult(
            record: record,
            userId: userId,
            deletedValues: Map<String, dynamic>.from(deleted),
          );
        }
"""
text = replace_once(text, old, new, 'successful delete cleanup result')

old = """    await _client.storage
        .from(_bucket)
        .remove([objectPath])
        .timeout(_storageTimeout);
  }
"""
new = """    try {
      await _client.storage
          .from(_bucket)
          .remove([objectPath])
          .timeout(_storageTimeout);
    } on StorageException catch (error) {
      if (isStorageObjectMissingStatus(error.statusCode)) return;
      rethrow;
    }
  }
"""
text = replace_once(text, old, new, 'idempotent storage delete')

anchor = "Map<String, dynamic>? _zeroOrOneRemoteRow(List<Map<String, dynamic>> rows) {\n"
helpers = """RemoteWriteResult _appliedDeleteResult({
  required SyncRecord record,
  required String userId,
  Map<String, dynamic>? deletedValues,
}) {
  return RemoteWriteResult.applied(
    null,
    cleanupObjectPaths: deleteCleanupObjectPaths(
      record: record,
      userId: userId,
      deletedValues: deletedValues,
    ),
  );
}

@visibleForTesting
List<String> deleteCleanupObjectPaths({
  required SyncRecord record,
  required String userId,
  Map<String, dynamic>? deletedValues,
}) {
  final paths = <String>{};

  void addPath(Object? rawPath) {
    if (rawPath == null) return;
    if (rawPath is! String || rawPath.trim().isEmpty) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.incompatibleSchema,
        message: 'Cloud media cleanup identity is malformed.',
      );
    }
    if (!rawPath.startsWith('$userId/')) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.storage,
        message: 'Cloud media cleanup path does not belong to this account.',
      );
    }
    paths.add(rawPath);
  }

  addPath(record.values['cleanup_object_path']);
  if (deletedValues != null) {
    addPath(_remoteMediaPath(record.spec, deletedValues));
  }
  return paths.toList(growable: false);
}

@visibleForTesting
bool isStorageObjectMissingStatus(String? statusCode) {
  return int.tryParse(statusCode ?? '') == 404;
}

"""
text = replace_once(text, anchor, helpers + anchor, 'delete cleanup helpers')
path.write_text(text, encoding='utf-8')


# 4. Close the crash window: local outbox completion and durable media cleanup
# insertion are one transaction whenever the remote ACK carries cleanup work.
path = Path('lib/src/core/sync/sync_coordinator.dart')
text = path.read_text(encoding='utf-8')
old = """  ) async {
    await _localStore.markMutationSucceeded(mutation, result.canonical);
    for (final objectPath in result.cleanupObjectPaths) {
      await _localStore.enqueueMediaCleanup(
        objectPath: objectPath,
        userId: userId,
        entity: mutation.entity,
        recordKey: mutation.recordKey,
      );
    }
  }
"""
new = """  ) async {
    if (result.cleanupObjectPaths.isEmpty) {
      await _localStore.markMutationSucceeded(mutation, result.canonical);
      return;
    }
    await _localStore.markMutationSucceededAndEnqueueMediaCleanup(
      mutation,
      result.canonical,
      userId: userId,
      objectPaths: result.cleanupObjectPaths,
    );
  }
"""
text = replace_once(text, old, new, 'atomic coordinator mutation finalization')
path.write_text(text, encoding='utf-8')


# 5. Documentation: make the local tombstone -> durable cleanup invariant
# explicit alongside the existing server upload/replacement cleanup ledger.
path = Path('docs/architecture/sync-protocol.md')
text = path.read_text(encoding='utf-8')
old = """- **Durable Cleanup Ledger**: Replacing or deleting a photo enqueues the old object path into `media_cleanup_queue` transactionally before database mutation acknowledgement, guaranteeing zero lost orphan cleanup work.
"""
new = """- **Server Durable Cleanup Ledger**: Upload finalization and server-side replacement flows enqueue superseded object paths into `media_cleanup_queue` transactionally before database mutation acknowledgement.
- **Client Delete Tombstone & Cleanup Handoff**: A local `asset_photo` DELETE preserves the exact canonical Storage path in the durable outbox tombstone before the local row disappears. If the remote metadata row was already deleted (including response-loss retry), `SupabaseSyncGateway.write()` returns that same tombstone path as cleanup work. The coordinator acknowledges the exact outbox generation and inserts `sync_media_cleanup` in one Drift transaction, so the object path is always represented by either pending mutation intent or durable cleanup work. Storage object-not-found is successful idempotent cleanup; duplicate cleanup attempts are safe.
"""
text = replace_once(text, old, new, 'sync protocol media cleanup documentation')
path.write_text(text, encoding='utf-8')


# 6. Focused fault-injection tests covering response loss, restart/retry,
# atomic generation-safe handoff, and duplicate/idempotent cleanup execution.
test_path = Path('test/bug_009_photo_cleanup_response_loss_test.dart')
test_path.write_text(r'''import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
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
const _assetId = 'asset-bug-009';
const _photoId = 'photo-bug-009';
const _cleanupPath = '$_userId/assets/$_assetId/$_photoId.jpg';

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
  Future<SyncFeedCapability> getSyncFeedCapability() async {
    return const SyncFeedCapability(
      enabled: false,
      capabilityVersion: 'bug-009-test',
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
            id: 'area-bug-009',
            name: 'BUG-009 area',
            kind: 'indoor',
          ),
        );
    await db
        .into(db.rooms)
        .insert(
          RoomsCompanion.insert(
            id: 'room-bug-009',
            areaId: 'area-bug-009',
            name: 'BUG-009 room',
          ),
        );
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'category-bug-009',
            name: 'BUG-009 category',
            healthGroup: 'other',
          ),
        );
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: _assetId,
            name: 'BUG-009 asset',
            categoryId: 'category-bug-009',
            roomId: 'room-bug-009',
          ),
        );
    await db
        .into(db.assetPhotos)
        .insert(
          AssetPhotosCompanion.insert(
            id: _photoId,
            assetId: _assetId,
            relativePath: 'media/$_assetId/$_photoId.jpeg',
          ),
        );
  });
  await db.delete(db.syncOutbox).go();
}

Future<void> _makeOutboxImmediatelyRetryable(AppDatabase db) async {
  await (db.update(db.syncOutbox)..where(
        (row) => row.entity.equals('asset_photo') & row.recordKey.equals(_photoId),
      ))
      .write(
        const SyncOutboxCompanion(
          state: Value('pending'),
          nextAttemptAt: Value(null),
        ),
      );
}

Future<void> _makeCleanupImmediatelyRetryable(AppDatabase db) async {
  await (db.update(db.syncMediaCleanup)..where(
        (row) => row.objectPath.equals(_cleanupPath),
      ))
      .write(
        const SyncMediaCleanupCompanion(nextAttemptAt: Value(null)),
      );
}

void main() {
  test(
    'photo delete survives server response loss, restart, and duplicate cleanup',
    () async {
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
        (await store.pendingMutations()).where(
          (mutation) =>
              mutation.entity == 'asset_photo' && mutation.recordKey == _photoId,
        ),
        isNotEmpty,
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
    },
  );

  test('stale outbox generation cannot enqueue cleanup or erase newer intent', () async {
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
              row.entity.equals(stale.entity) & row.recordKey.equals(stale.recordKey),
        ))
        .write(SyncOutboxCompanion(generation: Value(stale.generation + 1)));

    final acknowledged = await store.markMutationSucceededAndEnqueueMediaCleanup(
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
  });

  test('gateway reuses durable cleanup path when remote photo row is absent', () {
    final record = SyncRecord(
      spec: syncSpecByEntity['asset_photo']!,
      recordKey: _photoId,
      values: const {
        'id': _photoId,
        'cleanup_object_path': _cleanupPath,
      },
      clientModifiedAt: DateTime.utc(2026, 8, 17),
      originDeviceId: 'device-1',
      deletedAt: DateTime.utc(2026, 8, 17),
    );

    expect(
      deleteCleanupObjectPaths(record: record, userId: _userId),
      const [_cleanupPath],
    );
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
            'cleanup_object_path': 'other-user/assets/a/p.jpg',
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
  });

  test('Storage object-not-found is classified as successful idempotent delete', () {
    expect(isStorageObjectMissingStatus('404'), isTrue);
    expect(isStorageObjectMissingStatus('403'), isFalse);
    expect(isStorageObjectMissingStatus(null), isFalse);
  });
}
''', encoding='utf-8')
