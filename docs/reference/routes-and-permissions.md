# Routes and Android Permissions

### Network security and navigation behavior (WP-011/WP-012)

The merged manifest pins `android:networkSecurityConfig` to
`res/xml/network_security_config.xml`, which denies cleartext for every
process explicitly. Notification deep links are validated by exact top-level
segment (`/assets-x` style look-alikes are rejected); a destination tapped
before startup finishes is captured in `PendingNotificationRoute` and honored
by startup finalization instead of forcing home. The app accepts
`portraitUp` and `portraitDown`.

## Application routes

GoRouter definitions in [`lib/src/features/navigation/app_router.dart`](../../lib/src/features/navigation/app_router.dart) are authoritative. Current route patterns include:

```text
/
/assets
/assets/room/:roomId
/assets/thing/:assetId
/maintenance
/maintenance/:planId
/calendar
/more
/search
/trash
/statistics
/settings
/sync-health
/profile -> /account
/account
/backup
/notifications
/permissions/setup
```

Route parameters are untrusted input. Screens must handle missing, deleted, unauthorized, malformed, or not-yet-hydrated entities without crashing or exposing another account's data.

`/sync-health` is linked from Account. It reads local failed-visible mutations and unresolved conflicts, displays only localized privacy-safe categories, and routes retry, dismissal, and keep-local/keep-cloud choices through the account-scoped sync store. It never renders record keys, preserved payloads, or raw exception text.

### Entity rehydration and route state

- Entity detail routes (`/assets/room/:roomId`, `/assets/thing/:assetId`, `/maintenance/:planId`) reconstruct their full state independently from repository providers without relying on transient route `extra` objects.
- Inactive, missing, deleted, or unauthorized entities explicitly present localized not-found empty states (`roomNotFound`, `itemNotFound`, `taskNotFound`) and error panels.

### Editor dirty-state exit guard

- All bottom-sheet and dialog editors (`RoomEditorDialog`, `AssetEditorDialog`, `AreaEditorDialog`, `PlanEditorDialog`) track form dirty state against initial model values.
- Intercepts system back gestures, modal overlay tap-outs, and App Bar close buttons via `PopScope`.
- Prompts with localized discard confirmation (`discardChangesTitle`, `discardChangesMessage`) if dirty, allowing users to keep editing or discard changes. Clean editors dismiss immediately.

Route changes should update navigation tests, deep-link behavior, authentication gates, analytics/diagnostic route naming, and this reference.

`/permissions/setup` is the user-invoked capability-setup surface. It can also be opened from Settings. Weather-card, reminder-settings, and task-scheduling education use the same controller with source-specific capability selection rather than creating independent OS permission requesters.

## Capability truth model

Owntend keeps four kinds of state separate:

| Layer | Examples | What it establishes |
|---|---|---|
| Application preference | Reminders enabled, inbox enabled, weather alerts enabled | User intent only |
| OS permission, service, or special access | Approximate location permission, location services, notification permission | Current Android authorization or availability |
| Runtime service truth | Notifications actually enabled, scheduler can actually schedule alarms | Whether the platform service can perform the requested operation now |
| Effective capability | `active`, `degraded`, `blocked`, `disabledByUser`, `unavailable`, `notConfigured` | The combined product state shown to application logic and education UI |

The snapshot derivation in `lib/src/features/permissions/domain/capability_snapshots.dart` is authoritative. A preference never upgrades a denied OS state, and an OS grant alone does not turn on a user-disabled feature.

Weather areas have three modes: not configured, manually selected, and device-derived. A manual area is an active weather capability even when location permission remains denied, service-disabled, restricted, or unavailable; the stored OS state is not rewritten. Device-derived weather requires foreground approximate-location access, an available location service, and a successfully persisted area before setup advances.

Notification capability combines the master and channel preferences with Android permission and the notification plugin's effective state. In-app inbox and weather-alert preferences are independent of whether Android can post a device notification.

## Android permissions

The current main manifest declares:

| Permission | Purpose | Review requirement |
|---|---|---|
| `INTERNET` | Supabase, authentication, ads, weather/network features, Sentry | Keep network payloads privacy-safe |
| `ACCESS_COARSE_LOCATION` | Optional current-location selection for a weather area | Request in context; preserve manual selection; no precise/background expansion |
| `POST_NOTIFICATIONS` | Local maintenance reminders on supported Android versions | Explain value and handle denial |
| `RECEIVE_BOOT_COMPLETED` | Restore scheduled reminders after reboot | Keep receiver work bounded |
| `WAKE_LOCK` | Reliable bounded notification/background work | Avoid long-running holds |
| `VIBRATE` | Notification behavior | Respect user/channel settings |
| `FOREGROUND_SERVICE` | Foreground task support | Show required user-visible notification |
| `FOREGROUND_SERVICE_DATA_SYNC` | Foreground data synchronization | Keep service type aligned with actual work |

The source manifest does not request fine location or background location. A release claim still requires inspection of the merged production manifest because dependencies can contribute manifest entries.

## Android components

The application registers:

- `MainActivity` as the exported launcher activity.
- Flutter foreground-task service with `dataSync` type.
- Scheduled notification receiver.
- Scheduled notification boot receiver for boot, application replacement, time/timezone changes, and supported vendor quick-boot actions.

Android platform backup is disabled through manifest/application backup settings. Owntend's own backup feature is separate.

## Permission design rules

- Ask only when the user reaches a feature that requires the permission.
- Explain the product value before the system prompt where appropriate.
- Provide useful degraded behavior after denial.
- Do not repeatedly pressure the user after denial.
- Distinguish denied, permanently denied, restricted, service-disabled, and unavailable states.
- Link to the relevant app or location-service settings only when the user can act there, then recompute one coherent snapshot when the app resumes.
- Route all checks, prompts, prompt-history writes, and settings actions through `AppPermissionCoordinator`; feature adapters and notification scheduling must not create competing request paths.
- Update `PRIVACY.md`, store disclosures, tests, and operations docs for any new permission.

The first dashboard visit can educate for an unconfigured weather area and unsatisfied notification delivery, subject to deferral/cooldown. Manual weather selection does not request OS location.

## Notifications and reminder timing

Owntend promises approximate reminder timing only. Scheduling always uses `AndroidScheduleMode.inexactAllowWhileIdle`; the exact-alarm capability (manifest permission, domain model, UI, education copy, and ARB strings) was removed before launch because the binary does not request restricted exact-alarm access. Battery-saver or OEM restrictions may delay reminders; reminders still exist regardless of delivery precision.

Test permission and scheduling behavior across Android versions, notification channels, disabled notifications, reboot, application replacement, time-zone changes, daylight-saving transitions, maintenance completion, recurrence changes, and duplicate scheduling. Pure/widget tests establish derivation and routing contracts; OEM settings behavior, real notification delivery, reboot/update restoration, and timing accuracy require physical-device evidence.

## Foreground and background work

**Chosen model (BG-001).** Cloud sync is foreground-driven; first hydration and restore work run through the single account-scoped `flutter_foreground_task` dataSync foreground service (`ForegroundService`, `exported=false`) with timeout/fallback, and the daily notification refresh uses WorkManager (`owntend.daily_refresh`). The plugin's boot/auto-restart surface is unused: auto-run on boot is disabled, nothing registers restart-on-boot behavior, and no short-service work exists. The merged manifest therefore removes the plugin-contributed `RebootReceiver`, `RestartReceiver`, and `FOREGROUND_SERVICE_SHORT_SERVICE` via manifest-merger removals; a build-time check of the merged production manifest must confirm exactly one owned dataSync service and no unowned exported receiver. Android 15/16 dataSync six-hour budget behavior on physical devices remains required launch evidence.

Foreground service and Workmanager jobs should be bounded, idempotent, account-aware, and safe to restart. Notification plugin initialization does not itself prove that account-scoped background work is registered: authenticated-ready startup verifies the current session against the bound local account and registers or updates the unique `owntend.daily_refresh` periodic task. Repeated startup updates that unique work instead of creating duplicates, while sign-out/account mismatch cancels or rejects account-scoped execution. The daily worker reloads session and binding before domain reads.

Durable notification reconciliation requests are consumed by authenticated foreground startup/resume, relevant maintenance reconciliation, and the daily worker. Pending requests are coalesced into one scheduler refresh and acknowledged only after that refresh succeeds; retryable failures leave durable work queued. Background jobs must not expose user content in persistent notifications beyond what the user expects, and must stop or rebind safely during sign-out and account deletion.

## Location

Use approximate location only for the current-location weather-area option. Manual search is the non-permission alternative, but its typed query and chosen area still cross the documented weather-provider and synchronization boundaries; it must not be described as “no location data.” Do not retain or transmit location beyond the documented purpose. Handle no permission, unavailable services, timeout, stale cache, and network failure. Introducing precise or background location requires a separate product and privacy decision.
