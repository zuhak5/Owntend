import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

part 'photo_import_preflight.dart';

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
    final builder = BytesBuilder(copy: false);
    await for (final chunk in source.openRead(
      0,
      policy.maximumSourceBytes + 1,
    )) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    return Isolate.run(() => _normalizePhoto(bytes, policy));
  }
}

NormalizedPhoto _normalizePhoto(Uint8List bytes, PhotoImportPolicy policy) {
  final image.Image? decoded;
  try {
    // Some decoder metadata APIs already allocate pixels (JPEG) or palettes
    // (BMP). Inspect bounded headers before invoking any decoder API.
    final preflight = _preflightPhoto(bytes, policy);
    final decoder = preflight.decoder;
    final info = decoder.startDecode(bytes);
    if (info == null) {
      throw const PhotoImportException(PhotoImportFailureCode.invalidImage);
    }
    _validateDimensions(info.width, info.height, policy);
    if (info is image.WebPInfo && info.hasAnimation) {
      // The public API exposes canvas dimensions but does not preflight the
      // nested first frame's encoded dimensions before allocation.
      throw const PhotoImportException(PhotoImportFailureCode.invalidImage);
    }
    // Photo imports produce a static JPEG. Decoding only the first frame
    // avoids allocating every frame of an animated source before flattening.
    decoded = decoder.decodeFrame(0);
    if (decoded != null) {
      _boundPhotoMetadata(decoded, policy, jpegIcc: preflight.jpegIcc);
    }
  } on PhotoImportException {
    rethrow;
  } on Object {
    throw const PhotoImportException(PhotoImportFailureCode.invalidImage);
  }
  if (decoded == null) {
    throw const PhotoImportException(PhotoImportFailureCode.invalidImage);
  }
  _validateDimensions(decoded.width, decoded.height, policy);

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

void _validateDimensions(int width, int height, PhotoImportPolicy policy) {
  if (width <= 0 ||
      height <= 0 ||
      width * height > policy.maximumDecodedPixels) {
    throw const PhotoImportException(PhotoImportFailureCode.dimensionsTooLarge);
  }
}
