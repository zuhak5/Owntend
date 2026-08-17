import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/services/sidecar_registry.dart';
import '../../../core/sync/local_sync_store.dart';
import '../../../core/utils/redacting_logger.dart';

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
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(
        userId,
        'userId',
        'Destructive account cleanup requires an immutable account identity.',
      );
    }
    final account = await _store.existingAccount();
    if (account?.boundUserId == null) {
      if (!await _store.isDomainDataPristine()) {
        throw StateError(
          'Unbound local data cannot be attributed to the cleanup account.',
        );
      }
    } else if (account!.boundUserId != userId) {
      throw StateError('Local data belongs to a different cloud identity.');
    }
    await _store.clearAllAccountData(expectedUserId: userId);
  }

  Future<void> _clearFiles() async {
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
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(
        userId,
        'userId',
        'Destructive account cleanup requires an immutable account identity.',
      );
    }
    final account = await _store.existingAccount();
    if (account?.boundUserId != userId) {
      throw StateError(
        'Local account identity does not match the deleted cloud account.',
      );
    }

    final documents = await _documentsDirectory();
    await documents.create(recursive: true);
    final marker = _marker(documents);
    await marker.writeAsString(userId, flush: true);
    await _clear(expectedUserId: userId);
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
    if (recordedUserId.isEmpty || recordedUserId == 'pending') {
      AppLogger.warning('account_cleanup_marker_identity_invalid');
      throw StateError(
        'Pending account cleanup marker is missing a valid account identity.',
      );
    }

    final existingAccount = await _store.existingAccount();
    if (existingAccount?.boundUserId != null &&
        existingAccount!.boundUserId != recordedUserId) {
      AppLogger.warning('account_cleanup_marker_identity_mismatch');
      throw StateError(
        'Pending account cleanup belongs to a different cloud identity.',
      );
    }
    if (existingAccount?.boundUserId == null &&
        !await _store.isDomainDataPristine()) {
      AppLogger.warning('account_cleanup_unbound_non_pristine_data');
      throw StateError(
        'Pending account cleanup cannot attribute unbound local data safely.',
      );
    }

    await _clear(expectedUserId: recordedUserId);
    await additionalCleanup?.call(recordedUserId);
    if (await marker.exists()) await marker.delete();
    return true;
  }

  Future<void> _clear({required String expectedUserId}) async {
    await clearDatabase(expectedUserId);
    await _clearFiles();
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
