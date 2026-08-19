# Testing Strategy

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

Functions require formatting, locked type-checking, unit/request-validation tests, and explicit negative-security cases. Canonical Deno checks cover AdMob SSV, account deletion, and deletion-status recovery. These isolated tests do not prove that the reviewed function revision or secrets are deployed to a hosted project.

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

The AAB and APK rails are separate. Both require a successful `Validate Google
Backend and Release Contracts` run. The AAB rail
verifies one signed bundle and emits manifest, dependency, signing, and checksum
evidence; it does not upload to Google Play. The APK rail additionally verifies
the standalone signer/package/version and mutates Sentry release state.

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
dart format --output=none --set-exit-if-changed lib test integration_test
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

This runs all 12 canonical Node test suites, validates the complete test inventory, evaluates toolchain consistency, checks dependency license policies against the exception registry, and validates static Google/Android release contracts.

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

Authentication/deletion client contracts:

```powershell
flutter test --no-pub test/native_google_sign_in_test.dart
flutter test --no-pub test/supabase_auth_repository_test.dart
flutter test --no-pub test/supabase_android_config_test.dart
```

Edge Functions, public browser deletion, and release/static contracts:

```powershell
deno fmt --check `
  supabase/functions/admob-ssv-handler/index.ts `
  supabase/functions/admob-ssv-handler/index_test.ts `
  supabase/functions/delete-account/index.ts `
  supabase/functions/delete-account/index_test.ts `
  supabase/functions/account-deletion-status/index.ts `
  supabase/functions/account-deletion-status/index_test.ts

deno check --frozen supabase/functions/admob-ssv-handler/index.ts
deno check --frozen supabase/functions/delete-account/index.ts
deno check --frozen supabase/functions/account-deletion-status/index.ts

node --test `
  tool/account-deletion-site.test.mjs `
  tool/android-lint-gate.test.mjs `
  tool/asset-and-test-inventory.test.mjs `
  tool/dependency-security-and-notices.test.mjs `
  tool/toolchain.test.mjs

node tool/validate_google_release_contracts.mjs
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

Test valid current/historical backups, unsupported versions, path traversal, duplicate paths, oversized expansion, hash mismatch, insufficient storage, interrupted replacement, rollback, account mismatch, and sync restart.

### Notifications

Test the separation of user preference, OS/service/special-access state, scheduler truth, and effective capability. Include manual weather with denied location, service-disabled location, notification denial and disabled channel, exact preference off, exact denial with inexact fallback, settings-return refresh, time-zone change, reboot, application update, stale snapshots, completion rescheduling, and duplicate prevention. For background notification work, cover matching versus mismatched account identity, idempotent unique periodic registration across restart, cancellation/rejection on sign-out or account switch, durable reconciliation surviving process restart, coalescing duplicate requests, ACK only after successful refresh, retry state after failure, and replay when a worker/foreground consumer restarts mid-reconciliation.

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


### Problem #7 wallet synchronization

`test/problem_007_wallet_sync_test.dart` covers the auth-scoped wallet owner,
authoritative mutation adoption, stale-snapshot ordering, external updates,
last-good refresh behavior, account isolation, reconnect, points-pill updates,
and the boundary that keeps wallets outside the generic change feed.
`test/charged_operation_journal_test.dart` additionally verifies authoritative
balances recovered from completed status and exact replay.

`supabase/tests/database/0023_problem_007_wallet_realtime.test.sql` proves the
wallet Realtime publication/replica identity and its read-only authenticated
RLS/grant contract. Existing monetization, SSV-hardening, charged-operation,
17-table Realtime, BUG-005, and BUG-011 suites remain required regressions.
