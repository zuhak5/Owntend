# Offline-First Synchronization Protocol

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
4. Place non-pristine local data from an unsupported provider or unbound session in durable upload-prohibited quarantine (`uploadProhibited = true`, `migrationState = 'quarantined'`).
5. Reject automatic binding and outbox push while data is quarantined.
6. Present explicit resolution paths: Export Safety Backup, Reset Local Data, or Explicit Import/Merge into the authenticated account.
7. Initialize or hydrate the correct account state after explicit resolution.

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
4. Distinguishes success, duplicate success, conflict, retryable failure, authorization failure, and terminal validation failure. Optimistic updates and deletes request list responses, so a revision mismatch or missing row returns HTTP 200 with an empty list instead of a noisy PostgREST 406 object-response warning. The empty result is still a sync conflict and triggers canonical remote fetching; older `PGRST116` failures remain classified as conflicts.
5. Updates local revisions/shadows and removes or resolves the outbox entry transactionally.
6. Schedules targeted reconciliation when the cloud result differs from local assumptions.

A network timeout after a server commit must be safe to retry.

## Outbox generations and conditional completion

Every outbox row (`offline_mutation_queue` table) maintains an integer `generation` column (incremented automatically on SQLite triggers during coalesced same-key edits).
- Operations (`markMutationInFlight`, `markMutationSucceeded`, `markMutationFailed`, `markMutationTerminal`) use conditional Compare-And-Swap (CAS) matching `(entity, record_key, generation)`.
- If a same-key edit occurs while a network request is in-flight, `generation` is incremented. The older network response fails to match `generation`, preserving the newer local intent and preventing outbox data loss.
- Batch primary key conflict resolution (Postgres 23505) performs canonical remote record comparison and applies the fetched record before acknowledging completion.

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

## Client Pull-Only Cursors and Healing Scan

- **Change Feed Checkpoint Namespace**: The Change Feed cursor (`server_change_feed` in local SQLite `sync_cursors`) advances strictly during completed, ordered pull scans (`fetch_user_change_feed`).
- **Push & Point-Fetch Isolation**: Push acknowledgements (`markMutationSucceeded`), maintenance RPC completions, conflict point-fetches, and Realtime hints may update canonical entity shadows but **never** advance either the change-feed cursor or legacy per-entity pull cursors. Only completed pull transactions own inbound checkpoints.
- **Retention Gap Resnapshot**: When `fetch_user_change_feed` returns `resnapshot_required == true` (e.g. server retention window elapsed), the client resets the feed cursor to 0 and initiates an explicit account-bound initial hydration / resnapshot.
- **Healing Scan Path**: The `runHealingScan` worker calls `validate_change_feed_parity()` RPC to discover remote rows absent locally or omitted by legacy cursors, pulling missing records without overwriting newer local outbox intent.

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

## Conflict handling

A conflict exists when local and cloud changes cannot be safely merged under the entity contract.

Conflict behavior must be entity-specific and visible in tests. Valid strategies include:

- Server-authoritative overwrite for protected server state.
- Local retry against a new revision.
- Field-aware merge where semantics are deterministic.
- Explicit blocked state requiring reconciliation.
- Compensating local correction after a rejected operation.

Do not treat a conflict as generic success and do not discard pending local work silently.

## Clock skew

Device clocks are not a sole source of truth for global ordering. Prefer server revisions, server timestamps, stable operation identifiers, and monotonic local sequencing. Time-based UI values may use device time, but synchronization correctness must tolerate skew.

## Server change feed and durable deletes

The database includes a server-assigned, monotonic, owner-scoped change feed (`server_change_feed` table, `change_seq` identity column).
- Every INSERT, UPDATE, or DELETE on the 17 synchronized tables (`profiles`, `areas`, `rooms`, `assets`, `device_details`, `pet_details`, `plant_details`, `safety_details`, `tags`, `asset_tags`, `asset_photos`, `maintenance_plans`, `maintenance_plan_metadata`, `maintenance_records`, `notification_inbox`, `user_settings`, `streaks`) atomically writes a change log entry via the `fn_log_server_change_feed()` trigger.
- Change-feed record keys are table-aware: `asset_id` for specialized details, `plan_id` for maintenance metadata, `key` for user settings, `user_id` for profiles, `asset_id|tag_id` for asset tags, and `id` for ordinary entities.
- The `change_seq` is server-generated and independent of client clocks or backdated/future-dated `updated_at` business timestamps.
- Hard deletes write durable `DELETE` records into `server_change_feed`, recording the entity type and deleted record ID.
- Row Level Security (RLS) restricts SELECT access to the authenticated user owning the records (`user_id = auth.uid()`), while direct client INSERT/UPDATE/DELETE access to `server_change_feed` is strictly revoked.
- Monotonic change sequences support owner-scoped keyset pagination (`user_id`, `change_seq`) and feed status verification (`get_user_change_feed_watermark`).
- The `fetch_user_change_feed(p_since_seq, p_limit)` RPC exposes the feed to authenticated clients. It captures an owner-scoped high-water sequence at scan start and pages only changes `change_seq <= high_water_seq` in strict monotonic order.
- `fetch_user_change_feed` returns opaque paging metadata (`next_seq`, `has_more`, `high_water_seq`), capability flags (`capability_version`, `capability_enabled`), and `resnapshot_required = true` when requested `p_since_seq` predates the minimum retained sequence (`min_retained_seq`).
- Capability discovery (`get_sync_feed_capability()`) allows server-controlled feature flagging and instant withdrawal without destroying historical change log entries.
- Dark validation (`validate_change_feed_parity()`) compares entity counts between canonical tables and net change feed records to verify zero omission/duplicate discrepancies under load before client adoption.

The cloud uses deliberate aliases for maintenance plan recurrence (`description`, `interval_count`, `interval_unit`) and streak summaries (`longest_streak`, `last_completion_date`). `SyncEntitySpec.remoteRenames` translates those names in both directions. Specialized detail and maintenance metadata columns otherwise match the Flutter/Drift payload names directly, preventing silent field loss during RPC creation or ordinary synchronization.

## Maintenance completion

Maintenance completion affects history, recurrence, due state, reminders, statistics, and potentially multiple devices. Completion operations require stable idempotency keys. Maintenance completion timestamps (`completedAt`, `expectedNextDueDate`, `previousDueDate`, `nextDueDate`) MUST be canonicalized to whole-second UTC precision (`date_trunc('second', ...)` in SQL, `canonicalSyncSecond` in Dart) across Drift SQLite, outbox JSON payloads, and Supabase Postgres to eliminate sub-second precision mismatch rejections. If the server rejects or resolves a duplicate, local reminder and recurrence state must reconcile to the accepted cloud result rather than advance permanently from an unaccepted local assumption.

## Media synchronization

Media requires coordination between local metadata, file availability, Storage objects, upload state, and deletion cleanup.

- **Upload Ledger & Finalize Saga**: Media uploads use an owner-scoped upload ledger (`media_staging_objects` table, `stage_media_upload` RPC) bound to deterministic private Storage paths under `{user_id}/assets/{asset_id}/{photo_id}.{ext}`. Finalization (`finalize_asset_photo_upload` RPC) validates owner, expected row revision, MIME type (`image/jpeg`, `image/png`, `image/webp`), size (<=10 MiB), SHA-256 digest, and Storage object existence before exposing the metadata row.
- **Required Client Saga**: The client (`SupabaseSyncGateway`) computes local file SHA-256 digests and uploads to deterministic owner paths under `{user_id}/assets/{asset_id}/{photo_id}.{ext}` before executing `stage_media_upload` and `finalize_asset_photo_upload`. The pre-launch backend cutover is mandatory; failure at any stage remains a retryable/visible sync failure and never falls back to an untracked direct upload. Asset and photo IDs stay text across Drift, Postgres, and the RPC boundary.
- **Durable Cleanup Ledger**: Replacing or deleting a photo enqueues the old object path into `media_cleanup_queue` transactionally before database mutation acknowledgement, guaranteeing zero lost orphan cleanup work.
- **Transactional Primary Photo Selection & Unique Constraint**: Primary asset photo selection uses the owner-authoritative `set_primary_asset_photo` RPC. The RPC sets `is_primary = true` on the target photo and clears peer photos (`is_primary = false`) for that asset in a single transaction. Partial unique index `idx_asset_photos_single_primary` on `asset_photos(user_id, asset_id) WHERE is_primary = true` enforces at most one primary photo per asset at the database level.
- Uploads and deletes must be retryable and idempotent.
- Metadata must not claim cloud availability before verification.
- Cleanup must not delete another account's object.
- Account deletion can suspend ordinary sync while allowing deletion-specific cleanup.
- Orphan cleanup should be bounded and observable without logging private object names.

## Retry and backoff

Retryable failures should use bounded exponential backoff with jitter and persistence where appropriate. Authorization, schema, ownership, and terminal validation errors should not spin indefinitely. User-visible state should distinguish offline waiting from protocol failure.

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
