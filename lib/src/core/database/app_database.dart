import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/input_validation.dart';
import '../domain/models.dart';

part 'app_database.g.dart';

/// Monotonic generation identity for the local database.
///
/// A successful atomic restore closes the previous handles, swaps the data,
/// and increments this epoch exactly once. Every database-derived provider
/// reaches the database through [databaseProvider], which watches this value,
/// so dependent caches dispose and reload without any cross-feature
/// invalidation lists. Failed or rolled-back restores never publish a new
/// epoch.
class DatabaseRestoreEpoch extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final databaseRestoreEpochProvider =
    NotifierProvider<DatabaseRestoreEpoch, int>(DatabaseRestoreEpoch.new);

final databaseProvider = Provider<AppDatabase>((ref) {
  // Depend on the restore epoch so the database (and therefore every
  // repository and stream derived from it) is rebuilt when a restore swaps
  // the underlying data.
  ref.watch(databaseRestoreEpochProvider);
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

CustomExpression<bool> _maxLengthCheck(String column, int maximum) =>
    CustomExpression<bool>('length($column) <= $maximum');

CustomExpression<bool> _boundedLengthCheck(
  String column, {
  required int minimum,
  required int maximum,
}) => CustomExpression<bool>('length($column) BETWEEN $minimum AND $maximum');

@DataClassName('AreaRow')
class Areas extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get kind => text().check(
    const CustomExpression<bool>(
      "kind IN ('indoor', 'outdoor', 'utility', 'other')",
    ),
  )();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('RoomRow')
class Rooms extends Table {
  TextColumn get id => text()();
  TextColumn get areaId =>
      text().references(Areas, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get roomType => text()
      .withLength(min: 1, max: 120)
      .withDefault(const Constant('other'))();
  TextColumn get notes => text().withLength(max: 4000).nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AssetRow')
class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()
      .withLength(min: 1, max: InputValidationLimits.assetName)
      .check(
        _boundedLengthCheck(
          'name',
          minimum: 1,
          maximum: InputValidationLimits.assetName,
        ),
      )();
  TextColumn get assetType => text()
      .check(
        const CustomExpression<bool>(
          "asset_type IN ('device', 'pet', 'plant', 'safety', 'general')",
        ),
      )
      .withDefault(const Constant('general'))();
  TextColumn get roomId =>
      text().references(Rooms, #id, onDelete: KeyAction.cascade)();
  TextColumn get placement => text()
      .withLength(max: InputValidationLimits.assetPlacement)
      .check(_maxLengthCheck('placement', InputValidationLimits.assetPlacement))
      .nullable()();
  TextColumn get notes => text()
      .withLength(max: InputValidationLimits.assetNotes)
      .check(_maxLengthCheck('notes', InputValidationLimits.assetNotes))
      .nullable()();
  DateTimeColumn get purchaseDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('DeviceDetailRow')
class DeviceDetailsTable extends Table {
  @override
  String get tableName => 'device_details';

  TextColumn get assetId =>
      text().references(Assets, #id, onDelete: KeyAction.cascade)();
  TextColumn get brand => text()
      .withLength(max: InputValidationLimits.deviceBrand)
      .check(_maxLengthCheck('brand', InputValidationLimits.deviceBrand))
      .nullable()();
  TextColumn get model => text()
      .withLength(max: InputValidationLimits.deviceModel)
      .check(_maxLengthCheck('model', InputValidationLimits.deviceModel))
      .nullable()();
  TextColumn get serialNumber => text()
      .withLength(max: InputValidationLimits.deviceSerialNumber)
      .check(
        _maxLengthCheck(
          'serial_number',
          InputValidationLimits.deviceSerialNumber,
        ),
      )
      .nullable()();
  TextColumn get powerSource => text()
      .withLength(max: InputValidationLimits.devicePowerSource)
      .check(
        _maxLengthCheck(
          'power_source',
          InputValidationLimits.devicePowerSource,
        ),
      )
      .nullable()();
  DateTimeColumn get warrantyUntil => dateTime().nullable()();
  TextColumn get manualUrl => text()
      .withLength(max: InputValidationLimits.deviceManualUrl)
      .check(
        _maxLengthCheck('manual_url', InputValidationLimits.deviceManualUrl),
      )
      .nullable()();
  TextColumn get consumable => text()
      .withLength(max: InputValidationLimits.deviceConsumable)
      .check(
        _maxLengthCheck('consumable', InputValidationLimits.deviceConsumable),
      )
      .nullable()();

  @override
  Set<Column<Object>> get primaryKey => {assetId};
}

@DataClassName('PetDetailRow')
class PetDetailsTable extends Table {
  @override
  String get tableName => 'pet_details';

  TextColumn get assetId =>
      text().references(Assets, #id, onDelete: KeyAction.cascade)();
  TextColumn get species => text()
      .withLength(max: InputValidationLimits.petSpecies)
      .check(_maxLengthCheck('species', InputValidationLimits.petSpecies))
      .nullable()();
  TextColumn get breed => text()
      .withLength(max: InputValidationLimits.petBreed)
      .check(_maxLengthCheck('breed', InputValidationLimits.petBreed))
      .nullable()();
  DateTimeColumn get birthDate => dateTime().nullable()();
  TextColumn get microchipId => text()
      .withLength(max: InputValidationLimits.petMicrochipId)
      .check(
        _maxLengthCheck('microchip_id', InputValidationLimits.petMicrochipId),
      )
      .nullable()();
  TextColumn get vetName => text()
      .withLength(max: InputValidationLimits.petVetName)
      .check(_maxLengthCheck('vet_name', InputValidationLimits.petVetName))
      .nullable()();
  TextColumn get vetPhone => text()
      .withLength(max: InputValidationLimits.petVetPhone)
      .check(_maxLengthCheck('vet_phone', InputValidationLimits.petVetPhone))
      .nullable()();
  TextColumn get feedingNotes => text()
      .withLength(max: InputValidationLimits.petNotes)
      .check(_maxLengthCheck('feeding_notes', InputValidationLimits.petNotes))
      .nullable()();
  TextColumn get medicalNotes => text()
      .withLength(max: InputValidationLimits.petNotes)
      .check(_maxLengthCheck('medical_notes', InputValidationLimits.petNotes))
      .nullable()();

  @override
  Set<Column<Object>> get primaryKey => {assetId};
}

@DataClassName('PlantDetailRow')
class PlantDetailsTable extends Table {
  @override
  String get tableName => 'plant_details';

  TextColumn get assetId =>
      text().references(Assets, #id, onDelete: KeyAction.cascade)();
  TextColumn get species => text()
      .withLength(max: InputValidationLimits.plantSpecies)
      .check(_maxLengthCheck('species', InputValidationLimits.plantSpecies))
      .nullable()();
  TextColumn get sunlight => text()
      .withLength(max: InputValidationLimits.plantSunlight)
      .check(_maxLengthCheck('sunlight', InputValidationLimits.plantSunlight))
      .nullable()();
  IntColumn get wateringIntervalDays => integer()
      .check(
        const CustomExpression<bool>(
          'watering_interval_days IS NULL OR watering_interval_days > 0',
        ),
      )
      .nullable()();
  TextColumn get potSize => text()
      .withLength(max: InputValidationLimits.plantPotSize)
      .check(_maxLengthCheck('pot_size', InputValidationLimits.plantPotSize))
      .nullable()();
  DateTimeColumn get lastRepottedAt => dateTime().nullable()();
  TextColumn get toxicityNotes => text()
      .withLength(max: InputValidationLimits.plantToxicityNotes)
      .check(
        _maxLengthCheck(
          'toxicity_notes',
          InputValidationLimits.plantToxicityNotes,
        ),
      )
      .nullable()();

  @override
  Set<Column<Object>> get primaryKey => {assetId};
}

@DataClassName('SafetyDetailRow')
class SafetyDetailsTable extends Table {
  @override
  String get tableName => 'safety_details';

  TextColumn get assetId =>
      text().references(Assets, #id, onDelete: KeyAction.cascade)();
  TextColumn get safetyType => text()
      .withLength(max: InputValidationLimits.safetyType)
      .check(_maxLengthCheck('safety_type', InputValidationLimits.safetyType))
      .nullable()();
  DateTimeColumn get installedAt => dateTime().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  TextColumn get batteryType => text()
      .withLength(max: InputValidationLimits.safetyBatteryType)
      .check(
        _maxLengthCheck(
          'battery_type',
          InputValidationLimits.safetyBatteryType,
        ),
      )
      .nullable()();
  IntColumn get testIntervalDays => integer()
      .check(
        const CustomExpression<bool>(
          'test_interval_days IS NULL OR test_interval_days > 0',
        ),
      )
      .nullable()();

  @override
  Set<Column<Object>> get primaryKey => {assetId};
}

@DataClassName('TagRow')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()
      .withLength(min: 1, max: InputValidationLimits.tagName)
      .check(
        _boundedLengthCheck(
          'name',
          minimum: 1,
          maximum: InputValidationLimits.tagName,
        ),
      )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AssetTagRow')
class AssetTags extends Table {
  TextColumn get assetId =>
      text().references(Assets, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {assetId, tagId};
}

@DataClassName('AssetPhotoRow')
class AssetPhotos extends Table {
  TextColumn get id => text()();
  TextColumn get assetId =>
      text().references(Assets, #id, onDelete: KeyAction.cascade)();
  TextColumn get relativePath => text()();
  TextColumn get cloudObjectPath => text().nullable()();
  TextColumn get caption => text().withLength(max: 500).nullable()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MaintenancePlanRow')
class MaintenancePlans extends Table {
  TextColumn get id => text()();
  TextColumn get currentOccurrenceId =>
      text().clientDefault(() => const Uuid().v7())();
  TextColumn get assetId =>
      text().references(Assets, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()
      .withLength(min: 1, max: InputValidationLimits.maintenanceTitle)
      .check(
        _boundedLengthCheck(
          'title',
          minimum: 1,
          maximum: InputValidationLimits.maintenanceTitle,
        ),
      )();
  TextColumn get instructions => text()
      .withLength(max: InputValidationLimits.maintenanceInstructions)
      .check(
        _maxLengthCheck(
          'instructions',
          InputValidationLimits.maintenanceInstructions,
        ),
      )
      .nullable()();
  IntColumn get recurrenceInterval => integer().check(
    const CustomExpression<bool>('recurrence_interval > 0'),
  )();
  TextColumn get recurrenceUnit => text().check(
    const CustomExpression<bool>(
      "recurrence_unit IN ('hours', 'days', 'weeks', 'months', 'years')",
    ),
  )();
  TextColumn get priority => text().check(
    const CustomExpression<bool>(
      "priority IN ('low', 'medium', 'high', 'critical')",
    ),
  )();
  DateTimeColumn get nextDueDate => dateTime()();
  IntColumn get reminderDaysBefore => integer()
      .check(const CustomExpression<bool>('reminder_days_before >= 0'))
      .withDefault(const Constant(0))();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MaintenancePlanMetadataRow')
class MaintenancePlanMetadata extends Table {
  TextColumn get planId =>
      text().references(MaintenancePlans, #id, onDelete: KeyAction.cascade)();
  TextColumn get taskType => text()
      .withLength(max: InputValidationLimits.maintenanceTaskType)
      .check(
        _maxLengthCheck('task_type', InputValidationLimits.maintenanceTaskType),
      )
      .nullable()();
  TextColumn get locationLabel => text()
      .withLength(max: InputValidationLimits.maintenanceLocation)
      .check(
        _maxLengthCheck(
          'location_label',
          InputValidationLimits.maintenanceLocation,
        ),
      )
      .nullable()();
  IntColumn get estimatedDurationMinutes => integer()
      .check(
        const CustomExpression<bool>(
          'estimated_duration_minutes IS NULL OR '
          'estimated_duration_minutes >= 0',
        ),
      )
      .nullable()();
  TextColumn get requiredMaterialsJson => text()
      .withLength(max: InputValidationLimits.maintenanceRequiredMaterialsJson)
      .check(
        _maxLengthCheck(
          'required_materials_json',
          InputValidationLimits.maintenanceRequiredMaterialsJson,
        ),
      )
      .withDefault(const Constant('[]'))();
  TextColumn get reminderRecommendation => text()
      .withLength(max: InputValidationLimits.maintenanceReminderRecommendation)
      .check(
        _maxLengthCheck(
          'reminder_recommendation',
          InputValidationLimits.maintenanceReminderRecommendation,
        ),
      )
      .nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {planId};
}

@DataClassName('MaintenanceRecordRow')
class MaintenanceRecords extends Table {
  TextColumn get id => text()();
  TextColumn get planId =>
      text().references(MaintenancePlans, #id, onDelete: KeyAction.cascade)();
  TextColumn get occurrenceId =>
      text().clientDefault(() => const Uuid().v7())();
  DateTimeColumn get dueDate => dateTime()();
  DateTimeColumn get completedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get acceptedAt => dateTime().nullable()();
  TextColumn get timeZoneId => text().clientDefault(() => 'UTC')();
  TextColumn get notes => text().withLength(max: 4000).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {planId, occurrenceId},
  ];
}

@DataClassName('InboxNotificationRow')
class InboxNotifications extends Table {
  @override
  String get tableName => 'notification_inbox';

  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 500)();
  TextColumn get body => text().withLength(max: 20000)();
  TextColumn get kind => text().withLength(min: 1, max: 80)();
  TextColumn get route => text().withLength(max: 1000).nullable()();
  TextColumn get planId => text().nullable().references(
    MaintenancePlans,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get messageCode => text()
      .withLength(min: 1, max: 120)
      .withDefault(const Constant('generic'))
      .check(
        const CustomExpression<bool>(
          "message_code IN ('generic', 'weather_alert', 'task_overdue', "
          "'task_due_today', 'daily_digest', 'task_skipped', "
          "'task_postponed')",
        ),
      )();
  TextColumn get messageArgs => text().withDefault(const Constant('{}'))();
  TextColumn get dedupeKey => text().withLength(max: 128).nullable()();
  DateTimeColumn get readAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DataClassName('StreakRow')
class Streaks extends Table {
  TextColumn get id => text()();
  IntColumn get currentStreak => integer().withDefault(const Constant(0))();
  IntColumn get bestStreak => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastCompletedDate => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SyncOutbox extends Table {
  @override
  String get tableName => 'offline_mutation_queue';

  IntColumn get localSequence => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get recordKey => text()();
  TextColumn get operation => text().check(
    const CustomExpression<bool>(
      // 'upsert'/'delete' are written by the sync triggers; 'execute' is the
      // maintenance-completion journal that must survive response loss.
      "operation IN ('upsert', 'delete', 'execute')",
    ),
  )();
  TextColumn get payloadJson => text().nullable()();
  TextColumn get userId => text().nullable()();
  DateTimeColumn get changedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().nullable()();
  TextColumn get state => text()
      .withDefault(const Constant('pending'))
      .check(
        const CustomExpression<bool>(
          "state IN ('pending', 'inFlight', 'conflictRecovery', "
          "'failedVisible', 'conflict')",
        ),
      )();
  IntColumn get attempts => integer()
      .withDefault(const Constant(0))
      .check(const CustomExpression<bool>('attempts >= -1'))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  TextColumn get lastError => text().nullable()();
  IntColumn get generation => integer()
      .withDefault(const Constant(1))
      .check(const CustomExpression<bool>('generation >= 1'))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {entity, recordKey},
  ];
}

class ReminderScheduleSnapshots extends Table {
  @override
  String get tableName => 'reminder_schedule_snapshot';

  TextColumn get identity => text()();
  IntColumn get notificationId => integer().unique()();
  TextColumn get planRevision => text()();
  DateTimeColumn get scheduledAt => dateTime()();
  TextColumn get timezone => text()();
  TextColumn get localComponents => text()();
  TextColumn get scheduleMode => text()();
  TextColumn get contentVersion => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {identity};
}

@DataClassName('NotificationReconciliationRequestRow')
class NotificationReconciliationRequests extends Table {
  @override
  String get tableName => 'notification_reconciliation_requests';

  TextColumn get scopeKey => text()();
  TextColumn get planId => text().nullable()();
  TextColumn get reason => text().check(
    const CustomExpression<bool>('length(reason) BETWEEN 1 AND 80'),
  )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get attempts => integer()
      .withDefault(const Constant(0))
      .check(const CustomExpression<bool>('attempts >= -1'))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  TextColumn get lastErrorMessage => text().nullable()();
  BoolColumn get requiresFullRebuild =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {scopeKey};
}

class SyncCursors extends Table {
  @override
  String get tableName => 'sync_cursors';

  TextColumn get entity => text()();
  IntColumn get lastSyncSeq => integer()
      .withDefault(const Constant(0))
      .check(const CustomExpression<bool>('last_sync_seq >= 0'))();
  TextColumn get lastRecordKey => text().nullable()();
  IntColumn get feedGeneration => integer()
      .withDefault(const Constant(1))
      .check(const CustomExpression<bool>('feed_generation >= 1'))();
  IntColumn get highWaterSeq => integer()
      .withDefault(const Constant(0))
      .check(const CustomExpression<bool>('high_water_seq >= 0'))();

  @override
  Set<Column<Object>> get primaryKey => {entity};
}

@DataClassName('SyncConflictRow')
class SyncConflicts extends Table {
  @override
  String get tableName => 'sync_conflicts';

  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get entity => text()();
  TextColumn get recordKey => text()();
  TextColumn get operationId => text().nullable()();
  TextColumn get localPayloadJson => text().nullable()();
  TextColumn get remotePayloadJson => text().nullable()();
  IntColumn get remoteRevision => integer().nullable()();
  TextColumn get resolutionStatus => text()
      .withDefault(const Constant('unresolved'))
      .check(
        const CustomExpression<bool>(
          "resolution_status IN ('unresolved', 'resolved_keep_local', "
          "'resolved_keep_remote', 'resolved_server_acknowledged')",
        ),
      )();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SyncShadows extends Table {
  @override
  String get tableName => 'sync_shadows';

  TextColumn get entity => text()();
  TextColumn get recordKey => text()();
  IntColumn get remoteRevision => integer()();
  DateTimeColumn get remoteModifiedAt => dateTime().nullable()();
  TextColumn get payloadHash => text().nullable()();
  DateTimeColumn get lastSyncedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {entity, recordKey};
}

/// Durable bookkeeping for incremental-feed records that were skipped because
/// a local outbox intent masks them. A row here promises that the masked
/// remote change is refetched once the masking intent resolves; the feed
/// cursor may advance past such a record only while this promise exists.
@DataClassName('SyncSkippedFeedEntryRow')
class SyncSkippedFeedEntries extends Table {
  @override
  String get tableName => 'sync_skipped_feed_entries';

  TextColumn get entity => text()();
  TextColumn get recordKey => text()();
  TextColumn get reason => text().check(
    const CustomExpression<bool>(
      "reason IN ('active_intent', 'conflict_or_terminal')",
    ),
  )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {entity, recordKey};
}

class SyncRuntime extends Table {
  @override
  String get tableName => 'sync_runtime';

  IntColumn get id => integer().check(const CustomExpression<bool>('id = 1'))();
  BoolColumn get suppressOutbox =>
      boolean().withDefault(const Constant(false))();
  TextColumn get leaseOwner => text().nullable()();
  DateTimeColumn get leaseExpiresAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    // A lease is either fully present or fully absent.
    'CHECK ((lease_owner IS NULL) = (lease_expires_at IS NULL))',
  ];
}

class SyncMediaCleanup extends Table {
  @override
  String get tableName => 'sync_media_cleanup';

  TextColumn get objectPath => text()();
  TextColumn get userId => text()();
  TextColumn get entity => text()();
  TextColumn get recordKey => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get attempts => integer()
      .withDefault(const Constant(0))
      .check(const CustomExpression<bool>('attempts >= -1'))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {objectPath};
}

class LocalMediaCleanup extends Table {
  @override
  String get tableName => 'local_media_cleanup';

  TextColumn get relativePath => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get attempts => integer()
      .withDefault(const Constant(0))
      .check(const CustomExpression<bool>('attempts >= -1'))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastErrorCode => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {relativePath};
}

class SyncAccount extends Table {
  @override
  String get tableName => 'sync_account';

  IntColumn get id => integer().check(const CustomExpression<bool>('id = 1'))();
  TextColumn get deviceId => text()();
  TextColumn get boundUserId => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();
  TextColumn get migrationState => text()
      .withDefault(const Constant('localOnly'))
      .check(
        const CustomExpression<bool>(
          "migration_state IN ('localOnly', 'binding', 'active', 'restorePaused', 'migrating', 'migrated', 'failed', 'blocked')",
        ),
      )();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  DateTimeColumn get lastSyncAttemptAt => dateTime().nullable()();
  DateTimeColumn get lastSyncFailureAt => dateTime().nullable()();
  DateTimeColumn get lastIntegrityCheckAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  TextColumn get blockedReason => text().nullable()();
  BoolColumn get restorePending =>
      boolean().withDefault(const Constant(false))();
  TextColumn get backgroundResult => text().nullable()();
  TextColumn get hydrationRunId => text().nullable()();
  TextColumn get hydrationState => text().nullable()();
  TextColumn get hydrationStage => text().nullable()();
  IntColumn get hydrationCompletedUnits => integer()
      .withDefault(const Constant(0))
      .check(const CustomExpression<bool>('hydration_completed_units >= 0'))();
  IntColumn get hydrationTotalUnits => integer()
      .withDefault(const Constant(0))
      .check(const CustomExpression<bool>('hydration_total_units >= 0'))();
  DateTimeColumn get hydrationStartedAt => dateTime().nullable()();
  DateTimeColumn get hydrationUpdatedAt => dateTime().nullable()();
  TextColumn get hydrationError => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    // Hydration progress can never exceed the announced total once a total
    // is published.
    'CHECK (hydration_total_units = 0 '
        'OR hydration_completed_units <= hydration_total_units)',
  ];
}

@DriftDatabase(
  tables: [
    Areas,
    Rooms,
    Assets,
    DeviceDetailsTable,
    PetDetailsTable,
    PlantDetailsTable,
    SafetyDetailsTable,
    Tags,
    AssetTags,
    AssetPhotos,
    MaintenancePlans,
    MaintenancePlanMetadata,
    MaintenanceRecords,
    InboxNotifications,
    Settings,
    Streaks,
    SyncOutbox,
    ReminderScheduleSnapshots,
    SyncCursors,
    SyncShadows,
    SyncRuntime,
    SyncMediaCleanup,
    LocalMediaCleanup,
    SyncAccount,
    NotificationReconciliationRequests,
    SyncConflicts,
    SyncSkippedFeedEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor})
    : super(executor ?? _openDatabaseConnection());

  static const databaseName = 'owntend';
  static const databaseFileName = '$databaseName.sqlite';
  static const currentSchemaVersion = 1;
  static const _sqliteBusyTimeoutMs = 8000;
  static const _startupRecoveryAttempts = 5;
  static const _searchIndexSourceTables = <String>[
    'areas',
    'rooms',
    'assets',
    'device_details',
    'pet_details',
    'plant_details',
    'safety_details',
    'tags',
    'asset_tags',
    'asset_photos',
    'maintenance_plans',
  ];

  static QueryExecutor _openDatabaseConnection() {
    return driftDatabase(
      name: databaseName,
      native: const DriftNativeOptions(
        shareAcrossIsolates: true,
        setup: configureNativeSqlite,
      ),
    );
  }

  static void configureNativeSqlite(CommonDatabase db) {
    db.execute('PRAGMA busy_timeout = $_sqliteBusyTimeoutMs');
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA synchronous = NORMAL');
    db.execute('PRAGMA foreign_keys = ON');
  }

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  StreamQueryUpdateRules get streamUpdateRules => StreamQueryUpdateRules([
    for (final table in [
      'areas',
      'rooms',
      'assets',
      'device_details',
      'pet_details',
      'plant_details',
      'safety_details',
      'tags',
      'asset_tags',
      'asset_photos',
      'maintenance_plans',
      'maintenance_plan_metadata',
      'maintenance_records',
      'notification_inbox',
      'settings',
      'streaks',
    ])
      WritePropagation(
        on: TableUpdateQuery.onTableName(table),
        result: const [TableUpdate('offline_mutation_queue')],
      ),
  ]);

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes();
      await _createSearchIndex();
      await _createSearchIndexGenerationInfrastructure();
      await _createSyncTriggers();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA busy_timeout = $_sqliteBusyTimeoutMs');
      await customStatement('PRAGMA foreign_keys = ON');
      // Runtime verification only: a database that does not match the
      // canonical v1 baseline is rejected instead of being silently repaired.
      await _verifyBaselineObjects();
      await _seedSyncRuntime();
      await _recoverExpiredSyncRuntimeLease();
      await _seedDefaults();
    },
  );

  static const _baselineTables = <String>[
    'areas',
    'rooms',
    'assets',
    'device_details',
    'pet_details',
    'plant_details',
    'safety_details',
    'tags',
    'asset_tags',
    'asset_photos',
    'maintenance_plans',
    'maintenance_plan_metadata',
    'maintenance_records',
    'notification_inbox',
    'settings',
    'streaks',
    'offline_mutation_queue',
    'reminder_schedule_snapshot',
    'notification_reconciliation_requests',
    'sync_cursors',
    'sync_shadows',
    'sync_runtime',
    'sync_media_cleanup',
    'local_media_cleanup',
    'sync_account',
    'sync_conflicts',
    'sync_skipped_feed_entries',
    'search_index_state',
  ];

  /// Verifies the static schema baseline exists. Missing objects indicate a
  /// pre-baseline local database; because the project is pre-launch with no
  /// production databases, such files are rejected with an explicit error
  /// rather than silently patched at every open.
  Future<void> _verifyBaselineObjects() async {
    final rows = await customSelect(
      "SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
    ).get();
    final present = rows
        .map((row) => '${row.read<String>('type')}:${row.read<String>('name')}')
        .toSet();
    final missing = <String>[];
    for (final table in _baselineTables) {
      if (!present.contains('table:$table')) missing.add('table $table');
    }
    for (final statement in _indexStatements) {
      final match = RegExp(r'INDEX (?:UNIQUE )?IF NOT EXISTS (\w+)')
          .firstMatch(statement);
      final name = match?.group(1);
      if (name != null && !present.contains('index:$name')) {
        missing.add('index $name');
      }
    }
    if (!present.contains('table:search_index')) {
      missing.add('virtual table search_index');
    }
    final triggerRows = rows
        .where((row) => row.read<String>('type') == 'trigger')
        .length;
    const expectedTriggers =
        15 * 3 + // synchronized entity tables
        3 + // profile settings
        3 + // user settings
        11 * 3; // search invalidation triggers
    if (triggerRows < expectedTriggers) {
      missing.add(
        'triggers ($triggerRows present, $expectedTriggers expected)',
      );
    }
    if (missing.isNotEmpty) {
      throw StateError(
        'Local database does not match the canonical v1 schema baseline '
        '(missing: ${missing.join(', ')}). Pre-launch databases have no '
        'upgrade path; clear app storage to recreate the database.',
      );
    }
  }

  Future<void> _seedSyncRuntime() async {
    await into(syncRuntime).insert(
      SyncRuntimeCompanion.insert(id: const Value(1)),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<void> _recoverExpiredSyncRuntimeLease() {
    return _withStartupDatabaseRetry(() async {
      final now = DateTime.now();
      await customUpdate(
        '''
UPDATE sync_runtime
SET suppress_outbox = 0,
    lease_owner = NULL,
    lease_expires_at = NULL
WHERE id = 1
  AND (
    lease_owner IS NULL
    OR lease_expires_at IS NULL
    OR lease_expires_at <= ?
  )
''',
        variables: [Variable<DateTime>(now)],
        updates: {syncRuntime},
        updateKind: UpdateKind.update,
      );
    });
  }

  Future<T> _withStartupDatabaseRetry<T>(Future<T> Function() action) async {
    Object? lastError;
    for (var attempt = 0; attempt < _startupRecoveryAttempts; attempt++) {
      try {
        return await action();
      } on Object catch (error) {
        lastError = error;
        if (!_isSqliteBusy(error) || attempt == _startupRecoveryAttempts - 1) {
          rethrow;
        }
        await Future<void>.delayed(
          Duration(milliseconds: 80 * (attempt + 1) * (attempt + 1)),
        );
      }
    }
    throw StateError('Startup database recovery failed: $lastError');
  }

  bool _isSqliteBusy(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('database is locked') ||
        message.contains('database table is locked') ||
        message.contains('sqlite_busy') ||
        message.contains('sqlite_locked');
  }

  static const _assetPhotoDeletePayloadExpression = '''
CASE
  WHEN OLD.cloud_object_path IS NOT NULL
  THEN json_object('cleanup_object_path', OLD.cloud_object_path)
  ELSE NULL
END
''';

  Future<void> _createSyncTriggers() async {
    const specs = <(String, String, String)>[
      ('areas', 'area', 'id'),
      ('rooms', 'room', 'id'),
      ('assets', 'asset', 'id'),
      ('device_details', 'device_detail', 'asset_id'),
      ('pet_details', 'pet_detail', 'asset_id'),
      ('plant_details', 'plant_detail', 'asset_id'),
      ('safety_details', 'safety_detail', 'asset_id'),
      ('tags', 'tag', 'id'),
      ('asset_tags', 'asset_tag', "asset_id || '|' || tag_id"),
      ('asset_photos', 'asset_photo', 'id'),
      ('maintenance_plans', 'maintenance_plan', 'id'),
      ('maintenance_plan_metadata', 'maintenance_plan_metadata', 'plan_id'),
      ('maintenance_records', 'maintenance_record', 'id'),
      ('notification_inbox', 'notification_inbox', 'id'),
      ('streaks', 'streak', 'id'),
    ];
    for (final (table, entity, keyExpression) in specs) {
      await _createSyncTrigger(
        table: table,
        entity: entity,
        keyExpression: keyExpression,
        event: 'INSERT',
        rowPrefix: 'NEW',
        operation: 'upsert',
      );
      await _createSyncTrigger(
        table: table,
        entity: entity,
        keyExpression: keyExpression,
        event: 'UPDATE',
        rowPrefix: 'NEW',
        operation: 'upsert',
      );
      await _createSyncTrigger(
        table: table,
        entity: entity,
        keyExpression: keyExpression,
        event: 'DELETE',
        rowPrefix: 'OLD',
        operation: 'delete',
        payloadExpression: table == 'asset_photos'
            ? _assetPhotoDeletePayloadExpression
            : null,
      );
    }

    await _createSyncTrigger(
      table: 'settings',
      entity: 'profile',
      keyExpression: "'profile'",
      event: 'INSERT',
      rowPrefix: 'NEW',
      operation: 'upsert',
      extraWhen: "NEW.key = 'profile'",
    );
    await _createSyncTrigger(
      table: 'settings',
      entity: 'profile',
      keyExpression: "'profile'",
      event: 'UPDATE',
      rowPrefix: 'NEW',
      operation: 'upsert',
      extraWhen: "NEW.key = 'profile'",
    );
    await _createSyncTrigger(
      table: 'settings',
      entity: 'profile',
      keyExpression: "'profile'",
      event: 'DELETE',
      rowPrefix: 'OLD',
      operation: 'delete',
      extraWhen: "OLD.key = 'profile'",
    );

    const userSettingKeys =
        "'theme', 'app_language', 'app_language_explicit', 'theme_time_of_day_enabled', "
        "'notification_preferences', 'onboarding_completed', "
        "'permission_education_seen', "
        "'home_location'";
    for (final (event, rowPrefix, operation) in [
      ('INSERT', 'NEW', 'upsert'),
      ('UPDATE', 'NEW', 'upsert'),
      ('DELETE', 'OLD', 'delete'),
    ]) {
      await _createSyncTrigger(
        table: 'settings',
        entity: 'user_setting',
        keyExpression: 'key',
        event: event,
        rowPrefix: rowPrefix,
        operation: operation,
        extraWhen: "$rowPrefix.key IN ($userSettingKeys)",
      );
    }
  }

  Future<void> _createSyncTrigger({
    required String table,
    required String entity,
    required String keyExpression,
    required String event,
    required String rowPrefix,
    required String operation,
    String? extraWhen,
    String? payloadExpression,
  }) async {
    final normalizedEvent = event.toLowerCase();
    final triggerName = 'sync_${table}_${entity}_$normalizedEvent';
    final key = keyExpression.contains('||') || keyExpression.startsWith("'")
        ? keyExpression
        : '$rowPrefix.$keyExpression';
    final compositeKey = keyExpression.contains('||')
        ? keyExpression
              .split(RegExp(r'\s+'))
              .map((part) {
                if (part == 'asset_id' ||
                    part == 'tag_id' ||
                    part == 'session_id' ||
                    part == 'plan_id') {
                  return '$rowPrefix.$part';
                }
                return part;
              })
              .join(' ')
        : key;
    final conditions = [
      'COALESCE((SELECT suppress_outbox FROM sync_runtime WHERE id = 1), 0) = 0',
      ?extraWhen,
    ].join(' AND ');
    final payload = payloadExpression ?? 'NULL';
    await customStatement('''
CREATE TRIGGER IF NOT EXISTS $triggerName
AFTER $event ON $table
WHEN $conditions
BEGIN
  INSERT INTO offline_mutation_queue(
    entity,
    record_key,
    operation,
    payload_json,
    changed_at,
    attempts,
    next_attempt_at,
    last_error,
    generation
  )
  VALUES (
    '$entity',
    $compositeKey,
    '$operation',
    $payload,
    CAST(strftime('%s', 'now') AS INTEGER),
    0,
    NULL,
    NULL,
    1
  )
  ON CONFLICT(entity, record_key) DO UPDATE SET
    operation = excluded.operation,
    payload_json = excluded.payload_json,
    changed_at = excluded.changed_at,
    attempts = 0,
    next_attempt_at = NULL,
    last_error = NULL,
    state = CASE
      WHEN offline_mutation_queue.state = 'conflict' THEN 'pending'
      ELSE offline_mutation_queue.state
    END,
    generation = offline_mutation_queue.generation + 1;
END
''');
  }

  static const _indexStatements = <String>[
    'CREATE INDEX IF NOT EXISTS idx_areas_sort ON areas(sort_order, name)',
    'CREATE INDEX IF NOT EXISTS idx_areas_archived ON areas(archived_at)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_areas_active_name_nocase '
        'ON areas(name COLLATE NOCASE) WHERE archived_at IS NULL',
    'CREATE INDEX IF NOT EXISTS idx_rooms_area ON rooms(area_id)',
    'CREATE INDEX IF NOT EXISTS idx_rooms_name ON rooms(name)',
    'CREATE INDEX IF NOT EXISTS idx_rooms_archived ON rooms(archived_at)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_rooms_active_name_nocase '
        'ON rooms(area_id, name COLLATE NOCASE) WHERE archived_at IS NULL',
    'CREATE INDEX IF NOT EXISTS idx_assets_room ON assets(room_id)',
    'CREATE INDEX IF NOT EXISTS idx_assets_type ON assets(asset_type)',
    'CREATE INDEX IF NOT EXISTS idx_assets_archived ON assets(archived_at)',
    'CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_name_nocase '
        'ON tags(name COLLATE NOCASE)',
    'CREATE INDEX IF NOT EXISTS idx_asset_tags_asset ON asset_tags(asset_id)',
    'CREATE INDEX IF NOT EXISTS idx_asset_tags_tag ON asset_tags(tag_id)',
    'CREATE INDEX IF NOT EXISTS idx_asset_photos_asset ON asset_photos(asset_id)',
    'CREATE INDEX IF NOT EXISTS idx_asset_photos_primary ON asset_photos(asset_id, is_primary)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_asset_photos_single_primary '
        'ON asset_photos(asset_id) WHERE is_primary = 1',
    'CREATE INDEX IF NOT EXISTS idx_plans_asset ON maintenance_plans(asset_id)',
    'CREATE INDEX IF NOT EXISTS idx_plans_enabled_due '
        'ON maintenance_plans(is_enabled, next_due_date)',
    'CREATE INDEX IF NOT EXISTS idx_plans_due ON maintenance_plans(next_due_date)',
    'CREATE INDEX IF NOT EXISTS idx_plan_metadata_sort '
        'ON maintenance_plan_metadata(sort_order)',
    'CREATE INDEX IF NOT EXISTS idx_records_plan ON maintenance_records(plan_id)',
    'CREATE INDEX IF NOT EXISTS idx_records_completed ON maintenance_records(completed_at)',
    'CREATE INDEX IF NOT EXISTS idx_inbox_unread ON notification_inbox(read_at, created_at)',
    'CREATE INDEX IF NOT EXISTS idx_inbox_plan ON notification_inbox(plan_id)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_inbox_dedupe '
        "ON notification_inbox(dedupe_key) WHERE dedupe_key <> ''",
    'CREATE INDEX IF NOT EXISTS idx_settings_key ON settings(key)',
    'CREATE INDEX IF NOT EXISTS idx_streaks_updated ON streaks(updated_at)',
    // Retry-ready operational indexes: dequeue and cleanup scans are driven
    // by state plus scheduled retry time, not by insertion order.
    'CREATE INDEX IF NOT EXISTS idx_outbox_retry '
        'ON offline_mutation_queue(state, next_attempt_at, changed_at)',
    'CREATE INDEX IF NOT EXISTS idx_sync_media_cleanup_retry '
        'ON sync_media_cleanup(next_attempt_at, attempts)',
    'CREATE INDEX IF NOT EXISTS idx_local_media_cleanup_retry '
        'ON local_media_cleanup(next_attempt_at, attempts)',
    'CREATE INDEX IF NOT EXISTS idx_notification_reconciliation_retry '
        'ON notification_reconciliation_requests(next_attempt_at, attempts)',
    'CREATE INDEX IF NOT EXISTS idx_sync_conflicts_account ON sync_conflicts(account_id)',
    'CREATE INDEX IF NOT EXISTS idx_sync_conflicts_entity_record ON sync_conflicts(entity, record_key)',
    'CREATE INDEX IF NOT EXISTS idx_sync_conflicts_status ON sync_conflicts(resolution_status)',
  ];

  Future<void> _createIndexes() async {
    for (final statement in _indexStatements) {
      await customStatement(statement);
    }
  }

  Future<void> _createSearchIndexGenerationInfrastructure() async {
    await customStatement('''
CREATE TABLE IF NOT EXISTS search_index_state (
  id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
  source_generation INTEGER NOT NULL CHECK (source_generation >= 0),
  indexed_generation INTEGER NOT NULL CHECK (indexed_generation >= 0)
)
''');
    await customStatement('''
INSERT OR IGNORE INTO search_index_state(
  id,
  source_generation,
  indexed_generation
) VALUES (1, 1, 0)
''');

    for (final table in _searchIndexSourceTables) {
      for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
        final normalizedEvent = event.toLowerCase();
        await customStatement('''
CREATE TRIGGER IF NOT EXISTS search_${table}_$normalizedEvent
AFTER $event ON $table
BEGIN
  UPDATE search_index_state
  SET source_generation = source_generation + 1
  WHERE id = 1;
END
''');
      }
    }
  }

  Future<void> _createSearchIndex() async {
    await customStatement(
      'CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5('
      'entity_type UNINDEXED, entity_id UNINDEXED, title, '
      'display_body, search_terms)',
    );
  }

  Future<void> _seedDefaults() async {
    final now = DateTime.now();
    await batch((batch) {
      batch.insertAll(settings, [
        SettingsCompanion.insert(
          key: 'theme',
          value: ThemePreference.system.name,
          updatedAt: Value(now),
        ),
        SettingsCompanion.insert(
          key: 'app_language',
          value: AppLanguage.en.name,
          updatedAt: Value(now),
        ),
        SettingsCompanion.insert(
          key: 'app_language_explicit',
          value: 'false',
          updatedAt: Value(now),
        ),
        SettingsCompanion.insert(
          key: 'theme_time_of_day_enabled',
          value: 'false',
          updatedAt: Value(now),
        ),
        SettingsCompanion.insert(
          key: 'notification_preferences',
          value: '{"enabled":true}',
          updatedAt: Value(now),
        ),
        SettingsCompanion.insert(
          key: 'onboarding_completed',
          value: 'false',
          updatedAt: Value(now),
        ),
        SettingsCompanion.insert(
          key: 'permission_education_seen',
          value: 'false',
          updatedAt: Value(now),
        ),
      ], mode: InsertMode.insertOrIgnore);
      batch.insertAll(streaks, [
        StreaksCompanion.insert(id: 'default', updatedAt: Value(now)),
      ], mode: InsertMode.insertOrIgnore);
    });
  }
}
