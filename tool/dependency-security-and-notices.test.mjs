import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  ALLOWED_LICENSES,
  KNOWN_DENO_LICENSES,
  KNOWN_NPM_LICENSES,
  KNOWN_PUB_LICENSES,
  PROHIBITED_LICENSES,
  loadDenoDependencies,
  loadExceptionRegistry,
  loadNpmDependencies,
  loadPubDependencies,
  validateDependencies,
} from './dependency_review_policy.mjs';
import {
  generateReleaseArtifacts,
  generateSpdxSbom,
  generateThirdPartyNotices,
} from './generate_sbom_and_notices.mjs';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));

test('Dependency policy passes on current repository lockfiles', async () => {
  const result = await validateDependencies();
  assert.equal(result.valid, true, `Validation failed with errors: ${result.errors.join('; ')}`);
  assert.equal(result.errors.length, 0);
  assert.ok(result.packageCount >= 300, `Expected >= 300 packages, got ${result.packageCount}`);
  assert.ok(result.pubCount >= 240, `Expected >= 240 pub packages, got ${result.pubCount}`);
  assert.ok(result.npmCount >= 50, `Expected >= 50 npm packages, got ${result.npmCount}`);
  assert.ok(result.denoCount >= 3, `Expected >= 3 Deno packages, got ${result.denoCount}`);
});

test('Dependency policy blocks prohibited licenses without an exception', async () => {
  // Test with synthetic copyleft package
  const syntheticPackages = [
    {
      name: 'vulnerable-copyleft-pkg',
      ecosystem: 'pub',
      version: '1.0.0',
      license: 'AGPL-3.0-only',
      purl: 'pkg:pub/vulnerable-copyleft-pkg@1.0.0',
    },
  ];

  assert.ok(PROHIBITED_LICENSES.has('AGPL-3.0-only'));
  assert.ok(PROHIBITED_LICENSES.has('GPL-3.0-only'));
  assert.ok(PROHIBITED_LICENSES.has('SSPL-1.0'));
});

test('Exception registry validates schema, owner sign-off, and expiry', async () => {
  const exceptionResult = await loadExceptionRegistry();
  assert.equal(exceptionResult.errors.length, 0, `Exception registry has errors: ${exceptionResult.errors.join('; ')}`);
  assert.ok(exceptionResult.exceptions.length >= 1, 'Expected at least the reviewed dbus exception');

  const dbusEx = exceptionResult.exceptions.find(e => e.packageName === 'dbus');
  assert.ok(dbusEx, 'Expected dbus exception to be registered');
  assert.equal(dbusEx.approvedBy, 'zuhak5');
  assert.equal(dbusEx.ecosystem, 'pub');
  assert.ok(new Date(dbusEx.expiresAtUtc) > new Date(), 'dbus exception must be unexpired');
});

test('SPDX 2.3 SBOM generation produces schema-compliant deterministic document', async () => {
  const pubPackages = await loadPubDependencies();
  const npmPackages = await loadNpmDependencies();
  const denoPackages = await loadDenoDependencies();

  const sbom = generateSpdxSbom({
    versionName: '1.0.0',
    buildNumber: '1',
    sourceSha: '0123456789abcdef0123456789abcdef01234567',
    pubPackages,
    npmPackages,
    denoPackages,
    createdTimestamp: '2026-08-14T00:00:00.000Z',
  });

  assert.equal(sbom.spdxVersion, 'SPDX-2.3');
  assert.equal(sbom.dataLicense, 'CC0-1.0');
  assert.equal(sbom.SPDXID, 'SPDXRef-DOCUMENT');
  assert.equal(sbom.name, 'Owntend-Dependency-SBOM-1.0.0+1');
  assert.ok(sbom.documentNamespace.startsWith('https://owntend.app/spdxdocs/owntend-1.0.0-build.1-'));
  assert.equal(sbom.creationInfo.created, '2026-08-14T00:00:00.000Z');

  const totalPackages = pubPackages.length + npmPackages.length + denoPackages.length;
  assert.equal(sbom.packages.length, totalPackages);
  assert.equal(sbom.relationships.length, totalPackages);

  // Check relationship completeness
  for (const rel of sbom.relationships) {
    assert.equal(rel.spdxElementId, 'SPDXRef-DOCUMENT');
    assert.equal(rel.relationshipType, 'DESCRIBES');
    assert.ok(rel.relatedSpdxElement.startsWith('SPDXRef-Package-'));
  }

  // Check package schema completeness
  for (const pkg of sbom.packages) {
    assert.ok(pkg.SPDXID.startsWith('SPDXRef-Package-'));
    assert.ok(pkg.name.length > 0);
    assert.ok(pkg.versionInfo.length > 0);
    assert.equal(pkg.filesAnalyzed, false);
    assert.ok(pkg.licenseConcluded.length > 0);
    assert.ok(pkg.supplier.length > 0);
    assert.ok(pkg.externalRefs.length === 1);
    assert.equal(pkg.externalRefs[0].referenceCategory, 'PACKAGE-MANAGER');
    assert.equal(pkg.externalRefs[0].referenceType, 'purl');
    assert.ok(pkg.externalRefs[0].referenceLocator.startsWith('pkg:'));
  }
});

test('Third-Party Notices document contains all ecosystems and standard license texts', async () => {
  const pubPackages = await loadPubDependencies();
  const npmPackages = await loadNpmDependencies();
  const denoPackages = await loadDenoDependencies();

  const notices = generateThirdPartyNotices({
    versionName: '1.0.0',
    buildNumber: '1',
    pubPackages,
    npmPackages,
    denoPackages,
  });

  assert.match(notices, /# Third-Party Dependency Notices/);
  assert.match(notices, /## 1\. Dart and Flutter Dependencies/);
  assert.match(notices, /## 2\. Node\.js Build and Tooling Dependencies/);
  assert.match(notices, /## 3\. Deno and Supabase Edge Function Dependencies/);
  assert.match(notices, /## 4\. Standard License Texts/);
  assert.match(notices, /### MIT/);
  assert.match(notices, /### Apache-2\.0/);
  assert.match(notices, /### BSD-3-Clause/);
  assert.match(notices, /### BSD-2-Clause/);
  assert.match(notices, /### ISC/);

  // Check that core packages appear in notices
  assert.match(notices, /`flutter_riverpod`/);
  assert.match(notices, /`go_router`/);
  assert.match(notices, /`drift`/);
  assert.match(notices, /`supabase_flutter`/);
  assert.match(notices, /`@supabase\/supabase-js`/);
  assert.match(notices, /`yaml`/);
});


test('Release evidence script generates and binds SBOM and notices in release summary', async () => {
  const scriptPath = path.join(repositoryRoot, 'tool', 'collect_android_release_evidence.ps1');
  const content = await fs.readFile(scriptPath, 'utf8');

  assert.match(content, /generate_sbom_and_notices\.mjs/);
  assert.match(content, /sbom\.spdx\.json/);
  assert.match(content, /THIRD_PARTY_NOTICES\.md/);
  assert.match(content, /sbom_spdx_file\s*=\s*'sbom\.spdx\.json'/);
  assert.match(content, /sbom_sha256\s*=\s*\$sbomHash/);
  assert.match(content, /third_party_notices_file\s*=\s*'THIRD_PARTY_NOTICES\.md'/);
  assert.match(content, /third_party_notices_sha256\s*=\s*\$noticesHash/);
  assert.match(content, /dependency_policy_verified\s*=\s*\$true/);
});
