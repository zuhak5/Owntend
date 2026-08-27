# Production containment

_Last updated: August 28, 2026_

Scoped containment is active. Signed/validated evidence is distinct from public or hosted-service mutation.

## Allowed evidence operations

- ordinary read-only validation and backend/security contract checks;
- `Shorebird Android Release` with `operation=validate` (server dry-run, no release publication);
- `Shorebird Android Patch` with `operation=validate` (static gate and server dry-run, no patch publication);
- protected checksums, package/signer/manifest/dependency/lint/SBOM/symbol/toolchain/provenance evidence;
- VersionDeck deployment with explicit `disabled` publication;
- privacy-scrubbed runtime Sentry ingestion configured by the public DSN.

Validation still enters the selected GitHub environment because Shorebird authentication, Android release signing, and KMS public-key access are required. The `production` environment does not require a separate deployment review: exact-source and branch policies, the requested workflow operation, explicit operator authorization, and the matching kill switch remain the publication controls.

## Separately contained mutations

- production Shorebird release publication (gated by explicit operator authorization and the `SHOREBIRD_PRODUCTION_RELEASES_ENABLED` kill switch);
- production patch publication to staging and exact staging-to-stable promotion;
- Shorebird Console patch rollback/disable;
- Google Play upload/track/rollout;
- Sentry release/deploy/debug-file mutation using `SENTRY_AUTH_TOKEN`;
- hosted Supabase mutation except through its separately authorized protected workflow.

Once production Shorebird release publication is authorized and successfully executed on `main`, the downstream pipeline automatically drives APK set verification, GitHub Release creation with verified APK assets, and VersionDeck deployment to GitHub Pages in verified publication mode.

The enable Variables remain absent/false until an operator records explicit approval.

## Preserved guarantees

Production release/patch paths require exact identity, current-main/backend gates where applicable, environment-scoped credentials, separate Play and standalone signers, exact Shorebird/tool pins, non-exportable KMS patch signing, no native/asset bypasses, retained symbols, independent provenance, and no Play/Sentry/VersionDeck mutation. The canonical production AAB is built once; VersionDeck APKs are derived from it without a second Flutter compile.

Before lifting any containment boundary, complete hosted security/advisor review, physical-device evidence, privacy/Data safety/store disclosures, signer and KMS verification, source/artifact provenance, rollback ownership, credential scope/rotation, and the operation-specific runbook. A failed or partial run cannot be converted into publication by manual bypass.

See [`shorebird-code-push.md`](shorebird-code-push.md) and [`release-runbook.md`](release-runbook.md).
