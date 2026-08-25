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
          'sync_conflicts',
          'sync_skipped_feed_entries',
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

    test('rejects outbox rows outside the canonical state domain', () async {
      await expectLater(
        db.customStatement(
          "INSERT INTO offline_mutation_queue(entity, record_key, operation, state) "
          "VALUES ('asset', 'a1', 'upsert', 'processing')",
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO offline_mutation_queue(entity, record_key, operation) "
          "VALUES ('asset', 'a1', 'patch')",
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO offline_mutation_queue(entity, record_key, operation, attempts) "
          "VALUES ('asset', 'a1', 'upsert', -2)",
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO offline_mutation_queue(entity, record_key, operation, generation) "
          "VALUES ('asset', 'a1', 'upsert', 0)",
        ),
        throwsA(anything),
      );
      // A canonical pending row is accepted; -1 is the terminal sentinel.
      await db.customStatement(
        "INSERT INTO offline_mutation_queue(entity, record_key, operation, state) "
        "VALUES ('asset', 'a1', 'delete', 'pending')",
      );
    });

    test('enforces cursor sequence and generation domains', () async {
      await expectLater(
        db.customStatement(
          "INSERT INTO sync_cursors(entity, last_sync_seq) VALUES ('asset', -1)",
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO sync_cursors(entity, feed_generation) VALUES ('asset', 0)",
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO sync_cursors(entity, high_water_seq) VALUES ('asset', -5)",
        ),
        throwsA(anything),
      );
      await db.customStatement(
        "INSERT INTO sync_cursors(entity, last_sync_seq, feed_generation, high_water_seq) "
        "VALUES ('asset', 3, 2, 4)",
      );
    });

    test('enforces the sync runtime singleton and lease pairing', () async {
      await expectLater(
        db.customStatement('INSERT INTO sync_runtime(id) VALUES (2)'),
        throwsA(anything),
      );
      // A lease owner without an expiry is structurally impossible.
      await expectLater(
        db.customStatement(
          "UPDATE sync_runtime SET lease_owner = 'device-x' WHERE id = 1",
        ),
        throwsA(anything),
      );
      await db.customStatement(
        "UPDATE sync_runtime SET lease_owner = 'device-x', "
        "lease_expires_at = strftime('%s','now') + 60 WHERE id = 1",
      );
      final runtime = await db.select(db.syncRuntime).getSingle();
      expect(runtime.leaseOwner, 'device-x');
      expect(runtime.leaseExpiresAt, isNotNull);
    });

    test('enforces the sync account singleton and hydration bounds', () async {
      await expectLater(
        db.customStatement(
          "INSERT INTO sync_account(id, device_id) VALUES (2, 'd2')",
        ),
        throwsA(anything),
      );
      await db.customStatement(
        "INSERT INTO sync_account(id, device_id, hydration_total_units) "
        "VALUES (1, 'd1', 10)",
      );
      await expectLater(
        db.customStatement(
          "UPDATE sync_account SET hydration_completed_units = 11 WHERE id = 1",
        ),
        throwsA(anything),
      );
      await db.customStatement(
        'UPDATE sync_account SET hydration_completed_units = 10 WHERE id = 1',
      );
    });

    test('enforces conflict resolution and reconciliation reason domains', () async {
      await db.customStatement(
        "INSERT INTO sync_conflicts(id, account_id, entity, record_key) "
        "VALUES ('c1', 'user-a', 'asset', 'a1')",
      );
      await expectLater(
        db.customStatement(
          "UPDATE sync_conflicts SET resolution_status = 'winner' "
          "WHERE id = 'c1'",
        ),
        throwsA(anything),
      );

      await db.customStatement(
        "INSERT INTO notification_reconciliation_requests(scope_key, reason) "
        "VALUES ('scope-1', 'local_completion')",
      );
      await expectLater(
        db.customStatement(
          "UPDATE notification_reconciliation_requests SET reason = 'because' "
          "WHERE scope_key = 'scope-1'",
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          "UPDATE notification_reconciliation_requests SET attempts = -2 "
          "WHERE scope_key = 'scope-1'",
        ),
        throwsA(anything),
      );
    });

    test('enforces cleanup retry attempt domains', () async {
      await expectLater(
        db.customStatement(
          "INSERT INTO sync_media_cleanup(object_path, user_id, entity, record_key, attempts) "
          "VALUES ('p/1.jpg', 'u1', 'asset_photo', 'p1', -2)",
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO local_media_cleanup(relative_path, attempts) "
          "VALUES ('p/1.jpg', -2)",
        ),
        throwsA(anything),
      );
    });

    test('retry indexes drive outbox and cleanup query plans', () async {
      final plan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN '
            "SELECT * FROM offline_mutation_queue "
            "WHERE state IN ('pending', 'inFlight', 'conflictRecovery') "
            "AND (next_attempt_at IS NULL OR next_attempt_at <= '2026-01-01') "
            'ORDER BY changed_at LIMIT 50',
          )
          .get();
      final detail = plan.map((row) => row.read<String>('detail')).join(' | ');
      expect(detail, contains('idx_outbox_retry'));

      final mediaPlan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN '
            'SELECT * FROM sync_media_cleanup '
            "WHERE next_attempt_at IS NULL OR next_attempt_at <= '2026-01-01' "
            'ORDER BY next_attempt_at LIMIT 20',
          )
          .get();
      final mediaDetail = mediaPlan
          .map((row) => row.read<String>('detail'))
          .join(' | ');
      expect(mediaDetail, contains('idx_sync_media_cleanup_retry'));
    });
  });
}
