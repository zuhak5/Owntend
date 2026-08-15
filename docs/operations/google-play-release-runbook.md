# Google Play AAB Release Runbook

> **Play release containment is active.** Release rails are paused.
> Do not
> build, upload, or roll out from this runbook until authorized.

## Purpose and authority

This runbook governs the handoff from Owntend's verified AAB build artifact to a manually controlled Google Play release. It does not authorize a Play upload or rollout by itself.

The executable AAB sources are:

- [`tool/build_play_prod.ps1`](../../tool/build_play_prod.ps1)
- [`tool/collect_android_release_evidence.ps1`](../../tool/collect_android_release_evidence.ps1)
- [`tool/validate_google_release_contracts.mjs`](../../tool/validate_google_release_contracts.mjs)
- [`pubspec.yaml`](../../pubspec.yaml)

The cross-rail order, APK publication, and VersionDeck handoff are defined in the [Android production release runbook](release-runbook.md).

## No automatic Play upload

Building the Play Store AAB is a signed build-and-evidence process. It contains no Google Play API call, service-account credential, edit/track operation, staged rollout, or publish step.

Release notes are entered and captured during the separately authorized Play Console operation.

Do not claim that an AAB build uploaded, validated, or released anything in Google Play. Automated upload would require a separately reviewed implementation and documentation change.

## Preconditions

Before building the AAB:

1. Select the full commit SHA that exactly equals the current `main` tip and freeze it for all release rails.
2. Confirm `pubspec.yaml` uses `x.y.z+N` and that `N` is greater than every version code ever accepted by Google Play for `app.owntend.mobile`.
3. Run `Validate Google Backend and Release Contracts` on `main`. The validation run uses a local stack and is not hosted deployment evidence.
4. Review user-visible release notes, privacy impact, permissions, ads, account deletion, data retention, and store declarations.
5. Confirm the expected Play application/package is `app.owntend.mobile`, the intended initial target is identified, and no conflicting Play edit or rollout is active.

## Version and artifact identity

The build parses `pubspec.yaml` and rejects values outside `x.y.z+N`. It expects one `prodRelease` bundle and renames it to `Owntend-x.y.z-build-N.aab`. Its checksum file is `Owntend-x.y.z-build-N.aab.sha256` and contains the lowercase SHA-256, two spaces, and that exact filename.

Play may reject a duplicate even when all repository checks pass. Once Play accepts `N`, it remains consumed; a corrected bundle must use a higher build number/version code.

## Upload key versus Play App Signing

Keep these identities separate in evidence:

1. **Upload key certificate.** The AAB is signed with the keystore restored from upload signing secrets. The build runs `jarsigner`, reads the AAB certificate with `keytool -printcert -jarfile`, reads the restored keystore certificate, and requires those SHA-256 digests to match. This proves internal consistency with the supplied upload keystore only.
2. **Play-enrolled upload certificate.** Google Play Console shows the certificate it accepts for bundle uploads. Compare its SHA-256 fingerprint with `aab-signature-verification.txt`.
3. **Play App Signing certificate.** When Play App Signing is enabled, Google signs generated/delivered APKs with the app signing key shown in Console. That certificate can differ from the upload certificate and from the signer on Owntend's standalone APK. Record it separately and verify a Play-delivered APK against it.

Never upload or archive either private key as evidence. A certificate fingerprint is evidence; a private keystore, password, base64 secret, or signing export is prohibited.

## Build steps and gates

After execution at the final SHA, require completion of:

1. Toolchain consistency check.
2. `npm ci`, Google/Android static contract validation, and locked AdMob SSV/account-deletion/deletion-status Deno checks/tests.
3. Production configuration creation and upload-keystore restoration.
4. Flutter clean/dependency resolution, localization and Drift generation, analysis, tests, and production-configuration validation.
5. Release registrant checks and `flutter build appbundle --flavor prod --release` through `tool/build_play_prod.ps1`.
6. Exactly one bundle, SHA-256/checksum creation, JAR signature verification, and AAB-to-upload-keystore certificate comparison.
7. Manifest/dependency evidence collection.
8. Always-run cleanup of temporary signing/configuration files.

## Exact AAB evidence package

Retain the final SHA and evidence files:

- `Owntend-x.y.z-build-N.aab`
- `Owntend-x.y.z-build-N.aab.sha256`
- `release-evidence-summary.json`
- `prod-release-runtime-classpath.txt`
- `AndroidManifest-prodRelease.xml`
- `aab-signature-verification.txt`

The summary must agree with the AAB on artifact filename/hash, parsed `app.owntend.mobile` package, version name/code, parsed target SDK 36, parsed `allowBackup: false`, the exactly-one parsed production AdMob application ID, and `prodReleaseRuntimeClasspath`. The dependency report must be retained in full and contain no direct Firebase Analytics dependency. The merged manifest must contain the required coarse-location, notification, and exact-alarm declarations; it must not contain fine/background location, a Google demo AdMob identifier, or a debuggable production flag.

`aab-signature-verification.txt` must show successful JAR verification and the upload-certificate SHA-256 emitted by the build. Compare that fingerprint with Play Console.

Safe independent inspection after building includes:

```powershell
Get-FileHash -LiteralPath .\Owntend-x.y.z-build-N.aab -Algorithm SHA256
jarsigner -verify -verbose -certs .\Owntend-x.y.z-build-N.aab
keytool -printcert -jarfile .\Owntend-x.y.z-build-N.aab
```

## Manual Play Console handoff

The Console operation is an externally authorized state change. Use an internal testing track first unless the approved release plan explicitly requires another target.

1. Open the intended Owntend application in Play Console and record the application identity and current highest accepted version code.
2. Review **App integrity** before upload. Record the enrolled upload-certificate and Play App Signing certificate SHA-256 fingerprints; compare the upload fingerprint with the AAB evidence.
3. Create or select the approved track release and upload the verified AAB. Confirm Play reports the expected package, version name, version code, target SDK, and no unexpected blocking error.
4. Review Bundle Explorer/generated APK details, manifest permissions/features, supported devices, native-code/debug-symbol notices, and Play's automated checks. Do not dismiss warnings without a recorded decision.
5. Enter the approved release notes manually.
6. Review countries/testers, rollout percentage, managed-publishing state, availability, and start time. Capture the review screen before the final rollout action.
7. Obtain the required human approval immediately before submitting the Console action that creates, publishes, or advances a release.
8. Record the resulting release/track status and Console timestamps. Do not describe a draft, processing bundle, or pending review as released.

## App-content and data-safety evidence

Use the [Google Play data-safety evidence worksheet](google-play-data-safety-evidence.md) for the exact release. It is an engineering starting point, not a Play Console export or proof of submitted declarations.

At minimum, reconcile Play Console App content against the reviewed build and current privacy policy:

- Data safety collection, sharing, purpose, security, and deletion answers.
- Privacy-policy URL and public account-deletion URL.
- Ads declaration and families/target-audience status where applicable.
- App access instructions for review accounts if required.
- Coarse location, notification, and exact-alarm declarations and justifications.
- Absence of fine/background location in the merged production manifest.
- Google sign-in, Supabase, AdMob, Sentry, backup/export, retention, and deletion behavior.

## Play-delivered device evidence

An AAB cannot be installed directly, and a locally generated APK set cannot prove Play signing or Play delivery. After the internal-track release is available, install/update through Google Play on a controlled physical device and record:

- Tester account/track eligibility without exposing the account address.
- Device model, Android/API version, locale, and clean-install versus update path.
- Installed package `app.owntend.mobile`, expected version name/code, and release/non-debuggable behavior.
- Play-delivered base APK certificate SHA-256 matching the Play App Signing certificate recorded from Console.
- Cold start and first-run behavior; Google sign-in and account binding; sync and private media.
- Notification permission, scheduling, exact-alarm behavior, reboot/update restoration, and graceful denial states.
- Coarse-location-dependent behavior with fine/background location absent.
- Consent, ads, reward verification/pending recovery, and core behavior when ads are unavailable.
- Backup/export and restore checks appropriate to the release.
- In-app and public-web account-deletion entry points, using disposable data when destructive verification is approved.
- Sentry release association and privacy-safe diagnostics without user content.

## Failure and rollback boundaries

- **Build or evidence failure before upload:** stop; Play state is unchanged. Correct the source/configuration and produce a new accepted AAB before Console work.
- **Upload certificate mismatch:** do not bypass signature checks or upload a differently signed local bundle. Verify the selected application and keystore, then use Play's approved upload-key recovery process only when authorized.
- **Play rejects version code:** choose a higher build number in `pubspec.yaml`, create a new final SHA, and restart the complete sequence.
- **Bundle accepted but release still draft:** the version code is consumed even if the draft is later discarded. Preserve Console evidence and use a higher code for a replacement.
- **Internal/device validation fails:** halt promotion. Record affected versions/devices, fix with a higher version code, and repeat all final-SHA evidence.
- **Staged rollout regression:** halt the rollout through Play Console and assess whether an existing safe release can continue serving users. Android upgrades still require a higher version code for the correction; do not attempt a downgrade artifact.
- **Play-only failure:** does not automatically withdraw the standalone APK or VersionDeck. Evaluate and act on those rails separately.

Never delete or overwrite evidence to make a later run appear continuous with an earlier SHA or version code.

## Required Play release record

Record:

- Final SHA, `pubspec.yaml` version/build, and backend deployment dependency.
- Artifact names, recomputed/checksum/summary hashes, upload certificate, and manifest/dependency review.
- Play application, App integrity fingerprints, uploaded bundle version, Bundle Explorer result, automated checks/warnings, track, testers/countries, rollout/managed-publishing settings, approvals, and timestamps.
- Data-safety/app-content evidence at the reserved canonical path.
- Physical-device install/update results, Play-delivered signer, functional/privacy checks, and deferred cases.
- Rollback/halt decisions and the independent status of Play, Sentry, and VersionDeck.
