import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  dartSatisfiesCaret,
  evaluateToolchainPolicy,
  generateToolchainManifest,
  loadCanonicalToolchain,
  parseJavaDistribution,
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
  assert.equal(tc.android.compileSdkVersion, 37);
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
  assert.match(tc.android.gradleWrapperJarSha256, /^[0-9a-f]{64}$/);
  assert.equal(tc.node.npmMajor, 11);
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
    java: { version: '21.0.5', distribution: 'temurin' },
    dart: { version: '3.13.0' },
    node: { version: '24.11.1', npmVersion: '11.7.0' },
    deno: { version: '2.9.3' },
    supabaseCli: { resolvedVersion: '2.115.0' },
    android: {
      agpVersion: '9.3.0',
      kotlinVersion: '2.4.10',
      gradleDistribution: '9.6.1-bin',
      gradleDistributionSha256: '9c0f7faeeb306cb14e4279a3e084ca6b596894089a0638e68a07c945a32c9e14',
      gradleWrapperJarSha256: canonical.canonicalToolchain.android.gradleWrapperJarSha256,
      compileSdkVersion: 37,
      targetSdkVersion: 36,
      minSdkVersion: 26,
      buildToolsVersion: '36.0.0',
    },
    flutter: { version: '3.47.0', channel: 'stable' },
  };

  const passResult = evaluateToolchainPolicy(canonical, matchingResolved);
  assert.equal(passResult.status, 'PASS', `Expected PASS, got errors: ${passResult.errors.join('; ')}`);
  assert.equal(passResult.errors.length, 0);

  // Every canonical field must have an executable check in ordinary mode.
  const checkNames = passResult.checks.map(check => check.name);
  for (const required of [
    'Java major version',
    'Java distribution',
    'Dart SDK compatibility',
    'Node.js major version',
    'npm major version',
    'Deno version',
    'Supabase CLI',
    'Android Gradle Plugin (AGP)',
    'Kotlin Plugin',
    'Gradle Distribution',
    'Gradle Distribution SHA-256',
    'Gradle wrapper JAR SHA-256',
    'Android compileSdk',
    'Android targetSdk',
    'Android minSdk',
    'Android build tools',
    'Flutter Version',
    'Flutter channel',
  ]) {
    assert.ok(
      checkNames.includes(required),
      `Policy must evaluate "${required}" explicitly.`,
    );
  }

  // Per-field mismatch fixtures: each enforced field fails when wrong.
  const mismatchFixtures = [
    ['java', { version: '17.0.17' }, /Java major version/],
    ['javaDistribution', null, /Java distribution/],
    ['dart', { version: '3.12.9' }, /Dart SDK mismatch/],
    ['nodeVersion', '23.5.0', /Node\.js major version/],
    ['npmVersion', '10.9.2', /npm major version/],
    ['deno', { version: '2.8.0' }, /Deno version mismatch/],
    ['supabaseCli', { resolvedVersion: '2.114.0' }, /Supabase CLI mismatch/],
    ['agp', '8.9.0', /Android Gradle Plugin \(AGP\)/],
    ['kotlin', '2.3.21', /Kotlin Plugin/],
    ['gradleDist', '9.5.0-bin', /Gradle Distribution/],
    ['gradleSha', '0000000000000000000000000000000000000000000000000000000000000000', /Gradle Distribution SHA-256/],
    ['wrapperJar', 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef', /Gradle wrapper JAR SHA-256/],
    ['compileSdk', 35, /Android compileSdk/],
    ['targetSdk', 35, /Android targetSdk/],
    ['minSdk', 24, /Android minSdk/],
    ['buildTools', '35.0.0', /Android build tools/],
    ['flutter', { version: '3.44.7', channel: 'stable' }, /Flutter Version/],
    ['flutterChannel', { version: '3.47.0', channel: 'beta' }, /Flutter channel/],
  ];

  for (const [fixtureName, override, expectedError] of mismatchFixtures) {
    const broken = structuredClone(matchingResolved);
    switch (fixtureName) {
      case 'java': Object.assign(broken.java, override); break;
      case 'javaDistribution': broken.java.distribution = override; break;
      case 'dart': Object.assign(broken.dart, override); break;
      case 'nodeVersion': broken.node.version = override; break;
      case 'npmVersion': broken.node.npmVersion = override; break;
      case 'deno': Object.assign(broken.deno, override); break;
      case 'supabaseCli': Object.assign(broken.supabaseCli, override); break;
      case 'agp': broken.android.agpVersion = override; break;
      case 'kotlin': broken.android.kotlinVersion = override; break;
      case 'gradleDist': broken.android.gradleDistribution = override; break;
      case 'gradleSha': broken.android.gradleDistributionSha256 = override; break;
      case 'wrapperJar': broken.android.gradleWrapperJarSha256 = override; break;
      case 'compileSdk': broken.android.compileSdkVersion = override; break;
      case 'targetSdk': broken.android.targetSdkVersion = override; break;
      case 'minSdk': broken.android.minSdkVersion = override; break;
      case 'buildTools': broken.android.buildToolsVersion = override; break;
      case 'flutter': case 'flutterChannel': Object.assign(broken.flutter, override); break;
      default: throw new Error(`Unknown fixture ${fixtureName}`);
    }
    const result = evaluateToolchainPolicy(canonical, broken);
    assert.equal(result.status, 'FAIL', `Expected FAIL for fixture ${fixtureName}`);
    assert.ok(
      result.errors.some(error => expectedError.test(error)),
      `Expected error matching ${expectedError} for fixture ${fixtureName}; got: ${result.errors.join('; ')}`,
    );
  }

  // Missing tools fail closed instead of being skipped silently.
  const missingDeno = structuredClone(matchingResolved);
  missingDeno.deno.version = null;
  const missingResult = evaluateToolchainPolicy(canonical, missingDeno);
  assert.equal(missingResult.status, 'FAIL');
  assert.ok(missingResult.errors.some(error => error.includes('Deno version missing')));

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

test('Java distribution parsing recognizes Temurin and unknown vendors', () => {
  const temurinOutput = [
    'openjdk version "21.0.5" 2026-01-20 LTS',
    'OpenJDK Runtime Environment Temurin-21.0.5+9 (build 21.0.5+9)',
    'OpenJDK 64-Bit Server VM Temurin-21.0.5+9 (build 21.0.5+9, mixed mode)',
  ].join('\n');
  assert.equal(parseJavaDistribution(temurinOutput), 'temurin');

  const plainOpenJdkOutput = [
    'openjdk version "21" 2026-01-20',
    'OpenJDK Runtime Environment (build 21+35)',
    'OpenJDK 64-Bit Server VM (build 21+35, mixed mode)',
  ].join('\n');
  assert.equal(parseJavaDistribution(plainOpenJdkOutput), null);

  assert.equal(parseJavaDistribution(null), null);
});

test('Dart caret constraint compatibility is evaluated correctly', () => {
  assert.equal(dartSatisfiesCaret('3.13.0', '^3.13.0'), true);
  assert.equal(dartSatisfiesCaret('3.13.9', '^3.13.0'), true);
  assert.equal(dartSatisfiesCaret('3.14.1', '^3.13.0'), true);
  assert.equal(dartSatisfiesCaret('3.12.9', '^3.13.0'), false);
  assert.equal(dartSatisfiesCaret('4.0.0', '^3.13.0'), false);
  assert.equal(dartSatisfiesCaret(null, '^3.13.0'), false);
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
