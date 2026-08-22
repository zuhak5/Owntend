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
    schema_version: 2,
    evidence_mode: 'protected-shorebird-aab-derived-apk-evidence',
    derivation_mode: 'pinned-bundletool-universal-pruned-per-abi',
    source_sha: sourceSha,
    version_name: versionName,
    version_code: versionCode,
    package: 'app.owntend.mobile',
    expected_signer_sha256: signer,
    expected_abis: [...EXPECTED_ANDROID_APK_ABIS],
    canonical_aab_sha256: 'a'.repeat(64),
    bundletool_version: '1.18.3',
    bundletool_sha256: 'a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29',
    universal_apk_file: `artifacts/Owntend-${versionName}-build-${versionCode}-universal.apk`,
    universal_apk_sha256: 'b'.repeat(64),
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
  };
}

test('APK derivation preserves exact AAB identity and all supported ABIs without Flutter recompilation', async () => {
  const script = await read('tool/derive_versiondeck_apks.ps1');

  assert.match(script, /build-apks/);
  assert.match(script, /--mode=universal/);
  assert.match(script, /download_bundletool\.ps1/);
  assert.match(
    script,
    /\$expectedAbis = @\('arm64-v8a', 'armeabi-v7a', 'x86_64'\)/,
  );
  assert.match(script, /Remove-OtherAbis/);
  assert.match(script, /zipalign/);
  assert.match(script, /apksigner sign/);
  assert.match(script, /\^lib\/\(\[\^\/\]\+\)\//);
  assert.match(script, /\$abis\.Count -ne 1/);
  assert.match(script, /android_apk_size_report\.mjs/);
  assert.match(script, /app\.android-arm64\.symbols/);
  assert.match(script, /app\.android-arm\.symbols/);
  assert.match(script, /app\.android-x64\.symbols/);
  assert.match(script, /build\\app\\outputs\\mapping\\prodRelease\\mapping\.txt/);
  assert.match(script, /universal_apk_remains_authoritative = \$true/);
  assert.match(script, /public_distribution_authorized = \$false/);
  assert.match(script, /versiondeck_publication_authorized = \$false/);
  assert.match(script, /canonical_aab_sha256/);
  assert.match(script, /pinned-bundletool-universal-pruned-per-abi/);
  assert.doesNotMatch(script, /flutter (?:build|assemble)/);
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

test('protected Shorebird workflow derives APKs only after the canonical AAB job', async () => {
  const workflow = await read('.github/workflows/shorebird-release-android.yml');
  assert.match(workflow, /derive-versiondeck-apks:/);
  assert.match(workflow, /needs: release/);
  assert.match(workflow, /inputs\.flavor == 'prod' && inputs\.operation == 'publish'/);
  assert.match(workflow, /download-artifact@37930b1c2abaa49bbe596cd826c3c89aef350131 # v7\.0\.0/);
  assert.match(workflow, /derive_versiondeck_apks\.ps1/);
  assert.match(workflow, /production-shorebird-apk-evidence/);
  assert.match(workflow, /subject-path: release\/shorebird-apk-evidence\/artifacts\/\*\.apk/);
  assert.doesNotMatch(workflow, /gh release (?:create|upload|edit)/);
  assert.doesNotMatch(workflow, /deploy-download-site|publication_mode:\s*verified/);
});

test('post-build artifact-set workflow independently verifies exactly the protected ABI set', async () => {
  const workflow = await read('.github/workflows/verify-production-apk-artifact-set.yml');

  assert.match(workflow, /workflow_run:/);
  assert.match(workflow, /- Shorebird Android Release/);
  assert.match(workflow, /workflow_run\.conclusion == 'success'/);
  assert.match(workflow, /workflow_run\.event == 'workflow_dispatch'/);
  assert.match(workflow, /workflow_run\.head_branch == 'main'/);
  assert.match(workflow, /Require triggering source to remain current main/);
  assert.match(workflow, /Owntend-production-shorebird-apk-evidence-\$SOURCE_RUN_NUMBER/);
  assert.match(workflow, /should_verify=false/);
  assert.match(workflow, /verify_android_apk_artifact_set\.mjs/);
  assert.match(workflow, /--source-sha "\$SOURCE_SHA"/);
  assert.match(workflow, /--version-name "\$EXPECTED_VERSION"/);
  assert.match(workflow, /--version-code "\$EXPECTED_BUILD"/);
  assert.match(workflow, /apk-artifact-set-verification\.json/);
  assert.doesNotMatch(workflow, /gh release (?:create|upload|edit)/);
  assert.doesNotMatch(workflow, /deploy-download-site|publication-mode\s+verified/);
});
