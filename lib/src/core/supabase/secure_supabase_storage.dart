import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const owntendAndroidSecureStorageOptions = AndroidOptions(
  migrateOnAlgorithmChange: true,
  migrateWithBackup: true,
  resetOnError: false,
);

class SecureSupabaseStorage extends LocalStorage {
  SecureSupabaseStorage({
    required String namespace,
    FlutterSecureStorage? secureStorage,
  }) : _sessionKey = '$namespace.session',
       _secureStorage =
           secureStorage ??
           const FlutterSecureStorage(
             aOptions: owntendAndroidSecureStorageOptions,
           );

  final String _sessionKey;
  final FlutterSecureStorage _secureStorage;

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() {
    return _secureStorage.read(key: _sessionKey);
  }

  @override
  Future<bool> hasAccessToken() {
    return _secureStorage.containsKey(key: _sessionKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) {
    return _secureStorage.write(key: _sessionKey, value: persistSessionString);
  }

  @override
  Future<void> removePersistedSession() {
    return _secureStorage.delete(key: _sessionKey);
  }
}
