# Supabase Backend

## Responsibilities

Supabase provides Owntend's authenticated cloud layer:

- Google-backed Supabase Auth sessions.
- Postgres domain and operational tables.
- Row Level Security and ownership enforcement.
- RPCs for atomic or protected operations.
- Realtime invalidation.
- Private `user-media` Storage.
- Edge Functions for account deletion, deletion-status recovery, and AdMob server-side verification.

The committed local configuration is `supabase/config.toml`. The migration
directory contains one clean pre-launch baseline,
[`20260821124930_initial_schema.sql`](../../supabase/migrations/20260821124930_initial_schema.sql).
Database tests are under `supabase/tests/database/`. Local validation must use
explicit local targets; a linked hosted project is never reset, pushed, or
deployed without separate authorization for that exact operation and target.

## Local environment

Install dependencies and start the stack:

```powershell
npm ci
npx supabase start
```

Use the API, database, Studio, mail, and analytics ports declared in `supabase/config.toml`. Development configuration must point to that API endpoint or an emulator-accessible equivalent.

Validate:

```powershell
npm run supabase:lint
npm run supabase:test
```

Do not link to or mutate a hosted project during ordinary local validation.

## Pre-launch hosted reset

The zero-user launch baseline is validated by starting Supabase from an empty local database. When an already-linked hosted project is disposable and the maintainer explicitly authorizes a reset, use the protected `Deploy Supabase Migrations` workflow rather than direct SQL or an unprotected CLI invocation.

The `reset-prelaunch-database` operation requires exact current `main`, the exact protected project reference, confirmation `reset-prelaunch-zero-user`, the unchecked lifecycle marker in `AGENTS.md`, and approval through the `production-supabase-migrations` environment. It runs `supabase db reset --linked --no-seed`, then verifies hosted migration history and requires a final dry-run with no pending migrations.

This operation destroys disposable hosted Auth/test data and user-created database state. It is a pre-launch-only mechanism and must not be used once the project has active users or production data.

## Authentication

The shipped application uses Google-backed Supabase authentication. The local
Supabase configuration also enables disposable email sign-up solely so the
loopback integration suite can create two isolated test identities without
external OAuth. Production authentication behavior still depends on correctly
configured Google OAuth clients, package identity, redirects, and protected
Supabase environment values; the email test path is not exposed by Flutter.

Backend authorization must derive ownership from the authenticated JWT identity rather than trusting a user ID supplied by Flutter.

## Database and RLS

Every user-owned table should have explicit RLS policies for intended owner operations and denial tests for anonymous and cross-user access. Private operational ledgers are not exposed to Data API roles: they retain revoked schema/table privileges and explicit `FOR ALL` false policies for `anon` and `authenticated`, making the fail-closed boundary visible to database tests and Supabase Advisor lint 0008 without granting access. Constraints and indexes should enforce invariants independently of client behavior.

Generic synchronization also uses column-level UPDATE privileges. Every one of
the 17 synchronized tables has table-wide authenticated UPDATE revoked, and
only these columns are granted; the executable sources of truth are
[`SyncEntitySpec.updatableLocalColumns`](../../lib/src/core/sync/sync_dtos.dart)
and the [single initial migration](../../supabase/migrations/20260821124930_initial_schema.sql):

| Entity | Authenticated generic UPDATE columns |
| --- | --- |
| Profile | `nickname` |
| Area | `name`, `kind`, `sort_order`, `archived_at` |
| Room | `area_id`, `name`, `room_type`, `notes`, `sort_order`, `archived_at` |
| Asset | `name`, `room_id`, `placement`, `notes`, `purchase_date`, `archived_at` |
| Device detail | `brand`, `model`, `serial_number`, `power_source`, `warranty_until`, `manual_url`, `consumable` |
| Pet detail | `species`, `breed`, `birth_date`, `microchip_id`, `vet_name`, `vet_phone`, `feeding_notes`, `medical_notes` |
| Plant detail | `species`, `sunlight`, `watering_interval_days`, `pot_size`, `last_repotted_at`, `toxicity_notes` |
| Safety detail | `safety_type`, `installed_at`, `expires_at`, `battery_type`, `test_interval_days` |
| Tag | `name` |
| Asset tag | None; insert/delete only |
| Asset photo | None; protected media RPCs only |
| Maintenance plan | `title`, `instructions`, `recurrence_interval`, `recurrence_unit`, `priority`, `next_due_date`, `reminder_days_before`, `is_enabled`, `archived_at` |
| Maintenance-plan metadata | `task_type`, `location_label`, `estimated_duration_minutes`, `required_materials_json`, `reminder_recommendation`, `sort_order` |
| Maintenance record | None; completion/undo/restore RPCs only |
| Notification inbox | `read_at` |
| User setting | `value` |
| Streak | `current_streak`, `longest_streak`, `last_completion_date` |

Ownership columns, primary/composite keys, `created_at`, `updated_at`, and
`revision` are never client-updatable. Owner RLS retains both `USING` and `WITH
CHECK`; the metadata trigger remains responsible for the server timestamp and
revision increment. Exact pgTAP matrix comparison prevents a future table
grant or stale column grant from widening this boundary.

Review `SECURITY DEFINER` functions carefully:

- Set a safe `search_path`.
- Authenticate and authorize inside the function.
- Minimize privileges and returned data.
- Validate inputs and bound resource use.
- Make externally retried mutations idempotent.

Prefer `SECURITY INVOKER` whenever existing table grants and RLS can enforce the caller's authority. If a client operation genuinely requires elevated database privileges, keep the privileged `SECURITY DEFINER` implementation in a non-exposed private schema and expose only a minimal authenticated `SECURITY INVOKER` wrapper through `public`. Existing Supabase projects can retain automatic Data API function grants, so application migrations must not rely on default-privilege changes alone: after creating or replacing each exposed function, explicitly revoke execution from `PUBLIC` and every unintended API role, then grant only the minimum intended callers. Database tests and hosted Advisors must verify those effective ACLs before rollout.

Ownership policies use statement-stable helper caching where safe: `(select auth.uid())` replaces per-row `auth.uid()` calls, and statement-constant `current_setting()` checks are wrapped the same way. Row-dependent authorization helpers are not cached because doing so could change authorization semantics.

Never disable RLS to resolve an application error.

The pre-launch cloud schema follows the fields emitted by Flutter for device,
pet, plant, and safety details plus maintenance-plan metadata. Maintenance plan
fields use canonical `instructions`, `recurrence_interval`, and
`recurrence_unit` names on both sides. Only streaks retain cloud aliases
(`longest_streak`, `last_completion_date`);
`SyncEntitySpec.remoteRenames` is the executable client mapping. Plan insertion
requires an existing private entitlement, direct plan reparenting and
asset-type mutation are not granted, and maintenance history is read-only
through table access. Completion, undo, economy changes, and validated restore
use dedicated invariant-preserving RPCs.

`complete_maintenance_task` accepts one exact occurrence-intent request and
exposes response contract 1. All non-exception branches return one fixed
ten-field envelope containing version, status, retryability, bounded conflict
reason, canonical revision/result fields, nullable reward eligibility token,
and nullable plan and record rows. The server locks the canonical plan and
computes recurrence; it does not accept a client next-due projection. A private
security-invoker helper builds the envelope and is
not executable by Data API roles. The authenticated public wrapper and private
implementation retain their existing ownership and entitlement boundaries;
the response version adds validation, not authority. The strict Flutter parser
accepts only the documented status/reason/row combinations and treats any
other shape as `maintenance_completion_rpc_contract_mismatch`.

`maintenance_records` are unique by owner/plan/occurrence and retain the client
completion time, server acceptance time, and IANA time zone. A canonical final
due occurrence may create a 30-minute eligibility row bound to its account and
completion. `create_reward_claim_request` requires and consumes that token for
`rewarded_interstitial`; losing, rejected, expired, cross-account, and replayed
tokens fail closed. Generic `rewarded_ad` earning remains a separate flow.

### Asset detail contract

`device_details.consumable` is optional descriptive text end to end, matching the Flutter domain model and Drift schema. It stores user-entered consumable or replacement-part descriptions such as filters, batteries, and cartridges; it is not a Boolean capability flag. The atomic asset-creation RPC normalizes blank consumable text to `NULL` and persists the optional `assets.placement` field supplied by Flutter. Database regression coverage exercises this contract through `create_asset`.

## RPCs

Use RPCs when an operation must be atomic or server-authoritative, including point debit plus entity creation, revision-aware mutation, protected cleanup, or idempotent completion.

RPC contracts should define:

- Authentication and ownership.
- Input schema and limits.
- Idempotency key behavior and advisory-lock (`pg_advisory_xact_lock`) parity.
- Success and duplicate-success responses, including the contract-1 `get_charged_operation_status` result used for lost-response recovery.
- Conflict and stale-revision responses.
- Retryable versus terminal errors.
- Server timestamp/revision semantics.
- Audit and privacy-safe diagnostics.

`get_charged_operation_status(p_operation_id uuid, p_request_hash text)` enables client journal reconciliation following transport failure. Lookups are strictly same-account and operation-bound; querying another user's operation returns `status: 'not_found'` without revealing operation existence, while reuse with a mismatched request hash is rejected. The public function is a pinned `SECURITY INVOKER` wrapper; its elevated implementation lives in `owntend_monetization_private`, is `SECURITY DEFINER SET search_path = ''`, and still derives the caller from `auth.uid()`.

The media RPCs `prepare_asset_photo_upload`, `finalize_asset_photo_upload`, and `set_primary_asset_photo` follow the same wrapper/private-implementation boundary. Public functions are pinned invokers; privileged implementations are pinned definers in non-exposed `owntend_media_private`, derive `auth.uid()`, and validate ownership.

## Storage

The `user-media` bucket is private and limited to supported image MIME types and the configured 10 MiB object limit. Object paths and policies must prevent cross-user access. Signed URLs, if used, are temporary credentials and must not appear in logs, Sentry, or public artifacts.

Media metadata, object creation, replacement, and cleanup should tolerate partial failure and retry without exposing or deleting another user's data.

Asset and photo identifiers are text throughout the synced tables and media RPC boundary. Before any bytes are uploaded, Flutter calls `prepare_asset_photo_upload` with an idempotency key and expected object facts. The server serializes prepares per user, enforces at most 20 fresh staged rows and 100 MiB expected bytes, and returns an opaque `<user>/media/<stage-uuid>/<attempt>.<ext>` path. Exact active/finalized replays are stable; expired or failed attempts retain the staging row ID, queue the old path, increment `attempt`, and issue a new path. The Storage INSERT policy requires that exact fresh staged row. Authenticated Storage DELETE has no policy; clients delete photo metadata through `delete_asset_photo`, and the service worker alone removes objects.

### Protected media-cleanup worker  Server-side cleanup is executed only by the [`process-media-cleanup`](../../supabase/functions/process-media-cleanup/index.ts) Edge Function against the service-role worker RPCs `claim_media_cleanup_batch`, `acknowledge_media_cleanup`, and `record_media_cleanup_failure`, all of which are revoked from client roles and granted exclusively to `service_role`.  Worker authority is a dedicated service-to-service capability, never a user JWT and never the platform service-role key:  - The gateway runs this function with `verify_jwt = false` in `supabase/config.toml`; bearer tokens carry no meaning on this endpoint. - Callers must present an exact random capability in the `X-Owntend-Worker-Token` header. The function compares it in constant time against `OWNTEND_MEDIA_CLEANUP_WORKER_TOKEN` from Edge Runtime environment configuration. - A request without the header receives `401`; a wrong value receives `403`. Without a configured capability the function fails closed with `403`. No CORS headers are ever emitted; non-POST methods, non-JSON content types, and oversized bodies are rejected. - Work is bounded: batches are capped at 25 rows claimed under `SKIP LOCKED`, removals run with bounded concurrency (4) under an overall 20-second deadline, and rows whose lease (5 minutes) expires after a dead invocation are reclaimed automatically. Absent Storage objects count as idempotent successes. - Failures persist only bounded allowlisted technical codes (`last_error_code`); raw provider messages and object paths are never stored or logged.  Recurring invocation is fail-safe: when operators provision BOTH the Vault secret `media_cleanup_worker_authorization` (the same capability value as the runtime token) AND the database setting `owntend.media_cleanup_function_url` holding the EXACT function endpoint, migration-time scheduling registers the protected `owntend-media-cleanup-worker` cron job that POSTs the endpoint hourly with the capability header and a 30-second request budget; while either input is absent no schedule exists and the queue drains only through explicitly authorized invocations. Expired staging reservations are swept by the separate in-database `owntend-media-staging-sweep` job, which needs no external secret.  The canonical backend gate (`npm run test:backend-integration`) proves the whole contract end to end - gateway denials, capability acceptance, real Storage deletion, idempotent re-removal, bounded failure codes, lease recovery, and disjoint concurrent claims - against a freshly applied blank baseline in an isolated disposable stack. ## Realtime

Realtime is an invalidation mechanism, not a replacement for authenticated pull and revision checks. The client must tolerate dropped, duplicated, delayed, and out-of-order events.

The launch baseline adds the 17 synchronized app tables to `supabase_realtime` and uses `REPLICA IDENTITY FULL`. The one shipped incremental contract has integer boundary version `1`; it maps those tables one-to-one to canonical client entity identifiers and stores typed delete keys plus canonical upsert payloads, including both columns of the `asset_tag` composite key. Realtime payloads remain hints; durable insert, update, and delete authority comes from an authenticated snapshot followed by the owner-scoped change feed.

Change-feed Data API privileges are fail closed. `fetch_user_change_feed(...)` and `get_user_change_feed_watermark()` are authenticated-only `SECURITY INVOKER` functions and derive ownership exclusively from `auth.uid()`. `validate_change_feed_parity(p_user_id uuid)` is service-role-only; the no-argument overload is absent. The protected migration workflow enumerates hosted Auth accounts through the server-only Admin API and invokes it once per account with a normal service credential, emitting no account IDs. This intentionally fails if an Auth account is missing its required profile instead of silently omitting that account from evidence. The application has no rollout-discovery or parity/healing RPC. `fn_log_server_change_feed()` remains a trigger-only pinned definer with direct execution revoked from API roles.

After a hosted pre-launch reset or migration deployment, a release may depend on the feed only after the exact-main baseline is proven hosted: no pending migration drift, contract `1`, zero malformed feed rows, correct effective RPC ACLs, no unresolved blocking feed/security Advisor findings, and service-side parity success for every hosted account (or verified zero accounts).

## Hosted Advisor audit

`Audit Supabase Advisors` runs only from exact current `main` and queries both hosted security and performance Advisors through a protected environment. Its sanitized artifact retains every finding. `WARN`, `ERROR`, and unknown severities are blocking unless a narrowly documented exception is explicitly allowlisted; `INFO` findings remain visible but are non-blocking. This distinction is important on a newly reset zero-user database, where unused-index telemetry has no representative workload behind it.

## Edge Functions

Functions run in the Deno-based Supabase runtime and must validate all untrusted requests. Secrets belong in function environment configuration, not source or Flutter. Canonical locked formatting, type-checking, and unit-test commands are enforced by the backend and Android release workflows.

### `delete-account` HTTP contract

[`supabase/functions/delete-account/index.ts`](../../supabase/functions/delete-account/index.ts) is the shared remote-deletion authority for the installed application and the public browser page.

- `POST` is the only deletion method. The body must contain `{ "confirmation": "delete-my-account", "recovery_key": "<43-character base64url value>" }` and the `Authorization` header must contain the user's bearer token. The unpadded base64url value must decode to exactly 32 bytes.
- The function extracts the session ID from the JWT, verifies the user through Supabase Auth, and checks recent-session state. It never accepts a client-supplied user ID as ownership authority.
- It hashes the recovery key and a key/user binding before persistence. Raw keys, tokens, and direct identifiers are not logged.
- A successful response is HTTP `200` with `deleted: true`, `status: "deleted"`, and `user_id` set to the verified authenticated user. Browser code must match all three fields, including the verified user ID, before reporting success.
- Responses use `Cache-Control: no-store`. Failure responses expose stable technical error codes rather than raw requests, tokens, provider payloads, or user content.

The function's browser CORS allowlist is exact and contains only:

- `https://owntend.app`
- `http://localhost:4173`
- `http://127.0.0.1:4173`

An allowed `OPTIONS` preflight returns `204`, echoes that exact origin in `Access-Control-Allow-Origin`, varies on `Origin`, and permits `POST, OPTIONS` plus the `authorization`, `apikey`, `content-type`, and `x-client-info` request headers. A missing or non-allowlisted preflight origin is rejected. A non-preflight browser request with an unapproved `Origin` is rejected before authorization or body processing, and allowed browser origins receive readable CORS headers on both success and failure responses. Wildcard origins and credentialed cookies are not used.

Native Flutter HTTP requests normally have no `Origin` header. They continue through the full JWT, confirmation, recent-session, cleanup, and receipt checks, but receive no `Access-Control-Allow-Origin` header. Absence of `Origin` is compatibility behavior, not an authorization bypass.

### `account-deletion-status` HTTP contract

[`supabase/functions/account-deletion-status/index.ts`](../../supabase/functions/account-deletion-status/index.ts) provides status verification and post-deletion acknowledgment for recovery operations.

- `POST` with `{ "recovery_key": "<43-character base64url value>", "expected_user_id": "<uuid>" }` queries status.
- `POST` with `{ "recovery_key": "<43-character base64url value>", "expected_user_id": "<uuid>", "action": "acknowledge" }` advances the operation to `acknowledged`.
- The endpoint is capability-authorized and intentionally does not require a caller JWT. Authorization derives from the hashed recovery key plus the expected user binding so recovery still works after the Auth user has been deleted.
- Responses specify status (`pending`, `deleted`, `acknowledged`, `recovery_not_found`, or `unauthorized`), target user ID, timestamps, and GC window.
- Recovery records enter a 7-day retention window after acknowledgment before garbage collection.


### Wallet Realtime channel

`public.point_wallets` is included in `supabase_realtime` with full replica
identity so server-side monetization changes, including SSV settlement, notify
a running client. This is a monetization state channel, separate from the
17-table local-first sync/change-feed contract.

Authenticated clients may select only their own wallet row and retain no
direct INSERT/UPDATE/DELETE privilege. Charges, rewards, refunds, and
adjustments stay behind server-authoritative RPC/service-role paths.
[`0026_wallet_realtime.test.sql`](../../supabase/tests/database/0026_wallet_realtime.test.sql) locks the publication,
replica-identity, owner-read, and no-client-write contract.
