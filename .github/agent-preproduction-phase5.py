from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text and old not in text:
        return
    if old not in text:
        raise SystemExit(f"expected snippet not found in {path}: {old[:180]!r}")
    file.write_text(text.replace(old, new, 1))


asset = Path('lib/src/core/data/asset_repository.dart')
text = asset.read_text()

old = '''  @override
  Future<void> trashArea(String id) async {
    final now = DateTime.now();
    final roomRows = await (db.select(
      db.rooms,
    )..where((room) => room.areaId.equals(id))).get();
    final roomIds = roomRows.map((row) => row.id).toList();
    final assetRows = roomIds.isEmpty
        ? <AssetRow>[]
        : await (db.select(
            db.assets,
          )..where((asset) => asset.roomId.isIn(roomIds))).get();
    final assetIds = assetRows.map((row) => row.id).toList();
    await db.transaction(() async {
      await (db.update(db.areas)..where((area) => area.id.equals(id))).write(
        AreasCompanion(archivedAt: Value(now), updatedAt: Value(now)),
      );
      if (roomIds.isNotEmpty) {
        await (db.update(
          db.rooms,
        )..where((room) => room.id.isIn(roomIds))).write(
          RoomsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
      }
      if (assetIds.isNotEmpty) {
        await (db.update(
          db.assets,
        )..where((asset) => asset.id.isIn(assetIds))).write(
          AssetsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
        await (db.update(
          db.maintenancePlans,
        )..where((plan) => plan.assetId.isIn(assetIds))).write(
          MaintenancePlansCompanion(
            archivedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }
'''
new = '''  @override
  Future<void> trashArea(String id) async {
    final now = DateTime.now();
    await db.transaction(() async {
      final area = await (db.select(
        db.areas,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (area == null || area.archivedAt != null) return;
      final activeRooms = await (db.select(db.rooms)..where(
            (room) => room.areaId.equals(id) & room.archivedAt.isNull(),
          )).get();
      final roomIds = activeRooms.map((row) => row.id).toList();
      final activeAssets = roomIds.isEmpty
          ? <AssetRow>[]
          : await (db.select(db.assets)..where(
                (row) => row.roomId.isIn(roomIds) & row.archivedAt.isNull(),
              )).get();
      final assetIds = activeAssets.map((row) => row.id).toList();
      await (db.update(db.areas)..where((row) => row.id.equals(id))).write(
        AreasCompanion(archivedAt: Value(now), updatedAt: Value(now)),
      );
      if (roomIds.isNotEmpty) {
        await (db.update(db.rooms)..where((row) => row.id.isIn(roomIds))).write(
          RoomsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
      }
      if (assetIds.isNotEmpty) {
        await (db.update(db.assets)..where((row) => row.id.isIn(assetIds))).write(
          AssetsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
        await (db.update(db.maintenancePlans)..where(
              (plan) => plan.assetId.isIn(assetIds) & plan.archivedAt.isNull(),
            )).write(
          MaintenancePlansCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
      }
    });
  }
'''
if old not in text: raise SystemExit('trashArea not found')
text = text.replace(old,new,1)

old = '''  @override
  Future<void> restoreArea(String id) async {
    final now = DateTime.now();
    final roomRows = await (db.select(
      db.rooms,
    )..where((room) => room.areaId.equals(id))).get();
    final roomIds = roomRows.map((row) => row.id).toList();
    final assetRows = roomIds.isEmpty
        ? <AssetRow>[]
        : await (db.select(
            db.assets,
          )..where((asset) => asset.roomId.isIn(roomIds))).get();
    final assetIds = assetRows.map((row) => row.id).toList();
    await db.transaction(() async {
      await (db.update(db.areas)..where((area) => area.id.equals(id))).write(
        AreasCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
      );
      if (roomIds.isNotEmpty) {
        await (db.update(
          db.rooms,
        )..where((room) => room.id.isIn(roomIds))).write(
          RoomsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
      }
      if (assetIds.isNotEmpty) {
        await (db.update(
          db.assets,
        )..where((asset) => asset.id.isIn(assetIds))).write(
          AssetsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
        await (db.update(
          db.maintenancePlans,
        )..where((plan) => plan.assetId.isIn(assetIds))).write(
          MaintenancePlansCompanion(
            archivedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }
'''
new = '''  @override
  Future<void> restoreArea(String id) async {
    final now = DateTime.now();
    await db.transaction(() async {
      final area = await (db.select(
        db.areas,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      final cascadeAt = area?.archivedAt;
      if (area == null || cascadeAt == null) return;
      final cascadeRooms = await (db.select(db.rooms)..where(
            (room) => room.areaId.equals(id) & room.archivedAt.equals(cascadeAt),
          )).get();
      final roomIds = cascadeRooms.map((row) => row.id).toList();
      final cascadeAssets = roomIds.isEmpty
          ? <AssetRow>[]
          : await (db.select(db.assets)..where(
                (row) => row.roomId.isIn(roomIds) & row.archivedAt.equals(cascadeAt),
              )).get();
      final assetIds = cascadeAssets.map((row) => row.id).toList();
      await (db.update(db.areas)..where((row) => row.id.equals(id))).write(
        AreasCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
      );
      if (roomIds.isNotEmpty) {
        await (db.update(db.rooms)..where((row) => row.id.isIn(roomIds))).write(
          RoomsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
      }
      if (assetIds.isNotEmpty) {
        await (db.update(db.assets)..where((row) => row.id.isIn(assetIds))).write(
          AssetsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
        await (db.update(db.maintenancePlans)..where(
              (plan) => plan.assetId.isIn(assetIds) & plan.archivedAt.equals(cascadeAt),
            )).write(
          MaintenancePlansCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
      }
    });
  }
'''
if old not in text: raise SystemExit('restoreArea not found')
text = text.replace(old,new,1)

old = '''  @override
  Future<void> trashRoom(String id) async {
    final now = DateTime.now();
    final assetRows = await (db.select(
      db.assets,
    )..where((asset) => asset.roomId.equals(id))).get();
    final assetIds = assetRows.map((row) => row.id).toList();
    await db.transaction(() async {
      await (db.update(db.rooms)..where((room) => room.id.equals(id))).write(
        RoomsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
      );
      if (assetIds.isNotEmpty) {
        await (db.update(
          db.assets,
        )..where((asset) => asset.id.isIn(assetIds))).write(
          AssetsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
        await (db.update(
          db.maintenancePlans,
        )..where((plan) => plan.assetId.isIn(assetIds))).write(
          MaintenancePlansCompanion(
            archivedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }
'''
new = '''  @override
  Future<void> trashRoom(String id) async {
    final now = DateTime.now();
    await db.transaction(() async {
      final room = await (db.select(
        db.rooms,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (room == null || room.archivedAt != null) return;
      final activeAssets = await (db.select(db.assets)..where(
            (row) => row.roomId.equals(id) & row.archivedAt.isNull(),
          )).get();
      final assetIds = activeAssets.map((row) => row.id).toList();
      await (db.update(db.rooms)..where((row) => row.id.equals(id))).write(
        RoomsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
      );
      if (assetIds.isNotEmpty) {
        await (db.update(db.assets)..where((row) => row.id.isIn(assetIds))).write(
          AssetsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
        await (db.update(db.maintenancePlans)..where(
              (plan) => plan.assetId.isIn(assetIds) & plan.archivedAt.isNull(),
            )).write(
          MaintenancePlansCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
      }
    });
  }
'''
if old not in text: raise SystemExit('trashRoom not found')
text = text.replace(old,new,1)

old = '''  @override
  Future<void> restoreRoom(String id) async {
    final now = DateTime.now();
    final room = await (db.select(
      db.rooms,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (room == null) return;
    final assetRows = await (db.select(
      db.assets,
    )..where((asset) => asset.roomId.equals(id))).get();
    final assetIds = assetRows.map((row) => row.id).toList();
    await db.transaction(() async {
      await (db.update(
        db.areas,
      )..where((area) => area.id.equals(room.areaId))).write(
        AreasCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
      );
      await (db.update(db.rooms)..where((row) => row.id.equals(id))).write(
        RoomsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
      );
      if (assetIds.isNotEmpty) {
        await (db.update(
          db.assets,
        )..where((asset) => asset.id.isIn(assetIds))).write(
          AssetsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
        await (db.update(
          db.maintenancePlans,
        )..where((plan) => plan.assetId.isIn(assetIds))).write(
          MaintenancePlansCompanion(
            archivedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }
'''
new = '''  @override
  Future<void> restoreRoom(String id) async {
    final now = DateTime.now();
    await db.transaction(() async {
      final room = await (db.select(
        db.rooms,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      final cascadeAt = room?.archivedAt;
      if (room == null || cascadeAt == null) return;
      final area = await (db.select(
        db.areas,
      )..where((row) => row.id.equals(room.areaId))).getSingleOrNull();
      if (area == null || area.archivedAt != null) {
        throw StateError('Restore the parent area before restoring this room.');
      }
      final cascadeAssets = await (db.select(db.assets)..where(
            (row) => row.roomId.equals(id) & row.archivedAt.equals(cascadeAt),
          )).get();
      final assetIds = cascadeAssets.map((row) => row.id).toList();
      await (db.update(db.rooms)..where((row) => row.id.equals(id))).write(
        RoomsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
      );
      if (assetIds.isNotEmpty) {
        await (db.update(db.assets)..where((row) => row.id.isIn(assetIds))).write(
          AssetsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
        await (db.update(db.maintenancePlans)..where(
              (plan) => plan.assetId.isIn(assetIds) & plan.archivedAt.equals(cascadeAt),
            )).write(
          MaintenancePlansCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
      }
    });
  }
'''
if old not in text: raise SystemExit('restoreRoom not found')
text = text.replace(old,new,1)

old = '''  @override
  Future<void> trashAsset(String id) async {
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.assets)..where((asset) => asset.id.equals(id))).write(
        AssetsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
      );
      await (db.update(
        db.maintenancePlans,
      )..where((plan) => plan.assetId.equals(id))).write(
        MaintenancePlansCompanion(
          archivedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });
  }
'''
new = '''  @override
  Future<void> trashAsset(String id) async {
    final now = DateTime.now();
    await db.transaction(() async {
      final asset = await (db.select(
        db.assets,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (asset == null || asset.archivedAt != null) return;
      await (db.update(db.assets)..where((row) => row.id.equals(id))).write(
        AssetsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
      );
      await (db.update(db.maintenancePlans)..where(
            (plan) => plan.assetId.equals(id) & plan.archivedAt.isNull(),
          )).write(
        MaintenancePlansCompanion(archivedAt: Value(now), updatedAt: Value(now)),
      );
    });
  }
'''
if old not in text: raise SystemExit('trashAsset not found')
text = text.replace(old,new,1)

old = '''  @override
  Future<void> restoreAsset(String id) async {
    final now = DateTime.now();
    final asset = await (db.select(
      db.assets,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (asset == null) return;
    final room = await (db.select(
      db.rooms,
    )..where((row) => row.id.equals(asset.roomId))).getSingleOrNull();
    await db.transaction(() async {
      if (room != null) {
        await (db.update(
          db.areas,
        )..where((area) => area.id.equals(room.areaId))).write(
          AreasCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
        await (db.update(
          db.rooms,
        )..where((row) => row.id.equals(asset.roomId))).write(
          RoomsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
      }
      await (db.update(db.assets)..where((row) => row.id.equals(id))).write(
        AssetsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
      );
      await (db.update(
        db.maintenancePlans,
      )..where((plan) => plan.assetId.equals(id))).write(
        MaintenancePlansCompanion(
          archivedAt: const Value(null),
          updatedAt: Value(now),
        ),
      );
    });
  }
'''
new = '''  @override
  Future<void> restoreAsset(String id) async {
    final now = DateTime.now();
    await db.transaction(() async {
      final asset = await (db.select(
        db.assets,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      final cascadeAt = asset?.archivedAt;
      if (asset == null || cascadeAt == null) return;
      final room = await (db.select(
        db.rooms,
      )..where((row) => row.id.equals(asset.roomId))).getSingleOrNull();
      final area = room == null
          ? null
          : await (db.select(
              db.areas,
            )..where((row) => row.id.equals(room.areaId))).getSingleOrNull();
      if (room == null || room.archivedAt != null || area == null || area.archivedAt != null) {
        throw StateError('Restore the parent room and area before restoring this item.');
      }
      await (db.update(db.assets)..where((row) => row.id.equals(id))).write(
        AssetsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
      );
      await (db.update(db.maintenancePlans)..where(
            (plan) => plan.assetId.equals(id) & plan.archivedAt.equals(cascadeAt),
          )).write(
        MaintenancePlansCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
      );
    });
  }
'''
if old not in text: raise SystemExit('restoreAsset not found')
text = text.replace(old,new,1)

start = text.index('  @override\n  Future<void> emptyTrash() async {')
end = text.index('\n  @override\n  Future<domain.AssetPhoto> addPhoto(', start)
old = text[start:end]
new = '''  @override
  Future<void> emptyTrash() async {
    final photoRows = await db.transaction(() async {
      // Select the deletion set only after the transaction has begun. A restore
      // that commits before this point is spared; a concurrent restore cannot
      // race a stale pre-transaction snapshot into hard deletion.
      final trashedAreas = await (db.select(
        db.areas,
      )..where((row) => row.archivedAt.isNotNull())).get();
      final trashedRooms = await (db.select(
        db.rooms,
      )..where((row) => row.archivedAt.isNotNull())).get();
      final trashedAssets = await (db.select(
        db.assets,
      )..where((row) => row.archivedAt.isNotNull())).get();
      final trashedPlans = await (db.select(
        db.maintenancePlans,
      )..where((row) => row.archivedAt.isNotNull())).get();
      final areaIds = trashedAreas.map((row) => row.id).toList();
      final roomIds = trashedRooms.map((row) => row.id).toList();
      final assetIds = trashedAssets.map((row) => row.id).toList();
      final planIds = trashedPlans.map((row) => row.id).toList();
      final photos = await _photoRowsForAssets(assetIds);
      if (planIds.isNotEmpty) await _deletePlansCascade(db, planIds);
      if (assetIds.isNotEmpty) await _deleteAssetsCascadeInTransaction(assetIds);
      if (roomIds.isNotEmpty) {
        await (db.delete(db.rooms)..where((row) => row.id.isIn(roomIds))).go();
      }
      if (areaIds.isNotEmpty) {
        await (db.delete(db.areas)..where((row) => row.id.isIn(areaIds))).go();
      }
      return photos;
    });
    await _deletePhotoFiles(photoRows);
  }
'''
text = text[:start] + new + text[end:]
asset.write_text(text)

# Update recurrence and Undo tests that encoded the superseded scheduled-anchor API.
test = Path('test/trash_lifecycle_and_invariants_test.dart')
t = test.read_text()
t = t.replace("test('Early completion advances nextDueDate past previousDueDate'", "test('Early completion resets nextDueDate from actual completion time'")
t = t.replace("""      // nextDueDate must be strictly after the scheduledDueDate being completed
      expect(
        updatedTask!.plan.nextDueDate.isAfter(scheduledDueDate),
        isTrue,
        reason:
            'nextDueDate must strictly advance past the completed occurrence',
      );
      expect(
        updatedTask.plan.nextDueDate.toUtc(),
        equals(DateTime.utc(2026, 9, 6, 12, 0, 0)),
      );
""", """      expect(
        updatedTask!.plan.nextDueDate.toUtc(),
        equals(DateTime.utc(2026, 8, 27, 10, 0, 0)),
      );
""")
# Convert both old Undo tests to exact completion IDs.
t = t.replace("""        await maintenanceRepo.completePlan(planId, completedAt: initialDue);

        // Verify outbox has the completion mutation
""", """        final completion = await maintenanceRepo.completePlanResult(
          planId,
          completedAt: initialDue,
          expectedNextDueDate: initialDue,
        );

        // Verify outbox has the completion mutation
""")
t = t.replace("""        // Call undo
        await maintenanceRepo.undoLastCompletion(planId, initialDue);
""", """        // Call undo for the exact completion that produced the action.
        await maintenanceRepo.undoCompletion(
          planId: planId,
          completionId: completion.operationId!,
          previousDueDate: completion.previousDueDate!,
          expectedCurrentNextDueDate: completion.nextDueDate!,
        );
""",1)
t = t.replace("""      await maintenanceRepo.completePlan(planId, completedAt: initialDue);

      // Simulate that the sync outbox was already processed and purged
""", """      final completion = await maintenanceRepo.completePlanResult(
        planId,
        completedAt: initialDue,
        expectedNextDueDate: initialDue,
      );

      // Simulate that the sync outbox was already processed and purged
""")
t = t.replace("""      // Call undo post-sync
      await maintenanceRepo.undoLastCompletion(planId, initialDue);
""", """      // Call undo post-sync for the exact completion.
      await maintenanceRepo.undoCompletion(
        planId: planId,
        completionId: completion.operationId!,
        previousDueDate: completion.previousDueDate!,
        expectedCurrentNextDueDate: completion.nextDueDate!,
      );
""",1)
# New provenance tests.
addition = r'''

  group('Trash provenance', () {
    test('restoring parent preserves independently trashed descendants', () async {
      final areaId = await assetRepo.saveArea(name: 'Provenance', kind: AreaKind.indoor);
      final roomId = await assetRepo.saveRoom(areaId: areaId, name: 'Room');
      final categoryId = (await assetRepo.listCategories()).first.id;
      final assetId = await assetRepo.saveAsset(
        name: 'Independent asset',
        categoryId: categoryId,
        roomId: roomId,
      );
      final planId = await maintenanceRepo.savePlan(
        assetId: assetId,
        title: 'Independent task',
        recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days),
        priority: PriorityLevel.medium,
        nextDueDate: DateTime(2026, 8, 20, 9),
        healthGroup: HealthGroup.other,
      );
      await maintenanceRepo.archivePlan(planId);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await assetRepo.trashAsset(assetId);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await assetRepo.trashRoom(roomId);
      await assetRepo.restoreRoom(roomId);

      final restoredAsset = await assetRepo.getAsset(assetId);
      expect(restoredAsset!.archivedAt, isNotNull);
      expect((await maintenanceRepo.listArchivedTasks()).map((t) => t.plan.id), contains(planId));
    });

    test('restoring a child never resurrects its trashed ancestor', () async {
      final areaId = await assetRepo.saveArea(name: 'Ancestor', kind: AreaKind.indoor);
      final roomId = await assetRepo.saveRoom(areaId: areaId, name: 'Child');
      await assetRepo.trashArea(areaId);
      await expectLater(assetRepo.restoreRoom(roomId), throwsStateError);
      expect((await assetRepo.listArchivedAreas()).map((a) => a.id), contains(areaId));
      expect((await assetRepo.listArchivedRooms()).map((r) => r.id), contains(roomId));
    });
  });
'''
if "group('Trash provenance'" not in t:
    idx = t.rfind('\n}')
    if idx < 0: raise SystemExit('test close not found')
    t = t[:idx] + addition + t[idx:]
test.write_text(t)
