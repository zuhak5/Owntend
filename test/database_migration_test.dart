import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';

void main() {
  group('AppDatabase schema v3 and lifecycle', () {
    late File dbFile;
    late AppDatabase db;

    setUp(() async {
      dbFile = File(
        '${Directory.systemTemp.path}/owntend_schema_v3_'
        '${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      db = AppDatabase(executor: NativeDatabase(dbFile));
      // Force database opening and beforeOpen execution.
      await db.customSelect('SELECT 1').get();
    });

    tearDown(() async {
      await db.close();
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
    });

    test('initializes with schema version 3', () async {
      expect(AppDatabase.currentSchemaVersion, 3);
      expect(db.schemaVersion, 3);

      final userVersionRow = await db
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(userVersionRow.read<int>('user_version'), 3);
    });

    test('creates canonical tables including search state', () async {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final tableNames = rows.map((r) => r.read<String>('name')).toSet();

      const expectedTables = {
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
        'notifications',
        'notification_inbox',
        'settings',
        'streaks',
        'offline_mutation_queue',
        'reminder_schedule_snapshot',
        'sync_cursors',
        'sync_shadows',
        'sync_runtime',
        'sync_media_cleanup',
        'sync_account',
        'notification_reconciliation_requests',
        'search_index_state',
      };

      for (final table in expectedTables) {
        expect(tableNames, contains(table), reason: 'Table $table must exist');
      }
    });

    test('creates the fts5 search_index virtual table', () async {
      final rows = await db
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE type = 'table' AND name = 'search_index'",
          )
          .get();
      expect(rows, hasLength(1));
      final definition = rows.first.read<String>('sql');
      expect(definition, contains('fts5'));
      expect(definition, contains('display_body'));
      expect(definition, contains('search_terms'));
    });

    test('creates search generation state and invalidation triggers', () async {
      final state = await db
          .customSelect(
            'SELECT source_generation, indexed_generation '
            'FROM search_index_state WHERE id = 1',
          )
          .getSingle();
      expect(state.read<int>('source_generation'), greaterThan(0));
      expect(
        state.read<int>('indexed_generation'),
        lessThan(state.read<int>('source_generation')),
      );

      final triggerRows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'search_%'",
          )
          .get();
      final triggerNames = triggerRows
          .map((row) => row.read<String>('name'))
          .toSet();
      expect(triggerNames, hasLength(33));
      expect(triggerNames, contains('search_areas_insert'));
      expect(triggerNames, contains('search_rooms_update'));
      expect(triggerNames, isNot(contains('search_categories_delete')));
      expect(triggerNames, contains('search_device_details_update'));
      expect(triggerNames, contains('search_pet_details_update'));
      expect(triggerNames, contains('search_plant_details_update'));
      expect(triggerNames, contains('search_safety_details_update'));
      expect(triggerNames, contains('search_tags_update'));
      expect(triggerNames, contains('search_asset_tags_insert'));
      expect(triggerNames, contains('search_asset_photos_update'));
      expect(triggerNames, contains('search_maintenance_plans_delete'));
    });

    test('creates required indexes and foreign keys', () async {
      final fkPragma = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(fkPragma.read<int>('foreign_keys'), 1);

      final indexRows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final indexNames = indexRows.map((r) => r.read<String>('name')).toSet();

      expect(indexNames, contains('idx_areas_sort'));
      expect(indexNames, contains('idx_rooms_area'));
      expect(indexNames, isNot(contains('idx_assets_category')));
      expect(indexNames, contains('idx_tags_name_nocase'));
      expect(indexNames, contains('idx_plans_enabled_due'));
      expect(indexNames, contains('idx_inbox_unread'));
      expect(indexNames, contains('idx_inbox_dedupe'));
    });

    test('creates offline mutation queue triggers on domain tables', () async {
      final triggerRows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'sync_%'",
          )
          .get();
      final triggerNames = triggerRows
          .map((r) => r.read<String>('name'))
          .toSet();

      expect(triggerNames, contains('sync_areas_area_insert'));
      expect(triggerNames, contains('sync_areas_area_update'));
      expect(triggerNames, contains('sync_areas_area_delete'));
      expect(triggerNames, contains('sync_rooms_room_insert'));
      expect(triggerNames, contains('sync_assets_asset_insert'));
      expect(
        triggerNames,
        contains('sync_maintenance_plans_maintenance_plan_insert'),
      );
      expect(
        triggerNames,
        contains('sync_notification_inbox_notification_inbox_insert'),
      );
      expect(triggerNames, contains('sync_settings_profile_insert'));
      expect(triggerNames, contains('sync_settings_user_setting_insert'));
      expect(triggerNames, contains('sync_settings_device_setting_insert'));
    });

    test('seeds settings and streak without Category tables', () async {
      final categoryTables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'categories'",
          )
          .get();
      expect(categoryTables, isEmpty);

      final assetColumns = await db
          .customSelect('PRAGMA table_info(assets)')
          .get();
      expect(
        assetColumns.map((row) => row.read<String>('name')),
        isNot(contains('category_id')),
      );

      final seededSettings = await db.select(db.settings).get();
      final settingKeys = seededSettings.map((s) => s.key).toSet();
      expect(
        settingKeys,
        containsAll([
          'theme',
          'app_language',
          'app_language_explicit',
          'theme_time_of_day_enabled',
          'notifications_enabled',
          'onboarding_completed',
          'permission_education_seen',
          'permission_education_seen_v2',
        ]),
      );

      final seededStreak = await db.select(db.streaks).get();
      expect(seededStreak.map((s) => s.id), contains('default'));

      final syncRuntimeRow = await db.select(db.syncRuntime).getSingle();
      expect(syncRuntimeRow.id, 1);
      expect(syncRuntimeRow.suppressOutbox, isFalse);
    });

    test('sync account initialization preserves columns', () async {
      final syncStore = LocalSyncStore(db);
      final account = await syncStore.account();
      expect(account.id, 1);
      expect(account.migrationState, 'localOnly');
      expect(account.uploadProhibited, isFalse);
      expect(account.quarantineReason, isNull);
      expect(account.legacyOwnerId, isNull);
    });
  });

  test('migrates schema v2 assets and removes Category state', () async {
    final dbFile = File(
      '${Directory.systemTemp.path}/owntend_v2_to_v3_'
      '${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    AppDatabase? db;
    try {
      db = AppDatabase(executor: NativeDatabase(dbFile));
      await db.customSelect('SELECT 1').get();
      await db.customStatement(
        'CREATE TABLE categories ('
        'id TEXT PRIMARY KEY, name TEXT NOT NULL, health_group TEXT NOT NULL, '
        'icon_name TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
      );
      await db.customStatement(
        "INSERT INTO categories(id, name, health_group, icon_name, created_at, updated_at) "
        "VALUES ('category_appliances', 'Appliances', 'appliances', 'kitchen', 0, 0)",
      );
      await db.customStatement(
        'ALTER TABLE assets ADD COLUMN category_id TEXT',
      );
      await db.customStatement(
        "INSERT INTO areas(id, name, kind) VALUES ('legacy-area', 'Home', 'indoor')",
      );
      await db.customStatement(
        "INSERT INTO rooms(id, area_id, name, room_type) "
        "VALUES ('legacy-room', 'legacy-area', 'Kitchen', 'kitchen')",
      );
      await db.customStatement(
        "INSERT INTO assets(id, name, asset_type, room_id, category_id) "
        "VALUES ('legacy-asset', 'Purifier', 'device', 'legacy-room', 'category_appliances')",
      );
      await db.customStatement('PRAGMA user_version = 2');
      await db.close();
      db = null;

      db = AppDatabase(executor: NativeDatabase(dbFile));
      await db.customSelect('SELECT 1').get();

      final userVersionRow = await db
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(userVersionRow.read<int>('user_version'), 3);
      final categoryTables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'categories'",
          )
          .get();
      expect(categoryTables, isEmpty);
      final assetColumns = await db
          .customSelect('PRAGMA table_info(assets)')
          .get();
      expect(
        assetColumns.map((row) => row.read<String>('name')),
        isNot(contains('category_id')),
      );
      final migrated = await db
          .customSelect(
            "SELECT id, name, asset_type FROM assets WHERE id = 'legacy-asset'",
          )
          .getSingle();
      expect(migrated.read<String>('name'), 'Purifier');
      expect(migrated.read<String>('asset_type'), 'device');
      final triggerRows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'search_%'",
          )
          .get();
      expect(triggerRows, hasLength(33));
    } finally {
      await db?.close();
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
    }
  });
}
