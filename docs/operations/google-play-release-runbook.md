# Google Play release runbook

This runbook governs the separately authorized Play handoff. No repository workflow uploads an AAB to Google Play or starts a rollout.

## Artifact source

The only acceptable AAB is `app-prod-release.aab` from a successful, explicitly authorized `operation=publish` run of [`Shorebird Android Release`](../../.github/workflows/shorebird-release-android.yml). It is signed with the established Play upload key and built once with the pinned Shorebird CLI/Flutter engine, obfuscation, strict patch verification public key, production runtime configuration, and exact current `main`.

Do not build an independent Flutter AAB for Play. Do not use a validation/dry-run artifact, VersionDeck-derived APK, patch artifact, local build, or different SHA. [`tool/collect_android_release_evidence.ps1`](../../tool/collect_android_release_evidence.ps1) binds the AAB to package, version/build, merged manifest, dependencies, lint, SBOM/notices, assets, symbols, R8 mapping, canonical toolchain, exact Shorebird revisions, source SHA, and workflow context.

## Pre-upload review

1. Match the frozen source SHA, `pubspec.yaml` version/build, Shorebird release, AAB SHA-256, and provenance.
2. Confirm the exact backend validation gate and any separately approved migration have completed.
3. Verify package `app.owntend.mobile`, upload-key certificate, target/min SDK, non-debuggable state, manifest/permissions, R8 mapping, and Dart/engine symbol retention.
4. Complete release tests on physical devices, including Google sign-in, Supabase sync/deletion, AdMob consent/reward verification, notifications/background work, backup/restore, English/Arabic RTL, offline behavior, and Shorebird base startup.
5. Complete [`google-play-data-safety-evidence.md`](google-play-data-safety-evidence.md), `PRIVACY.md`, screenshots/listing, content rating, ads declaration, app access, target audience, and account-deletion URL review. Engineering evidence is not proof of Console submission.

## Play Console handoff

An authorized Play operator uploads the exact AAB manually or through a separately reviewed protected process, first to the internal track. Record the Play artifact digest, versionCode, upload signer, Console receipt, tester cohort, review result, rollout decision, and link to the Shorebird release evidence. Do not expose Android signing or Shorebird credentials to the Play handoff.

The Play upload and Shorebird server release are related but separate state. If Play rejects the AAB, do not publish patches for a base users cannot install. If a new AAB is required, increment the build/version as appropriate and create a new Shorebird release; do not overwrite a registered release with different native code.

## Rollout and rollback

Promote through Play tracks only after internal testing. Monitor privacy-safe crash/performance signals and functional smoke tests. A Play rollback/halt affects base distribution; a Shorebird patch rollback affects code-push delivery. Record and execute them independently. Do not use a Shorebird patch to conceal a Play artifact identity, signer, native, permission, asset, or policy problem.

See [`release-runbook.md`](release-runbook.md), [`shorebird-code-push.md`](shorebird-code-push.md), and [`../SENTRY_OPERATIONS.md`](../SENTRY_OPERATIONS.md).
