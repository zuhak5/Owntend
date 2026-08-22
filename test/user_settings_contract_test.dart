import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';

void main() {
  group('user setting contract', () {
    late AppDatabase db;
    late LocalSyncStore store;

    setUp(() async {
      db = AppDatabase(executor: NativeDatabase.memory());
      store = LocalSyncStore(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('All Dart-declared remote setting keys are accepted by validateUserSettingKey', () {
      for (final key in allowedRemoteSettingKeys) {
        expect(store.validateUserSettingKey(key), isTrue);
      }
    });

    test('Undeclared setting key is rejected before enqueueing', () {
      expect(
        () => store.validateUserSettingKey('invalid_remote_key'),
        throwsArgumentError,
      );
    });

    test('permission education state uses its canonical key', () {
      expect(
        allowedRemoteSettingKeys.contains('permission_education_seen'),
        isTrue,
      );
      expect(
        allowedRemoteSettingKeys.where(
          (key) => key.startsWith('permission_education_seen'),
        ),
        const ['permission_education_seen'],
      );
    });
  });
}
