# ADR 0001: Offline-First Local Database with Authenticated Supabase Synchronization

- Status: Accepted
- Date: August 4, 2026

## Context

Owntend manages information users need during ordinary household work, including when connectivity is unavailable or unstable. Requiring a network round trip for every asset or maintenance interaction would degrade reliability. At the same time, authenticated users expect recovery and multi-device synchronization.

The system must protect pending local work, account isolation, recurrence/completion correctness, media lifecycle, and conflict handling across retries and process restarts.

## Decision

Use Drift/SQLite as the immediate local working set and Supabase as the authenticated cloud system.

Local synchronized mutations are applied transactionally and recorded as durable outbox operations. A synchronization coordinator binds work to an authenticated account, pushes idempotent operations, pulls revisioned changes using cursors, stores remote shadows, reconciles conflicts, and treats realtime events as invalidation signals.

Authoritative RPC pushes distinguish `applied` from `terminalHandled`.
Well-formed terminal business outcomes are reconciled or retained as
failed-visible and do not abort hydration or later independent mutations.
Retryable infrastructure failures and run-wide authentication, account-scope,
permission, or schema failures still stop the run. Maintenance completion uses
a fixed versioned envelope and one safe stale-revision retry; malformed or
unknown contracts fail closed.

Protected server-authoritative behavior—ownership, point balances, reward verification, atomic charged operations, and globally coordinated revisions—remains in Supabase.

## Consequences

### Positive

- Core application behavior remains useful offline.
- UI reads do not depend on network latency.
- Local mutation intent can survive restart.
- Backend authority is retained for security- and integrity-sensitive operations.
- Realtime can improve freshness without becoming the sole delivery channel.

### Negative

- Schema changes span local and cloud representations.
- Conflict, retry, hydration, cursor, shadow, and account-binding logic add substantial complexity.
- Backup/restore and account deletion must coordinate with synchronization state.
- Testing requires multi-state and multi-device scenarios.

## Required invariants

- Never silently discard pending local work.
- Never attach one account's local data to another account.
- Never advance a cursor before local application succeeds.
- Never rely on device time alone for global ordering.
- Never treat realtime payloads as bypassing authenticated pull validation.
- Make externally retried operations idempotent.
- Reconcile maintenance completion and reminders after conflicts.
- Do not let one well-formed terminal RPC business outcome fail an otherwise
  healthy hydration run.
- Validate versioned authoritative-RPC envelopes before applying canonical
  rows, including ownership and relationship checks.

## Alternatives considered

### Cloud-first reads and writes

Rejected because network dependency would undermine the core household-maintenance workflow and make retries/user feedback more fragile.

### Periodic full-database replacement

Rejected because it would not preserve concurrent local work, revisions, or efficient synchronization.

### Realtime payloads as the primary replication protocol

Rejected because events can be delayed, duplicated, dropped, or reordered and do not replace durable cursor/revision semantics.

## References

- `docs/architecture/sync-protocol.md`
- Drift schema and synchronization tables
- `lib/src/core/sync/`
- Supabase synchronization migrations, RPCs, and tests
