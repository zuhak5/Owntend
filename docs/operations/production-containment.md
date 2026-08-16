# TASK-001 Production Containment

_Last updated: August 16, 2026_

## Status

Scoped containment is active.

The repository distinguishes **signed evidence production builds** from
**public or hosted-service publication**.

## Allowed during scoped containment

The following operations are allowed only from exact current `main` and through
their protected GitHub Actions workflows:

- Read-only validation and backend contract checks.
- Signed standalone production APK evidence build.
- Signed Google Play AAB evidence build.
- APK/AAB checksum, signing, manifest, dependency, and provenance verification.
- Storage of build evidence and symbol/mapping artifacts as GitHub Actions artifacts.
- VersionDeck deployment with an explicit `disabled` publication manifest.
- Runtime Sentry ingestion configured only by the public DSN and existing privacy scrubbers.

An allowed evidence build does not itself authorize distribution.

## Still contained

The following remain blocked until separately reviewed and authorized:

- Sentry release creation, deploy mutation, or use of `SENTRY_AUTH_TOKEN`.
- GitHub Release or Git tag publication of a production APK.
- VersionDeck `verified`/active download publication.
- Google Play AAB upload, track selection, rollout, or production publication.
- Hosted Supabase mutation unless separately authorized by its protected deployment process.
- Any weakening of signer, checksum, package, backend, privacy, or provenance checks.

## Evidence-build contract

A production APK evidence run must:

1. Require exact current `main`.
2. Require the exact-SHA backend/release-contract validation gate.
3. Use only the protected standalone production signing environment.
4. Build and test the production configuration.
5. Verify package, version/build, non-debuggable status, checksum, and fixed signer.
6. Collect merged-manifest, dependency, symbol, mapping, and workflow evidence.
7. Produce GitHub build provenance and verify the provenance tuple.
8. Upload the signed APK and evidence only as protected workflow artifacts.
9. Perform no Sentry or public release mutation.

The Play AAB evidence rail remains separate and must preserve its independent
upload-key and provenance verification.

## Publication prerequisites

Before public production publication is lifted, record evidence that:

- Current Supabase advisor/security findings have been reviewed and remediated
  or explicitly accepted with a documented risk decision.
- Hosted backend state required by the release matches the frozen source SHA.
- Google Play upload-key certificate identity has been confirmed in Play Console
  before any AAB submission.
- Any decision to enable Sentry release mutation includes reviewed token scope,
  project identity, privacy controls, symbol artifacts, and retry/partial-state behavior.
- VersionDeck verified publication has a separately authorized immutable GitHub
  release artifact to verify.
- Store, privacy, account-deletion, advertising, and required public-site
  disclosures are ready for the chosen distribution path.

## Failure behavior

A failed evidence build creates no public release. Fix the cause, produce a new
exact-main validation result when source changes, and rerun the evidence rail.

Do not convert a failed or incomplete evidence run into a public release by
manually bypassing the protected checks.