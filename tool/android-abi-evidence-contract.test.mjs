import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';
import {
  EXPECTED_ANDROID_APK_ABIS,
  validateAbiEvidenceIndex,
} from './verify_android_apk_artifact_set.mjs';

const read = async (path) =>
  (await fs.readFile(new URL(`../${path}`, import.meta.url), 'utf8')).replaceAll(
    '\r\n',
    '\n',
  );

function makeIndex() {
  const sourceSha = '0123456789abcdef0123456789abcdef01234567';
  const versionName = '1.0.0';
  const versionCode = 3;
  const signer = '3e980eb5bb68a51990e77056d4e10995b2e04fb388a73442b79a46c853361e51';
  const symbols = {
    'arm64-v8a': 'app.android-arm64.symbols',
    'armeabi-v7a': 'app.android-arm.symbols',
    x86_64: 'app.android-x64.symbols',
  };
  return {
    schema_version: 1,
    evidence_mode: 'protected-abi-apk-evidence',
    source_sha: sourceSha,
    version_name: versionName,
    version_code: versionCode,
    package: 'app.owntend.mobile',
    expected_signer_sha256: signer,
    expected_abis: [...EXPECTED_ANDROID_APK_ABIS],
    universal_apk_remains_authoritative: true,
    public_distribution_authorized: false,
    versiondeck_publication_authorized: false,
    artifacts: EXPECTED_ANDROID_APK_ABIS.map((abi, index) => {
      const name = `Owntend-${versionName}-build-${versionCode}-${abi}.apk`;
      return {
        abi,
        file: `artifacts/${name}`,
        checksum_file: `artifacts/${name}.sha256`,
        sha256: `${index + 1}`.repeat(64),
        total_bytes: 30_000_000 + index,
        package: 'app.owntend.mobile',
        version_name: versionName,
        version_code: versionCode,
        signer_sha256: signer,
        native_abis: [abi],
        badging_file: `metadata/apk-badging-${abi}.txt`,
        signature_file: `metadata/apk-signature-${abi}.txt`,
        size_report_file: `metadata/apk-size-report-${abi}.json`,
        dart_symbols_file: `symbols/${symbols[abi]}`,
      };
    }),
    r8_mapping_file: 'symbols/mapping.txt',
    dart_obfuscation_map_file: 'symbols/obfuscation-map.json',
    output_metadata_file: 'metadata/output-metadata-apk.json',
  };
}

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

test('strict ABI artifact-set validator rejects incomplete, duplicate, unexpected, or mismatched variants', () => {
  const valid = makeIndex();
  assert.deepEqual(
    validateAbiEvidenceIndex(valid, {
      sourceSha: valid.source_sha,
      versionName: valid.version_name,
      versionCode: String(valid.version_code),
    }),
    [],
  );

  const missing = structuredClone(valid);
  missing.artifacts.pop();
  assert.match(validateAbiEvidenceIndex(missing).join(' '), /exactly 3|Missing ABI/u);

  const duplicate = structuredClone(valid);
  duplicate.artifacts[2] = structuredClone(duplicate.artifacts[0]);
  assert.match(validateAbiEvidenceIndex(duplicate).join(' '), /Duplicate ABI/u);

  const unexpected = structuredClone(valid);
  unexpected.artifacts[2].abi = 'riscv64';
  assert.match(validateAbiEvidenceIndex(unexpected).join(' '), /Unexpected ABI/u);

  const multiAbi = structuredClone(valid);
  multiAbi.artifacts[0].native_abis = ['arm64-v8a', 'x86_64'];
  assert.match(validateAbiEvidenceIndex(multiAbi).join(' '), /native ABI declaration/u);

  const wrongBuild = structuredClone(valid);
  wrongBuild.artifacts[0].version_code = 3003;
  assert.match(validateAbiEvidenceIndex(wrongBuild).join(' '), /versionCode/u);

  const wrongSigner = structuredClone(valid);
  wrongSigner.artifacts[0].signer_sha256 = '00'.repeat(32);
  assert.match(validateAbiEvidenceIndex(wrongSigner).join(' '), /signer/u);

  const duplicateHash = structuredClone(valid);
  duplicateHash.artifacts[1].sha256 = duplicateHash.artifacts[0].sha256;
  assert.match(validateAbiEvidenceIndex(duplicateHash).join(' '), /Duplicate ABI artifact SHA-256/u);
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

test('post-build artifact-set workflow independently verifies exactly the protected ABI set', async () => {
  const workflow = await read('.github/workflows/verify-production-apk-artifact-set.yml');

  assert.match(workflow, /workflow_run:/);
  assert.match(workflow, /- Build Production APK/);
  assert.match(workflow, /workflow_run\.conclusion == 'success'/);
  assert.match(workflow, /workflow_run\.event == 'workflow_dispatch'/);
  assert.match(workflow, /workflow_run\.head_branch == 'main'/);
  assert.match(workflow, /Require triggering source to remain current main/);
  assert.match(workflow, /Owntend-production-apk-evidence-\$SOURCE_RUN_NUMBER/);
  assert.match(workflow, /verify_android_apk_artifact_set\.mjs/);
  assert.match(workflow, /--source-sha "\$SOURCE_SHA"/);
  assert.match(workflow, /--version-name "\$EXPECTED_VERSION"/);
  assert.match(workflow, /--version-code "\$EXPECTED_BUILD"/);
  assert.match(workflow, /apk-artifact-set-verification\.json/);
  assert.doesNotMatch(workflow, /gh release (?:create|upload|edit)/);
  assert.doesNotMatch(workflow, /deploy-download-site|publication-mode\s+verified/);
});
