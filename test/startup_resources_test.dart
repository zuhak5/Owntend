import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/owntend_animated_splash_screen.dart';

({int width, int height}) _pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return (
    width: data.getUint32(16, Endian.big),
    height: data.getUint32(20, Endian.big),
  );
}

Future<({int width, int height, int minX, int minY, int maxX, int maxY})>
_nonBlackBounds(String path, {int minimumBrightness = 45}) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(pixels, isNotNull);
  var minX = image.width;
  var minY = image.height;
  var maxX = -1;
  var maxY = -1;
  final bytes = pixels!.buffer.asUint8List();
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final offset = (y * image.width + x) * 4;
      if (bytes[offset + 3] == 0 ||
          bytes[offset] + bytes[offset + 1] + bytes[offset + 2] <=
              minimumBrightness) {
        continue;
      }
      minX = x < minX ? x : minX;
      minY = y < minY ? y : minY;
      maxX = x > maxX ? x : maxX;
      maxY = y > maxY ? y : maxY;
    }
  }
  final bounds = (
    width: image.width,
    height: image.height,
    minX: minX,
    minY: minY,
    maxX: maxX,
    maxY: maxY,
  );
  image.dispose();
  codec.dispose();
  return bounds;
}

Future<int> _cornerAlpha(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(pixels, isNotNull);
  final alpha = pixels!.getUint8(3);
  image.dispose();
  codec.dispose();
  return alpha;
}

Future<bool> _brightArtworkFitsCircle(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(pixels, isNotNull);
  final bytes = pixels!.buffer.asUint8List();
  final center = (image.width - 1) / 2;
  final radiusSquared = math.pow(image.width * 0.49, 2);
  var foundArtwork = false;
  var fits = true;
  for (var y = 0; y < image.height && fits; y++) {
    for (var x = 0; x < image.width; x++) {
      final offset = (y * image.width + x) * 4;
      final brightness = bytes[offset] + bytes[offset + 1] + bytes[offset + 2];
      if (bytes[offset + 3] == 0 || brightness < 260) {
        continue;
      }
      foundArtwork = true;
      final dx = x - center;
      final dy = y - center;
      if ((dx * dx) + (dy * dy) > radiusSquared) {
        fits = false;
        break;
      }
    }
  }
  image.dispose();
  codec.dispose();
  return foundArtwork && fits;
}

Future<bool> _opaqueArtworkFitsCircle(
  String path, {
  required double radius,
}) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(pixels, isNotNull);
  final bytes = pixels!.buffer.asUint8List();
  final centerX = (image.width - 1) / 2;
  final centerY = (image.height - 1) / 2;
  final radiusSquared = radius * radius;
  var foundArtwork = false;
  var fits = true;
  for (var y = 0; y < image.height && fits; y++) {
    for (var x = 0; x < image.width; x++) {
      final alpha = bytes[(y * image.width + x) * 4 + 3];
      if (alpha == 0) continue;
      foundArtwork = true;
      final dx = x - centerX;
      final dy = y - centerY;
      if ((dx * dx) + (dy * dy) > radiusSquared) {
        fits = false;
        break;
      }
    }
  }
  image.dispose();
  codec.dispose();
  return foundArtwork && fits;
}

void main() {
  test('process splash has one fixed presentation lifetime', () {
    expect(owntendSplashDisplayDuration, const Duration(milliseconds: 3200));
    expect(owntendSplashFadeOutDuration, const Duration(milliseconds: 250));
    expect(owntendSplashBackground.toARGB32(), 0xFFF9FCF8);
  });

  test('first runApp child owns the process splash above startup branches', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('runApp(OwntendProcessSplash(child: child))'));
    expect(
      source,
      contains('_runOwntendProcess(const OwntendStartupFailure())'),
    );
    expect(source, contains('_DeferredOwntendBootstrap('));
    expect(source, isNot(contains('startup-theme-placeholder')));
    expect(source, isNot(contains('return OwntendSplashOverlay(')));
  });

  test('Android native splash uses the final borderless 3D icon', () {
    final launchBackground = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();
    expect(launchBackground, contains('@drawable/background'));
    expect(launchBackground, contains('@drawable/splash'));

    final colors = File('android/app/src/main/res/values/colors.xml')
        .readAsStringSync();
    expect(colors, contains('#F9FCF8'));

    final modernStyles = File('android/app/src/main/res/values-v31/styles.xml')
        .readAsStringSync();
    expect(modernStyles, contains('@drawable/android12splash'));
    expect(modernStyles, contains('#F9FCF8'));
    expect(modernStyles, isNot(contains('icon_background_color')));

    for (final path in [
      'android/app/src/main/res/drawable/launch_mark.xml',
      'android/app/src/main/res/drawable/launch_mark_animated.xml',
      'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
      'android/app/src/main/res/animator/launch_reveal_heart.xml',
      'android/app/src/main/res/animator/launch_scale_x.xml',
      'android/app/src/main/res/animator/launch_scale_y.xml',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });

  test(
    'Android launch-only APIs are isolated to supported resource levels',
    () {
      for (final path in [
        'android/app/src/main/res/values/styles.xml',
        'android/app/src/main/res/values-night/styles.xml',
      ]) {
        final baseStyles = File(path).readAsStringSync();
        expect(baseStyles, isNot(contains('android:forceDarkAllowed')));
        expect(
          baseStyles,
          isNot(contains('android:windowLayoutInDisplayCutoutMode')),
        );
      }

      for (final path in [
        'android/app/src/main/res/values-v27/styles.xml',
        'android/app/src/main/res/values-night-v27/styles.xml',
      ]) {
        final api27Styles = File(path).readAsStringSync();
        expect(
          api27Styles,
          contains('android:windowLayoutInDisplayCutoutMode'),
        );
        expect(api27Styles, isNot(contains('android:forceDarkAllowed')));
      }

      for (final path in [
        'android/app/src/main/res/values-v29/styles.xml',
        'android/app/src/main/res/values-night-v29/styles.xml',
        'android/app/src/main/res/values-v31/styles.xml',
        'android/app/src/main/res/values-night-v31/styles.xml',
      ]) {
        final modernStyles = File(path).readAsStringSync();
        expect(modernStyles, contains('android:forceDarkAllowed'));
        expect(
          modernStyles,
          contains('android:windowLayoutInDisplayCutoutMode'),
        );
      }
    },
  );

  test('Android backup and transfer rules exclude private app data', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(manifest, isNot(contains('android:screenOrientation="portrait"')));

    final legacyRules = File('android/app/src/main/res/xml/backup_rules.xml')
        .readAsStringSync();
    final modernRules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    for (final domain in [
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
    ]) {
      expect(legacyRules, contains('domain="$domain" path="."'));
      expect(modernRules, contains('domain="$domain" path="."'));
    }
    expect(modernRules, contains('<cloud-backup>'));
    expect(modernRules, contains('<device-transfer>'));
  });

  test('Android restore foreground service is declared as data sync', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(
      manifest,
      contains('android.permission.FOREGROUND_SERVICE_DATA_SYNC'),
    );
    expect(
      manifest,
      contains('com.pravera.flutter_foreground_task.service.ForegroundService'),
    );
    expect(manifest, contains('android:foregroundServiceType="dataSync"'));
    expect(manifest, contains('android:exported="false"'));
  });

  test('Android system bars use API-safe insets implementations', () {
    final activity = File(
      'android/app/src/main/kotlin/app/zuhak5/Owntend/MainActivity.kt',
    ).readAsStringSync();
    expect(
      activity,
      contains('if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)'),
    );
    expect(
      activity,
      contains('WindowCompat.setDecorFitsSystemWindows(window, false)'),
    );
    expect(
      activity,
      contains('WindowCompat.setDecorFitsSystemWindows(window, true)'),
    );
    expect(activity, contains('window.decorView.systemUiVisibility = flags'));
    expect(activity, contains('View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY'));
    expect(
      activity,
      contains('window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)'),
    );
    expect(
      activity,
      isNot(
        contains('window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)'),
      ),
    );
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:windowSoftInputMode="adjustResize"'));
  });

  test('popup menus use the root navigator for touch ownership', () {
    final sources = [
      File('lib/main.dart').readAsStringSync(),
      File('lib/src/ui/components.dart').readAsStringSync(),
    ].join('\n');
    final menuCount = RegExp(r'PopupMenuButton<').allMatches(sources).length;
    final rootNavigatorCount = RegExp(
      r'PopupMenuButton<[\s\S]*?useRootNavigator:\s*true,',
    ).allMatches(sources).length;
    expect(menuCount, greaterThan(0));
    expect(rootNavigatorCount, menuCount);
  });

  test('Android launcher and splash PNGs have exact density dimensions', () {
    for (final path in [
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml',
    ]) {
      final contents = File(path).readAsStringSync();
      expect(contents, contains('@mipmap/ic_launcher_foreground'));
      expect(contents, contains('@color/ic_launcher_background'));
    }
    const variants = {
      'mdpi': (legacy: 48, foreground: 108),
      'hdpi': (legacy: 72, foreground: 162),
      'xhdpi': (legacy: 96, foreground: 216),
      'xxhdpi': (legacy: 144, foreground: 324),
      'xxxhdpi': (legacy: 192, foreground: 432),
    };
    for (final entry in variants.entries) {
      for (final name in ['ic_launcher.png', 'ic_launcher_round.png']) {
        expect(_pngSize('android/app/src/main/res/mipmap-${entry.key}/$name'), (
          width: entry.value.legacy,
          height: entry.value.legacy,
        ));
      }
      expect(
        _pngSize(
          'android/app/src/main/res/mipmap-${entry.key}/'
          'ic_launcher_foreground.png',
        ),
        (width: entry.value.foreground, height: entry.value.foreground),
      );
    }

    expect(_pngSize('assets/brand/Owntend.png'), (width: 1254, height: 1254));
    expect(_pngSize('assets/splash/owntend_splash_icon_3d.png'), (
      width: 432,
      height: 432,
    ));
    expect(_pngSize('assets/splash/owntend_splash_android12.png'), (
      width: 1152,
      height: 1152,
    ));
    expect(
      _pngSize('android/app/src/main/res/drawable-nodpi/splash_icon.png'),
      (width: 432, height: 432),
    );
  });

  test('launcher artwork fits circular masks and splash safe areas', () async {
    const launcherDirectory = 'android/app/src/main/res/mipmap-xxxhdpi/';
    expect(
      await _brightArtworkFitsCircle(
        '${launcherDirectory}ic_launcher_foreground.png',
      ),
      isTrue,
    );
    final foreground = await _nonBlackBounds(
      '${launcherDirectory}ic_launcher_foreground.png',
      minimumBrightness: 260,
    );
    final foregroundInset = (foreground.width * 0.15).round();
    expect(foreground.minX, greaterThanOrEqualTo(foregroundInset));
    expect(foreground.minY, greaterThanOrEqualTo(foregroundInset));
    expect(foreground.maxX, lessThan(foreground.width - foregroundInset));
    expect(foreground.maxY, lessThan(foreground.height - foregroundInset));
    expect(await _cornerAlpha('${launcherDirectory}ic_launcher.png'), 255);
    expect(await _cornerAlpha('${launcherDirectory}ic_launcher_round.png'), 0);

    expect(await _cornerAlpha('assets/splash/owntend_splash_icon_3d.png'), 0);
    expect(await _cornerAlpha('assets/splash/owntend_splash_android12.png'), 0);
    expect(
      await _opaqueArtworkFitsCircle(
        'assets/splash/owntend_splash_android12.png',
        radius: 384,
      ),
      isTrue,
    );
    final android12Bounds = await _nonBlackBounds(
      'assets/splash/owntend_splash_android12.png',
    );
    expect(
      (android12Bounds.minX + android12Bounds.maxX) / 2,
      closeTo(575.5, 2),
    );
    expect(
      (android12Bounds.minY + android12Bounds.maxY) / 2,
      closeTo(575.5, 2),
    );
    expect(
      await _cornerAlpha(
        'android/app/src/main/res/drawable-nodpi/splash_icon.png',
      ),
      0,
    );
  });

  test('Android path provider stays on the verified implementation', () {
    final lockfile = File('pubspec.lock')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final pathProviderBlock = RegExp(
      r'^  path_provider_android:\n(?:(?!^  \S).*\n)*',
      multiLine: true,
    ).firstMatch(lockfile)?.group(0);
    expect(pathProviderBlock, isNotNull);
    expect(pathProviderBlock, contains('version: "2.2.23"'));

    for (final mode in ['debug', 'profile', 'release']) {
      final registrantFile = File(
        'android/app/src/$mode/java/io/flutter/plugins/'
        'GeneratedPluginRegistrant.java',
      );

      // Generated plugin registrants are ignored and may not exist in a
      // clean checkout until Flutter performs an Android build.
      if (!registrantFile.existsSync()) {
        continue;
      }

      final registrant = registrantFile.readAsStringSync();
      expect(
        registrant,
        contains('new io.flutter.plugins.pathprovider.PathProviderPlugin()'),
        reason: '$mode must register the verified path provider implementation',
      );
      expect(
        registrant,
        isNot(contains('com.github.dart_lang.jni')),
        reason: '$mode must not retain stale JNI plugin registrations',
      );
    }
  });
}
