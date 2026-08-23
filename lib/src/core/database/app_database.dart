import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sqlite3/common.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';

part 'app_database.g.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

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
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get assetType => text()
      .check(
        const CustomExpression<bool>(
          "asset_type IN ('device', 'pet', 'plant', 'safety', 'general')",
        ),
      )
      .withDefault(const Constant('general'))();
  TextColumn get roomId =>
      text().references(Rooms, #id, onDelete: KeyAction.cascade)();
  TextColumn get placement => text().withLength(max: 300).nullable()();
  TextColumn get notes => text().withLength(max: 10000).nullable()();
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
  TextColumn get brand => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get serialNumber => text().nullable()();
  TextColumn get powerSource => text().nullable()();
  DateTimeColumn get warrantyUntil => dateTime().nullable()();
  TextColumn get manualUrl => text().nullable()();
  TextColumn get consumable => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {assetId};
}

@DataClassName('PetDetailRow')
class PetDetailsTable extends Table {
  @override
  String get tableName => 'pet_details';

  TextColumn get assetId =>
      text().references(Assets, #id, onDelete: KeyAction.cascade)();
  TextColumn get species => text().nullable()();
  TextColumn get breed => text().nullable()();
  DateTimeColumn get birthDate => dateTime().nullable()();
  TextColumn get microchipId => text().nullable()();
  TextColumn get vetName => text().nullable()();
  TextColumn get vetPhone => text().nullable()();
  TextColumn get feedingNotes => text().nullable()();
  TextColumn get medicalNotes => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {assetId};
}

@DataClassName('PlantDetailRow')
class PlantDetailsTable extends Table {
  @override
  String get tableName => 'plant_details';

  TextColumn get assetId =>
      text().references(Assets, #id, onDelete: KeyAction.cascade)();
  TextColumn get species => text().nullable()();
  TextColumn get sunlight => text().nullable()();
  IntColumn get wateringIntervalDays => integer().nullable()();
  TextColumn get potSize => text().nullable()();
  DateTimeColumn get lastRepottedAt => dateTime().nullable()();
  TextColumn get toxicityNotes => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {assetId};
}

@DataClassName('SafetyDetailRow')
class SafetyDetailsTable extends Table {
  @override
  String get tableName => 'safety_details';

  TextColumn get assetId =>
      text().references(Assets, #id, onDelete: KeyAction.cascade)();
  TextColumn get safetyType => text().nullable()();
  DateTimeColumn get installedAt => dateTime().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  TextColumn get batteryType => text().nullable()();
  IntColumn get testIntervalDays => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {assetId};
}

@DataClassName('TagRow')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
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
  TextColumn get caption => text().withLength(max: 500).nullable()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MaintenancePlanRow')
class MaintenancePlans extends Table {
  TextColumn get id => text()();
  TextColumn get assetId =>
      text().references(Assets, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get instructions => text().withLength(max: 4000).nullable()();
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
  TextColumn get taskType => text().nullable()();
  TextColumn get locationLabel => text().nullable()();
  IntColumn get estimatedDurationMinutes => integer().nullable()();
  TextColumn get requiredMaterialsJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get reminderRecommendation => text().nullable()();
  IntColumn get sortOrder => integer().nullable()();
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
  DateTimeColumn get dueDate => dateTime()();
  DateTimeColumn get completedAt =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get notes => text().withLength(max: 4000).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
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

  TextColumn get entity => text()();
  TextColumn get recordKey => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text().nullable()();
  TextColumn get userId => text().nullable()();
  DateTimeColumn get changedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().nullable()();
  TextColumn get state => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  TextColumn get lastError => text().nullable()();
  IntColumn get generation => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {entity, recordKey};
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
  TextColumn get reason => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
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
  IntColumn get lastSyncSeq => integer().withDefault(const Constant(0))();
  TextColumn get lastRecordKey => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {entity};
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

class SyncRuntime extends Table {
  @override
  String get tableName => 'sync_runtime';

  IntColumn get id => integer()();
  BoolColumn get suppressOutbox =>
      boolean().withDefault(const Constant(false))();
  TextColumn get leaseOwner => text().nullable()();
  DateTimeColumn get leaseExpiresAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SyncMediaCleanup extends Table {
  @override
  String get tableName => 'sync_media_cleanup';

  TextColumn get objectPath => text()();
  TextColumn get userId => text()();
  TextColumn get entity => text()();
  TextColumn get recordKey => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
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
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastErrorCode => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {relativePath};
}

class SyncAccount extends Table {
  @override
  String get tableName => 'sync_account';

  IntColumn get id => integer()();
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
  IntColumn get hydrationCompletedUnits =>
      integer().withDefault(const Constant(0))();
  IntColumn get hydrationTotalUnits =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get hydrationStartedAt => dateTime().nullable()();
  DateTimeColumn get hydrationUpdatedAt => dateTime().nullable()();
  TextColumn get hydrationError => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
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
      await _createSearchIndexGenerationInfrastructure();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA busy_timeout = $_sqliteBusyTimeoutMs');
      await customStatement('PRAGMA foreign_keys = ON');
      await _createIndexes();
      await _createSearchIndex();
      await _createSearchIndexGenerationInfrastructure();
      await _seedSyncRuntime();
      await _recoverExpiredSyncRuntimeLease();
      await _createSyncTriggers();
      await _seedDefaults();
    },
  );

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
  WHEN (SELECT bound_user_id FROM sync_account WHERE id = 1) IS NULL THEN NULL
  WHEN lower(OLD.relative_path) LIKE '%.jpeg' THEN json_object('cleanup_object_path', (SELECT bound_user_id FROM sync_account WHERE id = 1) || '/assets/' || OLD.asset_id || '/' || OLD.id || '.jpg')
  WHEN lower(OLD.relative_path) LIKE '%.jpg' THEN json_object('cleanup_object_path', (SELECT bound_user_id FROM sync_account WHERE id = 1) || '/assets/' || OLD.asset_id || '/' || OLD.id || '.jpg')
  WHEN lower(OLD.relative_path) LIKE '%.png' THEN json_object('cleanup_object_path', (SELECT bound_user_id FROM sync_account WHERE id = 1) || '/assets/' || OLD.asset_id || '/' || OLD.id || '.png')
  WHEN lower(OLD.relative_path) LIKE '%.webp' THEN json_object('cleanup_object_path', (SELECT bound_user_id FROM sync_account WHERE id = 1) || '/assets/' || OLD.asset_id || '/' || OLD.id || '.webp')
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
    const deviceSettingKeys = "'weather_cache'";
    for (final (entity, keys) in [
      ('user_setting', userSettingKeys),
      ('device_setting', deviceSettingKeys),
    ]) {
      for (final (event, rowPrefix, operation) in [
        ('INSERT', 'NEW', 'upsert'),
        ('UPDATE', 'NEW', 'upsert'),
        ('DELETE', 'OLD', 'delete'),
      ]) {
        await _createSyncTrigger(
          table: 'settings',
          entity: entity,
          keyExpression: 'key',
          event: event,
          rowPrefix: rowPrefix,
          operation: operation,
          extraWhen: "$rowPrefix.key IN ($keys)",
        );
      }
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
    generation = offline_mutation_queue.generation + 1;
END
''');
  }

  Future<void> _createIndexes() async {
    final statements = [
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
    ];
    for (final statement in statements) {
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
        final triggerName = 'search_${table}_$normalizedEvent';
        await customStatement('DROP TRIGGER IF EXISTS $triggerName');
        await customStatement('''
CREATE TRIGGER $triggerName
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
    final existing = await customSelect(
      "SELECT sql FROM sqlite_master "
      "WHERE type = 'table' AND name = 'search_index'",
    ).getSingleOrNull();
    if (existing != null) {
      final definition = existing.read<String>('sql');
      if (!definition.contains('display_body') ||
          !definition.contains('search_terms')) {
        // The FTS table is a derived cache and can be recreated when its
        // source-owned column contract changes.
        await customStatement('DROP TABLE search_index');
      }
    }
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
