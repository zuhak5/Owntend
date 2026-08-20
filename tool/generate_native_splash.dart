import 'dart:io';

const _android12Densities = <String>[
  'mdpi',
  'hdpi',
  'xhdpi',
  'xxhdpi',
  'xxxhdpi',
];

Future<void> main(List<String> args) async {
  final root = File.fromUri(Platform.script).parent.parent;

  if (args.length > 1 || (args.isNotEmpty && args.single != '--check')) {
    stderr.writeln('Usage: dart run tool/generate_native_splash.dart [--check]');
    exitCode = 64;
    return;
  }

  if (args.isEmpty) {
    final process = await Process.start(
      Platform.resolvedExecutable,
      const ['run', 'flutter_native_splash:create'],
      workingDirectory: root.path,
      mode: ProcessStartMode.inheritStdio,
    );
    final result = await process.exitCode;
    if (result != 0) {
      stderr.writeln('flutter_native_splash:create failed with exit code $result.');
      exitCode = result;
      return;
    }

    await _pruneDuplicateAndroid12NightAssets(root);
  }

  _verifyAndroid12SplashContract(root);
}

Future<void> _pruneDuplicateAndroid12NightAssets(Directory root) async {
  for (final density in _android12Densities) {
    final normal = File(
      '${root.path}/android/app/src/main/res/drawable-$density/android12splash.png',
    );
    final night = File(
      '${root.path}/android/app/src/main/res/drawable-night-$density/android12splash.png',
    );

    if (!night.existsSync()) continue;
    if (!normal.existsSync()) {
      throw StateError(
        'Refusing to prune ${night.path}: matching light resource is missing.',
      );
    }

    final normalBytes = await normal.readAsBytes();
    final nightBytes = await night.readAsBytes();
    if (!_sameBytes(normalBytes, nightBytes)) {
      throw StateError(
        'Refusing to prune ${night.path}: it differs from ${normal.path}. '
        'A distinct dark splash must remain packaged.',
      );
    }

    await night.delete();
    final nightDirectory = night.parent;
    if (nightDirectory.existsSync() && nightDirectory.listSync().isEmpty) {
      await nightDirectory.delete();
    }
    stdout.writeln('Pruned duplicate Android 12 night splash: ${night.path}');
  }
}

void _verifyAndroid12SplashContract(Directory root) {
  for (final density in _android12Densities) {
    final normal = File(
      '${root.path}/android/app/src/main/res/drawable-$density/android12splash.png',
    );
    final night = File(
      '${root.path}/android/app/src/main/res/drawable-night-$density/android12splash.png',
    );

    if (!normal.existsSync()) {
      throw StateError('Missing Android 12 splash resource: ${normal.path}');
    }
    if (night.existsSync()) {
      throw StateError(
        'Duplicate Android 12 night splash is present: ${night.path}. '
        'Regenerate through tool/generate_native_splash.dart.',
      );
    }
  }

  for (final relativePath in [
    'android/app/src/main/res/values-v31/styles.xml',
    'android/app/src/main/res/values-night-v31/styles.xml',
  ]) {
    final file = File('${root.path}/$relativePath');
    final contents = file.readAsStringSync();
    if (!contents.contains('@drawable/android12splash')) {
      throw StateError('$relativePath must reference @drawable/android12splash.');
    }
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
