import { execFileSync, spawnSync } from 'node:child_process';
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
  // Version probes print to stdout or stderr depending on the tool
  // (java -version writes to stderr), so both streams are captured.
  const spawnOptions = {
    encoding: 'utf8',
    timeout: 60000,
    windowsHide: true,
    ...options,
  };

  let result = spawnSync(cmd, args, spawnOptions);
  if (result.error && process.platform === 'win32') {
    // Windows resolves .cmd/.bat launchers (npm, flutter) only through the shell.
    const commandLine = [quoteCommand(cmd), ...args.map(quoteArg)].join(' ');
    result = spawnSync(commandLine, { ...spawnOptions, shell: true });
  }
  const output = `${result.stdout || ''}\n${result.stderr || ''}`.trim();
  return output.length > 0 && !result.error ? output : null;
}

function quoteCommand(cmd) {
  return /[\s"]/.test(cmd) ? `"${cmd.replace(/"/g, '\\"')}"` : cmd;
}

function quoteArg(arg) {
  return typeof arg === 'string' && /[\s"]/.test(arg) ? `"${arg.replace(/"/g, '\\"')}"` : arg;
}

export function parseJavaDistribution(versionOutput) {
  if (!versionOutput) return null;
  const match = versionOutput.match(/(?:VM|Client VM|Server VM)\s+([A-Za-z][A-Za-z0-9]*)[-_\s]/);
  if (!match) return null;
  const vendor = match[1].toLowerCase();
  // Normalize common vendor spellings to the canonical distribution name.
  if (vendor.startsWith('temurin')) return 'temurin';
  return vendor;
}

async function sha256File(filePath) {
  try {
    const contents = await fs.readFile(filePath);
    return crypto.createHash('sha256').update(contents).digest('hex').toLowerCase();
  } catch {
    return null;
  }
}

async function readInstalledSupabaseCliVersion(rootDir) {
  try {
    const pkg = JSON.parse(
      await fs.readFile(path.join(rootDir, 'node_modules', 'supabase', 'package.json'), 'utf8'),
    );
    return typeof pkg.version === 'string' ? pkg.version : null;
  } catch {
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
  const javaDistribution = parseJavaDistribution(javaVersionRaw);

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
  let minSdk = null;
  let buildToolsVersion = null;
  try {
    const appBuild = await fs.readFile(path.join(rootDir, 'android', 'app', 'build.gradle.kts'), 'utf8');
    const cMatch = appBuild.match(/compileSdk\s*=\s*(\d+)/);
    if (cMatch) compileSdk = parseInt(cMatch[1], 10);
    const tMatch = appBuild.match(/targetSdk\s*=\s*(\d+)/);
    if (tMatch) targetSdk = parseInt(tMatch[1], 10);
    const minMatch = appBuild.match(/minSdk\s*=\s*(\d+)/);
    if (minMatch) minSdk = parseInt(minMatch[1], 10);
    const btMatch = appBuild.match(/buildToolsVersion\s*=\s*"([^"]+)"/);
    if (btMatch) buildToolsVersion = btMatch[1];
  } catch {}

  // Gradle wrapper bootstrap integrity: the tracked JAR must hash to the
  // canonical value recorded in config/toolchain.json.
  const gradleWrapperJarSha256 = await sha256File(
    path.join(rootDir, 'android', 'gradle', 'wrapper', 'gradle-wrapper.jar'),
  );

  const supabaseCliResolved = await readInstalledSupabaseCliVersion(rootDir);

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
      distribution: javaDistribution,
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
      minSdkVersion: minSdk,
      buildToolsVersion,
      agpVersion,
      kotlinVersion,
      gradleDistribution,
      gradleDistributionSha256: gradleChecksum,
      gradleWrapperJarSha256,
    },
    supabaseCli: {
      resolvedVersion: supabaseCliResolved,
    },
    shorebird: {
      version: shorebirdVersion,
      commit: shorebirdCommit,
      flutterRevision: shorebirdFlutterRevision,
      engineRevision: shorebirdEngineRevision,
    },
  };
}

function checkField(checks, errors, name, expected, actual) {
  const pass = actual !== null && actual !== undefined && String(actual).toLowerCase() === String(expected).toLowerCase();
  checks.push({ name, expected, actual: actual ?? 'NOT FOUND', pass });
  if (!pass) {
    if (actual === null || actual === undefined) {
      errors.push(`${name} missing: canonical toolchain requires ${expected}. Install the tool or point PATH/JAVA_HOME at the pinned release.`);
    } else {
      errors.push(`${name} mismatch: expected ${expected}, got ${actual}`);
    }
  }
}

export function dartSatisfiesCaret(resolvedVersion, caretConstraint) {
  if (!resolvedVersion || !caretConstraint) return false;
  const match = caretConstraint.match(/^\^(\d+)\.(\d+)\.(\d+)$/);
  if (!match) return false;
  const [, major, minor, patch] = match.map(Number);
  const resolved = resolvedVersion.split('.').map(Number);
  if (resolved.length < 3 || resolved.some(Number.isNaN)) return false;
  const [rMajor, rMinor, rPatch] = resolved;
  if (major === 0) {
    return rMajor === major && rMinor === minor && rPatch >= patch;
  }
  return (
    rMajor === major &&
    (rMinor > minor || (rMinor === minor && rPatch >= patch))
  );
}

export function evaluateToolchainPolicy(canonical, resolved, { requireShorebird = false } = {}) {
  const checks = [];
  const errors = [];

  const cAndroid = canonical.canonicalToolchain?.android || {};
  const rAndroid = resolved.android || {};

  // --- Java runtime: enforced whenever the toolchain gate runs. ---
  const cJava = canonical.canonicalToolchain?.java;
  if (cJava?.version) {
    const actualMajor = resolved.java?.version ? parseInt(resolved.java.version.split('.')[0], 10) : null;
    checkField(checks, errors, 'Java major version', cJava.version, Number.isNaN(actualMajor) ? null : actualMajor);
  }
  if (cJava?.distribution) {
    checkField(checks, errors, 'Java distribution', cJava.distribution, resolved.java?.distribution);
  }

  // --- Dart SDK compatibility with the canonical constraint. ---
  const cDart = canonical.canonicalToolchain?.dart;
  if (cDart?.sdkConstraint) {
    const pass = dartSatisfiesCaret(resolved.dart?.version, cDart.sdkConstraint);
    checks.push({ name: 'Dart SDK compatibility', expected: cDart.sdkConstraint, actual: resolved.dart?.version ?? 'NOT FOUND', pass });
    if (!pass) {
      errors.push(`Dart SDK mismatch: expected ${cDart.sdkConstraint}, got ${resolved.dart?.version ?? 'NOT FOUND'}`);
    }
  }

  // --- Node.js and npm majors ---
  const cNode = canonical.canonicalToolchain?.node;
  if (cNode?.version) {
    const actualMajor = resolved.node?.version ? parseInt(resolved.node.version.split('.')[0], 10) : null;
    checkField(checks, errors, 'Node.js major version', cNode.version, Number.isNaN(actualMajor) ? null : actualMajor);
  }
  if (cNode?.npmMajor) {
    const actualNpmMajor = resolved.node?.npmVersion ? parseInt(resolved.node.npmVersion.split('.')[0], 10) : null;
    checkField(checks, errors, 'npm major version', cNode.npmMajor, Number.isNaN(actualNpmMajor) ? null : actualNpmMajor);
  }

  // --- Deno exact pin ---
  const cDeno = canonical.canonicalToolchain?.deno;
  if (cDeno?.version) {
    checkField(checks, errors, 'Deno version', cDeno.version, resolved.deno?.version);
  }

  // --- Supabase CLI exact pin (resolved from installed npm dependency) ---
  const cSupabaseCli = canonical.canonicalToolchain?.tools?.supabaseCli;
  if (cSupabaseCli) {
    checkField(
      checks,
      errors,
      'Supabase CLI',
      cSupabaseCli,
      resolved.supabaseCli?.resolvedVersion,
    );
  }

  // --- Android build inputs ---
  if (cAndroid.agpVersion) {
    checkField(checks, errors, 'Android Gradle Plugin (AGP)', cAndroid.agpVersion, rAndroid.agpVersion);
  }
  if (cAndroid.kotlinVersion) {
    checkField(checks, errors, 'Kotlin Plugin', cAndroid.kotlinVersion, rAndroid.kotlinVersion);
  }
  if (cAndroid.gradleDistribution) {
    checkField(checks, errors, 'Gradle Distribution', cAndroid.gradleDistribution, rAndroid.gradleDistribution);
  }
  if (cAndroid.gradleDistributionSha256) {
    checkField(checks, errors, 'Gradle Distribution SHA-256', cAndroid.gradleDistributionSha256.toLowerCase(), rAndroid.gradleDistributionSha256);
  }
  if (cAndroid.gradleWrapperJarSha256) {
    checkField(checks, errors, 'Gradle wrapper JAR SHA-256', cAndroid.gradleWrapperJarSha256, rAndroid.gradleWrapperJarSha256);
  }
  if (cAndroid.compileSdkVersion) {
    checkField(checks, errors, 'Android compileSdk', cAndroid.compileSdkVersion, rAndroid.compileSdkVersion);
  }
  if (cAndroid.targetSdkVersion) {
    checkField(checks, errors, 'Android targetSdk', cAndroid.targetSdkVersion, rAndroid.targetSdkVersion);
  }
  if (cAndroid.minSdkVersion) {
    checkField(checks, errors, 'Android minSdk', cAndroid.minSdkVersion, rAndroid.minSdkVersion);
  }
  if (cAndroid.buildToolsVersion) {
    checkField(checks, errors, 'Android build tools', cAndroid.buildToolsVersion, rAndroid.buildToolsVersion);
  }

  // --- Flutter exact release and channel ---
  const cFlutter = canonical.canonicalToolchain?.flutter;
  if (cFlutter?.version) {
    checkField(checks, errors, 'Flutter Version', cFlutter.version, resolved.flutter?.version);
    if (cFlutter.channel) {
      checkField(checks, errors, 'Flutter channel', cFlutter.channel, resolved.flutter?.channel);
    }
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
