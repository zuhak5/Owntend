import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/services/sidecar_registry.dart';
import 'package:owntend/src/features/auth/data/local_account_data_cleaner.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('SidecarRegistryStore Tests', () {
    late Directory tempDir;
    late SidecarRegistryStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sidecar_test_');
      store = SidecarRegistryStore(storage: const FlutterSecureStorage());
      await store.clearAll();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      await store.clearAll();
    });

    test('registers and reads sidecar entries', () async {
      final entry = SidecarEntry(
        token: 'token123',
        type: SidecarType.restoreStaged,
        canonicalRoot: 'photos',
        activeJournalId: 'journal1',
        createdAt: DateTime.now().toUtc(),
      );

      await store.registerSidecar(entry);
      final all = await store.readAll();
      expect(all.length, equals(1));
      expect(all.first.token, equals('token123'));
      expect(all.first.canonicalRoot, equals('photos'));
      expect(all.first.relativeName, equals('photos.restore-token123'));
    });

    test(
      'sweeps terminal orphans while preserving active restore journals',
      () async {
        // Create directories under tempDir
        final activeSidecar = Directory(
          p.join(tempDir.path, 'photos.restore-activeToken'),
        );
        final orphanSidecar = Directory(
          p.join(tempDir.path, 'photos.previous-orphanToken'),
        );
        await activeSidecar.create(recursive: true);
        await orphanSidecar.create(recursive: true);

        await store.registerSidecar(
          SidecarEntry(
            token: 'activeToken',
            type: SidecarType.restoreStaged,
            canonicalRoot: 'photos',
            activeJournalId: 'activeJournal',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        await store.registerSidecar(
          SidecarEntry(
            token: 'orphanToken',
            type: SidecarType.previousBackup,
            canonicalRoot: 'photos',
            activeJournalId: 'terminalJournal',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        await store.sweepOrphans(
          appDir: tempDir,
          activeJournalIds: {'activeJournal'},
          activeRestoreTokens: {'activeToken'},
        );

        expect(await activeSidecar.exists(), isTrue);
        expect(await orphanSidecar.exists(), isFalse);

        final remaining = await store.readAll();
        expect(remaining.map((e) => e.token), contains('activeToken'));
        expect(remaining.map((e) => e.token), isNot(contains('orphanToken')));
      },
    );

    test('discovers and sweeps unregistered legacy sidecars', () async {
      final legacySidecar = Directory(
        p.join(tempDir.path, 'cloud_media.restore-legacy999'),
      );
      await legacySidecar.create(recursive: true);

      await store.sweepOrphans(
        appDir: tempDir,
        activeJournalIds: {},
        activeRestoreTokens: {},
      );

      expect(await legacySidecar.exists(), isFalse);
    });

    test(
      'account deletion sweeps canonical and sidecar directories completely',
      () async {
        final db = AppDatabase(executor: NativeDatabase.memory());
        final syncStore = LocalSyncStore(db);
        final cleaner = LocalAccountDataCleaner(
          syncStore,
          sidecarRegistry: store,
          documentsDirectory: () async => tempDir,
          cacheDirectory: () async => tempDir,
        );

        final photosDir = Directory(p.join(tempDir.path, 'photos'));
        final sidecarDir = Directory(
          p.join(tempDir.path, 'profile.previous-abc123'),
        );
        await photosDir.create(recursive: true);
        await sidecarDir.create(recursive: true);

        await store.registerSidecar(
          SidecarEntry(
            token: 'abc123',
            type: SidecarType.previousBackup,
            canonicalRoot: 'profile',
            activeJournalId: '',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        await cleaner.clearFiles();

        expect(await photosDir.exists(), isFalse);
        expect(await sidecarDir.exists(), isFalse);
        expect((await store.readAll()).isEmpty, isTrue);

        await db.close();
      },
    );
  });
}
