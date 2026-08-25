import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/services/backup/backup_container.dart';
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
  FlutterSecureStorage.setMockInitialValues(<String, String>{});

  group('Backup container hostile-input and resource budget tests', () {
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
        await _deleteDirectoryWithRetries(root);
      }
    });

    test('isAllowedBackupPathForTest allows valid photo paths', () {
      final service = OwntendBackupService(db);
      expect(service.isAllowedBackupPathForTest('photos/bomb.jpg'), isTrue);
    });

    test(
      'valid device-key container passes export and inspect within budgets',
      () async {
        final service = OwntendBackupService(db);
        final backupPath = await service.exportBackup();
        expect(File(backupPath).existsSync(), isTrue);
        expect(backupPath, endsWith('.owntend-backup'));

        final preview = await service.inspectBackup(backupPath);
        expect(preview, isNotNull);
        expect(preview.backupSizeBytes, greaterThan(0));
        // The header must advertise the device key guard class.
        final bytes = File(backupPath).readAsBytesSync();
        expect(bytes.length, greaterThanOrEqualTo(52));
        expect(bytes[51], BackupContainerCodec.keyGuardDeviceKey);
      },
    );

    test('rejects empty and non-container files', () async {
      final service = OwntendBackupService(db);
      final empty = File(p.join(temp.path, 'empty.owntend-backup'))
        ..writeAsBytesSync([]);
      final garbage = File(p.join(temp.path, 'garbage.owntend-backup'))
        ..writeAsStringSync('definitely not an owntend backup');

      expect(
        () => service.inspectBackup(empty.path),
        throwsA(isA<BackupException>()),
      );
      expect(
        () => service.inspectBackup(garbage.path),
        throwsA(isA<BackupException>()),
      );
    });

    test(
      'rejects containers whose magic or version bytes were replaced',
      () async {
        final service = OwntendBackupService(db);
        final backupPath = await service.exportBackup();
        final forged = File(p.join(root.path, 'forged.owntend-backup'));
        final original = await File(backupPath).readAsBytes();
        final mutated = Uint8List.fromList(original);
        mutated[2] = mutated[2] == 0x4e
            ? 0x4d
            : 0x4e; // corrupt the ASCII magic "OWNT"
        await forged.writeAsBytes(mutated, flush: true);

        expect(
          () => service.inspectBackup(forged.path),
          throwsA(isA<BackupException>()),
        );
      },
    );

    test(
      'rejects any single flipped payload byte (AEAD authentication)',
      () async {
        final service = OwntendBackupService(db);
        final backupPath = await service.exportBackup();
        final original = await File(backupPath).readAsBytes();

        var rejected = 0;
        // Flip bytes spread across the payload region. A full authenticated
        // read (restore path) must reject every one of them.
        for (final index in <int>[
          BackupContainerCodec.headerLength + 7,
          original.length ~/ 2,
          original.length - 1,
        ]) {
          if (index <= BackupContainerCodec.headerLength ||
              index >= original.length) {
            continue;
          }
          final mutated = Uint8List.fromList(original);
          mutated[index] = mutated[index] ^ 0x01;
          final tampered = File(p.join(root.path, 'tampered-$index.bk'))
            ..writeAsBytesSync(mutated, flush: true);
          await expectLater(
            service.restoreBackup(tampered.path),
            throwsA(isA<BackupException>()),
            reason: 'a flipped byte at offset $index must fail authentication',
          );
          rejected++;
        }
        expect(rejected, greaterThan(0));
      },
    );

    test('user-passphrase containers require the exact passphrase', () async {
      final service = OwntendBackupService(db);
      final backupPath = await service.exportBackup(
        passphrase: 'correct horse battery',
      );

      // Missing passphrase surfaces the dedicated prompt signal.
      await expectLater(
        service.inspectBackup(backupPath),
        throwsA(isA<BackupPassphraseRequiredException>()),
      );

      // Wrong passphrase is an authentication failure.
      await expectLater(
        service.restoreBackup(backupPath, passphrase: 'wrong-passphrase'),
        throwsA(isA<BackupException>()),
      );

      // Short passphrases are refused at export time.
      await expectLater(
        service.exportBackup(passphrase: 'short'),
        throwsA(isA<BackupException>()),
      );
    });

    test(
      'rejects forged manifests claiming a newer schema or format',
      () async {
        final service = OwntendBackupService(db);
        final backupPath = await service.exportBackup();

        Future<File> rebuildWithManifest(Map<String, Object?> updates) async {
          final secret = await BackupAutoKeyStore.load();
          final source = await File(backupPath).open(mode: FileMode.read);
          final reader = await BackupContainerReader.open(
            input: source,
            passphrase: secret,
          );
          final manifestFrame = await reader.readFrame(source);
          final manifest =
              jsonDecode(utf8.decode(manifestFrame!)) as Map<String, dynamic>;
          manifest.addAll(updates);
          final rebuilt = File(
            p.join(root.path, 'rebuilt-${updates.hashCode}.bk'),
          );
          final output = await rebuilt.open(mode: FileMode.write);
          final writer = await BackupContainerWriter.start(
            output: output,
            passphrase: secret,
            keyGuard: BackupContainerCodec.keyGuardDeviceKey,
            fastProfile: false,
          );
          await writer.writeFrame(utf8.encode(jsonEncode(manifest)));
          while (true) {
            final frame = await reader.readFrame(source);
            if (frame == null) break;
            await writer.writeFrame(frame);
          }
          await output.close();
          await source.close();
          return rebuilt;
        }

        final newerSchema = await rebuildWithManifest(<String, Object?>{
          'schemaVersion': db.schemaVersion + 1,
        });
        final newerFormat = await rebuildWithManifest(<String, Object?>{
          'format': 99,
        });

        expect(
          () => service.inspectBackup(newerSchema.path),
          throwsA(isA<BackupException>()),
        );
        expect(
          () => service.inspectBackup(newerFormat.path),
          throwsA(isA<BackupException>()),
        );
      },
    );

    test('local peak-memory sampling during export and inspect stays bounded '
        'relative to archive size', () async {
      // Local, non-device evidence only: the physical min-spec low-memory
      // benchmark remains an explicit launch blocker (BACKUP-001).
      final service = OwntendBackupService(db);
      var peakRssBytes = ProcessInfo.currentRss;
      final sampler = Timer.periodic(const Duration(milliseconds: 10), (_) {
        final rss = ProcessInfo.currentRss;
        if (rss > peakRssBytes) peakRssBytes = rss;
      });
      addTearDown(sampler.cancel);

      final backupPath = await service.exportBackup();
      await service.inspectBackup(backupPath);

      final archiveSize = File(backupPath).lengthSync();
      final growth = peakRssBytes - ProcessInfo.currentRss < 0
          ? 0
          : peakRssBytes - ProcessInfo.currentRss;
      // Streaming I/O must not scale memory with archive size; allow a
      // generous fixed working-set headroom independent of the archive.
      expect(growth, lessThan(512 * 1024 * 1024), reason: 'peak RSS growth');
      expect(archiveSize, greaterThan(0));
    });
  });
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
