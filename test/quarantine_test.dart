import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';

void main() {
  late AppDatabase db;
  late File tempFile;
  late LocalSyncStore store;

  setUp(() async {
    tempFile = File(
      '${Directory.systemTemp.path}/quarantine_test_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    db = AppDatabase(executor: NativeDatabase(tempFile));
    store = LocalSyncStore(db);
  });

  tearDown(() async {
    await db.close();
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  });

  Future<void> seedNonPristineData() async {
    await db.customInsert(
      "INSERT INTO areas(id, name, kind, created_at, updated_at) VALUES ('area-1', 'Main Area', 'indoor', '2026-08-13', '2026-08-13')",
    );
    await db.customInsert(
      "INSERT INTO rooms(id, area_id, name, created_at, updated_at) VALUES ('room-1', 'area-1', 'Living Room', '2026-08-13', '2026-08-13')",
    );
  }

  test(
    'quarantineLegacyData marks store uploadProhibited with legacy owner',
    () async {
      await seedNonPristineData();
      expect(await store.isDomainDataPristine(), false);

      await store.quarantineLegacyData(
        legacyUserId: 'user-a',
        reason: 'unsupported_provider',
      );

      final account = await store.account();
      expect(account.uploadProhibited, true);
      expect(account.quarantineReason, 'unsupported_provider');
      expect(account.legacyOwnerId, 'user-a');
      expect(account.boundUserId, isNull);
      expect(account.migrationState, 'quarantined');
    },
  );

  test('bindIdentity throws StateError when data is quarantined or unbound non-pristine', () async {
    await seedNonPristineData();
    await store.quarantineLegacyData(
      legacyUserId: 'user-a',
      reason: 'unsupported_provider',
    );

    expect(
      () => store.bindIdentity('user-b'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Local data is quarantined'),
        ),
      ),
    );

    final account = await store.account();
    expect(account.uploadProhibited, true);
    expect(account.migrationState, 'quarantined');
    expect(account.boundUserId, isNull);
  });

  test(
    'resolveQuarantineWithReset wipes domain data and clears quarantine',
    () async {
      await seedNonPristineData();
      await store.quarantineLegacyData(
        legacyUserId: 'user-a',
        reason: 'unsupported_provider',
      );

      await store.resolveQuarantineWithReset();

      final account = await store.account();
      expect(account.uploadProhibited, false);
      expect(account.quarantineReason, isNull);
      expect(account.legacyOwnerId, isNull);
      expect(account.migrationState, 'localOnly');
      expect(await store.isDomainDataPristine(), true);

      // Clean binding under User B should now succeed
      await store.bindIdentity('user-b');
      final boundAccount = await store.account();
      expect(boundAccount.boundUserId, 'user-b');
      expect(boundAccount.uploadProhibited, false);
    },
  );

  test('resolveQuarantineWithImport unquarantines and binds user-b with initial snapshot', () async {
    await seedNonPristineData();
    await store.quarantineLegacyData(
      legacyUserId: 'user-a',
      reason: 'unsupported_provider',
    );

    await store.resolveQuarantineWithImport('user-b');

    final account = await store.account();
    expect(account.uploadProhibited, false);
    expect(account.quarantineReason, isNull);
    expect(account.boundUserId, 'user-b');
    expect(account.migrationState, 'binding');
    expect(await store.pendingCount() > 0, true);
  });
}
