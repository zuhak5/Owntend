import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';

void main() {
  late AppDatabase db;
  late LocalSyncStore store;
  late DriftAssetRepository assets;
  late Asset original;

  setUp(() async {
    db = AppDatabase(executor: NativeDatabase.memory());
    store = LocalSyncStore(db);
    assets = DriftAssetRepository(db);
    await assets.saveArea(id: 'area', name: 'Home', kind: AreaKind.indoor);
    await assets.saveRoom(id: 'room', name: 'Room', areaId: 'area');
    await assets.saveAsset(
      id: 'item',
      name: 'Original',
      roomId: 'room',
      assetType: AssetType.safety,
    );
    original = (await assets.getAsset('item'))!;
    await store.bindIdentity('account');
    await db.delete(db.syncOutbox).go();
  });
  tearDown(() => db.close());

  Future<AuthoritativeEditorSnapshot> capture() =>
      store.captureAuthoritativeEditor(
        entity: 'asset',
        recordKey: 'item',
        accountId: 'account',
        expectedUpdatedAt: original.updatedAt,
      );

  Future<void> finish(
    AuthoritativeEditorSnapshot snapshot,
    Map<String, dynamic> canonical, {
    bool accountIsCurrent = true,
    bool failAfterSave = false,
  }) => store.finishAuthoritativeEditor(
    snapshot: snapshot,
    canonicalJson: canonical,
    expectedTarget: 'general',
    accountIsCurrent: () => accountIsCurrent,
    saveLocalEdit: (updatedAt) async {
      await assets.saveAsset(
        id: 'item',
        name: 'Edited',
        roomId: 'room',
        expectedUpdatedAt: updatedAt,
      );
      if (failAfterSave) throw StateError('local save failed');
    },
  );

  for (final pullFirst in [false, true]) {
    test(
      'own type mutation saves the form with pullFirst=$pullFirst',
      () async {
        final snapshot = await capture();
        final canonical = _assetRow(original);
        if (pullFirst) {
          await store.applyRemoteRecords([
            SyncRecord.fromRemote(syncSpecByEntity['asset']!, canonical),
          ]);
        }
        await finish(snapshot, canonical);
        expect((await assets.getAsset('item'))!.name, 'Edited');
        expect((await assets.getAsset('item'))!.assetType, AssetType.general);
        expect(await db.select(db.safetyDetailsTable).get(), isEmpty);
        final shadow = await (db.select(db.syncShadows)).getSingle();
        expect(shadow.remoteRevision, 2);
        final mutations = await db.select(db.syncOutbox).get();
        expect(mutations.any((row) => row.entity == 'asset'), isTrue);
        expect(mutations.any((row) => row.entity == 'safety_detail'), isFalse);
      },
    );
  }

  test(
    'already-acknowledged pre-RPC intent does not reject own canonical result',
    () async {
      await db.customStatement(
        "INSERT INTO offline_mutation_queue(entity, record_key, operation) VALUES ('asset','item','upsert')",
      );
      final snapshot = await capture();
      await db.delete(db.syncOutbox).go();
      await finish(snapshot, _assetRow(original));
      expect((await assets.getAsset('item'))!.name, 'Edited');
    },
  );

  test(
    'replacement intent with identical values is not erased (ABA)',
    () async {
      await db.customStatement(
        "INSERT INTO offline_mutation_queue(entity, record_key, operation) VALUES ('asset','item','upsert')",
      );
      final snapshot = await capture();
      await db.delete(db.syncOutbox).go();
      await db.customStatement(
        "INSERT INTO offline_mutation_queue(entity, record_key, operation) VALUES ('asset','item','upsert')",
      );
      await expectLater(
        finish(snapshot, _assetRow(original)),
        throwsStateError,
      );
      expect((await assets.getAsset('item'))!.name, 'Original');
      expect(await db.select(db.syncOutbox).get(), hasLength(1));
    },
  );

  test('new local form edits survive an accepted server response', () async {
    final snapshot = await capture();
    await assets.saveAsset(
      id: 'item',
      name: 'Newer local',
      roomId: 'room',
      assetType: AssetType.safety,
      expectedUpdatedAt: original.updatedAt,
    );
    await expectLater(finish(snapshot, _assetRow(original)), throwsStateError);
    expect((await assets.getAsset('item'))!.name, 'Newer local');
    expect(await db.select(db.syncOutbox).get(), isNotEmpty);
  });

  test('newer pulled state and revision are preserved', () async {
    final snapshot = await capture();
    final canonical = _assetRow(original);
    final newer = {...canonical, 'name': 'Newer remote', 'revision': 3};
    await store.applyRemoteRecords([
      SyncRecord.fromRemote(syncSpecByEntity['asset']!, newer),
    ]);
    await expectLater(finish(snapshot, canonical), throwsStateError);
    expect((await assets.getAsset('item'))!.name, 'Newer remote');
  });

  test(
    'higher shadow revision blocks identical canonical row values',
    () async {
      final snapshot = await capture();
      final canonical = _assetRow(original);
      await store.applyRemoteRecords([
        SyncRecord.fromRemote(syncSpecByEntity['asset']!, {
          ...canonical,
          'revision': 3,
        }),
      ]);
      await expectLater(finish(snapshot, canonical), throwsStateError);
      expect((await db.select(db.syncShadows).getSingle()).remoteRevision, 3);
    },
  );

  test(
    'canonical result containing another edit cannot overwrite the preimage',
    () async {
      final snapshot = await capture();
      await expectLater(
        finish(snapshot, {..._assetRow(original), 'name': 'Other edit'}),
        throwsStateError,
      );
      expect((await assets.getAsset('item'))!.name, 'Original');
    },
  );

  test(
    'account changes and wrong response ownership block local adoption',
    () async {
      final snapshot = await capture();
      await expectLater(
        finish(snapshot, _assetRow(original), accountIsCurrent: false),
        throwsStateError,
      );
      await expectLater(
        finish(snapshot, {..._assetRow(original), 'user_id': 'another'}),
        throwsFormatException,
      );
      expect((await assets.getAsset('item'))!.assetType, AssetType.safety);
      expect(await db.select(db.syncShadows).get(), isEmpty);
    },
  );

  test(
    'local save failure rolls canonical adoption and outbox back atomically',
    () async {
      final snapshot = await capture();
      await expectLater(
        finish(snapshot, _assetRow(original), failAfterSave: true),
        throwsStateError,
      );
      expect((await assets.getAsset('item'))!.name, 'Original');
      expect((await assets.getAsset('item'))!.assetType, AssetType.safety);
      expect(await db.select(db.syncShadows).get(), isEmpty);
      expect(await db.select(db.syncOutbox).get(), isEmpty);
    },
  );

  test('typed canonical details establish revision shadows before local detail edits', () async {
    final snapshot = await capture();
    final canonical = {..._assetRow(original), 'asset_type': 'device'};
    final details = <String, dynamic>{
      'asset_id': 'item',
      'user_id': 'account',
      'brand': 'Server brand',
      'created_at': canonical['updated_at'],
      'updated_at': canonical['updated_at'],
      'revision': 5,
    };
    await store.finishAuthoritativeEditor(
      snapshot: snapshot,
      canonicalJson: canonical,
      expectedTarget: 'device',
      detailRows: [
        {'entity': 'device_detail', 'row': details},
      ],
      accountIsCurrent: () => true,
      saveLocalEdit: (at) async {
        await assets.saveAsset(
          id: 'item',
          name: 'Edited',
          roomId: 'room',
          assetType: AssetType.device,
          deviceDetails: const DeviceDetails(brand: 'Edited brand'),
          expectedUpdatedAt: at,
        );
      },
    );
    expect(
      (await assets.getAsset('item'))!.deviceDetails!.brand,
      'Edited brand',
    );
    final shadows = await db.select(db.syncShadows).get();
    expect(
      shadows
          .singleWhere((row) => row.entity == 'device_detail')
          .remoteRevision,
      5,
    );
    expect(await db.select(db.safetyDetailsTable).get(), isEmpty);
  });

  test('task move reconciles own pull while preserving occurrence CAS and form metadata', () async {
    await assets.saveAsset(
      id: 'destination',
      name: 'Destination',
      roomId: 'room',
    );
    final tasks = DriftMaintenanceRepository(db);
    final due = DateTime.utc(2027, 2, 1);
    await tasks.savePlan(
      id: 'plan',
      assetId: 'item',
      title: 'Original task',
      recurrence: const RecurrenceRule(
        interval: 1,
        unit: RecurrenceUnit.months,
      ),
      priority: PriorityLevel.medium,
      nextDueDate: due,
    );
    final plan = (await tasks.listTasks()).single.plan;
    await db.delete(db.syncOutbox).go();
    final snapshot = await store.captureAuthoritativeEditor(
      entity: 'maintenance_plan',
      recordKey: 'plan',
      accountId: 'account',
      expectedUpdatedAt: plan.updatedAt,
      expectedOccurrenceId: plan.currentOccurrenceId,
    );
    final canonical = <String, dynamic>{
      'id': plan.id,
      'user_id': 'account',
      'asset_id': 'destination',
      'title': plan.title,
      'instructions': plan.instructions,
      'recurrence_interval': 1,
      'recurrence_unit': 'months',
      'priority': 'medium',
      'current_occurrence_id': plan.currentOccurrenceId,
      'next_due_date': due.toIso8601String(),
      'is_enabled': true,
      'reminder_days_before': 0,
      'created_at': plan.createdAt.toUtc().toIso8601String(),
      'updated_at': plan.updatedAt
          .add(const Duration(seconds: 5))
          .toUtc()
          .toIso8601String(),
      'archived_at': null,
      'revision': 2,
    };
    await store.applyRemoteRecords([
      SyncRecord.fromRemote(syncSpecByEntity['maintenance_plan']!, canonical),
    ]);
    await store.finishAuthoritativeEditor(
      snapshot: snapshot,
      canonicalJson: canonical,
      expectedTarget: 'destination',
      accountIsCurrent: () => true,
      saveLocalEdit: (at) async {
        await tasks.savePlan(
          id: 'plan',
          assetId: 'destination',
          title: 'Edited task',
          recurrence: plan.recurrence,
          priority: plan.priority,
          nextDueDate: due,
          expectedUpdatedAt: at,
          expectedOccurrenceId: plan.currentOccurrenceId,
        );
      },
    );
    final saved = (await tasks.listTasks()).single.plan;
    expect(saved.title, 'Edited task');
    expect(saved.assetId, 'destination');
    expect(saved.currentOccurrenceId, plan.currentOccurrenceId);
    expect(
      await db.select(db.notificationReconciliationRequests).get(),
      isNotEmpty,
    );
  });
}

Map<String, dynamic> _assetRow(Asset asset) => {
  'id': asset.id,
  'user_id': 'account',
  'name': asset.name,
  'asset_type': 'general',
  'room_id': asset.roomId,
  'placement': asset.placement,
  'notes': asset.notes,
  'purchase_date': asset.purchaseDate?.toUtc().toIso8601String(),
  'created_at': asset.createdAt.toUtc().toIso8601String(),
  'updated_at': asset.updatedAt
      .add(const Duration(seconds: 5))
      .toUtc()
      .toIso8601String(),
  'archived_at': asset.archivedAt?.toUtc().toIso8601String(),
  'revision': 2,
};
