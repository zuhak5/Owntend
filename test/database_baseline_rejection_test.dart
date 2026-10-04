import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// The current pre-launch baseline is the launch contract. A database that is
/// missing any baseline object must be rejected with an explicit, actionable
/// diagnostic — never silently repaired — because pre-launch files have no
/// upgrade path.
void main() {
  test(
    'previous pre-launch schema is rejected without changing its data',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'owntend_old_schema_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final path = '${tempDir.path}${Platform.pathSeparator}previous.db';
      final previous = sqlite.sqlite3.open(path);
      previous.execute('CREATE TABLE retained(value TEXT NOT NULL)');
      previous.execute("INSERT INTO retained VALUES ('local data')");
      previous.execute('PRAGMA user_version = 1');
      previous.close();

      final db = AppDatabase(executor: NativeDatabase(File(path)));
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('found schema 1'),
          ),
        ),
      );
      await db.close();

      final unchanged = sqlite.sqlite3.open(path);
      try {
        expect(
          unchanged.select('PRAGMA user_version').single['user_version'],
          1,
        );
        expect(
          unchanged.select('SELECT value FROM retained').single['value'],
          'local data',
        );
      } finally {
        unchanged.close();
      }
    },
  );

  test('opening a database missing baseline objects rejects with actionable '
      'guidance', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'owntend_baseline_rejection_',
    );
    addTearDown(() async => tempDir.delete(recursive: true));
    final dbFile = File('${tempDir.path}${Platform.pathSeparator}probe.db');

    // Build a genuine current file, then strip objects to simulate a
    // pre-baseline local database.
    final writer = AppDatabase(
      executor: NativeDatabase(dbFile, logStatements: false),
    );
    await writer.select(writer.syncRuntime).get();
    await writer.customStatement('DROP TABLE areas');
    await writer.customStatement('DROP TABLE sync_conflicts');
    await writer.close();

    final reopened = AppDatabase(
      executor: NativeDatabase(dbFile, logStatements: false),
    );
    addTearDown(reopened.close);

    await expectLater(
      reopened.select(reopened.syncRuntime).get(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains(
              'canonical v${AppDatabase.currentSchemaVersion} schema baseline',
            ),
            contains('missing'),
            contains('clear app storage'),
          ),
        ),
      ),
    );
  });
}
