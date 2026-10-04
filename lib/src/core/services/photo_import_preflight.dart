part of 'photo_import_service.dart';

// Normalized JPEG metadata is serialized into single 16-bit APP segments by
// the pinned encoder. Bound both that contract and decoder metadata records.
const _maximumPhotoMetadataRecords = 4096;
const _maximumPhotoIccBytes = 65535 - 16;
const _maximumPhotoExifBytes = 65535 - 8;

Never _invalidPhoto() =>
    throw const PhotoImportException(PhotoImportFailureCode.invalidImage);

({image.Decoder decoder, Uint8List? jpegIcc}) _preflightPhoto(
  Uint8List bytes,
  PhotoImportPolicy policy,
) {
  if (bytes.isEmpty || bytes.length > policy.maximumSourceBytes) {
    throw const PhotoImportException(PhotoImportFailureCode.sourceTooLarge);
  }
  final data = ByteData.sublistView(bytes);
  bool starts(List<int> signature) =>
      bytes.length >= signature.length &&
      Iterable<int>.generate(signature.length)
          .every((index) => bytes[index] == signature[index]);
  if (starts(const [0xff, 0xd8])) {
    final icc = _preflightJpeg(bytes, data, policy);
    return (decoder: image.JpegDecoder(), jpegIcc: icc);
  }
  if (starts(const [137, 80, 78, 71, 13, 10, 26, 10])) {
    _preflightPng(bytes, data, policy);
    return (decoder: image.PngDecoder(), jpegIcc: null);
  }
  if (starts(const [71, 73, 70, 56])) {
    _preflightGif(bytes, data, policy);
    return (decoder: image.GifDecoder(), jpegIcc: null);
  }
  if (starts(const [66, 77])) {
    final headerSize = data.getUint32(14, Endian.little);
    if (![40, 52, 56, 108, 124].contains(headerSize) ||
        14 + headerSize > bytes.length) {
      _invalidPhoto();
    }
    _validateDimensions(
      data.getInt32(18, Endian.little),
      data.getInt32(22, Endian.little).abs(),
      policy,
    );
    final bits = data.getUint16(28, Endian.little);
    final colors = data.getUint32(46, Endian.little);
    if (![1, 4, 8, 16, 24, 32].contains(bits) ||
        (bits <= 8 && colors > 1 << bits)) {
      _invalidPhoto();
    }
    return (decoder: image.BmpDecoder(), jpegIcc: null);
  }
  if (starts(const [82, 73, 70, 70]) &&
      bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    _preflightWebP(bytes, data, policy);
    return (decoder: image.WebPDecoder(), jpegIcc: null);
  }
  // TIFF follows an unbounded linked IFD chain even in isValidFile. EXR/ICO
  // and other containers do not provide this importer's bounded decode path.
  _invalidPhoto();
}

Uint8List? _preflightJpeg(
  Uint8List bytes,
  ByteData data,
  PhotoImportPolicy policy,
) {
  var offset = 2;
  var frames = 0;
  var records = 0;
  final iccChunks = <int, Uint8List>{};
  int? iccChunkCount;
  var iccBytes = 0;
  while (offset < bytes.length) {
    if (bytes[offset++] != 0xff) continue; // Entropy-coded scan bytes.
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset == bytes.length) _invalidPhoto();
    final marker = bytes[offset++];
    if (marker == 0 || marker == 0x01 || marker >= 0xd0 && marker <= 0xd7) {
      continue;
    }
    if (marker == 0xd9) break;
    if (marker == 0xd8) _invalidPhoto();
    if (++records > _maximumPhotoMetadataRecords) _invalidPhoto();
    final length = data.getUint16(offset);
    final end = offset + length;
    if (length < 2 || end > bytes.length) _invalidPhoto();
    if (marker == 0xc0 || marker == 0xc1 || marker == 0xc2) {
      if (++frames != 1 || length < 8) _invalidPhoto();
      _validateDimensions(
        data.getUint16(offset + 5),
        data.getUint16(offset + 3),
        policy,
      );
      final components = bytes[offset + 7];
      if (![1, 3, 4].contains(components) || length != 8 + 3 * components) {
        _invalidPhoto();
      }
      for (var index = 0; index < components; index++) {
        final sampling = bytes[offset + 9 + 3 * index];
        if (sampling >> 4 < 1 ||
            sampling >> 4 > 4 ||
            sampling & 15 < 1 ||
            sampling & 15 > 4) {
          _invalidPhoto();
        }
      }
    } else if (marker == 0xe2 &&
        length >= 14 &&
        String.fromCharCodes(bytes.sublist(offset + 2, offset + 14)) ==
            'ICC_PROFILE\x00') {
      if (length < 16) _invalidPhoto();
      final sequence = bytes[offset + 14];
      final count = bytes[offset + 15];
      if (sequence == 0 ||
          count == 0 ||
          sequence > count ||
          iccChunkCount != null && iccChunkCount != count ||
          iccChunks.containsKey(sequence)) {
        _invalidPhoto();
      }
      iccChunkCount = count;
      final chunk = Uint8List.sublistView(bytes, offset + 16, end);
      iccBytes += chunk.length;
      if (iccBytes > _iccBudget(policy)) _invalidPhoto();
      iccChunks[sequence] = chunk;
    } else if (marker == 0xe1 && length >= 8) {
      if (String.fromCharCodes(bytes.sublist(offset + 2, offset + 8)) ==
          'Exif\x00\x00') {
        _preflightExif(Uint8List.sublistView(bytes, offset + 8, end));
      }
    }
    offset = end;
  }
  if (frames != 1) _invalidPhoto();
  if (iccChunkCount == null) return null;
  if (iccChunks.length != iccChunkCount) _invalidPhoto();
  final profile = BytesBuilder(copy: false);
  for (var sequence = 1; sequence <= iccChunkCount; sequence++) {
    profile.add(iccChunks[sequence]!);
  }
  return profile.takeBytes();
}

void _preflightPng(Uint8List bytes, ByteData data, PhotoImportPolicy policy) {
  if (data.getUint32(8) != 13 ||
      String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') {
    _invalidPhoto();
  }
  final width = data.getUint32(16);
  final height = data.getUint32(20);
  _validateDimensions(width, height, policy);
  final bits = bytes[24];
  final colorType = bytes[25];
  final channels = switch (colorType) {
    0 || 3 => 1,
    2 => 3,
    4 => 2,
    6 => 4,
    _ => 0,
  };
  if (channels == 0 || ![1, 2, 4, 8, 16].contains(bits)) _invalidPhoto();
  // Adam7 has up to seven filtered passes. This upper bound also covers
  // packed samples and scanline padding without expanding a compressed bomb.
  final maximumInflated =
      width * height * channels * ((bits + 7) ~/ 8) + height * 14;
  final sink = _PhotoInflateBudget(maximumInflated);
  final inflate = ZLibDecoder().startChunkedConversion(sink);
  var sawEnd = false;
  var records = 0;
  for (var offset = 8; offset + 12 <= bytes.length;) {
    if (++records > _maximumPhotoMetadataRecords) _invalidPhoto();
    final length = data.getUint32(offset);
    final end = offset + 12 + length;
    if (end > bytes.length) _invalidPhoto();
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    final fixedLength = switch (type) {
      'IHDR' => 13,
      'IEND' => 0,
      'pHYs' => 9,
      'gAMA' || 'cICP' => 4,
      'acTL' => 8,
      'fcTL' => 26,
      'bKGD' => switch (colorType) {
        0 || 4 => 2,
        3 => 1,
        _ => 6,
      },
      _ => null,
    };
    if (type == 'IHDR' && offset != 8 ||
        fixedLength != null && length != fixedLength ||
        type == 'PLTE' && length > 768 ||
        type == 'tRNS' && length > 256 ||
        type == 'fdAT' && length < 4) {
      _invalidPhoto();
    }
    if (type == 'iCCP') {
      final terminator = bytes.indexOf(0, offset + 8);
      if (terminator <= offset + 8 ||
          terminator > offset + 8 + 79 ||
          terminator + 1 >= end - 4 ||
          bytes[terminator + 1] != 0) {
        _invalidPhoto();
      }
      _inflatePhotoMetadata(
        Uint8List.sublistView(bytes, terminator + 2, end - 4),
        _iccBudget(policy),
      );
    }
    if (type == 'IDAT') {
      for (var pos = offset + 8; pos < end - 4;) {
        final next = pos + 4096 < end - 4 ? pos + 4096 : end - 4;
        inflate.add(Uint8List.sublistView(bytes, pos, next));
        pos = next;
      }
    }
    if (type == 'IEND') {
      sawEnd = true;
      break;
    }
    offset = end;
  }
  inflate.close();
  if (!sawEnd) _invalidPhoto();
}

class _PhotoInflateBudget implements Sink<List<int>> {
  _PhotoInflateBudget(this.remaining, {this.output});
  int remaining;
  final BytesBuilder? output;

  @override
  void add(List<int> data) {
    remaining -= data.length;
    if (remaining < 0) _invalidPhoto();
    output?.add(data);
  }

  @override
  void close() {}
}

int _iccBudget(PhotoImportPolicy policy) =>
    policy.maximumEncodedBytes < _maximumPhotoIccBytes
    ? policy.maximumEncodedBytes
    : _maximumPhotoIccBytes;

Uint8List _inflatePhotoMetadata(Uint8List bytes, int maximumBytes) {
  final output = BytesBuilder(copy: false);
  final inflate = ZLibDecoder().startChunkedConversion(
    _PhotoInflateBudget(maximumBytes, output: output),
  );
  for (var offset = 0; offset < bytes.length;) {
    final end = offset + 4096 < bytes.length ? offset + 4096 : bytes.length;
    inflate.add(Uint8List.sublistView(bytes, offset, end));
    offset = end;
  }
  inflate.close();
  return output.takeBytes();
}

void _preflightGif(Uint8List bytes, ByteData data, PhotoImportPolicy policy) {
  final width = data.getUint16(6, Endian.little);
  final height = data.getUint16(8, Endian.little);
  _validateDimensions(width, height, policy);
  var offset = 13;
  if (bytes[10] & 0x80 != 0) {
    offset += 3 * (1 << ((bytes[10] & 7) + 1));
  }
  var records = 0;
  var frames = 0;
  void skipBlocks() {
    while (offset < bytes.length) {
      final size = bytes[offset++];
      if (size == 0) return;
      offset += size;
      if (offset > bytes.length) _invalidPhoto();
    }
    _invalidPhoto();
  }

  while (offset < bytes.length) {
    if (++records > _maximumPhotoMetadataRecords) _invalidPhoto();
    final kind = bytes[offset++];
    if (kind == 0x3b) {
      if (frames == 0) _invalidPhoto();
      return;
    }
    if (kind == 0x21) {
      final label = bytes[offset++];
      if (label == 0xf9 &&
          (offset + 6 > bytes.length ||
              bytes[offset] != 4 ||
              bytes[offset + 5] != 0)) {
        _invalidPhoto();
      }
      if (label == 0xff &&
          offset + 12 <= bytes.length &&
          bytes[offset] == 11 &&
          String.fromCharCodes(bytes.sublist(offset + 1, offset + 12)) ==
              'NETSCAPE2.0') {
        // The decoder consumes exactly this loop block, then resumes parsing
        // records. Reject other sub-block shapes so their payload cannot be
        // interpreted as unchecked image descriptors or extension records.
        if (offset + 17 > bytes.length ||
            bytes[offset + 12] != 3 ||
            bytes[offset + 13] != 1 ||
            bytes[offset + 16] != 0) {
          _invalidPhoto();
        }
      }
      skipBlocks();
    } else if (kind == 0x2c) {
      if (offset + 9 > bytes.length) _invalidPhoto();
      final frameWidth = data.getUint16(offset + 4, Endian.little);
      final frameHeight = data.getUint16(offset + 6, Endian.little);
      if (frameWidth == 0 ||
          frameHeight == 0 ||
          data.getUint16(offset, Endian.little) + frameWidth > width ||
          data.getUint16(offset + 2, Endian.little) + frameHeight > height) {
        _invalidPhoto();
      }
      final packed = bytes[offset + 8];
      offset += 9;
      if (packed & 0x80 != 0) offset += 3 * (1 << ((packed & 7) + 1));
      if (offset >= bytes.length || bytes[offset] < 2 || bytes[offset] > 8) {
        _invalidPhoto();
      }
      offset++;
      skipBlocks();
      frames++;
    } else {
      _invalidPhoto();
    }
  }
  _invalidPhoto();
}

void _preflightWebP(Uint8List bytes, ByteData data, PhotoImportPolicy policy) {
  var images = 0;
  var records = 0;
  for (var offset = 12; offset + 8 <= bytes.length;) {
    if (++records > _maximumPhotoMetadataRecords) _invalidPhoto();
    final type = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    final end = start + size;
    if (end > bytes.length) _invalidPhoto();
    if (type == 'ANIM' || type == 'ANMF') _invalidPhoto();
    if (type == 'VP8X') {
      if (size != 10 || bytes[start] & 2 != 0) _invalidPhoto();
      int uint24(int pos) =>
          bytes[pos] | bytes[pos + 1] << 8 | bytes[pos + 2] << 16;
      _validateDimensions(uint24(start + 4) + 1, uint24(start + 7) + 1, policy);
    } else if (type == 'VP8 ') {
      if (size < 10 || ++images != 1) _invalidPhoto();
      _validateDimensions(
        data.getUint16(start + 6, Endian.little) & 0x3fff,
        data.getUint16(start + 8, Endian.little) & 0x3fff,
        policy,
      );
    } else if (type == 'VP8L') {
      if (size < 5 || ++images != 1 || bytes[start] != 0x2f) _invalidPhoto();
      final dimensions = data.getUint32(start + 1, Endian.little);
      _validateDimensions(
        (dimensions & 0x3fff) + 1,
        ((dimensions >> 14) & 0x3fff) + 1,
        policy,
      );
    } else if (type == 'EXIF') {
      _preflightExif(Uint8List.sublistView(bytes, start, end));
    } else if (type == 'ICCP' && size > _iccBudget(policy)) {
      _invalidPhoto();
    }
    offset = end + (size & 1);
  }
  if (images != 1) _invalidPhoto();
}

void _preflightExif(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final endian = switch (data.getUint16(0)) {
    0x4949 => Endian.little,
    0x4d4d => Endian.big,
    _ => _invalidPhoto(),
  };
  if (data.getUint16(2, endian) != 42) _invalidPhoto();
  final pending = [data.getUint32(4, endian)];
  final visited = <int>{};
  var totalEntries = 0;
  var referencedBytes = 0;
  const sizes = [0, 1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 4, 8, 4];
  while (pending.isNotEmpty) {
    final offset = pending.removeLast();
    if (offset == 0) continue;
    if (!visited.add(offset) || visited.length > 256) _invalidPhoto();
    final count = data.getUint16(offset, endian);
    totalEntries += count;
    final end = offset + 2 + 12 * count;
    if (totalEntries > 4096 || end + 4 > bytes.length) _invalidPhoto();
    for (var entry = offset + 2; entry < end; entry += 12) {
      final tag = data.getUint16(entry, endian);
      final type = data.getUint16(entry + 2, endian);
      if (type <= 0 || type >= sizes.length) _invalidPhoto();
      final size = data.getUint32(entry + 4, endian) * sizes[type];
      referencedBytes += size;
      final value = size > 4 ? data.getUint32(entry + 8, endian) : entry + 8;
      if (value + size > bytes.length ||
          referencedBytes > bytes.length ||
          referencedBytes + totalEntries * 12 > _maximumPhotoExifBytes) {
        _invalidPhoto();
      }
      if (tag == 0x0202) {
        if (type != 4 ||
            size != 4 ||
            data.getUint32(value, endian) > _maximumPhotoExifBytes) {
          _invalidPhoto();
        }
      }
      if (tag == 0x8769 || tag == 0xa005 || tag == 0x8825) {
        if (type != 4 || size != 4) _invalidPhoto();
        pending.add(data.getUint32(value, endian));
      }
    }
    pending.add(data.getUint32(end, endian));
  }
}

void _boundPhotoMetadata(
  image.Image photo,
  PhotoImportPolicy policy, {
  Uint8List? jpegIcc,
}) {
  final profile = photo.iccProfile;
  if (profile != null) {
    final budget = _iccBudget(policy);
    final data =
        jpegIcc ??
        (profile.compression == image.IccProfileCompression.deflate
            ? _inflatePhotoMetadata(profile.data, budget)
            : profile.data);
    if (data.length > budget) _invalidPhoto();
    photo.iccProfile = image.IccProfile(
      profile.name,
      image.IccProfileCompression.none,
      // The pinned encoder writes these bytes directly after ICC_PROFILE.
      // Emit one complete, correctly sequenced APP2 chunk for every source.
      Uint8List.fromList([1, 1, ...data]),
    );
  }
  if (!photo.exif.isEmpty) {
    final encoded = image.OutputBuffer();
    photo.exif.write(encoded);
    if (encoded.length > _maximumPhotoExifBytes) _invalidPhoto();
  }
}
