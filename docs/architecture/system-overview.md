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
  -> Local notifications, exact alarms, foreground tasks, Workmanager
  -> Google Sign-In
  -> Google Mobile Ads
  -> Sentry

Release and verification tooling
  -> exact backend, Edge Function, database, web, and static contracts
  -> signed AAB plus evidence and verification
  -> signed APK, evidence, and Sentry release
  -> VersionDeck independent verification and static deployment
```

## Flutter application

The Flutter presentation and application layer is structured modularly by domain. `lib/main.dart` acts as the clean application root, declaring imports, feature parts, `main()`, process runner, and `OwntendApp`. Feature-specific UI screens, dialogs, and widgets reside under `lib/src/features/` (startup, navigation, dashboard, rooms, assets, maintenance, search, trash, notifications, statistics, settings, backup, and monetization), shared widgets and enum formatters in `lib/src/ui/`, domain providers in `lib/src/core/providers/app_providers.dart`, and domain data repositories in `lib/src/core/data/`.

Riverpod is the dependency and state-management mechanism. GoRouter is the navigation mechanism. Modules maintain strict boundaries with decoupled services, repositories, and state controllers.

`OwntendProcessSplash` is the first child passed to every `runApp` branch. It remains mounted while deferred initialization, startup-theme loading, the application, or a startup-failure surface changes beneath it, so those branches cannot reset the fixed splash lifetime or expose a blank Flutter frame. A static startup surface remains underneath if initialization outlives the overlay. The splash selects English or Arabic from the device locale, exposes one localized semantic label, supports compact and scaled layouts, and stops repeating animation when the platform requests reduced motion. These are repository and widget-test contracts; launch behavior on a physical release device remains separate evidence.

## Local persistence

Drift manages the SQLite database. The schema stores product entities and operational state including synchronization outbox entries, pull cursors, remote shadows, hydration/runtime state, account binding, reminder snapshots, and cleanup work.

The local database is the immediate user-facing working set. Cloud synchronization does not make every UI read depend on network availability.

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
3. runtime service truth, such as whether notification delivery is enabled and exact alarms can actually be scheduled; and
4. the derived effective capability: active, degraded, blocked, disabled by the user, unavailable, or not configured.

A manually chosen weather area is active without changing the real OS location state. Device-derived weather requires current approximate-location access and an available location service. Exact alarm access is an optional timing enhancement: when it is not selected or available, reminder scheduling uses the inexact allow-while-idle mode rather than disabling reminders. The canonical permission coordinator owns checks, requests, prompt history, and targeted settings actions. Physical-device behavior across Android variants remains required evidence.

## Transient feedback

Application SnackBars are coordinated through one protected queue. An active Undo opportunity cannot be replaced by passive feedback or an error; only matching non-null batch keys aggregate; Trash and maintenance completion use separate keys; batch Undo runs newest first; finalization runs oldest first; and callback failure cannot strand the queue. Accessible-navigation mode preserves actionable Undo until the user acts or dismisses it. See [Transient feedback and Undo](../development/transient-feedback.md).

## Notifications and background execution

The Android host declares permissions and components required for internet access, optional approximate location, notifications, optional exact alarms, boot handling, wake locks, vibration, foreground data synchronization, and local notification receivers. Notification plugin initialization is separate from account-scoped periodic registration: after authenticated readiness, `NotificationBootstrap` verifies that the active Supabase session matches the bound local account before it register/updates the unique daily WorkManager refresh. The worker independently reloads and revalidates the same account boundary before reading or scheduling anything.

Durable notification-reconciliation requests live in Drift and are consumed after authenticated notification bootstrap, after relevant foreground maintenance reconciliation, and by the daily WorkManager path. A consumer coalesces pending requests into one schedule refresh and removes only the exact request versions covered by a successful refresh; failures retain the request with bounded retry metadata, so restart or a later trigger can replay it safely. Background work restores or reconciles reminders and synchronization without introducing fine or background location.

## Backup and restore

Owntend produces versioned ZIP archives with a manifest and hashes. Restore treats archives as untrusted input, validates compatibility and extraction bounds, creates a safety backup, stages media, applies data, and rolls back on failure.

## Observability

Sentry is optional by configuration. Events are scrubbed and should contain only technical diagnostics. Production workflows associate releases with source and artifacts without uploading user data.

## Build and distribution

The project builds:

1. signed Google Play bundles with release rules and non-debuggable enforcement;
2. signed APK artifacts with SHA-256 generation; and
3. VersionDeck static assets for release verification and public downloads.
