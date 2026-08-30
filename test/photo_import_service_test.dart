import 'dart:io';

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

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}
