part of '../monetization.dart';

class OfflineCreationDraftStore {
  const OfflineCreationDraftStore([
    this._storage = const FlutterSecureStorage(
      aOptions: owntendAndroidSecureStorageOptions,
    ),
  ]);

  final FlutterSecureStorage _storage;

  Future<void> save(String key, Map<String, dynamic> value) async {
    try {
      await _storage.write(key: _storageKey(key), value: jsonEncode(value));
    } on Object catch (error) {
      AppLogger.warning('offline_creation_draft_save', error: error);
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> load(String key) async {
    try {
      final encoded = await _storage.read(key: _storageKey(key));
      if (encoded == null) return null;
      final decoded = jsonDecode(encoded);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on Object catch (error) {
      AppLogger.warning('offline_creation_draft_load', error: error);
      return null;
    }
  }

  Future<void> clear(String key) async {
    try {
      await _storage.delete(key: _storageKey(key));
    } on Object catch (error) {
      AppLogger.warning('offline_creation_draft_clear', error: error);
    }
  }

  Future<void> clearForAccount(String accountId) async {
    final normalized = accountId.trim();
    if (normalized.isEmpty) return;
    final prefixes = <String>[
      _storageKey('asset_copy_${normalized}_'),
      _storageKey('asset_${normalized}_'),
      _storageKey('task_${normalized}_'),
    ];
    try {
      final stored = await _storage.readAll();
      for (final key in stored.keys.toList(growable: false)) {
        if (prefixes.any(key.startsWith)) {
          await _storage.delete(key: key);
        }
      }
    } on Object catch (error) {
      AppLogger.warning('offline_creation_draft_account_clear', error: error);
      rethrow;
    }
  }

  String _storageKey(String key) => 'owntend_creation_draft_$key';
}

final offlineCreationDraftStoreProvider = Provider<OfflineCreationDraftStore>(
  (_) => const OfflineCreationDraftStore(),
);
