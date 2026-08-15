import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/services/sidecar_registry.dart';
import '../../../core/sync/local_sync_store.dart';

typedef AccountDataDirectoryProvider = Future<Directory> Function();
typedef AdditionalAccountDataCleaner = Future<void> Function(String userId);

class LocalAccountDataCleaner {
  LocalAccountDataCleaner(
    this._store, {
    SidecarRegistryStore? sidecarRegistry,
    AccountDataDirectoryProvider? documentsDirectory,
    AccountDataDirectoryProvider? cacheDirectory,
  }) : _sidecarRegistry = sidecarRegistry ?? SidecarRegistryStore(),
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory;

  static const _pendingMarkerName = '.owntend-account-deletion-cleanup-pending';
  static const _documentDirectories = [
    'photos',
    'profile',
    'cloud_media',
    'backups',
  ];
  static const _documentFiles = ['owntend-backup-state.json'];
  static const _cacheDirectories = ['avatars'];

  final LocalSyncStore _store;
  final SidecarRegistryStore _sidecarRegistry;
  final AccountDataDirectoryProvider _documentsDirectory;
  final AccountDataDirectoryProvider _cacheDirectory;

  Future<void> clearDatabase(String userId) async {
    final account = await _store.account();
    if (account.boundUserId != null && account.boundUserId != userId) {
      throw StateError('Local data belongs to a different cloud identity.');
    }
    await _store.clearAllAccountData(expectedUserId: userId);
  }

  Future<void> clearFiles() async {
    final documents = await _documentsDirectory();
    for (final name in _documentDirectories) {
      await _deleteDirectoryWithin(documents, name);
    }
    for (final name in _documentFiles) {
      await _deleteFileWithin(documents, name);
    }

    // Clean all registered and discovered media sidecars (.restore-*, .previous-*)
    final discoveredSidecars = await _sidecarRegistry.discoverSidecars(
      documents,
    );
    final failures = <String>[];
    for (final sidecarDir in discoveredSidecars) {
      try {
        if (FileSystemEntity.isLinkSync(sidecarDir.path)) {
          failures.add('${sidecarDir.path} (symlink detected)');
          continue;
        }
        await sidecarDir.delete(recursive: true);
      } catch (e) {
        failures.add('${sidecarDir.path} ($e)');
      }
    }

    if (failures.isNotEmpty) {
      throw StateError(
        'Account deletion failed to remove sidecar media directories: ${failures.join(', ')}',
      );
    }

    await _sidecarRegistry.clearAll();

    final cache = await _cacheDirectory();
    for (final name in _cacheDirectories) {
      await _deleteDirectoryWithin(cache, name);
    }
  }

  Future<void> clearAfterCloudDeletion(
    String userId, {
    AdditionalAccountDataCleaner? additionalCleanup,
  }) async {
    final account = await _store.account();
    if (account.boundUserId != null && account.boundUserId != userId) {
      throw StateError('Local data belongs to a different cloud identity.');
    }

    final documents = await _documentsDirectory();
    await documents.create(recursive: true);
    final marker = _marker(documents);
    await marker.writeAsString(userId, flush: true);
    await clearDatabase(userId);
    await clearFiles();
    await additionalCleanup?.call(userId);
    if (await marker.exists()) await marker.delete();
  }

  Future<bool> resumePendingCleanup({
    AdditionalAccountDataCleaner? additionalCleanup,
  }) async {
    final documents = await _documentsDirectory();
    final marker = _marker(documents);
    if (!await marker.exists()) return false;
    final recordedUserId = (await marker.readAsString()).trim();
    final existingAccount = await _store.existingAccount();
    final userId = recordedUserId == 'pending' || recordedUserId.isEmpty
        ? existingAccount?.boundUserId
        : recordedUserId;
    await _clear(documents: documents);
    if (userId != null) await additionalCleanup?.call(userId);
    if (await marker.exists()) await marker.delete();
    return true;
  }

  Future<void> _clear({
    required Directory documents,
    String? expectedUserId,
  }) async {
    await _store.clearAllAccountData(expectedUserId: expectedUserId);
    await clearFiles();
  }

  File _marker(Directory documents) =>
      File(p.join(documents.path, _pendingMarkerName));

  Future<void> _deleteDirectoryWithin(Directory root, String name) async {
    final target = Directory(p.normalize(p.join(root.path, name)));
    if (!p.isWithin(p.normalize(root.path), target.path)) {
      throw StateError('Account cleanup path escaped app storage.');
    }
    if (await target.exists()) await target.delete(recursive: true);
  }

  Future<void> _deleteFileWithin(Directory root, String name) async {
    final target = File(p.normalize(p.join(root.path, name)));
    if (!p.isWithin(p.normalize(root.path), target.path)) {
      throw StateError('Account cleanup path escaped app storage.');
    }
    if (await target.exists()) await target.delete();
  }
}
