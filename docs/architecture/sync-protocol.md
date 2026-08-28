# Offline-First Synchronization Protocol


## Skipped-feed promises and push efficiency (WP-004/WP-006)

Incremental-feed records masked by a local outbox intent are never applied
blindly. Each skip writes a durable `sync_skipped_feed_entries` promise:

- Active intents (`pending`/`inFlight`/`conflictRecovery`) defer the remote row;
  the cursor may advance only because the promise exists.
- Conflict/terminal intents additionally refresh the shadow so revision checks
  stay truth-adjacent, while the local row remains owned by conflict machinery.
- After every push cycle `_drainSkippedFeedEntries` performs one targeted
  `gateway.fetch` per unmasked promise; failures leave the promise for the next
  cycle. Deletions behind intents are promised, never guessed.
- Invariant: for any feed record either the shadows reflect it or a durable
  promise exists.

Failure semantics: outbox/acknowledgement payload decode failures increment the
non-PII `SyncStatus.payloadParseFailures` counter (never silent, no content
stored); incremental-feed photo download failures defer to the post-ready media
worker exactly like first-sync photos; `deferPendingAfterFailure` schedules
run-level backoff without forging per-row error text.

Push dequeue is a bounded due-window query (`pendingMutations`, LIMIT 200,
indexed by `idx_outbox_retry`) with dependency keys resolved by targeted
lookups — the queue table is no longer loaded whole per cycle.

## Purpose

Owntend must accept useful local work without connectivity and later synchronize it without losing mutation intent, mixing accounts, duplicating charged or completion operations, or silently overwriting newer cloud state.

The implementation under `lib/src/core/sync/`, synchronized repositories, Drift synchronization tables, Supabase migrations, RPCs, and tests is authoritative.

## State model

The coordinator exposes states equivalent to:

- Disabled: synchronization is not configured or intentionally unavailable.
- Signed out: no authenticated cloud account is bound.
- Ready: initialized and able to schedule work.
- Initializing: account binding and local runtime preparation are in progress.
- Waiting for sync lease: initial hydration cannot own the local sync lease yet and remains non-ready while durable hydration completion is observed or retried.
- Syncing: push, pull, reconciliation, or cleanup work is active.
- Offline: network-dependent work is deferred while local operation continues.
- Blocked: an authorization, account, conflict, or protocol condition requires intervention.
- Error: a recoverable or terminal failure is visible.

Hydration and realtime readiness have their own lifecycle and must not be collapsed into a single boolean.

## Account binding

Every synchronized local working set is associated with an authenticated account identity.

On sign-in or account transition, the coordinator must:

1. Resolve the current Supabase user.
2. Compare it with the locally bound identity.
3. Prevent pending work from a previous account being pushed under the new account.
4. Require the canonical merge decision when a non-pristine, unbound local working set and existing cloud data could collide.
5. Clear stale sync cursors, shadows, leases, and cleanup work before binding a previously unbound installation.
6. Initialize or hydrate only the correctly bound account state.

Never silently reassign local records between accounts.

## Local mutation path

A synchronized mutation should:

1. Validate domain behavior locally.
2. Apply the local database change transactionally.
3. Create a durable outbox operation with a stable operation identifier.
4. Record enough payload and revision context to retry after restart.
5. Notify local readers immediately.
6. Schedule synchronization when the environment permits.

The UI must not wait for network success to reflect valid offline-first changes, but it must show blocked or failed cloud state when that distinction matters.

## Push path

The push worker:

1. Selects eligible outbox work for the current account.
2. Orders operations when dependencies require it.
3. Sends an idempotent RPC or cloud mutation.
4. Distinguishes success, duplicate success, conflict, retryable failure, authorization failure, and terminal validation failure. New-row batches use `ON CONFLICT DO NOTHING` against the exact remote primary-key columns (`user_id`, optional `device_id`, plus entity key columns): a response-loss replay is skipped without a noisy PostgREST 409/PostgreSQL 23505, then the canonical row is fetched and acknowledged only when its semantic data matches the local intent. A divergent same-key row is applied as canonical state and the losing local intent remains a durable conflict; unrelated business uniqueness constraints are never ignored. Optimistic updates and deletes request list responses, so a revision mismatch or missing row returns HTTP 200 with an empty list instead of a noisy PostgREST 406 object-response warning. The empty result is still a sync conflict and triggers canonical remote fetching; older `PGRST116` failures remain classified as conflicts.
5. Updates local revisions/shadows and removes or resolves the outbox entry transactionally.
6. Schedules targeted reconciliation when the cloud result differs from local assumptions.

A network timeout after a server commit must be safe to retry.

Generic row creation and optimistic update use separate serialization
contracts. Creation may carry the owner asserted from the authenticated
session, record keys, offline creation timestamps, and the entity's insert
fields. An update is built only from the entity's required
`SyncEntitySpec.updatableLocalColumns` allowlist; ownership, device scope,
record keys, expected revision, `created_at`, `updated_at`, and `revision`
remain filters or server-owned metadata. Remote aliases are applied only after
the local allowlist is evaluated, and an allowlisted nullable value remains in
the PATCH map when its value is explicitly `null`. Deletes serialize no row
payload. An empty update contract means generic UPDATE is prohibited and must
fail locally before an HTTP request.

The client allowlist and authenticated Postgres column-level UPDATE grants are
one invariant enforced at two layers. The executable client matrix is in
[`sync_dtos.dart`](../../lib/src/core/sync/sync_dtos.dart), and the database
matrix is installed by the latest migration under
[`supabase/migrations/`](../../supabase/migrations/) and compared exhaustively
by pgTAP. Table-wide authenticated UPDATE and direct client authority over
server revision/timestamp columns are prohibited even when owner RLS would
otherwise allow the row.

## Outbox generations and conditional completion

Every outbox row (`offline_mutation_queue` table) maintains an integer `generation` column (incremented automatically on SQLite triggers during coalesced same-key edits).
- Operations (`markMutationInFlight`, `markMutationSucceeded`, `markMutationFailed`, `markMutationTerminal`) use conditional Compare-And-Swap (CAS) matching `(entity, record_key, generation)`.
- If a same-key edit occurs while a network request is in-flight, `generation` is incremented. The older network response fails to match `generation`, preserving the newer local intent and preventing outbox data loss.
- Idempotent batch replay resolution performs canonical remote record comparison and applies the fetched record before acknowledging completion; the legacy primary-key 23505 fallback uses the same exact-data check.

## Pull path

The pull worker:

1. Uses the account's cursor or checkpoint.
2. Reads bounded cloud changes in deterministic order.
3. Applies ownership and schema validation.
4. Compares remote revision, local row, shadow, and pending outbox intent.
5. Applies non-conflicting changes transactionally.
6. Records shadows and advances the cursor only after successful application.
7. Continues until the current window is drained.

The local mutations, shadows, and matching checkpoint for a completed pull page
must commit in the same Drift transaction. Any failure rolls back both data
application and checkpoint advancement so retry replays the page safely.

## Feed checkpoint and retention recovery

- **Change Feed Checkpoint Namespace**: The Change Feed cursor (`server_change_feed` in local SQLite `sync_cursors`) advances strictly during completed, ordered pull scans (`fetch_user_change_feed`).
- **Push & Point-Fetch Isolation**: Push acknowledgements, maintenance RPC completions, conflict point-fetches, and Realtime hints may update canonical entity shadows but never advance the change-feed cursor. Only a completed feed transaction owns the inbound checkpoint.
- **Retention Gap Resnapshot**: When `fetch_user_change_feed` returns `resnapshot_required == true`, the client persists a resnapshot marker and the captured high-water boundary. A restart while that marker exists repeats an authoritative snapshot plus delete reconciliation. Only after that succeeds does the client advance the feed cursor to the captured high-water and clear the marker.
- **No client parity API**: Cross-account feed parity is a service/CI concern. The application has no capability-discovery, dark-validation, or client healing RPC.

## Initial hydration

Initial hydration builds a trusted local view for a newly bound account. It must be restartable and must not present partial hydration as fully synchronized. Existing offline local work requires an explicit policy before cloud data is applied.

Hydration completion is durable and independent from ordinary incremental synchronization. Authenticated startup may become ready only after the local store proves a complete snapshot for the currently authenticated account.

A local sync-lease miss is not hydration success. The coordinator exposes a waiting-for-lease state and retries or observes the shared durable completion marker until hydration is complete. A foreground process may accept hydration completed by a background worker only after that durable marker is complete. The wait is bounded and becomes a retryable startup failure rather than silently publishing ready, and an account identity change while waiting fails closed.

## Realtime invalidation

Realtime events (insert, update, delete) are strictly non-authoritative invalidation and scheduling hints.
- Realtime callbacks do not directly modify domain tables or erase local outbox/shadow state.
- A peer hard-delete event received via Realtime schedules a change feed pull (`_scheduleAutomaticSync`) but does not destroy local SQLite rows or pending outbox intent (`LocalSyncMutation.generation`).
- Deletes are applied authoritatively ONLY through the ordered change feed pull protocol (`_pullServerChangeFeed` -> `applyRemoteFeedDelete`). If a local pending mutation exists, local domain data is preserved and the shadow is updated so the next push can reconcile cleanly.
- The system tolerates dropped, duplicated, delayed, reordered, and burst Realtime events without permanent state divergence.

## Resume and reconnect convergence

Foreground resume and network restoration are correctness boundaries, not freshness optimizations. When cloud sync is enabled for the currently authenticated bound account, the coordinator first ensures Realtime and then requires a pull-capable broad convergence pass even when `lastSyncedAt` is only minutes old. That pass also pushes eligible local mutations.

A broad convergence request has precedence over queued targeted or push-only work. If a targeted or push-only operation is already active, one broad follow-up remains pending. If a broad pull is already active, the resume/reconnect request coalesces into that operation. The only incremental protocol is integer contract `1`; an unsupported contract is a visible incompatible-schema failure.

This recovery path repairs a remote change whose Realtime notification was missed while the app was suspended or disconnected. Realtime payloads remain hints: canonical app-domain state enters Drift through an authoritative snapshot, targeted fetch, or the change feed before Riverpod exposes it to widgets.

## Conflict handling

A conflict exists when local and cloud changes cannot be safely merged under the entity contract.

Conflict behavior is entity-specific, durable, and verifiable in tests:
- **Full Preimage Conflict Ledger**: All sync conflicts are durably recorded in the SQLite `sync_conflicts` table (`id`, `account_id`, `entity`, `record_key`, `operation_id`, `local_payload_json`, `remote_payload_json`, `remote_revision`, `resolution_status`, `resolved_at`, `created_at`). Account ownership is strictly non-null for account-bound conflicts, and only the owning account can list or resolve its conflicts.
- **No Silent Discard**: The sync engine has no discard-on-conflict path across snapshot, pull, and push. An outbox entry is removed only when (a) the exact server operation is acknowledged with a generation-checked CAS delete, (b) a newer local edit replaces it through the outbox trigger's generation bump, or (c) the user explicitly resolves the conflict.
- **Durable Conflict State**: When a remote edit wins a conflict — by higher server revision, newer client timestamp, or clock-skew policy — the client applies the canonical remote row locally but moves the losing outbox entry into the durable `conflict` state instead of deleting or resolving it. Conflicted rows are excluded from automatic pushes and survive restart and process death indefinitely. Each preserved conflict records the serialized local payload snapshot plus remote payload/revision evidence in `sync_conflicts`; `resolution_status` stays `unresolved` and `resolved_at` stays null until explicit resolution.
- **Explicit Resolution Only**: `LocalSyncStore.resolveSyncConflict` is the sole resolution entry point. Keep-local restores the newest preserved payload into the local table and returns the mutation to the push queue; keep-remote deletes the conflicted intent. Exact server acknowledgement resolves outstanding ledger rows as `resolved_server_acknowledged`. A fresh local edit on a conflicted record supersedes the stale conflict through the trigger's generation bump and returns the row to the pending queue.
- **Server-Authoritative State**: Maintenance completion RPCs and wallet/point debits are strictly server-authoritative and idempotent.

## Clock skew

Device clocks are not a sole source of truth for global ordering. Prefer server revisions, server timestamps, stable operation identifiers, and monotonic local sequencing. Time-based UI values may use device time, but synchronization correctness must tolerate skew.

## Server change feed and durable deletes

The database includes a server-assigned, monotonic, owner-scoped change feed (`server_change_feed` table, `change_seq` identity column).
- Every INSERT, UPDATE, or DELETE on the 17 synchronized tables (`profiles`, `areas`, `rooms`, `assets`, `device_details`, `pet_details`, `plant_details`, `safety_details`, `tags`, `asset_tags`, `asset_photos`, `maintenance_plans`, `maintenance_plan_metadata`, `maintenance_records`, `notification_inbox`, `user_settings`, `streaks`) atomically writes a change log entry via the `fn_log_server_change_feed()` trigger. Feed entries guarantee a non-null `client_updated_at` ISO-8601 timestamp coalesced from client modification, updated, created, or clock timestamps.
- Contract `1` uses the exact canonical `SyncEntitySpec.entity` identifier for each of the 17 synchronized entities. Every feed row carries typed `key_data`, a bounded canonical payload for upserts, and the exact key for deletes. Unknown entities, malformed keys, key mismatches, extra fields, or unsupported contract versions are incompatible-schema failures and do not advance the feed cursor.
- The `change_seq` is server-generated and independent of client clocks or backdated/future-dated `updated_at` business timestamps.
- Hard deletes write durable `DELETE` records into `server_change_feed`, recording the entity type and deleted record ID.
- Row Level Security (RLS) restricts SELECT access to the authenticated user owning the records (`user_id = auth.uid()`), while direct client INSERT/UPDATE/DELETE access to `server_change_feed` is strictly revoked.
- Monotonic change sequences support owner-scoped keyset pagination (`user_id`, `change_seq`).
- The `fetch_user_change_feed(p_since_seq, p_limit, p_expected_generation)` RPC exposes the feed to authenticated clients as a `SECURITY INVOKER` function under owner-scoped RLS. It captures an owner-scoped high-water sequence and generation at scan start and pages only changes `change_seq <= high_water_seq` in strict monotonic order.
- Bounded retention is real: the service-only `owntend_private.compact_user_change_feed()` job removes rows below the retained boundary (age plus per-owner row cap) while holding the owner state row lock, and — only when it actually removed rows — atomically advances the durable `owner_feed_state.feed_generation` together with `retained_min_seq`. No-op runs never advance the generation. Concurrent feed writes serialize on the same row lock, so a generation or high-water range can never be observed half-applied.
- `fetch_user_change_feed` returns contract version, `feed_generation`, `next_seq`, `has_more`, `high_water_seq`, and `resnapshot_required = true` when the requested cursor predates the retained range or was built for a different generation. Because compaction advances the durable generation, every pre-compaction cursor deterministically rehydrates instead of silently missing deleted history.
- There is no rollout flag, capability table, fallback pull protocol, or authenticated parity function in production v1. A service-role-only parity function remains available to protected validation.

Maintenance plan columns use the same canonical names in Flutter/Drift and
Postgres (`instructions`, `recurrence_interval`, and `recurrence_unit`). The
only deliberate generic-sync aliases are the streak summary fields
(`best_streak` to `longest_streak` and `last_completed_date` to
`last_completion_date`); `SyncEntitySpec.remoteRenames` translates those names
in both directions. Specialized detail and maintenance metadata columns also
match the Flutter/Drift payload names directly, preventing silent field loss
during RPC creation or ordinary synchronization.

## Maintenance completion

Maintenance completion affects history, recurrence, due state, reminders, statistics, and potentially multiple devices. Completion operations require stable idempotency keys. Maintenance completion timestamps (`completedAt`, `expectedNextDueDate`, `previousDueDate`, `nextDueDate`) MUST be canonicalized to whole-second UTC precision (`date_trunc('second', ...)` in SQL, `canonicalSyncSecond` in Dart) across Drift SQLite, outbox JSON payloads, and Supabase Postgres to eliminate sub-second precision mismatch rejections. If the server rejects or resolves a duplicate, local reminder and recurrence state must reconcile to the accepted cloud result rather than advance permanently from an unaccepted local assumption.

Cloud `maintenance_records` are pull-only for generic synchronization. Authenticated table INSERT, UPDATE, and DELETE are revoked, and both single-row and batch gateway paths fail closed if asked to mutate them. Before pushing, a retained generic history row duplicated by a structurally valid completion/undo intent is removed; any other retained generic history mutation becomes a durable, user-visible `server_authority_required` failure. Restore-origin rows are replaced by validated per-plan merge batches. Ordinary completions and undo use their dedicated RPCs. A missing-plan completion is accepted only when the same account already has an exact task-creation authorization for that plan ID; otherwise it returns terminal `task_creation_not_authorized` without partial state.

`complete_maintenance_task` returns completion contract version 1. Every
non-exception result has the same nine fields: `contract_version`, `status`,
`retryable`, `conflict_reason`, `current_plan_revision`,
`resulting_record_id`, `resulting_next_due_date`, `plan`, and `record`. The
client rejects unknown versions, statuses, reason codes, types, ownership,
plan/record relationships, requested identities, timestamps, and impossible
field combinations as the non-retryable
`maintenance_completion_rpc_contract_mismatch`. It never persists the response
or its identifiers for diagnostics.

A completion push has two successful run-level dispositions. `applied`
acknowledges or reconciles the mutation. `terminalHandled` keeps a rejected
business mutation as failed-visible and allows hydration and later independent
mutations to continue. Applied, already-applied, and
occurrence-completed-elsewhere results require canonical rows. A stale plan
revision receives exactly one retry using the returned canonical revision;
another well-formed conflict is reconciled or quarantined without failing the
run. Invalid payload outcomes are quarantined with their bounded server reason.
Only transport failures and run-wide authentication, account-scope,
permission, or schema failures abort the run. The run coordinator rethrows the
canonical typed failure with the original stack trace so observability sees the
classification without losing the originating frames.

Signed-in backup restore converts maintenance history into deterministic per-plan `maintenance_history_restore` execute operations of at most 100 records. `restore_maintenance_history` requires an existing owned plan, expected revision, and exact material plan snapshot. It inserts only missing rows; an exact existing row counts as replay success; a differing record ID or operation ID makes the whole batch a durable `history_record_conflict`. A plan difference is a durable `plan_snapshot_conflict`. The RPC never creates plans, overwrites schedules, or deletes unrelated cloud history. An imported archive remains untrusted: this proves ownership, structure, and exact replay, not historical authenticity.

Asset and plan generic updates are positive allowlists, not full-row payloads
with protected fields removed afterward. Asset type and plan parent asset are
therefore absent by construction, while revision-aware filters retain
optimistic concurrency. Type changes, task moves, and owned-source copies
require an authenticated online quote/commit path. Offline attempts remain
explicit drafts. Copy recovery retains local-only tag/photo intent in secure
storage but sends only the allowlisted source/target/room/include/map contract
to Supabase.

## Media synchronization

Media requires coordination between local metadata, file availability, Storage objects, upload state, and deletion cleanup.

- **Prepare-first ledger**: `prepare_asset_photo_upload` creates an owner-scoped stage before any Storage mutation and returns a server-issued `{user_id}/media/{staging_uuid}/{attempt}.{ext}` path. The preparation binds asset, photo, expected size/MIME, an idempotency key, and the client digest (explicitly advisory). Exact retries use atomic `ON CONFLICT`; expired/failed attempts retain identity, queue the previous path, and issue a new attempt.
- **Exact quota authority**: one per-user transaction advisory lock serializes quota evaluation. Fresh `staged` rows may not exceed 20 or 100 MiB aggregate expected bytes. Concurrent exact replays consume quota once; concurrent distinct prepares cannot oversubscribe either limit.
- **Storage policy binding**: authenticated INSERT requires the exact fresh staged path and active session. Prefix ownership alone is insufficient. Authenticated DELETE is not granted; `delete_asset_photo` records cleanup intent and the service worker removes bytes.
- **Required client saga**: The client prepares, uploads once with `upsert: false`, then calls `finalize_asset_photo_upload`. Finalization reads trusted Storage metadata and validates owner, row revision, MIME type, size (<=10 MiB), and object existence before exposing photo metadata. Failure remains retryable or visible; there is no direct-upload fallback.
- **Server Durable Cleanup Ledger**: Upload finalization and server-side replacement flows enqueue superseded object paths into `media_cleanup_queue` transactionally before database mutation acknowledgement.
- **Client Delete Tombstone & Cleanup Handoff**: A local `asset_photo` DELETE preserves the exact canonical Storage path in the durable outbox tombstone before the local row disappears. If the remote metadata row was already deleted (including response-loss retry), `SupabaseSyncGateway.write()` returns that same tombstone path as cleanup work. The coordinator acknowledges the exact outbox generation and inserts `sync_media_cleanup` in one Drift transaction, so the object path is always represented by either pending mutation intent or durable cleanup work. Storage object-not-found is successful idempotent cleanup; duplicate cleanup attempts are safe.
- **Local file cleanup**: Replaced or remotely deleted local photo paths enter `local_media_cleanup`. Filesystem failures persist bounded retry/backoff; paths escaping the application documents root become visible terminal records instead of being executed.
- **Transactional Primary Photo Selection & Unique Constraint**: Primary asset photo selection uses the owner-authoritative `set_primary_asset_photo` RPC. The RPC sets `is_primary = true` on the target photo and clears peer photos (`is_primary = false`) for that asset in a single transaction. Partial unique index `idx_asset_photos_single_primary` on `asset_photos(user_id, asset_id) WHERE is_primary = true` enforces at most one primary photo per asset at the database level.
- Uploads and deletes must be retryable and idempotent.
- Metadata must not claim cloud availability before verification.
- Cleanup must not delete another account's object.
- Account deletion can suspend ordinary sync while allowing deletion-specific cleanup.
- Orphan cleanup should be bounded and observable without logging private object names.

## Retry and backoff

Retryable failures should use bounded exponential backoff with jitter and persistence where appropriate. Authorization, schema, ownership, and terminal validation errors should not spin indefinitely. A PostgreSQL `42501` that explicitly reports a missing table/column privilege is a non-retryable, sync-blocking incompatible-schema failure with stable diagnostic code `data_api_acl_contract_mismatch`; RLS ownership and `WITH CHECK` denials remain permission-denied failures. Diagnostics retain only entity, operation, and SQLSTATE, never row keys, account IDs, URLs, payloads, or field values. Existing generic permission failures are never automatically replayed because they may represent genuine ownership denial. User-visible state should distinguish offline waiting from protocol failure.

## Account deletion interaction

Before remote account deletion, normal synchronization is suspended to prevent new cloud writes. The deletion workflow then removes remote media and account state, records a verifiable result, and clears local data. If deletion succeeds remotely but local cleanup fails, restart recovery must finish local cleanup without attempting to resurrect the deleted cloud account.

## Required test matrix

Every protocol change should cover relevant combinations of:

- Online and offline mutation.
- Restart before push.
- Timeout after possible server commit.
- Duplicate operation.
- Stale local revision.
- Newer cloud revision.
- Concurrent changes from two devices.
- Realtime event missing or duplicated.
- Recent-sync resume after a missed Realtime event.
- Connectivity restoration requiring broad pull convergence.
- Cursor-page failure and retry.
- Account switch with pending work.
- Revoked session.
- Hydration interruption.
- Media upload or delete failure.
- Maintenance completion conflict.
- Clock skew.
- Account deletion during queued work.

## Change checklist

A synchronized field or entity is incomplete until local schema, cloud schema, serialization, outbox, push, pull, shadows, revisions, hydration, realtime invalidation, conflict behavior, retry, account binding, backup, deletion, and tests are all addressed.
