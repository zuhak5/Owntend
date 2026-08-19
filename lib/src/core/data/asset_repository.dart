part of 'repositories.dart';

Future<void> _deletePlansCascade(AppDatabase db, List<String> planIds) async {
  if (planIds.isEmpty) {
    return;
  }
  await (db.delete(
    db.inboxNotifications,
  )..where((row) => row.planId.isIn(planIds))).go();
  await (db.delete(
    db.appNotifications,
  )..where((row) => row.planId.isIn(planIds))).go();
  await (db.delete(
    db.maintenanceRecords,
  )..where((row) => row.planId.isIn(planIds))).go();
  await (db.delete(
    db.maintenancePlanMetadata,
  )..where((row) => row.planId.isIn(planIds))).go();
  await (db.delete(
    db.notificationReconciliationRequests,
  )..where((row) => row.planId.isIn(planIds))).go();
  await (db.delete(
    db.maintenancePlans,
  )..where((row) => row.id.isIn(planIds))).go();
}

Future<void> _syncPlantWateringPlansForInterval({
  required AppDatabase db,
  required String assetId,
  required int? previousIntervalDays,
  required int? nextIntervalDays,
  required DateTime updatedAt,
}) async {
  if (nextIntervalDays == null ||
      nextIntervalDays < 1 ||
      previousIntervalDays == nextIntervalDays) {
    return;
  }
  final asset = await (db.select(
    db.assets,
  )..where((row) => row.id.equals(assetId))).getSingleOrNull();
  if (asset == null || asset.assetType != domain.AssetType.plant.name) {
    return;
  }
  final plans =
      await (db.select(db.maintenancePlans)..where(
            (plan) =>
                plan.assetId.equals(assetId) &
                plan.archivedAt.isNull() &
                plan.recurrenceUnit.equals(domain.RecurrenceUnit.days.name),
          ))
          .get();
  if (plans.isEmpty) return;

  final planIds = plans.map((plan) => plan.id).toList();
  final metadataRows = await (db.select(
    db.maintenancePlanMetadata,
  )..where((row) => row.planId.isIn(planIds))).get();
  final metadataByPlanId = {for (final row in metadataRows) row.planId: row};

  for (final plan in plans) {
    if (plan.recurrenceInterval == nextIntervalDays) continue;
    final metadata = metadataByPlanId[plan.id];
    if (!_isClearPlantWateringPlan(plan, metadata)) continue;
    final latestCompletion =
        await (db.select(db.maintenanceRecords)
              ..where((record) => record.planId.equals(plan.id))
              ..orderBy([(record) => OrderingTerm.desc(record.completedAt)])
              ..limit(1))
            .getSingleOrNull();
    final nextDueDate = latestCompletion == null
        ? const Value<DateTime>.absent()
        : Value<DateTime>(
            _nextDailyDueDate(latestCompletion.completedAt, nextIntervalDays),
          );
    await (db.update(
      db.maintenancePlans,
    )..where((row) => row.id.equals(plan.id))).write(
      MaintenancePlansCompanion(
        recurrenceInterval: Value(nextIntervalDays),
        recurrenceUnit: Value(domain.RecurrenceUnit.days.name),
        nextDueDate: nextDueDate,
        updatedAt: Value(updatedAt),
      ),
    );
  }
}

bool _isClearPlantWateringPlan(
  MaintenancePlanRow plan,
  MaintenancePlanMetadataRow? metadata,
) {
  final primaryText = _normalizedConsistencyText([
    plan.title,
    metadata?.taskType,
  ]);
  if (!_wateringIntentPattern.hasMatch(primaryText)) return false;
  if (_nonWateringPlantIntentPattern.hasMatch(primaryText)) return false;
  return true;
}

DateTime _nextDailyDueDate(DateTime completionDate, int intervalDays) {
  return DateTime(
    completionDate.year,
    completionDate.month,
    completionDate.day + intervalDays,
    completionDate.hour,
    completionDate.minute,
    completionDate.second,
    completionDate.millisecond,
    completionDate.microsecond,
  );
}

String _normalizedConsistencyText(Iterable<Object?> values) {
  return values
      .whereType<Object>()
      .map((value) => value.toString().toLowerCase())
      .join(' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

final RegExp _wateringIntentPattern = RegExp(
  r'\b(water|watering|moisture|irrigat|hydrate|hydro|watercheck|waterchange)\b',
);

final RegExp _nonWateringPlantIntentPattern = RegExp(
  r'\b(fertiliz|feed|prun|trim|repot|sunlight|light|pest|leaf|leaves|temperature|aquarium|fish|gravel)\b',
);

class DriftAssetRepository implements AssetRepository {
  DriftAssetRepository(this.db);

  final AppDatabase db;

  Future<DateTime> _nextTrashCascadeTimestamp() async {
    final usedSeconds = <int>{};
    void remember(DateTime? value) {
      if (value != null) {
        usedSeconds.add(value.millisecondsSinceEpoch ~/ 1000);
      }
    }

    for (final row in await (db.select(
      db.areas,
    )..where((row) => row.archivedAt.isNotNull())).get()) {
      remember(row.archivedAt);
    }
    for (final row in await (db.select(
      db.rooms,
    )..where((row) => row.archivedAt.isNotNull())).get()) {
      remember(row.archivedAt);
    }
    for (final row in await (db.select(
      db.assets,
    )..where((row) => row.archivedAt.isNotNull())).get()) {
      remember(row.archivedAt);
    }
    for (final row in await (db.select(
      db.maintenancePlans,
    )..where((row) => row.archivedAt.isNotNull())).get()) {
      remember(row.archivedAt);
    }

    var candidateSecond = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    while (usedSeconds.contains(candidateSecond)) {
      candidateSecond += 1;
    }
    return DateTime.fromMillisecondsSinceEpoch(candidateSecond * 1000);
  }

  @override
  Stream<List<domain.Area>> watchAreas() {
    final query = db.select(db.areas)
      ..where((area) => area.archivedAt.isNull())
      ..orderBy([
        (area) => OrderingTerm.asc(area.sortOrder),
        (area) => OrderingTerm.asc(area.name),
      ]);
    return query
        .watch()
        .map((rows) => rows.map(_areaFromRow).toList())
        .distinctByFingerprint(areaListFingerprint);
  }

  @override
  Future<List<domain.Area>> listAreas() async {
    final rows =
        await (db.select(db.areas)
              ..where((area) => area.archivedAt.isNull())
              ..orderBy([
                (area) => OrderingTerm.asc(area.sortOrder),
                (area) => OrderingTerm.asc(area.name),
              ]))
            .get();
    return rows.map(_areaFromRow).toList();
  }

  @override
  Future<String> saveArea({
    String? id,
    required String name,
    required domain.AreaKind kind,
    int? sortOrder,
  }) async {
    final areaId = id ?? _uuid.v7();
    final now = DateTime.now();
    final existing = id == null
        ? null
        : await (db.select(
            db.areas,
          )..where((area) => area.id.equals(areaId))).getSingleOrNull();
    final resolvedSortOrder =
        sortOrder ?? existing?.sortOrder ?? await _nextAreaSortOrder();
    if (existing == null) {
      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(
              id: areaId,
              name: name.trim(),
              kind: kind.name,
              sortOrder: Value(resolvedSortOrder),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    } else {
      await (db.update(
        db.areas,
      )..where((area) => area.id.equals(areaId))).write(
        AreasCompanion(
          name: Value(name.trim()),
          kind: Value(kind.name),
          sortOrder: Value(resolvedSortOrder),
          updatedAt: Value(now),
        ),
      );
    }
    return areaId;
  }

  @override
  Future<void> archiveArea(String id) async {
    final roomCount =
        await (db.select(db.rooms)..where(
              (room) => room.areaId.equals(id) & room.archivedAt.isNull(),
            ))
            .get();
    if (roomCount.isNotEmpty) {
      throw StateError('Move or archive rooms before archiving this area.');
    }
    await (db.update(db.areas)..where((area) => area.id.equals(id))).write(
      AreasCompanion(archivedAt: Value(DateTime.now())),
    );
  }

  @override
  Future<void> deleteArea(String id) async {
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
    final photoRows = await _photoRowsForAssets(assetIds);
    await db.transaction(() async {
      await _deleteAssetsCascadeInTransaction(assetIds);
      if (roomIds.isNotEmpty) {
        await (db.delete(
          db.rooms,
        )..where((room) => room.id.isIn(roomIds))).go();
      }
      await (db.delete(db.areas)..where((area) => area.id.equals(id))).go();
    });
    await _deletePhotoFiles(photoRows);
  }

  @override
  Stream<List<domain.Area>> watchArchivedAreas() {
    final query = db.select(db.areas)
      ..where((area) => area.archivedAt.isNotNull())
      ..orderBy([
        (area) => OrderingTerm.desc(area.archivedAt),
        (area) => OrderingTerm.asc(area.name),
      ]);
    return query
        .watch()
        .map((rows) => rows.map(_areaFromRow).toList())
        .distinctByFingerprint(areaListFingerprint);
  }

  @override
  Future<List<domain.Area>> listArchivedAreas() async {
    final rows =
        await (db.select(db.areas)
              ..where((area) => area.archivedAt.isNotNull())
              ..orderBy([
                (area) => OrderingTerm.desc(area.archivedAt),
                (area) => OrderingTerm.asc(area.name),
              ]))
            .get();
    return rows.map(_areaFromRow).toList();
  }

  @override
  Future<void> trashArea(String id) async {
    await db.transaction(() async {
      final now = await _nextTrashCascadeTimestamp();
      final area = await (db.select(
        db.areas,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (area == null || area.archivedAt != null) return;
      final activeRooms =
          await (db.select(db.rooms)..where(
                (room) => room.areaId.equals(id) & room.archivedAt.isNull(),
              ))
              .get();
      final roomIds = activeRooms.map((row) => row.id).toList();
      final activeAssets = roomIds.isEmpty
          ? <AssetRow>[]
          : await (db.select(db.assets)..where(
                  (row) => row.roomId.isIn(roomIds) & row.archivedAt.isNull(),
                ))
                .get();
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
        await (db.update(
          db.assets,
        )..where((row) => row.id.isIn(assetIds))).write(
          AssetsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
        await (db.update(db.maintenancePlans)..where(
              (plan) => plan.assetId.isIn(assetIds) & plan.archivedAt.isNull(),
            ))
            .write(
              MaintenancePlansCompanion(
                archivedAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      }
    });
  }

  @override
  Future<void> restoreArea(String id) async {
    final now = DateTime.now();
    await db.transaction(() async {
      final area = await (db.select(
        db.areas,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      final cascadeAt = area?.archivedAt;
      if (area == null || cascadeAt == null) return;
      final cascadeRooms =
          await (db.select(db.rooms)..where(
                (room) =>
                    room.areaId.equals(id) & room.archivedAt.equals(cascadeAt),
              ))
              .get();
      final roomIds = cascadeRooms.map((row) => row.id).toList();
      final cascadeAssets = roomIds.isEmpty
          ? <AssetRow>[]
          : await (db.select(db.assets)..where(
                  (row) =>
                      row.roomId.isIn(roomIds) &
                      row.archivedAt.equals(cascadeAt),
                ))
                .get();
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
        await (db.update(
          db.assets,
        )..where((row) => row.id.isIn(assetIds))).write(
          AssetsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
        await (db.update(db.maintenancePlans)..where(
              (plan) =>
                  plan.assetId.isIn(assetIds) &
                  plan.archivedAt.equals(cascadeAt),
            ))
            .write(
              MaintenancePlansCompanion(
                archivedAt: const Value(null),
                updatedAt: Value(now),
              ),
            );
      }
    });
  }

  @override
  Stream<List<domain.Room>> watchRooms({String? areaId}) {
    final query = db.select(db.rooms)
      ..where(
        (room) =>
            room.archivedAt.isNull() &
            (areaId == null
                ? const Constant(true)
                : room.areaId.equals(areaId)),
      )
      ..orderBy([
        (room) => OrderingTerm.asc(room.sortOrder),
        (room) => OrderingTerm.asc(room.name),
      ]);
    return query
        .watch()
        .map((rows) => rows.map(_roomFromRow).toList())
        .distinctByFingerprint(roomListFingerprint);
  }

  @override
  Future<List<domain.Room>> listRooms({String? areaId}) async {
    final query = db.select(db.rooms)
      ..where(
        (room) =>
            room.archivedAt.isNull() &
            (areaId == null
                ? const Constant(true)
                : room.areaId.equals(areaId)),
      )
      ..orderBy([
        (room) => OrderingTerm.asc(room.sortOrder),
        (room) => OrderingTerm.asc(room.name),
      ]);
    return (await query.get()).map(_roomFromRow).toList();
  }

  @override
  Future<String> saveRoom({
    String? id,
    required String areaId,
    required String name,
    domain.RoomType roomType = domain.RoomType.other,
    String? notes,
    int? sortOrder,
  }) async {
    final roomId = id ?? _uuid.v7();
    final now = DateTime.now();
    final existing = id == null
        ? null
        : await (db.select(
            db.rooms,
          )..where((room) => room.id.equals(roomId))).getSingleOrNull();
    final resolvedSortOrder =
        sortOrder ??
        (existing?.areaId == areaId ? existing?.sortOrder : null) ??
        await _nextRoomSortOrder(areaId);
    if (id == null) {
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              id: roomId,
              areaId: areaId,
              name: name.trim(),
              roomType: Value(roomType.name),
              notes: Value(_blankToNull(notes)),
              sortOrder: Value(resolvedSortOrder),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    } else {
      await (db.update(
        db.rooms,
      )..where((room) => room.id.equals(roomId))).write(
        RoomsCompanion(
          areaId: Value(areaId),
          name: Value(name.trim()),
          roomType: Value(roomType.name),
          notes: Value(_blankToNull(notes)),
          sortOrder: Value(resolvedSortOrder),
          updatedAt: Value(now),
        ),
      );
    }
    return roomId;
  }

  @override
  Future<void> archiveRoom(String id) async {
    final assetRows =
        await (db.select(db.assets)..where(
              (asset) => asset.roomId.equals(id) & asset.archivedAt.isNull(),
            ))
            .get();
    if (assetRows.isNotEmpty) {
      throw StateError('Move or archive items before archiving this room.');
    }
    await (db.update(db.rooms)..where((room) => room.id.equals(id))).write(
      RoomsCompanion(
        archivedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> deleteRoom(String id) async {
    final assetRows = await (db.select(
      db.assets,
    )..where((asset) => asset.roomId.equals(id))).get();
    final assetIds = assetRows.map((row) => row.id).toList();
    final photoRows = await _photoRowsForAssets(assetIds);
    await db.transaction(() async {
      await _deleteAssetsCascadeInTransaction(assetIds);
      await (db.delete(db.rooms)..where((room) => room.id.equals(id))).go();
    });
    await _deletePhotoFiles(photoRows);
  }

  @override
  Stream<List<domain.Room>> watchArchivedRooms() {
    final query = db.select(db.rooms)
      ..where((room) => room.archivedAt.isNotNull())
      ..orderBy([
        (room) => OrderingTerm.desc(room.archivedAt),
        (room) => OrderingTerm.asc(room.name),
      ]);
    return query
        .watch()
        .map((rows) => rows.map(_roomFromRow).toList())
        .distinctByFingerprint(roomListFingerprint);
  }

  @override
  Future<List<domain.Room>> listArchivedRooms() async {
    final rows =
        await (db.select(db.rooms)
              ..where((room) => room.archivedAt.isNotNull())
              ..orderBy([
                (room) => OrderingTerm.desc(room.archivedAt),
                (room) => OrderingTerm.asc(room.name),
              ]))
            .get();
    return rows.map(_roomFromRow).toList();
  }

  @override
  Future<void> trashRoom(String id) async {
    await db.transaction(() async {
      final now = await _nextTrashCascadeTimestamp();
      final room = await (db.select(
        db.rooms,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (room == null || room.archivedAt != null) return;
      final activeAssets = await (db.select(
        db.assets,
      )..where((row) => row.roomId.equals(id) & row.archivedAt.isNull())).get();
      final assetIds = activeAssets.map((row) => row.id).toList();
      await (db.update(db.rooms)..where((row) => row.id.equals(id))).write(
        RoomsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
      );
      if (assetIds.isNotEmpty) {
        await (db.update(
          db.assets,
        )..where((row) => row.id.isIn(assetIds))).write(
          AssetsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
        );
        await (db.update(db.maintenancePlans)..where(
              (plan) => plan.assetId.isIn(assetIds) & plan.archivedAt.isNull(),
            ))
            .write(
              MaintenancePlansCompanion(
                archivedAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      }
    });
  }

  @override
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
      final cascadeAssets =
          await (db.select(db.assets)..where(
                (row) =>
                    row.roomId.equals(id) & row.archivedAt.equals(cascadeAt),
              ))
              .get();
      final assetIds = cascadeAssets.map((row) => row.id).toList();
      await (db.update(db.rooms)..where((row) => row.id.equals(id))).write(
        RoomsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
      );
      if (assetIds.isNotEmpty) {
        await (db.update(
          db.assets,
        )..where((row) => row.id.isIn(assetIds))).write(
          AssetsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
        );
        await (db.update(db.maintenancePlans)..where(
              (plan) =>
                  plan.assetId.isIn(assetIds) &
                  plan.archivedAt.equals(cascadeAt),
            ))
            .write(
              MaintenancePlansCompanion(
                archivedAt: const Value(null),
                updatedAt: Value(now),
              ),
            );
      }
    });
  }

  @override
  Stream<List<domain.Asset>> watchAssets({String? roomId}) {
    return watchReloaded(
      triggers: [
        db.select(db.assets).watch(),
        db.select(db.deviceDetailsTable).watch(),
        db.select(db.petDetailsTable).watch(),
        db.select(db.plantDetailsTable).watch(),
        db.select(db.safetyDetailsTable).watch(),
      ],
      load: () => listAssets(roomId: roomId),
      fingerprint: assetListFingerprint,
    );
  }

  @override
  Future<List<domain.Asset>> listAssets({String? roomId}) async {
    final query = db.select(db.assets)
      ..where(
        (asset) =>
            asset.archivedAt.isNull() &
            (roomId == null
                ? const Constant(true)
                : asset.roomId.equals(roomId)),
      )
      ..orderBy([(asset) => OrderingTerm.asc(asset.name)]);
    return _hydrateAssetRows(await query.get());
  }

  @override
  Stream<domain.Asset?> watchAsset(String id) {
    return watchReloaded(
      triggers: [
        db.select(db.assets).watch(),
        db.select(db.deviceDetailsTable).watch(),
        db.select(db.petDetailsTable).watch(),
        db.select(db.plantDetailsTable).watch(),
        db.select(db.safetyDetailsTable).watch(),
      ],
      load: () => getAsset(id),
      fingerprint: (asset) => asset == null ? 0 : assetFingerprint(asset),
    );
  }

  @override
  Future<domain.Asset?> getAsset(String id) async {
    final row = await (db.select(
      db.assets,
    )..where((asset) => asset.id.equals(id))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return (await _hydrateAssetRows([row])).first;
  }

  @override
  Future<String> saveAsset({
    String? id,
    required String name,
    domain.AssetType assetType = domain.AssetType.general,
    required String roomId,
    String? placement,
    String? notes,
    DateTime? purchaseDate,
    List<String> tagNames = const [],
    domain.DeviceDetails? deviceDetails,
    domain.PetDetails? petDetails,
    domain.PlantDetails? plantDetails,
    domain.SafetyDetails? safetyDetails,
  }) async {
    final assetId = id ?? _uuid.v7();
    final now = DateTime.now();
    await db.transaction(() async {
      final existingAsset = await (db.select(
        db.assets,
      )..where((row) => row.id.equals(assetId))).getSingleOrNull();
      final previousPlantDetails = existingAsset == null
          ? null
          : await (db.select(
              db.plantDetailsTable,
            )..where((row) => row.assetId.equals(assetId))).getSingleOrNull();
      if (existingAsset == null) {
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: assetId,
                name: name.trim(),
                assetType: Value(assetType.name),
                roomId: roomId,
                placement: Value(_blankToNull(placement)),
                notes: Value(_blankToNull(notes)),
                purchaseDate: Value(purchaseDate),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      } else {
        await (db.update(
          db.assets,
        )..where((asset) => asset.id.equals(assetId))).write(
          AssetsCompanion(
            name: Value(name.trim()),
            assetType: Value(assetType.name),
            roomId: Value(roomId),
            placement: Value(_blankToNull(placement)),
            notes: Value(_blankToNull(notes)),
            purchaseDate: Value(purchaseDate),
            updatedAt: Value(now),
          ),
        );
      }

      await _replaceAssetDetails(
        assetId: assetId,
        assetType: assetType,
        deviceDetails: deviceDetails,
        petDetails: petDetails,
        plantDetails: plantDetails,
        safetyDetails: safetyDetails,
      );
      await _syncPlantWateringPlansForInterval(
        db: db,
        assetId: assetId,
        previousIntervalDays: previousPlantDetails?.wateringIntervalDays,
        nextIntervalDays: assetType == domain.AssetType.plant
            ? plantDetails?.wateringIntervalDays
            : null,
        updatedAt: now,
      );

      await (db.delete(
        db.assetTags,
      )..where((tag) => tag.assetId.equals(assetId))).go();
      for (final rawTag in tagNames) {
        final tagName = rawTag.trim();
        if (tagName.isEmpty) {
          continue;
        }
        final tagId = await _ensureTag(tagName);
        await db
            .into(db.assetTags)
            .insert(
              AssetTagsCompanion.insert(assetId: assetId, tagId: tagId),
              mode: InsertMode.insertOrIgnore,
            );
      }
    });
    return assetId;
  }

  @override
  Future<void> moveAsset({
    required String assetId,
    required String roomId,
  }) async {
    await _ensureActiveRoom(roomId);
    final asset = await getAsset(assetId);
    if (asset == null || asset.archivedAt != null) {
      throw StateError('Item is no longer available.');
    }
    final tags = await listTagsForAsset(assetId);
    await saveAsset(
      id: asset.id,
      name: asset.name,
      assetType: asset.assetType,
      roomId: roomId,
      placement: asset.placement,
      notes: asset.notes,
      purchaseDate: asset.purchaseDate,
      tagNames: [for (final tag in tags) tag.name],
      deviceDetails: asset.deviceDetails,
      petDetails: asset.petDetails,
      plantDetails: asset.plantDetails,
      safetyDetails: asset.safetyDetails,
    );
  }

  @override
  Future<String> copyAsset({
    required String assetId,
    required String roomId,
    bool includeTasks = true,
    bool includePhotos = false,
    String? newAssetId,
    Map<String, String> taskIdBySource = const {},
  }) async {
    await _ensureActiveRoom(roomId);
    final source = await getAsset(assetId);
    if (source == null || source.archivedAt != null) {
      throw StateError('Item is no longer available.');
    }
    final tags = await listTagsForAsset(assetId);
    final copiedAssetId = await saveAsset(
      id: newAssetId,
      name: source.name,
      assetType: source.assetType,
      roomId: roomId,
      placement: source.placement,
      notes: source.notes,
      purchaseDate: source.purchaseDate,
      tagNames: [for (final tag in tags) tag.name],
      deviceDetails: source.deviceDetails,
      petDetails: source.petDetails,
      plantDetails: source.plantDetails,
      safetyDetails: source.safetyDetails,
    );
    if (includeTasks) {
      final maintenance = DriftMaintenanceRepository(db);
      final tasks = await maintenance.listTasksForAsset(assetId);
      for (final task in tasks) {
        await maintenance.savePlan(
          id: taskIdBySource[task.plan.id],
          assetId: copiedAssetId,
          title: task.plan.title,
          instructions: task.plan.instructions,
          recurrence: task.plan.recurrence,
          priority: task.plan.priority,
          nextDueDate: task.plan.nextDueDate,
          reminderDaysBefore: task.plan.reminderDaysBefore,
          metadata: task.plan.metadata,
        );
      }
    }
    if (includePhotos) {
      final docDir = await getApplicationDocumentsDirectory();
      final photos = await listPhotosForAsset(assetId);
      for (final photo in photos) {
        final file = File(
          p.joinAll([docDir.path, ...photo.relativePath.split('/')]),
        );
        if (!await file.exists()) {
          continue;
        }
        await addPhoto(
          copiedAssetId,
          file.path,
          caption: photo.caption,
          makePrimary: photo.isPrimary,
        );
      }
    }
    return copiedAssetId;
  }

  @override
  Future<void> archiveAsset(String id) async {
    await (db.update(db.assets)..where((asset) => asset.id.equals(id))).write(
      AssetsCompanion(
        archivedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> deleteAsset(String id) async {
    final photoRows = await _photoRowsForAssets([id]);
    await db.transaction(() async {
      await _deleteAssetsCascadeInTransaction([id]);
    });
    await _deletePhotoFiles(photoRows);
  }

  @override
  Stream<List<domain.Asset>> watchArchivedAssets() {
    return watchReloaded(
      triggers: [
        db.select(db.assets).watch(),
        db.select(db.deviceDetailsTable).watch(),
        db.select(db.petDetailsTable).watch(),
        db.select(db.plantDetailsTable).watch(),
        db.select(db.safetyDetailsTable).watch(),
      ],
      load: listArchivedAssets,
      fingerprint: assetListFingerprint,
    );
  }

  @override
  Future<List<domain.Asset>> listArchivedAssets() async {
    final rows =
        await (db.select(db.assets)
              ..where((asset) => asset.archivedAt.isNotNull())
              ..orderBy([
                (asset) => OrderingTerm.desc(asset.archivedAt),
                (asset) => OrderingTerm.asc(asset.name),
              ]))
            .get();
    return _hydrateAssetRows(rows);
  }

  @override
  Future<void> trashAsset(String id) async {
    await db.transaction(() async {
      final now = await _nextTrashCascadeTimestamp();
      final asset = await (db.select(
        db.assets,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (asset == null || asset.archivedAt != null) return;
      await (db.update(db.assets)..where((row) => row.id.equals(id))).write(
        AssetsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
      );
      await (db.update(db.maintenancePlans)..where(
            (plan) => plan.assetId.equals(id) & plan.archivedAt.isNull(),
          ))
          .write(
            MaintenancePlansCompanion(
              archivedAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    });
  }

  @override
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
      if (room == null ||
          room.archivedAt != null ||
          area == null ||
          area.archivedAt != null) {
        throw StateError(
          'Restore the parent room and area before restoring this item.',
        );
      }
      await (db.update(db.assets)..where((row) => row.id.equals(id))).write(
        AssetsCompanion(archivedAt: const Value(null), updatedAt: Value(now)),
      );
      await (db.update(db.maintenancePlans)..where(
            (plan) =>
                plan.assetId.equals(id) & plan.archivedAt.equals(cascadeAt),
          ))
          .write(
            MaintenancePlansCompanion(
              archivedAt: const Value(null),
              updatedAt: Value(now),
            ),
          );
    });
  }

  @override
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
      if (planIds.isNotEmpty) {
        await _deletePlansCascade(db, planIds);
      }
      if (assetIds.isNotEmpty) {
        await _deleteAssetsCascadeInTransaction(assetIds);
      }
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

  @override
  Future<domain.AssetPhoto> addPhoto(
    String assetId,
    String sourcePath, {
    String? caption,
    bool makePrimary = false,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw ArgumentError.value(
        sourcePath,
        'sourcePath',
        'Photo file does not exist.',
      );
    }
    final docDir = await getApplicationDocumentsDirectory();
    final photoId = _uuid.v7();
    final extension = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    final relativePath = p.posix.join('photos', assetId, '$photoId$extension');
    final destination = File(
      p.joinAll([docDir.path, ...relativePath.split('/')]),
    );
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);
    final existingPhotos = await listPhotosForAsset(assetId);
    final isPrimary = makePrimary || existingPhotos.isEmpty;
    final createdAt = DateTime.now();
    try {
      await db.transaction(() async {
        if (isPrimary) {
          await (db.update(db.assetPhotos)
                ..where((photo) => photo.assetId.equals(assetId)))
              .write(const AssetPhotosCompanion(isPrimary: Value(false)));
        }
        await db
            .into(db.assetPhotos)
            .insert(
              AssetPhotosCompanion.insert(
                id: photoId,
                assetId: assetId,
                relativePath: relativePath,
                caption: Value(_blankToNull(caption)),
                isPrimary: Value(isPrimary),
                createdAt: Value(createdAt),
              ),
            );
      });
    } catch (_) {
      try {
        if (await destination.exists()) {
          await destination.delete();
        }
      } catch (_) {
        // The database insert failed, so the app should not rely on this file.
      }
      rethrow;
    }
    return domain.AssetPhoto(
      id: photoId,
      assetId: assetId,
      relativePath: relativePath,
      caption: _blankToNull(caption),
      isPrimary: isPrimary,
      createdAt: createdAt,
    );
  }

  @override
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

      await (db.update(db.syncRuntime)..where((row) => row.id.equals(1))).write(
        const SyncRuntimeCompanion(suppressOutbox: Value(true)),
      );
      try {
        await (db.update(db.assetPhotos)
              ..where((photo) => photo.assetId.equals(assetId)))
            .write(const AssetPhotosCompanion(isPrimary: Value(false)));
        await (db.update(db.assetPhotos)..where(
              (photo) =>
                  photo.id.equals(photoId) & photo.assetId.equals(assetId),
            ))
            .write(const AssetPhotosCompanion(isPrimary: Value(true)));
      } finally {
        await (db.update(db.syncRuntime)..where((row) => row.id.equals(1)))
            .write(const SyncRuntimeCompanion(suppressOutbox: Value(false)));
      }

      final account = await (db.select(
        db.syncAccount,
      )..where((row) => row.id.equals(1))).getSingleOrNull();
      await db
          .into(db.syncOutbox)
          .insertOnConflictUpdate(
            SyncOutboxCompanion.insert(
              entity: 'asset_photo_primary',
              recordKey: assetId,
              operation: 'execute',
              changedAt: Value(now),
              payloadJson: Value(
                jsonEncode({
                  'version': 1,
                  'asset_id': assetId,
                  'photo_id': photoId,
                }),
              ),
              userId: Value(account?.boundUserId),
            ),
          );
    });
  }

  @override
  Future<void> deletePhoto(String photoId) async {
    final row = await (db.select(
      db.assetPhotos,
    )..where((photo) => photo.id.equals(photoId))).getSingleOrNull();
    if (row == null) {
      return;
    }
    await (db.delete(
      db.assetPhotos,
    )..where((photo) => photo.id.equals(photoId))).go();
    if (row.isPrimary) {
      final next =
          await (db.select(db.assetPhotos)
                ..where((photo) => photo.assetId.equals(row.assetId))
                ..orderBy([(photo) => OrderingTerm.desc(photo.createdAt)])
                ..limit(1))
              .getSingleOrNull();
      if (next != null) {
        await setPrimaryPhoto(row.assetId, next.id);
      }
    }
    await _deletePhotoFile(row);
  }

  @override
  Stream<List<domain.AssetPhoto>> watchPhotosForAsset(String assetId) {
    return (db.select(db.assetPhotos)
          ..where((photo) => photo.assetId.equals(assetId))
          ..orderBy([
            (photo) => OrderingTerm.desc(photo.isPrimary),
            (photo) => OrderingTerm.desc(photo.createdAt),
          ]))
        .watch()
        .map((rows) => rows.map(_photoFromRow).toList())
        .distinctByFingerprint(assetPhotoListFingerprint);
  }

  @override
  Future<List<domain.AssetPhoto>> listPhotosForAsset(String assetId) async {
    final rows =
        await (db.select(db.assetPhotos)
              ..where((photo) => photo.assetId.equals(assetId))
              ..orderBy([
                (photo) => OrderingTerm.desc(photo.isPrimary),
                (photo) => OrderingTerm.desc(photo.createdAt),
              ]))
            .get();
    return rows.map(_photoFromRow).toList();
  }

  @override
  Stream<List<domain.Tag>> watchTagsForAsset(String assetId) {
    return watchReloaded(
      triggers: [db.select(db.assetTags).watch(), db.select(db.tags).watch()],
      load: () => listTagsForAsset(assetId),
      fingerprint: tagListFingerprint,
    );
  }

  @override
  Future<List<domain.Tag>> listTagsForAsset(String assetId) async {
    final rows = await (db.select(
      db.assetTags,
    )..where((tag) => tag.assetId.equals(assetId))).get();
    final ids = rows.map((row) => row.tagId).toList();
    if (ids.isEmpty) {
      return [];
    }
    final tags = await (db.select(
      db.tags,
    )..where((tag) => tag.id.isIn(ids))).get();
    return tags.map(_tagFromRow).toList();
  }

  Future<List<AssetPhotoRow>> _photoRowsForAssets(List<String> assetIds) async {
    if (assetIds.isEmpty) {
      return [];
    }
    return (db.select(
      db.assetPhotos,
    )..where((photo) => photo.assetId.isIn(assetIds))).get();
  }

  Future<void> _deleteAssetsCascadeInTransaction(List<String> assetIds) async {
    if (assetIds.isEmpty) {
      return;
    }
    final planRows = await (db.select(
      db.maintenancePlans,
    )..where((plan) => plan.assetId.isIn(assetIds))).get();
    await _deletePlansCascade(db, planRows.map((row) => row.id).toList());
    await (db.delete(
      db.assetTags,
    )..where((row) => row.assetId.isIn(assetIds))).go();
    await (db.delete(
      db.assetPhotos,
    )..where((row) => row.assetId.isIn(assetIds))).go();
    await (db.delete(
      db.deviceDetailsTable,
    )..where((row) => row.assetId.isIn(assetIds))).go();
    await (db.delete(
      db.petDetailsTable,
    )..where((row) => row.assetId.isIn(assetIds))).go();
    await (db.delete(
      db.plantDetailsTable,
    )..where((row) => row.assetId.isIn(assetIds))).go();
    await (db.delete(
      db.safetyDetailsTable,
    )..where((row) => row.assetId.isIn(assetIds))).go();
    await (db.delete(db.assets)..where((row) => row.id.isIn(assetIds))).go();
  }

  Future<void> _deletePhotoFiles(List<AssetPhotoRow> photoRows) async {
    if (photoRows.isEmpty) {
      return;
    }
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final assetIds = <String>{};
      for (final row in photoRows) {
        assetIds.add(row.assetId);
        final file = File(
          p.joinAll([docDir.path, ...row.relativePath.split('/')]),
        );
        if (await file.exists()) {
          await file.delete();
        }
      }
      for (final assetId in assetIds) {
        final dir = Directory(p.join(docDir.path, 'photos', assetId));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    } catch (_) {
      // Database cleanup is authoritative; stale photo files should not block it.
    }
  }

  Future<void> _deletePhotoFile(AssetPhotoRow row) async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final file = File(
        p.joinAll([docDir.path, ...row.relativePath.split('/')]),
      );
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Database cleanup is authoritative; stale photo files should not block it.
    }
  }

  Future<int> _nextAreaSortOrder() async {
    final rows = await db.select(db.areas).get();
    if (rows.isEmpty) {
      return 0;
    }
    return rows.map((row) => row.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<int> _nextRoomSortOrder(String areaId) async {
    final rows = await (db.select(
      db.rooms,
    )..where((room) => room.areaId.equals(areaId))).get();
    if (rows.isEmpty) {
      return 0;
    }
    return rows.map((row) => row.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<void> _replaceAssetDetails({
    required String assetId,
    required domain.AssetType assetType,
    domain.DeviceDetails? deviceDetails,
    domain.PetDetails? petDetails,
    domain.PlantDetails? plantDetails,
    domain.SafetyDetails? safetyDetails,
  }) async {
    await (db.delete(
      db.deviceDetailsTable,
    )..where((row) => row.assetId.equals(assetId))).go();
    await (db.delete(
      db.petDetailsTable,
    )..where((row) => row.assetId.equals(assetId))).go();
    await (db.delete(
      db.plantDetailsTable,
    )..where((row) => row.assetId.equals(assetId))).go();
    await (db.delete(
      db.safetyDetailsTable,
    )..where((row) => row.assetId.equals(assetId))).go();

    switch (assetType) {
      case domain.AssetType.device:
        final details = deviceDetails ?? const domain.DeviceDetails();
        await db
            .into(db.deviceDetailsTable)
            .insert(
              DeviceDetailsTableCompanion.insert(
                assetId: assetId,
                brand: Value(_blankToNull(details.brand)),
                model: Value(_blankToNull(details.model)),
                serialNumber: Value(_blankToNull(details.serialNumber)),
                powerSource: Value(details.powerSource?.name),
                warrantyUntil: Value(details.warrantyUntil),
                manualUrl: Value(_blankToNull(details.manualUrl)),
                consumable: Value(_blankToNull(details.consumable)),
              ),
            );
      case domain.AssetType.pet:
        final details = petDetails ?? const domain.PetDetails();
        await db
            .into(db.petDetailsTable)
            .insert(
              PetDetailsTableCompanion.insert(
                assetId: assetId,
                species: Value(_blankToNull(details.species)),
                breed: Value(_blankToNull(details.breed)),
                birthDate: Value(details.birthDate),
                microchipId: Value(_blankToNull(details.microchipId)),
                vetName: Value(_blankToNull(details.vetName)),
                vetPhone: Value(_blankToNull(details.vetPhone)),
                feedingNotes: Value(_blankToNull(details.feedingNotes)),
                medicalNotes: Value(_blankToNull(details.medicalNotes)),
              ),
            );
      case domain.AssetType.plant:
        final details = plantDetails ?? const domain.PlantDetails();
        await db
            .into(db.plantDetailsTable)
            .insert(
              PlantDetailsTableCompanion.insert(
                assetId: assetId,
                species: Value(_blankToNull(details.species)),
                sunlight: Value(details.sunlight?.name),
                wateringIntervalDays: Value(details.wateringIntervalDays),
                potSize: Value(_blankToNull(details.potSize)),
                lastRepottedAt: Value(details.lastRepottedAt),
                toxicityNotes: Value(_blankToNull(details.toxicityNotes)),
              ),
            );
      case domain.AssetType.safety:
        final details = safetyDetails ?? const domain.SafetyDetails();
        await db
            .into(db.safetyDetailsTable)
            .insert(
              SafetyDetailsTableCompanion.insert(
                assetId: assetId,
                safetyType: Value(_blankToNull(details.safetyType)),
                installedAt: Value(details.installedAt),
                expiresAt: Value(details.expiresAt),
                batteryType: Value(_blankToNull(details.batteryType)),
                testIntervalDays: Value(details.testIntervalDays),
              ),
            );
      case domain.AssetType.general:
        break;
    }
  }

  Future<List<domain.Asset>> _hydrateAssetRows(List<AssetRow> rows) async {
    if (rows.isEmpty) {
      return [];
    }
    final ids = rows.map((row) => row.id).toSet().toList();
    final deviceRows = await (db.select(
      db.deviceDetailsTable,
    )..where((row) => row.assetId.isIn(ids))).get();
    final petRows = await (db.select(
      db.petDetailsTable,
    )..where((row) => row.assetId.isIn(ids))).get();
    final plantRows = await (db.select(
      db.plantDetailsTable,
    )..where((row) => row.assetId.isIn(ids))).get();
    final safetyRows = await (db.select(
      db.safetyDetailsTable,
    )..where((row) => row.assetId.isIn(ids))).get();
    final devices = {
      for (final row in deviceRows) row.assetId: _deviceDetailsFromRow(row),
    };
    final pets = {
      for (final row in petRows) row.assetId: _petDetailsFromRow(row),
    };
    final plants = {
      for (final row in plantRows) row.assetId: _plantDetailsFromRow(row),
    };
    final safetyItems = {
      for (final row in safetyRows) row.assetId: _safetyDetailsFromRow(row),
    };
    return [
      for (final row in rows)
        _assetFromRow(
          row,
          deviceDetails: devices[row.id],
          petDetails: pets[row.id],
          plantDetails: plants[row.id],
          safetyDetails: safetyItems[row.id],
        ),
    ];
  }

  Future<String> _ensureTag(String tagName) async {
    final existing = await db
        .customSelect(
          'SELECT id FROM tags WHERE name = ? COLLATE NOCASE LIMIT 1',
          variables: [Variable.withString(tagName)],
          readsFrom: {db.tags},
        )
        .getSingleOrNull();
    if (existing != null) {
      return existing.read<String>('id');
    }
    final id = _uuid.v7();
    await db
        .into(db.tags)
        .insert(
          TagsCompanion.insert(
            id: id,
            name: tagName,
            createdAt: Value(DateTime.now()),
          ),
        );
    return id;
  }

  Future<void> _ensureActiveRoom(String roomId) async {
    final room =
        await (db.select(db.rooms)
              ..where((row) => row.id.equals(roomId) & row.archivedAt.isNull()))
            .getSingleOrNull();
    if (room == null) {
      throw StateError('Choose an active room.');
    }
  }
}
