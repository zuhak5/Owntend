import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show UpdateKind, Value;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/services/backup/backup_container.dart';
import 'package:owntend/src/core/services/backup_service.dart';

import 'support/maintenance_test_extensions.dart';

import 'package:owntend/src/core/services/restore_journal.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues(<String, String>{});

  group('OwntendBackupService', () {
    late Directory root;
    late Directory docs;
    late Directory temp;
    late List<AppDatabase> databases;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('owntend_backup_test_');
      docs = Directory(p.join(root.path, 'docs'))..createSync(recursive: true);
      temp = Directory(p.join(root.path, 'temp'))..createSync(recursive: true);
      PathProviderPlatform.instance = _FakePathProviderPlatform(
        documentsPath: docs.path,
        temporaryPath: temp.path,
      );
      databases = [];
    });

    tearDown(() async {
      for (final db in databases.reversed) {
        try {
          await db.close();
        } catch (_) {
          // Some restore tests intentionally close the active database.
        }
      }
      if (await root.exists()) {
        await _deleteDirectoryWithRetries(root);
      }
    });

    test(
      'exports an inspectable backup with all core data and media',
      () async {
        final db = await _openDatabase(docs, databases);
        await _seedRealisticData(db, root);
        final service = OwntendBackupService(db);

        final backupPath = await service.exportBackup();
        final preview = await service.inspectBackup(backupPath);
        final state = await service.backupState();

        expect(File(backupPath).existsSync(), isTrue);
        expect(p.basename(p.dirname(backupPath)), 'backups');
        expect(p.basename(backupPath), startsWith('owntend-backup-'));
        expect(preview.thingCount, 1);
        expect(preview.taskCount, 1);
        expect(preview.historyCount, 1);
        expect(preview.fileCount, 2);
        expect(preview.counts['settings'], greaterThanOrEqualTo(4));
        expect(preview.includedData.join(' '), contains('Notification'));
        expect(
          preview.excludedData.join(' '),
          contains('Android scheduled alarm handles'),
        );
        expect(state.lastBackup?.successful, isTrue);
        expect(state.lastBackup?.path, backupPath);
      },
    );

    test('backs up and restores media downloaded from cloud sync', () async {
      final db = await _openDatabase(docs, databases);
      await _seedRealisticData(db, root);
      final photo = await db.select(db.assetPhotos).getSingle();
      final originalFile = File(
        p.joinAll([docs.path, ...photo.relativePath.split('/')]),
      );
      final cloudRelativePath = 'cloud_media/${photo.assetId}/${photo.id}.jpg';
      final cloudFile = File(
        p.joinAll([docs.path, ...cloudRelativePath.split('/')]),
      );
      await cloudFile.parent.create(recursive: true);
      await originalFile.rename(cloudFile.path);
      await (db.update(db.assetPhotos)..where((row) => row.id.equals(photo.id)))
          .write(AssetPhotosCompanion(relativePath: Value(cloudRelativePath)));
      final service = OwntendBackupService(db);

      final backupPath = await service.exportBackup();
      final preview = await service.inspectBackup(backupPath);
      expect(preview.fileCount, greaterThan(0));
      expect(File(backupPath).readAsBytesSync().take(8), 'OWNTDBK1'.codeUnits);

      await cloudFile.writeAsBytes([9, 9, 9], flush: true);
      await service.restoreBackup(
        backupPath,
        cloudDisposition: RestoreCloudDisposition.localOnlyPaused,
      );

      _expectNormalizedTestPhoto(await cloudFile.readAsBytes());
    });

    test('rejects traversal inside the cloud media root', () async {
      final db = await _openDatabase(docs, databases);
      await _seedRealisticData(db, root);
      await db
          .update(db.assetPhotos)
          .write(
            const AssetPhotosCompanion(
              relativePath: Value('cloud_media/../outside.jpg'),
            ),
          );
      final service = OwntendBackupService(db);

      await expectLater(
        service.exportBackup(),
        throwsA(isA<BackupException>()),
      );
    });

    test('restores backup state without duplicating current data', () async {
      final db = await _openDatabase(docs, databases);
      await _seedRealisticData(db, root);
      final service = OwntendBackupService(db);
      final backupPath = await service.exportBackup();

      final repo = DriftAssetRepository(db);
      final extraRoom = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Temporary room',
      );
      await repo.saveAsset(name: 'Temporary thing', roomId: extraRoom);
      await DriftSettingsRepository(db)
          .setThemePreference(ThemePreference.light);

      await service.restoreBackup(
        backupPath,
        cloudDisposition: RestoreCloudDisposition.localOnlyPaused,
      );

      final restoredRepo = DriftAssetRepository(db);
      final restoredMaintenance = DriftMaintenanceRepository(db);
      final restoredSettings = DriftSettingsRepository(db);
      final assets = await restoredRepo.listAssets();
      final tasks = await restoredMaintenance.listTasks();
      final state = await service.backupState();

      expect(assets.map((asset) => asset.name), ['Water heater']);
      expect(tasks.map((task) => task.plan.title), ['Flush tank']);
      expect(
        await restoredMaintenance.listRecordsForPlan(tasks.single.plan.id),
        hasLength(1),
      );
      expect(await restoredSettings.themePreference(), ThemePreference.dark);
      expect(
        File(p.join(docs.path, 'photos', assets.single.id, 'seed-photo.jpg'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(docs.path, 'profile', 'avatar.jpg')).existsSync(),
        isTrue,
      );
      expect(state.lastBackup?.trigger, BackupTrigger.preRestore);
      expect(
        p.basename(state.lastBackup?.path ?? ''),
        startsWith('owntend-before-restore-'),
      );
      expect(state.lastBackup?.message, contains('Restore completed'));
      final stagedMedia = await docs
          .list()
          .where(
            (entity) =>
                p.basename(entity.path).contains('.restore-') ||
                p.basename(entity.path).contains('.previous-'),
          )
          .toList();
      expect(stagedMedia, isEmpty);
    });

    test('captures account scope before the restore barrier and persists cloud intent', () async {
      final db = await _openDatabase(docs, databases);
      await _seedRealisticData(db, root);
      final syncStore = LocalSyncStore(db);
      await syncStore.bindIdentity('user-a');
      await syncStore.recordSyncSuccess(DateTime.now());

      final journalStore = InMemoryRestoreJournalStore();
      RestoreJournalEntry? entryAtBarrier;
      final service = OwntendBackupService(
        db,
        journalStore: journalStore,
        onBeforeRestoreBarrier: () async {
          entryAtBarrier = await journalStore.getActiveEntry();
        },
      );
      final backupPath = await service.exportBackup();
      await db.delete(db.syncOutbox).go();

      await service.restoreBackup(
        backupPath,
        cloudDisposition: RestoreCloudDisposition.updateCloud,
      );

      expect(entryAtBarrier?.accountScope, 'user-a');
      expect(
        entryAtBarrier?.cloudDisposition,
        RestoreCloudDisposition.updateCloud,
      );
      expect(await journalStore.getActiveEntry(), isNull);
      expect(await syncStore.pendingCount(), greaterThan(0));
    });

    test('local-only restore durably pauses cloud synchronization', () async {
      final db = await _openDatabase(docs, databases);
      await _seedRealisticData(db, root);
      final journalStore = InMemoryRestoreJournalStore();
      final service = OwntendBackupService(db, journalStore: journalStore);
      final backupPath = await service.exportBackup();

      await service.restoreBackup(
        backupPath,
        cloudDisposition: RestoreCloudDisposition.localOnlyPaused,
      );

      final account = await LocalSyncStore(db).account();
      expect(account.enabled, isFalse);
      expect(account.boundUserId, isNull);
      expect(account.migrationState, 'restorePaused');
      expect(account.restorePending, isTrue);
      expect(await journalStore.getActiveEntry(), isNull);
    });

    test(
      'explicit local-only choice wins even for a complete bound snapshot',
      () async {
        final db = await _openDatabase(docs, databases);
        await _seedRealisticData(db, root);
        final syncStore = LocalSyncStore(db);
        await syncStore.bindIdentity('user-a');
        await syncStore.recordSyncSuccess(DateTime.utc(2026, 8, 30, 8));
        final journalStore = InMemoryRestoreJournalStore();
        RestoreJournalEntry? entryAtBarrier;
        final service = OwntendBackupService(
          db,
          journalStore: journalStore,
          onBeforeRestoreBarrier: () async {
            entryAtBarrier = await journalStore.getActiveEntry();
          },
        );
        final backupPath = await service.exportBackup();

        await service.restoreBackup(
          backupPath,
          cloudDisposition: RestoreCloudDisposition.localOnlyPaused,
        );

        expect(
          entryAtBarrier?.cloudDisposition,
          RestoreCloudDisposition.localOnlyPaused,
        );
        final account = await syncStore.account();
        expect(account.enabled, isFalse);
        expect(account.boundUserId, isNull);
        expect(account.migrationState, 'restorePaused');
        expect(account.restorePending, isTrue);
        expect(await syncStore.pendingCount(), 0);
      },
    );

    test('update-cloud choice requires a complete bound snapshot', () async {
      final db = await _openDatabase(docs, databases);
      await _seedRealisticData(db, root);
      final syncStore = LocalSyncStore(db);
      await syncStore.bindIdentity('user-a');
      final journalStore = InMemoryRestoreJournalStore();
      final service = OwntendBackupService(db, journalStore: journalStore);
      final backupPath = await service.exportBackup();

      await expectLater(
        service.restoreBackup(
          backupPath,
          cloudDisposition: RestoreCloudDisposition.updateCloud,
        ),
        throwsA(
          isA<BackupException>().having(
            (error) => error.message,
            'message',
            contains('complete synchronized snapshot'),
          ),
        ),
      );

      expect(await journalStore.getActiveEntry(), isNull);
      final account = await syncStore.account();
      expect(account.boundUserId, 'user-a');
      expect(account.restorePending, isFalse);
    });

    test('rolls media back when the database import fails', () async {
      final db = await _openDatabase(docs, databases);
      await _seedRealisticData(db, root);
      final service = OwntendBackupService(db);
      final backupPath = await service.exportBackup();
      final asset = (await DriftAssetRepository(db).listAssets()).single;
      final photo = File(
        p.join(docs.path, 'photos', asset.id, 'seed-photo.jpg'),
      );
      await photo.writeAsBytes([9, 8, 7, 6], flush: true);
      await db.customStatement('''
CREATE TRIGGER fail_restore_settings
BEFORE INSERT ON settings
BEGIN
  SELECT RAISE(ABORT, 'forced restore failure');
END
''');

      await expectLater(
        service.restoreBackup(
          backupPath,
          cloudDisposition: RestoreCloudDisposition.localOnlyPaused,
        ),
        throwsA(anything),
      );

      expect(await photo.readAsBytes(), [9, 8, 7, 6]);
      expect(
        await LocalSyncStore(db).readRestoreGenerationMarker(),
        isNull,
        reason: 'a failed import must never leave a commit marker',
      );
      final stagedMedia = await docs
          .list()
          .where(
            (entity) =>
                p.basename(entity.path).contains('.restore-') ||
                p.basename(entity.path).contains('.previous-'),
          )
          .toList();
      expect(stagedMedia, isEmpty);
    });

    test('rejects corrupted, empty, and unsafe backup files', () async {
      final db = await _openDatabase(docs, databases);
      final service = OwntendBackupService(db);
      final empty = File(p.join(root.path, 'empty.owntend-backup'))
        ..writeAsBytesSync([]);
      final corrupt = File(p.join(root.path, 'corrupt.owntend-backup'))
        ..writeAsStringSync('not an owntend container');
      // A ZIP file is not a valid Owntend container and must be rejected.
      final zipBytes = <int>[
        0x50, 0x4b, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00, 0x00, 0x00, //
        0x00, 0x00, 0x00, 0x00,
      ];
      final foreignZip = File(p.join(root.path, 'foreign.owntend-backup'))
        ..writeAsBytesSync(zipBytes);

      expect(
        () => service.inspectBackup(empty.path),
        throwsA(isA<BackupException>()),
      );
      expect(
        () => service.inspectBackup(corrupt.path),
        throwsA(isA<BackupException>()),
      );
      expect(
        () => service.inspectBackup(foreignZip.path),
        throwsA(isA<BackupException>()),
      );
    });

    test('rejects tampered checksum and newer schema backups', () async {
      final db = await _openDatabase(docs, databases);
      await _seedRealisticData(db, root);
      final service = OwntendBackupService(db);
      final backupPath = await service.exportBackup();

      final tamperedChecksum = await _tamperBackup(
        backupPath,
        root,
        mutateDatabase: true,
      );
      final newerSchema = await _tamperBackup(
        backupPath,
        root,
        manifestUpdates: {'schemaVersion': db.schemaVersion + 1},
      );
      final newerFormat = await _tamperBackup(
        backupPath,
        root,
        manifestUpdates: {'format': 99},
      );

      // Payload corruption is caught by the authenticated extraction path
      // (per-entry checksums), while manifest-level tampering is caught
      // during inspection.
      expect(
        () => service.restoreBackup(
          tamperedChecksum.path,
          cloudDisposition: RestoreCloudDisposition.localOnlyPaused,
        ),
        throwsA(isA<BackupException>()),
      );
      expect(
        () => service.inspectBackup(newerSchema.path),
        throwsA(isA<BackupException>()),
      );
      expect(
        () => service.inspectBackup(newerFormat.path),
        throwsA(isA<BackupException>()),
      );
    });
  });

  group('restore crash atomicity (failpoint process-death simulation)', () {
    late Directory root;
    late Directory docs;
    late Directory temp;
    late List<AppDatabase> databases;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('owntend_crash_test_');
      docs = Directory(p.join(root.path, 'docs'))..createSync(recursive: true);
      temp = Directory(p.join(root.path, 'temp'))..createSync(recursive: true);
      PathProviderPlatform.instance = _FakePathProviderPlatform(
        documentsPath: docs.path,
        temporaryPath: temp.path,
      );
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      databases = [];
    });

    tearDown(() async {
      for (final db in databases.reversed) {
        try {
          await db.close();
        } catch (_) {}
      }
      if (await root.exists()) {
        await _deleteDirectoryWithRetries(root);
      }
    });

    /// Exports a backup, then diverges live state from the archive so old
    /// and new generations are distinguishable.
    Future<({AppDatabase db, File photo, String backupPath})>
    seedDivergedState() async {
      final db = await _openDatabase(docs, databases);
      await _seedRealisticData(db, root);
      final service = OwntendBackupService(db);
      final backupPath = await service.exportBackup();
      final asset = (await DriftAssetRepository(db).listAssets()).single;
      final photo = File(
        p.join(docs.path, 'photos', asset.id, 'seed-photo.jpg'),
      );
      await photo.writeAsBytes([9, 9, 9, 9], flush: true);
      await db.customUpdate(
        "UPDATE rooms SET name = 'Renamed After Backup' "
        "WHERE name = 'Utility'",
        updates: {db.rooms},
        updateKind: UpdateKind.update,
      );
      return (db: db, photo: photo, backupPath: backupPath);
    }

    Future<String> roomName(AppDatabase db) async {
      final utility = await (db.select(
        db.rooms,
      )..where((row) => row.name.equals('Utility'))).getSingleOrNull();
      if (utility != null) return 'Utility';
      final renamed =
          await (db.select(db.rooms)
                ..where((row) => row.name.equals('Renamed After Backup')))
              .getSingleOrNull();
      return renamed == null ? '<missing>' : 'Renamed After Backup';
    }

    Future<List<String>> restoreResidue() async {
      return [
        for (final entity in docs.listSync())
          if (p.basename(entity.path).contains('.restore-') ||
              p.basename(entity.path).contains('.previous-'))
            p.basename(entity.path),
      ];
    }

    Future<void> runRecovery(AppDatabase db) async {
      await RestoreRecoveryCoordinator(
        journalStore: RestoreJournalStore(),
        localSyncStore: LocalSyncStore(db),
      ).recover();
    }

    test('death before the import transaction leaves the complete old '
        'generation', () async {
      final (:db, :photo, :backupPath) = await seedDivergedState();
      final crashing = OwntendBackupService(
        db,
        failpoints: RestoreFailpoints({'db:importCommit': 1}),
      );

      await expectLater(
        crashing.restoreBackup(
          backupPath,
          cloudDisposition: RestoreCloudDisposition.localOnlyPaused,
        ),
        throwsA(isA<StateError>()),
      );

      // The in-process failure handler already rolled staged media back;
      // assert the old generation is complete and unpaired with new data.
      expect(await roomName(db), 'Renamed After Backup');
      expect(await photo.readAsBytes(), [9, 9, 9, 9]);
      expect(await restoreResidue(), isEmpty);
      expect(await RestoreJournalStore().getActiveEntry(), isNull);
    });

    test('death after actual DB commit but before persisting dbCommitComplete '
        'rolls forward during recovery', () async {
      final (:db, :photo, :backupPath) = await seedDivergedState();
      final crashing = OwntendBackupService(
        db,
        failpoints: RestoreFailpoints({'db:importCommit:returned': 1}),
      );

      await expectLater(
        crashing.restoreBackup(
          backupPath,
          cloudDisposition: RestoreCloudDisposition.localOnlyPaused,
        ),
        throwsA(isA<StateError>()),
      );

      // SQLite committed: the generation marker matches the journal even
      // though the journal phase only says dbCommitStarted.
      final store = LocalSyncStore(db);
      final journal = await RestoreJournalStore().getActiveEntry();
      expect(journal, isNotNull);
      expect(journal!.phase, RestorePhase.dbCommitStarted);
      expect(await store.readRestoreGenerationMarker(), journal.journalId);
      // Media activation has not started yet: canonical files are still
      // the old generation, never mixed.
      expect(await photo.readAsBytes(), [9, 9, 9, 9]);

      await runRecovery(db);

      expect(
        await roomName(db),
        'Utility',
        reason: 'committed import must survive recovery',
      );
      _expectNormalizedTestPhoto(
        await photo.readAsBytes(),
        reason: 'staged media must be activated to pair with the new DB',
      );
      expect(await restoreResidue(), isEmpty);
      expect(await RestoreJournalStore().getActiveEntry(), isNull);
    });

    test(
      'death between per-root media activations converges during recovery',
      () async {
        final (:db, :photo, :backupPath) = await seedDivergedState();
        final profileAvatar = File(p.join(docs.path, 'profile', 'avatar.jpg'));
        await profileAvatar.writeAsBytes([8, 8, 8, 8], flush: true);
        final crashing = OwntendBackupService(
          db,
          failpoints: RestoreFailpoints({'media:activate:profile': 1}),
        );

        await expectLater(
          crashing.restoreBackup(
            backupPath,
            cloudDisposition: RestoreCloudDisposition.localOnlyPaused,
          ),
          throwsA(isA<StateError>()),
        );

        // photos activated; profile not yet.
        _expectNormalizedTestPhoto(await photo.readAsBytes());
        expect(await profileAvatar.readAsBytes(), [8, 8, 8, 8]);

        await runRecovery(db);

        expect(await profileAvatar.readAsBytes(), [
          5,
          6,
          7,
          8,
        ], reason: 'remaining root must finish activating');
        _expectNormalizedTestPhoto(await photo.readAsBytes());
        expect(await restoreResidue(), isEmpty);
        expect(await RestoreJournalStore().getActiveEntry(), isNull);
      },
    );

    test('death at the cleanup boundary retains consistent generations and '
        'recovery finishes cleanup', () async {
      final (:db, :photo, :backupPath) = await seedDivergedState();
      final crashing = OwntendBackupService(
        db,
        failpoints: RestoreFailpoints({'cleanup:previousGenerations': 1}),
      );

      await expectLater(
        crashing.restoreBackup(
          backupPath,
          cloudDisposition: RestoreCloudDisposition.localOnlyPaused,
        ),
        throwsA(isA<StateError>()),
      );

      expect(await roomName(db), 'Utility');
      _expectNormalizedTestPhoto(await photo.readAsBytes());
      final residueAfterCrash = await restoreResidue();
      expect(
        residueAfterCrash.where((name) => name.contains('.previous-')),
        isNotEmpty,
      );

      await runRecovery(db);

      expect(await restoreResidue(), isEmpty);
      expect(await RestoreJournalStore().getActiveEntry(), isNull);
      _expectNormalizedTestPhoto(await photo.readAsBytes());
    });

    test(
      'successful restore pairs the new database with the new media',
      () async {
        final (:db, :photo, :backupPath) = await seedDivergedState();
        final service = OwntendBackupService(db);

        await service.restoreBackup(
          backupPath,
          cloudDisposition: RestoreCloudDisposition.localOnlyPaused,
        );

        expect(await roomName(db), 'Utility');
        _expectNormalizedTestPhoto(await photo.readAsBytes());
        expect(await restoreResidue(), isEmpty);
        expect(await RestoreJournalStore().getActiveEntry(), isNull);
      },
    );
  });
}

void _expectNormalizedTestPhoto(List<int> bytes, {String? reason}) {
  expect(bytes.length, greaterThan(4), reason: reason);
  expect(bytes.take(2), orderedEquals(const [0xff, 0xd8]), reason: reason);
  expect(bytes, isNot(orderedEquals(const [9, 9, 9, 9])), reason: reason);
}

Future<AppDatabase> _openDatabase(
  Directory docs,
  List<AppDatabase> databases,
) async {
  final db = AppDatabase(
    executor: NativeDatabase(
      File(p.join(docs.path, AppDatabase.databaseFileName)),
    ),
  );
  databases.add(db);
  await db.customSelect('SELECT 1').get();
  return db;
}

Future<void> _seedRealisticData(AppDatabase db, Directory root) async {
  final repo = DriftAssetRepository(db);
  final maintenance = DriftMaintenanceRepository(db);
  final settings = DriftSettingsRepository(db);
  await repo.saveArea(
    id: 'area_first_floor',
    name: 'First Floor',
    kind: AreaKind.indoor,
    sortOrder: 0,
  );
  final roomId = await repo.saveRoom(
    areaId: 'area_first_floor',
    name: 'Utility',
    roomType: RoomType.utility,
  );
  final assetId = await repo.saveAsset(
    name: 'Water heater',
    assetType: AssetType.device,
    roomId: roomId,
    placement: 'North wall',
    tagNames: ['annual'],
    deviceDetails: const DeviceDetails(brand: 'Rheem', model: 'Pro'),
  );
  final planId = await maintenance.savePlan(
    assetId: assetId,
    title: 'Flush tank',
    recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.years),
    priority: PriorityLevel.high,
    nextDueDate: DateTime(2026, 6, 18),
    reminderDaysBefore: 7,
  );
  await maintenance.completeCurrentOccurrence(
    planId,
    completedAt: DateTime(2026, 6, 18, 9),
    notes: 'No sediment.',
  );
  await settings.setThemePreference(ThemePreference.dark);
  await settings.setNotificationPreferences(
    const NotificationPreferences(
      enabled: true,
      privacyMode: true,
      defaultSnoozeMinutes: 180,
    ),
  );
  await settings.setProfile(nickname: 'Backup Tester');

  final photoSource = File(p.join(root.path, 'seed-photo.jpg'))
    ..writeAsBytesSync(
      image.encodeJpg(
        image.Image(width: 8, height: 8)..clear(image.ColorRgb8(30, 100, 160)),
      ),
    );
  await repo.addPhoto(assetId, photoSource.path);
  final generatedPhotoDir = Directory(
    p.join((await _docs()).path, 'photos', assetId),
  );
  final generatedPhoto = generatedPhotoDir.listSync().whereType<File>().single;
  await generatedPhoto.rename(p.join(generatedPhotoDir.path, 'seed-photo.jpg'));
  await (db.update(
    db.assetPhotos,
  )..where((photo) => photo.assetId.equals(assetId))).write(
    AssetPhotosCompanion(relativePath: Value('photos/$assetId/seed-photo.jpg')),
  );
  final profileDir = Directory(p.join((await _docs()).path, 'profile'));
  await profileDir.create(recursive: true);
  File(p.join(profileDir.path, 'avatar.jpg')).writeAsBytesSync([5, 6, 7, 8]);
}

Future<Directory> _docs() async {
  final path = await PathProviderPlatform.instance
      .getApplicationDocumentsPath();
  return Directory(path!);
}

Future<void> _deleteDirectoryWithRetries(Directory directory) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    if (!await directory.exists()) {
      return;
    }
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 9) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }
}

/// Re-encrypts an exported container with a modified manifest, or flips a
/// payload byte when [mutateDatabase] is set (which must always fail AEAD
/// authentication).
Future<File> _tamperBackup(
  String backupPath,
  Directory root, {
  Map<String, Object?> manifestUpdates = const {},
  bool mutateDatabase = false,
}) async {
  final secret = await BackupAutoKeyStore.load();
  final sourceHandle = await File(backupPath).open(mode: FileMode.read);
  final reader = await BackupContainerReader.open(
    input: sourceHandle,
    passphrase: secret,
  );
  final manifestFrame = await reader.readFrame(sourceHandle);
  final manifest =
      jsonDecode(utf8.decode(manifestFrame!)) as Map<String, dynamic>;
  manifest.addAll(manifestUpdates);

  final output = File(
    p.join(
      root.path,
      '${_uuid()}${manifestUpdates.hashCode}${mutateDatabase ? '-flip' : ''}.owntend-backup',
    ),
  );
  final outHandle = await output.open(mode: FileMode.write);
  final writer = await BackupContainerWriter.start(
    output: outHandle,
    passphrase: secret,
    keyGuard: BackupContainerCodec.keyGuardDeviceKey,
    fastProfile: false,
  );
  await writer.writeFrame(utf8.encode(jsonEncode(manifest)));
  var payloadFrameIndex = 0;
  while (true) {
    final frame = await reader.readFrame(sourceHandle);
    if (frame == null) break;
    if (mutateDatabase && payloadFrameIndex == 0 && frame.isNotEmpty) {
      // Corrupt the first payload byte of the database snapshot so its
      // decrypted content no longer matches the manifest checksum.
      frame[0] ^= 0x01;
    }
    await writer.writeFrame(frame);
    payloadFrameIndex++;
  }
  await outHandle.close();
  await sourceHandle.close();
  return output;
}

String _uuid() => DateTime.now().microsecondsSinceEpoch.toString();

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
