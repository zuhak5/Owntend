import { readFileSync } from 'node:fs';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

const REQUIRED_LF_RULES = [
  '*.dart text eol=lf',
  '*.ts text eol=lf',
  '*.js text eol=lf',
  '*.mjs text eol=lf',
  '*.json text eol=lf',
  '*.yaml text eol=lf',
  '*.yml text eol=lf',
  '*.toml text eol=lf',
  '*.sql text eol=lf',
  '*.md text eol=lf',
];

const REQUIRED_BINARY_RULES = ['*.png binary', '*.jar binary', '*.ttf binary'];

test('.gitattributes normalizes canonical source types to LF', () => {
  const attributes = readFileSync(path.join(repositoryRoot, '.gitattributes'), 'utf8');
  for (const rule of REQUIRED_LF_RULES) {
    assert.ok(
      attributes.includes(rule),
      `Expected .gitattributes to contain "${rule}" so formatter checks stay deterministic across platforms.`,
    );
  }
});

test('.gitattributes excludes binary artifacts from normalization', () => {
  const attributes = readFileSync(path.join(repositoryRoot, '.gitattributes'), 'utf8');
  for (const rule of REQUIRED_BINARY_RULES) {
    assert.ok(
      attributes.includes(rule),
      `Expected .gitattributes to mark "${rule}" so binaries are never normalized.`,
    );
  }
});

test('.gitignore has no duplicate effective ignore entries', () => {
  const rawLines = readFileSync(path.join(repositoryRoot, '.gitignore'), 'utf8')
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(line => line.length > 0 && !line.startsWith('#'));
  const seen = new Map();
  const duplicates = [];
  for (const line of rawLines) {
    if (seen.has(line)) {
      duplicates.push(line);
    }
    seen.set(line, true);
  }
  assert.deepEqual(
    duplicates,
    [],
    `Duplicate .gitignore entries hide intentional policy: ${duplicates.join(', ')}`,
  );
});

test('analysis_options.yaml excludes only recognized build and platform paths', () => {
  const analysisOptions = readFileSync(
    path.join(repositoryRoot, 'analysis_options.yaml'),
    'utf8',
  );
  // flutter_tools (3.47) re-adds the standard platform excludes on every
  // `pub get` / `gen-l10n` upgrade pass, so their presence is accepted even
  // though this Android-first repository has no such directories. Any other
  // absent directory must stay excluded from the analyzer exclude list.
  const flutterManagedExcludes = new Set(['ios', 'web', 'windows', 'macos', 'linux']);
  const excludedPlatforms = ['ios', 'web', 'windows', 'macos', 'linux'].filter(platform =>
    new RegExp(`- ${platform}/\\*\\*`, 'm').test(analysisOptions),
  );
  for (const platform of excludedPlatforms) {
    if (flutterManagedExcludes.has(platform)) continue;
    assert.ok(
      existsSync(path.join(repositoryRoot, platform)),
      `analysis_options.yaml excludes "${platform}" but the repository has no such directory.`,
    );
  }
});

test('tracked SQL sources never begin with a UTF-8 byte-order mark', async () => {
  const { readdir, readFile } = await import('node:fs/promises');
  const sqlFiles = [];
  const walk = async (dir) => {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        await walk(full);
      } else if (entry.name.endsWith('.sql')) {
        sqlFiles.push(full);
      }
    }
  };
  await walk(path.join(repositoryRoot, 'supabase'));
  for (const file of sqlFiles) {
    const head = (await readFile(file)).subarray(0, 3);
    const hasBom = head[0] === 0xef && head[1] === 0xbb && head[2] === 0xbf;
    assert.equal(
      hasBom,
      false,
      `${path.relative(repositoryRoot, file)} begins with a UTF-8 BOM; the Postgres parser rejects it.`,
    );
  }
});
