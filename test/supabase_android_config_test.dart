import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest does not expose a browser OAuth callback', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(manifest, isNot(contains('android:screenOrientation="portrait"')));
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, isNot(contains('android.intent.action.VIEW')));
    expect(manifest, isNot(contains('android.intent.category.BROWSABLE')));
    expect(manifest, isNot(contains('auth-callback')));
    expect(manifest, contains('android:allowBackup="false"'));
  });

  test('Android flavors use separate package names', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('create("dev")'));
    expect(gradle, contains('applicationIdSuffix = ".dev"'));
    expect(gradle, contains('create("staging")'));
    expect(gradle, contains('applicationIdSuffix = ".staging"'));
    expect(gradle, contains('create("prod")'));
    expect(gradle, contains('applicationId = "app.owntend.mobile"'));
    expect(gradle, isNot(contains('authRedirectScheme')));
  });

  test('Google Services and direct Firebase Analytics stay removed', () {
    final appGradle = File('android/app/build.gradle.kts').readAsStringSync();
    final rootGradle = File('android/build.gradle.kts').readAsStringSync();
    final settingsGradle = File('android/settings.gradle.kts')
        .readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final gitignore = File('.gitignore').readAsStringSync();

    for (final gradle in [appGradle, rootGradle, settingsGradle]) {
      expect(gradle, isNot(contains('com.google.firebase:firebase-analytics')));
      expect(gradle, isNot(contains('com.google.gms.google-services')));
      expect(
        gradle.contains('google-services.json') && gradle.contains('.exists'),
        isFalse,
      );
    }
    expect(pubspec, isNot(contains('firebase_analytics:')));
    expect(
      File('android/app/google-services.json.example').existsSync(),
      isFalse,
    );
    expect(gitignore, contains('/android/app/google-services.json'));
    expect(gitignore, contains('/android/app/src/*/google-services.json'));
  });

  test('production Android builds reject missing Supabase Dart defines', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('name.startsWith("preProd")'));
    expect(gradle, contains('--dart-define-from-file=config/prod.json'));
    expect(gradle, contains('SUPABASE_PUBLISHABLE_KEY'));
    expect(gradle, contains('GOOGLE_WEB_CLIENT_ID'));
  });

  test('guarded production build preserves maintained registrants', () {
    final script = File('tool/build_prod.ps1').readAsStringSync();

    expect(script, contains(r'$relativePath -match'));
    expect(script, contains('debug|profile'));
    expect(script, contains('continue'));
    expect(
      script,
      contains(r'$registrantPath.Substring($workspacePrefix.Length)'),
    );
    expect(script, isNot(contains('[System.IO.Path]::GetRelativePath')));
    expect(
      script,
      contains(
        r'android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java',
      ),
    );
    expect(
      script,
      isNot(
        contains(
          r'android\app\src\release\java\io\flutter\plugins\GeneratedPluginRegistrant.java',
        ),
      ),
    );
    expect(script, contains('Remove-GeneratedAndroidRegistrants'));
    expect(script, contains("-Pattern 'IntegrationTestPlugin'"));
    expect(
      script,
      contains('Release plugin registrant contains integration_test'),
    );
  });
}
