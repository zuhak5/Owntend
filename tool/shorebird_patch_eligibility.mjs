import { execFileSync } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

const hardBlockedFiles = new Set([
  'l10n.yaml',
  'pubspec.lock',
  'pubspec.yaml',
  'shorebird.yaml',
  'shorebird.yaml.template',
]);

const hardBlockedPrefixes = [
  '.dart_tool/',
  '.github/',
  'android/',
  'assets/',
  'config/',
  'download-site/',
  'ios/',
  'linux/',
  'macos/',
  'web/',
  'windows/',
];

const allowedApplicationFiles = [
  /^lib\/.*\.dart$/,
  /^lib\/l10n\/.*\.arb$/,
];

const neutralPrefixes = [
  'docs/',
  'integration_test/',
  'supabase/',
  'test/',
  'tool/',
];

const neutralFiles = new Set([
  '.gitignore',
  'AGENTS.md',
  'CHANGELOG.md',
  'CONTRIBUTING.md',
  'PRIVACY.md',
  'README.md',
  'SECURITY.md',
  'package-lock.json',
  'package.json',
]);

export function classifyPatchPath(rawPath) {
  const normalized = rawPath.replaceAll('\\', '/').replace(/^\.\//, '');
  if (hardBlockedFiles.has(normalized)) {
    return { path: normalized, status: 'blocked', reason: 'release or dependency contract changed' };
  }
  if (hardBlockedPrefixes.some((prefix) => normalized.startsWith(prefix))) {
    return { path: normalized, status: 'blocked', reason: 'native, asset, toolchain, or delivery input changed' };
  }
  if (allowedApplicationFiles.some((pattern) => pattern.test(normalized))) {
    return { path: normalized, status: 'patchable', reason: 'Dart/localization source change' };
  }
  if (neutralFiles.has(normalized) || neutralPrefixes.some((prefix) => normalized.startsWith(prefix))) {
    return { path: normalized, status: 'neutral', reason: 'not packaged into the Flutter application' };
  }
  return { path: normalized, status: 'blocked', reason: 'unclassified path fails closed' };
}

function git(rootDir, args) {
  return execFileSync('git', ['-C', rootDir, ...args], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

function requireCommit(rootDir, ref, label) {
  try {
    return git(rootDir, ['rev-parse', '--verify', `${ref}^{commit}`]);
  } catch {
    throw new Error(`${label} does not resolve to a Git commit: ${ref}`);
  }
}

export async function evaluatePatchEligibility({
  baseRef,
  candidateRef = 'HEAD',
  rootDir = repositoryRoot,
} = {}) {
  if (!baseRef) throw new Error('A release base reference is required.');
  const baseSha = requireCommit(rootDir, baseRef, 'Base reference');
  const candidateSha = requireCommit(rootDir, candidateRef, 'Candidate reference');
  if (baseSha === candidateSha) {
    throw new Error('The candidate is identical to the release base; there is no patch to publish.');
  }

  let ancestor = false;
  try {
    execFileSync('git', ['-C', rootDir, 'merge-base', '--is-ancestor', baseSha, candidateSha], {
      stdio: 'ignore',
    });
    ancestor = true;
  } catch {}
  if (!ancestor) {
    throw new Error('The release base is not an ancestor of the patch candidate.');
  }

  const diff = git(rootDir, [
    'diff',
    '--name-only',
    '--diff-filter=ACDMRTUXB',
    `${baseSha}..${candidateSha}`,
    '--',
  ]);
  const files = diff ? diff.split(/\r?\n/).filter(Boolean).map(classifyPatchPath) : [];
  const blocked = files.filter((entry) => entry.status === 'blocked');
  const patchable = files.filter((entry) => entry.status === 'patchable');
  const errors = [];
  if (blocked.length > 0) {
    errors.push(...blocked.map((entry) => `${entry.path}: ${entry.reason}`));
  }
  if (patchable.length === 0) {
    errors.push('No patchable Flutter source changed.');
  }

  return {
    schemaVersion: 1,
    baseSha,
    candidateSha,
    eligible: errors.length === 0,
    files,
    errors,
    policy: {
      assetDiffsAllowed: false,
      nativeDiffsAllowed: false,
      unknownPathsAllowed: false,
    },
  };
}

async function main() {
  const args = process.argv.slice(2);
  let baseRef = null;
  let candidateRef = 'HEAD';
  let output = null;
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === '--base-ref' && args[index + 1]) baseRef = args[++index];
    else if (args[index] === '--candidate-ref' && args[index + 1]) candidateRef = args[++index];
    else if (args[index] === '--output' && args[index + 1]) output = path.resolve(args[++index]);
    else throw new Error(`Unknown or incomplete argument: ${args[index]}`);
  }
  const result = await evaluatePatchEligibility({ baseRef, candidateRef });
  const content = `${JSON.stringify(result, null, 2)}\n`;
  if (output) {
    await fs.mkdir(path.dirname(output), { recursive: true });
    await fs.writeFile(output, content, 'utf8');
  }
  process.stdout.write(content);
  if (!result.eligible) process.exitCode = 1;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await main();
}
