# Backend Migrations and Edge Functions

### Browser origin allowlists (WP-002)

`delete-account` and `account-deletion-status` allow browser origins
`https://owntend.app` plus development origins (`localhost:4173`,
`127.0.0.1:4173`) only when the runtime environment variable
`OWNTEND_FUNCTIONS_ENV` is set to a non-`production` value. Unset defaults to
production so hosted deployments fail closed; pgTAP/unit coverage asserts both
postures.

## Migration policy

The repository lifecycle checkbox in `AGENTS.md` decides whether Supabase history is a disposable baseline or production history.

While Owntend remains pre-launch, the eventual goal is a clean baseline. The current security remediation intentionally uses an ordered forward chain first so a previously deployed pre-launch project can be repaired without rewriting applied history. Those migration files are immutable on the preservation path. They may be folded into the initial migration only after hosted validation and a separately approved destructive `reset-prelaunch-database` operation.

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
2. Apply and validate the current forward chain without editing applied files.
3. Consolidate only after explicit reset approval and normalized forward-chain-versus-squashed schema/ACL comparison.
4. Add or update RLS, RPC, constraint, denial, and authorization tests.
5. Start Supabase from an empty local database.
6. Run schema lint and the full pgTAP suite.
7. Inspect the final migration diff and documentation.
8. Merge only after canonical CI is green.
9. Rebuild the authorized hosted pre-launch project from exact current `main` through the protected reset workflow.
10. Re-run hosted migration, ACL, Advisor, feed-parity, and integration checks before allowing a release to depend on the hosted baseline.

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
- Public API functions that require elevated internals remain `SECURITY INVOKER` wrappers rather than authenticated-executable `SECURITY DEFINER` functions in exposed schemas.
- Statement-stable RLS helpers such as `auth.uid()` and `current_setting()` use init-plan-safe `SELECT` wrapping when their result does not depend on the current row.

## Edge Function inventory

### `delete-account`

Requires a valid JWT and protects destructive account cleanup. It verifies confirmation, recent session state, and a 32-byte recovery key; stores only SHA-256-derived recovery values; removes private media with retry handling; signs out sessions; deletes the Auth user; and records/returns a strict result suitable for client recovery.

### `account-deletion-status`

Recovers a deletion operation when the authenticated destructive response can no longer be trusted or retrieved. It validates the original recovery key and expected user ID, performs a hash- and subject-bound service-role lookup, can finalize an operation whose Auth user is already absent, and returns only strict completed, pending, temporary, or not-found states. It never treats a client user ID alone as authority.

### `admob-ssv-handler`

Receives Google Mobile Ads server-side verification callbacks. It validates provider request/signature data, associates an opaque claim with the intended account, prevents replay, and credits the wallet idempotently. The function is externally callable for provider callbacks and must not trust request identity without cryptographic and backend checks.

## Function engineering rules

- Prefer `SECURITY INVOKER` when ordinary grants plus RLS can enforce caller authority; reserve `SECURITY DEFINER` for operations that genuinely require elevated database privileges.
- A client-callable operation that genuinely needs elevated database privileges must expose a minimal `SECURITY INVOKER` function in the Data API schema and keep its `SECURITY DEFINER` implementation in a non-exposed private schema. The private implementation still derives identity from trusted session state and receives only the minimum schema/function grants required by the wrapper.
- For every `SECURITY DEFINER` function, set a safe `search_path`, derive identity from trusted session state, and grant execution only to the minimum role set.
- Treat each Data API function as an explicit ACL boundary. Supabase projects can retain automatic function grants, so every application function must issue post-definition `REVOKE` statements for `PUBLIC` and unintended API roles, then grant only the exact intended callers.
- Verify effective function ACLs in database tests and hosted Advisors before rollout.
- Never expose an arbitrary `p_user_id` argument on a client-callable privileged function when `auth.uid()` is the authorization boundary. Administrative cross-account inspection belongs to protected SQL or other operator-only tooling.
- Validate method, content type, query/body schema, size, and required headers.
- Keep secrets in the Supabase function environment.
- Use bounded timeouts and retries for external or Storage work.
- Make repeated requests safe.
- Validate technical identifier formats against their real provider contracts. Native-ad event unit IDs use the canonical Google `ca-app-pub-<16 digits>/<10 digits>` shape; unknown properties and malformed identifiers remain rejected before ledger insertion.
- Return stable technical errors without leaking internals.
- Do not log tokens, signatures, direct identifiers, user content, signed URLs, or raw payloads.
- If Sentry is enabled for a function, use request-scoped capture only and report only genuine server failures. Do not attach JWTs, recovery keys, claim IDs, user IDs, raw callback query strings, or webhook payload bodies.
- Test malformed, unauthorized, replayed, expired, and partial-failure paths.

The server-only cleanup, recent-session, and AdMob settlement RPCs explicitly revoke execution from `PUBLIC`, `anon`, and `authenticated`, then grant only `service_role`. This remains necessary even when the function body also checks the service-role JWT because the Data API ACL must fail closed before invocation.

## Hosted Advisor gate

The protected `Audit Supabase Advisors` workflow queries both security and performance Advisors from exact current `main` and stores a sanitized report artifact. Advisor results are classified deliberately:

- `WARN`, `ERROR`, and unknown severities are blocking unless the documented auth-configuration title (`Leaked Password Protection Disabled`) is explicitly allowlisted. SECURITY DEFINER executability findings are never allowlisted.
- `INFO` findings are retained in the report as non-blocking evidence. In particular, an unused-index observation on a freshly reset zero-traffic database is not sufficient evidence that an index is unnecessary.
- Management API errors fail closed.

The public RPC surface keeps no elevated authority at the exposed layer: `20260826030000_public_rpcs_security_invoker.sql` converts the nine server-authoritative application RPCs into SECURITY INVOKER delegation wrappers, while their SECURITY DEFINER implementations remain in the unexposed `owntend_media_private` / `owntend_monetization_private` schemas serving `authenticated` and `service_role` callers. This clears splinter lints 0028/0029 by construction instead of by exception. Media-cleanup worker RPCs stay service-role-only per `20260826010000_harden_security_definer_execute_privileges.sql`. pgTAP `0023_api_security.test.sql` and `0031_rpc_execute_privileges.test.sql` pin that matrix.

Database-side pgTAP coverage independently locks the exposed RPC security mode, effective ACL boundary, RLS init-plan form, and required foreign-key indexes so the hosted Advisor check is not the only line of defense.

## Deno validation

Every deployable function owns an exact `deno.json` (no caret ranges) and its
own `deno.lock`; the shared `_shared` helpers are compiled through each
function's config and the root `deno.json` exists only for repository-wide
formatting and `_shared` tests. The backend, Android release, and endpoint
integration workflows enforce locked `deno fmt --check`, `deno check --frozen`,
and `deno test --frozen` commands for `admob-ssv-handler`, `delete-account`,
`account-deletion-status`, and `process-media-cleanup`. Passing them validates
committed source contracts only; it does not prove which revision or secrets
are deployed to a hosted project.

## Disposable backend integration lane

`npm run test:backend-integration` is the canonical database/Edge gate. It builds an
isolated disposable workspace (unique project id, shifted ports, CLI link state
never copied), starts a blank local stack that applies the complete ordered chain
migration, lints the schema, runs the full pgTAP suite against the blank
baseline, serves every configured Edge Function over real HTTP with a run-scoped
worker capability, executes `supabase/tests/integration/*.test.ts` through the
actual `/functions/v1/...` gateway, and tears everything down in every outcome.
Credentials stay in memory; nothing is printed. The lane refuses to target any
developer-started stack and can never reach a hosted project.

## Current pre-launch migration chain

The repository currently contains the initial schema, three earlier security/function corrections, and five remediation migrations in timestamp order. The remediation boundaries are:

1. authoritative entitlements, completion authorization, copy/move/type-change/history-restore RPCs;
2. media staging quotas/retry and stage-bound Storage policy;
3. explicit-user service parity RPC; and
4. final mutation grants and rejection of client-authored initial plans; and
5. explicit fail-closed Data API policies for the three private operational ledgers, clearing Advisor lint 0008 without granting API access.

The fourth remediation migration is a compatibility boundary: deploy the compatible Flutter build and convert retained journals/outbox work before applying it to an already-deployed environment. The fifth is an access-neutral security-visibility correction and can follow it directly. Fresh local environments replay the full chain. Documentation must describe this real chain until an operator explicitly approves the destructive pre-launch squash/reset. If approval is withheld, the forward chain remains canonical permanently.

The protected migration workflow also runs `npm run validate:supabase-parity` after a hosted operation. Before any database mutation, the pinned Supabase CLI uses the existing protected migration management token to require exactly one current default `sb_secret_...` project key. The key is resolved again only inside the parity step, masked immediately, and never persisted as a workflow output, artifact, repository secret, or application configuration. The validator enumerates Auth user IDs only in memory through the server-only Admin API, invokes `validate_change_feed_parity(p_user_id)` for each account, and uploads a sanitized report containing aggregate counts and account ordinals only. Zero Auth accounts is an explicit success; an Auth account without its required profile fails validation rather than disappearing from the evidence set.

## Deployment evidence

Record the exact source commit, hosted project reference, protected workflow run, operation selected, migration history, test results, Advisor results, ACL checks, parity results, and any required mobile release ordering. Source CI and a successful reset do not by themselves prove physical-device validation or authorize public release publication.
