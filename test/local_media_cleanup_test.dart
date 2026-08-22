import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';

void main() {
  late AppDatabase database;
  late Directory documents;

  setUp(() async {
    database = AppDatabase(executor: NativeDatabase.memory());
    documents = await Directory.systemTemp.createTemp(
      'owntend_local_media_cleanup_',
    );
  });

  tearDown(() async {
    await database.close();
    if (await documents.exists()) {
      await documents.delete(recursive: true);
    }
  });

  Future<void> enqueue(String relativePath) {
    return database
        .into(database.localMediaCleanup)
        .insert(LocalMediaCleanupCompanion.insert(relativePath: relativePath));
  }

  test('a queued file is deleted after a new store instance starts', () async {
    final mediaDirectory = Directory('${documents.path}/media');
    await mediaDirectory.create();
    final file = File('${mediaDirectory.path}/photo.jpg');
    await file.writeAsBytes(const [1, 2, 3]);
    await enqueue('media/photo.jpg');

    final restartedStore = LocalSyncStore(
      database,
      documentsDirectory: () async => documents,
    );
    expect(await restartedStore.processLocalMediaCleanup(), 1);

    expect(await file.exists(), isFalse);
    expect(await database.select(database.localMediaCleanup).get(), isEmpty);
  });

  test(
    'a locked-file failure remains durable with bounded retry state',
    () async {
      final file = File('${documents.path}/locked.jpg');
      await file.writeAsBytes(const [1]);
      await enqueue('locked.jpg');
      final store = LocalSyncStore(
        database,
        documentsDirectory: () async => documents,
        deleteFile: (_) async => throw const FileSystemException('locked'),
      );

      expect(await store.processLocalMediaCleanup(), 1);

      final cleanup = await database
          .select(database.localMediaCleanup)
          .getSingle();
      expect(cleanup.attempts, 1);
      expect(cleanup.nextAttemptAt, isNotNull);
      expect(cleanup.lastErrorCode, 'filesystem_error');
      expect(await file.exists(), isTrue);
    },
  );

  test('an escaping path becomes a visible terminal cleanup record', () async {
    await enqueue('../outside.jpg');
    final store = LocalSyncStore(
      database,
      documentsDirectory: () async => documents,
    );

    expect(await store.processLocalMediaCleanup(), 1);

    final cleanup = await database
        .select(database.localMediaCleanup)
        .getSingle();
    expect(cleanup.attempts, -1);
    expect(cleanup.nextAttemptAt, isNull);
    expect(cleanup.lastErrorCode, 'invalid_path');
  });
}
