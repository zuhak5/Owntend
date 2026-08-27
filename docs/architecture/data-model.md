# Data Model

## Scope

Owntend maintains both user-domain data and operational metadata. The Drift schema and Supabase migrations are authoritative; this document describes conceptual groups and review obligations rather than duplicating every column.

## Home organization

- Areas represent major parts of a home.
- Rooms belong to areas or the broader home organization.
- Item Type (`AssetType`) is the single classification for maintained things: device, pet, plant, safety, or general.
- Assets belong to rooms and may have tags, notes, photos, warranty data, and specialized details.
- Specialized records support device, pet, plant, and safety use cases.

Ownership must remain tied to the authenticated account in cloud storage. Local records must not be rebound silently between accounts.

## Maintenance

- Maintenance plans define title, recurrence, due state, and asset association.
- Maintenance history records completion events.
- Optional plan metadata includes task type, location label, estimated duration,
  required materials, reminder guidance, and sort order.
- Attachments and media can accompany relevant records.
- Reminder snapshots represent the last scheduling decision used to reconcile local notifications.
- Recommendation, timeline, health/readiness, warranty-alert, and streak models derive product insight from domain state.

Completion identifiers and recurrence calculations must remain idempotent across offline retries and multiple devices.

## User and application state

- User profile and preferences.
- Home location where configured.
- Notification settings and runtime state.
- Onboarding and feature settings.
- Search, statistics, and display preferences.
- Monetization consent and locally cached wallet/configuration state.

Sensitive session data belongs in secure storage rather than ordinary settings rows.

## Search derived state

The production-v1 Drift baseline includes durable local generation metadata for the FTS5 search cache. The singleton `search_index_state` row stores:

- `source_generation`: the generation of committed searchable authoritative data; and
- `indexed_generation`: the generation represented by the current `search_index` snapshot.

SQLite triggers increment `source_generation` after INSERT, UPDATE, or DELETE on every authoritative table whose values contribute to search: areas, rooms, assets, specialized asset-detail tables, tags and asset-tag links, asset-photo captions, and maintenance plans. The FTS5 table and generation row are derived local state, not synchronized user-domain authority.

`DriftSearchRepository` owns freshness. A query may use the existing FTS snapshot only when the generation state is structurally valid and both generations match. Otherwise the repository serializes a transactional full rebuild and advances `indexed_generation` only after the rebuilt snapshot succeeds. A failed rebuild therefore leaves a detectable generation mismatch; a later query, including after process restart, retries instead of knowingly returning stale results. Search UI routes do not own or preserve index correctness.

## Synchronization metadata

The local schema includes operational records such as:

- Outbox entries describing durable local mutation intent.
- Pull cursors used for incremental cloud reads.
- Remote shadows and revisions used for conflict detection and reconciliation.
- Hydration and synchronization runtime state.
- Account binding and cleanup state.
- Media upload/deletion cleanup work.
- Reminder reconciliation state.

These tables are part of the synchronization protocol, not disposable caches. Deleting or resetting them can lose local intent or attach data to the wrong account.

Search generation metadata is intentionally separate from synchronization metadata. Remote/hydration writes still touch the authoritative searchable tables, so the same database triggers invalidate FTS state even while outbox generation is suppressed.

## Cloud-only authority

Supabase is authoritative for:

- Authenticated ownership and cross-user isolation.
- Globally coordinated revisions or server timestamps.
- Point balances and debit operations.
- Verified reward claims and replay prevention.
- Protected account deletion status.
- Private media access policies.

Private Postgres technical tables also preserve authority and replay evidence:

- `owntend_monetization_private.maintenance_plan_entitlements` stores the monotonic zero/one paid entitlement and its provenance for each plan.
- `owntend_monetization_private.plan_economy_operations` stores idempotent task-move and asset-type-change charge results.
- `owntend_private.maintenance_history_restore_operations` stores exact restore success/conflict outcomes.
- `media_staging_objects.attempt` and `media_cleanup_queue` coordinate server-issued upload attempts and service-only deletion.

They are outside exposed schemas, have no authenticated table policies or privileges, use RLS as defense in depth, and cascade with `auth.users`/owned plans. They contain technical identifiers, timestamps, hashes, counts, cost/provenance state, and bounded conflict codes; they do not store wallet credentials or copy client-authored task bodies as economic provenance.

Cloud maintenance history is user-readable but not directly mutable. Completion, undo, and validated restore are the only mutation authorities. Cloud plan association and asset type are likewise protected columns changed only by the entitlement-aware RPCs.

The Flutter client may cache representations for UX, but it must not become the authority for these decisions.

## Media

Media can exist locally, in backup archives, and in private Supabase Storage. Metadata and object lifecycle must stay coordinated. Deletion and account cleanup should tolerate retries and partial failures without exposing another user's objects.

## Schema-change procedure

For every new or changed field:

1. Identify the local table and repository contract.
2. Decide whether the field synchronizes.
3. Define the cloud column, RPC, RLS, revision, and baseline behavior if applicable.
4. Define null/default semantics and database invariants.
5. Preserve the current Supabase forward remediation chain until a separately approved reset/squash; after launch, always add forward migration coverage.
6. Update serialization and generated code.
7. Update outbox/pull/shadow handling.
8. Update backup inclusion and compatibility.
9. Update deletion and privacy inventories.
10. Add focused repository, backend, synchronization, and UI tests.

The current Drift schema version is `1`. It directly contains the canonical domain, FTS generation/invalidation, sync/outbox/shadow/checkpoint, notification-reconciliation, and durable local-media-cleanup structures. There is no unpublished upgrade ladder, Category table, duplicate device-notification table, or compatibility field in the production-v1 baseline.

All static schema objects — tables, CHECK constraints, indexes, the FTS cache, and every sync/search trigger — are installed by one canonical creation path when a fresh database is created. `beforeOpen` performs only connection pragmas, baseline verification (a database that does not match the canonical v1 object inventory fails closed with an explicit error instead of being silently repaired), runtime lease recovery, and deliberate default seeding.

Structural invariants enforced by the schema itself include:

- Outbox operation/state/attempt/generation domains (`upsert`/`delete` trigger operations plus the durable `execute` completion journal; states `pending`, `inFlight`, `conflictRecovery`, `failedVisible`, `conflict`; attempts use `-1` as the terminal sentinel; generations start at 1).
- Cursor sequence/generation domains and singleton runtime/account rows with all-or-nothing lease pairing.
- Conflict resolution and notification-reconciliation reason domains.
- Retry-ready composite indexes for outbox dequeue, sync/local media cleanup, and reminder reconciliation; query plans are asserted by test.

### Upgrade story and timestamp convention (WP-008, F-008)

The v1 baseline is the launch contract. `beforeOpen` deliberately rejects any
database that does not match the canonical object inventory
(`StateError` naming the missing objects plus "clear app storage" guidance);
the startup bootstrap surfaces this as a localized, unrecoverable-database
screen (`OwntendStartupFailure(databaseUnrecoverable: true)`).

- **Through launch:** no `onUpgrade` ladder exists. Any schema change is made
  directly in the v1 baseline (`schemaVersion` stays `1`) because zero devices
  carry an older file. `test/database_baseline_rejection_test.dart` pins the
  rejection contract.
- **First post-launch schema change (trigger):** bump `currentSchemaVersion`,
  add an `onUpgrade` step from the previously shipped version, extend
  `test/database_schema_test.dart` with from-fixture coverage for every shipped
  version, and coordinate the change with the backup container format and sync
  payload contracts in the same release.
- **Timestamps:** all synced timestamps use second precision
  (`canonicalSyncSecond` in `maintenance_repository.dart`; SQLite triggers use
  `strftime('%s','now')`). Never mix millisecond values into synced columns.

## Indexing and constraints

Use database constraints for invariants that must hold independently of Flutter. Add indexes based on real query and synchronization access patterns. Review uniqueness together with soft deletion, account ownership, retries, and idempotency.

FTS correctness is generation-bound: authoritative searchable mutations dirty the index at the database boundary, and queries restore freshness before returning results. Force rebuild remains a recovery path for missing or malformed derived search storage.

## Deletion

Distinguish:

- Product-level trash or soft deletion.
- Permanent domain deletion.
- Media cleanup.
- Sign-out cleanup.
- Full account deletion.
- External backup files that remain outside application control.

A deletion change is incomplete until all relevant local, cloud, media, sync, backup, notification, and diagnostic state is considered.

### Task classification and health scoring

Maintenance plans do not persist an independent health/category classifier. Every plan is linked to an item, and task classification is derived from that item's `AssetType` (`device`, `pet`, `plant`, `safety`, or `general`). Cleaning is task/activity semantics (for example, task type/title/instructions); it is never an Item Type.

Weighted health-score normalization uses the linked Item Type with the preserved weights Safety 30, Pet 25, Device 20, and Plant 15. `AssetType.general` is intentionally excluded from both the weighted numerator and denominator because the former `other` Health Group was unweighted. There is no approved General weight, and Cleaning's former weight is not reused for General.
