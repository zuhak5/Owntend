# ADR: Shorebird Android code push

## Status

Accepted for pre-launch implementation on 2026-08-22. Production publication remains contained.

## Decision

Owntend uses one Shorebird app per existing Android flavor, exact-commit CLI and engine pins, an explicit canonical release Flutter override, `strict` patch verification, external Google Cloud KMS patch signing, and environment-scoped CI credentials. Shorebird CLI upgrades cannot implicitly change the release Flutter version. A patch must pass the repository's static eligibility policy and Shorebird dry-run without native/asset bypass flags. Production release, patch, and promotion are independent protected operations with separate kill switches. (superseded by REL-001 amendment: production patches publish directly to track `stable`; see Amendment (2026-08).)

The canonical production artifact is one Shorebird-built AAB. Play evidence and VersionDeck APKs derive from that same build. Pinned Bundletool produces a signed universal APK; the protected standalone-signing job prunes the two non-target native directories for each ABI, realigns, resigns, and verifies the result. No second Flutter compilation is allowed.

Sentry release/dist remain bound to the store release. Patch number is a bounded technical tag (`base` or a positive integer), and updater failure is startup-safe. Engine symbols are retained but Sentry upload remains separately authorized.

## Consequences

- App IDs are safe repository Variables; tokens, Android signers, and private KMS material are not.
- A native, asset, dependency, toolchain, or unknown change requires a new release.
- Staging publication and stable promotion are distinct; stable promotion names the exact device-tested patch. (superseded by REL-001 amendment)
- Production patches publish directly to track `stable`; every validation, dry-run, approval, and kill-switch gate completes before publication.
- Rollback is a Shorebird Console operation because the pinned CLI has no unambiguous reviewed rollback command.
- Release build time is higher than ordinary Flutter validation because Shorebird, KMS, evidence, symbols, and provenance are fail-closed gates.

## Amendment (2026-08)

REL-001 deleted the separate Shorebird promotion workflow and its script.
Exactly two Shorebird workflows remain under [`.github/workflows`](../../.github/workflows):
[`shorebird-release-android.yml`](../../.github/workflows/shorebird-release-android.yml) and
[`shorebird-patch-android.yml`](../../.github/workflows/shorebird-patch-android.yml).
Production patches now publish directly to track `stable`; there is no
intermediate staging-promotion step, so all safety validation completes before
publication. The operator procedure is the "Publish a production patch
(Direct-to-Stable)" section of [`docs/operations/shorebird-code-push.md`](../operations/shorebird-code-push.md).
Sentences above that describe the deleted promotion path are marked
"(superseded by REL-001 amendment)".

## Verification

The executable sources are [`config/toolchain.json`](../../config/toolchain.json), [`shorebird.yaml.template`](../../shorebird.yaml.template), the two remaining Shorebird workflows (`shorebird-release-android.yml`, `shorebird-patch-android.yml`) under [`.github/workflows`](../../.github/workflows), the scripts under [`tool/`](../../tool), and their Node/Flutter tests. The operator procedure is [`docs/operations/shorebird-code-push.md`](../operations/shorebird-code-push.md).
