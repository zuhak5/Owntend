import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

export async function loadCanonicalToolchain(rootDir = repositoryRoot) {
  const toolchainPath = path.join(rootDir, 'config', 'toolchain.json');
  const content = await fs.readFile(toolchainPath, 'utf8');
  return JSON.parse(content);
}

function safeExec(cmd, args = [], options = {}) {
  try {
    const output = execFileSync(cmd, args, {
      encoding: 'utf8',
      timeout: 10000,
      stdio: ['ignore', 'pipe', 'pipe'],
      ...options,
    });
    return output.trim();
  } catch (err) {
    return null;
  }
}

export function sanitizePath(rawPath) {
  if (!rawPath || typeof rawPath !== 'string') return '';
  // Redact personal user directories and normalize separators
  return rawPath
    .replace(/[A-Z]:\\Users\\[^\\]+\\/gi, '%USERPROFILE%\\')
    .replace(/\/Users\/[^\/]+\//g, '~/')
    .replace(/\\/g, '/');
}

export async function collectResolvedToolchain(rootDir = repositoryRoot) {
  const nodeVersion = process.version.replace(/^v/, '');
  const npmVersion = safeExec('npm', ['--version']);
  const denoVersionRaw = safeExec('deno', ['--version']);
  let denoVersion = null;
  if (denoVersionRaw) {
    const match = denoVersionRaw.match(/^deno\s+([0-9.]+)/m);
    if (match) denoVersion = match[1];
  }

  const javaVersionRaw = safeExec('java', ['-version']);
  let javaVersion = null;
  if (javaVersionRaw) {
    const match = javaVersionRaw.match(/(?:version|openjdk version)\s+"([^"]+)"/i);
    if (match) javaVersion = match[1];
  }

  const flutterVersionRaw = safeExec('flutter', ['--version']);
  let flutterVersion = null;
  let dartVersion = null;
  let flutterChannel = null;
  if (flutterVersionRaw) {
    const fMatch = flutterVersionRaw.match(/Flutter\s+([0-9.]+)/i);
    if (fMatch) flutterVersion = fMatch[1];
    const cMatch = flutterVersionRaw.match(/channel\s+([a-zA-Z0-9_-]+)/i);
    if (cMatch) flutterChannel = cMatch[1];
    const dMatch = flutterVersionRaw.match(/Dart\s+([0-9.]+)/i);
    if (dMatch) dartVersion = dMatch[1];
  }

  // Gradle wrapper properties inspection
  let gradleDistribution = null;
  let gradleChecksum = null;
  try {
    const wrapperProps = await fs.readFile(
      path.join(rootDir, 'android', 'gradle', 'wrapper', 'gradle-wrapper.properties'),
      'utf8'
    );
    const urlMatch = wrapperProps.match(/distributionUrl=.*gradle-([0-9.]+(?:-[a-z]+)?)\.zip/);
    if (urlMatch) gradleDistribution = urlMatch[1];
    const shaMatch = wrapperProps.match(/distributionSha256Sum=([0-9a-f]{64})/i);
    if (shaMatch) gradleChecksum = shaMatch[1].toLowerCase();
  } catch {}

  // Android build gradle inspection
  let agpVersion = null;
  let kotlinVersion = null;
  try {
    const settings = await fs.readFile(path.join(rootDir, 'android', 'settings.gradle.kts'), 'utf8');
    const agpMatch = settings.match(/id\("com\.android\.application"\)\s+version\s+"([^"]+)"/);
    if (agpMatch) agpVersion = agpMatch[1];
    const ktMatch = settings.match(/id\("org\.jetbrains\.kotlin\.android"\)\s+version\s+"([^"]+)"/);
    if (ktMatch) kotlinVersion = ktMatch[1];
  } catch {}

  let compileSdk = null;
  let targetSdk = null;
  try {
    const appBuild = await fs.readFile(path.join(rootDir, 'android', 'app', 'build.gradle.kts'), 'utf8');
    const cMatch = appBuild.match(/compileSdk\s*=\s*(\d+)/);
    if (cMatch) compileSdk = parseInt(cMatch[1], 10);
    const tMatch = appBuild.match(/targetSdk\s*=\s*(\d+)/);
    if (tMatch) targetSdk = parseInt(tMatch[1], 10);
  } catch {}

  const shorebirdHome = process.env.SHOREBIRD_HOME;
  let shorebirdVersion = null;
  let shorebirdCommit = null;
  let shorebirdFlutterRevision = null;
  let shorebirdEngineRevision = null;
  if (shorebirdHome) {
    shorebirdCommit = safeExec('git', ['-C', shorebirdHome, 'rev-parse', 'HEAD']);
    try {
      const shorebirdPubspec = await fs.readFile(
        path.join(shorebirdHome, 'packages', 'shorebird_cli', 'pubspec.yaml'),
        'utf8',
      );
      const versionMatch = shorebirdPubspec.match(/^version:\s*([0-9.]+)\s*$/m);
      if (versionMatch) shorebirdVersion = versionMatch[1];
    } catch {}
    try {
      shorebirdFlutterRevision = (
        await fs.readFile(path.join(shorebirdHome, 'bin', 'internal', 'flutter.version'), 'utf8')
      ).trim();
    } catch {}
    try {
      shorebirdEngineRevision = (
        await fs.readFile(
          path.join(
            shorebirdHome,
            'bin',
            'cache',
            'flutter',
            shorebirdFlutterRevision || '',
            'bin',
            'internal',
            'engine.version',
          ),
          'utf8',
        )
      ).trim();
    } catch {}
  }

  return {
    runner: {
      platform: os.platform(),
      release: os.release(),
      arch: os.arch(),
      type: os.type(),
    },
    flutter: {
      version: flutterVersion,
      channel: flutterChannel,
    },
    dart: {
      version: dartVersion,
    },
    java: {
      version: javaVersion,
    },
    node: {
      version: nodeVersion,
      npmVersion,
    },
    deno: {
      version: denoVersion,
    },
    android: {
      compileSdkVersion: compileSdk,
      targetSdkVersion: targetSdk,
      agpVersion,
      kotlinVersion,
      gradleDistribution,
      gradleDistributionSha256: gradleChecksum,
    },
    shorebird: {
      version: shorebirdVersion,
      commit: shorebirdCommit,
      flutterRevision: shorebirdFlutterRevision,
      engineRevision: shorebirdEngineRevision,
    },
  };
}

export function evaluateToolchainPolicy(canonical, resolved, { requireShorebird = false } = {}) {
  const checks = [];
  const errors = [];

  const cAndroid = canonical.canonicalToolchain?.android || {};
  const rAndroid = resolved.android || {};

  // Check Android Gradle plugin version
  if (cAndroid.agpVersion) {
    const pass = rAndroid.agpVersion === cAndroid.agpVersion;
    checks.push({ name: 'Android Gradle Plugin (AGP)', expected: cAndroid.agpVersion, actual: rAndroid.agpVersion, pass });
    if (!pass) errors.push(`AGP version mismatch: expected ${cAndroid.agpVersion}, got ${rAndroid.agpVersion}`);
  }

  // Check Kotlin version
  if (cAndroid.kotlinVersion) {
    const pass = rAndroid.kotlinVersion === cAndroid.kotlinVersion;
    checks.push({ name: 'Kotlin Plugin', expected: cAndroid.kotlinVersion, actual: rAndroid.kotlinVersion, pass });
    if (!pass) errors.push(`Kotlin version mismatch: expected ${cAndroid.kotlinVersion}, got ${rAndroid.kotlinVersion}`);
  }

  // Check Gradle distribution
  if (cAndroid.gradleDistribution) {
    const pass = rAndroid.gradleDistribution === cAndroid.gradleDistribution;
    checks.push({ name: 'Gradle Distribution', expected: cAndroid.gradleDistribution, actual: rAndroid.gradleDistribution, pass });
    if (!pass) errors.push(`Gradle distribution mismatch: expected ${cAndroid.gradleDistribution}, got ${rAndroid.gradleDistribution}`);
  }

  // Check Gradle distribution checksum
  if (cAndroid.gradleDistributionSha256) {
    const pass = (rAndroid.gradleDistributionSha256 || '').toLowerCase() === cAndroid.gradleDistributionSha256.toLowerCase();
    checks.push({ name: 'Gradle Distribution SHA-256', expected: cAndroid.gradleDistributionSha256, actual: rAndroid.gradleDistributionSha256, pass });
    if (!pass) errors.push(`Gradle distribution checksum mismatch: expected ${cAndroid.gradleDistributionSha256}, got ${rAndroid.gradleDistributionSha256}`);
  }

  // Check compileSdk and targetSdk
  if (cAndroid.compileSdkVersion) {
    const pass = rAndroid.compileSdkVersion === cAndroid.compileSdkVersion;
    checks.push({ name: 'Android compileSdk', expected: cAndroid.compileSdkVersion, actual: rAndroid.compileSdkVersion, pass });
    if (!pass) errors.push(`compileSdk mismatch: expected ${cAndroid.compileSdkVersion}, got ${rAndroid.compileSdkVersion}`);
  }

  if (cAndroid.targetSdkVersion) {
    const pass = rAndroid.targetSdkVersion === cAndroid.targetSdkVersion;
    checks.push({ name: 'Android targetSdk', expected: cAndroid.targetSdkVersion, actual: rAndroid.targetSdkVersion, pass });
    if (!pass) errors.push(`targetSdk mismatch: expected ${cAndroid.targetSdkVersion}, got ${rAndroid.targetSdkVersion}`);
  }

  // Check Node version (major)
  const cNode = canonical.canonicalToolchain?.node?.version;
  if (cNode && resolved.node?.version) {
    const pass = resolved.node.version.startsWith(cNode);
    checks.push({ name: 'Node.js Version', expected: `^${cNode}`, actual: resolved.node.version, pass });
    if (!pass) errors.push(`Node.js version mismatch: expected ^${cNode}, got ${resolved.node.version}`);
  }

  // Check Flutter version if resolved
  const cFlutter = canonical.canonicalToolchain?.flutter?.version;
  if (cFlutter && resolved.flutter?.version) {
    const pass = resolved.flutter.version === cFlutter;
    checks.push({ name: 'Flutter Version', expected: cFlutter, actual: resolved.flutter.version, pass });
    if (!pass) errors.push(`Flutter version mismatch: expected ${cFlutter}, got ${resolved.flutter.version}`);
  }

  if (requireShorebird) {
    const expected = canonical.canonicalToolchain?.tools?.shorebirdCli || {};
    const actual = resolved.shorebird || {};
    for (const [actualField, expectedField, name] of [
      ['version', 'version', 'Shorebird CLI'],
      ['commit', 'commit', 'Shorebird CLI commit'],
      ['flutterRevision', 'bundledFlutterRevision', 'Shorebird bundled Flutter revision'],
      ['engineRevision', 'bundledEngineRevision', 'Shorebird bundled engine revision'],
    ]) {
      const pass = Boolean(expected[expectedField]) && actual[actualField] === expected[expectedField];
      checks.push({ name, expected: expected[expectedField], actual: actual[actualField], pass });
      if (!pass) {
        errors.push(`${name} mismatch: expected ${expected[expectedField]}, got ${actual[actualField]}`);
      }
    }
  }

  return {
    status: errors.length === 0 ? 'PASS' : 'FAIL',
    checks,
    errors,
  };
}

export async function generateToolchainManifest({
  outputDirectory = null,
  sourceSha = process.env.GITHUB_SHA || 'HEAD',
  rootDir = repositoryRoot,
  requireShorebird = false,
} = {}) {
  const canonical = await loadCanonicalToolchain(rootDir);
  const resolved = await collectResolvedToolchain(rootDir);
  const policy = evaluateToolchainPolicy(canonical, resolved, { requireShorebird });

  const manifest = {
    schemaVersion: 1,
    generatedAtUtc: new Date().toISOString(),
    sourceSha,
    canonicalToolchain: canonical.canonicalToolchain,
    resolvedToolchain: resolved,
    policyEvaluation: policy,
  };

  const manifestContent = JSON.stringify(manifest, null, 2);
  const manifestSha256 = crypto.createHash('sha256').update(manifestContent).digest('hex').toLowerCase();

  let manifestPath = null;
  if (outputDirectory) {
    await fs.mkdir(outputDirectory, { recursive: true });
    manifestPath = path.join(outputDirectory, 'resolved-toolchain-manifest.json');
    await fs.writeFile(manifestPath, manifestContent, 'utf8');
  }

  return {
    manifest,
    manifestPath,
    manifestSha256,
    policy,
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  let outputDirectory = null;
  let sourceSha = process.env.GITHUB_SHA || 'HEAD';
  let enforce = false;
  let requireShorebird = false;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--output-directory' && args[i + 1]) {
      outputDirectory = path.resolve(args[++i]);
    } else if (args[i] === '--source-sha' && args[i + 1]) {
      sourceSha = args[++i];
    } else if (args[i] === '--enforce') {
      enforce = true;
    } else if (args[i] === '--require-shorebird') {
      requireShorebird = true;
    }
  }

  const result = await generateToolchainManifest({
    outputDirectory,
    sourceSha,
    requireShorebird,
  });

  if (result.manifestPath) {
    console.log(`Generated Toolchain Manifest: ${result.manifestPath} (SHA256: ${result.manifestSha256})`);
  }
  console.log(`Toolchain Policy Evaluation: ${result.policy.status}`);
  for (const check of result.policy.checks) {
    console.log(`  [${check.pass ? 'PASS' : 'FAIL'}] ${check.name}: expected ${check.expected}, actual ${check.actual}`);
  }

  if (enforce && result.policy.status !== 'PASS') {
    console.error(`Toolchain policy enforcement failed: ${result.policy.errors.join('; ')}`);
    process.exit(1);
  }
}
