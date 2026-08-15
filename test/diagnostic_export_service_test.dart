import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/services/diagnostic_export_service.dart';
import 'package:owntend/src/core/utils/redacting_logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    AppLogger.clearForTesting();
    AppLogger.clearEventSinksForTesting();
    temporary = await Directory.systemTemp.createTemp(
      'owntend-diagnostics-test-',
    );
  });

  tearDown(() async {
    AppLogger.clearEventSinksForTesting();
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test(
    'export is app-scoped, redacted, and has a nonempty error stream',
    () async {
      AppLogger.info(
        'sync_started',
        fields: {
          'nested': {
            'email': 'person@example.test',
            'url': 'https://example.test/path?token=secret',
            'serial': 'ADB-RAW-SERIAL',
          },
          'operation': 'cb7d7772-9ab1-4e52-a6b2-b620d21e7777',
        },
      );
      AppLogger.warning(
        'sync_failed',
        error: StateError('Bearer eyJabcdefghijklmnopqrstuv'),
      );
      final service = DiagnosticExportService(
        temporaryDirectory: () async => temporary,
        packageInfo: () async => PackageInfo(
          appName: 'Owntend',
          packageName: 'app.owntend.mobile',
          version: '1.0.0',
          buildNumber: '1',
        ),
      );

      final zip = await service.export();
      final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
      final events = utf8.decode(archive.findFile('events.jsonl')!.content);
      final errors = utf8.decode(archive.findFile('errors.jsonl')!.content);
      final manifest = utf8.decode(archive.findFile('manifest.json')!.content);
      final combined = '$events\n$errors\n$manifest';

      expect(errors.trim(), isNotEmpty);
      expect(combined, contains('sync_failed'));
      expect(combined, isNot(contains('person@example.test')));
      expect(combined, isNot(contains('ADB-RAW-SERIAL')));
      expect(combined, isNot(contains('eyJabcdefghijklmnopqrstuv')));
      expect(combined, isNot(contains('cb7d7772-9ab1-4e52-a6b2-b620d21e7777')));
      expect(combined, isNot(contains('com.unrelated.application')));
      expect(manifest, contains('"cleanupForceStop": false'));
      expect(manifest, contains('"appScoped": true'));
    },
  );

  test('expired temporary diagnostic bundles are deleted', () async {
    final directory = Directory(
      '${temporary.path}${Platform.pathSeparator}owntend-diagnostics',
    );
    await directory.create(recursive: true);
    final old = File('${directory.path}${Platform.pathSeparator}old.zip');
    await old.writeAsBytes([1]);
    await old.setLastModified(DateTime.now().subtract(const Duration(days: 2)));
    final service = DiagnosticExportService(
      temporaryDirectory: () async => temporary,
      packageInfo: () async => PackageInfo(
        appName: 'Owntend',
        packageName: 'app.owntend.mobile',
        version: '1.0.0',
        buildNumber: '1',
      ),
    );

    await service.cleanupExpired();

    expect(await old.exists(), isFalse);
  });

  test('nested diagnostic metadata and URLs are redacted recursively', () {
    final redacted = redactDiagnosticValue({
      'profile': {
        'email': 'person@example.test',
        'links': ['https://example.test/private?token=secret'],
      },
      'latitude': 33.31,
    }) as Map<String, Object?>;

    expect(jsonEncode(redacted), isNot(contains('person@example.test')));
    expect(jsonEncode(redacted), isNot(contains('example.test')));
    expect(jsonEncode(redacted), isNot(contains('33.31')));
  });
}
