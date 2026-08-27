# Backup and Restore

## Restore epoch ownership and journal terminality (WP-005)

`OwntendBackupService` accepts an `onRestoreCommit` callback and fires it
exactly once per verified restore, after the commit marker, media activation,
cloud intent, status record, and cleanup are all durable — it is the service's
last action because the epoch bump may dispose its database connection. The
provider layer (`app_providers.dart`) owns the single epoch publication;
`databaseRestoreEpochProvider.bump()` no longer lives in the backup screen, so
every completion path rebuilds dependent streams.

Post-restore outbox requeue respects user decisions: `enqueueRestoreSnapshot`
clears backoff only for retryable states (`pending`, `inFlight`,
`conflictRecovery`); `failedVisible` and `conflict` rows are never resurrected.
Staged media activation is implemented once, in
`restore_journal.activateStagedMediaGenerations` (with pre-activation failpoint
and previous-backup sidecar hooks); the backup service delegates to it.

## Goals

Owntend backups provide a user-controlled way to preserve and transfer local application data and supported media. Restore must protect existing data and treat every imported archive as untrusted.

The backup service and tests are authoritative for exact file names, limits, and schema handling.

## Format

Backups are versioned, authenticated, streaming containers named `*.owntend-backup`. There is no plaintext ZIP format and no legacy reader: pre-launch had zero users, so no compatibility path exists.

A container is a 52-byte plaintext header (magic `OWNTDBK1`, KDF/cipher identifiers, Argon2id salt and parameters, chunk size, base nonce, and an authenticated key-guard class) followed by AEAD frames. Every frame is AES-256-GCM encrypted with a per-frame nonce derived from the base nonce and authenticated against the full header; any tampering with header or payload fails authentication before data is used. The first frame is always the JSON manifest; remaining frames are the database snapshot followed by each media entry in manifest order.

Key protection has two classes, recorded in the header:

- **User passphrase** (manual exports): derived with Argon2id using a per-file random salt and profiled parameters. The passphrase is never stored, logged, or derived from account state.
- **Device key** (automatic and pre-restore safety exports): a random 32-byte key generated on first use and kept only in platform secure storage. These backups open only on the same device installation.

The manifest declares format version, schema version, total payload bytes, and per-entry sizes with SHA-256 hashes. The format version is independent from the Flutter package version and the Drift schema version. Compatibility must be decided explicitly rather than inferred from application version alone.

Production v1 accepts backup format `1` with database schema `1` only. `search_index_state` and synchronization runtime tables are not imported as user-domain authority: importing authoritative searchable tables fires local invalidation triggers, leaving search dirty until `DriftSearchRepository` rebuilds the FTS snapshot on the next query or explicit recovery rebuild.

## Export sequence

1. Resolve the destination selected by the user or application retention policy.
2. Create a consistent database snapshot.
3. Enumerate allowed media from controlled roots.
4. Build the manifest and content hashes.
5. Write the archive to a temporary path.
6. Verify the completed archive.
7. Move it atomically where supported.
8. Apply automatic-backup retention without deleting the active or safety archive.

Partial archives must not be presented as successful backups.

## Import threat model

An imported archive can contain:

- Absolute or parent-traversal paths.
- Symlinks or path aliases.
- Excessive entry counts.
- Highly compressed data intended to exhaust storage or memory.
- Duplicate paths.
- Corrupted or misleading manifests.
- Hash mismatches.
- Unsupported format or database versions.
- Unexpected file types or media.
- Malformed database content.

Resource budgets enforced before allocation and during streaming:
- Max container size: 256 MiB (`_maxBackupBytes`).
- Max aggregate payload: 512 MiB (`_maxExtractedBytes`), counted while decrypting.
- Max single entry size: 256 MiB (`_maxSingleEntryBytes`).
- Max entry count: 10,000 entries (`_maxEntryCount`); max manifest: 128 KiB.
- KDF parameter caps for untrusted headers (memory, iterations, parallelism) are enforced before key derivation, preventing KDF denial-of-service.
- Per-entry SHA-256 verification happens incrementally while streaming into staging; written bytes must equal declared sizes exactly.
- Trailing frames beyond the declared payload length are rejected as tampering.

Validation must occur before any file is written outside a controlled staging directory.

## Restore sequence

1. Open the archive without trusting names or metadata.
2. Validate the format version and required manifest fields. Before any destructive phase, write `validated` to the process-durable secure-storage journal (`RestoreJournalStore`). Production has no in-memory journal fallback.
3. Capture the immutable local account scope and whether the current fully hydrated account requires `enqueueRestoreSnapshot`; local-only or non-ready state records the pause disposition instead. This decision is journaled before services are suspended.
4. Enforce entry-count, per-entry, total-expanded-size, and compression limits.
5. Normalize every path and reject absolute, traversal, duplicate, or disallowed entries.
6. Verify hashes and expected file types.
7. Require backup format `1` and schema `1`; reject any other version before import.
8. Create a pre-restore safety backup of the current state, hash it, and record `safetyBackupComplete`.
9. Acquire restore barrier: suspend `SyncCoordinator`, cancel WorkManager background jobs, and clear scheduled reminders. Write `servicesSuspended` phase.
10. Extract media into a private staging directory (`.restore-$token`) **without touching canonical folders**, register the sidecar root in `SidecarRegistryStore`, and write `mediaStaged` phase. Canonical media is never renamed before the database commit is proven, so a crash can never pair the old database with new media.
11. Begin the SQLite import transaction (`dbCommitStarted` journal phase is advisory only) and import table data. Inside that same transaction, write the restore-generation commit marker (`settings.restore_generation = journalId`). Because SQLite commits atomically, the marker exists only if the transaction actually committed; no post-commit journal write is required for proof. Record `dbCommitComplete` after the commit returns.
12. Activate staged media per root (`photos`, `profile`, `cloud_media`): rename live -> `.previous-$token`, then staged -> live. Each rename pair is idempotent, so a crash between roots leaves states recovery can distinguish by which directories exist. Record `mediaActivated`.
13. Make the recorded restore disposition durable (`pauseAfterLocalRestore` or `enqueueRestoreSnapshot`) and record `cloudIntentDurable` before terminal journal cleanup.
14. Rebuild derived runtime state and notifications where owned by their lifecycle. Search is generation-bound: restored authoritative rows invalidate the FTS snapshot automatically, and the repository rebuilds it before a subsequent search can return results.
15. Delete `.previous-$token` and `.restore-$token` media directories (`cleanupPending`), remove them from `SidecarRegistryStore`, and write `terminal` phase to clear journal. If deletion fails, update `SidecarRegistryStore` with `SidecarState.pendingCleanup` and error details for future startup sweepers or account deletion.
16. If interrupted, the process-level restore recovery gate runs before deferred account cleanup, cloud bootstrap, authentication hydration, realtime, or background sync. `RestoreJournalResolver` determines truth by reading `settings.restore_generation`: when it equals the active journal id the SQLite transaction committed and recovery rolls forward (finishing partial media activations idempotently); otherwise recovery rolls back (deleting only staged copies and restoring any `.previous-$token` generation). Journal phases are never used to infer commit status. Recovery fails closed on account-scope mismatch, does not clear the journal until the recorded cloud disposition is durable, rejects retired journal formats without a compatibility ladder, and blocks startup on newer unsupported versions. After successful resolution, `SidecarRegistryStore.sweepOrphans(...)` cleans terminal or unregistered orphan sidecars.

Failpoint injection (`RestoreFailpoints`) covers every journal write, the database begin/commit boundary, each per-root media activation, and the previous-generation cleanup boundary; tests assert that every injected crash converges to exactly the complete old or complete new database/media generation. The local bounded-memory sampling test records peak-RSS evidence on the host; the physical min-spec low-memory benchmark remains an explicit launch blocker.

## Compatibility

A restore change must define:

- Which backup format versions are accepted.
- Which Drift schema versions can be migrated.
- Whether newer archives are rejected or partially supported.
- How removed fields or media types are handled.
- Whether synchronized operational state is restored, reset, or reconciled.
- How account binding is handled when the archive and current session differ.

Do not restore stale account credentials or blindly reuse synchronization cursors from another account or environment.

Derived caches and local generation markers do not become user-domain backup authority merely because they exist inside the SQLite file snapshot. Import remains constrained to the service's canonical table allowlist, and derived search state is regenerated from authoritative imported rows.

## Synchronization interaction

Restore can introduce local state that differs from the cloud. The implementation must use an explicit policy for signed-in users, such as requiring sign-out, rebuilding outbox work, rehydrating, or reconciling entity revisions. Do not allow restored rows to bypass ownership and conflict rules.

For the current signed-in restore path, ordinary synchronized entities are requeued through their normal contracts, but maintenance history is never emitted as direct table CRUD. `enqueueRestoreSnapshot` groups records by existing plan into deterministic batches of at most 100 and creates `maintenance_history_restore` execute intents. Before sending, the client reads the canonical cloud plan revision and snapshot. The server inserts exact missing rows, accepts exact replay, retains unrelated cloud rows, and persists either `plan_snapshot_conflict` or `history_record_conflict` when data diverges. A conflicted batch commits no history rows and remains visible/durable across restart. Previously pending generic history mutations are converted when restore-derived; unsupported mutations become `server_authority_required` conflicts rather than being discarded.

This merge does not authenticate the historical truth of an imported archive. It only validates the current owner, plan match, bounded structure, timestamp precision, uniqueness, and exact replay. Product support must not describe restored history as independently verified.

## Media

Restore media only from validated paths and supported MIME/file types. Stage replacement before deleting current files. Metadata must not refer to files that failed verification or extraction.

## Automatic backup lifecycle

Automatic backup policy remains owned by `OwntendBackupService`: enablement, the last successful backup timestamp, the durable 24-hour due interval, and exclusive backup/restore execution are checked there.

Lifecycle invocation is owned separately. After authenticated startup reaches the ready state, Owntend schedules the first automatic due-check after the ready frame so backup work cannot delay the first useful UI. Foreground resumes may request another due-check, but successful checks are throttled in memory for 15 minutes; the service's durable 24-hour policy remains authoritative for whether an archive is actually created. A failed due-check does not advance the foreground throttle, so the next eligible lifecycle trigger can retry.

Leaving authenticated-ready state resets lifecycle eligibility. Resume events before readiness therefore cannot start an automatic backup.

## Retention

Automatic backup retention should be bounded and deterministic. Safety backups created for restore must not be removed until restore is confirmed. User-exported backups outside application storage remain under user control.

## Privacy

Backups may contain nearly all Owntend content. Do not upload them automatically, include them in Sentry, or expose their paths or contents in logs. Account deletion cannot remove files the user exported to external storage or shared with another application.

## Tests

Cover valid current containers, corrupted files, foreign formats (including ZIPs), traversal paths, duplicate names, hash mismatch, oversized expansion, unsupported versions, insufficient storage, interrupted extraction, database migration failure, media replacement failure, rollback, retention, account mismatch, synchronization restart, and derived-state invalidation after restore.
