# Android release runbook

Production release mutation remains contained. This runbook defines evidence and handoff; it does not authorize a Shorebird publish, Play upload, Sentry mutation, GitHub Release, VersionDeck publication, hosted backend mutation, or rollout.

## Canonical release rail

[`Shorebird Android Release`](../../.github/workflows/shorebird-release-android.yml) replaces the old independent APK and Play builds. It accepts an exact source SHA, flavor, and `validate`/`publish` operation. `validate` is the default and runs `shorebird release android --dry-run`. Production publication additionally requires:

- dispatch from exact current `main`;
- an exact successful `Validate Google Backend and Release Contracts` run for the source SHA;
- `production` environment approval;
- `SHOREBIRD_PRODUCTION_RELEASES_ENABLED=true`;
- the environment-scoped Shorebird token, Play upload signer, and non-exportable production KMS signing key.

The backend workflow's required jobs include `Deno SSV tests`, `Google contract/static checks`, and `Supabase database tests`. A pending migration must follow the separately protected migration workflow; release CI does not deploy it.

The release workflow produces one canonical Shorebird AAB with obfuscation, Dart symbols, R8 mapping, merged-manifest/dependency/lint/SBOM evidence, exact toolchain manifest, engine symbols, checksum, and provenance. The release identifier is the `pubspec.yaml` value `x.y.z+N`. Sentry retains `app.owntend.mobile@x.y.z+N` and dist `N`.

## VersionDeck APK derivation

Only a published production release can enter `production-android-signing`. [`tool/derive_versiondeck_apks.ps1`](../../tool/derive_versiondeck_apks.ps1) consumes the exact AAB from the preceding job. Pinned Bundletool creates the signed universal APK. The script then derives `arm64-v8a`, `armeabi-v7a`, and `x86_64` APKs by pruning other native directories, aligning, resigning with the established standalone signer, and verifying package, version/build, signer, native-directory set, hash, and size. It never invokes Flutter.

`Verify Production APK Artifact Set` ignores non-production and dry-run workflows. For the exact protected artifact, it rechecks all three ABI APKs and GitHub attestations at current `main`. This verification is evidence only and does not authorize distribution.

## Operator sequence

1. Freeze one exact `main` SHA and the `pubspec.yaml` release identity.
2. Require all ordinary Flutter, Node, Android, security, backend, database, documentation, dependency, secret-scan, and action-pin checks.
3. Run `Shorebird Android Release` with `flavor=prod`, `operation=validate`, and the exact SHA. Review the dry-run evidence.
4. Complete physical-device release smoke tests and the Play/Data safety/privacy reviews.
5. Only after explicit production authorization, enable the release kill switch and rerun with `operation=publish` through the protected `production` environment.
6. Review the canonical AAB evidence and the separately protected exact-AAB APK derivation/verification. Do not mix artifacts from different runs or SHAs.
7. Handle Play, Sentry, GitHub Release, and VersionDeck as separately authorized operations using their own runbooks.
8. For a patch, follow [`shorebird-code-push.md`](shorebird-code-push.md); a native, asset, dependency, or toolchain change requires a new release.

## Failures and partial state

- A validation failure publishes nothing. Fix the cause; never add Shorebird bypass flags.
- A Shorebird release upload that partially succeeds must be inspected in the Shorebird Console before retrying the same version. Do not change source SHA or signing keys during a retry.
- APK derivation failure does not invalidate the Play AAB or Shorebird release, but blocks VersionDeck evidence. Retry only from the same AAB hash and source run.
- Sentry and VersionDeck failures do not justify rebuilding the AAB. Preserve symbols/evidence and use the same release/source identity.
- A bad patch is disabled or rolled back in the Shorebird Console; do not treat promotion or a counter-patch as rollback.

## Required release record

Record the exact source SHA, backend-gate run, workflow run/attempt, flavor/app ID, Shorebird release version, CLI/Flutter/engine revisions, KMS key version, AAB hash/signature, Play upload signer, standalone APK signer, APK hashes, attestations, symbol/evidence artifact IDs, environment approvals, device evidence, and every separately authorized publication decision. Never record tokens, private keys, keystore passwords, user content, or raw credentials.

See [`shorebird-code-push.md`](shorebird-code-push.md), [`google-play-release-runbook.md`](google-play-release-runbook.md), [`../versiondeck-release-runbook.md`](../versiondeck-release-runbook.md), [`../SENTRY_OPERATIONS.md`](../SENTRY_OPERATIONS.md), and [`production-containment.md`](production-containment.md).
