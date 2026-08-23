// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/redacting_logger.dart';

class RemoteAssetEntry {
  const RemoteAssetEntry({
    required this.key,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
  });

  final String key;
  final String url;
  final String sha256;
  final int sizeBytes;

  static const int maxAssetSizeBytes = 5 * 1024 * 1024; // 5MB limit

  factory RemoteAssetEntry.fromJson(Map<String, dynamic> json) {
    return RemoteAssetEntry(
      key: json['key'] as String? ?? '',
      url: json['url'] as String? ?? '',
      sha256: (json['sha256'] as String? ?? '').toLowerCase(),
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'url': url,
    'sha256': sha256,
    'size_bytes': sizeBytes,
  };
}

class RemoteAssetManifest {
  const RemoteAssetManifest({required this.version, required this.assets});

  final int version;
  final Map<String, RemoteAssetEntry> assets;

  factory RemoteAssetManifest.fromJson(Map<String, dynamic> json) {
    final version = (json['version'] as num?)?.toInt() ?? 1;
    final rawAssets = json['assets'] as List<dynamic>? ?? const [];
    final assets = <String, RemoteAssetEntry>{};
    for (final item in rawAssets) {
      if (item is Map<String, dynamic>) {
        final entry = RemoteAssetEntry.fromJson(item);
        if (entry.key.isNotEmpty &&
            entry.url.isNotEmpty &&
            entry.sha256.isNotEmpty) {
          assets[entry.key] = entry;
        }
      }
    }
    return RemoteAssetManifest(version: version, assets: assets);
  }
}

typedef AssetBytesDownloader = Future<Uint8List?> Function(String url);

class RemoteAssetService {
  RemoteAssetService({
    required Directory cacheDirectory,
    AssetBytesDownloader? downloader,
  }) : _cacheDirectory = cacheDirectory,
       _downloader = downloader;

  final Directory _cacheDirectory;
  final AssetBytesDownloader? _downloader;
  RemoteAssetManifest? _manifest;

  RemoteAssetManifest? get manifest => _manifest;

  void setManifest(RemoteAssetManifest manifest) {
    _manifest = manifest;
  }

  String _sanitizeKey(String key) {
    return key.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
  }

  File _targetFileForKey(String key) {
    final safeName = _sanitizeKey(key);
    return File(p.join(_cacheDirectory.path, safeName));
  }

  Future<String?> getCachedAssetPath(String key) async {
    try {
      final file = _targetFileForKey(key);
      if (!await file.exists()) return null;

      final entry = _manifest?.assets[key];
      if (entry == null) return file.path;

      // Verify file matches expected sha256
      final bytes = await file.readAsBytes();
      final hash = sha256.convert(bytes).toString().toLowerCase();
      if (hash == entry.sha256.toLowerCase()) {
        return file.path;
      }
      // If corrupted or mismatched, delete it
      await file.delete();
      return null;
    } on Object catch (error) {
      AppLogger.warning('remote_asset_get_cached_failed', error: error);
      return null;
    }
  }

  Future<File?> downloadAndVerifyAsset(RemoteAssetEntry entry) async {
    if (_downloader == null) return null;
    if (entry.sizeBytes > RemoteAssetEntry.maxAssetSizeBytes) {
      AppLogger.warning(
        'remote_asset_exceeds_max_size',
        fields: {'key': entry.key},
      );
      return null;
    }

    final targetFile = _targetFileForKey(entry.key);
    final tempFile = File(
      p.join(
        _cacheDirectory.path,
        '.part-${DateTime.now().microsecondsSinceEpoch}-${_sanitizeKey(entry.key)}',
      ),
    );

    try {
      await _cacheDirectory.create(recursive: true);
      final bytes = await _downloader(entry.url);
      if (bytes == null || bytes.isEmpty) return null;
      if (bytes.length > RemoteAssetEntry.maxAssetSizeBytes) return null;

      final computedHash = sha256.convert(bytes).toString().toLowerCase();
      if (computedHash != entry.sha256.toLowerCase()) {
        AppLogger.warning(
          'remote_asset_hash_mismatch',
          fields: {'key': entry.key},
        );
        return null;
      }

      await tempFile.writeAsBytes(bytes, flush: true);
      await tempFile.rename(targetFile.path);
      return targetFile;
    } on Object catch (error) {
      AppLogger.warning('remote_asset_download_failed', error: error);
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      return null;
    }
  }
}

final remoteAssetServiceProvider = FutureProvider<RemoteAssetService>((
  ref,
) async {
  final tempDir = await getTemporaryDirectory();
  final cacheDir = Directory(p.join(tempDir.path, 'remote_assets'));
  return RemoteAssetService(cacheDirectory: cacheDir);
});
