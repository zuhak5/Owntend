import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';

void main() {
  group('Phase 1 - Persistence, Trigger & Outbox Invariants', () {
    late File dbFile;
    late AppDatabase db;
    late LocalSyncStore syncStore;

    setUp(() async {
      dbFile = File(
        '${Directory.systemTemp.path}/owntend_phase1_'
        '${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      db = AppDatabase(executor: NativeDatabase(dbFile));
      syncStore = LocalSyncStore(db);
      await db.customSelect('SELECT 1').get();
    });

    tearDown(() async {
      await db.close();
      if (await dbFile.exists()) await dbFile.delete();
    });

    test('[SYNC-01] asset_photos accepts null relative_path for deferred media hydration', () async {
      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(
              id: 'area-1',
              name: 'Living Area',
              kind: 'indoor',
            ),
          );
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              id: 'room-1',
              name: 'Lounge',
              areaId: 'area-1',
            ),
          );
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: 'asset-1',
              name: 'Sofa',
              roomId: 'room-1',
            ),
          );

      // Insert asset_photo without relative_path (null)
      await db
          .into(db.assetPhotos)
          .insert(
            AssetPhotosCompanion.insert(
              id: 'photo-1',
              assetId: 'asset-1',
              cloudObjectPath: const Value('user-1/media/photos/photo-1.jpg'),
            ),
          );

      final photo = await (db.select(
        db.assetPhotos,
      )..where((row) => row.id.equals('photo-1'))).getSingle();

      expect(photo.relativePath, isNull);
      expect(photo.cloudObjectPath, 'user-1/media/photos/photo-1.jpg');
    });

    test(
      '[SYNC-04] remotePhotoRecordKeys matches unmaterialized cloud photos',
      () async {
        await db
            .into(db.areas)
            .insert(
              AreasCompanion.insert(
                id: 'area-1',
                name: 'Living Area',
                kind: 'indoor',
              ),
            );
        await db
            .into(db.rooms)
            .insert(
              RoomsCompanion.insert(
                id: 'room-1',
                name: 'Lounge',
                areaId: 'area-1',
              ),
            );
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: 'asset-1',
                name: 'Sofa',
                roomId: 'room-1',
              ),
            );

        // Photo 1: Has cloud path, relative_path is null (unmaterialized)
        await db
            .into(db.assetPhotos)
            .insert(
              AssetPhotosCompanion.insert(
                id: 'photo-unmaterialized',
                assetId: 'asset-1',
                cloudObjectPath: const Value('user-xyz/media/photos/p1.jpg'),
              ),
            );

        // Photo 2: Has cloud path, relative_path is already local
        await db
            .into(db.assetPhotos)
            .insert(
              AssetPhotosCompanion.insert(
                id: 'photo-downloaded',
                assetId: 'asset-1',
                relativePath: const Value('cloud_media/asset-1/p2.jpg'),
                cloudObjectPath: const Value('user-xyz/media/photos/p2.jpg'),
              ),
            );

        // Photo 3: Belongs to different user
        await db
            .into(db.assetPhotos)
            .insert(
              AssetPhotosCompanion.insert(
                id: 'photo-other-user',
                assetId: 'asset-1',
                cloudObjectPath: const Value('user-other/media/photos/p3.jpg'),
              ),
            );

        final keys = await syncStore.remotePhotoRecordKeys('user-xyz');
        expect(keys, contains('photo-unmaterialized'));
        expect(keys, isNot(contains('photo-downloaded')));
        expect(keys, isNot(contains('photo-other-user')));
      },
    );

    test('[SYNC-08] outbox trigger resets state to pending on modification from failedVisible', () async {
      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(
              id: 'area-trigger',
              name: 'Initial Name',
              kind: 'indoor',
            ),
          );

      // Simulate the mutation in syncOutbox failing terminally
      await (db.update(db.syncOutbox)..where(
            (row) =>
                row.entity.equals('area') &
                row.recordKey.equals('area-trigger'),
          ))
          .write(
            const SyncOutboxCompanion(
              state: Value('failedVisible'),
              attempts: Value(-1),
              generation: Value(1),
            ),
          );

      // User modifies the area locally
      await (db.update(db.areas)..where((row) => row.id.equals('area-trigger')))
          .write(const AreasCompanion(name: Value('Updated Name')));

      // Trigger should have fired and updated syncOutbox
      final mutation =
          await (db.select(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals('area') &
                    row.recordKey.equals('area-trigger'),
              ))
              .getSingle();

      expect(mutation.state, 'pending');
      expect(mutation.attempts, 0);
      expect(mutation.generation, 2);
      expect(mutation.lastError, isNull);
    });

    test('[DB-01] MigrationStrategy defines both onCreate and onUpgrade', () {
      final migration = db.migration;
      expect(migration.onCreate, isNotNull);
      expect(migration.onUpgrade, isNotNull);
    });
  });
}
