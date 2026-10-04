import { readFileSync } from 'node:fs';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import { spawnSync } from 'node:child_process';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

test('backend serve bootstrap preserves spaces and apostrophes in every path', async (t) => {
  const shell = process.platform === 'win32' ? 'powershell.exe' : 'pwsh';
  const probe = spawnSync(shell, ['-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()'], { encoding: 'utf8' });
  if (probe.error?.code === 'ENOENT') {
    t.skip('PowerShell is required to execute the generated backend bootstrap');
    return;
  }
  assert.equal(probe.status, 0, probe.stderr);
  const source = readFileSync(path.join(repositoryRoot, 'tool/run_local_backend_integration.ps1'), 'utf8');
  const start = source.indexOf("    $serveBootstrap = Join-Path $workspace 'run-functions-serve.ps1'");
  const end = source.indexOf('    $serveWindowOptions =', start);
  assert.ok(start >= 0 && end > start, 'Use the actual bootstrap construction from the runner');
  const construction = source.slice(start, end);
  const fixture = await fs.mkdtemp(path.join(os.tmpdir(), 'owntend-backend-bootstrap-'));
  try {
    for (const [name, workspaceName, cliName] of [
      ['spaces', 'Workspace with spaces', 'Supabase CLI.ps1'],
      ['workspace apostrophe', "Owner's workspace", 'Supabase CLI.ps1'],
      ['CLI apostrophe', 'Another workspace', "Supabase's CLI.ps1"],
      ['curly workspace quote', 'Owner\u2019s workspace', 'Supabase CLI.ps1'],
      ['curly CLI quotes', 'Unicode workspace', 'Supabase\u2018\u2019\u201a\u201b CLI.ps1'],
      ['Unicode paths', '\u0645\u062c\u0644\u062f \u0627\u062e\u062a\u0628\u0627\u0631', '\u0623\u062f\u0627\u0629.ps1'],
    ]) {
      const workspace = path.join(fixture, workspaceName);
      const supabaseDir = path.join(workspace, 'supabase');
      const cli = path.join(fixture, cliName);
      const record = path.join(workspace, 'invocation.json');
      await fs.mkdir(supabaseDir, { recursive: true });
      // A script-local stub records the invocation. No real CLI, network,
      // containers, credentials, signing or build command can be reached.
      await fs.writeFile(cli, `
        $captured = [pscustomobject]@{ WorkingDirectory = (Get-Location).ProviderPath; Arguments = @($args) }
        [IO.File]::WriteAllText($env:OWNTEND_BOOTSTRAP_TEST_RECORD, ($captured | ConvertTo-Json -Depth 4))
        Write-Output 'STUB_EXECUTED'
      `);
      const harness = path.join(fixture, 'generate-and-run.ps1');
      await fs.writeFile(harness, `
        $ErrorActionPreference = 'Stop'
        $workspace = $env:OWNTEND_BOOTSTRAP_TEST_WORKSPACE
        $supabaseCli = $env:OWNTEND_BOOTSTRAP_TEST_CLI
        $envFile = Join-Path $workspace 'functions.env'
        $serveLog = Join-Path $workspace 'functions-serve.log'
        $serveErr = Join-Path $workspace 'functions-serve.err.log'
        ${construction}
        & $serveBootstrap
      `);
      const result = spawnSync(shell, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', harness], {
        cwd: fixture,
        encoding: 'utf8',
        timeout: 10_000,
        env: {
          ...process.env,
          OWNTEND_BOOTSTRAP_TEST_WORKSPACE: workspace,
          OWNTEND_BOOTSTRAP_TEST_CLI: cli,
          OWNTEND_BOOTSTRAP_TEST_RECORD: record,
        },
      });
      assert.equal(result.status, 0, `${name}: ${result.error?.message ?? result.stderr}`);
      const invoked = JSON.parse(await fs.readFile(record, 'utf8'));
      assert.equal(await fs.realpath(invoked.WorkingDirectory), await fs.realpath(supabaseDir), name);
      assert.deepEqual(invoked.Arguments, ['functions', 'serve', '--env-file', path.join(workspace, 'functions.env')], name);
      // Windows PowerShell redirects text as UTF-16LE; pwsh uses UTF-8.
      const stdoutBytes = await fs.readFile(path.join(workspace, 'functions-serve.log'));
      const stdout = stdoutBytes[0] === 0xff && stdoutBytes[1] === 0xfe
        ? stdoutBytes.subarray(2).toString('utf16le') : stdoutBytes.toString('utf8');
      assert.match(stdout, /STUB_EXECUTED/, name);
      assert.equal((await fs.readFile(path.join(workspace, 'functions-serve.err.log'))).length, 0, name);
    }
  } finally {
    assert.equal(path.dirname(path.resolve(fixture)), path.resolve(os.tmpdir()));
    assert.match(path.basename(fixture), /^owntend-backend-bootstrap-/);
    await fs.rm(fixture, { recursive: true, force: true });
  }
});

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
