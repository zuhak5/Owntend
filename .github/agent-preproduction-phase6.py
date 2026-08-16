from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text and old not in text:
        return
    if old not in text:
        raise SystemExit(f"expected snippet not found in {path}: {old[:180]!r}")
    file.write_text(text.replace(old, new, 1))


# Remove accidental duplicate declarations/dispatch blocks introduced by the
# temporary patch bootstrap. These never existed on main.
gateway = Path('lib/src/core/sync/supabase_sync_gateway.dart')
gtext = gateway.read_text()
undo_class_start = gtext.find('class MaintenanceUndoResult {')
second_undo_class = gtext.find('class MaintenanceUndoResult {', undo_class_start + 1)
if second_undo_class >= 0:
    class_end = gtext.find('\nclass MaintenanceCompletionResult {', second_undo_class)
    if class_end < 0:
        raise SystemExit('could not bound duplicate MaintenanceUndoResult')
    gtext = gtext[:second_undo_class] + gtext[class_end + 1:]
gateway.write_text(gtext)

coord = Path('lib/src/core/sync/sync_coordinator.dart')
ctext = coord.read_text()
needle = "        if (mutation.entity == 'maintenance_undo') {"
first = ctext.find(needle)
second = ctext.find(needle, first + 1) if first >= 0 else -1
if second >= 0:
    generic = ctext.find("        if (mutation.operation == 'upsert') {", second)
    if generic < 0:
        raise SystemExit('could not bound duplicate maintenance undo dispatch')
    ctext = ctext[:second] + ctext[generic:]
coord.write_text(ctext)

# Make-primary is an atomic business operation. Suppress the generic photo
# update triggers and enqueue one coalescing operation per asset instead.
asset = Path('lib/src/core/data/asset_repository.dart')
atext = asset.read_text()
old_primary = '''  @override
  Future<void> setPrimaryPhoto(String assetId, String photoId) async {
    await db.transaction(() async {
      final target =
          await (db.select(db.assetPhotos)..where(
                (photo) =>
                    photo.id.equals(photoId) & photo.assetId.equals(assetId),
              ))
              .getSingleOrNull();
      if (target == null) {
        return;
      }
      await (db.update(db.assetPhotos)
            ..where((photo) => photo.assetId.equals(assetId)))
          .write(const AssetPhotosCompanion(isPrimary: Value(false)));
      await (db.update(db.assetPhotos)..where(
            (photo) => photo.id.equals(photoId) & photo.assetId.equals(assetId),
          ))
          .write(const AssetPhotosCompanion(isPrimary: Value(true)));
    });
  }
'''
new_primary = '''  @override
  Future<void> setPrimaryPhoto(String assetId, String photoId) async {
    final now = DateTime.now();
    await db.transaction(() async {
      final target =
          await (db.select(db.assetPhotos)..where(
                (photo) =>
                    photo.id.equals(photoId) & photo.assetId.equals(assetId),
              ))
              .getSingleOrNull();
      if (target == null) return;

      await (db.update(db.syncRuntime)..where((row) => row.id.equals(1)))
          .write(const SyncRuntimeCompanion(suppressOutbox: Value(true)));
      try {
        await (db.update(db.assetPhotos)
              ..where((photo) => photo.assetId.equals(assetId)))
            .write(const AssetPhotosCompanion(isPrimary: Value(false)));
        await (db.update(db.assetPhotos)..where(
              (photo) => photo.id.equals(photoId) & photo.assetId.equals(assetId),
            ))
            .write(const AssetPhotosCompanion(isPrimary: Value(true)));
      } finally {
        await (db.update(db.syncRuntime)..where((row) => row.id.equals(1)))
            .write(const SyncRuntimeCompanion(suppressOutbox: Value(false)));
      }

      final account = await (db.select(
        db.syncAccount,
      )..where((row) => row.id.equals(1))).getSingleOrNull();
      await db.into(db.syncOutbox).insertOnConflictUpdate(
        SyncOutboxCompanion.insert(
          entity: 'asset_photo_primary',
          recordKey: assetId,
          operation: 'execute',
          changedAt: Value(now),
          payloadJson: Value(jsonEncode({
            'version': 1,
            'asset_id': assetId,
            'photo_id': photoId,
          })),
          userId: Value(account?.boundUserId),
        ),
      );
    });
  }
'''
if old_primary not in atext:
    raise SystemExit('setPrimaryPhoto block not found')
asset.write_text(atext.replace(old_primary, new_primary, 1))

# Existing photo metadata updates must not upload/finalize the binary again.
gateway = Path('lib/src/core/sync/supabase_sync_gateway.dart')
gtext = gateway.read_text()
gtext = gtext.replace(
    'final payload = await _preparePayload(record, userId, deviceId);',
    "final payload = await _preparePayload(\n        record,\n        userId,\n        deviceId,\n        uploadMedia: !(record.spec.entity == 'asset_photo' && expectedRevision != null),\n      );",
    1,
)
old_sig = '''  Future<Map<String, dynamic>> _preparePayload(
    SyncRecord record,
    String userId,
    String deviceId,
  ) async {
'''
new_sig = '''  Future<Map<String, dynamic>> _preparePayload(
    SyncRecord record,
    String userId,
    String deviceId, {
    bool uploadMedia = true,
  }) async {
'''
if old_sig not in gtext:
    raise SystemExit('_preparePayload signature not found')
gtext = gtext.replace(old_sig, new_sig, 1)
old_media = '''    if (record.spec.entity == 'asset_photo') {
      final localPath = record.values['relative_path'] as String;
      final assetId = record.values['asset_id'] as String;
      final photoId = record.values['id'] as String;
      final upload = await _uploadMedia(
        userId: userId,
        localRelativePath: localPath,
        remoteDirectory: '$userId/assets/$assetId',
        remoteBaseName: photoId,
        assetId: assetId,
        photoId: photoId,
        revision: record.revision,
      );
      payload['object_path'] = upload.objectPath;
    }
'''
new_media = '''    if (record.spec.entity == 'asset_photo') {
      if (uploadMedia) {
        final localPath = record.values['relative_path'] as String;
        final assetId = record.values['asset_id'] as String;
        final photoId = record.values['id'] as String;
        final upload = await _uploadMedia(
          userId: userId,
          localRelativePath: localPath,
          remoteDirectory: '$userId/assets/$assetId',
          remoteBaseName: photoId,
          assetId: assetId,
          photoId: photoId,
          revision: record.revision,
        );
        payload['object_path'] = upload.objectPath;
      } else {
        // The local relative path is device-specific and must never overwrite
        // the immutable cloud object path during a metadata-only update.
        payload.remove('object_path');
      }
    }
'''
if old_media not in gtext:
    raise SystemExit('asset photo media preparation block not found')
gateway.write_text(gtext.replace(old_media, new_media, 1))

# Custom primary operation runs after all normal entity upserts, ensuring a
# newly-created target photo exists remotely before the atomic RPC executes.
store = Path('lib/src/core/sync/local_sync_store.dart')
stext = store.read_text()
marker = '''    final maintenancePlanOrder = dependencyOrder['maintenance_plan'];
'''
insert = '''    dependencyOrder['asset_photo_primary'] = syncEntitySpecs.length + 1;

    final maintenancePlanOrder = dependencyOrder['maintenance_plan'];
'''
if insert not in stext:
    if marker not in stext: raise SystemExit('dependency marker not found')
    stext = stext.replace(marker, insert, 1)

success_marker = '''  Future<void> markMaintenanceUndoSucceeded(
'''
primary_success = '''  Future<void> markAssetPhotoPrimarySucceeded(
    LocalSyncMutation mutation, {
    required List<SyncRecord> photos,
  }) async {
    if (mutation.entity != 'asset_photo_primary' ||
        photos.any((record) => record.spec.entity != 'asset_photo')) {
      throw StateError('Invalid primary-photo acknowledgement.');
    }
    await db.transaction(() async {
      await withOutboxSuppressed(() async {
        for (final canonical in photos) {
          final local = await (db.select(db.assetPhotos)..where(
                (row) => row.id.equals(canonical.recordKey),
              )).getSingleOrNull();
          if (local == null) {
            // A photo created by another device will be materialized by the
            // normal pull path. Remembering its remote row here is unnecessary.
            continue;
          }
          final localized = SyncRecord(
            spec: canonical.spec,
            recordKey: canonical.recordKey,
            values: {
              ...canonical.values,
              'relative_path': local.relativePath,
            },
            clientModifiedAt: canonical.clientModifiedAt,
            originDeviceId: canonical.originDeviceId,
            revision: canonical.revision,
            syncSeq: canonical.syncSeq,
            serverUpdatedAt: canonical.serverUpdatedAt,
            deletedAt: canonical.deletedAt,
          );
          await _upsertLocal(localized);
          await _saveShadow(localized);
        }
      });
      await (db.delete(db.syncOutbox)..where(
            (row) =>
                row.entity.equals('asset_photo_primary') &
                row.recordKey.equals(mutation.recordKey),
          )).go();
    });
  }

'''+success_marker
if primary_success not in stext:
    if success_marker not in stext: raise SystemExit('local success marker not found')
    stext = stext.replace(success_marker, primary_success, 1)
store.write_text(stext)

# Dispatch the custom operation without trying to interpret it as a sync entity.
coord = Path('lib/src/core/sync/sync_coordinator.dart')
ctext = coord.read_text()
undo_marker = "        if (mutation.entity == 'maintenance_undo') {"
idx = ctext.find(undo_marker)
if idx < 0: raise SystemExit('maintenance undo dispatch marker missing')
primary_dispatch = r'''        if (mutation.entity == 'asset_photo_primary') {
          final payloadJson = mutation.payloadJson;
          if (mutation.operation != 'execute' ||
              payloadJson == null ||
              payloadJson.trim().isEmpty) {
            const failure = SupabaseFailure(
              kind: SupabaseFailureKind.incompatibleSchema,
              message: 'A queued primary-photo operation has an invalid payload.',
            );
            await _recordMutationFailure(mutation, failure);
            throw failure;
          }
          try {
            final payload = Map<String, dynamic>.from(
              jsonDecode(payloadJson) as Map,
            );
            final assetId = payload['asset_id'] as String?;
            final photoId = payload['photo_id'] as String?;
            if (assetId == null || photoId == null || assetId != mutation.recordKey) {
              throw const SupabaseFailure(
                kind: SupabaseFailureKind.incompatibleSchema,
                message: 'A queued primary-photo operation is malformed.',
              );
            }
            await _localStore.markMutationInFlight(mutation, userId: userId);
            final response = await _remoteGateway.setPrimaryAssetPhoto(
              assetId: assetId,
              photoId: photoId,
            );
            await _ensureActiveAccountScope(scope);
            final rawPhotos = response['photos'];
            if (rawPhotos is! List) {
              throw const FormatException(
                'The primary-photo RPC omitted canonical photo rows.',
              );
            }
            final spec = syncSpecByEntity['asset_photo']!;
            final photos = <SyncRecord>[];
            for (final raw in rawPhotos) {
              if (raw is! Map) {
                throw const FormatException(
                  'The primary-photo RPC returned an invalid photo row.',
                );
              }
              final row = Map<String, dynamic>.from(raw);
              if (row['user_id'] != userId || row['asset_id'] != assetId) {
                throw const SupabaseFailure(
                  kind: SupabaseFailureKind.permissionDenied,
                  message: 'The cloud returned primary-photo data for another scope.',
                );
              }
              photos.add(SyncRecord.fromRemote(spec, row));
            }
            if (!photos.any(
              (record) =>
                  record.recordKey == photoId &&
                  record.values['is_primary'] == true,
            )) {
              throw const FormatException(
                'The primary-photo RPC did not confirm the selected photo.',
              );
            }
            await _localStore.markAssetPhotoPrimarySucceeded(
              mutation,
              photos: photos,
            );
            if (trackHydration) await _localStore.addHydrationUnits(1);
            return true;
          } on _AccountScopeInactive {
            rethrow;
          } on Object catch (error) {
            final failure = SupabaseFailure.from(error);
            await _recordMutationFailure(mutation, failure);
            rethrow;
          }
        }

'''
if "mutation.entity == 'asset_photo_primary'" not in ctext:
    ctext = ctext[:idx] + primary_dispatch + ctext[idx:]
coord.write_text(ctext)

# Local regression: selecting a primary photo produces one custom operation
# and no generic metadata upserts for the selection itself.
test = Path('test/trash_lifecycle_and_invariants_test.dart')
t = test.read_text()
addition = r'''

  group('Primary photo mutation routing', () {
    test('make primary queues one atomic operation instead of photo upserts', () async {
      final areaId = await assetRepo.saveArea(name: 'Photos', kind: AreaKind.indoor);
      final roomId = await assetRepo.saveRoom(areaId: areaId, name: 'Photos');
      final categoryId = (await assetRepo.listCategories()).first.id;
      final assetId = await assetRepo.saveAsset(
        name: 'Photo asset',
        categoryId: categoryId,
        roomId: roomId,
      );
      final sourceA = File(p.join(tempDir.path, 'a.jpg'))..writeAsBytesSync([1, 2, 3]);
      final sourceB = File(p.join(tempDir.path, 'b.jpg'))..writeAsBytesSync([4, 5, 6]);
      final first = await assetRepo.addPhoto(assetId, sourceA.path);
      final second = await assetRepo.addPhoto(assetId, sourceB.path);
      await db.delete(db.syncOutbox).go();

      await assetRepo.setPrimaryPhoto(assetId, second.id);

      final outbox = await db.select(db.syncOutbox).get();
      expect(outbox.where((row) => row.entity == 'asset_photo'), isEmpty);
      final operation = outbox.singleWhere(
        (row) => row.entity == 'asset_photo_primary',
      );
      final payload = jsonDecode(operation.payloadJson!) as Map<String, dynamic>;
      expect(payload['asset_id'], assetId);
      expect(payload['photo_id'], second.id);
      final photos = await assetRepo.listPhotosForAsset(assetId);
      expect(photos.singleWhere((photo) => photo.id == first.id).isPrimary, isFalse);
      expect(photos.singleWhere((photo) => photo.id == second.id).isPrimary, isTrue);
    });
  });
'''
# test file already imports dart:io, add dart:convert.
if "import 'dart:convert';" not in t:
    t = t.replace("import 'dart:io';", "import 'dart:convert';\nimport 'dart:io';", 1)
if "group('Primary photo mutation routing'" not in t:
    close = t.rfind('\n}')
    if close < 0: raise SystemExit('trash test close not found')
    t = t[:close] + addition + t[close:]
test.write_text(t)
