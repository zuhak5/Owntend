import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

enum PhotoImportFailureCode {
  fileMissing,
  sourceTooLarge,
  invalidImage,
  dimensionsTooLarge,
  outputTooLarge,
}

class PhotoImportException implements Exception {
  const PhotoImportException(this.code);

  final PhotoImportFailureCode code;

  @override
  String toString() => 'PhotoImportException(${code.name})';
}

class PhotoImportPolicy {
  const PhotoImportPolicy({
    this.maximumSourceBytes = 40 * 1024 * 1024,
    this.maximumEncodedBytes = 10 * 1024 * 1024,
    this.maximumDecodedPixels = 40 * 1000 * 1000,
    this.maximumDimension = 4096,
  });

  final int maximumSourceBytes;
  final int maximumEncodedBytes;
  final int maximumDecodedPixels;
  final int maximumDimension;
}

class NormalizedPhoto {
  const NormalizedPhoto({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  String get extension => '.jpg';
  String get mimeType => 'image/jpeg';
}

class PhotoImportService {
  const PhotoImportService({this.policy = const PhotoImportPolicy()});

  final PhotoImportPolicy policy;

  Future<NormalizedPhoto> normalizeFile(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const PhotoImportException(PhotoImportFailureCode.fileMissing);
    }
    final sourceBytes = await source.length();
    if (sourceBytes <= 0 || sourceBytes > policy.maximumSourceBytes) {
      throw const PhotoImportException(PhotoImportFailureCode.sourceTooLarge);
    }
    final bytes = await source.readAsBytes();
    return Isolate.run(() => _normalizePhoto(bytes, policy));
  }
}

NormalizedPhoto _normalizePhoto(Uint8List bytes, PhotoImportPolicy policy) {
  final decoded = image.decodeImage(bytes);
  if (decoded == null) {
    throw const PhotoImportException(PhotoImportFailureCode.invalidImage);
  }
  if (decoded.width <= 0 ||
      decoded.height <= 0 ||
      decoded.width * decoded.height > policy.maximumDecodedPixels) {
    throw const PhotoImportException(PhotoImportFailureCode.dimensionsTooLarge);
  }

  var normalized = image.bakeOrientation(decoded);
  final longestSide = normalized.width > normalized.height
      ? normalized.width
      : normalized.height;
  if (longestSide > policy.maximumDimension) {
    if (normalized.width >= normalized.height) {
      normalized = image.copyResize(
        normalized,
        width: policy.maximumDimension,
        interpolation: image.Interpolation.average,
      );
    } else {
      normalized = image.copyResize(
        normalized,
        height: policy.maximumDimension,
        interpolation: image.Interpolation.average,
      );
    }
  }

  for (final quality in const [86, 78, 70, 60, 50]) {
    final encoded = Uint8List.fromList(
      image.encodeJpg(normalized, quality: quality),
    );
    if (encoded.length <= policy.maximumEncodedBytes) {
      return NormalizedPhoto(
        bytes: encoded,
        width: normalized.width,
        height: normalized.height,
      );
    }
  }
  throw const PhotoImportException(PhotoImportFailureCode.outputTooLarge);
}
