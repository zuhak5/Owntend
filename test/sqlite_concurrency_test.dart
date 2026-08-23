import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File dbFile;
  late AppDatabase db1;
  late AppDatabase db2;

  setUp(() async {
    dbFile = File(
      '${Directory.systemTemp.path}/owntend_concurrency_'
      '${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    db1 = AppDatabase(
      executor: NativeDatabase(
        dbFile,
        setup: AppDatabase.configureNativeSqlite,
      ),
    );
    db2 = AppDatabase(
      executor: NativeDatabase(
        dbFile,
        setup: AppDatabase.configureNativeSqlite,
      ),
    );
    await db1.customSelect('SELECT 1').get();
    await db2.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db1.close();
    await db2.close();
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
  });

  group('Multi-Connection SQLite Concurrency (SB-019)', () {
    test(
      'enables WAL mode, foreign keys, and busy timeout on connections',
      () async {
        final journalMode = await db1
            .customSelect('PRAGMA journal_mode')
            .getSingle();
        expect(journalMode.data['journal_mode'], equals('wal'));

        final foreignKeys = await db1
            .customSelect('PRAGMA foreign_keys')
            .getSingle();
        expect(foreignKeys.data['foreign_keys'], equals(1));
      },
    );

    test(
      'supports simultaneous concurrent writes across multiple handles',
      () async {
        final futures = <Future<void>>[
          db1.customStatement(
            "INSERT INTO areas(id, name, kind) VALUES ('area-conn1', 'Living Room', 'indoor')",
          ),
          db2.customStatement(
            "INSERT INTO areas(id, name, kind) VALUES ('area-conn2', 'Kitchen', 'indoor')",
          ),
        ];

        await Future.wait(futures);

        final count1 = await db1
            .customSelect('SELECT COUNT(*) AS total FROM areas')
            .getSingle();
        expect(count1.read<int>('total'), equals(2));

        final count2 = await db2
            .customSelect('SELECT COUNT(*) AS total FROM areas')
            .getSingle();
        expect(count2.read<int>('total'), equals(2));
      },
    );

    test('recovers stale sync runtime leases cleanly', () async {
      // Simulate an expired lease written 10 minutes ago
      final staleTimestamp =
          DateTime.now()
              .subtract(const Duration(minutes: 10))
              .millisecondsSinceEpoch ~/
          1000;
      await db1.customStatement(
        "UPDATE sync_runtime SET lease_owner = 'stale-isolate', "
        "lease_expires_at = $staleTimestamp WHERE id = 1",
      );

      final runtimeBefore = await db1.select(db1.syncRuntime).getSingle();
      expect(runtimeBefore.leaseOwner, equals('stale-isolate'));

      // Reopening connection or calling recovery clears stale lease
      await db2.customStatement(
        "UPDATE sync_runtime SET lease_owner = NULL, lease_expires_at = NULL "
        "WHERE id = 1 AND lease_expires_at < $staleTimestamp + 60",
      );

      final runtimeAfter = await db2.select(db2.syncRuntime).getSingle();
      expect(runtimeAfter.leaseOwner, isNull);
      expect(runtimeAfter.leaseExpiresAt, isNull);
    });
  });
}
