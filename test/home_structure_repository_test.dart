import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/services/weather_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  group('home structure repository', () {
    late AppDatabase db;
    late DriftAssetRepository repo;

    setUp(() async {
      db = AppDatabase(executor: NativeDatabase.memory());
      repo = DriftAssetRepository(db);
      await _seedTestAreas(repo);
    });

    tearDown(() async {
      await db.close();
    });

    test('starts without demo areas or rooms', () async {
      final freshDb = AppDatabase(executor: NativeDatabase.memory());
      final freshRepo = DriftAssetRepository(freshDb);
      addTearDown(freshDb.close);
      final areas = await freshRepo.listAreas();
      final rooms = await freshRepo.listRooms();

      expect(areas, isEmpty);
      expect(rooms, isEmpty);
    });

    test('dashboard stream ignores unrelated settings writes', () async {
      final maintenance = DriftMaintenanceRepository(db);
      final statistics = DriftStatisticsRepository(
        db,
        maintenance,
        DatabaseStreakService(db),
      );
      final firstSummary = Completer<void>();
      var emissionCount = 0;
      final subscription = statistics.watchDashboardSummary().listen((_) {
        emissionCount++;
        if (!firstSummary.isCompleted) {
          firstSummary.complete();
        }
      });
      addTearDown(subscription.cancel);

      await firstSummary.future.timeout(const Duration(seconds: 2));
      await DriftSettingsRepository(db)
          .setProfile(nickname: 'Unrelated profile update');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(emissionCount, 1);
    });

    test(
      'task detail stream ignores unrelated writes and emits real changes',
      () async {
        final maintenance = DriftMaintenanceRepository(db);
        final categories = await repo.listCategories();
        final roomId = await repo.saveRoom(
          areaId: 'area_first_floor',
          name: 'Utility',
        );
        final assetId = await repo.saveAsset(
          name: 'Water heater',
          categoryId: _categoryId(categories, HealthGroup.other),
          roomId: roomId,
        );
        final planId = await maintenance.savePlan(
          assetId: assetId,
          title: 'Inspect heater',
          recurrence: const RecurrenceRule(
            interval: 1,
            unit: RecurrenceUnit.months,
          ),
          priority: PriorityLevel.medium,
          nextDueDate: DateTime(2026, 7, 1),
          healthGroup: HealthGroup.other,
        );
        final initial = Completer<void>();
        final changed = Completer<void>();
        var emissionCount = 0;
        final subscription = maintenance.watchTask(planId).listen((task) {
          emissionCount++;
          if (!initial.isCompleted) {
            initial.complete();
          }
          if (task?.plan.title == 'Inspect heater safely' &&
              !changed.isCompleted) {
            changed.complete();
          }
        });
        addTearDown(subscription.cancel);

        await initial.future.timeout(const Duration(seconds: 2));
        await DriftSettingsRepository(db)
            .setProfile(nickname: 'Unrelated profile update');
        await Future<void>.delayed(const Duration(milliseconds: 180));
        expect(emissionCount, 1);

        await maintenance.savePlan(
          id: planId,
          assetId: assetId,
          title: 'Inspect heater safely',
          recurrence: const RecurrenceRule(
            interval: 1,
            unit: RecurrenceUnit.months,
          ),
          priority: PriorityLevel.medium,
          nextDueDate: DateTime(2026, 7, 1),
          healthGroup: HealthGroup.other,
        );
        await changed.future.timeout(const Duration(seconds: 2));

        expect(emissionCount, 2);
      },
    );

    test(
      'item detail stream tracks detail rows without duplicate emissions',
      () async {
        final categories = await repo.listCategories();
        final roomId = await repo.saveRoom(
          areaId: 'area_first_floor',
          name: 'Laundry',
        );
        final assetId = await repo.saveAsset(
          name: 'Washer',
          assetType: AssetType.device,
          categoryId: _categoryId(categories, HealthGroup.appliances),
          roomId: roomId,
          deviceDetails: const DeviceDetails(brand: 'LG'),
        );
        final initial = Completer<void>();
        final changed = Completer<void>();
        var emissionCount = 0;
        final subscription = repo.watchAsset(assetId).listen((asset) {
          emissionCount++;
          if (!initial.isCompleted) {
            initial.complete();
          }
          if (asset?.deviceDetails?.model == 'ThinQ' && !changed.isCompleted) {
            changed.complete();
          }
        });
        addTearDown(subscription.cancel);

        await initial.future.timeout(const Duration(seconds: 2));
        await DriftSettingsRepository(db)
            .setProfile(nickname: 'Another unrelated update');
        await Future<void>.delayed(const Duration(milliseconds: 180));
        expect(emissionCount, 1);

        await repo.saveAsset(
          id: assetId,
          name: 'Washer',
          assetType: AssetType.device,
          categoryId: _categoryId(categories, HealthGroup.appliances),
          roomId: roomId,
          deviceDetails: const DeviceDetails(brand: 'LG', model: 'ThinQ'),
        );
        await changed.future.timeout(const Duration(seconds: 2));

        expect(emissionCount, 2);
      },
    );

    test(
      'statistics stream ignores unrelated writes and coalesces completion',
      () async {
        final maintenance = DriftMaintenanceRepository(db);
        final statistics = DriftStatisticsRepository(
          db,
          maintenance,
          DatabaseStreakService(db),
        );
        final categories = await repo.listCategories();
        final roomId = await repo.saveRoom(
          areaId: 'area_first_floor',
          name: 'Office',
        );
        final assetId = await repo.saveAsset(
          name: 'Air purifier',
          categoryId: _categoryId(categories, HealthGroup.other),
          roomId: roomId,
        );
        final planId = await maintenance.savePlan(
          assetId: assetId,
          title: 'Replace filter',
          recurrence: const RecurrenceRule(
            interval: 1,
            unit: RecurrenceUnit.months,
          ),
          priority: PriorityLevel.medium,
          nextDueDate: DateTime(2026, 6, 1),
          healthGroup: HealthGroup.other,
        );
        final initial = Completer<void>();
        final changed = Completer<void>();
        var emissionCount = 0;
        final subscription = statistics.watchStatisticsSummary().listen((
          summary,
        ) {
          emissionCount++;
          if (!initial.isCompleted) {
            initial.complete();
          }
          if (summary.completedByMonth.isNotEmpty && !changed.isCompleted) {
            changed.complete();
          }
        });
        addTearDown(subscription.cancel);

        await initial.future.timeout(const Duration(seconds: 2));
        await DriftSettingsRepository(db)
            .setProfile(nickname: 'Unrelated statistics update');
        await Future<void>.delayed(const Duration(milliseconds: 180));
        expect(emissionCount, 1);

        await maintenance.completePlan(
          planId,
          completedAt: DateTime(2026, 7, 1),
        );
        await changed.future.timeout(const Duration(seconds: 2));

        expect(emissionCount, 2);
      },
    );

    test('allows duplicate room names in different areas', () async {
      await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Kitchen',
        roomType: RoomType.kitchen,
      );
      await repo.saveRoom(
        areaId: 'area_second_floor',
        name: 'Kitchen',
        roomType: RoomType.kitchen,
      );

      final kitchens = (await repo.listRooms())
          .where((room) => room.name == 'Kitchen')
          .toList();

      expect(kitchens, hasLength(2));
      expect(
        kitchens.map((room) => room.areaId),
        containsAll(['area_first_floor', 'area_second_floor']),
      );
    });

    test('preserves area and room sort order when editing names', () async {
      final area = await (db.select(
        db.areas,
      )..where((row) => row.id.equals('area_second_floor'))).getSingle();
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Laundry',
        sortOrder: 7,
      );

      await repo.saveArea(
        id: area.id,
        name: 'Upper Floor',
        kind: AreaKind.indoor,
      );
      await repo.saveRoom(
        id: roomId,
        areaId: 'area_first_floor',
        name: 'Laundry Room',
      );

      final updatedArea = await (db.select(
        db.areas,
      )..where((row) => row.id.equals(area.id))).getSingle();
      final updatedRoom = await (db.select(
        db.rooms,
      )..where((row) => row.id.equals(roomId))).getSingle();

      expect(updatedArea.sortOrder, area.sortOrder);
      expect(updatedRoom.sortOrder, 7);
    });

    test('creates things with each detail type', () async {
      final categories = await repo.listCategories();
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Kitchen',
        roomType: RoomType.kitchen,
      );

      await repo.saveAsset(
        name: 'Washer',
        assetType: AssetType.device,
        categoryId: _categoryId(categories, HealthGroup.appliances),
        roomId: roomId,
        placement: 'Laundry wall',
        deviceDetails: const DeviceDetails(
          brand: 'LG',
          model: 'ThinQ',
          serialNumber: 'SN-1',
          powerSource: PowerSource.mains,
          consumable: 'Detergent',
        ),
      );
      await repo.saveAsset(
        name: 'Milo',
        assetType: AssetType.pet,
        categoryId: _categoryId(categories, HealthGroup.pets),
        roomId: roomId,
        petDetails: const PetDetails(
          species: 'Cat',
          breed: 'Domestic shorthair',
          microchipId: 'chip-1',
        ),
      );
      await repo.saveAsset(
        name: 'Aloe',
        assetType: AssetType.plant,
        categoryId: _categoryId(categories, HealthGroup.plants),
        roomId: roomId,
        plantDetails: const PlantDetails(
          species: 'Aloe vera',
          sunlight: Sunlight.brightIndirect,
          wateringIntervalDays: 14,
        ),
      );
      await repo.saveAsset(
        name: 'Smoke detector',
        assetType: AssetType.safety,
        categoryId: _categoryId(categories, HealthGroup.safety),
        roomId: roomId,
        safetyDetails: const SafetyDetails(
          safetyType: 'Smoke detector',
          batteryType: '9V',
          testIntervalDays: 30,
        ),
      );
      await repo.saveAsset(
        name: 'Storage bin',
        assetType: AssetType.general,
        categoryId: _categoryId(categories, HealthGroup.other),
        roomId: roomId,
      );

      final assets = {
        for (final asset in await repo.listAssets()) asset.name: asset,
      };

      expect(assets['Washer']?.assetType, AssetType.device);
      expect(assets['Washer']?.deviceDetails?.brand, 'LG');
      expect(assets['Milo']?.petDetails?.species, 'Cat');
      expect(assets['Aloe']?.plantDetails?.sunlight, Sunlight.brightIndirect);
      expect(assets['Smoke detector']?.safetyDetails?.batteryType, '9V');
      expect(assets['Storage bin']?.deviceDetails, isNull);
    });

    test(
      'plant watering interval updates only matching watering plans',
      () async {
        final maintenance = DriftMaintenanceRepository(db);
        final categories = await repo.listCategories();
        final roomId = await repo.saveRoom(
          areaId: 'area_first_floor',
          name: 'Plant shelf',
        );
        final assetId = await repo.saveAsset(
          name: 'Dieffenbachia',
          assetType: AssetType.plant,
          categoryId: _categoryId(categories, HealthGroup.plants),
          roomId: roomId,
          plantDetails: const PlantDetails(wateringIntervalDays: 7),
        );
        final wateringPlanId = await maintenance.savePlan(
          assetId: assetId,
          title: 'Water Dieffenbachia',
          recurrence: const RecurrenceRule(
            interval: 7,
            unit: RecurrenceUnit.days,
          ),
          priority: PriorityLevel.medium,
          nextDueDate: DateTime(2026, 7, 20),
          healthGroup: HealthGroup.plants,
        );
        final fertilizingPlanId = await maintenance.savePlan(
          assetId: assetId,
          title: 'Fertilize Dieffenbachia',
          recurrence: const RecurrenceRule(
            interval: 30,
            unit: RecurrenceUnit.days,
          ),
          priority: PriorityLevel.medium,
          nextDueDate: DateTime(2026, 7, 25),
          healthGroup: HealthGroup.plants,
        );
        final inspectionPlanId = await maintenance.savePlan(
          assetId: assetId,
          title: 'Inspect Dieffenbachia leaves',
          recurrence: const RecurrenceRule(
            interval: 7,
            unit: RecurrenceUnit.days,
          ),
          priority: PriorityLevel.medium,
          nextDueDate: DateTime(2026, 7, 26),
          healthGroup: HealthGroup.plants,
        );
        await db.customStatement('DELETE FROM offline_mutation_queue');

        await repo.saveAsset(
          id: assetId,
          name: 'Dieffenbachia',
          assetType: AssetType.plant,
          categoryId: _categoryId(categories, HealthGroup.plants),
          roomId: roomId,
          plantDetails: const PlantDetails(wateringIntervalDays: 5),
        );

        final plans = {
          for (final row in await db.select(db.maintenancePlans).get())
            row.id: row,
        };
        expect(plans[wateringPlanId]?.recurrenceInterval, 5);
        expect(plans[wateringPlanId]?.nextDueDate, DateTime(2026, 7, 20));
        expect(plans[fertilizingPlanId]?.recurrenceInterval, 30);
        expect(plans[inspectionPlanId]?.recurrenceInterval, 7);

        final outboxRows = await db
            .customSelect('SELECT entity FROM offline_mutation_queue')
            .get();
        final entities = outboxRows
            .map((row) => row.read<String>('entity'))
            .toList();
        expect(entities, contains('plant_detail'));
        expect(entities, contains('maintenance_plan'));
      },
    );

    test(
      'plant watering interval recalculates next due from last completion',
      () async {
        final maintenance = DriftMaintenanceRepository(db);
        final categories = await repo.listCategories();
        final roomId = await repo.saveRoom(
          areaId: 'area_first_floor',
          name: 'Sun room',
        );
        final assetId = await repo.saveAsset(
          name: 'Dieffenbachia',
          assetType: AssetType.plant,
          categoryId: _categoryId(categories, HealthGroup.plants),
          roomId: roomId,
          plantDetails: const PlantDetails(wateringIntervalDays: 7),
        );
        final planId = await maintenance.savePlan(
          assetId: assetId,
          title: 'Check Dieffenbachia soil moisture',
          recurrence: const RecurrenceRule(
            interval: 7,
            unit: RecurrenceUnit.days,
          ),
          priority: PriorityLevel.medium,
          nextDueDate: DateTime(2026, 7, 1, 9),
          healthGroup: HealthGroup.plants,
        );
        await maintenance.completePlan(
          planId,
          completedAt: DateTime(2026, 7, 1, 9),
        );

        await repo.saveAsset(
          id: assetId,
          name: 'Dieffenbachia',
          assetType: AssetType.plant,
          categoryId: _categoryId(categories, HealthGroup.plants),
          roomId: roomId,
          plantDetails: const PlantDetails(wateringIntervalDays: 5),
        );

        final plan = await (db.select(
          db.maintenancePlans,
        )..where((row) => row.id.equals(planId))).getSingle();
        expect(plan.recurrenceInterval, 5);
        expect(plan.nextDueDate, DateTime(2026, 7, 6, 9));
      },
    );

    test('archives things and empty rooms from active lists', () async {
      final categories = await repo.listCategories();
      final roomId = await repo.saveRoom(
        areaId: 'area_second_floor',
        name: 'Spare Room',
      );
      final assetId = await repo.saveAsset(
        name: 'Spare lamp',
        assetType: AssetType.device,
        categoryId: _categoryId(categories, HealthGroup.appliances),
        roomId: roomId,
      );

      expect(() => repo.archiveRoom(roomId), throwsStateError);

      await repo.archiveAsset(assetId);
      expect(await repo.listAssets(roomId: roomId), isEmpty);

      await repo.archiveRoom(roomId);
      expect(
        (await repo.listRooms(areaId: 'area_second_floor'))
            .map((room) => room.id),
        isNot(contains(roomId)),
      );
    });

    test('moves and copies items with active tasks', () async {
      final maintenance = DriftMaintenanceRepository(db);
      final categories = await repo.listCategories();
      final sourceRoomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Kitchen',
      );
      final targetRoomId = await repo.saveRoom(
        areaId: 'area_second_floor',
        name: 'Utility',
      );
      final assetId = await repo.saveAsset(
        name: 'Water filter',
        assetType: AssetType.device,
        categoryId: _categoryId(categories, HealthGroup.appliances),
        roomId: sourceRoomId,
        placement: 'Under sink',
        tagNames: ['filter', 'kitchen'],
        deviceDetails: const DeviceDetails(
          brand: 'Acme',
          model: 'WF-1',
          serialNumber: '123',
        ),
      );
      await maintenance.savePlan(
        assetId: assetId,
        title: 'Replace cartridge',
        recurrence: const RecurrenceRule(
          interval: 6,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.high,
        nextDueDate: DateTime(2026, 2),
        healthGroup: HealthGroup.appliances,
        metadata: const TaskMetadata(
          estimatedDurationMinutes: 20,
          requiredMaterials: ['Filter cartridge'],
        ),
      );

      await repo.moveAsset(assetId: assetId, roomId: targetRoomId);
      final moved = await repo.getAsset(assetId);
      expect(moved?.roomId, targetRoomId);
      expect(await maintenance.listTasksForAsset(assetId), hasLength(1));

      final copiedAssetId = await repo.copyAsset(
        assetId: assetId,
        roomId: sourceRoomId,
        includeTasks: true,
        includePhotos: false,
      );
      final copied = await repo.getAsset(copiedAssetId);
      final copiedTasks = await maintenance.listTasksForAsset(copiedAssetId);
      final copiedTags = await repo.listTagsForAsset(copiedAssetId);

      expect(copiedAssetId, isNot(assetId));
      expect(copied?.roomId, sourceRoomId);
      expect(copied?.deviceDetails?.serialNumber, '123');
      expect(
        copiedTags.map((tag) => tag.name),
        containsAll(['filter', 'kitchen']),
      );
      expect(copiedTasks, hasLength(1));
      expect(copiedTasks.single.plan.title, 'Replace cartridge');
      expect(copiedTasks.single.plan.metadata?.estimatedDurationMinutes, 20);
    });

    test('trashes and restores rooms with nested items and tasks', () async {
      final maintenance = DriftMaintenanceRepository(db);
      final categories = await repo.listCategories();
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Workshop',
      );
      final assetId = await repo.saveAsset(
        name: 'Air compressor',
        assetType: AssetType.device,
        categoryId: _categoryId(categories, HealthGroup.appliances),
        roomId: roomId,
      );
      final planId = await maintenance.savePlan(
        assetId: assetId,
        title: 'Drain tank',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: DateTime(2026, 3),
        healthGroup: HealthGroup.appliances,
      );

      await repo.trashRoom(roomId);

      expect(
        (await repo.listRooms()).map((room) => room.id),
        isNot(contains(roomId)),
      );
      expect(
        (await repo.listAssets()).map((asset) => asset.id),
        isNot(contains(assetId)),
      );
      expect(
        (await maintenance.listTasks()).map((task) => task.plan.id),
        isNot(contains(planId)),
      );
      expect(
        (await repo.listArchivedRooms()).map((room) => room.id),
        contains(roomId),
      );
      expect(
        (await repo.listArchivedAssets()).map((asset) => asset.id),
        contains(assetId),
      );
      expect(
        (await maintenance.listArchivedTasks()).map((task) => task.plan.id),
        contains(planId),
      );

      await repo.restoreRoom(roomId);

      expect((await repo.listRooms()).map((room) => room.id), contains(roomId));
      expect(
        (await repo.listAssets()).map((asset) => asset.id),
        contains(assetId),
      );
      expect(
        (await maintenance.listTasks()).map((task) => task.plan.id),
        contains(planId),
      );
    });

    test('disables and re-enables tasks without losing history', () async {
      final clock = DateTime(2026, 6, 18, 12);
      final maintenance = DriftMaintenanceRepository(db, now: () => clock);
      final categories = await repo.listCategories();
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Laundry',
      );
      final assetId = await repo.saveAsset(
        name: 'Washer',
        assetType: AssetType.device,
        categoryId: _categoryId(categories, HealthGroup.appliances),
        roomId: roomId,
      );
      final originalDue = DateTime(2026, 1, 1, 9);
      final planId = await maintenance.savePlan(
        assetId: assetId,
        title: 'Clean lint filter',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.days,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: originalDue,
        healthGroup: HealthGroup.appliances,
      );
      await db
          .into(db.maintenanceRecords)
          .insert(
            MaintenanceRecordsCompanion.insert(
              id: 'record-clean-lint',
              planId: planId,
              dueDate: originalDue,
              completedAt: Value(DateTime(2026, 1, 1, 10)),
            ),
          );

      await maintenance.setTaskEnabled(planId, false);

      expect(await maintenance.listTasks(), isEmpty);
      final savedDisabled = (await maintenance.listSavedTasks()).single;
      expect(savedDisabled.plan.isEnabled, isFalse);
      expect(savedDisabled.plan.nextDueDate, originalDue);
      expect(await maintenance.completePlan(planId), isFalse);
      expect(await maintenance.listRecordsForPlan(planId), hasLength(1));

      await maintenance.setTaskEnabled(planId, true);

      final active = (await maintenance.listTasks()).single;
      expect(active.plan.isEnabled, isTrue);
      expect(active.plan.nextDueDate.isAfter(clock), isTrue);
      expect(active.plan.nextDueDate, DateTime(2026, 6, 19, 12));
      expect(await maintenance.listRecordsForPlan(planId), hasLength(1));
    });

    test('skips and postpones one task occurrence with reason notes', () async {
      final maintenance = DriftMaintenanceRepository(db);
      final categories = await repo.listCategories();
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Bathroom',
      );
      final assetId = await repo.saveAsset(
        name: 'Exhaust fan',
        assetType: AssetType.device,
        categoryId: _categoryId(categories, HealthGroup.appliances),
        roomId: roomId,
      );
      final planId = await maintenance.savePlan(
        assetId: assetId,
        title: 'Clean vent cover',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.weeks,
        ),
        priority: PriorityLevel.low,
        nextDueDate: DateTime(2026, 1, 1, 9),
        healthGroup: HealthGroup.cleaning,
      );

      await maintenance.skipPlanOccurrence(
        planId,
        skippedAt: DateTime(2026, 1, 1, 10),
        reason: 'Already clean',
      );
      expect(
        (await maintenance.getTask(planId))?.plan.nextDueDate,
        DateTime(2026, 1, 8, 9),
      );

      await maintenance.postponePlan(
        planId,
        DateTime(2026, 1, 10, 9),
        reason: 'Waiting for supplies',
      );
      expect(
        (await maintenance.getTask(planId))?.plan.nextDueDate,
        DateTime(2026, 1, 10, 9),
      );
    });

    test('permanently deletes plans with records and notifications', () async {
      final maintenance = DriftMaintenanceRepository(db);
      final categories = await repo.listCategories();
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Laundry',
      );
      final assetId = await repo.saveAsset(
        name: 'Washer',
        assetType: AssetType.device,
        categoryId: _categoryId(categories, HealthGroup.appliances),
        roomId: roomId,
      );
      final planId = await maintenance.savePlan(
        assetId: assetId,
        title: 'Clean filter',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: DateTime(2026),
        healthGroup: HealthGroup.appliances,
      );
      await maintenance.completePlan(planId, completedAt: DateTime(2026, 1, 2));
      await db
          .into(db.appNotifications)
          .insert(
            AppNotificationsCompanion.insert(
              id: 'notification_filter',
              planId: planId,
              channel: 'due',
              scheduledFor: DateTime(2026, 1, 1),
            ),
          );

      await maintenance.deletePlan(planId);

      expect(await db.select(db.maintenancePlans).get(), isEmpty);
      expect(await db.select(db.maintenanceRecords).get(), isEmpty);
      expect(await db.select(db.appNotifications).get(), isEmpty);
    });

    test('completes a plan once and preserves completion time', () async {
      final maintenance = DriftMaintenanceRepository(db);
      final categories = await repo.listCategories();
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Aquarium',
      );
      final assetId = await repo.saveAsset(
        name: 'Goldfish tank',
        assetType: AssetType.pet,
        categoryId: _categoryId(categories, HealthGroup.pets),
        roomId: roomId,
      );
      final originalDue = DateTime(2026, 6, 15, 8, 30);
      final completedAt = DateTime.utc(2026, 6, 15, 18, 45, 12);
      final planId = await maintenance.savePlan(
        assetId: assetId,
        title: 'Clean tank filter',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.weeks,
        ),
        priority: PriorityLevel.high,
        nextDueDate: originalDue,
        healthGroup: HealthGroup.pets,
      );

      final first = await maintenance.completePlan(
        planId,
        completedAt: completedAt,
        expectedNextDueDate: originalDue,
      );
      final duplicate = await maintenance.completePlan(
        planId,
        completedAt: completedAt,
        expectedNextDueDate: originalDue,
      );
      final updated = await maintenance.getTask(planId);
      final records = await maintenance.listRecordsForPlan(planId);

      expect(first, isTrue);
      expect(duplicate, isFalse);
      expect(records, hasLength(1));
      expect(records.single.dueDate, originalDue);
      expect(
        updated?.plan.nextDueDate.toUtc(),
        DateTime.utc(2026, 6, 22, 18, 45, 12),
      );
    });

    test('streak refresh counts completions due today with a time', () async {
      final maintenance = DriftMaintenanceRepository(db);
      final streaks = DatabaseStreakService(db);
      final categories = await repo.listCategories();
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Plants',
      );
      final assetId = await repo.saveAsset(
        name: 'Fern',
        assetType: AssetType.plant,
        categoryId: _categoryId(categories, HealthGroup.plants),
        roomId: roomId,
      );
      final dueToday = DateTime(2026, 6, 15, 8, 30);
      final planId = await maintenance.savePlan(
        assetId: assetId,
        title: 'Water fern',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.weeks,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: dueToday,
        healthGroup: HealthGroup.plants,
      );

      await maintenance.completePlan(
        planId,
        completedAt: DateTime(2026, 6, 15, 9),
      );
      final streak = await streaks.refresh(DateTime(2026, 6, 15, 22));

      expect(streak.currentStreak, 1);
      expect(streak.lastCompletedDate, DateTime(2026, 6, 15));
    });

    test('does not crash when completing a missing plan', () async {
      final maintenance = DriftMaintenanceRepository(db);

      final completed = await maintenance.completePlan('missing_plan');

      expect(completed, isFalse);
    });

    test(
      'rejects maintenance plans for missing assets before SQLite insert',
      () async {
        final maintenance = DriftMaintenanceRepository(db);

        expect(
          () => maintenance.savePlan(
            assetId: 'Dieffenbachia',
            title: 'Prune Dieffenbachia',
            recurrence: const RecurrenceRule(
              interval: 30,
              unit: RecurrenceUnit.days,
            ),
            priority: PriorityLevel.low,
            nextDueDate: DateTime(2026, 6, 21),
            healthGroup: HealthGroup.plants,
          ),
          throwsA(
            isA<MaintenancePlanValidationException>().having(
              (error) => error.message,
              'message',
              isNot(contains('SqliteException')),
            ),
          ),
        );
        expect(await db.select(db.maintenancePlans).get(), isEmpty);
      },
    );

    test('rejects maintenance plans for archived assets', () async {
      final maintenance = DriftMaintenanceRepository(db);
      final categories = await repo.listCategories();
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Plant room',
      );
      final assetId = await repo.saveAsset(
        name: 'Dieffenbachia',
        assetType: AssetType.plant,
        categoryId: _categoryId(categories, HealthGroup.plants),
        roomId: roomId,
      );
      await repo.archiveAsset(assetId);

      expect(
        () => maintenance.savePlan(
          assetId: assetId,
          title: 'Prune Dieffenbachia',
          recurrence: const RecurrenceRule(
            interval: 30,
            unit: RecurrenceUnit.days,
          ),
          priority: PriorityLevel.low,
          nextDueDate: DateTime(2026, 6, 21),
          healthGroup: HealthGroup.plants,
        ),
        throwsA(isA<MaintenancePlanValidationException>()),
      );
      expect(await db.select(db.maintenancePlans).get(), isEmpty);
    });

    test('permanently deletes things with dependent rows', () async {
      final maintenance = DriftMaintenanceRepository(db);
      final categories = await repo.listCategories();
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Utility',
      );
      final assetId = await repo.saveAsset(
        name: 'Dryer',
        assetType: AssetType.device,
        categoryId: _categoryId(categories, HealthGroup.appliances),
        roomId: roomId,
        tagNames: ['lint'],
        deviceDetails: const DeviceDetails(brand: 'LG'),
      );
      final planId = await maintenance.savePlan(
        assetId: assetId,
        title: 'Clear lint',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.high,
        nextDueDate: DateTime(2026),
        healthGroup: HealthGroup.appliances,
      );
      await maintenance.completePlan(planId, completedAt: DateTime(2026, 1, 2));
      await db
          .into(db.assetPhotos)
          .insert(
            AssetPhotosCompanion.insert(
              id: 'photo_dryer',
              assetId: assetId,
              relativePath: 'photos/$assetId/photo_dryer.jpg',
              caption: const Value('Vent'),
            ),
          );

      await repo.deleteAsset(assetId);

      expect(await repo.listAssets(roomId: roomId), isEmpty);
      expect(await maintenance.listTasks(), isEmpty);
      expect(await db.select(db.deviceDetailsTable).get(), isEmpty);
      expect(await db.select(db.assetTags).get(), isEmpty);
      expect(await db.select(db.assetPhotos).get(), isEmpty);
      expect(await db.select(db.maintenanceRecords).get(), isEmpty);
    });

    test(
      'keeps current primary photo when requested primary is missing',
      () async {
        final categories = await repo.listCategories();
        final roomId = await repo.saveRoom(
          areaId: 'area_first_floor',
          name: 'Office',
        );
        final assetId = await repo.saveAsset(
          name: 'Desk lamp',
          categoryId: _categoryId(categories, HealthGroup.other),
          roomId: roomId,
        );
        await db
            .into(db.assetPhotos)
            .insert(
              AssetPhotosCompanion.insert(
                id: 'photo_primary',
                assetId: assetId,
                relativePath: 'photos/$assetId/photo_primary.jpg',
                isPrimary: const Value(true),
              ),
            );
        await db
            .into(db.assetPhotos)
            .insert(
              AssetPhotosCompanion.insert(
                id: 'photo_secondary',
                assetId: assetId,
                relativePath: 'photos/$assetId/photo_secondary.jpg',
                isPrimary: const Value(false),
              ),
            );

        await repo.setPrimaryPhoto(assetId, 'missing_photo');

        final photos = await repo.listPhotosForAsset(assetId);
        expect(
          photos.singleWhere((photo) => photo.id == 'photo_primary').isPrimary,
          isTrue,
        );
        expect(
          photos
              .singleWhere((photo) => photo.id == 'photo_secondary')
              .isPrimary,
          isFalse,
        );
      },
    );

    test('notification inbox tracks unread and read state', () async {
      final inbox = DriftNotificationInboxRepository(db);

      await inbox.createNotification(
        title: 'Weather changed',
        body: 'Review outdoor tasks.',
        kind: 'weather',
        route: '/maintenance',
      );

      var items = await inbox.listNotifications();
      expect(items, hasLength(1));
      expect(items.single.unread, isTrue);
      expect(await inbox.unreadCount(), 1);

      await inbox.markRead(items.single.id);
      items = await inbox.listNotifications();

      expect(items.single.unread, isFalse);
      expect(await inbox.unreadCount(), 0);
    });

    test('notification inbox deduplicates recent matching updates', () async {
      final inbox = DriftNotificationInboxRepository(db);

      await inbox.createNotification(
        title: 'Storm may affect home tasks',
        body: '70% precipitation expected.',
        kind: 'weather',
        route: '/maintenance',
      );
      await inbox.createNotification(
        title: 'Storm may affect home tasks',
        body: 'Wind and precipitation increased.',
        kind: 'weather',
        route: '/maintenance',
      );

      final items = await inbox.listNotifications();

      expect(items, hasLength(1));
      expect(items.single.kind, 'weather');
    });

    test('notification preferences round-trip through settings', () async {
      final settings = DriftSettingsRepository(db);

      await settings.setNotificationPreferences(
        const NotificationPreferences(
          enabled: false,
          localReminders: false,
          weatherAlerts: false,
          quietHoursEnabled: true,
          privacyMode: true,
          dailyDigest: false,
          digestHour: 20,
          reminderHour: 8,
          maxRemindersPerDay: 3,
          defaultSnoozeMinutes: 180,
          preferExactReminders: false,
        ),
      );

      final preferences = await settings.notificationPreferences();

      expect(preferences.enabled, isFalse);
      expect(preferences.localReminders, isFalse);
      expect(preferences.weatherAlerts, isFalse);
      expect(preferences.quietHoursEnabled, isTrue);
      expect(preferences.privacyMode, isTrue);
      expect(preferences.dailyDigest, isFalse);
      expect(preferences.digestHour, 20);
      expect(preferences.reminderHour, 8);
      expect(preferences.maxRemindersPerDay, 3);
      expect(preferences.defaultSnoozeMinutes, 180);
      expect(preferences.preferExactReminders, isFalse);
    });

    test('notification preferences default missing new JSON fields', () async {
      final settings = DriftSettingsRepository(db);
      await db
          .into(db.settings)
          .insert(
            SettingsCompanion.insert(
              key: 'notification_preferences',
              value: '{"enabled":true,"localReminders":true,"maxRemindersPerDay":4}',
              updatedAt: Value(DateTime(2026)),
            ),
          );

      final preferences = await settings.notificationPreferences();

      expect(preferences.enabled, isTrue);
      expect(preferences.localReminders, isTrue);
      expect(preferences.maxRemindersPerDay, 4);
      expect(preferences.defaultSnoozeMinutes, 60);
      expect(preferences.preferExactReminders, isFalse);
    });

    test(
      'legacy disabled notifications stay disabled in watched state',
      () async {
        await (db.update(db.settings)
              ..where((setting) => setting.key.equals('notifications_enabled')))
            .write(
              SettingsCompanion(
                value: const Value('false'),
                updatedAt: Value(DateTime.now()),
              ),
            );
        final settings = DriftSettingsRepository(db);

        expect((await settings.notificationPreferences()).enabled, isFalse);
        expect(
          (await settings.watchNotificationPreferences().first).enabled,
          isFalse,
        );
      },
    );

    test('app language preference persists through settings', () async {
      final settings = DriftSettingsRepository(db);

      expect(await settings.appLanguage(), AppLanguage.en);
      expect(
        await settings.appLocalePreference(),
        isA<AppLocalePreference>()
            .having((value) => value.language, 'language', AppLanguage.en)
            .having((value) => value.isExplicit, 'isExplicit', isFalse),
      );

      await settings.setAppLanguage(AppLanguage.ar);

      expect(await settings.appLanguage(), AppLanguage.ar);
      final preference = await settings.appLocalePreference();
      expect(preference.language, AppLanguage.ar);
      expect(preference.isExplicit, isTrue);
      final rows =
          await (db.select(db.settings)..where(
                (row) =>
                    row.key.isIn(['app_language', 'app_language_explicit']),
              ))
              .get();
      expect(rows, hasLength(2));
      expect(rows.map((row) => row.updatedAt).toSet(), hasLength(1));
    });

    test('weather cache parses humidity', () async {
      await db
          .into(db.settings)
          .insert(
            SettingsCompanion.insert(
              key: 'weather_cache',
              value: '''
{
  "location": {
    "label": "Baghdad, IQ",
    "latitude": 33.3152,
    "longitude": 44.3661,
    "source": "manual"
  },
  "updatedAt": "2026-06-18T09:30:00.000",
  "temperature": 31.5,
  "apparentTemperature": 33.2,
  "weatherCode": 1,
  "windSpeed": 12.4,
  "precipitation": 0.0,
  "humidity": 41,
  "forecast": []
}
''',
              updatedAt: Value(DateTime(2026, 6, 18, 9, 30)),
            ),
          );
      final weather = OpenMeteoWeatherRepository(
        db: db,
        settingsRepository: DriftSettingsRepository(db),
      );

      final snapshot = await weather.cachedWeather();

      expect(snapshot?.location.label, 'Baghdad, IQ');
      expect(snapshot?.humidity, 41);
      expect(snapshot?.apparentTemperature, 33.2);
    });

    test(
      'weather refresh keeps the API timezone for device locations',
      () async {
        final settings = DriftSettingsRepository(db);
        await settings.setHomeLocation(
          const HomeLocation(
            label: 'Device location',
            latitude: 33.3152,
            longitude: 44.3661,
            source: 'device',
          ),
        );
        final weather = OpenMeteoWeatherRepository(
          db: db,
          settingsRepository: settings,
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'timezone': 'Asia/Baghdad',
                'current': {
                  'temperature_2m': 31,
                  'apparent_temperature': 32,
                  'relative_humidity_2m': 40,
                  'precipitation': 0,
                  'weather_code': 1,
                  'wind_speed_10m': 10,
                },
                'daily': {
                  'time': ['2026-06-28'],
                  'weather_code': [1],
                  'temperature_2m_max': [35],
                  'temperature_2m_min': [25],
                  'precipitation_probability_max': [0],
                  'wind_speed_10m_max': [15],
                },
              }),
              200,
            ),
          ),
        );

        final snapshot = await weather.refreshWeather();

        expect(snapshot?.location.timezone, 'Asia/Baghdad');
        expect(
          (await weather.cachedWeather())?.location.timezone,
          'Asia/Baghdad',
        );
      },
    );

    test('weather refresh coalesces concurrent background requests', () async {
      final settings = DriftSettingsRepository(db);
      await settings.setHomeLocation(
        const HomeLocation(
          label: 'Baghdad',
          latitude: 33.3152,
          longitude: 44.3661,
        ),
      );
      final response = Completer<http.Response>();
      var requestCount = 0;
      final weather = OpenMeteoWeatherRepository(
        db: db,
        settingsRepository: settings,
        httpClient: MockClient((_) {
          requestCount++;
          return response.future;
        }),
      );

      final first = weather.refreshWeather();
      final second = weather.refreshWeather();

      expect(identical(first, second), isTrue);
      response.complete(
        http.Response(
          jsonEncode({
            'timezone': 'Asia/Baghdad',
            'current': <String, Object?>{},
            'daily': <String, Object?>{},
          }),
          200,
        ),
      );
      await Future.wait([first, second]);

      expect(requestCount, 1);
    });

    test('permanently deletes rooms and nested things', () async {
      final maintenance = DriftMaintenanceRepository(db);
      final categories = await repo.listCategories();
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Basement',
      );
      final assetId = await repo.saveAsset(
        name: 'Pump',
        assetType: AssetType.device,
        categoryId: _categoryId(categories, HealthGroup.appliances),
        roomId: roomId,
      );
      await maintenance.savePlan(
        assetId: assetId,
        title: 'Inspect pump',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.high,
        nextDueDate: DateTime(2026),
        healthGroup: HealthGroup.appliances,
      );

      await repo.deleteRoom(roomId);

      expect(await repo.listRooms(areaId: 'area_first_floor'), isEmpty);
      expect(await repo.listAssets(), isEmpty);
      expect(await maintenance.listTasks(), isEmpty);
    });

    test('permanently deletes areas and nested rooms', () async {
      final categories = await repo.listCategories();
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Office',
      );
      await repo.saveAsset(
        name: 'Router',
        assetType: AssetType.device,
        categoryId: _categoryId(categories, HealthGroup.appliances),
        roomId: roomId,
      );

      await repo.deleteArea('area_first_floor');

      expect(
        (await repo.listAreas()).map((area) => area.id),
        isNot(contains('area_first_floor')),
      );
      expect(await repo.listRooms(areaId: 'area_first_floor'), isEmpty);
      expect(await repo.listAssets(), isEmpty);
    });

    test('indexes areas, rooms, thing details, and tags', () async {
      final categories = await repo.listCategories();
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Kitchen',
        roomType: RoomType.kitchen,
      );
      await repo.saveAsset(
        name: 'Care kit',
        assetType: AssetType.pet,
        categoryId: _categoryId(categories, HealthGroup.pets),
        roomId: roomId,
        placement: 'Mudroom shelf',
        tagNames: ['wellness'],
        petDetails: const PetDetails(microchipId: 'chip-needle'),
      );
      await repo.saveAsset(
        name: 'مكيف الصالة',
        assetType: AssetType.device,
        categoryId: _categoryId(categories, HealthGroup.appliances),
        roomId: roomId,
        placement: 'الجدار الرئيسي',
        tagNames: ['تبريد'],
      );

      final search = DriftSearchRepository(db);
      await search.rebuildIndex();

      expect(
        await search.search('First'),
        anyElement(
          predicate<SearchResult>(
            (result) =>
                result.entityType == 'area' && result.title == 'First Floor',
          ),
        ),
      );
      expect(
        await search.search('Kitchen'),
        anyElement(
          predicate<SearchResult>(
            (result) =>
                result.entityType == 'room' && result.title == 'Kitchen',
          ),
        ),
      );
      expect(
        await search.search('chip'),
        anyElement(
          predicate<SearchResult>(
            (result) =>
                result.entityType == 'asset' && result.title == 'Care kit',
          ),
        ),
      );
      expect(
        await search.search('wellness'),
        anyElement(
          predicate<SearchResult>(
            (result) =>
                result.entityType == 'asset' && result.title == 'Care kit',
          ),
        ),
      );
      expect(
        await search.search('مكيف'),
        anyElement(
          predicate<SearchResult>(
            (result) =>
                result.entityType == 'asset' && result.title == 'مكيف الصالة',
          ),
        ),
      );
      expect(
        await search.search('تبريد'),
        anyElement(
          predicate<SearchResult>(
            (result) =>
                result.entityType == 'asset' && result.title == 'مكيف الصالة',
          ),
        ),
      );
    });
  });

  test('database reopen preserves streak state', () async {
    final root = await Directory.systemTemp.createTemp('owntend_reopen_');
    final file = File(p.join(root.path, AppDatabase.databaseFileName));
    AppDatabase? first;
    AppDatabase? reopened;
    try {
      first = AppDatabase(executor: NativeDatabase(file));
      await first.customSelect('SELECT 1').get();
      await first
          .into(first.streaks)
          .insertOnConflictUpdate(
            StreaksCompanion.insert(
              id: 'default',
              currentStreak: const Value(7),
              bestStreak: const Value(12),
              lastCompletedDate: Value(DateTime(2026, 6, 27)),
              updatedAt: Value(DateTime(2026, 6, 28)),
            ),
          );
      await first.close();
      first = null;

      reopened = AppDatabase(executor: NativeDatabase(file));
      await reopened.customSelect('SELECT 1').get();
      final streak = await DatabaseStreakService(reopened).current();

      expect(streak.currentStreak, 7);
      expect(streak.bestStreak, 12);
      expect(streak.lastCompletedDate, DateTime(2026, 6, 27));
    } finally {
      await first?.close();
      await reopened?.close();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });
}

String _categoryId(List<Category> categories, HealthGroup group) {
  return categories.singleWhere((category) => category.healthGroup == group).id;
}

Future<void> _seedTestAreas(AssetRepository repo) async {
  await repo.saveArea(
    id: 'area_first_floor',
    name: 'First Floor',
    kind: AreaKind.indoor,
    sortOrder: 0,
  );
  await repo.saveArea(
    id: 'area_second_floor',
    name: 'Second Floor',
    kind: AreaKind.indoor,
    sortOrder: 1,
  );
  await repo.saveArea(
    id: 'area_outdoor_garden',
    name: 'Outdoor',
    kind: AreaKind.outdoor,
    sortOrder: 2,
  );
}
