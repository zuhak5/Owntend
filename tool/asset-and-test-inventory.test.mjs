import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  CANONICAL_NODE_TESTS,
  discoverNodeTests,
  validateTestInventory,
} from './test_inventory.mjs';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

async function read(relPath) {
  return fs.readFile(path.join(repositoryRoot, relPath), 'utf8');
}

test('All discovered Node tests match canonical test inventory with no omissions', async () => {
  const result = await validateTestInventory(repositoryRoot);
  assert.equal(result.valid, true, `Test inventory validation errors: ${result.errors.join('; ')}`);
  assert.equal(result.unowned.length, 0, `Unowned test files found: ${result.unowned.join(', ')}`);
  assert.equal(result.missing.length, 0, `Missing test files: ${result.missing.join(', ')}`);
  assert.equal(result.discovered.length, CANONICAL_NODE_TESTS.length);
});

test('VersionDeck runtime assets exist and match service worker precache', async () => {
  const swContent = await read('download-site/sw.js');
  const appShellMatch = swContent.match(/const\s+APP_SHELL\s*=\s*\[([\s\S]*?)\];/);
  assert.ok(appShellMatch, 'sw.js must define const APP_SHELL');

  const appShellFiles = appShellMatch[1]
    .split('\n')
    .map(l => l.trim().replace(/^['"]\.\/|['"],?$/g, ''))
    .filter(f => f && f !== '');

  for (const relFile of appShellFiles) {
    const fullPath = path.join(repositoryRoot, 'download-site', relFile);
    const exists = await fs.access(fullPath).then(() => true).catch(() => false);
    assert.ok(exists, `Precached asset in sw.js does not exist on disk: download-site/${relFile}`);
  }
});

test('VersionDeck validation script checks all required runtime assets', async () => {
  const validator = await read('tool/validate_versiondeck.mjs');
  const requiredFiles = [
    'build-status-timeline.css',
    'build-status-timeline.js',
    'sticky-download-fix.css',
    'sticky-download-fix.js',
    'build-status.css',
    'build-status-ui.css',
    'build-status.js',
    'build-status-ui.js',
    'sw.js',
    'app.js',
    'manifest-schema.js',
  ];

  for (const req of requiredFiles) {
    assert.ok(
      validator.includes(`"${req}"`) || validator.includes(`'${req}'`),
      `validate_versiondeck.mjs must require runtime file: ${req}`
    );
  }
});

