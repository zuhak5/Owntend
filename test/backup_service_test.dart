import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/services/backup_service.dart';
import 'package:owntend/src/core/services/restore_journal.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues(<String, String>{});

  group('ZipBackupService', () {
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
        final service = ZipBackupService(db);

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
      final service = ZipBackupService(db);

      final backupPath = await service.exportBackup();
      final archive = ZipDecoder().decodeBytes(
        await File(backupPath).readAsBytes(),
      );
      expect(archive.findFile(cloudRelativePath), isNotNull);

      await cloudFile.writeAsBytes([9, 9, 9], flush: true);
      await service.restoreBackup(backupPath);

      expect(await cloudFile.readAsBytes(), [1, 2, 3, 4]);
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
      final service = ZipBackupService(db);

      await expectLater(
        service.exportBackup(),
        throwsA(isA<BackupException>()),
      );
    });

    test('restores backup state without duplicating current data', () async {
      final db = await _openDatabase(docs, databases);
      await _seedRealisticData(db, root);
      final service = ZipBackupService(db);
      final backupPath = await service.exportBackup();

      final repo = DriftAssetRepository(db);
      final categories = await repo.listCategories();
      final extraRoom = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Temporary room',
      );
      await repo.saveAsset(
        name: 'Temporary thing',
        categoryId: _categoryId(categories, HealthGroup.other),
        roomId: extraRoom,
      );
      await DriftSettingsRepository(db)
          .setThemePreference(ThemePreference.light);

      await service.restoreBackup(backupPath);

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
      final service = ZipBackupService(
        db,
        journalStore: journalStore,
        onBeforeRestoreBarrier: () async {
          entryAtBarrier = await journalStore.getActiveEntry();
        },
      );
      final backupPath = await service.exportBackup();
      await db.delete(db.syncOutbox).go();

      await service.restoreBackup(backupPath);

      expect(entryAtBarrier?.accountScope, 'user-a');
      expect(entryAtBarrier?.updateCloudIntent, isTrue);
      expect(await journalStore.getActiveEntry(), isNull);
      expect(await syncStore.pendingCount(), greaterThan(0));
    });

    test('local-only restore durably pauses cloud synchronization', () async {
      final db = await _openDatabase(docs, databases);
      await _seedRealisticData(db, root);
      final journalStore = InMemoryRestoreJournalStore();
      final service = ZipBackupService(db, journalStore: journalStore);
      final backupPath = await service.exportBackup();

      await service.restoreBackup(backupPath);

      final account = await LocalSyncStore(db).account();
      expect(account.enabled, isFalse);
      expect(account.boundUserId, isNull);
      expect(account.migrationState, 'restorePaused');
      expect(account.restorePending, isTrue);
      expect(await journalStore.getActiveEntry(), isNull);
    });

    test('rolls media back when the database import fails', () async {
      final db = await _openDatabase(docs, databases);
      await _seedRealisticData(db, root);
      final service = ZipBackupService(db);
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

      await expectLater(service.restoreBackup(backupPath), throwsA(anything));

      expect(await photo.readAsBytes(), [9, 8, 7, 6]);
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
      final service = ZipBackupService(db);
      final empty = File(p.join(root.path, 'empty.zip'))..writeAsBytesSync([]);
      final corrupt = File(p.join(root.path, 'corrupt.zip'))
        ..writeAsStringSync('not a zip');
      final unsafe = File(p.join(root.path, 'unsafe.zip'))
        ..writeAsBytesSync(
          ZipEncoder().encode(
            Archive()..addFile(ArchiveFile.string('../evil.txt', 'x')),
          ),
        );

      expect(
        () => service.inspectBackup(empty.path),
        throwsA(isA<BackupException>()),
      );
      expect(
        () => service.inspectBackup(corrupt.path),
        throwsA(isA<BackupException>()),
      );
      expect(
        () => service.inspectBackup(unsafe.path),
        throwsA(isA<BackupException>()),
      );
    });

    test('rejects tampered checksum and newer schema backups', () async {
      final db = await _openDatabase(docs, databases);
      await _seedRealisticData(db, root);
      final service = ZipBackupService(db);
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

      expect(
        () => service.inspectBackup(tamperedChecksum.path),
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

    test(
      'previews old format backups as restorable with migration warning',
      () async {
        final db = await _openDatabase(docs, databases);
        final service = ZipBackupService(db);
        final oldBackup = await _createFormatOneBackup(root);

        final preview = await service.inspectBackup(oldBackup.path);

        expect(preview.formatVersion, 1);
        expect(preview.schemaVersion, 1);
        expect(preview.warnings.join(' '), contains('older backup format'));
      },
    );
  });
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
  final categories = await repo.listCategories();
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
    categoryId: _categoryId(categories, HealthGroup.appliances),
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
    healthGroup: HealthGroup.appliances,
    reminderDaysBefore: 7,
  );
  await maintenance.completePlan(
    planId,
    completedAt: DateTime(2026, 6, 18, 9),
    expectedNextDueDate: DateTime(2026, 6, 18),
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
    ..writeAsBytesSync([1, 2, 3, 4]);
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
  final legacyProfileDir = Directory(p.join((await _docs()).path, 'profile'));
  await legacyProfileDir.create(recursive: true);
  File(p.join(legacyProfileDir.path, 'avatar.jpg'))
      .writeAsBytesSync([5, 6, 7, 8]);
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

String _categoryId(List<Category> categories, HealthGroup group) {
  return categories.singleWhere((category) => category.healthGroup == group).id;
}

Future<File> _tamperBackup(
  String backupPath,
  Directory root, {
  Map<String, Object?> manifestUpdates = const {},
  bool mutateDatabase = false,
}) async {
  final archive = ZipDecoder().decodeBytes(
    await File(backupPath).readAsBytes(),
  );
  final manifest = jsonDecode(
    utf8.decode(archive.findFile('manifest.json')!.content),
  ) as Map<String, dynamic>;
  manifest.addAll(manifestUpdates);

  final next = Archive();
  for (final file in archive.files.where((file) => file.isFile)) {
    if (file.name == 'manifest.json') {
      continue;
    }
    final bytes = file.content.toList();
    if (mutateDatabase && file.name == AppDatabase.databaseFileName) {
      bytes[bytes.length - 1] = bytes.last == 0 ? 1 : 0;
    }
    next.addFile(ArchiveFile.bytes(file.name, bytes));
  }
  next.addFile(
    ArchiveFile.string(
      'manifest.json',
      const JsonEncoder.withIndent('  ').convert(manifest),
    ),
  );
  final output = File(p.join(root.path, '${_uuid()}.zip'));
  await output.writeAsBytes(ZipEncoder().encode(next), flush: true);
  return output;
}

Future<File> _createFormatOneBackup(Directory root) async {
  final dbFile = File(p.join(root.path, 'old-owntend.sqlite'));
  final oldDb = sqlite3.open(dbFile.path);
  try {
    _createV1Schema(oldDb);
  } finally {
    oldDb.close();
  }
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'app': 'Owntend',
          'format': 1,
          'schemaVersion': 1,
          'createdAt': DateTime(2026, 1, 1).toUtc().toIso8601String(),
          'database': AppDatabase.databaseFileName,
          'secretsIncluded': false,
        }),
      ),
    )
    ..addFile(
      ArchiveFile.bytes(
        AppDatabase.databaseFileName,
        await dbFile.readAsBytes(),
      ),
    );
  final backup = File(p.join(root.path, 'old-owntend.zip'));
  await backup.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return backup;
}

void _createV1Schema(Database database) {
  database
    ..execute('PRAGMA foreign_keys = OFF')
    ..execute('''
CREATE TABLE areas (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  kind TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''')
    ..execute('''
CREATE TABLE rooms (
  id TEXT NOT NULL PRIMARY KEY,
  area_id TEXT NOT NULL,
  name TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''')
    ..execute('''
CREATE TABLE categories (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  health_group TEXT NOT NULL,
  icon_name TEXT NOT NULL DEFAULT 'home',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''')
    ..execute('''
CREATE TABLE assets (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  category_id TEXT NOT NULL,
  room_id TEXT NOT NULL,
  asset_type TEXT NOT NULL DEFAULT 'general',
  notes TEXT NULL,
  purchase_date INTEGER NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  archived_at INTEGER NULL
)
''')
    ..execute('''
CREATE TABLE device_details (
  asset_id TEXT NOT NULL PRIMARY KEY,
  brand TEXT NULL,
  model TEXT NULL,
  serial_number TEXT NULL,
  power_source TEXT NULL,
  warranty_until INTEGER NULL,
  manual_url TEXT NULL,
  consumable INTEGER NOT NULL DEFAULT 0
)
''')
    ..execute('''
CREATE TABLE pet_details (
  asset_id TEXT NOT NULL PRIMARY KEY,
  species TEXT NULL,
  breed TEXT NULL,
  birth_date INTEGER NULL,
  microchip_id TEXT NULL,
  vet_name TEXT NULL,
  vet_phone TEXT NULL,
  feeding_notes TEXT NULL,
  medical_notes TEXT NULL
)
''')
    ..execute('''
CREATE TABLE plant_details (
  asset_id TEXT NOT NULL PRIMARY KEY,
  species TEXT NULL,
  sunlight TEXT NULL,
  watering_interval_days INTEGER NULL,
  pot_size TEXT NULL,
  last_repotted_at INTEGER NULL,
  toxicity_notes TEXT NULL
)
''')
    ..execute('''
CREATE TABLE safety_details (
  asset_id TEXT NOT NULL PRIMARY KEY,
  safety_type TEXT NULL,
  installed_at INTEGER NULL,
  expires_at INTEGER NULL,
  battery_type TEXT NULL,
  test_interval_days INTEGER NULL
)
''')
    ..execute('''
CREATE TABLE tags (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
)
''')
    ..execute('''
CREATE TABLE asset_tags (
  asset_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  PRIMARY KEY(asset_id, tag_id)
)
''')
    ..execute('''
CREATE TABLE asset_photos (
  id TEXT NOT NULL PRIMARY KEY,
  asset_id TEXT NOT NULL,
  relative_path TEXT NOT NULL,
  caption TEXT NULL,
  created_at INTEGER NOT NULL
)
''')
    ..execute('''
CREATE TABLE maintenance_plans (
  id TEXT NOT NULL PRIMARY KEY,
  asset_id TEXT NOT NULL,
  title TEXT NOT NULL,
  instructions TEXT NULL,
  recurrence_interval INTEGER NOT NULL,
  recurrence_unit TEXT NOT NULL,
  priority TEXT NOT NULL,
  next_due_date INTEGER NOT NULL,
  reminder_days_before INTEGER NOT NULL DEFAULT 0,
  health_group TEXT NOT NULL,
  is_enabled INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  archived_at INTEGER NULL
)
''')
    ..execute('''
CREATE TABLE maintenance_plan_metadata (
  plan_id TEXT NOT NULL PRIMARY KEY,
  task_type TEXT NULL,
  location_label TEXT NULL,
  estimated_duration_minutes INTEGER NULL,
  required_materials_json TEXT NOT NULL DEFAULT '[]',
  reminder_recommendation TEXT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0
)
''')
    ..execute('''
CREATE TABLE maintenance_records (
  id TEXT NOT NULL PRIMARY KEY,
  plan_id TEXT NOT NULL,
  due_date INTEGER NOT NULL,
  completed_at INTEGER NOT NULL,
  notes TEXT NULL
)
''')
    ..execute('''
CREATE TABLE notifications (
  id TEXT NOT NULL PRIMARY KEY,
  plan_id TEXT NOT NULL,
  channel TEXT NOT NULL,
  scheduled_for INTEGER NOT NULL,
  delivered_at INTEGER NULL,
  created_at INTEGER NOT NULL
)
''')
    ..execute('''
CREATE TABLE notification_inbox (
  id TEXT NOT NULL PRIMARY KEY,
  plan_id TEXT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  payload_json TEXT NULL,
  read_at INTEGER NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''')
    ..execute('''
CREATE TABLE settings (
  key TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)
''')
    ..execute('''
CREATE TABLE streaks (
  id TEXT NOT NULL PRIMARY KEY,
  current_streak INTEGER NOT NULL DEFAULT 0,
  best_streak INTEGER NOT NULL DEFAULT 0,
  last_completed_date INTEGER NULL,
  updated_at INTEGER NOT NULL
)
''')
    ..execute(
      "INSERT INTO areas(id, name, kind, sort_order, created_at, updated_at) VALUES "
      "('area_first_floor', 'First Floor', 'indoor', 0, 0, 0)",
    )
    ..execute(
      "INSERT INTO rooms(id, area_id, name, created_at, updated_at) VALUES "
      "('room_general', 'area_first_floor', 'General', 0, 0)",
    )
    ..execute(
      "INSERT INTO categories(id, name, health_group, icon_name, created_at, updated_at) VALUES "
      "('category_general', 'General', 'other', 'home', 0, 0)",
    )
    ..execute('PRAGMA user_version = 1');
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
