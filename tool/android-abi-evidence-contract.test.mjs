import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

const read = async (path) =>
  (await fs.readFile(new URL(`../${path}`, import.meta.url), 'utf8')).replaceAll(
    '\r\n',
    '\n',
  );

test('ABI evidence builder preserves exact release identity and all supported ABIs', async () => {
  const script = await read('tool/build_prod_abi_evidence.ps1');

  assert.match(script, /--split-per-abi/);
  assert.match(script, /force-version-code-ignoring-abi=true/);
  assert.match(
    script,
    /\$expectedAbis = @\('arm64-v8a', 'armeabi-v7a', 'x86_64'\)/,
  );
  assert.match(script, /Unexpected versionCode for \$\{abi\}/);
  assert.doesNotMatch(script, /\$abi:/);
  assert.match(script, /\$actualBuild -ne \$ExpectedBuild/);
  assert.match(script, /\^lib\/\(\[\^\/\]\+\)\//);
  assert.match(script, /\$libAbis\.Count -ne 1/);
  assert.match(script, /android_apk_size_report\.mjs/);
  assert.match(script, /app\.android-arm64\.symbols/);
  assert.match(script, /app\.android-arm\.symbols/);
  assert.match(script, /app\.android-x64\.symbols/);
  assert.match(script, /build\\app\\outputs\\mapping\\prodRelease\\mapping\.txt/);
  assert.match(script, /universal_apk_remains_authoritative = \$true/);
  assert.match(script, /public_distribution_authorized = \$false/);
  assert.match(script, /versiondeck_publication_authorized = \$false/);
  assert.doesNotMatch(script, /gh release (?:create|upload|edit)/);
});

test('protected APK workflow stages ABI evidence after the universal handoff', async () => {
  const workflow = await read('.github/workflows/build-production-android.yml');

  const universalHandoff = workflow.indexOf('name: Upload production APK handoff');
  const abiBuild = workflow.indexOf('name: Build and verify ABI-specific APK evidence');
  const diagnostics = workflow.indexOf('name: Upload APK diagnostics');
  assert.ok(universalHandoff >= 0, 'universal APK handoff step is required');
  assert.ok(abiBuild > universalHandoff, 'ABI evidence must run only after the universal handoff is preserved');
  assert.ok(diagnostics > abiBuild, 'ABI evidence must exist before diagnostics are uploaded');

  assert.match(workflow, /\.\\tool\\build_prod_abi_evidence\.ps1/);
  assert.match(workflow, /release\/abi-apk-evidence/);
  assert.match(workflow, /strategy:\n\s+fail-fast: false\n\s+matrix:\n\s+variant:/);
  for (const variant of ['universal', 'arm64-v8a', 'armeabi-v7a', 'x86_64']) {
    assert.match(workflow, new RegExp(`- ${variant.replace('-', '\\-')}`));
  }
  assert.match(workflow, /steps\.subject\.outputs\.subject_path/);
  assert.match(workflow, /gh attestation verify/);
  assert.match(workflow, /--source-digest \$env:GITHUB_SHA/);
  assert.match(workflow, /--source-ref refs\/heads\/main/);
  assert.match(workflow, /--deny-self-hosted-runners/);
  assert.doesNotMatch(workflow, /gh release (?:create|upload|edit)/);
  assert.doesNotMatch(workflow, /deploy-download-site|publication_mode:\s*verified/);
});
