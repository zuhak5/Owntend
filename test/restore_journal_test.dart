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
  _FakeLocalSyncStore({this.boundUserId, this.generationMarker});

  final String? boundUserId;
  String? generationMarker;
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
      migrationState: 'active',
      restorePending: false,
      hydrationCompletedUnits: 0,
      hydrationTotalUnits: 0,
      updatedAt: now,
    );
  }

  @override
  Future<String?> readRestoreGenerationMarker() async => generationMarker;

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

  RestoreJournalEntry entryFor({
    required String journalId,
    required RestorePhase phase,
    String accountScope = 'user-a',
    String? mediaToken,
    bool updateCloudIntent = true,
    int version = kCurrentRestoreJournalVersion,
  }) {
    final now = DateTime.now();
    return RestoreJournalEntry(
      version: version,
      journalId: journalId,
      accountScope: accountScope,
      archivePath: '/tmp/backup.zip',
      archiveHash: 'hash-$journalId',
      mediaToken: mediaToken,
      phase: phase,
      updateCloudIntent: updateCloudIntent,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Builds the on-disk media state for one token. When [partialActivation]
  /// is true, `photos` has already been renamed into place (state b/c) while
  /// `profile` is still fully staged.
  Future<void> seedMediaState(
    String token, {
    required bool withStaged,
    required bool withLive,
    bool partialActivation = false,
  }) async {
    if (withLive) {
      final photosLive = Directory(p.join(docs.path, 'photos'))
        ..createSync(recursive: true);
      File(p.join(photosLive.path, 'old.jpg')).writeAsBytesSync([1]);
      if (!partialActivation) {
        final profileLive = Directory(p.join(docs.path, 'profile'))
          ..createSync(recursive: true);
        File(p.join(profileLive.path, 'old.png')).writeAsBytesSync([2]);
      }
    }
    if (withStaged) {
      final photosStaged = Directory(p.join(docs.path, 'photos.restore-$token'))
        ..createSync(recursive: true);
      File(p.join(photosStaged.path, 'new.jpg')).writeAsBytesSync([3]);
      if (!partialActivation) {
        final profileStaged = Directory(
          p.join(docs.path, 'profile.restore-$token'),
        )..createSync(recursive: true);
        File(p.join(profileStaged.path, 'new.png')).writeAsBytesSync([4]);
      }
    }
    if (partialActivation) {
      // State b for photos: died between the two renames.
      final photosStaged = Directory(p.join(docs.path, 'photos.restore-$token'))
        ..createSync(recursive: true);
      File(p.join(photosStaged.path, 'new.jpg')).writeAsBytesSync([3]);
      final photosPrevious = Directory(
        p.join(docs.path, 'photos.previous-$token'),
      )..createSync(recursive: true);
      File(p.join(photosPrevious.path, 'old.jpg')).writeAsBytesSync([1]);
      final profilePrevious = Directory(
        p.join(docs.path, 'profile.previous-$token'),
      )..createSync(recursive: true);
      File(p.join(profilePrevious.path, 'old.png')).writeAsBytesSync([2]);
      final profileStaged = Directory(
        p.join(docs.path, 'profile.restore-$token'),
      )..createSync(recursive: true);
      File(p.join(profileStaged.path, 'new.png')).writeAsBytesSync([4]);
    }
  }

  group('RestoreJournal & Store Tests', () {
    test('serializes and deserializes RestoreJournalEntry accurately', () {
      final now = DateTime.now();
      final entry = RestoreJournalEntry(
        version: kCurrentRestoreJournalVersion,
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

      expect(restored.version, kCurrentRestoreJournalVersion);
      expect(restored.journalId, equals('j-101'));
      expect(restored.accountScope, equals('user-a'));
      expect(restored.phase, equals(RestorePhase.mediaStaged));
      expect(restored.updateCloudIntent, isTrue);
      expect(restored.mediaToken, equals('token-xyz'));
    });

    test('durable store survives a new store instance', () async {
      final entry = entryFor(
        journalId: 'j-durable',
        phase: RestorePhase.servicesSuspended,
      );

      await RestoreJournalStore().saveEntry(entry);
      final afterRestart = await RestoreJournalStore().getActiveEntry();

      expect(afterRestart?.journalId, 'j-durable');
      expect(afterRestart?.phase, RestorePhase.servicesSuspended);
    });

    test('in-memory test store saves and clears active entry', () async {
      final store = InMemoryRestoreJournalStore();
      await store.saveEntry(
        entryFor(journalId: 'j-102', phase: RestorePhase.validated),
      );

      final active = await store.getActiveEntry();
      expect(active, isNotNull);
      expect(active!.journalId, equals('j-102'));

      await store.clearActiveEntry();
      expect(await store.getActiveEntry(), isNull);
    });
  });

  group('RestoreJournalResolver Tests', () {
    test('rolls back when the database did not commit even though the journal '
        'says dbCommitComplete', () async {
      final store = InMemoryRestoreJournalStore();
      final fakeSync = _FakeLocalSyncStore(boundUserId: 'user-a');
      const token = 'token-uncommitted';

      await seedMediaState(token, withStaged: true, withLive: true);
      await store.saveEntry(
        entryFor(
          journalId: 'j-uncommitted',
          phase: RestorePhase.dbCommitComplete,
          mediaToken: token,
        ),
      );

      await RestoreJournalResolver(
        journalStore: store,
        localSyncStore: fakeSync,
        documentsDirectory: () async => docs,
      ).resolveActiveJournal();

      expect(await store.getActiveEntry(), isNull);
      expect(
        Directory(p.join(docs.path, 'photos.restore-$token')).existsSync(),
        isFalse,
        reason: 'staged media must be removed',
      );
      expect(File(p.join(docs.path, 'photos', 'old.jpg')).readAsBytesSync(), [
        1,
      ], reason: 'canonical media must remain the complete old generation');
      expect(fakeSync.calls, isEmpty);
    });

    test('rolls forward on commit-marker proof even when the process died '
        'before persisting dbCommitComplete', () async {
      final store = InMemoryRestoreJournalStore();
      final fakeSync = _FakeLocalSyncStore(boundUserId: 'user-a')
        ..generationMarker = 'j-committed';
      const token = 'token-committed';

      await seedMediaState(token, withStaged: true, withLive: true);
      await store.saveEntry(
        entryFor(
          journalId: 'j-committed',
          phase: RestorePhase.dbCommitStarted,
          mediaToken: token,
        ),
      );

      await RestoreJournalResolver(
        journalStore: store,
        localSyncStore: fakeSync,
        documentsDirectory: () async => docs,
      ).resolveActiveJournal();

      expect(await store.getActiveEntry(), isNull);
      expect(File(p.join(docs.path, 'photos', 'new.jpg')).readAsBytesSync(), [
        3,
      ], reason: 'staged media must be activated after verified commit');
      expect(
        Directory(p.join(docs.path, 'photos.restore-$token')).existsSync(),
        isFalse,
      );
      expect(fakeSync.calls, ['enqueueRestoreSnapshot']);
    });

    test(
      'completes a partially activated media generation during roll-forward',
      () async {
        final store = InMemoryRestoreJournalStore();
        final fakeSync = _FakeLocalSyncStore(boundUserId: 'user-a')
          ..generationMarker = 'j-partial';
        const token = 'token-partial';

        await seedMediaState(
          token,
          withStaged: false,
          withLive: false,
          partialActivation: true,
        );
        await store.saveEntry(
          entryFor(
            journalId: 'j-partial',
            phase: RestorePhase.mediaActivated,
            mediaToken: token,
          ),
        );

        await RestoreJournalResolver(
          journalStore: store,
          localSyncStore: fakeSync,
          documentsDirectory: () async => docs,
        ).resolveActiveJournal();

        expect(File(p.join(docs.path, 'photos', 'new.jpg')).readAsBytesSync(), [
          3,
        ]);
        expect(
          File(p.join(docs.path, 'profile', 'new.png')).readAsBytesSync(),
          [4],
        );
        expect(fakeSync.calls, ['enqueueRestoreSnapshot']);
      },
    );

    test('rolls back pre-import phases and cleans staged media', () async {
      final store = InMemoryRestoreJournalStore();
      final fakeSync = _FakeLocalSyncStore(boundUserId: 'user-a');
      const token = 'token-pre';

      await seedMediaState(token, withStaged: true, withLive: true);
      await store.saveEntry(
        entryFor(
          journalId: 'j-pre',
          phase: RestorePhase.mediaStaged,
          mediaToken: token,
        ),
      );

      await RestoreJournalResolver(
        journalStore: store,
        localSyncStore: fakeSync,
        documentsDirectory: () async => docs,
      ).resolveActiveJournal();

      expect(await store.getActiveEntry(), isNull);
      expect(
        Directory(p.join(docs.path, 'photos.restore-$token')).existsSync(),
        isFalse,
      );
      expect(File(p.join(docs.path, 'photos', 'old.jpg')).existsSync(), isTrue);
      expect(fakeSync.calls, isEmpty);
    });

    test('rolls forward post-commit local-only pause after restart', () async {
      final store = InMemoryRestoreJournalStore();
      final fakeSync = _FakeLocalSyncStore(boundUserId: null)
        ..generationMarker = 'j-local-post';

      await store.saveEntry(
        entryFor(
          journalId: 'j-local-post',
          phase: RestorePhase.cloudIntentDurable,
          accountScope: 'localOnly',
          updateCloudIntent: false,
        ),
      );

      await RestoreJournalResolver(
        journalStore: store,
        localSyncStore: fakeSync,
        documentsDirectory: () async => docs,
      ).resolveActiveJournal();

      expect(await store.getActiveEntry(), isNull);
      expect(fakeSync.calls, ['pauseAfterLocalRestore']);
    });

    test(
      'fails closed when recovery account differs from local binding',
      () async {
        final store = InMemoryRestoreJournalStore();
        final fakeSync = _FakeLocalSyncStore(boundUserId: 'user-b')
          ..generationMarker = 'j-mismatch';

        await store.saveEntry(
          entryFor(
            journalId: 'j-mismatch',
            phase: RestorePhase.dbCommitComplete,
          ),
        );

        await expectLater(
          RestoreJournalResolver(
            journalStore: store,
            localSyncStore: fakeSync,
            documentsDirectory: () async => docs,
          ).resolveActiveJournal(),
          throwsA(isA<StateError>()),
        );

        expect((await store.getActiveEntry())?.journalId, 'j-mismatch');
        expect(fakeSync.calls, isEmpty);
      },
    );

    test('blocks startup on unsupported future journal version', () async {
      final store = InMemoryRestoreJournalStore();
      await store.saveEntry(
        entryFor(
          journalId: 'j-future',
          phase: RestorePhase.mediaStaged,
          version: 99,
        ),
      );

      await expectLater(
        RestoreJournalResolver(
          journalStore: store,
          localSyncStore: _FakeLocalSyncStore(),
          documentsDirectory: () async => docs,
        ).resolveActiveJournal(),
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

    test(
      'rejects retired journal formats without a compatibility ladder',
      () async {
        final store = InMemoryRestoreJournalStore();
        await store.saveEntry(
          entryFor(
            journalId: 'j-legacy',
            phase: RestorePhase.dbCommitStarted,
            version: 1,
          ),
        );

        await expectLater(
          RestoreJournalResolver(
            journalStore: store,
            localSyncStore: _FakeLocalSyncStore(generationMarker: 'j-legacy'),
            documentsDirectory: () async => docs,
          ).resolveActiveJournal(),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}
