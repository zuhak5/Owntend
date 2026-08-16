import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';

void main() {
  group('AppDatabase baseline v1 schema and lifecycle', () {
    late File dbFile;
    late AppDatabase db;

    setUp(() async {
      dbFile = File(
        '${Directory.systemTemp.path}/owntend_baseline_v1_'
        '${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      db = AppDatabase(executor: NativeDatabase(dbFile));
      // Force database opening and beforeOpen execution
      await db.customSelect('SELECT 1').get();
    });

    tearDown(() async {
      await db.close();
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
    });

    test('initializes with baseline schema version 1', () async {
      expect(AppDatabase.currentSchemaVersion, 1);
      expect(db.schemaVersion, 1);

      final userVersionRow = await db
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(userVersionRow.read<int>('user_version'), 1);
    });

    test('creates all 26 canonical active tables', () async {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final tableNames = rows.map((r) => r.read<String>('name')).toSet();

      const expectedTables = {
        'areas',
        'rooms',
        'categories',
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
      expect(indexNames, contains('idx_assets_category'));
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

    test('seeds default categories, settings, and streak', () async {
      final seededCategories = await db.select(db.categories).get();
      expect(
        seededCategories.map((c) => c.id),
        containsAll([
          'category_safety',
          'category_pets',
          'category_appliances',
          'category_plants',
          'category_cleaning',
          'category_general',
        ]),
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
}
