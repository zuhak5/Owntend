# Data Model

## Scope

Owntend maintains both user-domain data and operational metadata. The Drift schema and Supabase migrations are authoritative; this document describes conceptual groups and review obligations rather than duplicating every column.

## Home organization

- Areas represent major parts of a home.
- Rooms belong to areas or the broader home organization.
- Categories classify maintained things.
- Assets belong to rooms/categories and may have tags, notes, photos, warranty data, and specialized details.
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

Drift schema 2 adds durable local generation metadata for the FTS5 search cache. The singleton `search_index_state` row stores:

- `source_generation`: the generation of committed searchable authoritative data; and
- `indexed_generation`: the generation represented by the current `search_index` snapshot.

SQLite triggers increment `source_generation` after INSERT, UPDATE, or DELETE on every authoritative table whose values contribute to search: areas, rooms, categories, assets, specialized asset-detail tables, tags and asset-tag links, asset-photo captions, and maintenance plans. The FTS5 table and generation row are derived local state, not synchronized user-domain authority.

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

The Flutter client may cache representations for UX, but it must not become the authority for these decisions.

## Media

Media can exist locally, in backup archives, and in private Supabase Storage. Metadata and object lifecycle must stay coordinated. Deletion and account cleanup should tolerate retries and partial failures without exposing another user's objects.

## Schema-change procedure

For every new or changed field:

1. Identify the local table and repository contract.
2. Decide whether the field synchronizes.
3. Define the cloud column, RPC, RLS, revision, and migration behavior if applicable.
4. Define existing-row conversion and null/default semantics.
5. Add Drift migration and migration tests.
6. Update serialization and generated code.
7. Update outbox/pull/shadow handling.
8. Update backup inclusion and compatibility.
9. Update deletion and privacy inventories.
10. Add focused repository, backend, synchronization, and UI tests.

The current Drift schema version is 2. Schema 2 adds only the local derived search-generation state and its invalidation triggers; no Supabase schema or synchronized wire contract changes with that version bump.

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
