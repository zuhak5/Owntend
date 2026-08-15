# Authentication and Account Deletion

## Authentication model

Owntend production authentication is based on Google sign-in connected to Supabase Auth. Email-and-password sign-up is disabled in the committed local Supabase configuration.

The Flutter authentication layer is responsible for:

- Starting and cancelling Google sign-in.
- Exchanging Google identity for a Supabase session.
- Persisting session material through secure platform storage.
- Restoring and refreshing sessions.
- Exposing signed-in, signed-out, loading, and error states.
- Binding synchronization to the authenticated Supabase user.

A successful Google UI interaction is not sufficient if the Supabase session cannot be established.

## Sign-out sequence

Sign-out, session loss, remote revocation, and startup unsupported session cleanup use one central, awaited, idempotent sign-out barrier (`signOutOrchestrationProvider` / `executeSignOutSequence`):

1. Stop or suspend active synchronization (`SyncCoordinator.suspend()`).
2. Cancel all account-scoped WorkManager tasks (`cancelAccountScopedBackgroundWork()`) including daily maintenance refresh and background sync.
3. Clear all scheduled notifications, local inbox notifications, and active reminder schedule snapshots (`NotificationService.clearAllScheduledReminders()`).
4. Advance local account epoch and clear binding metadata in `LocalSyncStore.clearBinding()`.
5. Sign out from Supabase Auth (`SignOutScope.local` or `SignOutScope.global`) and Google Sign-In (`NativeGoogleSignInGateway.signOut()`).
6. Reset Sentry telemetry account scope (`clearSentryAccountScope`).

Worker callbacks (`homeKeeperWorkManagerCallback`, `runCloudSyncInBackground`) fail closed behind an account guard that verifies active session state, bound identity match (`boundUserId == session.user.id`), and non-quarantined status before executing any domain reads, streak mutations, inbox writes, or weather HTTP requests.

Sign-out is not account deletion. Cloud data remains unless the deletion workflow succeeds.

## In-app deletion sequence

1. Explain consequences and obtain explicit confirmation.
2. Require recent Google reauthentication. First attempt lightweight
   verification of the already signed-in Google account; show Google's account
   chooser only when lightweight verification is unavailable.
3. Verify that the reauthenticated Google identity corresponds to the currently signed-in Supabase user.
4. Suspend normal synchronization and new account-scoped writes.
5. Generate a cryptographically secure 32-byte recovery key, encode it as 43-character unpadded base64url, and persist it with the expected Supabase user ID in secure platform storage before the destructive request.
6. Call the protected `delete-account` Edge Function with the current JWT, required confirmation, and that recovery key.
7. The function validates authentication, confirmation, recent session state, and the recovery-key schema. It stores only hashes and operation state, never the raw recovery key.
8. The backend removes private media with bounded retries, performs global sign-out, and deletes the Supabase Auth user.
9. The backend records a recoverable operation state and returns the strict deletion receipt when completion is known.
10. If the destructive response is lost, malformed, or otherwise ambiguous, the client queries `account-deletion-status` with the same recovery key and expected user ID. It never creates a replacement key for the same operation.
11. The client accepts completion only when `deleted` is `true`, `status` is `deleted`, and `user_id` equals the expected user ID, then completes local database, canonical media roots (`photos`, `profile`, `cloud_media`, `backups`), all registered and discovered sidecar directories (`.restore-*`, `.previous-*`), session, notification, cache, provider, and recovery-record cleanup.
12. Pending or temporarily unavailable status keeps synchronization suspended and the secure recovery record intact. A definitive `recovery_not_found` clears the stale recovery record and safely cancels the barrier without claiming deletion.
13. Restart recovery resumes status lookup and finishes local cleanup when cloud deletion succeeded but the client stopped before completion.
14. After receiving a completed receipt (from `delete-account` or `account-deletion-status`), the client completes local cleanup including all sidecar media directories via `LocalAccountDataCleaner` and `SidecarRegistryStore`. If ANY sidecar directory fails to delete, local cleanup throws and blocks completion, keeping the cleanup marker active. Only after all local canonical and sidecar media copies are completely purged does the client record that local cleanup is terminal and send an idempotent capability-bound acknowledgement to the backend. The backend transitions the operation from `completed` to `acknowledged` and makes the row eligible for shorter-window GC.

## Browser deletion sequence

> **Current availability:** the public page is intentionally unavailable while
> TASK-001 production containment is active.
> This does not change the in-app deletion sequence or backend contract. See the
> [containment record](../operations/production-containment.md).
