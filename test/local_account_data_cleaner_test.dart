import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/features/auth/data/local_account_data_cleaner.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  late AppDatabase database;
  late LocalSyncStore store;
  late Directory temporaryRoot;
  late Directory documents;
  late Directory cache;
  late LocalAccountDataCleaner cleaner;

  setUp(() async {
    database = AppDatabase(executor: NativeDatabase.memory());
    store = LocalSyncStore(database);
    temporaryRoot = await Directory.systemTemp.createTemp(
      'owntend-account-cleaner-',
    );
    documents = Directory(p.join(temporaryRoot.path, 'documents'));
    cache = Directory(p.join(temporaryRoot.path, 'cache'));
    await documents.create(recursive: true);
    await cache.create(recursive: true);
    cleaner = LocalAccountDataCleaner(
      store,
      documentsDirectory: () async => documents,
      cacheDirectory: () async => cache,
    );
  });

  tearDown(() async {
    await database.close();
    if (await temporaryRoot.exists()) {
      await temporaryRoot.delete(recursive: true);
    }
  });

  test(
    'clears bound database rows, media, caches, and local backups',
    () async {
      await _seedBoundAccountData(database, store, 'user-1');
      await _writePrivateFile(documents, 'photos/item/photo.jpg');
      await _writePrivateFile(documents, 'cloud_media/item/cached.jpg');
      await _writePrivateFile(documents, 'backups/owntend-manual.zip');
      await _writePrivateFile(documents, 'owntend-backup-state.json');
      await _writePrivateFile(cache, 'avatars/avatar.bin');

      await cleaner.clearAfterCloudDeletion('user-1');

      expect(
        await (database.select(
          database.areas,
        )..where((area) => area.id.equals('private-area'))).get(),
        isEmpty,
      );
      expect(await store.pendingCount(), 0);
      expect(
        await database.select(database.reminderScheduleSnapshots).get(),
        isEmpty,
      );
      expect(await database.select(database.inboxNotifications).get(), isEmpty);
      final account = await store.account();
      expect(account.boundUserId, isNull);
      expect(account.enabled, isFalse);
      expect(
        await Directory(p.join(documents.path, 'photos')).exists(),
        isFalse,
      );
      expect(
        await Directory(p.join(documents.path, 'cloud_media')).exists(),
        isFalse,
      );
      expect(
        await Directory(p.join(documents.path, 'backups')).exists(),
        isFalse,
      );
      expect(
        await File(p.join(documents.path, 'owntend-backup-state.json'))
            .exists(),
        isFalse,
      );
      expect(await Directory(p.join(cache.path, 'avatars')).exists(), isFalse);
      expect(
        await File(
          p.join(documents.path, '.owntend-account-deletion-cleanup-pending'),
        ).exists(),
        isFalse,
      );
    },
  );

  test('refuses to clear data bound to a different account', () async {
    await _seedBoundAccountData(database, store, 'user-1');

    await expectLater(
      cleaner.clearAfterCloudDeletion('user-2'),
      throwsStateError,
    );

    expect(
      await (database.select(
        database.areas,
      )..where((area) => area.id.equals('private-area'))).get(),
      hasLength(1),
    );
    expect(
      await File(
        p.join(documents.path, '.owntend-account-deletion-cleanup-pending'),
      ).exists(),
      isFalse,
    );
  });

  test('resumes a previously authorized cleanup from its marker', () async {
    await _seedBoundAccountData(database, store, 'user-1');
    await File(
      p.join(documents.path, '.owntend-account-deletion-cleanup-pending'),
    ).writeAsString('user-1');

    expect(await cleaner.resumePendingCleanup(), isTrue);
    expect(
      await (database.select(
        database.areas,
      )..where((area) => area.id.equals('private-area'))).get(),
      isEmpty,
    );
    expect((await store.account()).boundUserId, isNull);
    expect(await cleaner.resumePendingCleanup(), isFalse);
  });

  test(
    'refuses marker cleanup when a different account is currently bound',
    () async {
      await _seedBoundAccountData(database, store, 'user-2');
      final marker = File(
        p.join(documents.path, '.owntend-account-deletion-cleanup-pending'),
      );
      await marker.writeAsString('user-1');
      final privateFile = await _writePrivateFile(
        documents,
        'photos/private/photo.jpg',
      );
      var additionalCleanupCalled = false;

      await expectLater(
        cleaner.resumePendingCleanup(
          additionalCleanup: (_) async {
            additionalCleanupCalled = true;
          },
        ),
        throwsStateError,
      );

      expect(
        await (database.select(
          database.areas,
        )..where((area) => area.id.equals('private-area'))).get(),
        hasLength(1),
      );
      expect((await store.account()).boundUserId, 'user-2');
      expect(await privateFile.exists(), isTrue);
      expect(await marker.exists(), isTrue);
      expect(additionalCleanupCalled, isFalse);
    },
  );

  test(
    'refuses marker cleanup for unbound non-pristine local data',
    () async {
      await database
          .into(database.areas)
          .insert(
            AreasCompanion.insert(
              id: 'private-area',
              name: 'Private area',
              kind: 'indoor',
            ),
          );
      final marker = File(
        p.join(documents.path, '.owntend-account-deletion-cleanup-pending'),
      );
      await marker.writeAsString('user-1');
      final privateFile = await _writePrivateFile(
        documents,
        'photos/private/photo.jpg',
      );
      var additionalCleanupCalled = false;

      await expectLater(
        cleaner.resumePendingCleanup(
          additionalCleanup: (_) async {
            additionalCleanupCalled = true;
          },
        ),
        throwsStateError,
      );

      expect(await store.existingAccount(), isNull);
      expect(
        await (database.select(
          database.areas,
        )..where((area) => area.id.equals('private-area'))).get(),
        hasLength(1),
      );
      expect(await privateFile.exists(), isTrue);
      expect(await marker.exists(), isTrue);
      expect(additionalCleanupCalled, isFalse);
    },
  );

  for (final invalidMarker in ['', 'pending']) {
    test(
      'refuses cleanup when durable marker identity is invalid: "$invalidMarker"',
      () async {
        await _seedBoundAccountData(database, store, 'user-1');
        final marker = File(
          p.join(documents.path, '.owntend-account-deletion-cleanup-pending'),
        );
        await marker.writeAsString(invalidMarker);
        final privateFile = await _writePrivateFile(
          documents,
          'photos/private/photo.jpg',
        );
        var additionalCleanupCalled = false;

        await expectLater(
          cleaner.resumePendingCleanup(
            additionalCleanup: (_) async {
              additionalCleanupCalled = true;
            },
          ),
          throwsStateError,
        );

        expect(
          await (database.select(
            database.areas,
          )..where((area) => area.id.equals('private-area'))).get(),
          hasLength(1),
        );
        expect((await store.account()).boundUserId, 'user-1');
        expect(await privateFile.exists(), isTrue);
        expect(await marker.exists(), isTrue);
        expect(additionalCleanupCalled, isFalse);
      },
    );
  }

  test(
    'replays cleanup after database clear when the durable marker remains',
    () async {
      await _seedBoundAccountData(database, store, 'user-1');
      final marker = File(
        p.join(documents.path, '.owntend-account-deletion-cleanup-pending'),
      );
      await marker.writeAsString('user-1');
      await cleaner.clearDatabase('user-1');
      final privateFile = await _writePrivateFile(
        documents,
        'photos/private/photo.jpg',
      );
      String? cleanedAccount;

      expect(
        await cleaner.resumePendingCleanup(
          additionalCleanup: (userId) async {
            expect(await marker.exists(), isTrue);
            cleanedAccount = userId;
          },
        ),
        isTrue,
      );

      expect(cleanedAccount, 'user-1');
      expect(await privateFile.exists(), isFalse);
      expect(await marker.exists(), isFalse);
      expect((await store.account()).boundUserId, isNull);
    },
  );

  test(
    'replays account-scoped cleanup while the durable marker exists',
    () async {
      await _seedBoundAccountData(database, store, 'user-1');
      final marker = File(
        p.join(documents.path, '.owntend-account-deletion-cleanup-pending'),
      );
      await marker.writeAsString('user-1');
      String? cleanedAccount;

      expect(
        await cleaner.resumePendingCleanup(
          additionalCleanup: (userId) async {
            expect(await marker.exists(), isTrue);
            cleanedAccount = userId;
          },
        ),
        isTrue,
      );

      expect(cleanedAccount, 'user-1');
      expect(await marker.exists(), isFalse);
    },
  );
}

Future<void> _seedBoundAccountData(
  AppDatabase database,
  LocalSyncStore store,
  String userId,
) async {
  await database
      .into(database.areas)
      .insert(
        AreasCompanion.insert(
          id: 'private-area',
          name: 'Private area',
          kind: 'indoor',
        ),
      );
  await store.setEnabled(
    enabled: true,
    boundUserId: userId,
    migrationState: 'active',
  );
  final scheduledAt = DateTime.utc(2026, 8, 3, 12);
  await database
      .into(database.reminderScheduleSnapshots)
      .insert(
        ReminderScheduleSnapshotsCompanion.insert(
          identity: 'task:private-plan',
          notificationId: 10001,
          planRevision: '1',
          scheduledAt: scheduledAt,
          timezone: 'UTC',
          localComponents: '2026-08-03T12:00:00',
          scheduleMode: 'exactAllowWhileIdle',
          contentVersion: 'test',
        ),
      );
  await database
      .into(database.inboxNotifications)
      .insert(
        InboxNotificationsCompanion.insert(
          id: 'private-inbox-notification',
          title: 'Due',
          body: 'Private reminder',
          kind: 'maintenance',
        ),
      );
}

Future<File> _writePrivateFile(Directory root, String relativePath) async {
  final file = File(p.joinAll([root.path, ...relativePath.split('/')]));
  await file.parent.create(recursive: true);
  await file.writeAsString('private-test-data');
  return file;
}
