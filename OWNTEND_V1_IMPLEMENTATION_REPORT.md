# Owntend production-v1 implementation report

## Implementation metadata

| Field | Final value |
|---|---|
| Repository | `zuhak5/Owntend`, local checkout `F:\Owntend` |
| Lifecycle | Pre-launch: the authoritative `AGENTS.md` checkbox is `[ ]`; there are zero production users and no production-data compatibility obligation |
| Branch | `main` |
| Starting commit | `13d37d14a3ef70c7cc28f6e94dccb2a1ab3d7466` |
| Ending commit reference | `13d37d14a3ef70c7cc28f6e94dccb2a1ab3d7466`; the implementation remains an uncommitted working-tree change |
| Implementation period | 2026-08-21 through 2026-08-22, Asia/Baghdad |
| Release baseline | App `1.0.0`, Android build `1`, Drift schema `1`, backup format `1`, change-feed contract `1`, VersionDeck manifest/cache schema `1` |
| Local tools | Flutter 3.47.0; Dart 3.13.0; Node.js 24.11.1; npm 11.7.0; Deno 2.9.3; Supabase CLI 2.115.0; Flutter Android JDK 21.0.9 |
| Declared Android tools | AGP 9.3; Kotlin 2.4.10; Gradle 9.6.1; Java 21 policy; compile SDK 37; target SDK 36; minimum SDK 24 |
| Remote mutations | None. No commit, push, pull request, hosted deployment, protected workflow, release publication, signing, or Sentry release mutation was performed |

This report records the implementation of the findings and target architecture in [the production-v1 audit and remediation plan](OWNTEND_V1_AUDIT_AND_REMEDIATION_PLAN.md). The repository is intentionally treated as a clean, never-published v1 baseline rather than a sequence of compatibility-preserving upgrades.

## Completed phases

1. Normalized all project-owned release, schema, backup, transport, native-ad, cache, and manifest boundaries to baseline 1.
2. Replaced the unpublished Supabase patch sequence with one canonical initial migration and a canonical behavioral pgTAP suite.
3. Reconciled Drift, PostgreSQL, DTO, mapper, RPC, backup, account-isolation, and deletion contracts.
4. Replaced parallel sync paths and rollout discovery with one payload-bearing change feed plus authoritative snapshot/resnapshot.
5. Hardened outbox, checkpoint, retry, Realtime invalidation, media staging/cleanup, and account-deletion behavior.
6. Decomposed the application root, shared presentation code, monetization, local sync storage, and sync coordination into focused libraries behind stable facades.
7. Removed quarantine, legacy capability, superseded migration, versioned wrapper, duplicate provider, and remediation-era implementation/test paths.
8. Updated Flutter/Dart, Android, Node, Deno, Supabase, CI, release, VersionDeck, documentation, dependency-policy, and generated-source contracts.
9. Ran focused fault tests, complete local automated suites, a fresh local Supabase reset, real local application/backend integration, a debug Android build, and static-site generation/validation.

## Architectural final state

- `lib/main.dart` is a bootstrap-only entry point. Application startup and composition live under `lib/src/app/`, while feature presentation is exposed through ordinary domain libraries rather than a shared application-root private scope.
- Riverpod and GoRouter remain the single dependency-management and navigation systems. Exactly one `databaseProvider` owns the Drift database lifecycle.
- Shared UI and presentation helpers are organized by responsibility. Duplicate asset-type formatting and the former monolithic shared-widget surface were removed.
- `LocalSyncStore` is a stable facade over focused account, outbox, remote-state, mutation, and media stores.
- `SyncCoordinator` is a stable lifecycle facade over run, push, post-ready, and runtime coordination modules.
- No non-generated production Dart source exceeds 2,000 lines.
- Server-authoritative decisions remain in authenticated PostgreSQL functions or Edge Functions; local-first application behavior remains explicit about loading, offline, signed-out, retry, and blocked states.

## Major removals

- Twelve unpublished Supabase patch migrations and their superseded/duplicate database tests.
- VersionDeck `*_v5` implementations, generic wrappers around them, and stale cache/schema history.
- The quarantine resolution feature and its persistence/test paths.
- Capability-discovery and legacy full-pull sync branches.
- The unsupported synchronized device-notification mutation path.
- Parallel/duplicate Drift database providers.
- Obsolete compatibility, Build-44, schema-upgrade, backup-format fallback, and remediation-era test implementations.
- Duplicate UI formatters and the monolithic `shared_widgets.dart`/`enum_formatters.dart` libraries.

## Database final state

- `supabase/migrations/20260821124930_initial_schema.sql` is the only Supabase migration and represents the complete empty-project v1 schema.
- Authenticated ownership is derived from the caller identity; public wrappers and private implementations preserve least privilege, RLS, fixed `search_path`, and owner isolation.
- The canonical schema contains the contract-1 payload-bearing server change feed, authoritative snapshots, durable mutation/idempotency state, prepare/upload/finalize media operations, server-authoritative point/reward operations, and bounded account-deletion receipts.
- Deletion receipts and cleanup operations use documented 90-day pruning semantics.
- A fresh local reset applied only the canonical migration. Local database lint reported no error-level findings, and 25 pgTAP files passed 464 assertions.
- The repository has no checked-in Supabase generated-client-type target. Typed external boundaries are owned by explicit DTOs/mappers and verified against the canonical SQL/RPC contracts, so no stale generated Supabase type file remains.

## Local database final state

- Drift `schemaVersion` is 1, and the generated database source is current.
- Fresh creation directly installs the final schema; there is no pre-release upgrade ladder or compatibility shim.
- Containment, required fields, uniqueness, enum constraints, primary-photo behavior, account isolation, durable outbox intent, sync checkpoints, media cleanup, backup/restore, and derived-search generation are covered by behavioral tests.
- Backup format and embedded database schema are both 1. Imports are treated as untrusted and retain manifest/hash, traversal, size, staging, rollback, and compatibility checks without accepting a superseded Owntend format.

## Dependency and tooling final state

- Android policy is aligned on AGP 9.3, Kotlin 2.4.10, Gradle 9.6.1, and the Flutter-provided Java 21 runtime. A dev debug APK compiles successfully.
- Current plugin compatibility still requires AGP's temporary legacy-KGP mode. Flutter identifies `sentry_flutter` and `workmanager_android` as upstream Built-in-Kotlin migration warnings; the reviewed dependency graph provides no newer compatible release.
- Flutter/Dart, npm, Deno, and Supabase locks were regenerated. Dependency policy covers 316 resolved packages, and npm audit reported zero vulnerabilities.
- CI validates generated sources, Flutter analysis/tests, a disposable local Supabase stack, pgTAP, Deno format/check/tests, Node inventories, documentation links, repository secret patterns, dependency/toolchain policy, Google/static contracts, and VersionDeck generation.

## Version state

The only intended product baseline is:

| Boundary | Version |
|---|---:|
| Application | `1.0.0` |
| Android build | `1` |
| Drift schema | `1` |
| Backup format | `1` |
| Change-feed contract | `1` |
| Native-ad message schema | `1` |
| VersionDeck manifest/control/cache/site inventory | `1` |

External dependency versions, GitHub Action release labels, database engine versions, ABI names, and ordinary fixture values are not product schema boundaries.

## Verification results

### Flutter, generation, and configuration

- `flutter pub get`: passed.
- `flutter gen-l10n`: passed.
- `dart run build_runner build`: passed and regenerated 239 outputs.
- Dart format verification over `lib`, `test`, and `integration_test`: passed after formatting the changed sources.
- `flutter analyze --no-pub`: passed with no issues.
- Production example-configuration contract test with `VERIFY_PRODUCTION_CONFIG=true`: passed.
- Complete Flutter suite excluding the separately gated production-config tag: 713 passed, one explicitly local-backend-gated skip, zero failures.
- Focused sync store/coordinator/hydration suites: 69 passed; the extracted coordinator suite independently passed 29 tests.

### Supabase and Edge Functions

- Fresh `supabase db reset`: passed and applied only `20260821124930_initial_schema.sql`.
- `npm run supabase:lint`: passed with no schema errors.
- `npm run supabase:test`: 25 files and 464 assertions passed.
- Real local-backend Flutter gate: all three scenarios passed, covering two-user RLS/feed isolation, two independent Drift/SyncCoordinator stores converging through Supabase, and private Storage prepare/upload/finalize owner isolation.
- `deno fmt --check`: passed for nine files.
- Frozen `deno check`: passed for all three Edge Functions.
- Deno tests: 56 passed across shared Sentry scrubbing, AdMob SSV, account deletion, and deletion-status behavior.

### Node, policy, documentation, and VersionDeck

- `npm ci`: passed.
- Test inventory: 18 registered suites passed validation.
- `npm run test:all`: 121 passed, zero failed.
- Toolchain, dependency-policy, Google/static-contract, documentation-link, and repository-secret gates: passed; the final secret scan covered 640 repository files after generated staging cleanup.
- Dependency policy reviewed 316 packages: 254 Pub, 52 npm, and 10 Deno.
- `npm audit --audit-level=high`: passed with zero vulnerabilities.
- JavaScript syntax checks for `download-site/` and `tool/`: passed.
- VersionDeck site build at exact source SHA `13d37d14a3ef70c7cc28f6e94dccb2a1ab3d7466`: passed with a 30-file inventory.
- `tool/validate_versiondeck.mjs` against that build: passed.

### Android

- `flutter build apk --debug --flavor dev --no-pub`: passed and produced `build/app/outputs/flutter-apk/app-dev-debug.apk`.
- `:app:lintDevDebug` under Flutter's Java 21 runtime: passed with blocking lint enabled and generated text, HTML, XML, and SARIF reports. Warning-level output includes the separately tracked upstream plugin/AGP compatibility notices.
- `:app:testDevDebugUnitTest`: Gradle passed; the task reported `NO-SOURCE` because the Android host has no separate JVM unit-test sources.
- Repository tests verify blocking release lint configuration and release-evidence report binding.
- A protected signed production APK/AAB, signer/provenance checks, and release lint evidence were deliberately not produced locally.

## Finding disposition

- Implemented at repository level: **28 of 28** findings.
- Invalidated findings: **None**. No audit finding was disproven; implementation evidence refined the target without deleting a valid finding.
- Findings with genuine external verification still pending: **6** (`REL-002`, `SEC-001`, `SEC-002`, `PRIV-001`, `TEST-002`, and `PERF-001`).

`DEP-001` is implemented with an upstream warning tracked. The remaining Built-in-Kotlin notices are dependency-author migration work, not an unimplemented project-owned compatibility layer.

## Externally blocked evidence

| Evidence gate | Repository work complete | Required external authority or resource | Completion evidence |
|---|---|---|---|
| Protected Android and VersionDeck release | Build, verification, provenance, manifest, disabled-state, cache, service-worker, and publication workflows | Explicit authorization for protected signing/publication workflows and their configured secrets | Verified APK/AAB package/version/build/signer/ancestry/checksum/provenance; exact-SHA VersionDeck publication and browser checks |
| Hosted Supabase | Canonical migration, RLS/RPC/Storage/Realtime/cron/Edge contracts and local tests | Explicitly authorized exact-main pre-launch deployment/reset and hosted project/management access | Hosted bootstrap/smoke tests, Advisors, cron observation, Storage/Realtime/Edge configuration and limit evidence |
| Hosted non-production Sentry canary | Deep mobile/Edge scrubbing and adversarial tests | Non-production DSN/project access | A planted sensitive canary is absent while safe diagnostic context remains useful |
| Physical Android and Google matrix | Automated app, native contract, localization, permission, background, auth, ads, backup, and deletion tests | Representative Android devices/emulators plus Google Sign-In, AdMob/UMP, and environment configuration | English/Arabic and RTL, Google auth, rewarded/native ads and consent, permissions/exact alarm, reboot/time-zone/background work, backup/restore, and account-deletion results |
| Named-device performance and reliability | Automated feed call-count, startup, size, backup, search, and deterministic tooling budgets | Named low-, mid-, and high-tier hardware and sufficient observation time | Percentile startup/sync, battery/background, storage/backup, offline/restart, and soak measurements |

These gates are not repository implementation gaps and were not bypassed or represented as locally proven.

Exact authorized follow-up actions are:

1. Configure Shorebird/KMS per `docs/operations/shorebird-code-push.md`; from the exact reviewed `main` SHA, run protected **Shorebird Android Release** validation and only then an authorized production publication, followed by automatic **Verify Production APK Artifact Set**. Inspect the canonical AAB and exact-AAB derived APK evidence/provenance, then separately authorize **Deploy VersionDeck** with `publication_mode=verified`. Verify the public `releases.json` has schema 1, the exact `generatorCommit`, verified artifact hashes/signers, and active publication status; run the browser accessibility/reduced-motion/download checks in `docs/versiondeck-release-runbook.md`.
2. For the confirmed fresh hosted project, run **Deploy Supabase Migrations** with `source_sha=<exact current main SHA>`, `project_ref=<exact project ref>`, `operation=reset-prelaunch-database`, and `confirmation=reset-prelaunch-zero-user`. Then run **Audit Supabase Advisors** and the documented redacted hosted Auth/RLS/Storage/Realtime/Edge smoke matrix; verify the 90-day pruning job appears and executes on schedule.
3. Configure a non-production Sentry project, submit one event containing planted name/email/token/media-path/request-body canaries through both mobile and Edge capture paths, and inspect the received event JSON. Every canary must be absent while the safe error code, release, stack classification, and technical context remain.
4. On each representative device, run `flutter test integration_test/offline_account_localization_test.dart -d <device-id>` and execute the documented English/Arabic, Google Sign-In, AdMob/UMP, permission/exact-alarm, reboot/time-zone/background, backup/restore, and deletion manual matrix against non-production services. Record device/OS/configuration and pass/fail evidence.
5. On named low-, mid-, and high-tier devices, run `flutter run --profile --flavor dev -d <device-id>`, capture startup/sync frame and latency percentiles plus `adb shell dumpsys batterystats` before/after the defined background/soak scenario, and compare the results with the budgets in the audit acceptance matrix.

### Fresh-checkout simulation scope

The practical fresh-environment sequence was exercised through clean npm installation, Flutter dependency resolution, localization and Drift regeneration/checking, an empty local Supabase reset, complete database/backend/application tests, and an Android build. A second Git worktree was not created because the full implementation intentionally remains uncommitted and includes new untracked source files; doing so would not reproduce this working tree without first creating a commit or copying it. No undocumented pre-existing database state was required.

## Documentation synchronization

The documentation-maintenance policy was applied throughout implementation. The following documents were reviewed, with affected documents updated because their behavior, contract, operational procedure, privacy statement, validation command, or release boundary changed:

- `README.md`, `CHANGELOG.md`, and `PRIVACY.md`.
- `docs/README.md` and `docs/governance/documentation-maintenance.md` (policy reviewed; its contract remained accurate).
- `docs/architecture/system-overview.md`, `v1-contracts.md`, `data-model.md`, `sync-protocol.md`, `backup-and-restore.md`, `auth-and-account-deletion.md`, and `monetization.md`.
- `docs/backend/supabase.md` and `migrations-and-functions.md`.
- `docs/development/testing.md` and `android-lint.md`.
- `docs/product/feature-catalog.md`.
- `docs/reference/configuration.md`.
- `docs/SENTRY_OPERATIONS.md`.
- `docs/operations/google-play-data-safety-evidence.md`, `production-containment.md`, and `release-runbook.md`.
- `docs/versiondeck-release-runbook.md`.

The final documentation-link validator passed. Claims that still depend on CI, a hosted project, a protected environment, public hosting, or physical devices are explicitly identified in the external-evidence table above.

## Final release-readiness statement

The repository source, local/cloud contracts, generated artifacts, automated validation, documentation, and release tooling are locally ready as one coherent production-v1 baseline: **application 1.0.0, Android build 1, schema 1**. Local evidence does not establish that a production release has been signed, deployed, published, observed on hosted services, or qualified on physical devices. Production publication should proceed only after the five external evidence gates above are completed under explicit authorization.

No commit, push, pull request, protected workflow, hosted mutation, or public deployment was performed as part of this implementation.

## Final working-tree and cleanup summary

- `git diff --check`: passed.
- Tracked diff: 201 files changed, 10,469 insertions, and 38,015 deletions. The large deletion count is intentional pre-launch removal of superseded migrations, compatibility implementations, wrappers, and obsolete tests.
- Final file-level status: 302 entries comprising 201 tracked modifications/deletions and 101 untracked new implementation files; 53 tracked files are deleted.
- Generated VersionDeck staging directories and the three temporary schema-dump/canonicalization files were verified and removed.
- The disposable local Supabase stack was stopped without retaining a database backup.
- The final tree has no merge markers, active references to the removed UI/VersionDeck/legacy-pull implementations, unresolved `In progress` finding rows, or non-generated production Dart source over 2,000 lines.
