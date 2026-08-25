import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';

/// WP-008 (F-008): the v1 baseline is the launch contract. A database that is
/// missing any baseline object must be rejected with an explicit, actionable
/// diagnostic — never silently repaired — because pre-launch files have no
/// upgrade path.
void main() {
  test('opening a database missing baseline objects rejects with actionable '
      'guidance', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'owntend_baseline_rejection_',
    );
    addTearDown(() async => tempDir.delete(recursive: true));
    final dbFile = File('${tempDir.path}${Platform.pathSeparator}probe.db');

    // Build a genuine v1 file, then strip objects to simulate a
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
            contains('canonical v1 schema baseline'),
            contains('missing'),
            contains('clear app storage'),
          ),
        ),
      ),
    );
  });
}
