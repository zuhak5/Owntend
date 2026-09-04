// ignore_for_file: prefer_initializing_formals

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../supabase/supabase_failure.dart';
import '../utils/redacting_logger.dart';

typedef MediaDownloader = Future<Uint8List> Function(String objectPath);
typedef MediaRootProvider = Future<Directory> Function();

class MediaDownloadResult {
  const MediaDownloadResult({
    required this.relativePath,
    required this.byteSize,
    required this.cacheHit,
  });

  final String relativePath;
  final int byteSize;
  final bool cacheHit;
}

class MediaDownloadCache {
  MediaDownloadCache({
    required MediaDownloader download,
    required MediaRootProvider rootProvider,
  }) : _download = download,
       _rootProvider = rootProvider;

  final MediaDownloader _download;
  final MediaRootProvider _rootProvider;
  final Map<String, Future<MediaDownloadResult>> _inFlight = {};

  Future<MediaDownloadResult> materialize({
    required String objectPath,
    required String version,
    required String assetId,
  }) {
    final key = '$assetId|$objectPath|$version';
    final active = _inFlight[key];
    if (active != null) {
      AppLogger.info(
        'sync_photo_download_shared',
        fields: {'object': _diagnosticHash(objectPath)},
      );
      return active;
    }
    final operation = _materialize(
      objectPath: objectPath,
      version: version,
      assetId: assetId,
    );
    _inFlight[key] = operation;
    return operation.whenComplete(() {
      if (identical(_inFlight[key], operation)) {
        _inFlight.remove(key);
      }
    });
  }

  Future<MediaDownloadResult> _materialize({
    required String objectPath,
    required String version,
    required String assetId,
  }) async {
    final stopwatch = Stopwatch()..start();
    final root = await _rootProvider();
    final extension = p.extension(objectPath).toLowerCase();
    final cacheKey = sha256
        .convert('$objectPath|$version'.codeUnits)
        .toString()
        .substring(0, 24);
    final assetDirectory = sha256
        .convert(assetId.codeUnits)
        .toString()
        .substring(0, 16);
    final relativePath = p.posix.join(
      'cloud_media',
      assetDirectory,
      '$cacheKey$extension',
    );
    final destination = File(
      p.normalize(p.joinAll([root.path, ...relativePath.split('/')])),
    );
    if (!p.isWithin(root.path, destination.path)) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.storage,
        message: 'Cloud media destination is outside app storage.',
      );
    }
    if (await destination.exists() && await destination.length() > 0) {
      final byteSize = await destination.length();
      AppLogger.info(
        'sync_photo_download_cache_hit',
        fields: {
          'object': _diagnosticHash(objectPath),
          'bytes': byteSize,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return MediaDownloadResult(
        relativePath: relativePath,
        byteSize: byteSize,
        cacheHit: true,
      );
    }

    File? temporary;
    try {
      final bytes = await _download(objectPath);
      await destination.parent.create(recursive: true);
      temporary = File(
        '${destination.path}.part-${DateTime.now().microsecondsSinceEpoch}',
      );
      await temporary.writeAsBytes(bytes, flush: true);
      if (await destination.exists()) {
        await destination.delete();
      }
      await temporary.rename(destination.path);
      temporary = null;
      AppLogger.info(
        'sync_photo_download_completed',
        fields: {
          'object': _diagnosticHash(objectPath),
          'bytes': bytes.length,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'cache_hit': false,
        },
      );
      return MediaDownloadResult(
        relativePath: relativePath,
        byteSize: bytes.length,
        cacheHit: false,
      );
    } on Object catch (error) {
      AppLogger.warning(
        'sync_photo_download_failed',
        error: error,
        fields: {
          'object': _diagnosticHash(objectPath),
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      rethrow;
    } finally {
      final partial = temporary;
      if (partial != null && await partial.exists()) {
        await partial.delete();
      }
    }
  }
}

int _diagnosticHash(String value) {
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = ((hash * 31) + unit) & 0x7fffffff;
  }
  return hash;
}
