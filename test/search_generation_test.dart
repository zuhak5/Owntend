import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';

void main() {
  group('durable search generation', () {
    late AppDatabase db;
    late DriftAssetRepository assets;
    late DriftMaintenanceRepository maintenance;
    late DriftSearchRepository search;

    setUp(() async {
      db = AppDatabase(executor: NativeDatabase.memory());
      assets = DriftAssetRepository(db);
      maintenance = DriftMaintenanceRepository(db);
      search = DriftSearchRepository(db);
      await _seedSearchArea(assets);
    });

    tearDown(() async {
      await db.close();
    });

    test('source families invalidate without manual rebuild', () async {
      final roomId = await assets.saveRoom(
        areaId: 'area_search',
        name: 'Utility Room',
        notes: 'Old room note',
      );
      final deviceId = await assets.saveAsset(
        name: 'Old Boiler',
        assetType: AssetType.device,
        roomId: roomId,
        tagNames: const ['service-tag'],
        deviceDetails: const DeviceDetails(brand: 'OldBrand', model: 'Alpha'),
      );
      final petId = await assets.saveAsset(
        name: 'Milo',
        assetType: AssetType.pet,
        roomId: roomId,
        petDetails: const PetDetails(
          species: 'Cat',
          breed: 'OldBreed',
          microchipId: 'chip-old',
        ),
      );
      final plantId = await assets.saveAsset(
        name: 'Fern',
        assetType: AssetType.plant,
        roomId: roomId,
        plantDetails: const PlantDetails(
          species: 'Boston fern',
          sunlight: Sunlight.low,
          potSize: 'OldPot',
        ),
      );
      final safetyId = await assets.saveAsset(
        name: 'Detector',
        assetType: AssetType.safety,
        roomId: roomId,
        safetyDetails: const SafetyDetails(
          safetyType: 'Smoke detector',
          batteryType: 'OldBattery',
        ),
      );
      await db
          .into(db.assetPhotos)
          .insert(
            AssetPhotosCompanion.insert(
              id: 'photo-search',
              assetId: deviceId,
              relativePath: Value('photos/$deviceId/photo-search.jpg'),
              caption: const Value('OldCaption'),
            ),
          );
      final planId = await maintenance.savePlan(
        assetId: deviceId,
        title: 'OldPlan',
        instructions: 'OldInstructions',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: DateTime(2026, 9, 1),
      );

      await search.rebuildIndex();

      final areaEditBase = (await assets.listAreas()).singleWhere(
        (area) => area.id == 'area_search',
      );
      await assets.saveArea(
        id: 'area_search',
        name: 'North Wing',
        kind: AreaKind.indoor,
        expectedUpdatedAt: areaEditBase.updatedAt,
      );
      expect(await _hasResult(search, 'North', 'room', roomId), isTrue);

      final roomEditBase = (await assets.listRooms()).singleWhere(
        (room) => room.id == roomId,
      );
      await assets.saveRoom(
        id: roomId,
        areaId: 'area_search',
        name: 'Utility Room',
        notes: 'Copper Closet',
        expectedUpdatedAt: roomEditBase.updatedAt,
      );
      expect(await _hasResult(search, 'Copper', 'room', roomId), isTrue);

      await (db.update(db.assets)..where((row) => row.id.equals(deviceId)))
          .write(const AssetsCompanion(name: Value('Heat Pump')));
      expect(await _hasResult(search, 'Heat', 'asset', deviceId), isTrue);
      expect(
        await _hasResult(search, 'Old Boiler', 'asset', deviceId),
        isFalse,
      );

      await (db.update(db.deviceDetailsTable)
            ..where((row) => row.assetId.equals(deviceId)))
          .write(const DeviceDetailsTableCompanion(brand: Value('ThermoNova')));
      expect(await _hasResult(search, 'ThermoNova', 'asset', deviceId), isTrue);

      await (db.update(
        db.petDetailsTable,
      )..where((row) => row.assetId.equals(petId))).write(
        const PetDetailsTableCompanion(microchipId: Value('chip-new')),
      );
      expect(await _hasResult(search, 'chip-new', 'asset', petId), isTrue);

      await (db.update(
        db.plantDetailsTable,
      )..where((row) => row.assetId.equals(plantId))).write(
        const PlantDetailsTableCompanion(potSize: Value('CeramicPot')),
      );
      expect(await _hasResult(search, 'CeramicPot', 'asset', plantId), isTrue);

      await (db.update(
        db.safetyDetailsTable,
      )..where((row) => row.assetId.equals(safetyId))).write(
        const SafetyDetailsTableCompanion(batteryType: Value('LithiumCell')),
      );
      expect(
        await _hasResult(search, 'LithiumCell', 'asset', safetyId),
        isTrue,
      );

      final serviceTag = (await db.select(db.tags).get()).singleWhere(
        (row) => row.name == 'service-tag',
      );
      await (db.update(db.tags)..where((row) => row.id.equals(serviceTag.id)))
          .write(const TagsCompanion(name: Value('seasonalservice')));
      expect(
        await _hasResult(search, 'seasonalservice', 'asset', deviceId),
        isTrue,
      );
      expect(
        await _hasResult(search, 'service-tag', 'asset', deviceId),
        isFalse,
      );

      await db
          .into(db.tags)
          .insert(TagsCompanion.insert(id: 'tag-linked', name: 'linkedonly'));
      await db
          .into(db.assetTags)
          .insert(
            AssetTagsCompanion.insert(assetId: deviceId, tagId: 'tag-linked'),
          );
      expect(await _hasResult(search, 'linkedonly', 'asset', deviceId), isTrue);

      await (db.update(db.assetPhotos)
            ..where((row) => row.id.equals('photo-search')))
          .write(const AssetPhotosCompanion(caption: Value('PortraitCaption')));
      expect(
        await _hasResult(search, 'PortraitCaption', 'asset', deviceId),
        isTrue,
      );

      await (db.update(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).write(
        const MaintenancePlansCompanion(
          title: Value('Inspect Compressor'),
          instructions: Value('Pressure Gauge'),
        ),
      );
      expect(await _hasResult(search, 'Compressor', 'plan', planId), isTrue);
      expect(await _hasResult(search, 'OldPlan', 'plan', planId), isFalse);
    });

    test('archive, restore, and delete stay mutation-consistent', () async {
      final roomId = await assets.saveRoom(
        areaId: 'area_search',
        name: 'Archive Room',
      );
      final assetId = await assets.saveAsset(
        name: 'ArchiveTarget',
        roomId: roomId,
      );
      await search.rebuildIndex();
      expect(
        await _hasResult(search, 'ArchiveTarget', 'asset', assetId),
        isTrue,
      );

      await assets.trashAsset(assetId);
      expect(
        await _hasResult(search, 'ArchiveTarget', 'asset', assetId),
        isFalse,
      );

      await assets.restoreAsset(assetId);
      expect(
        await _hasResult(search, 'ArchiveTarget', 'asset', assetId),
        isTrue,
      );

      await assets.deleteAsset(assetId);
      expect(
        await _hasResult(search, 'ArchiveTarget', 'asset', assetId),
        isFalse,
      );
    });

    test('suppressed sync writes dirty and next query catches up', () async {
      final roomId = await assets.saveRoom(
        areaId: 'area_search',
        name: 'Bulk Room',
      );
      await search.rebuildIndex();
      final before = await _generation(db);
      expect(before.source, before.indexed);

      await LocalSyncStore(db).withOutboxSuppressed(() async {
        await (db.update(db.areas)
              ..where((row) => row.id.equals('area_search')))
            .write(const AreasCompanion(name: Value('Bulk North')));
        await (db.update(db.rooms)..where((row) => row.id.equals(roomId)))
            .write(const RoomsCompanion(notes: Value('Bulk Copper')));
      });

      final dirty = await _generation(db);
      expect(dirty.source, greaterThanOrEqualTo(before.source + 2));
      expect(dirty.indexed, before.indexed);

      expect(await _hasResult(search, 'Bulk Copper', 'room', roomId), isTrue);
      final fresh = await _generation(db);
      expect(fresh.source, fresh.indexed);
    });

    test('failed rebuild rolls back and later query retries', () async {
      final roomId = await assets.saveRoom(
        areaId: 'area_search',
        name: 'Failure Room',
      );
      await search.rebuildIndex();
      await (db.update(db.rooms)..where((row) => row.id.equals(roomId))).write(
        const RoomsCompanion(notes: Value('RetryNeedle')),
      );

      final failing = DriftSearchRepository(
        db,
        beforeIndexCommit: () async {
          throw StateError('injected rebuild failure');
        },
      );
      await expectLater(failing.search('RetryNeedle'), throwsStateError);
      final dirty = await _generation(db);
      expect(dirty.source, greaterThan(dirty.indexed));

      final recovered = DriftSearchRepository(db);
      expect(
        await _hasResult(recovered, 'RetryNeedle', 'room', roomId),
        isTrue,
      );
      final fresh = await _generation(db);
      expect(fresh.source, fresh.indexed);
    });

    test('malformed state and missing FTS force recovery', () async {
      final roomId = await assets.saveRoom(
        areaId: 'area_search',
        name: 'Recovery Room',
        notes: 'RecoveryNeedle',
      );
      await search.rebuildIndex();

      await db.customStatement(
        'UPDATE search_index_state '
        'SET source_generation = 1, indexed_generation = 2 WHERE id = 1',
      );
      expect(
        await _hasResult(search, 'RecoveryNeedle', 'room', roomId),
        isTrue,
      );
      var state = await _generation(db);
      expect(state.source, state.indexed);

      await db.customStatement('DROP TABLE search_index');
      expect(
        await _hasResult(search, 'RecoveryNeedle', 'room', roomId),
        isTrue,
      );
      state = await _generation(db);
      expect(state.source, state.indexed);
    });
  });

  test('dirty generation self-recovers after process restart', () async {
    final file = File(
      '${Directory.systemTemp.path}/owntend_search_restart_'
      '${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    AppDatabase? db;
    try {
      db = AppDatabase(executor: NativeDatabase(file));
      final assets = DriftAssetRepository(db);
      await _seedSearchArea(assets);
      final roomId = await assets.saveRoom(
        areaId: 'area_search',
        name: 'Restart Room',
      );
      final search = DriftSearchRepository(db);
      await search.rebuildIndex();

      await (db.update(db.rooms)..where((row) => row.id.equals(roomId))).write(
        const RoomsCompanion(notes: Value('RestartNeedle')),
      );
      final dirty = await _generation(db);
      expect(dirty.source, greaterThan(dirty.indexed));
      await db.close();
      db = null;

      db = AppDatabase(executor: NativeDatabase(file));
      final reopenedSearch = DriftSearchRepository(db);
      expect(
        await _hasResult(reopenedSearch, 'RestartNeedle', 'room', roomId),
        isTrue,
      );
      final fresh = await _generation(db);
      expect(fresh.source, fresh.indexed);
    } finally {
      await db?.close();
      if (await file.exists()) {
        await file.delete();
      }
    }
  });
}

Future<void> _seedSearchArea(DriftAssetRepository assets) async {
  await assets.saveArea(
    id: 'area_search',
    name: 'Search Area',
    kind: AreaKind.indoor,
  );
}

Future<bool> _hasResult(
  DriftSearchRepository search,
  String query,
  String entityType,
  String entityId,
) async {
  final results = await search.search(query);
  return results.any(
    (result) => result.entityType == entityType && result.entityId == entityId,
  );
}

Future<({int source, int indexed})> _generation(AppDatabase db) async {
  final row = await db
      .customSelect(
        'SELECT source_generation, indexed_generation '
        'FROM search_index_state WHERE id = 1',
      )
      .getSingle();
  return (
    source: row.read<int>('source_generation'),
    indexed: row.read<int>('indexed_generation'),
  );
}
