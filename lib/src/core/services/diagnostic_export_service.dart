import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:uuid/uuid.dart';

import '../utils/redacting_logger.dart';

const diagnosticConsentDisclosure =
    'This bundle contains only Owntend diagnostic events and redacted '
    'technical metadata. It does not include full system logs.';

abstract final class AppDiagnosticRuntime {
  static AppDiagnosticFileStore? fileStore;
}

class DiagnosticExportService {
  DiagnosticExportService({
    AppDiagnosticFileStore? fileStore,
    Future<Directory> Function()? temporaryDirectory,
    Future<PackageInfo> Function()? packageInfo,
    ShorebirdUpdater? updater,
  }) : _fileStore = fileStore ?? AppDiagnosticRuntime.fileStore,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _packageInfo = packageInfo ?? PackageInfo.fromPlatform,
       _updater = updater ?? ShorebirdUpdater();

  static const retention = Duration(hours: 24);
  static const redactionVersion = 1;
  static const _uuid = Uuid();

  final AppDiagnosticFileStore? _fileStore;
  final Future<Directory> Function() _temporaryDirectory;
  final Future<PackageInfo> Function() _packageInfo;
  final ShorebirdUpdater _updater;

  Future<File> export() async {
    final createdAt = DateTime.now().toUtc();
    final temporary = await _temporaryDirectory();
    final directory = Directory(p.join(temporary.path, 'owntend-diagnostics'));
    await directory.create(recursive: true);
    await cleanupExpired(now: createdAt);

    final events = AppLogger.snapshot();
    final errors = AppLogger.snapshot(errorsOnly: true);
    final eventBytes = utf8.encode(
      events.map((event) => jsonEncode(event.toJson())).join('\n'),
    );
    final errorBytes = utf8.encode(
      errors.map((event) => jsonEncode(event.toJson())).join('\n'),
    );
    final fileEntries = <String, List<int>>{
      'events.jsonl': eventBytes,
      'errors.jsonl': errorBytes,
    };

    final sourceFiles = await _fileStore?.files() ?? const <File>[];
    for (final source in sourceFiles) {
      fileEntries['rotated/${p.basename(source.path)}'] = await source
          .readAsBytes();
    }
    final archive = Archive();
    for (final entry in fileEntries.entries) {
      archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
    }

    final info = await _packageInfo();
    String shorebirdPatchNumber = 'base';
    var shorebirdAvailable = false;
    try {
      shorebirdAvailable = _updater.isAvailable;
      if (shorebirdAvailable) {
        final currentPatch = await _updater.readCurrentPatch();
        shorebirdPatchNumber = currentPatch?.number.toString() ?? 'base';
      }
    } on Object {
      // safe fallback
    }

    final manifest = <String, Object?>{
      'app': 'Owntend',
      'version': info.version,
      'buildNumber': info.buildNumber,
      'shorebirdPatchNumber': shorebirdPatchNumber,
      'shorebirdAvailable': shorebirdAvailable,
      'os': Platform.operatingSystem,
      'osVersion': redactDiagnosticValue(Platform.operatingSystemVersion),
      'timezone': DateTime.now().timeZoneName,
      'captureEnd': createdAt.toIso8601String(),
      'captureStart': events.isEmpty
          ? createdAt.toIso8601String()
          : events.first.timestamp.toUtc().toIso8601String(),
      'redactionVersion': redactionVersion,
      'appScoped': true,
      'cleanupForceStop': false,
      'consentDisclosure': diagnosticConsentDisclosure,
      'files': [
        for (final entry in fileEntries.entries)
          {
            'path': entry.key,
            'bytes': entry.value.length,
            'sha256': sha256.convert(entry.value).toString(),
          },
      ],
    };
    archive.addFile(
      ArchiveFile.string(
        'manifest.json',
        const JsonEncoder.withIndent('  ').convert(manifest),
      ),
    );

    final output = File(
      p.join(
        directory.path,
        'owntend-${createdAt.microsecondsSinceEpoch}-${_uuid.v7()}.zip',
      ),
    );
    await output.writeAsBytes(ZipEncoder().encode(archive), flush: true);
    return output;
  }

  Future<void> cleanupExpired({DateTime? now}) async {
    final temporary = await _temporaryDirectory();
    final directory = Directory(p.join(temporary.path, 'owntend-diagnostics'));
    if (!await directory.exists()) return;
    final cutoff = (now ?? DateTime.now().toUtc()).subtract(retention);
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || p.extension(entity.path) != '.zip') continue;
      final modified = await entity.lastModified();
      if (modified.toUtc().isBefore(cutoff)) {
        await entity.delete();
      }
    }
  }
}
