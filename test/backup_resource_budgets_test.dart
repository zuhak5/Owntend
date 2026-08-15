import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/services/backup_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('Backup Resource Budgets & Hostile Corpus Tests', () {
    late Directory root;
    late Directory docs;
    late Directory temp;
    late AppDatabase db;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('owntend_budget_test_');
      docs = Directory(p.join(root.path, 'docs'))..createSync(recursive: true);
      temp = Directory(p.join(root.path, 'temp'))..createSync(recursive: true);
      PathProviderPlatform.instance = _FakePathProviderPlatform(
        documentsPath: docs.path,
        temporaryPath: temp.path,
      );
      db = AppDatabase(executor: NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('isAllowedBackupPathForTest allows valid photo paths', () {
      final service = ZipBackupService(db);
      expect(service.isAllowedBackupPathForTest('photos/bomb.jpg'), isTrue);
    });

    test(
      'valid archive within budget limits passes inspectBackup validation',
      () async {
        final service = ZipBackupService(db);
        final zipPath = await service.exportBackup();
        expect(File(zipPath).existsSync(), isTrue);

        final preview = await service.inspectBackup(zipPath);
        expect(preview, isNotNull);
        expect(preview.backupSizeBytes, greaterThan(0));
      },
    );

    test(
      'rejects archive with excessive compression ratio (ZIP bomb)',
      () async {
        final service = ZipBackupService(db);
        final archive = Archive();
        archive.addFile(
          ArchiveFile(
            'manifest.json',
            30,
            utf8.encode('{"app":"Owntend","format":1}'),
          ),
        );
        archive.addFile(
          ArchiveFile('owntend.sqlite', 20, utf8.encode('SQLite format 3\x00')),
        );

        final bombBytes = List<int>.filled(100, 0);
        final bombEntry = ArchiveFile('photos/bomb.jpg', 50000000, bombBytes);
        archive.addFile(bombEntry);

        expect(
          () => service.validateArchivePathsForTest(archive),
          throwsA(
            isA<BackupException>().having(
              (e) => e.message,
              'message',
              contains('compression ratio'),
            ),
          ),
        );
      },
    );

    test('rejects archive exceeding max entry count limit', () async {
      final service = ZipBackupService(db);
      final archive = Archive();
      archive.addFile(
        ArchiveFile(
          'manifest.json',
          30,
          utf8.encode('{"app":"Owntend","format":1}'),
        ),
      );
      archive.addFile(
        ArchiveFile('owntend.sqlite', 20, utf8.encode('SQLite format 3\x00')),
      );

      for (var i = 0; i < 10001; i++) {
        archive.addFile(ArchiveFile('photos/file_$i.jpg', 1, [0]));
      }

      final zipBytes = ZipEncoder().encode(archive);
      final zipFile = File(p.join(temp.path, 'too_many_entries.zip'));
      await zipFile.writeAsBytes(zipBytes);

      expect(
        () async => service.inspectBackup(zipFile.path),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            contains('too many entries'),
          ),
        ),
      );
    });

    test('rejects archive with declared vs actual size mismatch', () async {
      final service = ZipBackupService(db);
      final archive = Archive();
      archive.addFile(
        ArchiveFile(
          'manifest.json',
          30,
          utf8.encode('{"app":"Owntend","format":1}'),
        ),
      );
      archive.addFile(
        ArchiveFile('owntend.sqlite', 20, utf8.encode('SQLite format 3\x00')),
      );

      final badEntry = ArchiveFile(
        'photos/bad.jpg',
        500,
        List<int>.filled(10, 0),
      );
      archive.addFile(badEntry);

      final zipBytes = ZipEncoder().encode(archive);
      final zipFile = File(p.join(temp.path, 'mismatch.zip'));
      await zipFile.writeAsBytes(zipBytes);

      expect(
        () async => service.restoreBackup(zipFile.path),
        throwsA(isA<BackupException>()),
      );
    });
  });
}
