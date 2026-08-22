# Owntend Privacy and Data Use

_Last reviewed: August 22, 2026_

This document describes the data-handling design represented by the current Owntend source code. It is technical project documentation, not a substitute for jurisdiction-specific legal review or store disclosures.

## Data Owntend manages

Depending on the features used, Owntend can process:

- Home organization data such as areas, rooms, assets, tags, notes, photos, and specialized device, pet, plant, or safety details.
- Maintenance plans, recurrence settings, due dates, completion history, attachments, warranty information, reminders, and notification state.
- Preferences, onboarding state, statistics, streaks, health or readiness summaries, and application settings.
- Account identifiers and session material required for Google sign-in and Supabase authentication.
- Synchronization metadata such as operation identifiers, revisions, cursors, retry state, shadows, hydration state, and cleanup state.
- Backup archives created or selected by the user.
- A manually selected weather area, or approximate location when the user explicitly grants coarse-location permission and chooses the current-location option. Manual configuration does not mean Android location permission was granted. Owntend stores weather coordinates rounded to two decimal places and does not request fine or background location in the current Android manifest.
- Advertising consent state, ad events, reward claims, point balances, charged-creation records, and fraud-prevention metadata used by the monetization system.
- Limited diagnostic and release metadata when Sentry is enabled.
- Technical release, architecture, anonymous per-app client, patch check/install, and updater state used by Shorebird code push.
- Account-deletion recovery metadata while a destructive request is unresolved: a high-entropy recovery key and expected account ID in device secure storage or browser `sessionStorage`, plus only hashed capability/binding values and bounded operation state in the private backend table.

## Where data is stored

Owntend is offline-first. Application data is stored in a local SQLite database managed through Drift. Media and backup files may also be stored in application-controlled local storage.

When a user signs in and synchronization is enabled, supported data is stored in the project's Supabase Postgres database and private Supabase Storage. Local synchronization metadata is retained to support offline work, retries, conflict handling, and account isolation.

Sensitive session material is stored through platform secure storage where supported. A pending in-app deletion operation stores its recovery key and expected account ID there until authoritative completion or safe cancellation. The browser keeps an unresolved deletion recovery record only in `sessionStorage`; access and refresh tokens are not persistently stored by the deletion page. All restore media sidecars (`.restore-*`, `.previous-*`) are durably tracked in `SidecarRegistryStore` in secure storage and completely purged during account deletion or startup orphan sweeping. Outbox mutation generations (`generation` integer column in local SQLite `offline_mutation_queue`) and Change Feed pull cursors (`server_change_feed` in `sync_cursors`) are purely technical monotonic identifiers used to enforce conditional Compare-And-Swap (CAS) safety and ordered feed synchronization without containing user domain data or private attributes. Account deletion fails and blocks backend acknowledgement if any local media copy or sidecar cannot be deleted.

## Third-party services

### Supabase

Supabase provides authentication, Postgres storage, private media Storage, Realtime invalidation, RPCs, Edge Functions, contract-1 server change-feed ordering (`server_change_feed`, `fetch_user_change_feed`, `get_user_change_feed_watermark`), service-only parity validation, media staging and cleanup ledgers (`media_staging_objects`, `media_cleanup_queue`, `prepare_asset_photo_upload`, `finalize_asset_photo_upload`), and the transactional primary-photo RPC (`set_primary_asset_photo`). Client media uploads generate local SHA-256 digests, create a durable owner-scoped staging operation before upload, use only the server-returned path, and then finalize. Realtime events serve strictly as non-authoritative invalidation hints. Row Level Security and ownership checks isolate user data, media staging objects, cleanup records, and change log entries (`user_id = auth.uid()`). Direct client modifications to feed entries are prohibited; changes are logged automatically through database triggers. Feed parity is protected service/CI evidence rather than a client healing or capability-discovery API.

### Google Sign-In

Production authentication uses Google sign-in. Google and Supabase process identity and session information needed to authenticate the user. The local loopback integration environment permits disposable email identities only to test two-user isolation; Flutter exposes no email-and-password production flow.

Ordinary Owntend sign-out ends the application session without revoking the user's Google authorization grant. In-app account deletion uses the separate disconnect path after confirmed cloud deletion. The public browser deletion flow clears its Supabase browser session on completion, but it cannot revoke Google authorization automatically; users may separately revoke Owntend from their Google Account connections.

### Google Mobile Ads

Owntend includes Google Mobile Ads. Ads are requested only when the application is foreground-eligible and the current consent and configuration gates permit the specific format. Depending on consent, configuration, region, and ad availability, Google may process device, advertising, consent, fraud-prevention, and interaction data. Rewarded-ad claims are verified server-side before points are credited. Core application data must not be inserted into ad request or reward identifiers.

Charged creation operations (asset and task creation) use server-side point debiting with canonical SHA-256 payload hashes and exact advisory locking. Status lookups via `get_charged_operation_status` are restricted strictly to the authenticated owner; cross-user queries return `not_found` without disclosing entity details or operation existence. Client journal entries store request payloads in secure storage prior to RPC execution, and automatically purge user-entered payload content (`purgeTerminalPayloads`) once operations reach terminal states (`reconciled` or `permanentRejected`).

### Sentry

Sentry may receive technical error and performance information when enabled. Owntend's intended observability policy excludes user content and direct identifiers, disables screenshots, session replay, view hierarchy, and raw HTTP payload capture, and applies event scrubbing. Supabase Edge Functions may optionally report request-scoped server failures to Sentry when their environment provides `SENTRY_DSN`, but they must exclude JWTs, authorization headers, recovery keys, claim IDs, user IDs, and raw callback payloads. See `docs/SENTRY_OPERATIONS.md`.

### Shorebird

Shorebird provides over-the-air delivery of compiled Dart patches. A Shorebird-enabled release checks for updates at startup in a background thread, stores updater state and downloaded patch binaries in the app's local cache, and normally applies a downloaded patch on the next launch. Requests include the public app ID, release version, patch number, track/channel, platform, CPU architecture, and an anonymous aggregated per-app client identifier. Successful/failed patch events support install metrics. Network infrastructure may process IP addresses in security/operational logs. Owntend does not send names, email addresses, household content, location, media, authentication tokens, advertising identifiers, or source code to Shorebird through this integration.

Release and patch tooling uploads compiled application/release artifacts and patch binaries to Shorebird's service; it does not upload source code. Owntend uses separate dev/staging/prod Shorebird apps, strict signature verification, and non-exportable KMS signing. App IDs are public identifiers, while API tokens and signing material are protected credentials. See [`docs/operations/shorebird-code-push.md`](docs/operations/shorebird-code-push.md). Store disclosures, Shorebird's current privacy policy/DPA, hosting/subprocessors, retention, and regional requirements still require operator/legal review before production launch.

### Location and network services

Owntend sends a manually selected or privacy-reduced approximate weather coordinate to Open-Meteo for forecasts. Manual place searches send the entered search text to Open-Meteo's geocoding service. Device location is obtained only after the user chooses that option and Android location permission and services allow it; Owntend does not continuously track location in the background. Changes that introduce a new external service require a privacy review and an update to this document.

## Notifications and background work

Owntend schedules local maintenance notifications and may use exact alarms, boot restoration, wake locks, foreground data-sync service capability, and Workmanager. Notification preferences, Android notification permission, channel state, and effective reminder capability are separate. Exact timing is optional; when exact-alarm access is unavailable, supported reminders use degraded inexact scheduling rather than treating the preference as permission. The local database can also retain bounded notification-reconciliation scope, reason, attempt, and retry/error metadata until the scheduler successfully refreshes and acknowledges the request. Notification content can reveal maintenance information on the device lock screen; users should configure operating-system notification privacy according to their needs.

Ordinary sign-out invokes the central account-safety barrier to quiesce synchronization/realtime work and cancel account-scoped WorkManager jobs before provider sign-out. Ordinary sign-out is non-destructive: it does not clear local domain data, notification inbox rows, reminder snapshots, or the local account binding merely because the session ends. Destructive local cleanup belongs to the separate account-deletion/recovery path after its identity and cloud-receipt requirements are satisfied. WorkManager callbacks fail closed unless a session is active, the bound account exactly matches it, and synchronization is enabled before any domain read, streak mutation, inbox write, or weather request.

The current Android manifest does not request fine or background location.

## Backup and restore

User-created backups can contain substantial Owntend data and media. Backups should be treated as sensitive files. The application validates archive paths, sizes, hashes, and schema compatibility, and uses safety-backup and rollback procedures during restore. Users control where exported backups are stored or shared.

Android platform backup is disabled for the application in the current manifest; Owntend's own backup feature is separate.

## Retention and deletion

Local data remains until it is deleted through application behavior, cleared by the user or operating system, removed during destructive account cleanup, or replaced through restore. Ordinary sign-out does not itself delete the local working set.

For in-app account deletion, Owntend requires recent same-identity Google reauthentication, first attempting lightweight verification of the already signed-in account and showing Google's chooser only when that is unavailable. It then suspends synchronization, creates a secure recovery operation, invokes the protected `delete-account` Edge Function, and verifies the deletion result. If the destructive response is ambiguous or the app restarts, it queries `account-deletion-status` with the same key and expected account before completing device-local database, media, session, notification, cache, and recovery-record cleanup. Pending or temporary status preserves the synchronization barrier and record; a definitive not-found result clears the stale record without claiming deletion.

The external web resource performs real Google OAuth through Supabase with PKCE, verifies the authenticated user, requires explicit confirmation, and calls the same protected Edge Function. It generates a 32-byte recovery key with Web Crypto, keeps the unresolved key and expected user ID in `sessionStorage`, and can query the status function after a reload or ambiguous response without persisting a bearer token. It accepts success only from a completed receipt for that same user. The backend removes the account's synchronized Postgres data, private Supabase Storage objects, cleanup job, and Auth user.

The external web resource is intentionally unavailable while pre-release
production containment is active. The
in-app deletion flow and its data handling remain available and unchanged.

The private deletion-recovery table stores a SHA-256 request hash, a SHA-256 subject binding, bounded stage/error metadata, and the active user UUID only until completion; it does not store the raw recovery key. Completion clears the active UUID. The backend distinguishes `prepared`, `storage_cleanup`, `storage_complete`, `auth_delete_started`, `completed` (remote deletion done, awaiting client acknowledgement), and `acknowledged` (client has confirmed local cleanup is terminal) stages. Non-completion rows expire after seven days by default. A completed but unacknowledged row has a strict 90-day maximum so recovery authority remains available for a bounded period after terminal remote deletion. A capability-bound acknowledgement shortens that window to seven days. The hourly pruning function deletes every expired stage, including an unacknowledged completed row after its 90-day maximum. Hosted backup, replica, log, or legal-hold retention remains an operator/service-policy concern rather than repository proof.

The browser cannot inspect or erase Owntend data, media, notifications, secure storage, or caches remaining on an installed device; users must clear or uninstall the app on each device. It also cannot erase copies held in user-exported backups or independently retained by service providers under their own disclosed obligations.

Backup files previously exported outside the application are not automatically deleted by account deletion. Multiphase restore operations write technical state entries (archive/safety hash, media token, phase enum) to secure local storage (`RestoreJournalStore`) to guarantee deterministic recovery after process termination; journal entries do not store user-entered content and are cleared upon completion or rollback.

## Security controls

The project uses private Storage, Row Level Security, authenticated RPCs, local secure storage, operation idempotency, account binding, archive validation, release signing, APK verification, and protected CI environments. No control can guarantee absolute security.

## Children's privacy

The project does not intentionally define a child-directed service. Product distribution and legal disclosures should be reviewed before offering the application to children or collecting age-related data.

## Changes to data use

Any change that adds a permission, SDK, telemetry field, external service, persistent field, AI processing path, advertising behavior, location use, or retention/deletion behavior must update this document and the relevant architecture or operations documentation before release.
