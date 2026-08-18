# Backend Migrations and Edge Functions

## Migration policy

The repository lifecycle checkbox in `AGENTS.md` decides whether Supabase history is a disposable baseline or production history.

While Owntend remains pre-launch with zero users and zero production data, migrations are a **clean baseline definition**. Refactor, rename, consolidate, or remove obsolete baseline modules directly when that produces a simpler final schema. The complete baseline must still build successfully from an empty database and pass the full database test suite.

After launch, migration history becomes append-only production history. At that point, change behavior only through new forward migrations and preserve compatibility with deployed clients and live data.

Each migration should be:

- Transactional where supported.
- Explicit about ownership, constraints, indexes, defaults, and nullability.
- Direct and minimal in pre-launch baseline mode rather than retaining obsolete compatibility layers.
- Backward-compatible after launch when rollout order requires it.
- Accompanied by database tests.
- Reviewed for synchronization and account deletion.

## Migration workflow

### Pre-launch / zero-user

1. Inspect the complete baseline and the final executable schema contract.
2. Refactor the existing baseline modules directly when behavior has not shipped.
3. Remove duplicate replay migrations and obsolete patch-only modules.
4. Add or update RLS, RPC, constraint, denial, and authorization tests.
5. Start Supabase from an empty local database.
6. Run schema lint and the full pgTAP suite.
7. Inspect the final migration diff and documentation.
8. Merge only after canonical CI is green.
9. Rebuild the authorized hosted pre-launch project from exact current `main` through the protected reset workflow.
10. Re-run hosted migration, ACL, Advisor, and parity checks before enabling gated capabilities.

### After launch

1. Inspect all prior migrations affecting the objects.
2. Define the desired schema and compatibility window.
3. Create a new timestamped forward migration.
4. Add constraints, indexes, RLS, and RPC changes deliberately.
5. Add database tests for success and denial.
6. Run local lint and tests.
7. Inspect the generated database diff where available.
8. Document deployment order and recovery.
9. Apply to hosted environments only through an explicitly authorized protected process.

## Destructive pre-launch reset

A hosted reset is allowed only while the authoritative lifecycle checkbox in `AGENTS.md` remains unchecked and the maintainer has explicitly authorized the exact target and operation.

The protected `Deploy Supabase Migrations` GitHub Actions workflow exposes a `reset-prelaunch-database` operation. It requires:

- exact current `main` as `source_sha`;
- the exact protected Supabase project reference;
- confirmation `reset-prelaunch-zero-user`;
- the unchecked lifecycle marker in `AGENTS.md`;
- approval through the `production-supabase-migrations` environment.

The reset runs `supabase db reset --linked --no-seed`, then lists the resulting hosted migration history and requires a final `supabase db push --linked --dry-run` with no pending migration. The operation is intentionally destructive: disposable hosted Auth/test data and user-created database objects are rebuilt from the repository baseline.

Once the project is launched, this reset path must not be used. Use additive forward migrations and compatibility-preserving rollout instead.

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
- Effective RPC ACLs rather than relying on assumed default privileges.

## Edge Function inventory

### `delete-account`

Requires a valid JWT and protects destructive account cleanup. It verifies confirmation, recent session state, and a 32-byte recovery key; stores only SHA-256-derived recovery values; removes private media with retry handling; signs out sessions; deletes the Auth user; and records/returns a strict result suitable for client recovery.

### `account-deletion-status`

Recovers a deletion operation when the authenticated destructive response can no longer be trusted or retrieved. It validates the original recovery key and expected user ID, performs a hash- and subject-bound service-role lookup, can finalize an operation whose Auth user is already absent, and returns only strict completed, pending, temporary, or not-found states. It never treats a client user ID alone as authority.

### `admob-ssv-handler`

Receives Google Mobile Ads server-side verification callbacks. It validates provider request/signature data, associates an opaque claim with the intended account, prevents replay, and credits the wallet idempotently. The function is externally callable for provider callbacks and must not trust request identity without cryptographic and backend checks.

## Function engineering rules

- Prefer `SECURITY INVOKER` when ordinary grants plus RLS can enforce caller authority; reserve `SECURITY DEFINER` for operations that genuinely require elevated database privileges.
- For every `SECURITY DEFINER` function, set a safe `search_path`, derive identity from trusted session state, and grant execution only to the minimum role set.
- Treat each Data API function as an explicit ACL boundary. Supabase projects can retain automatic function grants, so every application function must issue post-definition `REVOKE` statements for `PUBLIC` and unintended API roles, then grant only the exact intended callers.
- Verify effective function ACLs in database tests and hosted Advisors before rollout.
- Never expose an arbitrary `p_user_id` argument on a client-callable privileged function when `auth.uid()` is the authorization boundary. Administrative cross-account inspection belongs to protected SQL or other operator-only tooling.
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

## Pre-launch consolidated baseline

The zero-user launch database is defined by the ordered baseline modules under `supabase/migrations/`:

1. [`20260815000001_core_schema.sql`](../../supabase/migrations/20260815000001_core_schema.sql): owner-scoped entities, initial sync/change-feed structures, Realtime publication, indexes, and RLS.
2. [`20260815000002_storage_and_media.sql`](../../supabase/migrations/20260815000002_storage_and_media.sql): private `user-media` storage, upload staging/finalization, cleanup, and primary-photo RPCs.
3. [`20260815000003_points_monetization.sql`](../../supabase/migrations/20260815000003_points_monetization.sql): points ledger, wallets, SSV verification, charged creation RPCs, and monetization authority.
4. [`20260815000004_task_completion_and_rpc.sql`](../../supabase/migrations/20260815000004_task_completion_and_rpc.sql): server-authoritative maintenance completion RPC foundation.
5. [`20260815000005_account_deletion_and_recovery.sql`](../../supabase/migrations/20260815000005_account_deletion_and_recovery.sql): account-deletion operation lifecycle, recovery, acknowledgement, and pruning.
6. [`20260815000006_profile_revision.sql`](../../supabase/migrations/20260815000006_profile_revision.sql): profile revision invariant and profile change-feed trigger.
7. [`20260815000007_completion_integrity.sql`](../../supabase/migrations/20260815000007_completion_integrity.sql): final maintenance completion/undo integrity and recurrence behavior.
8. [`20260815000008_asset_device_contract.sql`](../../supabase/migrations/20260815000008_asset_device_contract.sql): final asset/device field and RPC contract.
9. [`20260815000009_charged_operation_recovery.sql`](../../supabase/migrations/20260815000009_charged_operation_recovery.sql): hash-qualified charged-operation recovery and capability `1.2.0`.
10. [`20260815000010_change_feed.sql`](../../supabase/migrations/20260815000010_change_feed.sql): canonical 17-entity change-feed identity, typed `key_data`, durable delete keys, triggers, paging, and parity foundation.
11. [`20260815000011_change_feed_access.sql`](../../supabase/migrations/20260815000011_change_feed_access.sql): final feed protocol `1.0.1`, authenticated-only `SECURITY INVOKER` RPCs, `auth.uid()` account scope, explicit Data API ACL normalization, and trigger-only definer execution.

The former duplicate baseline replays and remediation-era forward patch files are intentionally absent. They represented audit history for an environment that had not launched, not a compatibility contract that Owntend needs to preserve.

The checked-in feed capability remains disabled. After the hosted database is rebuilt from this baseline, enablement still requires exact-main hosted verification: no pending migration drift, protocol `1.0.1`, zero malformed feed rows, effective feed RPC ACLs matching the baseline, no unresolved feed-related security Advisor findings, and parity success for every hosted account (or explicit evidence that the reset contains zero accounts).

## Deployment evidence

Record the exact source commit, hosted project reference, protected workflow run, operation selected, migration history, test results, Advisor results, ACL checks, parity results, and any required mobile release ordering. Source CI and a successful reset do not by themselves prove physical-device validation or authorize public release publication.
