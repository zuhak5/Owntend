import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/supabase/secure_supabase_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureSupabaseStorage Continuity Contract (SB-029)', () {
    test('Android secure storage configuration preserves keys without resetOnError', () {
      final map = owntendAndroidSecureStorageOptions.toMap();
      expect(map['resetOnError'], equals('false'));
      expect(map['migrateOnAlgorithmChange'], equals('true'));
      expect(map['migrateWithBackup'], equals('true'));
    });

    test(
      'Persists, reads, and cleans session across distinct storage instances',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        const storageInstance = FlutterSecureStorage();

        final storage1 = SecureSupabaseStorage(
          namespace: 'owntend.prod',
          secureStorage: storageInstance,
        );

        expect(await storage1.hasAccessToken(), isFalse);
        expect(await storage1.accessToken(), isNull);

        const mockSession = '{"access_token":"jwt-123","user_id":"user-abc"}';
        await storage1.persistSession(mockSession);

        expect(await storage1.hasAccessToken(), isTrue);
        expect(await storage1.accessToken(), equals(mockSession));

        // Simulate app restart / patch re-instantiation
        final storage2 = SecureSupabaseStorage(
          namespace: 'owntend.prod',
          secureStorage: storageInstance,
        );

        expect(await storage2.hasAccessToken(), isTrue);
        expect(await storage2.accessToken(), equals(mockSession));

        // Cleanup
        await storage2.removePersistedSession();
        expect(await storage2.hasAccessToken(), isFalse);
        expect(await storage2.accessToken(), isNull);
      },
    );

    test('Namespaces isolate sessions cleanly between environments', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storageInstance = FlutterSecureStorage();

      final devStorage = SecureSupabaseStorage(
        namespace: 'owntend.dev',
        secureStorage: storageInstance,
      );
      final prodStorage = SecureSupabaseStorage(
        namespace: 'owntend.prod',
        secureStorage: storageInstance,
      );

      await devStorage.persistSession('dev-token');
      await prodStorage.persistSession('prod-token');

      expect(await devStorage.accessToken(), equals('dev-token'));
      expect(await prodStorage.accessToken(), equals('prod-token'));

      await devStorage.removePersistedSession();
      expect(await devStorage.accessToken(), isNull);
      expect(await prodStorage.accessToken(), equals('prod-token'));
    });
  });
}
