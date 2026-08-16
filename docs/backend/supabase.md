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

The committed local configuration is `supabase/config.toml`. SQL migrations are append-only history under `supabase/migrations/`; database tests are under `supabase/tests/database/`.

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

## Authentication

The local configuration enables Google as the external provider and disables email sign-up. Production authentication behavior depends on correctly configured Google OAuth clients, package identity, redirect behavior, and protected Supabase environment values.

Backend authorization must derive ownership from the authenticated JWT identity rather than trusting a user ID supplied by Flutter.

## Database and RLS

Every user-owned table should have explicit RLS policies for intended owner operations and denial tests for anonymous and cross-user access. Constraints and indexes should enforce invariants independently of client behavior.

Review `SECURITY DEFINER` functions carefully:

- Set a safe `search_path`.
- Authenticate and authorize inside the function.
- Minimize privileges and returned data.
- Validate inputs and bound resource use.
- Make externally retried mutations idempotent.

Never disable RLS to resolve an application error.

The pre-launch cloud schema follows the fields emitted by Flutter for device, pet, plant, and safety details plus maintenance-plan metadata. Cloud-only aliases remain intentional for maintenance plans (`description`, `interval_count`, `interval_unit`) and streaks (`longest_streak`, `last_completion_date`); `SyncEntitySpec.remoteRenames` is the executable client mapping. Direct client insertion of a new charged maintenance plan is denied. Authenticated reconciliation can only update a plan that the atomic creation or completion RPC already established.

### Asset detail contract

`device_details.consumable` is optional descriptive text end to end, matching the Flutter domain model and Drift schema. It stores user-entered consumable or replacement-part descriptions such as filters, batteries, and cartridges; it is not a Boolean capability flag. The atomic asset-creation RPC normalizes blank consumable text to `NULL` and persists the optional `assets.placement` field supplied by Flutter. Database regression coverage exercises this contract through `create_asset_with_point_debit`.

## RPCs

Use RPCs when an operation must be atomic or server-authoritative, including point debit plus entity creation, revision-aware mutation, protected cleanup, or idempotent completion.

RPC contracts should define:

- Authentication and ownership.
- Input schema and limits.
- Idempotency key behavior and advisory-lock (`pg_advisory_xact_lock`) parity.
- Success and duplicate-success responses (including `get_charged_operation_status` capability version `1.1.0` for lost-response recovery).
- Conflict and stale-revision responses.
- Retryable versus terminal errors.
- Server timestamp/revision semantics.
- Audit and privacy-safe diagnostics.

`get_charged_operation_status(p_operation_id uuid, p_request_hash text default null)` enables client journal reconciliation following transport failure. Lookups are strictly same-account and operation-bound; querying another user's operation returns `status: 'not_found'` without revealing operation existence.

## Storage

The `user-media` bucket is private and limited to supported image MIME types and the configured 10 MiB object limit. Object paths and policies must prevent cross-user access. Signed URLs, if used, are temporary credentials and must not appear in logs, Sentry, or public artifacts.

Media metadata, object creation, replacement, and cleanup should tolerate partial failure and retry without exposing or deleting another user's data.

Asset and photo identifiers are text throughout the synced tables and media RPC boundary. The Flutter client always executes `stage_media_upload` and `finalize_asset_photo_upload` after uploading bytes to the deterministic owner path; there is no direct-upload compatibility fallback.

## Realtime

Realtime is an invalidation mechanism, not a replacement for authenticated pull and revision checks. The client must tolerate dropped, duplicated, delayed, and out-of-order events.

The baseline adds the 17 synchronized app tables to `supabase_realtime` and uses `REPLICA IDENTITY FULL`. `fn_log_server_change_feed()` derives record keys by table shape: ordinary `id`, detail `asset_id`, metadata `plan_id`, setting `key`, profile `user_id`, and the `asset_id|tag_id` composite for asset tags. Realtime payloads remain hints; durable insert, update, and delete authority comes from authenticated pulls and the owner-scoped change feed.

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
