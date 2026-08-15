# Android Production Release Rails

> **Production containment is active.** Since 2026-08-11, production release
> rails are paused.
> Do not dispatch or re-enable a rail from this runbook. Follow the evidence and
> rail-specific prerequisites in the
> [TASK-001 containment record](production-containment.md).

## Scope

This runbook coordinates Owntend's production Android evidence rails. It does not authorize local signing, backend deployment, Google Play upload, rollout, Sentry mutation, or public deployment.

The executable sources are:

- [`tool/build_play_prod.ps1`](../../tool/build_play_prod.ps1) and [`tool/build_prod.ps1`](../../tool/build_prod.ps1)
- [`tool/collect_android_release_evidence.ps1`](../../tool/collect_android_release_evidence.ps1)
- [`tool/validate_google_release_contracts.mjs`](../../tool/validate_google_release_contracts.mjs)
- [`pubspec.yaml`](../../pubspec.yaml)

Use the dedicated [Google Play release runbook](google-play-release-runbook.md) for manual Play Console and Play-delivered device evidence. Use the [VersionDeck runbook](../versiondeck-release-runbook.md) for downstream APK verification evidence.

## Release identity and version uniqueness

The final source identity is one full Git commit SHA on `main`. Freeze that SHA for the entire sequence; do not combine backend, AAB, APK, Sentry, Play, or VersionDeck evidence from different commits.

`pubspec.yaml` is the release identity source and must use `x.y.z+N`:

- `x.y.z` becomes Android `versionName`.
- `N` becomes Android `versionCode` and the Sentry distribution.
- The AAB filename is `Owntend-x.y.z-build-N.aab`.
- The APK filename is `Owntend-x.y.z-build-N.apk`.
- The Sentry release is `app.owntend.mobile@x.y.z+N`.

Both build scripts parse and reject any other version shape. An operator must confirm that `N` is greater than every version code already uploaded to Play before starting the final sequence. Once Play accepts a version code, never reuse it, even if the release is halted or deleted.

If source changes after any final-SHA evidence is collected, choose a new final SHA, update the build number when required, and restart the sequence.

## Strict final-SHA sequence

The sequence below describes the intended protected release contract after
containment is lifted. It is not currently executable authorization.

1. **Backend database gate.** If the release contains pending database migrations, review and apply pending migrations to the exact project ref; inspect remote list and dry-run evidence and require verification to succeed. Then run `Validate Google Backend and Release Contracts` on the same `main` SHA. Its checks cover locked Deno formatting/type/tests for AdMob SSV, account deletion, and deletion-status recovery; deletion-site static tests; Google/Android static contracts; a local Supabase database start, lint, and test cycle; and the read-only Supabase Advisors audit.
2. **APK and Sentry.** Run `tool/build_prod.ps1` at the same SHA. The APK evidence collector must pass before Sentry mutation. Then require successful Sentry publication and artifact validation.
3. **VersionDeck.** Build and validate VersionDeck static distribution. VersionDeck independently verifies the candidate APK before deployment.
4. **Separate AAB evidence.** Run `tool/build_play_prod.ps1` at the same frozen SHA as an independent rail. Review the AAB checksum, upload-key signature evidence, merged manifest, output metadata when present, dependency report, and evidence summary. This workflow does not upload to Google Play.

## Immutable-asset withdrawal, supersession, and incident procedure

Once a release is published, its artifacts must remain durable. Recovery requires a new build under a new version/build number rather than editing an existing release.

**If a released asset is found to be defective:**

1. Do not attempt to delete or overwrite the published release assets.
2. Record the defect, its scope, and whether it affects security, privacy,
   data integrity, or correct behavior.
3. Decide whether downloads should be disabled immediately:
   - If yes, publish an explicit disabled VersionDeck manifest for the
     current `main` SHA to stop the download path. Record this as a VersionDeck containment action.
   - If no, record the decision and the threshold that would change it.
4. Determine whether the release requires a public disclosure, advisory,
   or Play Console action.
5. Create a corrected build with a higher build number (greater than any
   previously uploaded to Play). Follow the full release sequence.
6. After the corrected release is verified, update the VersionDeck
   control file (`tool/versiondeck-control.json`) with a
   `historicalReleaseDecisions` entry for the withdrawn release:
   - `status: "withdrawn"`
   - `reasonCode` identifying the withdrawal cause
   - `message` with a human-readable summary
   - `decidedAt` timestamp
7. Publish a new VersionDeck manifest pointing to the corrected release.
8. Record the complete incident in an operations document.

Never weaken the release-verification checks or VersionDeck trust model to recover a release faster. A slightly delayed corrected release is always safer than a weakened trust boundary.

## Shared build and security gates

Both Android build scripts:

1. Validate canonical toolchain consistency.
2. Run `npm ci`, `tool/validate_google_release_contracts.mjs`, locked Edge Function checks, and locked Edge Function tests.
3. Derive version/build metadata from `pubspec.yaml`.
4. Validate required production variables, construct `config/prod.json`, and restore signing files from secrets.
5. Clean, resolve Flutter dependencies, regenerate localization and Drift output, analyze, run the Flutter test suite, and run the production configuration test.
6. Remove the known generated integration-test registrant and reject `IntegrationTestPlugin` from release registrants before and after the release build.
7. Build the `prodRelease` artifact and remove temporary signing/configuration files in cleanup.

## AAB rail summary

The AAB script creates exactly one `prodRelease` bundle and verifies:

- SHA-256 plus a matching `.sha256` file.
- JAR signature validity.
- The AAB signing certificate matches the certificate in the restored upload keystore.
- Package, version name, and version code through generated metadata or the merged manifest.
- Merged production manifest and runtime-dependency evidence through the shared collector.

The AAB is only a verified upload candidate. The script does not call Google Play APIs, select a track, create an edit, upload release notes, or roll out a release. See the [Google Play release runbook](google-play-release-runbook.md).

## APK and Sentry rail

The APK script additionally validates fixed Sentry organization/project expectations, then builds and verifies the standalone APK:

- Exactly `app.owntend.mobile`, with the `pubspec.yaml` version/build.
- Non-debuggable package metadata.
- APK signature validity and the fixed standalone production signer.
- SHA-256 stability and exact checksum-file contents.
- The same merged-manifest, output-metadata, and dependency evidence collected for the AAB rail.
- Obfuscated Dart symbol files in `build/sentry-debug/dart`, the Flutter obfuscation map `build/sentry-debug/dart/mapping.json`, and the Android R8 mapping file `build/app/outputs/mapping/prodRelease/mapping.txt`.

## Evidence collector contract

For both artifact types, `tool/collect_android_release_evidence.ps1` emits:

- `release-evidence-summary.json` with artifact type/name/SHA-256, parsed package, version name/code, parsed target SDK, parsed backup setting, the exactly-one parsed AdMob application ID, merged-manifest and output-metadata sources, dependency configuration, analytics result, and generation time.
- `prod-release-runtime-classpath.txt` from Gradle `:app:dependencies --configuration prodReleaseRuntimeClasspath`.
- `AndroidManifest-prodRelease.xml`, copied from the newest merged `prodRelease` manifest.
- `output-metadata-apk.json` or `output-metadata-aab.json` when matching generated output metadata exists. APK discovery recognizes the Android Gradle Plugin `outputs/apk/prod/release/output-metadata.json` path; AAB discovery is restricted to `outputs/bundle/prodRelease/output-metadata.json`.

The collector parses the merged XML rather than accepting substring matches. It rejects direct Firebase Analytics, a debuggable production manifest, `android:allowBackup` other than exactly `false`, target SDK other than 36, fine/background location, the Google demo AdMob application ID, missing required coarse-location/notification/exact-alarm permissions, anything other than exactly one production AdMob metadata entry, package mismatch, multiple artifact metadata elements, or version/build mismatch.

## Upload key, standalone APK signer, and Play App Signing

The Play AAB and standalone APK rails use distinct secrets and may use
different keystores. Keep their evidence meanings separate:

- For the AAB, upload secrets represent the **upload key**. The
  script proves the bundle matches the restored keystore, not that the key
  matches the upload certificate currently enrolled in Play Console.
- For the APK, secrets represent the **standalone
  distribution signer**.
- Under Play App Signing, Google signs Play-delivered APKs with the separate **app signing key** shown in Play Console. The Play app-signing certificate must be recorded and verified against a Play-delivered APK. Do not substitute the upload certificate or standalone APK signer unless Play Console independently proves they are the same certificate.

Never export the Play app-signing private key. Store only certificate fingerprints and provenance needed for comparison. See the [Google Play release runbook](google-play-release-runbook.md) for the required Console and device checks.

## Failure and rollback boundaries

- **Backend gate failure:** stop. Do not start either signed artifact rail. A local database gate does not authorize hosted backend deployment.
- **Final SHA changes:** invalidate the release record and rerun the backend, AAB, APK, and downstream evidence for the new SHA.
- **AAB failure before Play upload:** no Play release exists. Preserve diagnostics, discard the candidate, and rerun only after correction.
- **Play accepts the AAB:** the version code is consumed. Halt or remove the affected rollout through Play Console as appropriate, then publish a corrected build with a higher version code; never replace the accepted bundle under the old code.
- **APK evidence failure:** occurs before Sentry mutation; do not publish the APK.
- **Sentry succeeds but a later step fails:** record the partial Sentry release/deploy. The script tolerates an existing Sentry release on retry, but the operator must ensure the same release identity and SHA before retrying.

Never weaken signer, checksum, package, backend, or VersionDeck checks to recover a release.

## Required release record

Record at minimum:

- Final source SHA and `pubspec.yaml` version/build.
- Backend verification output and separate hosted-backend deployment evidence.
- AAB artifact name, artifact/checksum equality, upload-certificate fingerprint, evidence-summary fields, and manifest/dependency review.
- APK artifact/evidence names, checksum, standalone signer, Sentry release/deploy, and partial-state notes if any.
- VersionDeck source SHA, independent verification result, and public manifest result.
- Google Play Console upload, Play App Signing, track/rollout, app-content, and device evidence from the dedicated runbook.
- Operator, reviewer/approval evidence, timestamps, exceptions, rollback decisions, and all checks deferred to hosted services or devices.

Do not put credentials, tokens, private signing material, direct user identifiers, or private test data in the release record.
