from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f'missing documentation block in {path}')
    file.write_text(text.replace(old, new, 1))


replace_once(
    'docs/architecture/system-overview.md',
    'The Android host declares permissions and components required for internet access, optional approximate location, notifications, optional exact alarms, boot handling, wake locks, vibration, foreground data synchronization, and local notification receivers. Background work restores or reconciles reminders and synchronization without introducing fine or background location.',
    'The Android host declares permissions and components required for internet access, optional approximate location, notifications, optional exact alarms, boot handling, wake locks, vibration, foreground data synchronization, and local notification receivers. Notification plugin initialization is separate from account-scoped periodic registration: after authenticated readiness, `NotificationBootstrap` verifies that the active Supabase session matches the bound local account before it register/updates the unique daily WorkManager refresh. The worker independently reloads and revalidates the same account boundary before reading or scheduling anything.\n\nDurable notification-reconciliation requests live in Drift and are consumed after authenticated notification bootstrap, after relevant foreground maintenance reconciliation, and by the daily WorkManager path. A consumer coalesces pending requests into one schedule refresh and removes only the exact request versions covered by a successful refresh; failures retain the request with bounded retry metadata, so restart or a later trigger can replay it safely. Background work restores or reconciles reminders and synchronization without introducing fine or background location.',
)

replace_once(
    'docs/reference/routes-and-permissions.md',
    'Foreground service and Workmanager jobs should be bounded, idempotent, account-aware, and safe to restart. They must not expose user content in persistent notifications beyond what the user expects. Background work must stop or rebind safely during sign-out and account deletion.',
    'Foreground service and Workmanager jobs should be bounded, idempotent, account-aware, and safe to restart. Notification plugin initialization does not itself prove that account-scoped background work is registered: authenticated-ready startup verifies the current session against the bound local account and register/updates the unique `owntend.daily_refresh` periodic task. Repeated startup updates that unique work instead of creating duplicates, while sign-out/account mismatch cancels or rejects account-scoped execution. The daily worker reloads session and binding before domain reads.\n\nDurable notification reconciliation requests are consumed by authenticated foreground startup/resume, relevant maintenance reconciliation, and the daily worker. Pending requests are coalesced into one scheduler refresh and acknowledged only after that refresh succeeds; retryable failures leave durable work queued. Background jobs must not expose user content in persistent notifications beyond what the user expects, and must stop or rebind safely during sign-out and account deletion.',
)

replace_once(
    'docs/development/testing.md',
    'Test the separation of user preference, OS/service/special-access state, scheduler truth, and effective capability. Include manual weather with denied location, service-disabled location, notification denial and disabled channel, exact preference off, exact denial with inexact fallback, settings-return refresh, time-zone change, reboot, application update, stale snapshots, completion rescheduling, and duplicate prevention.',
    'Test the separation of user preference, OS/service/special-access state, scheduler truth, and effective capability. Include manual weather with denied location, service-disabled location, notification denial and disabled channel, exact preference off, exact denial with inexact fallback, settings-return refresh, time-zone change, reboot, application update, stale snapshots, completion rescheduling, and duplicate prevention. For background notification work, cover matching versus mismatched account identity, idempotent unique periodic registration across restart, cancellation/rejection on sign-out or account switch, durable reconciliation surviving process restart, coalescing duplicate requests, ACK only after successful refresh, retry state after failure, and replay when a worker/foreground consumer restarts mid-reconciliation.',
)

replace_once(
    'PRIVACY.md',
    '_Last reviewed: August 13, 2026_',
    '_Last reviewed: August 17, 2026_',
)
replace_once(
    'PRIVACY.md',
    'Owntend schedules local maintenance notifications and may use exact alarms, boot restoration, wake locks, foreground data-sync service capability, and Workmanager. Notification preferences, Android notification permission, channel state, and effective reminder capability are separate. Exact timing is optional; when exact-alarm access is unavailable, supported reminders use degraded inexact scheduling rather than treating the preference as permission. Notification content can reveal maintenance information on the device lock screen; users should configure operating-system notification privacy according to their needs.',
    'Owntend schedules local maintenance notifications and may use exact alarms, boot restoration, wake locks, foreground data-sync service capability, and Workmanager. Notification preferences, Android notification permission, channel state, and effective reminder capability are separate. Exact timing is optional; when exact-alarm access is unavailable, supported reminders use degraded inexact scheduling rather than treating the preference as permission. The local database can also retain bounded notification-reconciliation scope, reason, attempt, and retry/error metadata until the scheduler successfully refreshes and acknowledges the request. Notification content can reveal maintenance information on the device lock screen; users should configure operating-system notification privacy according to their needs.',
)
replace_once(
    'PRIVACY.md',
    'Signing out or losing an authenticated session invokes a central sign-out barrier that cancels all account-scoped WorkManager jobs, clears scheduled notifications, local inbox rows, and reminder snapshots, and unbinds the local database identity. WorkManager background worker callbacks fail closed behind an account guard verifying active session state, bound user match, and non-quarantined status before executing any domain reads, streak mutations, inbox writes, or weather HTTP requests.',
    'Ordinary sign-out invokes the central account-safety barrier to quiesce synchronization/realtime work and cancel account-scoped WorkManager jobs before provider sign-out. Ordinary sign-out is non-destructive: it does not clear local domain data, notification inbox rows, reminder snapshots, or the local account binding merely because the session ends. Destructive local cleanup belongs to the separate account-deletion/recovery path after its identity and cloud-receipt requirements are satisfied. WorkManager background worker callbacks fail closed behind an account guard verifying active session state, bound user match, and non-quarantined status before executing any domain reads, streak mutations, inbox writes, or weather HTTP requests.',
)
replace_once(
    'PRIVACY.md',
    'Local data remains until it is deleted through application behavior, cleared by the user or operating system, removed during sign-out/account cleanup, or replaced through restore.',
    'Local data remains until it is deleted through application behavior, cleared by the user or operating system, removed during destructive account cleanup, or replaced through restore. Ordinary sign-out does not itself delete the local working set.',
)
