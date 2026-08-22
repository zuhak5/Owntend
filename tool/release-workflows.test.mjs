import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

import {
  validateActionSource,
  validateRepositoryActionReferences,
} from './github-actions-policy.mjs';

const read = async (path) =>
  (await fs.readFile(new URL(`../${path}`, import.meta.url), 'utf8')).replaceAll(
    '\r\n',
    '\n',
  );

test('GitHub Actions use only reviewed immutable references', async () => {
  const result = await validateRepositoryActionReferences();
  assert.deepEqual(result.errors, []);
  assert.equal(result.externalReferences, 57);
  assert.equal(result.localReferences, 0);
  assert.equal(result.files.length, 9);
});

test('GitHub Actions policy rejects mutable, shortened, and unowned references', () => {
  const fullSha = 'd23441a48e516b6c34aea4fa41551a30e30af803';
  const fixtures = [
    ['major tag', 'uses: actions/checkout@v6', /full 40-character/],
    ['branch', 'uses: actions/checkout@main', /full 40-character/],
    ['short SHA', 'uses: actions/checkout@d23441a', /full 40-character/],
    [
      'unknown owner',
      `uses: example/checkout@${fullSha} # v6.1.0`,
      /not an owned, reviewed action/,
    ],
    [
      'unowned action',
      `uses: actions/cache@${fullSha} # v6.1.0`,
      /not an owned, reviewed action/,
    ],
    [
      'YAML anchor',
      `uses: &checkout actions/checkout@${fullSha} # v6.1.0`,
      /YAML anchors/,
    ],
    [
      'YAML alias key',
      `*uses: actions/checkout@${fullSha} # v6.1.0`,
      /invalid YAML|YAML aliases/,
    ],
    [
      'escaped uses key',
      '"u\\u0073es": actions/checkout@main',
      /full 40-character/,
    ],
    [
      'unreviewed digest',
      'uses: actions/checkout@0000000000000000000000000000000000000000 # v6.1.0',
      /not a reviewed release/,
    ],
    [
      'missing release comment',
      `uses: actions/checkout@${fullSha}`,
      /exact comment # v6.1.0/,
    ],
    [
      'local path escape',
      'uses: ./tool/unowned-action',
      /owned under \.\/\.github\/actions/,
    ],
  ];

  for (const [name, source, expected] of fixtures) {
    const result = validateActionSource(`steps:\n  - ${source}\n`, `${name}.yml`);
    assert.match(result.errors.join('\n'), expected, name);
  }

  const explicitKey = validateActionSource(
    'steps:\n  - ? uses\n    : actions/checkout@main\n',
    'explicit-key.yml',
  );
  assert.match(explicitKey.errors.join('\n'), /full 40-character/);

  const aliasedKey = validateActionSource(
    `usesKey: &usesKey uses\nsteps:\n  - ? *usesKey\n    : actions/checkout@${fullSha}\n`,
    'aliased-key.yml',
  );
  assert.match(aliasedKey.errors.join('\n'), /YAML anchors|YAML aliases/);

  const multilineEscapedKey = validateActionSource(
    'steps:\n  - ? "u' +
      '\\' +
      '\n      ses"\n    : actions/checkout@main\n',
    'multiline-escaped-key.yml',
  );
  assert.match(multilineEscapedKey.errors.join('\n'), /full 40-character/);

  const taggedKey = validateActionSource(
    `steps:\n  - !owntend/key uses: actions/checkout@${fullSha} # v6.1.0\n`,
    'tagged-key.yml',
  );
  assert.match(taggedKey.errors.join('\n'), /invalid YAML|YAML tags/);

  const punctuatedAlias = validateActionSource(
    `key: &owntend.key uses\nsteps:\n  - ? *owntend.key\n    : actions/checkout@${fullSha}\n`,
    'punctuated-alias.yml',
  );
  assert.match(
    punctuatedAlias.errors.join('\n'),
    /invalid YAML|YAML anchors|YAML aliases/,
  );

  const unusualButOwned = validateActionSource(
    `steps:\n  - { uses: actions/checkout@${fullSha} } # v6.1.0\n  - run: |\n      echo "uses: actions/checkout@v6"\n`,
    'flow-and-block.yml',
  );
  assert.deepEqual(unusualButOwned.errors, []);
  assert.equal(unusualButOwned.externalReferences, 1);
});

test('Shorebird release rail is dry-run by default and preserves production gates', async () => {
  const workflow = await read('.github/workflows/shorebird-release-android.yml');
  assert.match(workflow, /name: Shorebird Android Release/);
  assert.match(workflow, /default: validate/);
  assert.match(workflow, /SHOREBIRD_PRODUCTION_RELEASES_ENABLED/);
  assert.match(workflow, /exact current origin\/main/);
  assert.match(workflow, /validate-google-backend\.yml\/runs\?head_sha=/);
  assert.match(workflow, /secrets\.SHOREBIRD_TOKEN/);
  assert.match(workflow, /vars\.SHOREBIRD_(?:DEV|STAGING|PROD)_APP_ID/);
  assert.match(workflow, /google-github-actions\/auth@7c6bc770dae815cd3e89ee6cdf493a5fab2cc093 # v3\.0\.0/);
  assert.match(workflow, /setup-gcloud@e427ad8a34f8676edf47cf7d7925499adf3eb74f # v2\.2\.1/);
  assert.match(workflow, /version: "581\.0\.0"/);
  assert.match(workflow, /invoke_shorebird_release\.ps1 @Parameters -DryRun/);
  assert.ok(workflow.lastIndexOf('verify_android_release_registrants.ps1 -RemoveGeneratedMain') < workflow.indexOf('invoke_shorebird_release.ps1 @Parameters -DryRun'));
  assert.match(workflow, /shorebird-release-\$\{\{ inputs\.flavor \}\}-\*\.json/);
  assert.match(await read('tool/invoke_shorebird_release.ps1'), /--flutter-version=\$\(\$shorebirdPin\.releaseFlutterVersion\)/);
  assert.match(await read('tool/invoke_shorebird_release.ps1'), /releaseFlutterRevision/);
  assert.match(workflow, /collect_android_release_evidence\.ps1/);
  assert.match(workflow, /download_shorebird_engine_symbols\.ps1/);
  assert.match(workflow, /derive_versiondeck_apks\.ps1/);
  assert.match(workflow, /environment: production-android-signing/);
  assert.match(workflow, /attest-build-provenance@977bb373ede98d70efdf65b84cb5f73e068dcc2a # v3\.0\.0/);
  assert.doesNotMatch(workflow, /gh release (?:create|upload|edit)|SENTRY_AUTH_TOKEN|edits\.(?:insert|bundles|tracks)/);
});

test('Shorebird patch rail rejects unsafe diffs and publishes only to staging track', async () => {
  const workflow = await read('.github/workflows/shorebird-patch-android.yml');
  const patchScript = await read('tool/invoke_shorebird_patch.ps1');
  assert.match(workflow, /default: validate/);
  assert.match(workflow, /shorebird_patch_eligibility\.mjs/);
  assert.match(workflow, /refs\/heads\/release\//);
  assert.match(workflow, /candidate must be the exact release-branch tip/);
  assert.match(workflow, /SHOREBIRD_PRODUCTION_PATCHES_ENABLED/);
  assert.match(workflow, /validate-google-backend\.yml\/runs\?head_sha=/);
  assert.ok(workflow.indexOf('invoke_shorebird_patch.ps1 @Parameters -DryRun') < workflow.indexOf('invoke_shorebird_patch.ps1 @Parameters }'));
  assert.match(patchScript, /--track=staging/);
  assert.match(patchScript, /--public-key-cmd=bash tool\/shorebird_kms_public_key\.sh/);
  assert.match(patchScript, /--sign-cmd=bash tool\/shorebird_kms_sign\.sh/);
  assert.match(patchScript, /'--',\s*'--no-pub'/);
  assert.match(patchScript, /release_base_sha = \$ReleaseBaseSha/);
  assert.match(patchScript, /releaseEngineRevision/);
  assert.match(patchScript, /Expected exactly one newly published patch/);
  assert.match(patchScript, /shorebird-patch-\$Flavor-\$mode\.json/);
  assert.doesNotMatch(patchScript, /allow-native-diffs|allow-asset-diffs|--confirm/);
});

test('promotion is exact, protected, and requires device-preview confirmation', async () => {
  const workflow = await read('.github/workflows/shorebird-promote-patch.yml');
  const script = await read('tool/promote_shorebird_patch.ps1');
  assert.match(workflow, /environment: production/);
  assert.match(workflow, /SHOREBIRD_PRODUCTION_PROMOTIONS_ENABLED/);
  assert.match(workflow, /secrets\.SHOREBIRD_TOKEN/);
  assert.match(script, /PREVIEWED PATCH \$ReleaseVersion#\$PatchNumber/);
  assert.match(script, /is_rolled_back/);
  assert.match(script, /channel -ne 'staging'/);
  assert.match(script, /patches set-track --release \$ReleaseVersion --patch \$PatchNumber --track stable/);
  assert.match(script, /shorebird-promotion-evidence\.json/);
  assert.match(workflow, /Upload immutable promotion evidence/);
  assert.doesNotMatch(script, /patches promote|rollback/);
});
test('backend gate covers formatting, type safety, functions, and database', async () => {
  const workflow = await read('.github/workflows/validate-google-backend.yml');
  const triggers = workflow.slice(
    workflow.indexOf('on:'),
    workflow.indexOf('concurrency:'),
  );
  assert.match(triggers, /pull_request:\n\s+branches: \[main\]/);
  assert.match(triggers, /push:\n\s+branches: \[main\]/);
  assert.doesNotMatch(triggers, /paths:/);
  assert.match(workflow, /name: Deno SSV tests/);
  assert.match(workflow, /name: Google contract\/static checks/);
  assert.match(workflow, /name: Supabase database tests/);
  assert.match(workflow, /name: Hosted Supabase Advisors/);
  assert.match(workflow, /deno fmt --check/);
  assert.match(workflow, /deno check --frozen/);
  assert.match(workflow, /deno test --frozen/);
  assert.match(workflow, /admob-ssv-handler\/index_test\.ts/);
  assert.match(workflow, /delete-account\/index_test\.ts/);
  assert.match(workflow, /account-deletion-status\/index_test\.ts/);
  assert.match(workflow, /npx supabase start/);
  assert.match(workflow, /npm run supabase:lint/);
  assert.match(workflow, /npm run supabase:test/);
  assert.match(workflow, /node tool\/audit_supabase_advisors\.mjs/);
  assert.match(workflow, /environment: production-supabase-advisors/);
  assert.match(workflow, /needs: validate-advisor-source/);
  assert.match(workflow, /persist-credentials: false/);
  assert.match(
    workflow,
    /SUPABASE_ACCESS_TOKEN: \$\{\{ secrets\.SUPABASE_ADVISOR_ACCESS_TOKEN \}\}/,
  );
  assert.doesNotMatch(
    workflow,
    /SUPABASE_MIGRATION_|ANDROID_(?:APK_)?KEY|PLAY_UPLOAD_|SENTRY_AUTH_TOKEN/,
  );
  assert.match(workflow, /if: github\.event_name == 'workflow_dispatch'/);
  assert.match(workflow, /if: always\(\)/);
});

test('Supabase migration deployment requires exact main and explicit production confirmation', async () => {
  const workflow = await read(
    '.github/workflows/deploy-supabase-migrations.yml',
  );
  assert.match(workflow, /name: Deploy Supabase Migrations/);
  assert.match(workflow, /test "\$GITHUB_REF" = "refs\/heads\/main"/);
  assert.match(workflow, /test "\$source_sha" = "\$INPUT_SOURCE_SHA"/);
  assert.match(workflow, /test "\$source_sha" = "\$GITHUB_SHA"/);
  assert.match(workflow, /test "\$source_sha" = "\$remote_sha"/);
  assert.match(workflow, /apply-pending-migrations/);
  assert.match(workflow, /test "\$INPUT_PROJECT_REF" = "\$expected_ref"/);
  assert.match(workflow, /environment: production-supabase-migrations/);
  assert.match(workflow, /name: Confirm protected Supabase project/);
  assert.match(workflow, /SUPABASE_URL: \$\{\{ vars\.SUPABASE_URL \}\}/);
  const protectedEnvironment = workflow.indexOf(
    'environment: production-supabase-migrations',
  );
  const projectConfirmation = workflow.indexOf(
    'name: Confirm protected Supabase project',
  );
  const projectLink = workflow.indexOf('name: Link the confirmed hosted project');
  assert.ok(
    protectedEnvironment >= 0 &&
      projectConfirmation > protectedEnvironment &&
      projectLink > projectConfirmation,
    'Project identity must be checked inside the protected job before linking.',
  );
  assert.match(
    workflow,
    /SUPABASE_ACCESS_TOKEN: \$\{\{ secrets\.SUPABASE_MIGRATION_ACCESS_TOKEN \}\}/,
  );
  assert.match(
    workflow,
    /SUPABASE_DB_PASSWORD: \$\{\{ secrets\.SUPABASE_MIGRATION_DB_PASSWORD \}\}/,
  );
  assert.doesNotMatch(
    workflow,
    /SUPABASE_ADVISOR_|ANDROID_(?:APK_)?KEY|PLAY_UPLOAD_|SENTRY_AUTH_TOKEN/,
  );
  const dryRun = workflow.indexOf('name: Dry-run pending migrations');
  const apply = workflow.indexOf('name: Apply pending migrations');
  assert.ok(dryRun >= 0 && apply > dryRun);
  assert.doesNotMatch(workflow, /--include-all|migration repair|include-seed/);
});

test('release evidence collector rejects analytics and unsafe manifests', async () => {
  const collector = await read('tool/collect_android_release_evidence.ps1');
  assert.match(collector, /prodReleaseRuntimeClasspath/);
  assert.match(collector, /firebase-analytics/);
  assert.match(collector, /ACCESS_FINE_LOCATION/);
  assert.match(collector, /ACCESS_BACKGROUND_LOCATION/);
  assert.match(collector, /GetAttribute\('package'\)/);
  assert.match(collector, /GetAttribute\('targetSdkVersion', \$androidNamespace\)/);
  assert.match(collector, /GetAttribute\('allowBackup', \$androidNamespace\)/);
  assert.match(collector, /GetAttribute\('debuggable', \$androidNamespace\)/);
  assert.match(collector, /\$adMobMetadata\.Count -ne 1/);
  assert.match(collector, /\/apk\/prod\/release\/output-metadata/);
  assert.match(collector, /\$elements\.Count -ne 1/);
  assert.match(collector, /allow_backup =/);
  assert.match(collector, /admob_application_id =/);
  assert.match(collector, /output_metadata_source =/);
  assert.doesNotMatch(collector, /ANDROID_(?:STORE|KEY)_PASSWORD/);
});

test('Google static validator scans all distributable sources and exact ad mappings', async () => {
  const validator = await read('tool/validate_google_release_contracts.mjs');
  assert.match(validator, /execFileSync\('git', \['ls-files', '--'\]/);
  assert.match(validator, /google-services\\\.json\$\/i/);
  assert.match(validator, /\.\.\.filesUnder\('lib'/);
  assert.match(validator, /'android\/app\/src'/);
  assert.match(validator, /\.\.\.filesUnder\('download-site'/);
  assert.match(validator, /payload\.role !== 'service_role'/);
  assert.match(validator, /configuredDemoIds\.length === approvedDemoIds\.length/);
  assert.match(validator, /String\\\\s\+get/);
});

test('release runbook names every required backend check exactly', async () => {
  const runbook = await read('docs/operations/release-runbook.md');
  assert.match(runbook, /`Deno SSV tests`/);
  assert.match(runbook, /`Google contract\/static checks`/);
  assert.match(runbook, /`Supabase database tests`/);
});

test('VersionDeck exposes only reviewed disabled and verified publication modes', async () => {
  const workflow = await read('.github/workflows/deploy-download-site.yml');

  assert.doesNotMatch(workflow, /^  push:/m);
  assert.doesNotMatch(workflow, /^  release:/m);
  assert.doesNotMatch(workflow, /^  workflow_run:/m);

  assert.match(workflow, /publication_mode:/);
  assert.match(workflow, /default: disabled/);
  assert.match(workflow, /^\s+- disabled$/m);
  assert.match(workflow, /^\s+- verified$/m);
  assert.doesNotMatch(workflow, /^\s+production_run_id:/m);

  assert.match(
    workflow,
    /if: github\.event_name == 'workflow_dispatch' && github\.ref == 'refs\/heads\/main'/,
  );

  assert.match(workflow, /disabled\)\s+[\s\S]*expected_publication_status="disabled"/);
  assert.match(workflow, /verified\)\s+[\s\S]*expected_publication_status="active"/);
  assert.match(workflow, /publication_mode == 'verified'/);
  assert.match(workflow, /Generate independently verified release manifest/);
  assert.match(workflow, /--publication-mode/);
  assert.match(workflow, /steps\.source\.outputs\.publication_mode/);
  assert.doesNotMatch(workflow, /test "\$run_name" = "Build Production APK"/);
  assert.match(workflow, /manifest\.schemaVersion !== 1/);
});
test('Gradle distribution checksum is present and correctly formatted', async () => {
  const props = await read(
    'android/gradle/wrapper/gradle-wrapper.properties',
  );
  // distributionSha256Sum must be a non-empty lowercase hex string of exactly
  // 64 characters (SHA-256 output).
  assert.match(
    props,
    /^distributionSha256Sum=[0-9a-f]{64}$/m,
    'gradle-wrapper.properties must contain a valid 64-character lowercase hex SHA-256 checksum',
  );
  // The distribution URL and checksum must name the same Gradle version.
  const urlMatch = props.match(
    /^distributionUrl=.*gradle-(\d+\.\d+(?:\.\d+)?)-bin\.zip/m,
  );
  assert.ok(
    urlMatch,
    'distributionUrl must reference a -bin.zip Gradle distribution',
  );
  // The checksum line must not contain any inline whitespace or extra characters.
  assert.doesNotMatch(
    props,
    /^distributionSha256Sum=[0-9a-f]{64}[ \t]/m,
    'distributionSha256Sum must not contain trailing whitespace or extra characters after the checksum',
  );
});

test('flutter pub get uses --enforce-lockfile in validation and Shorebird workflows', async () => {
  const validateWorkflow = await read('.github/workflows/validate-flutter.yml');
  // All pub get invocations in CI must enforce the lockfile.
  assert.doesNotMatch(
    validateWorkflow,
    /flutter pub get(?! --enforce-lockfile)/,
    'validate-flutter.yml must always pass --enforce-lockfile to flutter pub get',
  );
  assert.match(
    validateWorkflow,
    /flutter pub get --enforce-lockfile/,
    'validate-flutter.yml must use --enforce-lockfile',
  );
  // CI must also check that the lockfile is not mutated after enforced resolution.
  assert.match(
    validateWorkflow,
    /git status --porcelain pubspec\.lock/,
    'validate-flutter.yml must verify pubspec.lock is unchanged after enforced resolution',
  );
  assert.ok(
    validateWorkflow.indexOf('flutter pub get --enforce-lockfile') <
      validateWorkflow.indexOf('git status --porcelain pubspec.lock'),
    'enforced pub get must precede the lockfile-unchanged check',
  );

  for (const file of [
    '.github/workflows/shorebird-release-android.yml',
    '.github/workflows/shorebird-patch-android.yml',
  ]) {
    const workflow = await read(file);
    assert.match(workflow, /flutter pub get --enforce-lockfile/, file);
    assert.doesNotMatch(workflow, /flutter pub get(?! --enforce-lockfile)/, file);
  }
});
