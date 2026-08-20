import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const asset = 'assets/illustrations/owntend-onboarding-hero-target.webp';

  test(
    '$asset has feathered transparent perimeter and opaque subject',
    () async {
      final codec = await ui.instantiateImageCodec(
        File(asset).readAsBytesSync(),
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(data, isNotNull);
      final bytes = data!.buffer.asUint8List();
      final edgeX = (image.width * 0.04).floor();
      final edgeY = (image.height * 0.04).floor();
      var edgeAlpha = 0;
      var edgePixels = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          if (x >= edgeX &&
              x < image.width - edgeX &&
              y >= edgeY &&
              y < image.height - edgeY) {
            continue;
          }
          edgeAlpha += bytes[(y * image.width + x) * 4 + 3];
          edgePixels++;
        }
      }
      final centerAlpha =
          bytes[((image.height ~/ 2) * image.width + image.width ~/ 2) * 4 + 3];
      expect(edgeAlpha / edgePixels, lessThan(55));
      expect(centerAlpha, greaterThan(245));
      image.dispose();
      codec.dispose();
    },
  );
}
