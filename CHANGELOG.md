# Changelog

Owntend uses Git history as the authoritative record of shipped changes. This file records notable project-level changes that affect users, operators, contributors, architecture, security, or compatibility.

The current application version is defined only in `pubspec.yaml`. Released versions are recorded below after their version and build numbers have been finalized.

## Unreleased

- Hardened Supabase schema triggers and Flutter sync serialization across all 17 synchronized tables: `set_owntend_row_metadata()` now defensively coalesces default-backed NOT NULL columns (`sort_order`, `required_materials_json`, `reminder_days_before`, `is_enabled`, `is_primary`, `created_at`, `revision`) on `BEFORE INSERT OR UPDATE`, Drift `MaintenancePlanMetadata` defaults `sortOrder` to `0`, `TaskMetadata` defaults `sortOrder` to `0`, and local-to-remote DTO serialization sanitizes all default values before payload dispatch, resolving `23502` constraint violations. Bumped application version to `1.0.0+6`.

- Automated continuous delivery pipeline from Shorebird production publish to public VersionDeck download site: `Verify Production APK Artifact Set` now automatically creates/updates the official GitHub Release with verified ABI APKs and SHA-256 checksums upon successful APK verification, and triggers `Deploy VersionDeck` via `workflow_run` to generate the verified manifest and deploy the update to GitHub Pages.
- Upgraded Android compilation target to `compileSdk = 37` across build scripts and canonical toolchain specifications to resolve Android 16/17 AAR metadata requirements from modern AndroidX and native storage/permission plugins, while keeping runtime target at `targetSdk = 36` and minimum reach at `minSdk = 26`.
- Upgraded `archive` to `^4.2.0` (resolving large archive streaming and `XZDecoder` fixes) and verified 100% compliance across all 312 package dependencies under license and vulnerability review policies.
- Implemented comprehensive pre-release native Android foundation hardening: parameterized Google AdMob Application ID via Gradle `manifestPlaceholders` per flavor, removed `SCHEDULE_EXACT_ALARM` in favor of standard battery-friendly inexact scheduling, pinned toolchain compilation target to `compileSdk = 37` and `minSdk = 26`, eliminated deprecated legacy system UI flags in favor of modern AndroidX `WindowCompat`, added ProGuard/R8 protection for `flutter_foreground_task` and `androidx.media3`, fixed Android 12+ dark mode splash background to `#0D2118`, resolved edge-to-edge `NormalTheme` windowFullscreen conflicts, ensured RTL-safe `paddingStart`/`paddingEnd` across all native ad layout XML resources, and strengthened Drift database schema v1 with `SyncAccount.migrationState` CHECK constraints, nullable `InboxNotifications.dedupeKey`, and idempotent startup triggers.
- Replaced the duplicate Android APK/AAB build rails with one exact-commit-pinned Shorebird release rail, strict fail-closed Dart-only patch validation, staging-to-stable exact-patch promotion, non-exportable Google Cloud KMS signing, runtime Sentry patch attribution, retained engine symbols, and VersionDeck APK derivation from the canonical AAB without a second Flutter compile. Production publication remains protected and disabled until operator account/app IDs, tokens, environments, KMS, device evidence, and explicit authorization are complete.
- Rebuilt the never-published production-v1 baseline around one app/build, Drift/backup schema 1, one canonical Supabase migration, one contract-1 change feed plus authoritative snapshots, prepare-before-upload media staging, bounded deletion recovery, and VersionDeck manifest/cache contract 1.
- Extracted application bootstrap and dependency composition from `main.dart`, split shared UI and monetization buckets into focused modules, removed quarantine and other pre-release compatibility paths, and renamed remediation-era tests around the behavior they protect.
- Added real loopback Supabase integration coverage for two-user RLS isolation, two local app databases converging through outbox/snapshot/feed, and the private Storage prepare/upload/finalize saga; expanded CI with generated-source drift, documentation-link, secret, dependency-audit, Deno, and application/backend gates.
- Updated Flutter, WorkManager, foreground-task, archive, SQLite, Supabase CLI, and Java policy baselines and regenerated their locks and derived sources.
- Made local-first runtime screens update live from Drift/Riverpod without duplicate Home/Rooms render delays, kept startup Home snapshots seed-only once live domain values exist, and made resume/reconnect convergence pull-capable even after a recent sync so missed Realtime changes repair without navigation or manual refresh.
- Fixed points counter synchronization with one auth-scoped, server-authoritative wallet owner that immediately adopts charged RPC/recovery balances, converges external/SSV changes through Realtime plus canonical resume/reconnect refetches, and prevents stale snapshots or cross-account balances from regressing the UI.

### Fixed

- Fixed missing client SHA-256 `request_hash` generation during item and copy-item creation by establishing `SupabaseMonetizationRepository.createAsset` as the canonical signing authority for `create_asset_with_point_debit` RPC calls.
- Fixed sync failure `unsupported entity contract: device_setting` (Sentry issue `da919b7359724279966e88d5ce5ae663`) by eliminating SQLite triggers on device-local settings, purging legacy mutation queue entries, and gracefully ignoring unmapped `device_setting` mutations.
- Upgraded Shorebird production patch pipeline to publish directly to track `stable`, deprecating intermediate staging promotion, and added structured app-level patch observability diagnostics in `PatchUpdateCoordinator` and `DiagnosticExportService`.
- Fixed `null` `client_updated_at` values in Supabase `server_change_feed` for `profile` records, backfilled existing rows, enforced `NOT NULL` on change-feed client timestamps, and added resilient `created_at` fallback in Flutter client change-feed parsing to prevent sync-blocking `incompatibleSchema` errors.
- Fixed missing Android `GeneratedPluginRegistrant` in Shorebird release and patch builds by removing the premature registrant deletion before the Shorebird build invocation, ensuring plugin platform channels are present at runtime.
- Fixed Android plugin registration in minified release builds by using additive Gradle sourceSet configuration and preserving Flutter plugin reflection entry points in ProGuard rules.
- Resolved batched build provenance attestations by matching target artifact subjects across multi-subject SLSA statements in VersionDeck APK verification tooling.
- Fixed Bundletool password flag format to use `pass:` prefix and pinned Node.js setup in the protected VersionDeck APK derivation workflow job.
- Included R8 `mapping.txt` in the canonical Shorebird release evidence artifact upload to support downstream protected VersionDeck APK derivation and symbol packaging.
- Removed `integration_test` SDK dev dependency and migrated `offline_account_localization_test.dart` to unit/widget testing in `test/`, preventing `IntegrationTestPlugin` from leaking into release plugin registrants during Flutter and Shorebird builds.
- Scoped `verify_android_release_registrants.ps1` build output scanning to `build\app` to avoid deep Shorebird toolchain cache recursion on Windows runners.
- Kept Shorebird `--dry-run` on the Shorebird side of the `--` Flutter-argument separator in release and patch command builders, preventing validation runs from forwarding an unsupported option to `flutter build`.
- Ordered Shorebird release and patch validation so the committed-source policy test runs before the temporary `shorebird.yaml` asset injection, while preserving that injection immediately before the protected build.
- Pinned generated `*.g.dart` files to LF checkouts so the Windows Flutter CI runner can reproduce Drift output without false CRLF-only generated-source failures.
- Revoked inherited Supabase Data API execution from anonymous and authenticated callers for the four server-only account-cleanup, recent-session, and AdMob settlement `SECURITY DEFINER` RPCs, with explicit service-role grants and pgTAP regression coverage.
- Removed editable/persisted task Health Group; task scoring, statistics, and icons now derive from the linked item's Item Type. General remains explicitly excluded from weighted health-score normalization, while Cleaning remains task semantics.
- Made the “Today’s care is complete” reward prompt content-sized and accessible, with concise English/Arabic copy, responsive non-truncated actions, reduced-motion handling, and verification-pending messaging that never implies device-side reward credit.
- Removed Category as a duplicate item classification: Item Type is now the sole item classifier across UI/domain, Drift schema/search, asset sync payloads, current backups, and the pre-launch Supabase asset/RPC contract; safety checks use `asset_type`, while task Health Group behavior remains an independent domain rule.
- Unified the English/Arabic language selector across onboarding and Settings with anchor-width menus, directional RTL positioning, centered selected labels, and visible open-state accessibility feedback.
- Standardized Settings row gutters, leading-icon columns, text starts, trailing controls, and RTL-aware dividers across Language, Weather, permissions, and notification preferences without changing their behavior.
- Made Statistics content-driven and responsive so metric cards, charts, legends, inline empty states, text scaling, and RTL layouts remain readable without viewport-stretched chart panels or nested empty-state surfaces.
- Rebaselined the zero-user Supabase schema into one canonical initial migration, removed duplicate/remediation-era history, normalized the always-on change-feed boundary as integer contract `1`, and retained the exact-main protected workflow for an explicitly confirmed destructive pre-launch hosted reset.
- Removed authenticated-executable `SECURITY DEFINER` RPCs from the exposed Supabase API schema by routing privileged media and charged-operation status work through private implementations, optimized statement-stable RLS helpers, added the missing notification foreign-key index, and made hosted Advisor `INFO` findings non-blocking evidence while preserving fail-closed handling for warnings and unknown severities.
- Hardened change-feed RPC privileges so client-facing feed functions run as `SECURITY INVOKER`, derive account scope from authenticated identity, reject anonymous execution, and expose no caller-selected user IDs or rollout-capability branch.
- Hardened the server change-feed contract with exhaustive entity identifiers, canonical upsert payloads, typed delete keys, fail-closed client validation, and crash-durable retention-gap resnapshot checkpoints.
- Kept full-text search mutation-consistent by tracking durable source/index generations so edits, archive/restore/delete operations, sync writes, and restarts rebuild stale derived search data before returning results.
- Prevented delayed weather refreshes for a previous home location from overwriting the cache after the selected location changes.
- Invoked automatic-backup due checks after authenticated startup readiness and on throttled foreground resumes without blocking the first useful UI frame.
- Kept task inbox notifications unread when completion is cancelled or otherwise not applied, acknowledging them only after confirmed successful completion.
- Wired authenticated notification startup to idempotent daily background refresh registration and added a crash-safe consumer for durable notification reconciliation requests.
- Routed Realtime delete notifications through account-scoped authoritative reconciliation so peer delete hints cannot directly erase local rows, shadows, or pending outbox intent.
- Made inbound sync checkpoints pull-owned and transactionally atomic with the rows and shadows they acknowledge, preventing push acknowledgements or interrupted pull pages from skipping remote changes.
- Aligned the Supabase device `consumable` field with Flutter's optional descriptive-text contract so normal filter, battery, and cartridge descriptions no longer fail asset creation.
- Preserved item `placement` during the server-authoritative asset-creation RPC.
- Centralized built-in category and recurrence presentation, localized built-in pet species, corrected Arabic recurrence/reminder/duration grammar across detail and task-card surfaces, and removed English-only relationship fragments from Arabic UI surfaces.
- Added Arabic search aliases for controlled categories, room/item types, power sources, sunlight, and built-in pet/fish values while keeping canonical stored values locale-neutral.

### Added

- **Initial Production Baseline**:
  - Full-featured household asset organization, inventory tracking, and maintenance management for Android.
  - Offline-first local persistence via Drift SQLite with schema version 1, foreign keys, write-ahead logging (WAL), and FTS5 full-text search indexing with Unicode support.
  - Authenticated cloud synchronization with Supabase PostgreSQL, Row Level Security (RLS) policies, and table-aware real-time change feed.
  - Multi-factor resilient Google Sign-In authentication with secure session persistence.
  - Fully automated, privacy-compliant account deletion lifecycle with cryptographic recovery tokens and complete media cleanup.
  - Server-authoritative points and monetization engine supporting Google AdMob rewarded ads with server-side verification (SSV), 0-point free asset creation, and task-based point debiting.
  - Contextual notification scheduling, background WorkManager synchronization, exact alarm support, and periodic maintenance reminders.
  - Local backup and restore subsystem with ZIP archive integrity validation, SHA-256 manifest checks, and rollback safety.
  - Complete dual-language internationalization and RTL layout support for English and Arabic.
  - Privacy-preserving Sentry observability with strict PII scrubbing and symbolicated crash reporting.
  - First-class Empty Trash bulk purge capability with transactional cascading deletion, photo file unlinking, and UI confirmation.
  - Hardened task recurrence calculation preventing backward next_due_date regression on early completions.
  - Dual-state completion undo handling for both un-synced outbox mutations and synchronized cloud records.
  - Enhanced account deletion data cleaner purging all reconciliation requests and FTS virtual tables.
