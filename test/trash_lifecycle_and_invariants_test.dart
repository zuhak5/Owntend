import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:owntend/src/core/data/repositories.dart';

import 'support/maintenance_test_extensions.dart';

import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class FakePathProviderPlatform extends PathProviderPlatform {
  FakePathProviderPlatform(this.tempDir);
  final Directory tempDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftAssetRepository assetRepo;
  late DriftMaintenanceRepository maintenanceRepo;
  late DriftSearchRepository searchRepo;
  late LocalSyncStore syncStore;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('owntend_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir);
    db = AppDatabase(executor: NativeDatabase.memory());
    assetRepo = DriftAssetRepository(db);
    maintenanceRepo = DriftMaintenanceRepository(db);
    searchRepo = DriftSearchRepository(db);
    syncStore = LocalSyncStore(db);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Trash and Empty Trash Lifecycle', () {
    test('emptyTrash cascades across all trashed entities and purges photo files', () async {
      // 1. Setup active area, room, asset, plan, and photo
      final areaId = await assetRepo.saveArea(
        name: 'Basement',
        kind: AreaKind.indoor,
      );
      final roomId = await assetRepo.saveRoom(
        areaId: areaId,
        name: 'Storage Room',
      );
      final assetId = await assetRepo.saveAsset(
        name: 'Dehumidifier',
        roomId: roomId,
        assetType: AssetType.device,
        deviceDetails: const DeviceDetails(
          brand: 'Frigidaire',
          model: 'FFAD5033W1',
        ),
      );

      final photoFile = File(p.join(tempDir.path, 'source_photo.jpg'));
      await _writeTestPhoto(photoFile, image.ColorRgb8(30, 100, 160));
      await assetRepo.addPhoto(assetId, photoFile.path);

      // Create a maintenance plan and complete it once
      final planDueDate = DateTime.utc(2026, 8, 20, 10, 0, 0);
      final planId = await maintenanceRepo.savePlan(
        assetId: assetId,
        title: 'Empty Water Bucket',
        recurrence: const RecurrenceRule(
          interval: 3,
          unit: RecurrenceUnit.days,
        ),
        priority: PriorityLevel.high,
        nextDueDate: planDueDate,
      );
      await maintenanceRepo.completeCurrentOccurrence(
        planId,
        completedAt: DateTime.utc(2026, 8, 20, 9, 0, 0),
      );

      await searchRepo.rebuildIndex();
      final initialSearchResults = await searchRepo.search('Dehumidifier');
      expect(initialSearchResults, isNotEmpty);

      // 2. Trash the area (cascading soft delete)
      await assetRepo.trashArea(areaId);

      // Verify soft delete state
      final trashedAreas = await assetRepo.listArchivedAreas();
      expect(trashedAreas.map((a) => a.id), contains(areaId));

      final activeTasks = await maintenanceRepo.listTasks();
      expect(activeTasks.any((t) => t.plan.id == planId), isFalse);

      await searchRepo.rebuildIndex();
      final searchAfterTrash = await searchRepo.search('Dehumidifier');
      expect(searchAfterTrash, isEmpty);

      // 3. Call emptyTrash
      await assetRepo.emptyTrash();

      // Verify all database tables are completely purged of the deleted records
      expect(await assetRepo.listArchivedAreas(), isEmpty);
      expect(await assetRepo.listArchivedRooms(), isEmpty);
      expect(await assetRepo.listArchivedAssets(), isEmpty);
      expect(await maintenanceRepo.listArchivedTasks(), isEmpty);
      expect(
        await (db.select(db.areas)..where((r) => r.id.equals(areaId))).get(),
        isEmpty,
      );
      expect(
        await (db.select(db.rooms)..where((r) => r.id.equals(roomId))).get(),
        isEmpty,
      );
      expect(
        await (db.select(db.assets)..where((r) => r.id.equals(assetId))).get(),
        isEmpty,
      );
      expect(
        await (db.select(
          db.maintenancePlans,
        )..where((r) => r.id.equals(planId))).get(),
        isEmpty,
      );
      expect(
        await (db.select(
          db.maintenanceRecords,
        )..where((r) => r.planId.equals(planId))).get(),
        isEmpty,
      );
      expect(
        await (db.select(
          db.deviceDetailsTable,
        )..where((r) => r.assetId.equals(assetId))).get(),
        isEmpty,
      );
      expect(
        await (db.select(
          db.assetPhotos,
        )..where((r) => r.assetId.equals(assetId))).get(),
        isEmpty,
      );

      // Verify photo directory on disk was deleted
      final assetPhotoDir = Directory(p.join(tempDir.path, 'photos', assetId));
      expect(await assetPhotoDir.exists(), isFalse);
    });
  });

  group('Recurrence Invariants & Early Completion', () {
    test(
      'Early completion resets nextDueDate from actual completion time',
      () async {
        final areaId = await assetRepo.saveArea(
          name: 'Garage',
          kind: AreaKind.indoor,
        );
        final roomId = await assetRepo.saveRoom(
          areaId: areaId,
          name: 'Main Garage',
        );
        final assetId = await assetRepo.saveAsset(
          name: 'Lawn Mower',
          roomId: roomId,
        );

        final scheduledDueDate = DateTime.utc(2026, 8, 30, 12, 0, 0);
        final planId = await maintenanceRepo.savePlan(
          assetId: assetId,
          title: 'Oil Check',
          recurrence: const RecurrenceRule(
            interval: 7,
            unit: RecurrenceUnit.days,
          ),
          priority: PriorityLevel.medium,
          nextDueDate: scheduledDueDate,
        );

        // Complete 10 days early on Aug 20
        final earlyCompletedAt = DateTime.utc(2026, 8, 20, 10, 0, 0);
        final result = await maintenanceRepo.completePlanResult(
          planId,
          expectedOccurrenceId: (await maintenanceRepo.getTask(planId))!
              .plan
              .currentOccurrenceId,
          completedAt: earlyCompletedAt,
        );

        expect(result.isApplied, isTrue);

        final updatedTask = await maintenanceRepo.getTask(planId);
        expect(updatedTask, isNotNull);

        expect(
          updatedTask!.plan.nextDueDate.toUtc(),
          equals(DateTime.utc(2026, 8, 27, 10, 0, 0)),
        );
      },
    );
  });

  group('Undo Completion Pre-Sync and Post-Sync', () {
    test(
      'Undo pre-sync removes outbox composite and restores previousDueDate',
      () async {
        final areaId = await assetRepo.saveArea(
          name: 'Living Room',
          kind: AreaKind.indoor,
        );
        final roomId = await assetRepo.saveRoom(
          areaId: areaId,
          name: 'Living Room',
        );
        final assetId = await assetRepo.saveAsset(
          name: 'AC Unit',
          roomId: roomId,
        );

        final initialDue = DateTime.utc(2026, 8, 15, 10, 0, 0);
        final planId = await maintenanceRepo.savePlan(
          assetId: assetId,
          title: 'Filter Cleaning',
          recurrence: const RecurrenceRule(
            interval: 14,
            unit: RecurrenceUnit.days,
          ),
          priority: PriorityLevel.medium,
          nextDueDate: initialDue,
        );

        final completion = await maintenanceRepo.completePlanResult(
          planId,
          expectedOccurrenceId: (await maintenanceRepo.getTask(planId))!
              .plan
              .currentOccurrenceId,
          completedAt: initialDue,
        );

        // Verify outbox has the completion mutation
        final outboxBefore = await (db.select(
          db.syncOutbox,
        )..where((r) => r.entity.equals('maintenance_completion'))).get();
        expect(outboxBefore, hasLength(1));

        // Call undo for the exact completion that produced the action.
        await maintenanceRepo.undoCompletion(
          planId: planId,
          completionId: completion.operationId!,
          completedOccurrenceId: completion.completedOccurrenceId!,
          expectedCurrentOccurrenceId: completion.nextOccurrenceId!,
          previousDueDate: completion.previousDueDate!,
          expectedCurrentNextDueDate: completion.nextDueDate!,
        );

        // Outbox composite must be deleted
        final outboxAfter = await (db.select(
          db.syncOutbox,
        )..where((r) => r.entity.equals('maintenance_completion'))).get();
        expect(outboxAfter, isEmpty);

        // Records must be deleted and plan nextDueDate restored
        final records = await maintenanceRepo.listRecordsForPlan(planId);
        expect(records, isEmpty);

        final restoredTask = await maintenanceRepo.getTask(planId);
        expect(restoredTask!.plan.nextDueDate.toUtc(), equals(initialDue));
      },
    );

    test('Undo post-sync deletes record locally, enqueues delete to sync outbox, and restores plan', () async {
      final areaId = await assetRepo.saveArea(
        name: 'Office',
        kind: AreaKind.indoor,
      );
      final roomId = await assetRepo.saveRoom(areaId: areaId, name: 'Office');
      final assetId = await assetRepo.saveAsset(
        name: 'Desk Lamp',
        roomId: roomId,
      );

      final initialDue = DateTime.utc(2026, 8, 15, 10, 0, 0);
      final planId = await maintenanceRepo.savePlan(
        assetId: assetId,
        title: 'Bulb Check',
        recurrence: const RecurrenceRule(
          interval: 30,
          unit: RecurrenceUnit.days,
        ),
        priority: PriorityLevel.low,
        nextDueDate: initialDue,
      );

      final completion = await maintenanceRepo.completePlanResult(
        planId,
        expectedOccurrenceId: (await maintenanceRepo.getTask(planId))!
            .plan
            .currentOccurrenceId,
        completedAt: initialDue,
      );

      // Simulate that the sync outbox was already processed and purged
      await db.delete(db.syncOutbox).go();

      // Call undo post-sync for the exact completion.
      await maintenanceRepo.undoCompletion(
        planId: planId,
        completionId: completion.operationId!,
        completedOccurrenceId: completion.completedOccurrenceId!,
        expectedCurrentOccurrenceId: completion.nextOccurrenceId!,
        previousDueDate: completion.previousDueDate!,
        expectedCurrentNextDueDate: completion.nextDueDate!,
      );

      // Local maintenance record must be deleted
      final records = await maintenanceRepo.listRecordsForPlan(planId);
      expect(records, isEmpty);

      // Plan nextDueDate must be restored
      final task = await maintenanceRepo.getTask(planId);
      expect(task!.plan.nextDueDate.toUtc(), equals(initialDue));

      // Mutation outbox triggers must have captured the record deletion and plan update
      final outboxMutations = await db.select(db.syncOutbox).get();
      expect(
        outboxMutations.any(
          (r) => r.entity == 'maintenance_record' && r.operation == 'delete',
        ),
        isTrue,
      );
      expect(
        outboxMutations.any(
          (r) => r.entity == 'maintenance_plan' && r.operation == 'upsert',
        ),
        isTrue,
      );
    });
  });

  test(
    'restoring a task refuses to resurrect a trashed parent hierarchy',
    () async {
      final areaId = await assetRepo.saveArea(
        name: 'Restore hierarchy',
        kind: AreaKind.indoor,
      );
      final roomId = await assetRepo.saveRoom(
        areaId: areaId,
        name: 'Restore hierarchy room',
      );
      final assetId = await assetRepo.saveAsset(
        name: 'Restore hierarchy asset',
        roomId: roomId,
      );
      final planId = await maintenanceRepo.savePlan(
        assetId: assetId,
        title: 'Restore hierarchy task',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: DateTime(2026, 9, 1, 9),
      );

      await maintenanceRepo.archivePlan(planId);
      await assetRepo.trashAsset(assetId);
      await expectLater(
        maintenanceRepo.restorePlan(planId),
        throwsA(isA<StateError>()),
      );

      final assetRow = await (db.select(
        db.assets,
      )..where((row) => row.id.equals(assetId))).getSingle();
      final planRow = await (db.select(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).getSingle();
      expect(assetRow.archivedAt, isNotNull);
      expect(planRow.archivedAt, isNotNull);
    },
  );

  group('Account Deletion & Data Isolation', () {
    test('clearAllAccountData purges all tables including reconciliation requests and search index', () async {
      final areaId = await assetRepo.saveArea(
        name: 'Kitchen',
        kind: AreaKind.indoor,
      );
      final roomId = await assetRepo.saveRoom(areaId: areaId, name: 'Kitchen');
      final assetId = await assetRepo.saveAsset(
        name: 'Refrigerator',
        roomId: roomId,
      );

      await maintenanceRepo.savePlan(
        assetId: assetId,
        title: 'Clean Coils',
        recurrence: const RecurrenceRule(
          interval: 6,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.high,
        nextDueDate: DateTime.utc(2026, 9, 1),
      );

      // Saving the plan atomically persisted its schedule-reconciliation
      // request, so account deletion must clear it with the domain rows.
      expect(
        await db.select(db.notificationReconciliationRequests).get(),
        isNotEmpty,
      );

      await searchRepo.rebuildIndex();
      expect(await searchRepo.search('Refrigerator'), isNotEmpty);

      // Clear all account data
      await syncStore.clearAllAccountData();

      // Verify all tables and indexes are empty
      expect(await db.select(db.areas).get(), isEmpty);
      expect(await db.select(db.rooms).get(), isEmpty);
      expect(await db.select(db.assets).get(), isEmpty);
      expect(await db.select(db.maintenancePlans).get(), isEmpty);
      expect(
        await db.select(db.notificationReconciliationRequests).get(),
        isEmpty,
      );
      expect(await searchRepo.search('Refrigerator'), isEmpty);
    });
  });

  group('Trash provenance', () {
    test(
      'restoring parent preserves independently trashed descendants',
      () async {
        final areaId = await assetRepo.saveArea(
          name: 'Provenance',
          kind: AreaKind.indoor,
        );
        final roomId = await assetRepo.saveRoom(areaId: areaId, name: 'Room');
        final assetId = await assetRepo.saveAsset(
          name: 'Independent asset',
          roomId: roomId,
        );
        final planId = await maintenanceRepo.savePlan(
          assetId: assetId,
          title: 'Independent task',
          recurrence: const RecurrenceRule(
            interval: 1,
            unit: RecurrenceUnit.days,
          ),
          priority: PriorityLevel.medium,
          nextDueDate: DateTime(2026, 8, 20, 9),
        );
        await maintenanceRepo.archivePlan(planId);
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await assetRepo.trashAsset(assetId);
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await assetRepo.trashRoom(roomId);
        await assetRepo.restoreRoom(roomId);

        final restoredAsset = await assetRepo.getAsset(assetId);
        expect(restoredAsset!.archivedAt, isNotNull);
        expect(
          (await maintenanceRepo.listArchivedTasks()).map((t) => t.plan.id),
          contains(planId),
        );
      },
    );

    test('restoring a child never resurrects its trashed ancestor', () async {
      final areaId = await assetRepo.saveArea(
        name: 'Ancestor',
        kind: AreaKind.indoor,
      );
      final roomId = await assetRepo.saveRoom(areaId: areaId, name: 'Child');
      await assetRepo.trashArea(areaId);
      await expectLater(assetRepo.restoreRoom(roomId), throwsStateError);
      expect(
        (await assetRepo.listArchivedAreas()).map((a) => a.id),
        contains(areaId),
      );
      expect(
        (await assetRepo.listArchivedRooms()).map((r) => r.id),
        contains(roomId),
      );
    });
  });

  group('Primary photo mutation routing', () {
    test(
      'make primary queues one atomic operation instead of photo upserts',
      () async {
        final areaId = await assetRepo.saveArea(
          name: 'Photos',
          kind: AreaKind.indoor,
        );
        final roomId = await assetRepo.saveRoom(areaId: areaId, name: 'Photos');
        final assetId = await assetRepo.saveAsset(
          name: 'Photo asset',
          roomId: roomId,
        );
        final sourceA = File(p.join(tempDir.path, 'a.jpg'));
        final sourceB = File(p.join(tempDir.path, 'b.jpg'));
        await _writeTestPhoto(sourceA, image.ColorRgb8(100, 30, 10));
        await _writeTestPhoto(sourceB, image.ColorRgb8(10, 80, 140));
        final first = await assetRepo.addPhoto(assetId, sourceA.path);
        final second = await assetRepo.addPhoto(assetId, sourceB.path);
        await db.delete(db.syncOutbox).go();

        await assetRepo.setPrimaryPhoto(assetId, second.id);

        final outbox = await db.select(db.syncOutbox).get();
        expect(outbox.where((row) => row.entity == 'asset_photo'), isEmpty);
        final operation = outbox.singleWhere(
          (row) => row.entity == 'asset_photo_primary',
        );
        final payload =
            jsonDecode(operation.payloadJson!) as Map<String, dynamic>;
        expect(payload['asset_id'], assetId);
        expect(payload['photo_id'], second.id);
        final photos = await assetRepo.listPhotosForAsset(assetId);
        expect(
          photos.singleWhere((photo) => photo.id == first.id).isPrimary,
          isFalse,
        );
        expect(
          photos.singleWhere((photo) => photo.id == second.id).isPrimary,
          isTrue,
        );
      },
    );

    test(
      'deleting the primary photo atomically promotes a successor',
      () async {
        final areaId = await assetRepo.saveArea(
          name: 'Delete photo area',
          kind: AreaKind.indoor,
        );
        final roomId = await assetRepo.saveRoom(
          areaId: areaId,
          name: 'Delete photo room',
        );
        final assetId = await assetRepo.saveAsset(
          name: 'Delete photo asset',
          roomId: roomId,
        );
        final sourceA = File(p.join(tempDir.path, 'delete-a.jpg'));
        final sourceB = File(p.join(tempDir.path, 'delete-b.jpg'));
        await _writeTestPhoto(sourceA, image.ColorRgb8(100, 30, 10));
        await _writeTestPhoto(sourceB, image.ColorRgb8(10, 80, 140));
        final primary = await assetRepo.addPhoto(
          assetId,
          sourceA.path,
          makePrimary: true,
        );
        final successor = await assetRepo.addPhoto(assetId, sourceB.path);
        await db.delete(db.syncOutbox).go();

        await assetRepo.deletePhoto(primary.id);

        final photos = await assetRepo.listPhotosForAsset(assetId);
        expect(photos, hasLength(1));
        expect(photos.single.id, successor.id);
        expect(photos.single.isPrimary, isTrue);
        final outbox = await db.select(db.syncOutbox).get();
        expect(
          outbox.any(
            (row) => row.entity == 'asset_photo' && row.recordKey == primary.id,
          ),
          isTrue,
        );
        expect(
          outbox.any(
            (row) =>
                row.entity == 'asset_photo_primary' && row.recordKey == assetId,
          ),
          isTrue,
        );
      },
    );
  });
}

Future<void> _writeTestPhoto(File file, image.Color color) async {
  final pixels = image.Image(width: 12, height: 12)..clear(color);
  await file.writeAsBytes(image.encodeJpg(pixels));
}
