import { execFileSync } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

export const CANONICAL_NODE_TESTS = [
  'tool/account-deletion-site.test.mjs',
  'tool/android-lint-gate.test.mjs',
  'tool/asset-and-test-inventory.test.mjs',
  'tool/asset-provenance.test.mjs',
  'tool/build-status-timeline.test.mjs',
  'tool/build-status-ui.test.mjs',
  'tool/build-status.test.mjs',
  'tool/dependency-security-and-notices.test.mjs',
  'tool/provenance_policy.test.mjs',
  'tool/release-workflows.test.mjs',
  'tool/sticky-download-fix.test.mjs',
  'tool/supabase-advisors.test.mjs',
  'tool/toolchain.test.mjs',
  'tool/versiondeck.test.mjs',
];

export async function discoverNodeTests(rootDir = repositoryRoot) {
  const toolDir = path.join(rootDir, 'tool');
  const entries = await fs.readdir(toolDir, { withFileTypes: true });
  const discovered = [];
  for (const entry of entries) {
    if (entry.isFile() && entry.name.endsWith('.test.mjs')) {
      discovered.push(`tool/${entry.name}`);
    }
  }
  return discovered.sort();
}

export async function validateTestInventory(rootDir = repositoryRoot) {
  const discovered = await discoverNodeTests(rootDir);
  const canonicalSet = new Set(CANONICAL_NODE_TESTS);
  const discoveredSet = new Set(discovered);

  const unowned = discovered.filter(f => !canonicalSet.has(f));
  const missing = CANONICAL_NODE_TESTS.filter(f => !discoveredSet.has(f));

  const errors = [];
  if (unowned.length > 0) {
    errors.push(`Unowned test files found: ${unowned.join(', ')}. Register them in CANONICAL_NODE_TESTS.`);
  }
  if (missing.length > 0) {
    errors.push(`Missing canonical test files: ${missing.join(', ')}.`);
  }

  return {
    valid: errors.length === 0,
    discovered,
    canonical: CANONICAL_NODE_TESTS,
    unowned,
    missing,
    errors,
  };
}

export function runAllNodeTests(rootDir = repositoryRoot) {
  const testFiles = CANONICAL_NODE_TESTS.map(f => path.join(rootDir, f));
  try {
    const output = execFileSync(process.execPath, ['--test', ...testFiles], {
      cwd: rootDir,
      encoding: 'utf8',
      stdio: ['ignore', 'inherit', 'inherit'],
    });
    return { success: true, output };
  } catch (err) {
    return { success: false, error: err };
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const inventoryResult = await validateTestInventory();
  if (!inventoryResult.valid) {
    console.error('Test inventory validation failed:');
    for (const error of inventoryResult.errors) {
      console.error(`  - ${error}`);
    }
    process.exit(1);
  }

  console.log(`Test inventory verified: all ${inventoryResult.canonical.length} Node tests are registered and owned.`);
  for (const t of inventoryResult.canonical) {
    console.log(`  - ${t}`);
  }

  if (process.argv.includes('--run') || process.argv.includes('--test')) {
    console.log('\nRunning all canonical Node test suites:');
    const runResult = runAllNodeTests();
    if (!runResult.success) {
      console.error('One or more test suites failed.');
      process.exit(1);
    }
  }
}
