import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';

void main() {
  group('AppDatabase Migration Strategy onUpgrade', () {
    late File dbFile;
    late AppDatabase db;

    setUp(() async {
      dbFile = File(
        '${Directory.systemTemp.path}/owntend_migration_upgrade_'
        '${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      db = AppDatabase(executor: NativeDatabase(dbFile));
      // Trigger onCreate and initialization:
      await db.customSelect('SELECT 1').get();
    });

    tearDown(() async {
      await db.close();
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
    });

    test('onUpgrade does not fail with table already exists error', () async {
      // Simulating a future upgrade from schema 1 to 2
      final migrator = db.createMigrator();
      await db.migration.onUpgrade(migrator, 1, 2);

      // Verify that after upgrade, tables and indexes remain intact
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'areas'",
          )
          .get();
      expect(rows, isNotEmpty);
    });
  });
}
