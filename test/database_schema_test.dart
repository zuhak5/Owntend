import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';

void main() {
  group('AppDatabase production v1 schema', () {
    late File dbFile;
    late AppDatabase db;

    setUp(() async {
      dbFile = File(
        '${Directory.systemTemp.path}/owntend_schema_v1_'
        '${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      db = AppDatabase(executor: NativeDatabase(dbFile));
      await db.customSelect('SELECT 1').get();
    });

    tearDown(() async {
      await db.close();
      if (await dbFile.exists()) await dbFile.delete();
    });

    test('creates only schema version 1', () async {
      expect(AppDatabase.currentSchemaVersion, 1);
      expect(db.schemaVersion, 1);
      final row = await db.customSelect('PRAGMA user_version').getSingle();
      expect(row.read<int>('user_version'), 1);
    });

    test('creates final domain, sync, search, and cleanup tables', () async {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final names = rows.map((row) => row.read<String>('name')).toSet();

      expect(
        names,
        containsAll({
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
          'search_index_state',
          'search_index',
        }),
      );
      expect(names, isNot(contains('notifications')));
      expect(names, isNot(contains('categories')));
    });

    test('creates the final search cache and invalidation triggers', () async {
      final definition = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'table' "
            "AND name = 'search_index'",
          )
          .getSingle();
      expect(definition.read<String>('sql'), contains('fts5'));
      expect(definition.read<String>('sql'), contains('display_body'));
      expect(definition.read<String>('sql'), contains('search_terms'));

      final triggers = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' "
            "AND name LIKE 'search_%'",
          )
          .get();
      final names = triggers.map((row) => row.read<String>('name')).toSet();
      expect(names, hasLength(33));
      expect(names, contains('search_areas_insert'));
      expect(names, contains('search_asset_photos_update'));
      expect(names, contains('search_maintenance_plans_delete'));
    });

    test('creates one outbox mapping for every synchronized table', () async {
      final triggers = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' "
            "AND name LIKE 'sync_%'",
          )
          .get();
      final names = triggers.map((row) => row.read<String>('name')).toSet();
      expect(names, contains('sync_areas_area_insert'));
      expect(names, contains('sync_rooms_room_insert'));
      expect(names, contains('sync_assets_asset_insert'));
      expect(
        names,
        contains('sync_notification_inbox_notification_inbox_insert'),
      );
      expect(
        names,
        isNot(contains('sync_notifications_device_notification_insert')),
      );
    });

    test('enforces normalized active names and one primary photo', () async {
      await db.customStatement(
        "INSERT INTO areas(id, name, kind) VALUES ('area-a', 'Home', 'indoor')",
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO areas(id, name, kind) VALUES ('area-b', 'home', 'indoor')",
        ),
        throwsA(anything),
      );
      await db.customStatement(
        "UPDATE areas SET archived_at = 1 WHERE id = 'area-a'",
      );
      await db.customStatement(
        "INSERT INTO areas(id, name, kind) VALUES ('area-b', 'home', 'indoor')",
      );
      await db.customStatement(
        "INSERT INTO rooms(id, area_id, name) VALUES ('room-a', 'area-b', 'Kitchen')",
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO rooms(id, area_id, name) VALUES ('room-b', 'area-b', 'kitchen')",
        ),
        throwsA(anything),
      );
      await db.customStatement(
        "INSERT INTO assets(id, name, room_id) VALUES ('asset-a', 'Filter', 'room-a')",
      );
      await db.customStatement(
        "INSERT INTO asset_photos(id, asset_id, relative_path, is_primary) "
        "VALUES ('photo-a', 'asset-a', 'photos/a.jpg', 1)",
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO asset_photos(id, asset_id, relative_path, is_primary) "
          "VALUES ('photo-b', 'asset-a', 'photos/b.jpg', 1)",
        ),
        throwsA(anything),
      );
    });

    test('enforces containment cascade and inbox plan detachment', () async {
      await db.customStatement(
        "INSERT INTO areas(id, name, kind) VALUES ('area-a', 'Home', 'indoor')",
      );
      await db.customStatement(
        "INSERT INTO rooms(id, area_id, name) VALUES ('room-a', 'area-a', 'Kitchen')",
      );
      await db.customStatement(
        "INSERT INTO assets(id, name, room_id) VALUES ('asset-a', 'Filter', 'room-a')",
      );
      await db.customStatement(
        "INSERT INTO maintenance_plans("
        "id, asset_id, title, recurrence_interval, recurrence_unit, priority, next_due_date"
        ") VALUES ('plan-a', 'asset-a', 'Replace filter', 1, 'months', 'medium', 1)",
      );
      await db.customStatement(
        "INSERT INTO notification_inbox("
        "id, title, body, kind, plan_id, dedupe_key"
        ") VALUES ('inbox-a', 'Due', 'Replace filter', 'task', 'plan-a', 'due-a')",
      );

      await db.customStatement("DELETE FROM areas WHERE id = 'area-a'");

      for (final table in ['rooms', 'assets', 'maintenance_plans']) {
        final count = await db
            .customSelect('SELECT COUNT(*) AS value FROM $table')
            .getSingle();
        expect(count.read<int>('value'), 0, reason: '$table must cascade');
      }
      final inbox = await db
          .customSelect(
            "SELECT plan_id FROM notification_inbox WHERE id = 'inbox-a'",
          )
          .getSingle();
      expect(inbox.data['plan_id'], isNull);
    });

    test('rejects invalid enum, recurrence, and required due-date rows', () async {
      await expectLater(
        db.customStatement(
          "INSERT INTO areas(id, name, kind) VALUES ('bad', 'Bad', 'unknown')",
        ),
        throwsA(anything),
      );
      await db.customStatement(
        "INSERT INTO areas(id, name, kind) VALUES ('area-a', 'Home', 'indoor')",
      );
      await db.customStatement(
        "INSERT INTO rooms(id, area_id, name) VALUES ('room-a', 'area-a', 'Kitchen')",
      );
      await db.customStatement(
        "INSERT INTO assets(id, name, room_id) VALUES ('asset-a', 'Filter', 'room-a')",
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO maintenance_plans("
          "id, asset_id, title, recurrence_interval, recurrence_unit, priority, next_due_date"
          ") VALUES ('bad-plan', 'asset-a', 'Bad', 0, 'months', 'medium', 1)",
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO maintenance_plans("
          "id, asset_id, title, recurrence_interval, recurrence_unit, priority, next_due_date"
          ") VALUES ('bad-plan', 'asset-a', 'Bad', 1, 'months', 'medium', NULL)",
        ),
        throwsA(anything),
      );
    });

    test(
      'seeds only canonical settings and initializes sync runtime',
      () async {
        final keys = (await db.select(db.settings).get())
            .map((row) => row.key)
            .toSet();
        expect(
          keys,
          containsAll({
            'theme',
            'app_language',
            'app_language_explicit',
            'theme_time_of_day_enabled',
            'notification_preferences',
            'onboarding_completed',
            'permission_education_seen',
          }),
        );
        expect(keys, isNot(contains('notifications_enabled')));
        expect(keys, isNot(contains('permission_education_seen_v2')));

        final account = await LocalSyncStore(db).account();
        expect(account.id, 1);
        expect(account.migrationState, 'localOnly');
        final runtime = await db.select(db.syncRuntime).getSingle();
        expect(runtime.id, 1);
        expect(runtime.suppressOutbox, isFalse);
      },
    );
  });
}
