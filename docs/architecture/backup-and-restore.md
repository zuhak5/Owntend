# Backup and Restore

## Goals

Owntend backups provide a user-controlled way to preserve and transfer local application data and supported media. Restore must protect existing data and treat every imported archive as untrusted.

The backup service and tests are authoritative for exact file names, limits, and schema handling.

## Format

The current design uses a versioned ZIP archive containing:

- A manifest describing format and database compatibility.
- The database payload or exported application data.
- Supported media files.
- Cryptographic hashes used to verify archive content.
- Metadata required to validate and stage restoration.

The format version is independent from the Flutter package version and the Drift schema version. Compatibility must be decided explicitly rather than inferred from application version alone.

Drift schema 25 removes the retired task-dependency metadata column. Opening a
schema-24 database restored from an older valid backup runs the forward
migration, discards only that retired link list, and preserves the task and its
remaining metadata. The backup ZIP format itself is unchanged.

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

Resource budgets enforced prior to decompression and extraction:
- Max compressed backup size: 256 MiB (`_maxBackupBytes`).
- Max aggregate extracted size: 512 MiB (`_maxExtractedBytes`).
- Max single entry size: 256 MiB (`_maxSingleEntryBytes`).
- Max entry count: 10,000 files (`_maxEntryCount`).
- Max compression ratio: 20x (`_maxCompressionRatio`) to reject ZIP bombs.
- Streaming verification: actual extracted byte size must match declared entry size.

Validation must occur before any file is written outside a controlled staging directory.

## Restore sequence

1. Open the archive without trusting names or metadata.
2. Validate the format version and required manifest fields. Before any destructive phase, write `validated` to the process-durable secure-storage journal (`RestoreJournalStore`). Production has no in-memory journal fallback.
3. Capture the immutable local account scope and whether the current fully hydrated account requires `enqueueRestoreSnapshot`; local-only or non-ready state records the pause disposition instead. This decision is journaled before services are suspended.
4. Enforce entry-count, per-entry, total-expanded-size, and compression limits.
5. Normalize every path and reject absolute, traversal, duplicate, or disallowed entries.
6. Verify hashes and expected file types.
7. Validate database/schema compatibility.
8. Create a pre-restore safety backup of the current state, hash it, and record `safetyBackupComplete`.
9. Acquire restore barrier: suspend `SyncCoordinator`, cancel WorkManager background jobs, and clear scheduled reminders. Write `servicesSuspended` phase.
10. Extract media into a private staging directory (`.restore-$token`), register the sidecar root in `SidecarRegistryStore`, and write `mediaStaged` phase.
11. Begin SQLite database transaction (`dbCommitStarted`), import table data, and record `dbCommitComplete`.
12. Atomically swap staged media directories (`.restore-$token` -> active path, previous -> `.previous-$token`), register `.previous-$token` sidecars in `SidecarRegistryStore`, and write `mediaSwapped` phase.
13. Make the recorded restore disposition durable (`pauseAfterLocalRestore` or `enqueueRestoreSnapshot`) and record `cloudIntentDurable` before terminal journal cleanup.
14. Rebuild derived runtime state, notifications, and search index (`derivedRebuilt`) where owned by their existing lifecycle.
15. Delete `.previous-$token` and `.restore-$token` media directories (`cleanupPending`), remove them from `SidecarRegistryStore`, and write `terminal` phase to clear journal. If deletion fails, update `SidecarRegistryStore` with `SidecarState.pendingCleanup` and error details for future startup sweepers or account deletion.
16. If interrupted, the process-level restore recovery gate runs before deferred account cleanup, cloud bootstrap, authentication hydration, realtime, or background sync. `RestoreJournalResolver` rolls back pre-DB-commit phases (< `dbCommitStarted`) or rolls forward post-commit phases (>= `dbCommitStarted`), fails closed on account-scope mismatch, and does not clear the journal until the recorded cloud disposition is durable. Recovery failure leaves startup blocked with retry. After successful resolution, `SidecarRegistryStore.sweepOrphans(...)` cleans terminal or legacy sidecars. A newer unsupported journal version also blocks startup.

## Compatibility

A restore change must define:

- Which backup format versions are accepted.
- Which Drift schema versions can be migrated.
- Whether newer archives are rejected or partially supported.
- How removed fields or media types are handled.
- Whether synchronized operational state is restored, reset, or reconciled.
- How account binding is handled when the archive and current session differ.

Do not restore stale account credentials or blindly reuse synchronization cursors from another account or environment.

## Synchronization interaction

Restore can introduce local state that differs from the cloud. The implementation must use an explicit policy for signed-in users, such as requiring sign-out, rebuilding outbox work, rehydrating, or reconciling entity revisions. Do not allow restored rows to bypass ownership and conflict rules.

## Media

Restore media only from validated paths and supported MIME/file types. Stage replacement before deleting current files. Metadata must not refer to files that failed verification or extraction.

## Automatic backup lifecycle

Automatic backup policy remains owned by `ZipBackupService`: enablement, the last successful backup timestamp, the durable 24-hour due interval, and exclusive backup/restore execution are checked there.

Lifecycle invocation is owned separately. After authenticated startup reaches the ready state, Owntend schedules the first automatic due-check after the ready frame so backup work cannot delay the first useful UI. Foreground resumes may request another due-check, but successful checks are throttled in memory for 15 minutes; the service's durable 24-hour policy remains authoritative for whether an archive is actually created. A failed due-check does not advance the foreground throttle, so the next eligible lifecycle trigger can retry.

Leaving authenticated-ready state resets lifecycle eligibility. Resume events before readiness therefore cannot start an automatic backup.

## Retention

Automatic backup retention should be bounded and deterministic. Safety backups created for restore must not be removed until restore is confirmed. User-exported backups outside application storage remain under user control.

## Privacy

Backups may contain nearly all Owntend content. Do not upload them automatically, include them in Sentry, or expose their paths or contents in logs. Account deletion cannot remove files the user exported to external storage or shared with another application.

## Tests

Cover valid current and historical archives, corrupted ZIPs, traversal paths, duplicate names, hash mismatch, oversized expansion, unsupported versions, insufficient storage, interrupted extraction, database migration failure, media replacement failure, rollback, retention, account mismatch, and synchronization restart.
