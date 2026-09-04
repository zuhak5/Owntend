import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/services/backup_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues(<String, String>{});

  group('OwntendBackupService Sync Metadata Cleanup on Restore', () {
    late Directory root;
    late Directory docs;
    late Directory temp;
    late AppDatabase db;

    setUp(() async {
      root = await Directory.systemTemp.createTemp(
        'owntend_restore_sync_test_',
      );
      docs = Directory(p.join(root.path, 'docs'))..createSync(recursive: true);
      temp = Directory(p.join(root.path, 'temp'))..createSync(recursive: true);
      PathProviderPlatform.instance = _FakePathProviderPlatform(
        documentsPath: docs.path,
        temporaryPath: temp.path,
      );
      final dbFile = File(p.join(docs.path, 'owntend.sqlite'));
      db = AppDatabase(executor: NativeDatabase(dbFile));
      await db.customSelect('SELECT 1').get();
    });

    tearDown(() async {
      await db.close();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test(
      'purges sync_outbox and sync_shadows during database restore',
      () async {
        final service = OwntendBackupService(db);
        final backupPath = await service.exportBackup();

        // Seed sync metadata representing pre-restore sync state:
        await db
            .into(db.syncOutbox)
            .insert(
              SyncOutboxCompanion.insert(
                entity: 'asset',
                recordKey: 'pre-restore-asset',
                operation: 'upsert',
                changedAt: Value(DateTime.now().toUtc()),
                payloadJson: const Value('{}'),
              ),
            );
        await db
            .into(db.syncShadows)
            .insert(
              SyncShadowsCompanion.insert(
                entity: 'asset',
                recordKey: 'pre-restore-asset',
                remoteRevision: 5,
              ),
            );

        // Verify they are present
        final outboxBefore = await db.select(db.syncOutbox).get();
        expect(outboxBefore, isNotEmpty);
        final shadowsBefore = await db.select(db.syncShadows).get();
        expect(shadowsBefore, isNotEmpty);

        // Execute restore
        await service.restoreBackup(
          backupPath,
          cloudDisposition: RestoreCloudDisposition.localOnlyPaused,
        );

        // Verify that sync metadata tables have been completely purged
        final outboxAfter = await db.select(db.syncOutbox).get();
        expect(outboxAfter, isEmpty);
        final shadowsAfter = await db.select(db.syncShadows).get();
        expect(shadowsAfter, isEmpty);
        final cursorsAfter = await db.select(db.syncCursors).get();
        expect(cursorsAfter, isEmpty);
        final conflictsAfter = await db.select(db.syncConflicts).get();
        expect(conflictsAfter, isEmpty);
      },
    );
  });
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform({
    required this.documentsPath,
    required this.temporaryPath,
  });

  final String documentsPath;
  final String temporaryPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;

  @override
  Future<String?> getTemporaryPath() async => temporaryPath;

  @override
  Future<String?> getApplicationSupportPath() async => documentsPath;

  @override
  Future<String?> getApplicationCachePath() async => temporaryPath;
}
