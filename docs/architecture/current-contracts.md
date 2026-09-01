# Current contracts

## Purpose

This document describes Owntend's canonical pre-launch contracts. Owntend has
no production users or production data, so unpublished shapes are replaced
directly instead of being treated as compatibility promises.

## Version authorities

| Concern | Authority | Current contract |
| --- | --- | --- |
| Product version and Android build | [`pubspec.yaml`](../../pubspec.yaml) | not copied here; the authoritative version/build live in [`pubspec.yaml`](../../pubspec.yaml) |
| Local SQLite schema | `AppDatabase.currentSchemaVersion` | `1` |
| Backup archive and embedded database | backup manifest constants | `1` |
| Mobile/backend sync boundary | change-feed response contract | `1` |
| Native-ad platform channel | shared Dart/Kotlin contract assertion | `2` |
| VersionDeck manifest and cache contract | generic VersionDeck schema modules | `1` |
| Supabase application schema | [`20260821124930_initial_schema.sql`](../../supabase/migrations/20260821124930_initial_schema.sql) | one clean pre-launch baseline without a runtime marker table |

External API, Android SDK, ABI, PostgreSQL, SPDX, dependency, and file-format
versions remain governed by their external contracts.

## Domain and persistence contract

- An area belongs to the authenticated owner. Active area names are unique per
  owner without regard to case.
- A room has one required area. Active room names are unique within an area
  without regard to case.
- An asset has one required room. Deleting an area permanently deletes its room
  and asset subtree; ordinary user removal uses the existing archive workflow.
- Tags are unique per owner without regard to case.
- At most one photo is primary for an asset in SQLite and PostgreSQL.
- An enabled maintenance plan has a required next due date. Recurrence interval,
  priority, enum values, and bounded text are checked in both databases where
  the engines can express the same invariant.
- Each maintenance plan carries one `current_occurrence_id`. Each maintenance
  record captures the completed `occurrence_id`, server/local acceptance time,
  and IANA time-zone identity. `(plan_id, occurrence_id)` is unique, so an
  occurrence can be completed once even when devices race.
- Maintenance records contain only the fields implemented end to end by the
  domain, Drift, sync mapping, backup, UI, and PostgreSQL contracts.
- Cloud ownership is derived from `auth.uid()`. A client-supplied user ID is
  never an authorization source.
- Local-only operational tables include the outbox, shadows, checkpoints,
  hydration/account state, reminder schedule snapshots, notification
  reconciliation, search cache state, and local media cleanup work. They are not
  uploaded as domain entities.
- User-visible cloud notifications use `notification_inbox`. OS schedule state
  uses local reminder snapshots. There is no third notifications domain table.

## Synchronization contract

Owntend has one account-scoped sync engine:

1. `pullAuthoritativeSnapshot` performs first hydration and recovery from a
   retained-feed gap.
2. `pullChangeFeed` is the only incremental pull path.
3. Realtime events are invalidation hints and never authoritative payloads.
4. A feed entry contains its typed key, operation, sequence, and bounded
   canonical upsert payload or delete key. Applying a page and advancing its
   checkpoint is one local transaction.
5. A checkpoint never advances when any entry is malformed, unauthorized, or
   not applied. Replay is idempotent.
6. Outbox rows receive a database-assigned monotonic `local_sequence` and are
   dequeued in that stable order. Completion dependencies name the exact prior
   operation; a local mutation is removed only after the matching remote
   operation succeeds. An unknown entity or contract blocks visibly and is not
   discarded.
7. Server revision and durable local intent determine conflicts. Timestamps do
   not synthesize missing sequence or revision metadata.
8. Account binding, account epoch, deletion suspension, retry classification,
   backoff, maintenance-completion idempotency, and reminder reconciliation
   remain durable across restart.
9. Maintenance completion is a compare-and-set on the expected occurrence. The
   client sends intent, while the server computes recurrence from the locked
   canonical plan and returns one fixed response envelope. A losing device
   adopts the canonical plan/record and does not retry a stale projection.
10. Undo identifies the completed occurrence and expected successor occurrence;
    it rewinds only that exact latest state and is idempotent on replay.
11. A local-only restore remains durably unbound and paused across startup.
   Generic sync enable cannot resume it; explicit restore resume atomically binds
   the authenticated identity and creates the complete restore outbox intent
   before hydration may advance the account to active.

The mobile/backend response carries integer contract `1`. A different contract
is an incompatible failure; there is no capability table, rollout flag, second
incremental pull, or mid-page fallback.

## Local concurrency and reminders

- Editors for plans, areas, rooms, and assets use compare-and-set updates so a
  stale form cannot silently overwrite a newer local value. Removing a primary
  asset photo and selecting its replacement is one database transaction.
- Reminder snapshots are durable desired state. Schedule reconciliation is
  serialized, verifies the platform's pending identifiers before accepting a
  no-op, and removes only the exact reconciliation request version covered by a
  successful refresh. Snooze intent is persisted before scheduling so restart
  can replay it.

## Failure model

Authoritative operations return one of these closed outcomes:

- success with a validated value;
- absent, only where absence is a valid domain result;
- retryable transport or availability failure;
- authentication or authorization failure;
- incompatible contract or malformed remote data;
- permanent domain rejection.

Infrastructure exceptions retain a stable technical code and safe cause for
retry and diagnostics. Presentation maps failures to localized messages. Raw
PostgreSQL, Supabase, request, user-content, path, token, or SDK text is never
shown to users or sent to telemetry. An error is never converted into an empty
collection, `null`, disabled capability, or success.

## Media lifecycle

1. The authenticated client asks the server to prepare an idempotent stage.
2. The server records the stage before any Storage mutation and issues an
   immutable owner-scoped path plus bounded expected size and media type.
3. The client uploads without final-path overwrite semantics.
4. Finalization verifies stage ownership and stored object facts through a
   trusted server path before attaching the photo.
5. A durable cloud cleanup job owns every incomplete stage; a durable local
   cleanup row owns failed local-file deletion.

Uploads are limited to 10 MiB. Object paths outside the authenticated owner's
prefix or outside the app-owned local media directory are rejected.

## Account deletion retention

- Incomplete and acknowledged deletion operations have a maximum lifetime of
  seven days.
- Completed but unacknowledged recovery receipts have a maximum lifetime of 90
  days from completion.
- After expiry, the receipt is deleted. The already completed remote account
  deletion remains terminal and cannot be undone.
- Cleanup jobs use bounded retries and finite retention; scheduled pruning is a
  hosted operational requirement verified separately from local SQL tests.

## Supabase security contract

- Every retained table in an exposed schema has RLS enabled and only the
  minimum explicit Data API grants. Owner CRUD policies use explicit roles,
  `(select auth.uid())`, and both `USING` and `WITH CHECK` for updates.
- Anonymous, cross-user, ownership-transfer, and invalid-input denial are tested.
- Public functions are invoker wrappers unless elevated privileges are required.
  Definer implementations live in an unexposed private schema, have an empty
  fixed `search_path`, authorize explicitly, revoke `PUBLIC` execute, and grant
  only the intended role.
- Storage remains private and owner-scoped. Realtime publication contains only
  intended retained tables and remains an invalidation channel.
- Edge request bodies and fields are bounded before expensive processing.
  Replays are controlled by transactional idempotency, without rejecting valid
  Google callback retries.

## Configuration and composition

- Configuration examples define shape only and contain no credentials.
- One immutable validated application configuration is created at bootstrap and
  supplied through Riverpod.
- `main.dart` owns process bootstrap only. The app composition module owns
  provider wiring, router construction, one `AppDatabase`, and one account-
  scoped sync graph.
- Feature domains expose standalone libraries with explicit imports and do not
  share application-root private scope. Domain code is framework independent;
  presentation does not own Drift or Supabase clients.
- The public local-store and coordinator facades each expose one implementation.
  Focused account/outbox/remote/mutation/media store modules and
  run/push/post-ready/runtime coordinator modules divide responsibility without
  adding a second persistence or synchronization path.

## Verification boundaries

Local tests can prove source, generation, SQLite, disposable local Supabase,
Edge, Node, Flutter, and unsigned build behavior. Hosted Supabase advisors and
configuration, Sentry canaries, Google identity/ads, physical-device behavior,
protected signing/provenance, and publication require their named protected
environments and must not be inferred from local checks.
