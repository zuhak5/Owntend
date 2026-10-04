import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/services/photo_import_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('owntend_photo_import_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('decodes actual content and produces bounded JPEG output', () async {
    final source = File(p.join(root.path, 'renamed.heic'));
    final pixels = image.Image(width: 120, height: 80)
      ..clear(image.ColorRgb8(24, 120, 72));
    await source.writeAsBytes(image.encodePng(pixels));

    final normalized = await const PhotoImportService().normalizeFile(
      source.path,
    );

    expect(normalized.extension, '.jpg');
    expect(normalized.mimeType, 'image/jpeg');
    expect(normalized.bytes, hasLength(lessThan(10 * 1024 * 1024)));
    expect(normalized.bytes.take(2), [0xff, 0xd8]);
    final decoded = image.decodeJpg(normalized.bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 120);
    expect(decoded.height, 80);
  });

  test('checks declared dimensions before attempting pixel decoding', () async {
    final source = File(p.join(root.path, 'large-declared.png'));
    final encoded = Uint8List.fromList(
      image.encodePng(image.Image(width: 20, height: 20)),
    );
    final data = ByteData.sublistView(encoded);
    var offset = 8;
    while (offset + 12 <= encoded.length) {
      final length = data.getUint32(offset);
      final type = String.fromCharCodes(
        encoded.sublist(offset + 4, offset + 8),
      );
      if (type == 'IDAT') {
        // Its readable header already exceeds policy. The invalid pixel
        // checksum makes any attempt to decode pixels observable and cheap.
        encoded[offset + 8 + length] ^= 1;
        break;
      }
      offset += 12 + length;
    }
    await source.writeAsBytes(encoded);
    await expectLater(
      const PhotoImportService(
        policy: PhotoImportPolicy(maximumDecodedPixels: 100),
      ).normalizeFile(source.path),
      _photoFailure(PhotoImportFailureCode.dimensionsTooLarge),
    );
  });

  test('normalizes only the first frame of an animated GIF', () async {
    final source = File(p.join(root.path, 'animated.gif'));
    final frames = image.Image(width: 12, height: 8)
      ..clear(image.ColorRgb8(240, 10, 10));
    frames.addFrame(
      image.Image(width: 12, height: 8)..clear(image.ColorRgb8(10, 240, 10)),
    );
    await source.writeAsBytes(image.encodeGif(frames));

    final normalized = await const PhotoImportService().normalizeFile(
      source.path,
    );
    final decoded = image.decodeJpg(normalized.bytes)!;
    expect(decoded.numFrames, 1);
    expect(decoded.width, 12);
    expect(decoded.height, 8);
    expect(decoded.getPixel(0, 0).r, greaterThan(200));
    expect(decoded.getPixel(0, 0).g, lessThan(40));
  });

  test('rejects PNG inflation beyond its declared image dimensions', () async {
    final source = File(p.join(root.path, 'inflated.png'));
    final original = image.encodePng(image.Image(width: 1, height: 1));
    final expanded = Uint8List(100000);
    final compressed = ZLibEncoder().convert(expanded);
    final bytes = Uint8List.fromList([
      ...original.take(33), // Signature and the valid 1x1 IHDR.
      ..._pngChunk('IDAT', compressed),
      ..._pngChunk('IEND', const []),
    ]);
    // The dependency otherwise accepts the excess inflated payload. The
    // normalizer must enforce the budget before that unbounded allocation.
    expect(image.decodePng(bytes), isNotNull);
    await source.writeAsBytes(bytes);
    await expectLater(
      const PhotoImportService().normalizeFile(source.path),
      _photoFailure(PhotoImportFailureCode.invalidImage),
    );
  });

  test('rejects compressed ICC expansion before JPEG serialization', () async {
    final source = File(p.join(root.path, 'icc-expansion.png'));
    final original = image.encodePng(image.Image(width: 1, height: 1));
    await source.writeAsBytes([
      ...original.take(33),
      ..._pngChunk('iCCP', [
        ...'profile'.codeUnits,
        0,
        0,
        ...ZLibEncoder().convert(Uint8List(100000)),
      ]),
      ...original.skip(33),
    ]);
    await expectLater(
      const PhotoImportService().normalizeFile(source.path),
      _photoFailure(PhotoImportFailureCode.invalidImage),
    );
  });

  test('preserves bounded PNG ICC metadata in normalized JPEG', () async {
    final source = File(p.join(root.path, 'bounded-icc.png'));
    final original = image.encodePng(image.Image(width: 2, height: 2));
    final profile = Uint8List.fromList(List.generate(128, (index) => index));
    await source.writeAsBytes([
      ...original.take(33),
      ..._pngChunk('iCCP', [
        ...'profile'.codeUnits,
        0,
        0,
        ...ZLibEncoder().convert(profile),
      ]),
      ...original.skip(33),
    ]);
    final normalized = await const PhotoImportService().normalizeFile(
      source.path,
    );
    // The dependency's PNG-to-JPEG path writes raw ICC bytes after the
    // signature, omitting JPEG's required sequence/count fields.
    final dependencyOutput = image.encodeJpg(
      image.decodePng(await source.readAsBytes())!,
    );
    expect(_jpegIccSegments(dependencyOutput).single.take(2), [0, 1]);
    final segments = _jpegIccSegments(normalized.bytes);
    expect(segments, hasLength(1));
    expect(segments.single.take(2), [1, 1]);
    expect(segments.single.skip(2), profile);
    expect(image.decodeJpg(normalized.bytes)!.iccProfile!.data, [
      1,
      1,
      ...profile,
    ]);
  });

  test(
    'reassembles bounded JPEG ICC chunks in their declared sequence',
    () async {
      final source = File(p.join(root.path, 'segmented-icc.jpg'));
      final original = image.encodeJpg(image.Image(width: 2, height: 2));
      final first = List<int>.generate(64, (index) => index);
      final second = List<int>.generate(64, (index) => index + 64);
      final bytes = Uint8List.fromList([
        ...original.take(2),
        ..._jpegIccChunk(2, 2, second),
        ..._jpegIccChunk(1, 2, first),
        ...original.skip(2),
      ]);
      // The pinned decoder keeps only the last physical APP2 block.
      expect(image.decodeJpg(bytes)!.iccProfile!.data, [1, 2, ...first]);
      await source.writeAsBytes(bytes);
      final normalized = await const PhotoImportService().normalizeFile(
        source.path,
      );
      expect(_jpegIccSegments(normalized.bytes).single, [
        1,
        1,
        ...first,
        ...second,
      ]);
    },
  );

  test('rejects incomplete, duplicated and oversized segmented ICC', () async {
    final source = File(p.join(root.path, 'invalid-icc.jpg'));
    final original = image.encodeJpg(image.Image(width: 2, height: 2));
    for (final chunks in [
      [
        _jpegIccChunk(1, 2, [1]),
      ],
      [
        _jpegIccChunk(1, 2, [1]),
        _jpegIccChunk(1, 2, [2]),
      ],
      [
        _jpegIccChunk(1, 2, Uint8List(32760)),
        _jpegIccChunk(2, 2, Uint8List(32760)),
      ],
    ]) {
      await source.writeAsBytes([
        ...original.take(2),
        for (final chunk in chunks) ...chunk,
        ...original.skip(2),
      ]);
      await expectLater(
        const PhotoImportService().normalizeFile(source.path),
        _photoFailure(PhotoImportFailureCode.invalidImage),
      );
    }
  });

  test(
    'rejects excessive GIF metadata before enumerating frame palettes',
    () async {
      final source = File(p.join(root.path, 'many-frames.gif'));
      // Transparent frames each cause the dependency to clone the global
      // palette despite normalization consuming only the first image frame.
      const frame = <int>[
        0x21,
        0xf9,
        4,
        1,
        0,
        0,
        0,
        0,
        0x2c,
        0,
        0,
        0,
        0,
        1,
        0,
        1,
        0,
        0,
        2,
        2,
        0x44,
        1,
        0,
      ];
      await source.writeAsBytes([
        ...'GIF89a'.codeUnits,
        1,
        0,
        1,
        0,
        0x87,
        0,
        0,
        ...Uint8List(256 * 3),
        for (var index = 0; index < 2050; index++) ...frame,
        0x3b,
      ]);
      await expectLater(
        const PhotoImportService().normalizeFile(source.path),
        _photoFailure(PhotoImportFailureCode.invalidImage),
      );
    },
  );

  test('rejects excessive PNG metadata records before decoding', () async {
    final source = File(p.join(root.path, 'many-chunks.png'));
    final original = image.encodePng(image.Image(width: 1, height: 1));
    await source.writeAsBytes([
      ...original.take(33),
      for (var index = 0; index < 4096; index++)
        ..._pngChunk('tEXt', [65, 0, 66]),
      ...original.skip(33),
    ]);
    await expectLater(
      const PhotoImportService().normalizeFile(source.path),
      _photoFailure(PhotoImportFailureCode.invalidImage),
    );
  });

  test('rejects GIF loop extensions that hide unchecked frame records', () async {
    final source = File(p.join(root.path, 'hidden-gif-records.gif'));
    final original = image.encodeGif(image.Image(width: 1, height: 1));
    final bytes = Uint8List.fromList([
      ...original.take(original.length - 1),
      0x21,
      0xff,
      11,
      ...'NETSCAPE2.0'.codeUnits,
      // A sub-block reader skips this payload. The pinned GIF decoder consumes
      // its first two bytes then treats the remainder as top-level records.
      4,
      1,
      0,
      0,
      0,
      0,
      0x3b,
    ]);
    expect(image.decodeGif(bytes, frame: 0), isNotNull);
    await source.writeAsBytes(bytes);
    await expectLater(
      const PhotoImportService().normalizeFile(source.path),
      _photoFailure(PhotoImportFailureCode.invalidImage),
    );
  });

  test('rejects EXIF too large for normalized JPEG metadata', () async {
    final source = File(p.join(root.path, 'large-exif.webp'));
    final original = image.encodeWebP(image.Image(width: 2, height: 2));
    final exif = Uint8List(26 + 65528);
    final directory = ByteData.sublistView(exif);
    directory.setUint16(0, 0x4949);
    directory.setUint16(2, 42, Endian.little);
    directory.setUint32(4, 8, Endian.little);
    directory.setUint16(8, 1, Endian.little);
    directory.setUint16(10, 0x010e, Endian.little);
    directory.setUint16(12, 2, Endian.little);
    directory.setUint32(14, 65528, Endian.little);
    directory.setUint32(18, 26, Endian.little);
    final chunkSize = ByteData(4)..setUint32(0, exif.length, Endian.little);
    final bytes = Uint8List.fromList([
      ...original,
      ...'EXIF'.codeUnits,
      ...chunkSize.buffer.asUint8List(),
      ...exif,
    ]);
    ByteData.sublistView(bytes).setUint32(4, bytes.length - 8, Endian.little);
    await source.writeAsBytes(bytes);
    await expectLater(
      const PhotoImportService().normalizeFile(source.path),
      _photoFailure(PhotoImportFailureCode.invalidImage),
    );
  });

  test(
    'rejects malformed fixed-length PNG metadata before decoder traversal',
    () async {
      final source = File(p.join(root.path, 'malformed-metadata.png'));
      final original = image.encodePng(image.Image(width: 2, height: 2));
      for (final type in ['pHYs', 'bKGD', 'acTL', 'fcTL', 'iCCP']) {
        await source.writeAsBytes([
          ...original.take(33),
          ..._pngChunk(type, [65, 65, 65]),
          ...original.skip(33),
        ]);
        await expectLater(
          const PhotoImportService().normalizeFile(source.path),
          _photoFailure(PhotoImportFailureCode.invalidImage),
          reason: type,
        );
      }
    },
  );

  for (final format in ['jpeg', 'bmp']) {
    test(
      '$format dimensions are checked before allocating decoder metadata',
      () async {
        final source = File(p.join(root.path, 'bounded.$format'));
        final pixels = image.Image(width: 20, height: 20);
        await source.writeAsBytes(
          format == 'jpeg' ? image.encodeJpg(pixels) : image.encodeBmp(pixels),
        );
        await expectLater(
          const PhotoImportService(
            policy: PhotoImportPolicy(maximumDecodedPixels: 100),
          ).normalizeFile(source.path),
          _photoFailure(PhotoImportFailureCode.dimensionsTooLarge),
        );
        final valid = await const PhotoImportService().normalizeFile(
          source.path,
        );
        expect((valid.width, valid.height), (20, 20));
      },
    );
  }

  test('rejects an oversized BMP palette before decoder allocation', () async {
    final source = File(p.join(root.path, 'palette.bmp'));
    final bytes = Uint8List.fromList(
      image.encodeBmp(image.Image(width: 2, height: 2)),
    );
    final header = ByteData.sublistView(bytes);
    header.setUint16(28, 8, Endian.little);
    header.setUint32(46, 0x40000000, Endian.little);
    await source.writeAsBytes(bytes);
    await expectLater(
      const PhotoImportService().normalizeFile(source.path),
      _photoFailure(PhotoImportFailureCode.invalidImage),
    );
  });

  test('rejects TIFF without entering its linked metadata parser', () async {
    final source = File(p.join(root.path, 'cycle.tiff'));
    final bytes = Uint8List.fromList(
      image.encodeTiff(image.Image(width: 2, height: 2)),
    );
    final data = ByteData.sublistView(bytes);
    final endian = data.getUint16(0) == 0x4949 ? Endian.little : Endian.big;
    final directory = data.getUint32(4, endian);
    final count = data.getUint16(directory, endian);
    data.setUint32(directory + 2 + count * 12, directory, endian);
    await source.writeAsBytes(bytes);
    await expectLater(
      const PhotoImportService().normalizeFile(source.path),
      _photoFailure(PhotoImportFailureCode.invalidImage),
    );
  });

  test('rejects a two-directory EXIF cycle before JPEG decoding', () async {
    final source = File(p.join(root.path, 'cyclic-exif.jpg'));
    final jpeg = image.encodeJpg(image.Image(width: 2, height: 2));
    final exif = Uint8List(20);
    final data = ByteData.sublistView(exif);
    data.setUint16(0, 0x4949);
    data.setUint16(2, 42, Endian.little);
    data.setUint32(4, 8, Endian.little);
    data.setUint32(10, 14, Endian.little);
    data.setUint32(16, 8, Endian.little);
    await source.writeAsBytes([
      ...jpeg.take(2),
      0xff,
      0xe1,
      0,
      exif.length + 8,
      ...'Exif\x00\x00'.codeUnits,
      ...exif,
      ...jpeg.skip(2),
    ]);
    await expectLater(
      const PhotoImportService().normalizeFile(source.path),
      _photoFailure(PhotoImportFailureCode.invalidImage),
    );
  });

  test(
    'preserves valid JPEG orientation through bounded metadata inspection',
    () async {
      final source = File(p.join(root.path, 'oriented.jpg'));
      final pixels = image.Image(width: 20, height: 10);
      pixels.exif.imageIfd.orientation = 6;
      await source.writeAsBytes(image.encodeJpg(pixels));
      final normalized = await const PhotoImportService().normalizeFile(
        source.path,
      );
      expect((normalized.width, normalized.height), (10, 20));
    },
  );

  test('rejects nested icon containers before pixel decoding', () async {
    final source = File(p.join(root.path, 'photo.ico'));
    await source.writeAsBytes(
      image.encodeIco(image.Image(width: 20, height: 20)),
    );
    await expectLater(
      const PhotoImportService().normalizeFile(source.path),
      _photoFailure(PhotoImportFailureCode.invalidImage),
    );
  });

  test('rejects corrupt or renamed non-image content', () async {
    final source = File(p.join(root.path, 'not-really-a-photo.jpg'));
    await source.writeAsString('private text, not an image');

    await expectLater(
      const PhotoImportService().normalizeFile(source.path),
      throwsA(
        isA<PhotoImportException>().having(
          (error) => error.code,
          'code',
          PhotoImportFailureCode.invalidImage,
        ),
      ),
    );
  });

  test('enforces source, decoded-pixel, and encoded-byte budgets', () async {
    final source = File(p.join(root.path, 'photo.png'));
    final pixels = image.Image(width: 20, height: 20)
      ..clear(image.ColorRgb8(15, 40, 180));
    await source.writeAsBytes(image.encodePng(pixels));

    await expectLater(
      const PhotoImportService(policy: PhotoImportPolicy(maximumSourceBytes: 8))
          .normalizeFile(source.path),
      _photoFailure(PhotoImportFailureCode.sourceTooLarge),
    );
    await expectLater(
      const PhotoImportService(
        policy: PhotoImportPolicy(maximumDecodedPixels: 100),
      ).normalizeFile(source.path),
      _photoFailure(PhotoImportFailureCode.dimensionsTooLarge),
    );
    await expectLater(
      const PhotoImportService(
        policy: PhotoImportPolicy(maximumEncodedBytes: 8),
      ).normalizeFile(source.path),
      _photoFailure(PhotoImportFailureCode.outputTooLarge),
    );
  });

  test('storage failure never commits photo metadata', () async {
    final originalPathProvider = PathProviderPlatform.instance;
    addTearDown(() => PathProviderPlatform.instance = originalPathProvider);
    final blockedDocumentsPath = File(p.join(root.path, 'not-a-directory'));
    await blockedDocumentsPath.writeAsString('occupied');
    PathProviderPlatform.instance = _FakePathProvider(
      blockedDocumentsPath.path,
    );

    final source = File(p.join(root.path, 'photo.png'));
    final pixels = image.Image(width: 20, height: 20)
      ..clear(image.ColorRgb8(70, 80, 90));
    await source.writeAsBytes(image.encodePng(pixels));

    final database = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftAssetRepository(database);
    final areaId = await repository.saveArea(
      name: 'Home',
      kind: AreaKind.indoor,
    );
    final roomId = await repository.saveRoom(areaId: areaId, name: 'Room');
    final assetId = await repository.saveAsset(
      name: 'Item',
      assetType: AssetType.general,
      roomId: roomId,
    );

    await expectLater(
      repository.addPhoto(assetId, source.path),
      throwsA(anything),
    );
    expect(await database.select(database.assetPhotos).get(), isEmpty);
  });
}

Matcher _photoFailure(PhotoImportFailureCode code) => throwsA(
  isA<PhotoImportException>().having((error) => error.code, 'code', code),
);

Uint8List _pngChunk(String type, List<int> payload) {
  final bytes = Uint8List(payload.length + 12);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, payload.length);
  bytes.setRange(4, 8, type.codeUnits);
  bytes.setRange(8, 8 + payload.length, payload);
  var crc = 0xffffffff;
  for (final byte in bytes.sublist(4, bytes.length - 4)) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xedb88320;
    }
  }
  data.setUint32(bytes.length - 4, crc ^ 0xffffffff);
  return bytes;
}

List<int> _jpegIccChunk(int sequence, int count, List<int> profile) {
  final length = 16 + profile.length;
  return [
    0xff,
    0xe2,
    length >> 8,
    length & 255,
    ...'ICC_PROFILE\x00'.codeUnits,
    sequence,
    count,
    ...profile,
  ];
}

List<Uint8List> _jpegIccSegments(Uint8List jpeg) {
  final data = ByteData.sublistView(jpeg);
  final segments = <Uint8List>[];
  for (var offset = 2; offset + 4 <= jpeg.length;) {
    final marker = jpeg[offset + 1];
    if (marker == 0xda || marker == 0xd9) break;
    final length = data.getUint16(offset + 2);
    if (marker == 0xe2 &&
        length >= 16 &&
        String.fromCharCodes(jpeg.sublist(offset + 4, offset + 16)) ==
            'ICC_PROFILE\x00') {
      segments.add(
        Uint8List.sublistView(jpeg, offset + 16, offset + 2 + length),
      );
    }
    offset += 2 + length;
  }
  return segments;
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}
