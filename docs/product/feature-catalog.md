# Product Feature Catalog

## Product purpose

Owntend helps users inventory household assets and keep recurring or one-time maintenance work visible, scheduled, and recoverable across offline and signed-in use.

The first Flutter frame is owned by one process-lifetime splash above deferred startup, theme loading, application, and failure branches. A non-blank startup surface remains available underneath. English/Arabic semantics, scaled compact layout, and reduced-motion behavior are part of the widget contract; a physical release launch still requires device validation.

## Navigation surfaces

The current application exposes dashboard, assets, maintenance, calendar, search, trash, statistics, settings, account, backup, notifications, capability setup at `/permissions/setup`, and additional utility surfaces through GoRouter. `/profile` redirects to `/account`. The route definitions in `lib/src/features/navigation/app_router.dart`, composed by `navigation_presentation.dart`, are authoritative.

## Organization model

- Areas and rooms organize the home.
- Item Type is the sole item classification: device, pet, plant, safety, or general.
- Assets represent maintained things and can carry tags, photos, notes, warranty information, and type-specific detail.
- Specialized detail models support devices, pets, plants, and safety-related assets.
- Trash and cleanup flows protect against accidental permanent deletion. Moving a task, asset, room, or area to Trash offers restoration through the protected Undo coordinator; permanent deletion remains separately confirmed.

Category is not a second item classifier, search entity, persistence field, backup table, or synchronization/RPC alias. Activity words such as cleaning may still describe maintenance work, but they do not create an Item Type.

## Maintenance

- One-time and recurring maintenance plans.
- Due, overdue, completed, and historical views.
- Completion history and attachments.
- Calendar integration and date-based filtering.
- Recommendations, timelines, readiness or health summaries, streaks, and warranty alerts.
- Local reminders that can be restored after reboot or application update.
- Task metadata without task-to-task dependency links; that retired feature is
  removed from editors, details, drafts, local/cloud schemas, and sync payloads.

Maintenance completion is a synchronized, idempotent operation. UI changes must not bypass repository and synchronization semantics.

Transient feedback has one protected queue. Passive messages and errors wait behind an active Undo opportunity, compatible operations batch only under an exact non-null key, Trash never batches with maintenance completion, and accessible-navigation mode keeps actionable Undo available until action or dismissal. Floating feedback follows the active Scaffold's real navigation, footer, keyboard, and floating-action obstruction instead of route-specific offsets. See [`transient-feedback.md`](../development/transient-feedback.md).

## Search and insights

- Search across supported home and maintenance data.
- Statistics and chart-based summaries.
- Dashboard summaries and actionable status.
- Health, readiness, and warranty indicators where data is available.

## Accounts and synchronization

- Google-based production sign-in.
- Offline-first local operation.
- Authenticated Supabase synchronization.
- Initial hydration, incremental pull, queued local changes, retry, realtime invalidation, and conflict recovery.
- Account deletion with recent reauthentication and coordinated local/remote cleanup.
- A public VersionDeck deletion page that authenticates with Google OAuth PKCE through Supabase, requires explicit confirmation, and invokes the protected deletion function with the signed-in bearer token.

The VersionDeck page is intentionally unpublished during active pre-release
production containment, so the public browser deletion route is currently
unavailable. The in-app authenticated deletion flow is unchanged. See the
[production containment record](../operations/production-containment.md).

Signed-out or offline operation must remain explicit; the application should not imply cloud protection when synchronization is unavailable.

The public page is not an anonymous deletion endpoint. It accepts success only when the protected function returns a deletion receipt for the authenticated user. Repository coverage does not prove the page, OAuth redirect configuration, or Edge Function is deployed to production.

## Notifications and background work

- Local notification permission education.
- A capability-setup surface that distinguishes application preferences from Android permission/special-access state, service availability, scheduler truth, and effective feature state.
- Manual weather-area selection without requesting device location; the real OS location state remains unchanged.
- Optional exact-alarm scheduling when exact timing is selected and available, with inexact allow-while-idle scheduling as the reminder fallback.
- Boot and application-update restoration.
- Foreground data-sync capability and Workmanager for bounded background work.
- Time-zone-aware reminders.

The first-dashboard education flow considers weather-area and notification setup; it does not pressure users for exact-alarm access. Exact timing is surfaced from settings or reminder/task scheduling context. Denied or unavailable access must leave useful manual-weather, in-app inbox, and inexact-reminder paths where their prerequisites are met.

## Backup and restore

- Production-v1 authenticated `.owntend-backup` containers (Argon2id + AES-256-GCM; no plaintext reader) with one format contract.
- Manifest and cryptographic hash validation.
- Media inclusion and staging.
- Retention of automatic backups.
- Pre-restore safety backup.
- Compatibility checks and rollback on failure.

Backups exported outside the app are user-controlled sensitive files. The pre-launch application accepts only the canonical format-1/schema-1 contract and contains no obsolete Category table or old-format migration path.

## Monetization

- Consent-aware Google Mobile Ads integration.
- Native, interstitial, rewarded, and rewarded-interstitial experiences where configured.
- Fail-closed runtime gates for supported platform, resumed lifecycle, refreshed consent, UMP permission, global enablement, and per-format switches.
- Bounded retry/dormancy, 55-minute ad freshness, exact-once native ownership, and one shared fullscreen presentation gate.
- Server-authoritative points wallet.
- Task-only point debiting (1 point per new standalone maintenance task; asset/item creation is completely free).
- Server-side verification and replay-resistant reward claims.
- Explicit unfinished drafts when charged creation cannot be completed offline.
- A collapsible native-ad placement on every routed application content screen,
  including task detail, Inbox, permission setup, and all Tools destinations.

Ads and points must not become the authority for core domain data.

Repository tests cover the application eligibility, ownership, native schema, and reward-security contracts. AdMob/UMP console state, provider ownership, hosted SSV settlement, merged release dependencies, and physical-device presentation remain external release evidence. See [Monetization architecture](../architecture/monetization.md).

## Localization and accessibility

- English and Arabic localization.
- Right-to-left layout for Arabic.
- Locale-aware dates, numbers, plurals, and placeholders.
- Accessible labels, scalable text, focus behavior, protected actionable feedback, and reduced-motion behavior for startup and navigation.

## Observability

Sentry provides technical error and performance diagnostics when enabled. The intended policy excludes user content and direct identifiers and disables screenshots, session replay, view hierarchy, and raw HTTP payload capture.

Shorebird-enabled Android releases can receive signed Dart-only patches after a new base release is registered. Patches cannot change native code, packaged assets, dependencies, or toolchain inputs; production patches are published to staging, verified on a device, and promoted as an exact numbered patch through a protected workflow. The updater checks in the background at startup and normally applies a downloaded patch on the next launch.

## Distribution

Production distribution is currently paused under the pre-release containment policy.

Release validation covers Edge Functions, browser deletion/static contracts, and local-stack database security. One pinned Shorebird rail produces the canonical Play AAB; a protected job derives VersionDeck's universal and ABI APKs from that exact AAB without recompiling Flutter. Play upload, Sentry mutation, GitHub Release, and VersionDeck verified publication remain separately authorized, independently verified operations.

## Product change checklist

A new feature is complete only when its local data, cloud data, synchronization, localization, permissions, privacy, backup, deletion, tests, documentation, and release implications have been reviewed.

### Item-Type-derived task classification

Tasks are always linked to items and derive their classification/icon/statistics bucket from the linked item's Item Type. Health Group is not editable or stored on tasks. Cleaning remains an activity/task concept and inherits the linked item's Item Type for scoring (plant cleaning is Plant, device cleaning is Device, safety-item cleaning is Safety, and general-household cleaning is General). General currently remains outside weighted health-score normalization to preserve the previous unweighted `other` behavior.
