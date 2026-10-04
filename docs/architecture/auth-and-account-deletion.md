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

Supabase client initialization is a required cloud startup boundary. Failure presents a localized retry surface for pristine local state; an existing bound account or non-pristine local data may open in offline mode so initialization failure does not remove local access. Once initialized, authentication stream failures propagate through `authStateProvider` as Riverpod error state; cached repository session state remains available to continuity-sensitive consumers, and a stream transport error is never converted into a signed-out event.

## Sign-out sequence

Ordinary user sign-out is deliberately **non-destructive**. It does not clear the local database, unlink the stored account binding, or reuse the account-deletion cleanup path. Production authentication is wrapped by `AccountSafetyAuthRepository`, which requires an `AccountSafetyBarrier` before it delegates to Supabase/Google sign-out.

For an authenticated account, the sign-out sequence is:

1. Capture the current Supabase user ID as the immutable expected account identity.
2. Enter the coordinator's account-transition barrier for that identity. The coordinator advances the account epoch, rejects new automatic sync work, stops realtime, and waits for in-flight account work, including unsettled operations owned by retired coordinators. A timeout fails preparation.
3. Cancel all account-scoped WorkManager tasks with `cancelAccountScopedBackgroundWork()`, including daily refresh, restore recovery, and cloud synchronization. This cancellation is not best-effort for sign-out: failure propagates and cloud/provider sign-out does not run.
4. Re-check that the authenticated identity is still the captured user ID.
5. Only after the barrier succeeds, delegate to Supabase Auth (`SignOutScope.local` or `SignOutScope.global`) and Google Sign-In.
6. Resolve the account-transition barrier according to the resulting auth state. If sign-out failed and the authenticated session remains, `cancelAccountDeletion()` is the rollback path and may resume background sync, realtime, and normal scheduling. If sign-out succeeded and the session is gone, `completeAccountSignOut()` is terminal: it clears the transition state while keeping scheduled sync work cancelled and realtime stopped, and account-scoped WorkManager tasks are cancelled again. The local account binding remains intact in both cases.
7. Reset Sentry telemetry account scope after successful delegated sign-out.

A barrier preparation failure is fail-closed: the authenticated session remains in place and the caller can retry. A partially prepared barrier may be rolled back only while the authenticated session still identifies the original account. Successful sign-out never uses the rollback path and never re-enables account-scoped work as part of barrier release. This rollback-versus-terminal split is part of the sign-out safety invariant, not a best-effort cleanup detail.

When a sync run encounters an authentication failure, its error-owning cleanup
waits for that run and any enabling account transition to finish before asking
the auth repository to sign out. It rechecks the account epoch and identity.
This preserves the same safety barrier without making a failed sync wait on
itself or signing out a replacement account.

Worker callbacks (`owntendWorkManagerCallback`, `runCloudSyncInBackground`) independently fail closed behind their own account guard before performing account-scoped work.

Sign-out is not account deletion. Local data and cloud data remain unless the separate deletion workflow succeeds.

The startup sign-out escape path publishes signed-out state only after the authentication repository confirms that no session remains. If local cleanup or provider sign-out fails while a session remains, startup retains the authenticated blocking retry screen and disables offline continuation because local cleanup may be partial. A failure after the repository has already cleared its session remains signed out. The coordinator suspended for startup sign-out is retired; successful sign-out or explicit startup retry creates a fresh account-bound coordinator, preventing permanent suspension from leaking into the next login.

After an authoritative signed-out event, independent reminder and inbox cleanup
have immediate error ownership without keeping a startup timeout alive. Either failure is logged through
the scrubbed startup logger without becoming an unhandled asynchronous exception
or preventing the other cleanup from running.

## In-app deletion sequence

Deletion preparation waits for both active synchronization and optional photo
file writers from current and retired coordinators to settle. A timeout fails preparation before the destructive RPC
can begin. A fresh pre-request attempt can then cancel safely; an older
unresolved deletion operation retains its recovery record and barrier.

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
12. Pending, temporarily unavailable, or `recovery_not_found` status keeps synchronization suspended and the secure recovery record intact. A missing receipt cannot prove that an earlier destructive request was never accepted. Preparation failures and identity mismatches on a retry cannot cancel or erase that earlier operation. Cancellation is permitted only for a fresh operation created by the current invocation when no request began or the server definitively rejected it before destruction.
13. Restart recovery resumes status lookup and finishes local cleanup when cloud deletion succeeded but the client stopped before completion.
14. After receiving a completed receipt (from `delete-account` or `account-deletion-status`), the client completes local cleanup including all sidecar media directories via `LocalAccountDataCleaner` and `SidecarRegistryStore`. If ANY sidecar directory fails to delete, local cleanup throws and blocks completion, keeping the cleanup marker active. Only after all local canonical and sidecar media copies are completely purged does the client record that local cleanup is terminal.
    Account-scoped local cleanup includes secure drafts for asset creation, asset editing/copying, and task creation/editing. Exact account-delimited key prefixes preserve other accounts and local-mode drafts; a storage deletion failure blocks completion.

15. Acknowledgment is a durable protocol transition, not best-effort telemetry. The client invokes the capability-bound `account-deletion-status` acknowledgment and treats the operation as acknowledged ONLY when the server responds with an explicit `acknowledged` receipt carrying `deleted: true` and the exact expected user ID. The browser sends only the accepted `action`, `recovery_key`, and `expected_user_id` request fields; response metadata is not echoed into the strict request body. Any transport loss, non-success status, or mismatched/incomplete receipt persists `acknowledgementPending` in the secure journal, keeps authentication cleared, and is retried at startup without repeating local cleanup or cloud deletion. The secure recovery record (and therefore the only retry authority) is deleted strictly after a validated acknowledgment; the backend then transitions the operation from `completed` to `acknowledged`, making the row eligible for shorter-window GC.

### Interrupted local cleanup identity

`LocalAccountDataCleaner` persists the exact account user ID in `.owntend-account-deletion-cleanup-pending` before destructive local cleanup begins. Recovery treats that durable marker identity as authoritative:

- Blank markers and the historical `pending` placeholder are invalid and are never rebound to whichever account happens to be active later.
- If the marker identifies Account A while the local database is bound to Account B, recovery deletes nothing, preserves the marker, and reports an identity-mismatch failure for retry/recovery handling.
- If no account is bound but authoritative domain data is still present, recovery also deletes nothing because that data cannot be safely attributed to the marker account.
- If the database was already cleared before a crash, a valid Account A marker can replay the remaining cleanup with no current binding because the authoritative domain data is pristine; this keeps the operation idempotent without borrowing another account's identity.
- Additional account-scoped cleanup receives the marker's recorded user ID only after the database and canonical file cleanup have passed the identity guard.
- The marker is removed only after the complete local cleanup succeeds.

Deferred startup resolves this marker before diagnostics, cloud initialization, authentication restoration, realtime, or normal account-scoped background work. An invalid marker, account mismatch, or unbound non-pristine database transitions startup to an explicit blocked-recovery surface and stops bootstrap at that boundary. The marker remains intact and the surface exposes a retry action; normal startup resumes only after the same account-scoped recovery succeeds safely.

These rules ensure that work authorized for one account cannot be reinterpreted as destructive work for another account after restart or account switching.

## Browser deletion sequence

> **Current availability:** the public page is intentionally unavailable while
> Pre-release production containment is active.
> This does not change the in-app deletion sequence or backend contract. See the
> [containment record](../operations/production-containment.md).
