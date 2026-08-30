# System Overview

## Context

Owntend is an Android-first Flutter application. Its central architectural requirement is that users can continue organizing assets and recording maintenance while offline, then synchronize safely after authentication and connectivity return.

## Major components

```text
OwntendProcessSplash (first runApp child; stable process owner)
  -> deferred startup, theme loading, failure surface, and Flutter UI
  -> Riverpod providers and application services
  -> Domain repositories
  -> Drift/SQLite local database
  -> Sync coordinator and media pipeline
  -> Supabase Auth, Postgres, Storage, Realtime, RPCs, Edge Functions

Flutter services
  -> Local notifications, approximate alarms, foreground tasks, WorkManager
  -> Google Sign-In
  -> Google Mobile Ads
  -> Sentry

Release and verification tooling
  -> exact backend, Edge Function, database, web, and static contracts
  -> signed AAB plus evidence and verification
  -> canonical Shorebird AAB, exact-AAB APK evidence, and retained symbols
  -> VersionDeck independent verification and static deployment
```

## Flutter application

The Flutter presentation and application layer is structured modularly by domain. `lib/main.dart` is a bootstrap-only entry point. `lib/src/app/owntend_app.dart` owns process startup and the application shell, while `lib/src/app/app_dependencies.dart` is the single exported Riverpod composition surface. Feature presentation libraries live under `lib/src/features/` (startup, navigation, dashboard, rooms, assets, maintenance, search, trash, notifications, statistics, settings, backup, and monetization) and import their dependencies explicitly instead of sharing application-root private scope. Focused shared presentation APIs live under `lib/src/ui/`; domain providers live in `lib/src/core/providers/app_providers.dart`; domain data repositories live in `lib/src/core/data/`. Exactly one `databaseProvider`, in `lib/src/core/database/app_database.dart`, owns the process database supplied during deferred startup.

Riverpod is the dependency and state-management mechanism. GoRouter is the navigation mechanism. Modules maintain strict boundaries with decoupled services, repositories, and state controllers.

`OwntendProcessSplash` is the first child passed to every `runApp` branch. It remains mounted while deferred initialization, startup-theme loading, the application, or a startup-failure surface changes beneath it, so those branches cannot reset the fixed splash lifetime or expose a blank Flutter frame. A static startup surface remains underneath if initialization outlives the overlay. The splash selects English or Arabic from the device locale, exposes one localized semantic label, supports compact and scaled layouts, and stops repeating animation when the platform requests reduced motion. These are repository and widget-test contracts; launch behavior on a physical release device remains separate evidence.

Deferred startup treats Supabase client initialization as a required cloud boundary. A failure is logged through the privacy-scrubbed logger and presents the localized cloud-unavailable surface with an explicit retry; the application is not published ready with a null client. Authentication stream failures likewise remain Riverpod `AsyncError` states while consumers may retain the repository's cached session, so transport failure cannot masquerade as sign-out.

## Local persistence

Drift manages the SQLite database. The schema stores product entities and operational state including synchronization outbox entries, pull cursors, remote shadows, hydration/runtime state, account binding, reminder snapshots, and cleanup work.

The FTS5 search index is a derived local materialized view. SQLite invalidation triggers advance a durable source generation whenever any searchable authoritative table changes, while the search repository records the generation represented by the last successful full index rebuild. Search queries validate those generations and rebuild transactionally when needed, so route lifetime, sync-origin writes, restore, or process restart cannot make a stale index an accepted source of truth. The search screen separately binds each asynchronous request to the current input generation and ignores late results or failures from superseded queries.

The local database is the immediate user-facing working set. Cloud synchronization does not make every UI read depend on network availability.

## Runtime UI authority

Ordinary local-first domain screens render from Drift-backed Riverpod providers. A local mutation commits through its repository and Drift transaction, Drift watchers emit, Riverpod updates, and already-mounted widgets render the new value without route remounts, manual refreshes, or screen-local collection caches. Multi-table repository watches may coalesce closely related Drift invalidations long enough to observe one coherent post-transaction aggregate; presentation screens must not stack a second debounce for the same domain state.

The startup `InitialHomeSnapshot` is a first-ready-frame seed, not an ongoing competing source of truth. Home uses a live provider value whenever that concern has one and falls back to the startup seed only while the live concern has never produced usable data. Non-domain startup concerns such as profile, weather, backup state, notification count, and avatar/session state retain their own live-first fallbacks where appropriate.

For populated streams, ordinary revalidation keeps the last usable provider value visible while replacement data is loading or converging. Home labels its retained startup snapshot as saved data when a live domain refresh fails. Without usable data, Home, room detail, item detail, and calendar distinguish loading, retryable error, authoritative not-found, and true empty states instead of coercing `AsyncValue` failures to empty collections. Stable domain IDs remain widget identity for mutable lists.

`localNowProvider` is the injectable local wall-time source and `localClockProvider` is the shared presentation clock. It emits at the next local minute boundary and immediately on application resume, allowing date bucketing, calendar selection, room health, dashboard readiness, and time-of-day theme state to react to midnight or time-zone changes without a database event.

## Cloud backend

Supabase provides:

- Google-backed user sessions through Supabase Auth.
- Postgres tables, indexes, RLS policies, and RPCs.
- Private `user-media` Storage.
- Realtime invalidation signals.
- Edge Functions for protected workflows such as account deletion, deletion-status recovery, and AdMob server-side verification.

The backend is authoritative for ownership, point balances, charged operations, verified rewards, and globally coordinated revisions.

## Synchronization

Local mutations become durable outbox work. The coordinator binds work to an authenticated account, pushes idempotent operations, pulls cloud changes using cursors and revisions, records shadows, handles retry and conflicts, and uses realtime events as invalidation rather than as complete authoritative payloads.

Sync Health is the user-resolution boundary for work that automatic synchronization cannot safely finish. The store returns payload-free summaries; failed-visible work can be requeued or explicitly dismissed, and unresolved conflicts can be resolved only for their bound account by keeping the newest preserved local intent or the canonical cloud state.

The synchronization implementation is divided behind stable public facades. `LocalSyncStore` delegates account/hydration, outbox, remote application, composite mutation, and media-cleanup responsibilities to focused store modules. `SyncCoordinator` retains the public lifecycle and account-deletion surface while focused modules own run/pull/snapshot, push/conflict, post-ready media, and runtime/connectivity/realtime behavior. These are one store and one state machine, not parallel protocols or compatibility paths.

Foreground resume and network restoration are pull-capable convergence points even when `lastSyncedAt` is recent. After ensuring Realtime, the coordinator schedules one broad convergence pass that also pushes pending local work; an already-running broad pull satisfies the request, while targeted or push-only work is followed by the required broad pull. Initial hydration and retention gaps use an authoritative owner-scoped snapshot. Every subsequent incremental pass uses the always-on contract-1 server feed; contract mismatch or incomplete page application fails without advancing the durable checkpoint.

See `sync-protocol.md`.

## Authentication and deletion

Production authentication is Google-based. Session state is stored through Supabase and secure platform storage. Account deletion is a coordinated workflow across Flutter, synchronization, Storage, Postgres, and Auth and requires recent same-identity reauthentication. Each destructive operation uses one 32-byte recovery key, retained only while unresolved, so an ambiguous response can be reconciled without weakening identity or receipt validation.

The public VersionDeck deletion page is an entry point, not an unauthenticated delete API. It performs Google OAuth with PKCE through Supabase, keeps access tokens in memory, requires explicit confirmation, calls the protected `delete-account` Edge Function with the authenticated bearer token and recovery key, and accepts success only from a matching deletion receipt. After reload or an ambiguous response, it can query the capability- and subject-bound `account-deletion-status` function with the same key while keeping bearer tokens out of persistent browser storage. Repository tests encode the browser and function contracts; they do not prove that the reviewed site, OAuth redirect, or function revision is deployed. See [Authentication and account deletion](auth-and-account-deletion.md).

## Monetization

Google Mobile Ads runs in Flutter with consent-aware presentation. Points and charged creation are implemented as backend-authoritative operations. Reward callbacks become pending claims and are credited only after server verification and replay protection.

Ad eligibility fails closed across supported platform, resumed lifecycle, launch-fresh consent state, UMP permission, global remote enablement, and per-format switches. Eligibility generations invalidate stale loads and retries; bounded retry classes can become dormant; cached ads expire at 55 minutes; leases own native ads exactly once; and one fullscreen gate serializes interstitial and rewarded presentation. These contracts and the Android native-ad schema have local tests. They do not establish AdMob ownership, UMP/SSV console configuration, resolved release-SDK behavior, hosted settlement, or physical rendering. See [Monetization architecture](monetization.md) and the [Data safety evidence worksheet](../operations/google-play-data-safety-evidence.md).

## Permission and capability truth

Permission education does not treat an application preference as proof that a feature works. Its snapshots combine:

1. user intent, such as reminders enabled or exact timing preferred;
2. Android permission, special-access, and location-service state;
3. runtime service truth, such as whether notification delivery is enabled and alarm scheduling is available; and
4. the derived effective capability: active, degraded, blocked, disabled by the user, unavailable, or not configured.

A manually chosen weather area is active without changing the real OS location state. Device-derived weather requires current approximate-location access and an available location service. Reminder timing is deliberately approximate: scheduling always uses the inexact allow-while-idle mode because the binary does not request restricted exact-alarm access (NOTIF-001). The canonical permission coordinator owns checks, requests, prompt history, and targeted settings actions. Physical-device behavior across Android variants remains required evidence.

## Transient feedback

Application SnackBars are coordinated through one protected queue. An active Undo opportunity cannot be replaced by passive feedback or an error; only matching non-null batch keys aggregate; Trash and maintenance completion use separate keys; batch Undo runs newest first; finalization runs oldest first; and callback failure cannot strand the queue. Accessible-navigation mode preserves actionable Undo until the user acts or dismisses it. See [Transient feedback and Undo](../development/transient-feedback.md).

## Notifications and background execution

The Android host declares permissions and components required for internet access, optional approximate location, notifications, boot handling, wake locks, vibration, foreground data synchronization, and local notification receivers. Notification plugin initialization is separate from account-scoped periodic registration: after authenticated readiness, `NotificationBootstrap` verifies that the active Supabase session matches the bound local account before it registers or updates the unique daily WorkManager refresh. The worker independently reloads and revalidates the same account boundary before reading or scheduling anything.

Durable notification-reconciliation requests live in Drift and are consumed after authenticated notification bootstrap, after relevant foreground maintenance reconciliation, and by the daily WorkManager path. A consumer coalesces pending requests into one schedule refresh and removes only the exact request versions covered by a successful refresh; failures retain the request with bounded retry metadata, so restart or a later trigger can replay it safely. Background work restores or reconciles reminders and synchronization without introducing fine or background location.

## Backup and restore

Owntend produces versioned, authenticated `.owntend-backup` containers — an `OWNTDBK1` header with Argon2id key derivation and AES-256-GCM framing; there is no plaintext ZIP reader. Restore treats every imported container as untrusted input, validates compatibility and extraction bounds, creates a safety backup, stages media, applies data, and rolls back on failure. Derived search state is not imported as user authority; restored searchable rows invalidate the local FTS generation and are rebuilt before search results are returned.

## Media import

Local photo import validates the file and source-byte budget before decoding on a worker isolate, rejects undecodable or excessive-pixel content, bakes orientation, scales to the configured maximum dimension, and searches a bounded JPEG-quality ladder for an output within the cloud 10 MiB contract. The repository writes that normalized output first and inserts photo metadata only after the filesystem succeeds; database failure removes the just-written file.

## Observability

Sentry is optional by configuration. Events are scrubbed and should contain only technical diagnostics; Shorebird patch attribution is bounded to `base` or an integer while release/dist remain unchanged. Production workflows associate releases with source and artifacts without uploading user data or mutating Sentry.

Shorebird is the Android release/code-push boundary. Each existing flavor maps to a distinct app ID. The updater checks Shorebird for a signed Dart patch at startup and applies it on a subsequent launch. Repository and Shorebird dry-run gates reject native, asset, dependency, toolchain, and unknown changes. Google Cloud KMS signs patches without exporting a private key. Production stable promotion is a separate exact-patch operation after staging device evidence.

## Build and distribution

The project builds:

1. signed Google Play bundles with release rules and non-debuggable enforcement;
2. signed APK artifacts with SHA-256 generation; and
3. VersionDeck static assets for release verification and public downloads.


### Server-authoritative wallet live state

Point balances are a separate server-authoritative live-state concern rather
than local-first domain data. One auth-scoped Riverpod owner adopts balances
returned by successful charged RPCs immediately, then converges through the
owner-filtered `point_wallets` Realtime stream and canonical refetches on
mutation, resume, and reconnect. Server `updated_at` orders canonical
snapshots, and auth changes clear the previous account before loading the next.
