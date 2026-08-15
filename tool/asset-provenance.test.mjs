import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { validateAssetProvenance } from './validate_asset_provenance.mjs';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

async function read(relPath) {
  return fs.readFile(path.join(repositoryRoot, relPath), 'utf8');
}

test('Asset provenance registry matches repository assets and license files', async () => {
  const result = await validateAssetProvenance(repositoryRoot);
  assert.equal(result.valid, true, `Validation errors: ${result.errors.join('; ')}`);
  assert.equal(result.errors.length, 0);
  assert.equal(result.totalAssets >= 15, true);
  assert.equal(result.registeredAssets, result.totalAssets);
});

test('Root license and notice files are present and contain required terms', async () => {
  const license = await read('LICENSE');
  assert.match(license, /MIT License/);
  assert.match(license, /Copyright \(c\) 2026/);

  const notice = await read('NOTICE');
  assert.match(notice, /Owntend/);
  assert.match(notice, /Google LLC/);
  assert.match(notice, /SIL Open Font License/);
  assert.match(notice, /CC0 1\.0 Universal/);

  const noticesMd = await read('THIRD_PARTY_NOTICES.md');
  assert.ok(noticesMd.length > 500);
});

test('Asset provenance registry schema is valid and approved for distribution', async () => {
  const raw = await read('config/asset_provenance.json');
  const config = JSON.parse(raw);

  assert.equal(config.schemaVersion, 1);
  assert.equal(config.legalDisposition, 'APPROVED_FOR_DISTRIBUTION');
  assert.equal(config.reviewer, 'zuhak5');
  assert.ok(Array.isArray(config.assets));
  assert.ok(config.assets.length >= 15);

  for (const asset of config.assets) {
    assert.ok(asset.path, 'Asset missing path');
    assert.ok(asset.sha256 && /^[a-f\d]{64}$/i.test(asset.sha256), `Asset ${asset.path} invalid sha256`);
    assert.ok(asset.license, `Asset ${asset.path} missing license`);
    assert.ok(asset.origin, `Asset ${asset.path} missing origin`);
    assert.ok(asset.creator, `Asset ${asset.path} missing creator`);
    assert.ok(typeof asset.sizeBytes === 'number' && asset.sizeBytes > 0, `Asset ${asset.path} invalid sizeBytes`);
  }
});

test('Release evidence collector validates and binds asset provenance', async () => {
  const collector = await read('tool/collect_android_release_evidence.ps1');
  assert.match(collector, /validate_asset_provenance\.mjs/);
  assert.match(collector, /asset_provenance_verified\s*=\s*\$true/);
});
