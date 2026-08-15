import 'models.dart';

int areaFingerprint(Area area) =>
    Object.hash(area.id, area.name, area.kind, area.sortOrder, area.archivedAt);

int areaListFingerprint(Iterable<Area> areas) =>
    Object.hashAll(areas.map(areaFingerprint));

int roomFingerprint(Room room) => Object.hash(
  room.id,
  room.areaId,
  room.name,
  room.roomType,
  room.notes,
  room.sortOrder,
  room.archivedAt,
);

int roomListFingerprint(Iterable<Room> rooms) =>
    Object.hashAll(rooms.map(roomFingerprint));

int categoryFingerprint(Category category) => Object.hash(
  category.id,
  category.name,
  category.healthGroup,
  category.iconName,
);

int categoryListFingerprint(Iterable<Category> categories) =>
    Object.hashAll(categories.map(categoryFingerprint));

int tagFingerprint(Tag tag) => Object.hash(tag.id, tag.name);

int tagListFingerprint(Iterable<Tag> tags) =>
    Object.hashAll(tags.map(tagFingerprint));

int assetPhotoFingerprint(AssetPhoto photo) => Object.hash(
  photo.id,
  photo.assetId,
  photo.relativePath,
  photo.isPrimary,
  photo.caption,
);

int assetPhotoListFingerprint(Iterable<AssetPhoto> photos) =>
    Object.hashAll(photos.map(assetPhotoFingerprint));

int assetFingerprint(Asset asset) => Object.hashAll([
  asset.id,
  asset.name,
  asset.assetType,
  asset.categoryId,
  asset.roomId,
  asset.placement,
  asset.notes,
  asset.purchaseDate,
  asset.archivedAt,
  _deviceDetailsFingerprint(asset.deviceDetails),
  _petDetailsFingerprint(asset.petDetails),
  _plantDetailsFingerprint(asset.plantDetails),
  _safetyDetailsFingerprint(asset.safetyDetails),
]);

int assetListFingerprint(Iterable<Asset> assets) =>
    Object.hashAll(assets.map(assetFingerprint));

int taskFingerprint(TaskItem task) => Object.hashAll([
  task.plan.id,
  task.plan.assetId,
  task.plan.title,
  task.plan.instructions,
  task.plan.recurrence.interval,
  task.plan.recurrence.unit,
  task.plan.priority,
  task.plan.nextDueDate,
  task.plan.reminderDaysBefore,
  task.plan.isEnabled,
  task.plan.healthGroup,
  task.plan.archivedAt,
  _taskMetadataFingerprint(task.plan.metadata),
  assetFingerprint(task.asset),
  categoryFingerprint(task.category),
  roomFingerprint(task.room),
  task.status,
]);

int taskListFingerprint(Iterable<TaskItem> tasks) =>
    Object.hashAll(tasks.map(taskFingerprint));

int maintenanceRecordFingerprint(MaintenanceRecord record) => Object.hash(
  record.id,
  record.planId,
  record.dueDate,
  record.completedAt,
  record.notes,
);

int maintenanceRecordListFingerprint(Iterable<MaintenanceRecord> records) =>
    Object.hashAll(records.map(maintenanceRecordFingerprint));

int dashboardSummaryFingerprint(DashboardSummary summary) => Object.hash(
  summary.todayTasks,
  summary.upcomingTasks,
  summary.overdueTasks,
  summary.health.score,
  _enumDoubleMapFingerprint(summary.health.groupScores),
  _enumDoubleMapFingerprint(summary.health.activeWeights),
  summary.streak.currentStreak,
  summary.streak.bestStreak,
  summary.streak.lastCompletedDate,
  summary.completionRate,
  summary.completedThisMonth,
);

int statisticsSummaryFingerprint(StatisticsSummary summary) => Object.hash(
  summary.completionRate,
  summary.overdueRate,
  Object.hashAll(
    (summary.completedByMonth.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((entry) => Object.hash(entry.key, entry.value)),
  ),
  Object.hashAll(
    (summary.taskDistribution.entries.toList()
          ..sort((a, b) => a.key.index.compareTo(b.key.index)))
        .map((entry) => Object.hash(entry.key, entry.value)),
  ),
);

int _enumDoubleMapFingerprint(Map<HealthGroup, double> values) =>
    Object.hashAll(
      (values.entries.toList()
            ..sort((a, b) => a.key.index.compareTo(b.key.index)))
          .map((entry) => Object.hash(entry.key, entry.value)),
    );

int _deviceDetailsFingerprint(DeviceDetails? details) => details == null
    ? 0
    : Object.hashAll([
        details.brand,
        details.model,
        details.serialNumber,
        details.powerSource,
        details.warrantyUntil,
        details.manualUrl,
        details.consumable,
      ]);

int _petDetailsFingerprint(PetDetails? details) => details == null
    ? 0
    : Object.hashAll([
        details.species,
        details.breed,
        details.birthDate,
        details.microchipId,
        details.vetName,
        details.vetPhone,
        details.feedingNotes,
        details.medicalNotes,
      ]);

int _plantDetailsFingerprint(PlantDetails? details) => details == null
    ? 0
    : Object.hashAll([
        details.species,
        details.sunlight,
        details.wateringIntervalDays,
        details.potSize,
        details.lastRepottedAt,
        details.toxicityNotes,
      ]);

int _safetyDetailsFingerprint(SafetyDetails? details) => details == null
    ? 0
    : Object.hashAll([
        details.safetyType,
        details.installedAt,
        details.expiresAt,
        details.batteryType,
        details.testIntervalDays,
      ]);

int _taskMetadataFingerprint(TaskMetadata? metadata) => metadata == null
    ? 0
    : Object.hashAll([
        metadata.taskType,
        metadata.locationLabel,
        metadata.estimatedDurationMinutes,
        Object.hashAll(metadata.requiredMaterials),
        metadata.reminderRecommendation,
        metadata.sortOrder,
      ]);
