import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/services/restore_journal.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
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

class _FakeLocalSyncStore implements LocalSyncStore {
  final List<String> calls = [];

  @override
  Future<void> enqueueRestoreSnapshot(DateTime timestamp) async {
    calls.add('enqueueRestoreSnapshot');
  }

  @override
  Future<void> pauseAfterLocalRestore() async {
    calls.add('pauseAfterLocalRestore');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory docs;
  late Directory temp;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('owntend_restore_test_');
    docs = Directory(p.join(root.path, 'docs'))..createSync(recursive: true);
    temp = Directory(p.join(root.path, 'temp'))..createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProviderPlatform(
      documentsPath: docs.path,
      temporaryPath: temp.path,
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  group('RestoreJournal & Store Tests', () {
    test('serializes and deserializes RestoreJournalEntry accurately', () {
      final now = DateTime.now();
      final entry = RestoreJournalEntry(
        version: 1,
        journalId: 'j-101',
        accountScope: 'user-a',
        archivePath: '/tmp/backup.zip',
        archiveHash: 'hash-abc',
        safetyBackupPath: '/tmp/safety.zip',
        safetyBackupHash: 'hash-safety',
        mediaToken: 'token-xyz',
        phase: RestorePhase.mediaStaged,
        updateCloudIntent: true,
        createdAt: now,
        updatedAt: now,
      );

      final json = entry.toJson();
      final restored = RestoreJournalEntry.fromJson(json);

      expect(restored.version, equals(1));
      expect(restored.journalId, equals('j-101'));
      expect(restored.accountScope, equals('user-a'));
      expect(restored.phase, equals(RestorePhase.mediaStaged));
      expect(restored.updateCloudIntent, isTrue);
      expect(restored.mediaToken, equals('token-xyz'));
    });

    test('RestoreJournalStore saves and clears active entry', () async {
      final store = RestoreJournalStore();
      final now = DateTime.now();
      final entry = RestoreJournalEntry(
        version: 1,
        journalId: 'j-102',
        accountScope: 'localOnly',
        archivePath: '/tmp/test.zip',
        archiveHash: 'hash-102',
        phase: RestorePhase.validated,
        updateCloudIntent: false,
        createdAt: now,
        updatedAt: now,
      );

      await store.saveEntry(entry);
      final active = await store.getActiveEntry();
      expect(active, isNotNull);
      expect(active!.journalId, equals('j-102'));
      expect(active.phase, equals(RestorePhase.validated));

      await store.clearActiveEntry();
      expect(await store.getActiveEntry(), isNull);
    });
  });

  group('RestoreJournalResolver Tests', () {
    test('rolls back pre-DB-commit state (phase < dbCommitStarted)', () async {
      final store = RestoreJournalStore();
      final fakeSync = _FakeLocalSyncStore();
      final now = DateTime.now();

      final stagedDir = Directory(
        p.join(docs.path, 'photos.restore-token-pre'),
      );
      await stagedDir.create(recursive: true);
      expect(await stagedDir.exists(), isTrue);

      final entry = RestoreJournalEntry(
        version: 1,
        journalId: 'j-pre',
        accountScope: 'localOnly',
        archivePath: '/tmp/pre.zip',
        archiveHash: 'hash-pre',
        mediaToken: 'token-pre',
        phase: RestorePhase.mediaStaged,
        updateCloudIntent: false,
        createdAt: now,
        updatedAt: now,
      );
      await store.saveEntry(entry);

      final resolver = RestoreJournalResolver(
        journalStore: store,
        localSyncStore: fakeSync,
      );

      await resolver.resolveActiveJournal();

      expect(await store.getActiveEntry(), isNull);
      expect(await stagedDir.exists(), isFalse);
      expect(fakeSync.calls, isEmpty);
    });

    test(
      'rolls forward post-commit state (phase >= dbCommitStarted)',
      () async {
        final store = RestoreJournalStore();
        final fakeSync = _FakeLocalSyncStore();
        final now = DateTime.now();

        final entry = RestoreJournalEntry(
          version: 1,
          journalId: 'j-post',
          accountScope: 'user-a',
          archivePath: '/tmp/post.zip',
          archiveHash: 'hash-post',
          mediaToken: 'token-post',
          phase: RestorePhase.dbCommitComplete,
          updateCloudIntent: true,
          createdAt: now,
          updatedAt: now,
        );
        await store.saveEntry(entry);

        final resolver = RestoreJournalResolver(
          journalStore: store,
          localSyncStore: fakeSync,
        );

        await resolver.resolveActiveJournal();

        expect(await store.getActiveEntry(), isNull);
        expect(fakeSync.calls, contains('enqueueRestoreSnapshot'));
      },
    );

    test('blocks startup on unsupported future journal version', () async {
      final store = RestoreJournalStore();
      final now = DateTime.now();

      final entry = RestoreJournalEntry(
        version: 99,
        journalId: 'j-future',
        accountScope: 'localOnly',
        archivePath: '/tmp/future.zip',
        archiveHash: 'hash-future',
        phase: RestorePhase.mediaStaged,
        updateCloudIntent: false,
        createdAt: now,
        updatedAt: now,
      );
      await store.saveEntry(entry);

      final resolver = RestoreJournalResolver(
        journalStore: store,
        localSyncStore: null,
      );

      expect(
        () async => resolver.resolveActiveJournal(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('newer than supported'),
          ),
        ),
      );
    });
  });
}
