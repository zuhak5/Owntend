# Changelog

Owntend uses Git history as the authoritative record of shipped changes. This file records notable project-level changes that affect users, operators, contributors, architecture, security, or compatibility.

The current application version is defined only in `pubspec.yaml`. Released versions are recorded below after their version and build numbers have been finalized.

## Unreleased

- Replaced the duplicate Android APK/AAB build rails with one exact-commit-pinned Shorebird release rail, strict fail-closed Dart-only patch validation, staging-to-stable exact-patch promotion, non-exportable Google Cloud KMS signing, runtime Sentry patch attribution, retained engine symbols, and VersionDeck APK derivation from the canonical AAB without a second Flutter compile. Production publication remains protected and disabled until operator account/app IDs, tokens, environments, KMS, device evidence, and explicit authorization are complete.
- Rebuilt the never-published production-v1 baseline around one app/build, Drift/backup schema 1, one canonical Supabase migration, one contract-1 change feed plus authoritative snapshots, prepare-before-upload media staging, bounded deletion recovery, and VersionDeck manifest/cache contract 1.
- Extracted application bootstrap and dependency composition from `main.dart`, split shared UI and monetization buckets into focused modules, removed quarantine and other pre-release compatibility paths, and renamed remediation-era tests around the behavior they protect.
- Added real loopback Supabase integration coverage for two-user RLS isolation, two local app databases converging through outbox/snapshot/feed, and the private Storage prepare/upload/finalize saga; expanded CI with generated-source drift, documentation-link, secret, dependency-audit, Deno, and application/backend gates.
- Updated Flutter, WorkManager, foreground-task, archive, SQLite, Supabase CLI, and Java policy baselines and regenerated their locks and derived sources.
- Made local-first runtime screens update live from Drift/Riverpod without duplicate Home/Rooms render delays, kept startup Home snapshots seed-only once live domain values exist, and made resume/reconnect convergence pull-capable even after a recent sync so missed Realtime changes repair without navigation or manual refresh.
- Fixed points counter synchronization with one auth-scoped, server-authoritative wallet owner that immediately adopts charged RPC/recovery balances, converges external/SSV changes through Realtime plus canonical resume/reconnect refetches, and prevents stale snapshots or cross-account balances from regressing the UI.

### Fixed

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
