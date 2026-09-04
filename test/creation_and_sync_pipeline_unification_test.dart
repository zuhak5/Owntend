import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';

void main() {
  group('Phase 1 & Phase 2 Creation & Sync Pipeline Remediation Tests', () {
    late AppDatabase db;
    late LocalSyncStore store;

    setUp(() {
      db = AppDatabase(executor: NativeDatabase.memory());
      store = LocalSyncStore(
        db,
        documentsDirectory: () async => Directory.systemTemp.createTemp(),
        deleteFile: (file) async {},
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('CC-03: offline domain creations are enqueued for upload via enqueueInitialSnapshot on identity binding', () async {
      final now = DateTime.now().toUtc();
      const planId = 'plan-123';

      // Seed area, room, asset, and plan offline
      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(
              id: 'area-offline-1',
              name: 'Garage',
              kind: 'indoor',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              id: 'room-offline-1',
              areaId: 'area-offline-1',
              name: 'Main Bay',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: 'asset-offline-1',
              name: 'Air Compressor',
              assetType: const Value('device'),
              roomId: 'room-offline-1',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await db
          .into(db.maintenancePlans)
          .insert(
            MaintenancePlansCompanion.insert(
              id: planId,
              assetId: 'asset-offline-1',
              title: 'Drain Tank',
              nextDueDate: now,
              recurrenceInterval: 1,
              recurrenceUnit: 'months',
              priority: 'medium',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      // Verify that local domain data is non-pristine
      final pristine = await store.isPristineForCloudBootstrap();
      expect(pristine, isFalse);

      // Bind identity and run initial snapshot enqueue (as done by sync coordinator)
      await store.bindIdentity('user-google-456');
      await store.enqueueInitialSnapshot();

      // Verify outbox contains the offline plan and asset ready for upload
      final outboxRows = await db.select(db.syncOutbox).get();
      expect(
        outboxRows.any(
          (r) => r.entity == 'maintenance_plan' && r.recordKey == planId,
        ),
        isTrue,
      );
      expect(
        outboxRows.any(
          (r) => r.entity == 'asset' && r.recordKey == 'asset-offline-1',
        ),
        isTrue,
      );
    });

    test(
      'CC-02: readAssetDetails bundles device detail row for asset',
      () async {
        final now = DateTime.now().toUtc();
        const assetId = 'asset-device-1';

        // Seed area and room
        await db
            .into(db.areas)
            .insert(
              AreasCompanion.insert(
                id: 'area-1',
                name: 'Kitchen',
                kind: 'indoor',
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        await db
            .into(db.rooms)
            .insert(
              RoomsCompanion.insert(
                id: 'room-1',
                areaId: 'area-1',
                name: 'Kitchen Area',
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );

        // Insert asset
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: assetId,
                name: 'Dishwasher',
                assetType: const Value('device'),
                roomId: 'room-1',
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );

        // Insert device detail
        await db
            .into(db.deviceDetailsTable)
            .insert(
              DeviceDetailsTableCompanion.insert(
                assetId: assetId,
                brand: const Value('Bosch'),
                model: const Value('Series 6'),
                serialNumber: const Value('SN-98765'),
                powerSource: const Value('electric_corded'),
                manualUrl: const Value('https://example.com/manual.pdf'),
                consumable: const Value('Tablets'),
              ),
            );

        // Test reading asset details
        final details = await store.readAssetDetails(assetId);
        expect(details, isNotNull);
        expect(details!['brand'], equals('Bosch'));
        expect(details['model'], equals('Series 6'));
        expect(details['serial_number'], equals('SN-98765'));
        expect(details['power_source'], equals('electric_corded'));
        expect(details['manual_url'], equals('https://example.com/manual.pdf'));
        expect(details['consumable'], equals('Tablets'));
      },
    );

    test(
      'CC-01: readPlanMetadata bundles plan metadata for maintenance task',
      () async {
        final now = DateTime.now().toUtc();
        const planId = 'plan-tv-filter';

        // Seed area, room, asset, and maintenance plan
        await db
            .into(db.areas)
            .insert(
              AreasCompanion.insert(
                id: 'area-plan-1',
                name: 'Living',
                kind: 'indoor',
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        await db
            .into(db.rooms)
            .insert(
              RoomsCompanion.insert(
                id: 'room-plan-1',
                areaId: 'area-plan-1',
                name: 'Living Room',
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: 'asset-plan-1',
                name: 'TV',
                assetType: const Value('device'),
                roomId: 'room-plan-1',
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        await db
            .into(db.maintenancePlans)
            .insert(
              MaintenancePlansCompanion.insert(
                id: planId,
                assetId: 'asset-plan-1',
                title: 'Clean TV Filter',
                nextDueDate: now,
                recurrenceInterval: 1,
                recurrenceUnit: 'months',
                priority: 'medium',
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );

        // Insert metadata row
        await db
            .into(db.maintenancePlanMetadata)
            .insert(
              MaintenancePlanMetadataCompanion.insert(
                planId: planId,
                taskType: const Value('cleaning'),
                locationLabel: const Value('Living Room Shelf'),
                estimatedDurationMinutes: const Value(15),
                requiredMaterialsJson: const Value('["Microfiber cloth"]'),
                reminderRecommendation: const Value(
                  'Do not spray liquid directly',
                ),
                sortOrder: const Value(2),
              ),
            );

        // Test reading plan metadata
        final metadata = await store.readPlanMetadata(planId);
        expect(metadata, isNotNull);
        expect(metadata!['task_type'], equals('cleaning'));
        expect(metadata['location_label'], equals('Living Room Shelf'));
        expect(metadata['estimated_duration_minutes'], equals(15));
        expect(
          metadata['required_materials_json'],
          equals('["Microfiber cloth"]'),
        );
        expect(
          metadata['reminder_recommendation'],
          equals('Do not spray liquid directly'),
        );
        expect(metadata['sort_order'], equals(2));
      },
    );
  });
}
