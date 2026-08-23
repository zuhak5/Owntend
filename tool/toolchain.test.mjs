import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  evaluateToolchainPolicy,
  generateToolchainManifest,
  loadCanonicalToolchain,
  sanitizePath,
} from './toolchain_manifest.mjs';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

async function read(relPath) {
  return fs.readFile(path.join(repositoryRoot, relPath), 'utf8');
}

test('Canonical toolchain configuration is complete and valid', async () => {
  const canonical = await loadCanonicalToolchain();
  assert.equal(canonical.schemaVersion, 1);
  assert.equal(canonical.reviewedBy, 'zuhak5');
  assert.ok(canonical.canonicalToolchain, 'canonicalToolchain block must exist');

  const tc = canonical.canonicalToolchain;
  assert.equal(tc.flutter.version, '3.47.0');
  assert.equal(tc.flutter.channel, 'stable');
  assert.equal(tc.dart.sdkConstraint, '^3.13.0');
  assert.equal(tc.java.version, '21');
  assert.equal(tc.java.distribution, 'temurin');
  assert.equal(tc.node.version, '24');
  assert.equal(tc.deno.version, '2.9.3');
  assert.equal(tc.android.compileSdkVersion, 36);
  assert.equal(tc.android.targetSdkVersion, 36);
  assert.equal(tc.android.minSdkVersion, 26);
  assert.equal(tc.android.buildToolsVersion, '36.0.0');
  assert.equal(tc.android.agpVersion, '9.3.0');
  assert.equal(tc.android.kotlinVersion, '2.4.10');
  assert.equal(tc.android.gradleDistribution, '9.6.1-bin');
  assert.equal(
    tc.android.gradleDistributionSha256,
    '9c0f7faeeb306cb14e4279a3e084ca6b596894089a0638e68a07c945a32c9e14'
  );
  assert.equal(tc.tools.sentryCli, '2.58.6');
  assert.equal(tc.tools.supabaseCli, '2.115.0');
  assert.equal(tc.tools.shorebirdCli.version, '1.6.119');
  assert.match(tc.tools.shorebirdCli.commit, /^[0-9a-f]{40}$/);
  assert.match(tc.tools.shorebirdCli.bundledFlutterRevision, /^[0-9a-f]{40}$/);
  assert.match(tc.tools.shorebirdCli.bundledEngineRevision, /^[0-9a-f]{40}$/);
  assert.equal(tc.tools.shorebirdCli.releaseFlutterVersion, tc.flutter.version);
  assert.match(tc.tools.shorebirdCli.releaseFlutterRevision, /^[0-9a-f]{40}$/);
  assert.match(tc.tools.shorebirdCli.releaseEngineRevision, /^[0-9a-f]{40}$/);
  assert.equal(tc.tools.bundletool.version, '1.18.3');
  assert.match(tc.tools.bundletool.sha256, /^[0-9a-f]{64}$/);
  assert.equal(tc.tools.gcloud, '581.0.0');
});

test('Repository configuration specifies matching canonical toolchain versions', async () => {
  const canonical = await loadCanonicalToolchain();
  const tc = canonical.canonicalToolchain;

  const pubspec = await read('pubspec.yaml');
  assert.match(pubspec, new RegExp(`flutter:\\s*">=3\\.47\\.0"`));
  assert.match(pubspec, new RegExp(`sdk:\\s*\\^3\\.13\\.0`));

  const settingsGradle = await read('android/settings.gradle.kts');
  assert.match(settingsGradle, new RegExp(`id\\("com\\.android\\.application"\\)\\s+version\\s+"${tc.android.agpVersion}"`));
  assert.match(settingsGradle, new RegExp(`id\\("org\\.jetbrains\\.kotlin\\.android"\\)\\s+version\\s+"${tc.android.kotlinVersion}"`));

  const wrapperProps = await read('android/gradle/wrapper/gradle-wrapper.properties');
  assert.match(wrapperProps, new RegExp(`gradle-${tc.android.gradleDistribution}\\.zip`));
  assert.match(wrapperProps, new RegExp(`distributionSha256Sum=${tc.android.gradleDistributionSha256}`));

  for (const workflow of [
    '.github/workflows/shorebird-release-android.yml',
    '.github/workflows/shorebird-patch-android.yml',
  ]) {
    assert.match(await read(workflow), /java-version:\s*"21"/);
  }
});

test('Toolchain policy evaluation detects mismatches and fails closed', async () => {
  const canonical = await loadCanonicalToolchain();

  const matchingResolved = {
    android: {
      agpVersion: '9.3.0',
      kotlinVersion: '2.4.10',
      gradleDistribution: '9.6.1-bin',
      gradleDistributionSha256: '9c0f7faeeb306cb14e4279a3e084ca6b596894089a0638e68a07c945a32c9e14',
      compileSdkVersion: 36,
      targetSdkVersion: 36,
    },
    node: { version: '24.11.1' },
    flutter: { version: '3.47.0' },
  };

  const passResult = evaluateToolchainPolicy(canonical, matchingResolved);
  assert.equal(passResult.status, 'PASS');
  assert.equal(passResult.errors.length, 0);

  // Test Flutter version mismatch
  const mismatchedFlutter = {
    ...matchingResolved,
    flutter: { version: '3.44.7' },
  };
  const failFlutter = evaluateToolchainPolicy(canonical, mismatchedFlutter);
  assert.equal(failFlutter.status, 'FAIL');
  assert.ok(failFlutter.errors.some(e => e.includes('Flutter version mismatch')));

  // Test Gradle checksum mismatch
  const mismatchedGradleSha = {
    ...matchingResolved,
    android: {
      ...matchingResolved.android,
      gradleDistributionSha256: '0000000000000000000000000000000000000000000000000000000000000000',
    },
  };
  const failGradle = evaluateToolchainPolicy(canonical, mismatchedGradleSha);
  assert.equal(failGradle.status, 'FAIL');
  assert.ok(failGradle.errors.some(e => e.includes('Gradle distribution checksum mismatch')));

  const missingShorebird = evaluateToolchainPolicy(canonical, matchingResolved, {
    requireShorebird: true,
  });
  assert.equal(missingShorebird.status, 'FAIL');
  assert.ok(missingShorebird.errors.some((error) => error.includes('Shorebird CLI mismatch')));

  const shorebirdPin = canonical.canonicalToolchain.tools.shorebirdCli;
  const matchingShorebird = {
    ...matchingResolved,
    shorebird: {
      version: shorebirdPin.version,
      commit: shorebirdPin.commit,
      flutterRevision: shorebirdPin.bundledFlutterRevision,
      engineRevision: shorebirdPin.bundledEngineRevision,
    },
  };
  const shorebirdPass = evaluateToolchainPolicy(canonical, matchingShorebird, {
    requireShorebird: true,
  });
  assert.equal(shorebirdPass.status, 'PASS');
});

test('Sanitizer redacts personal usernames and sensitive path roots', () => {
  assert.equal(
    sanitizePath('C:\\Users\\JohnDoe\\AppData\\Local\\Android\\Sdk'),
    '%USERPROFILE%/AppData/Local/Android/Sdk'
  );
  assert.equal(
    sanitizePath('/Users/alice/Library/Android/sdk'),
    '~/Library/Android/sdk'
  );
});

test('Release evidence collector includes and verifies toolchain manifest', async () => {
  const collector = await read('tool/collect_android_release_evidence.ps1');
  assert.match(collector, /toolchain_manifest\.mjs/);
  assert.match(collector, /resolved-toolchain-manifest\.json/);
  assert.match(collector, /toolchain_manifest_file\s*=\s*'resolved-toolchain-manifest\.json'/);
  assert.match(collector, /toolchain_manifest_sha256\s*=\s*\$toolchainManifestHash/);
  assert.match(collector, /toolchain_policy_verified\s*=\s*\$true/);
  assert.match(collector, /--require-shorebird/);
});
