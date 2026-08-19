import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';

void main() {
  test('task editor drafts and RPC payload omit Health Group', () {
    final editor = File(
      'lib/src/features/maintenance/presentation/maintenance_dialogs.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/src/features/maintenance/application/task_creation_controller.dart',
    ).readAsStringSync();

    expect(editor, isNot(contains('HealthGroup')));
    expect(editor, isNot(contains('_healthGroup')));
    expect(editor, isNot(contains('health_group')));
    expect(editor, isNot(contains('l10n.healthGroup')));
    expect(controller, isNot(contains('health_group')));
  });

  test('task presentation and statistics derive linked Item Type', () {
    final taskDetail = File(
      'lib/src/features/maintenance/presentation/task_detail_screen.dart',
    ).readAsStringSync();
    final sharedWidgets = File('lib/src/ui/shared_widgets.dart')
        .readAsStringSync();
    final components = File('lib/src/ui/components.dart').readAsStringSync();
    final statistics = File('lib/src/core/data/statistics_repository.dart')
        .readAsStringSync();
    final assetRepository = File('lib/src/core/data/asset_repository.dart')
        .readAsStringSync();

    expect(taskDetail, contains('_iconForAssetType(task.asset.assetType)'));
    expect(sharedWidgets, contains('_iconForAssetType(task.asset.assetType)'));
    expect(components, contains('iconForAssetType(task.asset.assetType)'));
    expect(statistics, contains('task.asset.assetType'));
    expect(assetRepository, contains('domain.AssetType.plant.name'));
    expect(assetRepository, contains('_isClearPlantWateringPlan'));
  });

  test('maintenance sync spec omits health_group', () {
    final spec = syncEntitySpecs.firstWhere(
      (value) => value.entity == 'maintenance_plan',
    );
    expect(spec.localColumns, isNot(contains('health_group')));
  });

  group('Task Creation Composite Acknowledgment Tests (P1-A)', () {
    late AppDatabase db;
    late LocalSyncStore store;

    setUp(() async {
      db = AppDatabase(executor: NativeDatabase.memory());
      store = LocalSyncStore(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('acknowledgeTaskCreationComposite applies canonical rows and clears outbox mutations atomically', () async {
      final now = DateTime.now().toUtc();
      const planId = 'task-uuid-101';
      const assetId = 'asset-uuid-202';

      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(
              id: 'area-1',
              name: 'Main Area',
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
              name: 'Garage',
              roomType: const Value('storage'),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      // Insert an asset row so foreign key / target asset validations pass if needed
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: assetId,
              name: 'Test Appliance',
              assetType: const Value('device'),
              roomId: 'room-1',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      // Clear auto-generated trigger outbox rows so we test exact composite acknowledgment behavior
      await (db.delete(db.syncOutbox)).go();

      // Seed pending outbox mutations simulating local creation
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              entity: 'maintenance_plan',
              recordKey: planId,
              operation: 'upsert',
              changedAt: Value(now),
              attempts: const Value(0),
            ),
          );
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              entity: 'maintenance_plan_metadata',
              recordKey: planId,
              operation: 'upsert',
              changedAt: Value(now),
              attempts: const Value(0),
            ),
          );
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              entity: 'area',
              recordKey: 'unrelated-area',
              operation: 'upsert',
              changedAt: Value(now),
              attempts: const Value(0),
            ),
          );

      expect(await store.pendingCount(), 3);

      final canonicalPlan = <String, dynamic>{
        'id': planId,
        'user_id': 'user-1',
        'asset_id': assetId,
        'title': 'Server Authoritative Task Title',
        'description': 'Server instructions',
        'interval_count': 30,
        'interval_unit': 'days',
        'priority': 'medium',
        'next_due_date': now.toIso8601String(),
        'reminder_days_before': 1,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'revision': 1,
        'is_enabled': true,
      };

      final canonicalMetadata = <String, dynamic>{
        'plan_id': planId,
        'user_id': 'user-1',
        'task_type': 'inspection',
        'required_materials_json': '[]',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'revision': 1,
      };

      await store.acknowledgeTaskCreationComposite(
        planId: planId,
        planJson: canonicalPlan,
        metadataJson: canonicalMetadata,
      );

      // Verify covered outbox entries for task plan and metadata are removed
      final remainingMutations = await store.pendingMutations();
      expect(remainingMutations.length, 1);
      expect(remainingMutations.single.entity, 'area');
      expect(remainingMutations.single.recordKey, 'unrelated-area');

      // Verify canonical plan is persisted locally
      final planRow = await (db.select(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).getSingleOrNull();
      expect(planRow, isNotNull);
      expect(planRow!.title, 'Server Authoritative Task Title');
    });
  });
}
