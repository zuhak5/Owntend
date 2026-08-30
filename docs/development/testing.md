# Testing Strategy

### Widget suite layout and shared helpers (WP-014/WP-015)

The former 7,000-line `test/widget_test.dart` is split into themed suites under
`test/widgets/` with shared fakes in `test/support/widget_test_fakes.dart`
(121 tests, count-preserving). Async conditions use the single bounded helper
`waitFor` from `test/support/wait_for.dart` — wall-clock busy-wait loops are
gone. `dart_test.yaml` pins `concurrency: 1` (matching the documented
full-suite command) and a 2-minute per-test timeout. Golden tests render with
Flutter's synthetic Ahem-style test font; no font loader is configured, so
regressions in real font metrics must be caught on device.

### Integration-evidence lanes (WP-016)

Two gated suites exist by design and run in CI, not the default lane:
`npm run test:backend-integration` provisions an isolated disposable Supabase
stack (blank-baseline pgTAP + Edge Functions + worker contract) in the
`Blank-baseline database and Edge endpoint integration` job of
`.github/workflows/validate-google-backend.yml`; the Dart-side two-user loopback
suite `test/backend_integration/local_backend_sync_test.dart` runs only with
loopback dart-defines. Its authenticated gateway cases include full local
asset/maintenance-plan records serialized into least-privilege PATCH payloads,
server metadata advancement, stale-revision conflict behavior, and cross-user
isolation. It also exercises the versioned maintenance-completion envelope and
runs a stale completion through the real coordinator during initial hydration,
proving one safe retry, canonical reconciliation, `ready` completion, and
cross-user history isolation. Skips are honest gates, not rot.

## Launch evidence ladder

Launch claims map to named lanes; a claim without its lane is not evidenced:

| Lane | Command / owner | Evidence class |
| --- | --- | --- |
| Fast focused | `flutter test --no-pub <files>` | Local/CI, mocked |
| Full Flutter | `flutter test --no-pub --concurrency=1 --timeout 3m --exclude-tags production-config` | Local/CI |
| Production example contract | documented production-config command | Local/CI, example only |
| Node/tooling | `npm run validate:test-inventory`; `npm run test:all` | Local/CI |
| Deno functions | per-function frozen fmt/check/test | Local/CI |
| Blank-baseline database + endpoint integration | `npm run test:backend-integration` (isolated disposable stack) | Disposable local/CI |
| Two-user application/backend | `test/backend_integration/local_backend_sync_test.dart` via backend workflow | Disposable local/CI |
| Emulator/device integration | Removed: the `integration_test` SDK dependency leaked into release plugin registration (flutter/flutter#169336) and broke production AAB builds; no device lane exists in CI |  |
| Physical-device matrix | API 26/33/35/36 + OEM matrix: permissions, reboot/timezone, process death, TalkBack | Device (external) |
| Hosted staging | disposable hosted Supabase, cron, Storage with authorization | Hosted (external) |
| Protected release rehearsal | release workflow dry runs, signing, Sentry symbols, VersionDeck derivation | Protected (external) |

Flaky retry never converts a failure into success: a red lane is disclosed,
never silently rerun to green.

## Goals

Owntend tests should protect user data, offline behavior, account isolation, backend authorization, monetization integrity, backup safety, localization, and release trust—not only line coverage.

## Test layers

### Pure Dart and service tests

Use for recurrence, formatting, configuration, backup validation, synchronization decisions, monetization state, and deterministic helpers. Prefer these for fast exhaustive edge cases.

### Repository and database tests

Use temporary Drift databases to verify queries, transactions, schema migrations, outbox behavior, reminder snapshots, cleanup, and restart persistence. Migration tests must begin from historical schema fixtures rather than only creating the latest schema.

### Widget tests

Cover visible state, navigation, forms, accessibility, localization, RTL layout, loading, empty, error, offline, signed-out, and blocked behavior. Override Riverpod dependencies instead of contacting real services.

### Integration tests

Use for cross-layer application journeys that cannot be proven by isolated tests. Current integration coverage is limited; new synchronization-sensitive journeys should add real local-service integration coverage where maintainable.

### Supabase database tests

`supabase/tests/database` should verify tables, constraints, RLS, RPCs, ownership, idempotency, and cross-user denial. Run against the local Supabase stack.

### Edge Function tests

Functions require formatting, locked type-checking, unit/request-validation tests, and explicit negative-security cases. Canonical Deno checks cover AdMob SSV, account deletion, deletion-status recovery, and the media-cleanup worker. These isolated tests do not prove that the reviewed function revision or secrets are deployed to a hosted project.

### Disposable backend endpoint integration

`npm run test:backend-integration` provisions an isolated, disposable local Supabase stack on shifted ports inside a temporary workspace, replays the complete migration chain, runs schema lint and all pgTAP files (including exact sync UPDATE ACL and maintenance-completion response matrices), serves every configured Edge Function over real HTTP, runs `supabase/tests/integration/*.test.ts` against the actual `/functions/v1/...` gateway, and tears everything down in every outcome. The application/backend lane separately drives two authenticated clients through real Auth, RLS, PostgREST, and Storage. It covers unprepared/expired upload denial, live-object delete denial, concurrent stage count/byte quotas, duplicate copy/move idempotency, simultaneous move/type point conservation with a deadlock timeout, validated history-restore replay/conflict, protected-column/history CRUD denial, full-record asset/plan PATCH allowlisting, server metadata advancement, stale revisions, versioned completion parsing and initial-hydration reconciliation, and cross-user UPDATE/history isolation. Both lanes keep credentials in memory and target loopback only.

### Browser deletion and Google/Android contract tests

Node tests cover the public account-deletion PKCE flow, token-storage boundary, Web Crypto recovery key, explicit confirmation, protected function call, same-key status recovery across reload or ambiguous responses, strict receipt, exact CORS origins, service-worker navigation policy, and release source contracts. The static validator also cross-checks Android, ads, reward, auth, and deletion invariants.

### VersionDeck tests

Use Node's test runner for manifest schema, cache policy, relative time,
APK-verification helpers, build status, and UI state
helpers. Cover the reviewed control file (`tool/versiondeck-control.json`),
absolute manifest lease expiry, explicit disabled publication, and
withdrawn/superseded historical-release states in addition to the ordinary
active-release path. When adding focused Node tests, update
`tool/test_inventory.mjs` at the same time so the file cannot be skipped. Build
and validate the static artifact after focused tests.

### Release validation

One pinned Shorebird rail builds the canonical AAB. Production requires the exact
`Validate Google Backend and Release Contracts` result. A protected downstream
job derives the universal and three ABI APKs from that AAB and verifies the
standalone signer/package/version without invoking Flutter again. None of these
steps uploads to Play, mutates Sentry, or deploys VersionDeck.

`npm run test:shorebird` protects configuration generation, exact pins, KMS
commands, patch eligibility, and runtime attribution. Patch workflows additionally
run `tool/shorebird_patch_eligibility.mjs` against exact commits and a Shorebird
dry-run. Physical-device staging evidence is required before promotion and cannot
be replaced by unit/CI tests.

## Security assertion testing

### AdMob SSV cryptographic verification

The SSV handler verifies ECDSA signatures using Google's public keys (`1457` and
`488`). Tests must cover valid signatures, tampered queries, replay attempts,
unknown keys, malformed public keys, network timeouts, and key caching. Run with:

```powershell
deno test supabase/functions/admob-ssv-handler/index_test.ts
```

### Row Level Security negative testing

Database tests must explicitly assert access denial:
- User A cannot read User B's assets, rooms, tasks, or photos.
- Anonymous requests cannot access private tables.
- Deleted-account users cannot perform operations.
- `SECURITY DEFINER` functions run with fixed `search_path`.

```powershell
npm run supabase:test
```

## Standard Flutter commands

```powershell
flutter pub get
flutter gen-l10n
dart run build_runner build
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --timeout 3m --exclude-tags production-config
```

Production configuration schema:

```powershell
flutter test --no-pub test/prod_build_config_test.dart `
  --dart-define-from-file=config/prod.example.json `
  --dart-define=VERIFY_PRODUCTION_CONFIG=true
```

## Supabase commands

```powershell
npm ci
npx supabase start
npm run supabase:lint
npm run supabase:test
npx supabase stop --no-backup
```

The local Docker stack must be healthy on the ports configured in `supabase/config.toml`. A connection failure or host port reservation is an environment block, not a passing database result.

## Canonical Node and tooling commands

```powershell
npm ci
npm run validate:test-inventory
npm run test:all
npm run validate:toolchain
npm run validate:dependency-policy
npm run validate:google-contracts
```

This runs every canonical Node test suite registered in [`tool/test_inventory.mjs`](../../tool/test_inventory.mjs); that list is authoritative for count and membership. The suite includes the sanitized per-account parity operator tool, complete test inventory, toolchain consistency, dependency policy, and static Google/Android release contracts.

## Focused remediation contracts

Run focused tests first while iterating, then run the complete relevant suites above.

Startup topology, localization, accessibility, and reduced motion:

```powershell
flutter test --no-pub test/owntend_splash_lifecycle_test.dart
flutter test --no-pub test/owntend_splash_overlay_test.dart
flutter test --no-pub test/startup_resources_test.dart
```

Permission/capability derivation, serialized education, settings targeting, and the canonical requester adapters:

```powershell
flutter test --no-pub test/features/permissions
```

Protected transient feedback, runtime ads, and native-ad schema:

```powershell
flutter test --no-pub test/feedback_coordinator_test.dart
flutter test --no-pub test/monetization_test.dart
flutter test --no-pub test/native_ad_factory_contract_test.dart
flutter test --no-pub test/task_creation_insufficient_points_test.dart
node --test tool/supabase-advisors.test.mjs
```

The Supabase pgTAP monetization suite proves that zero-balance standalone task
creation returns the structured shortage state and leaves no target row behind,
while zero-balance asset creation succeeds with a zero charge and no negative
ledger entry. Widget coverage proves the task-shortage dialog remains visible
with inline recovery status when rewarded ads are unavailable.

Input-boundary and authoritative error-taxonomy coverage:

```powershell
flutter test --no-pub `
  test/input_validation_test.dart `
  test/database_schema_test.dart `
  test/wallet_error_taxonomy_test.dart `
  test/asset_creation_controller_test.dart `
  test/task_creation_insufficient_points_test.dart

supabase test db --local `
  supabase/tests/database/0036_input_validation_contract.test.sql
```

These tests cover accepted maxima, max-plus-one rejection, zero/negative
numeric boundaries, physical SQLite and PostgreSQL constraints, definitive
terminal journal states, payload scrubbing, and privacy-safe ambiguous failure
records.

Authentication/deletion client contracts:

```powershell
flutter test --no-pub test/native_google_sign_in_test.dart
flutter test --no-pub test/supabase_auth_repository_test.dart
flutter test --no-pub test/supabase_android_config_test.dart
```

Auth-stream, cloud-startup, and Sync Health recovery contracts:

```powershell
flutter test --no-pub --concurrency=1 --timeout 3m `
  test/auth_state_provider_test.dart `
  test/account_cleanup_startup_recovery_test.dart `
  test/failed_mutation_diagnostics_test.dart `
  test/sync_conflict_preservation_test.dart `
  test/widgets/sync_health_screen_test.dart `
  test/account_screen_test.dart
```

This matrix proves auth errors remain observable, cloud initialization failure
has an explicit retry surface, failed mutation summaries omit record keys from
diagnostics and UI, and keep-device/keep-cloud resolution stays explicit and
account scoped.

Photo-import, asynchronous-screen, local-clock, search-ordering, and canonical
backup-picker contracts:

```powershell
flutter test --no-pub --concurrency=1 --timeout 3m `
  test/photo_import_service_test.dart `
  test/local_clock_test.dart `
  test/room_route_state_and_editor_guard_test.dart `
  test/widgets/home_shell_header_test.dart `
  test/widgets/search_screen_ordering_test.dart `
  test/widgets/statistics_calendar_trash_test.dart `
  test/widgets/backup_restore_screens_test.dart
```

These tests cover real content decoding and normalized JPEG budgets, no metadata
after storage failure, loading/error/not-found separation, labeled last-good
Home data, midnight and resume clock updates, superseded search responses, and
the `.owntend-backup` picker allowlist. They do not establish low-storage or
performance behavior on a physical Android device, OS time-zone delivery,
hosted synchronization, or protected release/publication evidence.

Edge Functions, public browser deletion, and release/static contracts:

```powershell
deno install --frozen --config deno.json
Push-Location supabase/functions/admob-ssv-handler; deno install --frozen; Pop-Location
Push-Location supabase/functions/delete-account; deno install --frozen; Pop-Location
Push-Location supabase/functions/account-deletion-status; deno install --frozen; Pop-Location
Push-Location supabase/functions/process-media-cleanup; deno install --frozen; Pop-Location

deno fmt --check `
  supabase/functions/_shared/request.ts `
  supabase/functions/_shared/sentry.ts `
  supabase/functions/_shared/sentry_test.ts `
  supabase/functions/admob-ssv-handler/index.ts `
  supabase/functions/admob-ssv-handler/index_test.ts `
  supabase/functions/delete-account/index.ts `
  supabase/functions/delete-account/index_test.ts `
  supabase/functions/account-deletion-status/index.ts `
  supabase/functions/account-deletion-status/index_test.ts `
  supabase/functions/process-media-cleanup/index.ts `
  supabase/functions/process-media-cleanup/index_test.ts

deno check --frozen supabase/functions/admob-ssv-handler/index.ts
deno check --frozen supabase/functions/delete-account/index.ts
deno check --frozen supabase/functions/account-deletion-status/index.ts
deno check --frozen supabase/functions/process-media-cleanup/index.ts

deno test --frozen --allow-env --allow-net --config deno.json `
  supabase/functions/_shared/sentry_test.ts
Push-Location supabase/functions/admob-ssv-handler; deno test --frozen --allow-env --allow-net index_test.ts; Pop-Location
Push-Location supabase/functions/delete-account; deno test --frozen --allow-env --allow-net index_test.ts; Pop-Location
Push-Location supabase/functions/account-deletion-status; deno test --frozen --allow-env --allow-net index_test.ts; Pop-Location
Push-Location supabase/functions/process-media-cleanup; deno test --frozen --allow-env --allow-net index_test.ts; Pop-Location

node --test `
  tool/account-deletion-site.test.mjs `
  tool/android-lint-gate.test.mjs `
  tool/asset-and-test-inventory.test.mjs `
  tool/dependency-security-and-notices.test.mjs `
  tool/toolchain.test.mjs

node tool/validate_google_release_contracts.mjs
```

Disposable backend endpoint integration (isolated stack, real gateway):

```powershell
npm run test:backend-integration
```

VersionDeck packaging and static validation:

```powershell
node --test `
  tool/account-deletion-site.test.mjs `
  tool/build-status.test.mjs `
  tool/build-status-timeline.test.mjs `
  tool/build-status-ui.test.mjs `
  tool/sticky-download-fix.test.mjs `
  tool/versiondeck.test.mjs

node tool/build_versiondeck_site.mjs `
  --source download-site `
  --output .versiondeck-site `
  --revision 0000000000000000000000000000000000000000 `
  --allow-inert-account-deletion-config true

node tool/validate_versiondeck.mjs .versiondeck-site
```

The package scripts are authoritative if this focused command list changes.

## Risk-based matrices

### Synchronization

Test offline mutation, restart, timeout after possible commit, duplicate retry, stale revision, concurrent device changes, missing/duplicate realtime events, cursor-page failure, account switch, revoked session, hydration interruption, media failure, and deletion during queued work.

### Account deletion

Test confirmation, cancellation, wrong Google account, stale session, offline state, 32-byte/43-character recovery-key validation, secure operation persistence, duplicate requests with the same key, pending/temporary/not-found status recovery, Storage/database/Auth ordering, failed cleanup finalization, strict same-user receipt, cloud success/local failure, restart recovery, web PKCE/state and `sessionStorage` handling without token persistence, exact CORS origins, and exported backups remaining outside app control.

### Monetization

Test every global/per-format runtime gate, generation invalidation, stale callbacks, retry classification/budgets/dormancy/jitter, the 55-minute boundary, exact-once leases, fullscreen serialization, native palette fallback, consent unavailable, no reward, pending claim, valid SSV, replay, invalid signature, wrong account, expiry, insufficient balance, duplicate charged creation, timeout after commit, and offline draft behavior.

### Backup and restore

Test valid format-1/schema-1 backups, unsupported versions, path traversal, duplicate paths, oversized expansion, hash mismatch, insufficient storage, interrupted replacement, rollback, account mismatch, and sync restart.

### Notifications

Test the separation of user preference, OS/service/special-access state, scheduler truth, and effective capability. Include manual weather with denied location, service-disabled location, notification denial and disabled channel, settings-return refresh, time-zone change, reboot, application update, stale snapshots, completion rescheduling, and duplicate prevention. For background notification work, cover matching versus mismatched account identity, idempotent unique periodic registration across restart, cancellation/rejection on sign-out or account switch, durable reconciliation surviving process restart, coalescing duplicate requests, ACK only after successful refresh, retry state after failure, and replay when a worker/foreground consumer restarts mid-reconciliation.

### Startup and transient feedback

Test the first Flutter owner, fixed splash lifetime across startup/failure branch changes, non-blank fallback, English and Arabic semantics, compact/large-text layout, interaction blocking, and no repeating animation under reduced motion. For settings, exercise narrow English and Arabic layouts with scaled text, especially capability status and recovery actions. For feedback, test protected Undo ordering, exact-key batching, visible counts and deadline reset, LIFO Undo, FIFO finalization, exactly-once callbacks, accessible persistence, callback failure, directional layout, one visual gap above real Scaffold bottom navigation and floating actions, feedback above modal-sheet barriers, and all Trash restoration call sites. Schema migration coverage must preserve tasks and remaining metadata while removing retired dependency links. Native-ad contract coverage must enumerate every routed content placement and verify the shared light/dark surface palette. Sync gateway coverage guards the zero-row list-response path that avoids expected PostgREST 406 warnings without weakening revision checks.

## Test-writing rules

- Test behavior and invariants, not implementation trivia.
- Use stable clocks, UUIDs, and deterministic fixtures where possible.
- Never use production credentials or services.
- Do not suppress flaky tests without identifying the source of nondeterminism.
- Do not change expected values simply to match an unexplained failure.
- Keep security-denial tests alongside success tests.
- State explicitly when a device, hosted service, or protected workflow remains untested.


### Wallet synchronization

[`test/wallet_sync_test.dart`](../../test/wallet_sync_test.dart) covers the auth-scoped wallet owner,
authoritative mutation adoption, stale-snapshot ordering, external updates,
last-good refresh behavior, account isolation, reconnect, points-pill updates,
and the boundary that keeps wallets outside the generic change feed.
`test/charged_operation_journal_test.dart` additionally verifies authoritative
balances recovered from completed status and exact replay.

[`supabase/tests/database/0026_wallet_realtime.test.sql`](../../supabase/tests/database/0026_wallet_realtime.test.sql) proves the
wallet Realtime publication/replica identity and its read-only authenticated
RLS/grant contract. Existing monetization, SSV security, charged-operation,
17-table Realtime, recovery, and notification-completion suites remain required regressions.

### Live runtime updates

[`test/live_runtime_updates_test.dart`](../../test/live_runtime_updates_test.dart) covers local repository mutations reaching the existing Drift-backed Riverpod streams without a post-population loading/empty gap, room/item/task completion convergence, preservation of the repository aggregate settle boundary, removal of redundant Dashboard/Rooms render caches, live-first Home startup-snapshot precedence, and the recent-sync resume regression where a missed remote change must trigger a broad pull and repair local Drift state.

Keep the coordinator, Realtime, hydration, notification-completion, backup, search-generation, and wallet suites in the same validation run. In particular, [`test/sync_coordinator_test.dart`](../../test/sync_coordinator_test.dart) retains active broad-pull coalescing and canonical Realtime convergence coverage, while the focused recovery, account-scope, startup, completion, backup, search, and monetization tests protect those boundaries.
