# Shorebird Android code-push operations

This is the canonical setup and operations guide for Owntend's Shorebird integration. Owntend is pre-launch; no command in this guide authorizes a production release, patch, Play upload, Sentry mutation, VersionDeck deployment, or other public action.

## Implemented contract

Owntend uses three separate Shorebird apps, one for each Android flavor:

| Flavor | Package | Repository variable | GitHub environment |
| --- | --- | --- | --- |
| `dev` | `app.owntend.mobile.dev` | `SHOREBIRD_DEV_APP_ID` | `development` |
| `staging` | `app.owntend.mobile.staging` | `SHOREBIRD_STAGING_APP_ID` | `staging` |
| `prod` | `app.owntend.mobile` | `SHOREBIRD_PROD_APP_ID` | `production` |

[`shorebird.yaml.template`](../../shorebird.yaml.template) is safe to commit because it contains placeholders only. [`tool/configure_shorebird.ps1`](../../tool/configure_shorebird.ps1) validates the three non-secret UUIDs, requires them to be distinct, generates ignored `shorebird.yaml`, and temporarily adds the exact asset to `pubspec.yaml` when `-EnsurePubspecAsset` is used. Never commit the generated file.

The canonical CLI, bundled Flutter fork/engine, release Flutter fork/engine, Bundletool, and gcloud pins are in [`config/toolchain.json`](../../config/toolchain.json). [`tool/install_shorebird.ps1`](../../tool/install_shorebird.ps1) fetches the exact Shorebird commit rather than building from a mutable installer channel. CLI `1.6.119` bundles Flutter `3.47.1`, while every Owntend full release explicitly uses the still-supported canonical Flutter `3.47.0`; patches inherit their base release toolchain. Release evidence fails if any pinned identity differs, so a CLI update cannot silently upgrade the app toolchain.

Patch verification is `strict`. Native and asset bypass flags are forbidden. [`tool/shorebird_patch_eligibility.mjs`](../../tool/shorebird_patch_eligibility.mjs) rejects native projects, assets, dependencies, toolchain/delivery inputs, unknown paths, a base that is not an ancestor, or a candidate with no patchable Flutter source. Shorebird's mandatory dry-run is a second independent gate.

## Value classification

| Location | Values | Handling |
| --- | --- | --- |
| Committed | template, CLI/tool pins, KMS command scripts, public workflow policy | Contains no credentials or private keys |
| Repository Variables | the three `SHOREBIRD_*_APP_ID` UUIDs | Non-secret; available to all three workflows |
| Environment Variables | runtime public config, GCP/KMS resource names, Workload Identity provider and service-account address, enable switches | Not credentials; scope by environment to prevent cross-environment mixups |
| Environment Secrets | `SHOREBIRD_TOKEN`, Android signing keystore/password values | Never echo, commit, or place in Flutter configuration |
| Google Cloud KMS | RSA private patch-signing keys | Non-exportable; CI receives only short-lived OIDC credentials and signing permission |

Shorebird app IDs are identifiers, not credentials. `SHOREBIRD_TOKEN` is a credential. Android keystores and passwords are credentials. KMS private keys must remain non-exportable and never enter GitHub.

## One-time Shorebird account and app registration

1. Sign in to the Shorebird Console and create or select the Owntend organization. Record its numeric organization ID.
2. Use a disposable clean clone so Shorebird initialization cannot modify the working repository:

   ```powershell
   git clone https://github.com/zuhak5/Owntend.git Owntend-shorebird-init
   Set-Location Owntend-shorebird-init
   .\tool\install_shorebird.ps1
   shorebird login
   shorebird init --display-name Owntend --organization-id <NUMERIC_ORGANIZATION_ID>
   Get-Content .\shorebird.yaml
   ```

   The pinned CLI detects `dev`, `staging`, and `prod` from Gradle and registers a distinct Shorebird app for each. It writes their UUIDs under `flavors:`. This is the required registration step when the apps do not yet exist; do not invent UUIDs.
3. Confirm in the Shorebird Console that all three apps exist and have the intended display names and organization. Read each ID from the generated `shorebird.yaml` mapping. If an app already exists, use its Console app settings or an existing generated `shorebird.yaml`; never register a duplicate merely to get an ID.
4. Delete the disposable clone after copying the three non-secret UUIDs. Do not copy its modified `pubspec.yaml` or generated `shorebird.yaml` into this repository.

In the Shorebird Console API-key page, create:

- one non-production CI key, 90-day expiry, named for Owntend non-production CI;
- one production CI key, 90-day expiry, named for Owntend production CI.

On a plan that offers scoped API keys, grant only release-and-patch access. Otherwise use the minimum available CI access and restrict it with GitHub Environments. Store the same non-production token separately in the `development` and `staging` environment secret named `SHOREBIRD_TOKEN`; store the production token only in the `production` environment secret with the same name. Record the owner and rotation date outside the repository. Revoke replaced or incident-exposed keys.

## GitHub repository and environment configuration

Create these repository-level Variables:

```text
SHOREBIRD_DEV_APP_ID=<dev UUID from generated shorebird.yaml>
SHOREBIRD_STAGING_APP_ID=<staging UUID from generated shorebird.yaml>
SHOREBIRD_PROD_APP_ID=<prod UUID from generated shorebird.yaml>
```

Create or review these environments:

- `development`: no reviewer is required for validation; restrict deployments to appropriate branches.
- `staging`: require at least one reviewer before publishing a release or patch. Validation also uses this environment because it needs its token, Android signer, and KMS public key.
- `production`: require production reviewers, prevent self-review where available, restrict to `main` and `release/*`, and keep all production credentials here.
- `production-android-signing`: preserve the existing reviewers and branch protection. It contains only the standalone VersionDeck APK signer and is entered only after a published production Shorebird release.

In each of `development`, `staging`, and `production`, create environment Variables:

```text
GCP_PROJECT_ID
GCP_WORKLOAD_IDENTITY_PROVIDER
GCP_SERVICE_ACCOUNT
SHOREBIRD_KMS_LOCATION
SHOREBIRD_KMS_KEYRING
SHOREBIRD_KMS_KEY
SHOREBIRD_KMS_KEY_VERSION
SUPABASE_URL
SUPABASE_PUBLISHABLE_KEY
GOOGLE_WEB_CLIENT_ID
SENTRY_DSN
```

`SENTRY_DSN` may be empty outside production. These are public runtime/resource values, not private credentials.

Create environment Secret `SHOREBIRD_TOKEN` as described above. For `development` and `staging`, create these environment Secrets using a non-production Android release signer:

```text
SHOREBIRD_ANDROID_KEYSTORE_BASE64
SHOREBIRD_ANDROID_KEY_ALIAS
SHOREBIRD_ANDROID_KEY_PASSWORD
SHOREBIRD_ANDROID_STORE_PASSWORD
```

Keep the existing Play upload Secrets only in `production`:

```text
PLAY_UPLOAD_KEYSTORE_BASE64
PLAY_UPLOAD_KEY_ALIAS
PLAY_UPLOAD_KEY_PASSWORD
PLAY_UPLOAD_STORE_PASSWORD
```

Keep the existing standalone APK Secrets only in `production-android-signing`:

```text
ANDROID_APK_KEYSTORE_BASE64
ANDROID_APK_KEY_ALIAS
ANDROID_APK_KEY_PASSWORD
ANDROID_APK_STORE_PASSWORD
```

The workflows intentionally use no Google service-account JSON secret.

The following environment Variables are independent kill switches. Leave them absent or `false` until the corresponding operation is explicitly authorized; set the exact lowercase value `true` only in the environment where it is approved:

```text
SHOREBIRD_NONPRODUCTION_RELEASES_ENABLED
SHOREBIRD_PRODUCTION_RELEASES_ENABLED
SHOREBIRD_NONPRODUCTION_PATCHES_ENABLED
SHOREBIRD_PRODUCTION_PATCHES_ENABLED
SHOREBIRD_PRODUCTION_PROMOTIONS_ENABLED
```

## Google Cloud KMS patch signing

Use separate non-production and production asymmetric keys. The following is an operator template; substitute reviewed project and location values:

```bash
gcloud kms keyrings create owntend-shorebird --project=PROJECT --location=global
gcloud kms keys create shorebird-nonprod --project=PROJECT --location=global --keyring=owntend-shorebird --purpose=asymmetric-signing --default-algorithm=rsa-sign-pkcs1-2048-sha256
gcloud kms keys create shorebird-prod --project=PROJECT --location=global --keyring=owntend-shorebird --purpose=asymmetric-signing --default-algorithm=rsa-sign-pkcs1-2048-sha256
```

Create dedicated non-production and production service accounts. Configure GitHub OIDC Workload Identity Federation with an attribute condition restricted to repository `zuhak5/Owntend` and the intended environment/ref. Grant the external GitHub principal `roles/iam.workloadIdentityUser` on its service account. Grant each service account only `roles/cloudkms.signerVerifier` on its matching KMS key; that key-scoped role already includes public-key retrieval as well as signing and verification. Do not add the redundant viewer role or grant key administration, project Editor, private-key export, or project-wide KMS access.

Set each environment's GCP/KMS Variables to its own provider, service account, key, and active key version. [`tool/shorebird_kms_public_key.sh`](../../tool/shorebird_kms_public_key.sh) retrieves only public verification material. [`tool/shorebird_kms_sign.sh`](../../tool/shorebird_kms_sign.sh) sends the digest to KMS and returns the base64 signature expected by Shorebird. Neither script handles a private key.

When rotating a patch-signing key, create a new key version and test a non-production release before changing production. A Shorebird release embeds the public verification key; patches for that release must continue to use the corresponding private KMS version. Preserve the old non-exportable key versions for supported releases.

## Safe setup verification

First validate in a disposable clone or a clean branch:

```powershell
$env:SHOREBIRD_DEV_APP_ID = '<dev UUID>'
$env:SHOREBIRD_STAGING_APP_ID = '<staging UUID>'
$env:SHOREBIRD_PROD_APP_ID = '<prod UUID>'
.\tool\configure_shorebird.ps1
.\tool\install_shorebird.ps1
node --test tool/shorebird.test.mjs tool/toolchain.test.mjs
node tool/toolchain_manifest.mjs --enforce --require-shorebird
.\tool\configure_shorebird.ps1 -EnsurePubspecAsset
shorebird doctor
```

The policy tests run before the temporary `pubspec.yaml` asset injection so they can verify that source control still omits generated Shorebird configuration. Then verify that the generated `shorebird.yaml` has the expected mapping and `patch_verification: strict`, and that `git status --short` shows only the expected temporary `pubspec.yaml` asset edit. Remove the generated ignored file and discard that temporary edit in the disposable clone. `shorebird doctor` and `operation=validate` do not publish a release.

The first safe CI commands are dry-runs:

In PowerShell command builders, Shorebird options such as `--dry-run` must be added before the `--` separator. Only Flutter options such as `--no-pub` belong after it; Shorebird forwards everything after the separator directly to Flutter.

```bash
sha=$(git rev-parse origin/main)
gh workflow run "Shorebird Android Release" --ref main -f flavor=dev -f operation=validate -f source_sha="$sha"
gh workflow run "Shorebird Android Release" --ref main -f flavor=staging -f operation=validate -f source_sha="$sha"
```

Review the uploaded config-free evidence, exact CLI/toolchain manifest, AAB hash, symbol files, and logs. A validation run does not publish a Shorebird release and cannot derive public VersionDeck artifacts.

## Release, patch, preview, promotion, and rollback

### Create the first Shorebird-enabled development APK

After the safe validation passes, a local operator can create a non-published installable APK in the prepared disposable clone. Restore the non-production Android signing files and a safe `config/dev.json`, authenticate with a non-production `SHOREBIRD_TOKEN`, set the non-production GCP/KMS Variables, then run:

```powershell
shorebird release android --flavor=dev --artifact=apk --target=lib/main.dart --build-name=1.0.0 --build-number=1 --dart-define-from-file=config/dev.json --obfuscate --split-debug-info=build/shorebird-symbols/dev/base --public-key-cmd="bash tool/shorebird_kms_public_key.sh" --dry-run
```

Install the resulting dev release APK on a test device. Because this is `--dry-run`, it is Shorebird-enabled build validation but is not registered as a patchable server release. Never use a debug build to validate code push.

### Publish a release

`Shorebird Android Release` is the only release build rail. It always creates one canonical AAB. Production requires exact current `main`, the exact backend validation gate, explicit operator authorization, the branch-restricted `production` environment, and `SHOREBIRD_PRODUCTION_RELEASES_ENABLED=true`. The environment does not require a separate deployment review. The protected downstream job derives the universal and three single-ABI VersionDeck APKs from that exact AAB using pinned Bundletool; it never recompiles Flutter.

Example non-production publication after authorization:

```bash
gh workflow run "Shorebird Android Release" --ref main -f flavor=staging -f operation=publish -f source_sha="$(git rev-parse origin/main)"
```

The release workflow does not upload to Play or mutate Sentry. A successful production publication automatically triggers independent APK verification, the verified GitHub Release, and VersionDeck deployment.

#### Publish a production patch (Direct-to-Stable)

Owntend production patches publish **directly to track `stable`**. Because there is no intermediate staging promotion step, all safety validation must pass **before publication**.

1. Record the release's exact source SHA and release version, for example `1.0.0+4`.
2. Create branch `release/1.0.0+4` from that release SHA. Commit only patch-eligible Flutter changes plus neutral tests/docs. Do not change assets, native code, dependencies, toolchain, or release configuration.
3. Push the branch. For a production patch, ensure `Validate Google, Backend, and Database` has passed on the exact candidate SHA. A pending hosted migration still requires its separately authorized deployment and compatibility verification; the patch workflow never mutates Supabase.
4. Dispatch a validation run (`operation=validate`):

   ```bash
   gh workflow run "Shorebird Android Patch" --ref "release/1.0.0+4" -f flavor=prod -f operation=validate -f release_version="1.0.0+4" -f release_base_sha="BASE_SHA" -f candidate_sha="CANDIDATE_SHA"
   ```

5. Review the static eligibility JSON and Shorebird dry-run. After explicit operator authorization and `SHOREBIRD_PRODUCTION_PATCHES_ENABLED=true`, rerun with `operation=publish`. The branch-restricted `production` environment supplies scoped credentials without a separate deployment review. Publication is accepted only from the exact tip of `release/<release_version>`, and the wrapper publishes directly to track `stable`; it never uses `--allow-native-diffs` or `--confirm`. The evidence artifact preserves both the dry-run record and the published patch number with `mode: published-directly-to-stable`.

### Verify on a physical device

Use a physical Android device or emulator with a production release build whose exact version matches the target release:

1. Launch the base release app on the device.
2. In the background, `PatchUpdateCoordinator` checks for updates, downloads the patch, and transitions to `PatchUpdateReady`.
3. Force stop and relaunch the app.
4. Verify the native updater logs:
   ```text
   Patch signature is valid
   Shorebird updater: active path: .../patches/<N>/dlc.vmcode
   Reporting successful launch
   Patch <N> is already installed, skipping
   ```
5. Confirm that sanitized Sentry events use `shorebird_patch_number=<N>`.

### Disable or roll back a bad patch

If an issue is detected on a published stable patch:
1. Open the Shorebird Console for the `Owntend` production app.
2. Navigate to the target release and patch number.
3. Use the Console **Rollback / Disable** control to deactivate the patch.
4. Verify on a test device that the patch is immediately rolled back to the previous stable patch or base release.
5. Do not publish an unverified counter-patch blindly. If Console access is unavailable, disable the `SHOREBIRD_PRODUCTION_PATCHES_ENABLED` variable in GitHub repository settings.

### Engine boot-loop protection & automatic unstaging fallback

Shorebird's native engine incorporates automatic crash resilience:
1. If an active OTA patch triggers a fatal crash during early bootstrap before the first Flutter frame renders, the native updater marks the launch as failed.
2. Consecutive startup crashes automatically unstage the faulty patch and revert execution to the previous stable patch or base Play Store binary.
3. Because Owntend enforces **strictly additive Drift database migrations** (SB-010), rolling back to an earlier patch or base binary never causes database incompatibility, missing column crashes, or data corruption.
4. If an unhandled exception or network partition occurs during initialization, Owntend's `_RestoreRecoveryGate` presents emergency offline and sign-out options rather than freezing or crashing.

## Sentry and VersionDeck boundaries

The runtime keeps the existing release identity `app.owntend.mobile@x.y.z+N` and dist `N`; patch identity is a bounded tag (`shorebird_patch_number`), not a new Sentry release. Release evidence retains Dart obfuscation symbols, R8 mapping, and exact-revision Shorebird engine-symbol archives. A separately authorized [`tool/publish_sentry_release.ps1`](../../tool/publish_sentry_release.ps1) run requires `-EngineSymbolsDirectory`, validates the canonical revision, hashes, ABI set, and debug/code identifiers, waits for processing, and verifies the exact debug-information files before finalization.

### Sentry Release Health & Patch Regression Alerting

Sentry monitors release health tagged by `shorebird_patch_number` (`base` or patch integer):
- **Alert Rule 1 (Patch Crash-Rate Spike)**: Triggers when the crash-free session rate for any `shorebird_patch_number` drops below 99.0% over a 15-minute evaluation window.
- **Alert Rule 2 (Patch New Issue Spike)**: Triggers when >= 5 new unhandled events with tag `shorebird_patch_number` occur within 1 hour of patch deployment.
- **Rollback Procedure**: When an alert fires on a newly promoted patch, operators immediately disable/rollback the patch in the Shorebird Console to return all clients safely to the previous stable patch.

VersionDeck verifies the unified Shorebird release workflow provenance. Its universal and ABI APKs come from the same canonical AAB. `Verify Production APK Artifact Set` ignores validation/non-production runs, then independently checks a published production artifact set. A successful verified production artifact automatically triggers VersionDeck publication; fail-closed manifest and artifact checks remain mandatory.

## Evidence and incident checks

Every operator review must record the source SHA, flavor/app ID, release version, operation, workflow run, GitHub environment identity, explicit operator authorization, CLI/Flutter/engine revisions, KMS key version, artifact hashes, and device evidence. Do not include tokens, keystore passwords, DSNs containing private query values, user content, or KMS signatures in tickets or logs.

For a suspected credential leak, disable the relevant workflow switch, revoke the Shorebird API key, disable the Workload Identity binding, rotate Android credentials if affected, and follow [`SECURITY.md`](../../SECURITY.md). A leaked app ID alone is not credential compromise, but unexpected app registration or patch activity is.
