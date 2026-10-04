part of '../monetization.dart';

class OfflineCreationDraftStore {
  const OfflineCreationDraftStore([
    this._storage = const FlutterSecureStorage(
      aOptions: owntendAndroidSecureStorageOptions,
    ),
  ]);

  final FlutterSecureStorage _storage;

  static const generationKey = 'draft_generation';
  static final _random = math.Random.secure();
  static Future<void> _pending = Future<void>.value();

  // Secure storage has no compare-and-delete primitive. All store instances
  // share this lane so a replacement write cannot interleave with cleanup.
  static Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<String> save(String key, Map<String, dynamic> value) {
    final generation = base64UrlEncode(
      List<int>.generate(16, (_) => _random.nextInt(256)),
    );
    final encoded = jsonEncode({...value, generationKey: generation});
    return _serialize(() async {
      try {
        await _storage.write(key: _storageKey(key), value: encoded);
        return generation;
      } on Object catch (error) {
        AppLogger.warning('offline_creation_draft_save', error: error);
        rethrow;
      }
    });
  }

  Future<Map<String, dynamic>?> load(String key) => _serialize(() async {
    try {
      final encoded = await _storage.read(key: _storageKey(key));
      if (encoded == null) return null;
      final decoded = jsonDecode(encoded);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on Object catch (error) {
      AppLogger.warning('offline_creation_draft_load', error: error);
      return null;
    }
  });

  Future<void> clear(String key, {required String? expectedGeneration}) =>
      _serialize(() async {
        if (expectedGeneration == null) return;
        try {
          final encoded = await _storage.read(key: _storageKey(key));
          if (encoded == null) return;
          final decoded = jsonDecode(encoded);
          if (decoded is! Map || decoded[generationKey] != expectedGeneration) {
            return;
          }
          await _storage.delete(key: _storageKey(key));
        } on Object catch (error) {
          AppLogger.warning('offline_creation_draft_clear', error: error);
        }
      });

  Future<void> clearForAccount(String accountId) => _serialize(() async {
    final normalized = accountId.trim();
    if (normalized.isEmpty) return;
    final prefixes = <String>[
      _storageKey('asset_copy_${normalized}_'),
      _storageKey('asset_create_${normalized}_'),
      _storageKey('asset_edit_${normalized}_'),
      _storageKey('task_create_${normalized}_'),
      _storageKey('task_edit_${normalized}_'),
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
  });

  String _storageKey(String key) => 'owntend_creation_draft_$key';
}

final offlineCreationDraftStoreProvider = Provider<OfflineCreationDraftStore>(
  (_) => const OfflineCreationDraftStore(),
);
