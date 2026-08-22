import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { classifyPatchPath } from './shorebird_patch_eligibility.mjs';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));
const read = (relativePath) => fs.readFile(path.join(repositoryRoot, relativePath), 'utf8');

test('patch eligibility allows Dart and ARB source but rejects native, assets, and toolchain inputs', () => {
  assert.equal(classifyPatchPath('lib/src/app.dart').status, 'patchable');
  assert.equal(classifyPatchPath('lib/l10n/app_en.arb').status, 'patchable');
  assert.equal(classifyPatchPath('docs/operations/note.md').status, 'neutral');
  assert.equal(classifyPatchPath('test/widget_test.dart').status, 'neutral');
  for (const unsafePath of [
    'android/app/build.gradle.kts',
    'assets/brand/logo.png',
    'config/toolchain.json',
    'pubspec.yaml',
    'pubspec.lock',
    'shorebird.yaml.template',
    'unknown-release-input.txt',
  ]) {
    assert.equal(classifyPatchPath(unsafePath).status, 'blocked', unsafePath);
  }
});

test('Shorebird configuration is generated from non-secret app IDs and not committed', async () => {
  const template = await read('shorebird.yaml.template');
  const configure = await read('tool/configure_shorebird.ps1');
  const ignore = await read('.gitignore');
  const pubspec = await read('pubspec.yaml');
  assert.match(template, /\$\{SHOREBIRD_DEV_APP_ID\}/);
  assert.match(template, /patch_verification:\s+strict/);
  assert.match(configure, /SHOREBIRD_PROD_APP_ID/);
  assert.match(configure, /canonical UUID/);
  assert.match(ignore, /^\/shorebird\.yaml$/m);
  assert.doesNotMatch(pubspec, /^\s+- shorebird\.yaml$/m);
});

test('Shorebird is commit pinned and KMS helpers never contain private key material', async () => {
  const installer = await read('tool/install_shorebird.ps1');
  const engineSymbols = await read('tool/download_shorebird_engine_symbols.ps1');
  const publicKey = await read('tool/shorebird_kms_public_key.sh');
  const signer = await read('tool/shorebird_kms_sign.sh');
  assert.match(installer, /checkout.*-B.*owntend-pinned/);
  assert.match(installer, /flutter\.version/);
  assert.match(engineSymbols, /https:\/\/download\.shorebird\.dev\/flutter_infra_release/);
  assert.doesNotMatch(engineSymbols, /storage\.googleapis\.com\/flutter_infra_release/);
  assert.match(publicKey, /gcloud kms keys versions get-public-key/);
  assert.match(signer, /gcloud kms asymmetric-sign/);
  assert.match(signer, /--digest-algorithm=sha256/);
  assert.match(signer, /mktemp -d/);
  assert.match(signer, /trap.*rm -rf/);
  assert.doesNotMatch(signer, /--input-file=-/);
  assert.match(signer, /\bbase64\s+</);
  assert.doesNotMatch(`${publicKey}\n${signer}`, /BEGIN (?:RSA )?PRIVATE KEY/);
});

test('runtime patch attribution is privacy-safe and startup-safe', async () => {
  const config = await read('lib/src/core/observability/observability_config.dart');
  const scope = await read('lib/src/core/observability/sentry_scope.dart');
  const scrubber = await read('lib/src/core/observability/sentry_event_scrubber.dart');
  assert.match(config, /readCurrentPatch/);
  assert.match(config, /on Object/);
  assert.match(scope, /shorebird_patch_number/);
  assert.match(scrubber, /shorebird_patch_number/);
});
