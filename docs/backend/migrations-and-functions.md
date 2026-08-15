# Backend Migrations and Edge Functions

## Migration policy

Supabase SQL migrations become ordered, append-only production history once they may have been applied outside a disposable local environment. While the repository lifecycle checkbox remains pre-launch with zero users, the consolidated baseline may be reconstructed directly and must be verified by a fresh local reset. After launch, change behavior only through a new forward migration.

Each migration should be:

- Transactional where supported.
- Idempotent only where repeated execution is intentionally safe.
- Explicit about ownership, constraints, indexes, defaults, and nullability.
- Backward-compatible with the currently released mobile client when rollout order requires it.
- Accompanied by database tests.
- Reviewed for synchronization and account deletion.

## Migration workflow

1. Inspect all prior migrations affecting the objects.
2. Define the desired schema and compatibility window.
3. Write a new timestamped migration.
4. Add constraints and indexes deliberately.
5. Add or update RLS policies.
6. Add database tests for success and denial.
7. Run local lint and tests.
8. Inspect the generated database diff where available.
9. Document deployment order and recovery.
10. Apply to hosted environments only through an explicitly authorized process.

## Destructive changes

The repository lifecycle checkbox in `AGENTS.md` controls the migration strategy. In the current pre-launch state, remove obsolete baseline structures directly instead of adding compatibility layers. The expand-and-contract sequence below applies after launch or whenever a migration may already hold production data.

Avoid dropping columns, tables, policies, or functions in the same rollout that removes client use. Prefer expand-and-contract:

1. Add the new representation.
2. Deploy compatible backend behavior.
3. Release clients that write/read the new representation.
4. Backfill and verify.
5. Stop old writes.
6. Remove obsolete structures in a later reviewed migration.

## Database tests

Test:

- Authenticated owner success.
- Cross-user denial.
- Anonymous denial.
- Invalid input and boundary conditions.
- Constraint enforcement.
- Idempotent duplicate behavior.
- Stale revision or conflict behavior.
- Account deletion cleanup.
- Point and reward conservation where applicable.

## Edge Function inventory

### `delete-account`

Requires a valid JWT and protects destructive account cleanup. It verifies confirmation, recent session state, and a 32-byte recovery key; stores only SHA-256-derived recovery values; removes private media with retry handling; signs out sessions; deletes the Auth user; and records/returns a strict result suitable for client recovery.

### `account-deletion-status`

Recovers a deletion operation when the authenticated destructive response can no longer be trusted or retrieved. It validates the original recovery key and expected user ID, performs a hash- and subject-bound service-role lookup, can finalize an operation whose Auth user is already absent, and returns only strict completed, pending, temporary, or not-found states. It never treats a client user ID alone as authority.

### `admob-ssv-handler`

Receives Google Mobile Ads server-side verification callbacks. It validates provider request/signature data, associates an opaque claim with the intended account, prevents replay, and credits the wallet idempotently. The function is externally callable for provider callbacks and must not trust request identity without cryptographic and backend checks.

## Function engineering rules

- Validate method, content type, query/body schema, size, and required headers.
- Keep secrets in the Supabase function environment.
- Use bounded timeouts and retries for external or Storage work.
- Make repeated requests safe.
- Return stable technical errors without leaking internals.
- Do not log tokens, signatures, direct identifiers, user content, signed URLs, or raw payloads.
- If Sentry is enabled for a function, use request-scoped capture only and report only genuine server failures. Do not attach JWTs, recovery keys, claim IDs, user IDs, raw callback query strings, or webhook payload bodies.
- Test malformed, unauthorized, replayed, expired, and partial-failure paths.

## Deno validation

The backend and Android release workflows enforce locked `deno fmt --check`, `deno check --frozen`, and `deno test --frozen` commands for `admob-ssv-handler`, `delete-account`, and `account-deletion-status`. Passing them validates committed source contracts only; it does not prove which revision or secrets are deployed to a hosted project.

## Baseline consolidated migrations

For the V1 zero-user production launch, the database is defined by 5 clean baseline SQL migrations under `supabase/migrations/`:

1. [`20260815000001_core_schema.sql`](../../supabase/migrations/20260815000001_core_schema.sql): Core owner-scoped entities, client-aligned specialized detail and maintenance metadata fields, sync revisions, table-aware change-feed triggers, the 17-table Realtime publication contract, relationship indexes, and RLS.
2. [`20260815000002_storage_and_media.sql`](../../supabase/migrations/20260815000002_storage_and_media.sql): `user-media` private storage bucket, storage RLS, owner-scoped upload ledger, text-ID upload finalization, and primary photo RPCs.
3. [`20260815000003_points_monetization.sql`](../../supabase/migrations/20260815000003_points_monetization.sql): Points ledger, wallets, reward claims, transactions, AdMob SSV verification, charged creation RPCs (`create_task_with_point_debit`, 0-point free `create_asset_with_point_debit`, and `get_charged_operation_status` capability `1.1.0`), direct charged-plan insertion protection, and advisory locking (`pg_advisory_xact_lock`).
4. [`20260815000004_task_completion_and_rpc.sql`](../../supabase/migrations/20260815000004_task_completion_and_rpc.sql): Server-authoritative `complete_maintenance_task` RPC with canonical timestamps, v1/v2 payload compatibility, and causal ordering.
5. [`20260815000005_account_deletion_and_recovery.sql`](../../supabase/migrations/20260815000005_account_deletion_and_recovery.sql): Account deletion operation lifecycle, multi-stage recovery, acknowledgement protocol, and scheduled pruning.

## Deployment evidence

Record migration identifiers, function versions/source commits, local test results, hosted target, deployment operator, compatibility assumptions, and any required mobile release ordering.
