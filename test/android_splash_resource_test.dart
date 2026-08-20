import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 12 splash reuses light assets in dark mode', () {
    const densities = <String>['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];

    for (final density in densities) {
      final normal = File(
        'android/app/src/main/res/drawable-$density/android12splash.png',
      );
      final night = File(
        'android/app/src/main/res/drawable-night-$density/android12splash.png',
      );

      expect(normal.existsSync(), isTrue, reason: normal.path);
      expect(
        night.existsSync(),
        isFalse,
        reason:
            'Dark mode intentionally reuses the light Android 12 splash. '
            'Regenerate with tool/generate_native_splash.dart so identical '
            'night copies are pruned.',
      );
    }

    for (final path in [
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
    ]) {
      final contents = File(path).readAsStringSync();
      expect(contents, contains('@drawable/android12splash'), reason: path);
    }
  });

  test('native splash regeneration uses the repository wrapper', () {
    const path = 'tool/generate_native_splash.dart';
    final wrapper = File(path).readAsStringSync();
    expect(wrapper, contains('flutter_native_splash:create'));
    expect(wrapper, contains('Refusing to prune'));
    expect(wrapper, contains('A distinct dark splash must remain packaged.'));
  });
}
