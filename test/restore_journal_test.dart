import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
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
  _FakeLocalSyncStore({this.boundUserId});

  final String? boundUserId;
  final List<String> calls = [];

  @override
  Future<SyncAccountData?> existingAccount() async {
    final userId = boundUserId;
    if (userId == null) return null;
    final now = DateTime.now();
    return SyncAccountData(
      id: 1,
      deviceId: 'device-test',
      enabled: true,
      boundUserId: userId,
      uploadProhibited: false,
      migrationState: 'active',
      restorePending: false,
      hydrationCompletedUnits: 0,
      hydrationTotalUnits: 0,
      updatedAt: now,
    );
  }

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
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
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

    test('durable store survives a new store instance', () async {
      final now = DateTime.now();
      final entry = RestoreJournalEntry(
        version: 1,
        journalId: 'j-durable',
        accountScope: 'user-a',
        archivePath: '/tmp/durable.zip',
        archiveHash: 'hash-durable',
        phase: RestorePhase.servicesSuspended,
        updateCloudIntent: true,
        createdAt: now,
        updatedAt: now,
      );

      await RestoreJournalStore().saveEntry(entry);
      final afterRestart = await RestoreJournalStore().getActiveEntry();

      expect(afterRestart?.journalId, 'j-durable');
      expect(afterRestart?.phase, RestorePhase.servicesSuspended);
      expect(afterRestart?.accountScope, 'user-a');
      expect(afterRestart?.updateCloudIntent, isTrue);
    });

    test('in-memory test store saves and clears active entry', () async {
      final store = InMemoryRestoreJournalStore();
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
    test('rolls back pre-DB-commit state after restart', () async {
      final store = InMemoryRestoreJournalStore();
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

    test('rolls forward post-commit cloud intent after restart', () async {
      final store = InMemoryRestoreJournalStore();
      final fakeSync = _FakeLocalSyncStore(boundUserId: 'user-a');
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
      expect(fakeSync.calls, ['enqueueRestoreSnapshot']);
    });

    test('rolls forward post-commit local-only pause after restart', () async {
      final store = InMemoryRestoreJournalStore();
      final fakeSync = _FakeLocalSyncStore();
      final now = DateTime.now();

      await store.saveEntry(
        RestoreJournalEntry(
          version: 1,
          journalId: 'j-local-post',
          accountScope: 'localOnly',
          archivePath: '/tmp/local-post.zip',
          archiveHash: 'hash-local-post',
          phase: RestorePhase.mediaSwapped,
          updateCloudIntent: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await RestoreJournalResolver(
        journalStore: store,
        localSyncStore: fakeSync,
      ).resolveActiveJournal();

      expect(await store.getActiveEntry(), isNull);
      expect(fakeSync.calls, ['pauseAfterLocalRestore']);
    });

    test('fails closed when recovery account differs from local binding', () async {
      final store = InMemoryRestoreJournalStore();
      final fakeSync = _FakeLocalSyncStore(boundUserId: 'user-b');
      final now = DateTime.now();
      final entry = RestoreJournalEntry(
        version: 1,
        journalId: 'j-mismatch',
        accountScope: 'user-a',
        archivePath: '/tmp/mismatch.zip',
        archiveHash: 'hash-mismatch',
        phase: RestorePhase.dbCommitComplete,
        updateCloudIntent: true,
        createdAt: now,
        updatedAt: now,
      );
      await store.saveEntry(entry);

      await expectLater(
        RestoreJournalResolver(
          journalStore: store,
          localSyncStore: fakeSync,
        ).resolveActiveJournal(),
        throwsA(isA<StateError>()),
      );

      expect((await store.getActiveEntry())?.journalId, 'j-mismatch');
      expect(fakeSync.calls, isEmpty);
    });

    test('blocks startup on unsupported future journal version', () async {
      final store = InMemoryRestoreJournalStore();
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

      await expectLater(
        resolver.resolveActiveJournal(),
        throwsA(
          isA<StateError>().having(
            (e) => e.toString(),
            'message',
            contains('newer than supported'),
          ),
        ),
      );
      expect((await store.getActiveEntry())?.journalId, 'j-future');
    });
  });
}
