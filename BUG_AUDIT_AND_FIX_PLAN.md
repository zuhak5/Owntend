# Owntend Comprehensive Bug Audit and Remediation Record

## 1. Executive Summary

Status: **complete within the audited and locally validated scope — zero known actionable repository defects remain**. All 28 corrections are implemented. Twenty-seven defects have completed local verification; BUG-013's extracted production operation passes, while actual native WorkManager dispatch remains **BLOCKED — EXTERNAL VALIDATION REQUIRED**. Final validation passed 1,080 Flutter tests (one expected opt-in backend skip), analysis, the production-example contract, development APK compilation, 148 Node tests, 71 Deno tests, fresh schema lint/669 pgTAP assertions/eight HTTP steps, and the separately executed eight-scenario application/backend lane. The concluding review found no additional credible actionable defect. Device, hosted, protected-release and earlier cleanup limitations are explicit below; this is not an absolute bug-free or production-launch claim.

Scope: all tracked Owntend runtime, Flutter UI/domain/persistence/synchronization, Supabase SQL and Edge Functions, Android host, VersionDeck, configuration, tests, build and release tooling, and supporting documentation. Methods: architecture mapping, independent subsystem audits, caller/callee tracing, adversarial candidate verification, edge-case and cross-layer review, baseline/focused/full tests, regression proof, and post-fix re-audit.

Initial state: clean working tree at `30eda430df89c11cdfcd4e8a1ebe4a51ebae9311`. Repository lifecycle is `[ ]` pre-launch, with no production users/data. No nested AGENTS.md or CLAUDE.md found. No release, signing, hosted mutation, deployment, or destructive linked Supabase operation is authorized by this audit.

The inventory contains 28 accepted defects: 6 High and 22 Medium; none Critical or Low. Ten came from the initial pass, eight from independent/edge-case verification, two from continued implementation review, and eight from post-fix review. Current confidence: 27 Confirmed and one High confidence (013, whose native WorkManager entry point still needs device evidence). The original proof records remain below; section 14 and the latest validation results supersede historical intermediate status. External/device/protected validation is distinguished from local evidence.

## 2. Repository Architecture

- Flutter bootstrap: `lib/main.dart` → `lib/src/app/owntend_app.dart` → Riverpod composition/startup → GoRouter feature screens.
- Domain flows: UI → providers/controllers → repositories → transactional Drift working set/outbox → account-bound sync coordinator → Supabase gateway. Pull feed/snapshot, revision conflicts, media cache, and durable cleanup converge back into Drift watchers.
- Persistence: SQLite domain rows, outbox, shadows, cursors, account/hydration/restore state, reminders, encrypted backup containers, private local media, secure authentication storage, and settings.
- Backend: `supabase/migrations/20260821124930_initial_schema.sql` defines tables/RLS/RPC/realtime/storage; four Edge Function entry points handle account deletion, recovery status, reward SSV, and media cleanup. Auth, ownership, points, and global revisions are server authoritative.
- Native/background boundaries: Android MainActivity/native ads, permissions, notifications, WorkManager, foreground restore, location/weather, Google sign-in/ads, Shorebird, and privacy-scrubbed Sentry.
- Web/release: VersionDeck browser and service worker consume verified release metadata; public account deletion uses PKCE and protected functions. Node/PowerShell tooling and protected GitHub workflows validate pins, builds, APK/AAB provenance, signing, and publication.
- Inventory at start: 200 files under `lib`, 179 under `test`; tracked/source inventory and canonical test membership are verified through `tool/test_inventory.mjs`.

Audit allocation: data/sync/core services; Flutter app/presentation; backend/Android/VersionDeck/tooling; root integration and notifications/permissions/weather/observability/recurrence. Independent reviewers challenged each initial area; additional post-fix reviews revisited dependency boundaries, native/release behavior, startup callers and the final diff.

## 3. Validation Baseline

This table preserves baseline evidence and initial failures. The final validation table below records the corrected source state. Logs are local ignored scratch under `.tmp-bug-audit/`; this document carries durable conclusions.

| Command | Result | Interpretation |
| --- | --- | --- |
| `git status --short` | pass, empty | No pre-existing edits |
| instruction and source inventory | pass | Global instructions read; no nested overrides |
| `npm ci` | pass | 20 packages installed; npm audit reported no vulnerabilities |
| `flutter pub get` | pass | Lockfile unchanged; newer/retracted transitive package notices are not themselves verified bugs |
| `npm run validate:test-inventory` | pass | 21 canonical Node suites registered |
| `npm run test:all` | pass | 144/144 baseline Node tests |
| `npm run validate:dependency-policy` | pass | 305 package entries satisfy configured policy |
| `npm run validate:google-contracts` | pass | Repository static contracts |
| `npm run validate:docs-links` | pass | Local Markdown targets resolve |
| `npm run validate:secrets` | pass | No scanner findings in 693 files at execution time |
| `npm run validate:toolchain` | pass | All enforced host/source pins match, including Flutter 3.47.4/Dart 3.13.3 |
| `npm run supabase:lint` | pass | No schema errors on existing local stack |
| `npm run supabase:test` | fail | 35 files/649 assertions; 0036 stops at line 241 with INVALID_TASK_PAYLOAD after 13 of 17 assertions; stale stack versus source discrepancy under investigation |
| frozen Deno SSV check/test | pass | 22 tests |
| frozen Deno deletion check/test | pass | 21 tests |
| frozen Deno deletion-status check/test | expected regression failure | 13 existing tests pass; website acknowledgement regression fails |
| frozen Deno cleanup check/test | expected regression failure | 9 existing tests pass; hung-removal deadline regression fails |
| frozen Deno shared Sentry test | environment preparation incomplete | Missing npm Sentry package after npm ci; run documented frozen Deno install then retry |

Flutter focused attempts initially collided copying the Windows sqlite native asset while multiple commands ran. The subsequent serial UI run reached and reproduced two behavioral failures. Flutter tests/builds are now serialized across agents; the transient native-copy exception is not classified as a repository product defect.

## 4. Canonical Bug Inventory

| ID | Severity | Confidence | Component | Title | Primary Location |
| --- | --- | --- | --- | --- | --- |
| BUG-001 | Medium | Confirmed | Flutter Undo | Deferred Undo reads disposed route WidgetRef | task_actions.dart; task_disposal_actions.dart; trash_actions.dart |
| BUG-002 | Medium | Confirmed | Date editors | Existing dates outside fixed picker bounds crash | asset/plan editor picker methods; postpone picker |
| BUG-003 | Medium | Confirmed | Backup | Export publishes an archive its own reader rejects | backup_service.dart, _exportContainerInternal/_verifyContainerSelf |
| BUG-004 | High | Confirmed | Account deletion | A new pre-request failure destroys an older unresolved recovery operation | supabase_auth_repository.dart, _deleteAccount |
| BUG-005 | Medium | Confirmed | Web deletion | Browser acknowledgement sends a field rejected by the status function | account-deletion.js; account-deletion-status/index.ts |
| BUG-006 | Medium | Confirmed | Media cleanup | Hung I/O escapes the worker's overall deadline | process-media-cleanup/index.ts |
| BUG-007 | Medium | Confirmed | Media upload | Finalization response disagrees with canonical updated photo | initial_schema.sql; supabase_sync_gateway.dart |
| BUG-008 | Medium | Confirmed | VersionDeck | ABI enhancer restores download links for withdrawn/superseded releases | abi-downloads.js |
| BUG-009 | Medium | Confirmed | VersionDeck | An open page retains download authority after lease expiry | app.js; abi-downloads.js |
| BUG-010 | Medium | Confirmed | Asset editor | Save can replace existing tags before initialization finishes | AssetEditorDialog initialization/save |
| BUG-011 | Medium | Confirmed | Notifications | Failed cancellation destroys retry state | notification_service.dart |
| BUG-012 | Medium | Confirmed | Reminder queue | Timestamp acknowledgement erases replacement work | reminder_schedule_reconciler.dart; app_database.dart |
| BUG-013 | Medium | High confidence | Background worker | Local mode dereferences an absent session | notification_service.dart |
| BUG-014 | High | Confirmed | Account privacy | Draft cleanup misses current editor key families | offline_creation_drafts.dart |
| BUG-015 | High | Confirmed | Restore/sync | Suspension fails to prevent newly admitted work | sync_coordinator.dart and coordinator modules |
| BUG-016 | High | Confirmed | Photo import | Pixel budget is checked after allocation | photo_import_service.dart |
| BUG-017 | Medium | Confirmed | Startup | Early parallel read failure escapes error ownership | startup_bootstrap.dart |
| BUG-018 | Medium | Confirmed | Startup sign-out | UI reports signed out despite a retained session | startup_bootstrap.dart |
| BUG-019 | Medium | Confirmed | Weather | Malformed response fabricates fresh zero readings | weather_service.dart |
| BUG-020 | Medium | Confirmed | Notifications | Overdue rows starve future reminder selection | notification_service.dart |
| BUG-021 | Medium | Confirmed | Integration tooling | Teardown silently leaves disposable credential workspace behind | run_local_backend_integration.ps1 |
| BUG-022 | Medium | Confirmed | Charged editors | Own server mutation races the editor's original compare-and-set | asset/task editors; charged mutation controllers; local_sync_store.dart |
| BUG-023 | Medium | Confirmed | Photo normalization | ICC chunks are lost or serialized without required JPEG framing | photo_import_service.dart; pinned image ICC decoder/encoder boundary |
| BUG-024 | High | Confirmed | Release gates | Failed native validation is hidden by a later successful command | Shorebird release/patch validation workflow blocks |
| BUG-025 | High | Confirmed | Restore/deletion media barrier | Optional downloads can recreate media after a destructive barrier returns | sync_coordinator.dart; post_ready_coordinator.dart; media_download_cache.dart |
| BUG-026 | Medium | Confirmed | Editor recovery | Older completion deletes a newer unfinished draft | offline_creation_drafts.dart; asset/task editor completion |
| BUG-027 | Medium | Confirmed | Ready-screen lifecycle | Notification startup resumes after disposal and leaks initial read errors | startup_restoration_screen.dart; NotificationBootstrap |
| BUG-028 | Medium | Confirmed | Windows integration tooling | Apostrophes in local paths corrupt the generated server bootstrap | run_local_backend_integration.ps1; serveScript construction |

Candidates are not accepted until reachability, upstream guards, tests, and intentional contracts have been checked. Stable IDs will never be reused.

### BUG-001 — Deferred Undo loses its route owner

**Trigger/current behavior:** Trash from task/item detail automatically closes that route; the global SnackBar remains but its callback calls `ref.read` on the disposed originating widget. Undo fails, and the callback can swallow the failure because its context is no longer mounted. Completion and area/room Trash have the same deferred ownership pattern. **Expected/impact:** promised Undo remains functional after navigation; otherwise the operation cannot be recovered through the visible Undo affordance. **Root cause:** route lifetime is shorter than the global feedback queue lifetime. **Evidence/reproduction:** actual `TaskDetailScreen` → Trash confirmation → automatic route pop → Undo leaves the fake repository's `restoredPlanIds` empty in `test/ui_audit_regressions_test.dart`. Callers and global `FeedbackCoordinator` confirm reachability; no upstream lifetime guard compensates. **Related code/fix direction:** capture stable repository/service dependencies and immutable presentation data before asynchronous work; defer UI access only through a live global feedback owner. Existing tests covered Undo while the original route remained mounted.

### BUG-002 — Date pickers reject valid persisted selections

**Trigger/current behavior:** open a task editor with a due date older than 365 days, then choose its date; `showDatePicker` asserts because `initialDate < firstDate`. Far-future plan/postpone dates and pre-1990 asset dates share fixed bounds that can exclude existing values. **Expected/impact:** valid persisted dates remain editable without picker crashes. **Root cause:** presentation bounds are chosen independently from the selected persisted date. **Evidence/reproduction:** `task editor can open date picker for a long overdue task`, using now minus 800 days, fails at the Flutter picker assertion. No domain rule limits task age to one year. **Fix direction:** expand each picker range to contain the selected initial date while retaining normal selection bounds. Existing tests used contemporary dates only.

### BUG-003 — Export and restore disagree on resource limits

**Trigger/current behavior:** exporting 1,000 small photos writes a manifest exceeding the reader's 128 KiB ceiling; export reports success and publishes the file, but `inspectBackup` rejects it. **Expected/impact:** an export either satisfies the restore contract or fails before publishing/updating successful-backup state; users must not trust an unusable safety/export archive. **Root cause:** writer self-verification checks authentication/aggregate length without applying reader manifest/entry/container constraints. **Evidence/reproduction:** added `never publishes an export exceeding its manifest restore budget` in `test/backup_service_test.dart` fails against unchanged production code. **Related code:** `backup_service.dart` export, self-verification, inspection and `_validateBackup`; encrypted framing. **Fix direction:** enforce shared resource/manifest/integrity constraints before publication; verify exported contents through the reader-compatible path without arbitrary incompatible limits. Prior tests exercised corrupted imports and small successful exports separately.

### BUG-004 — Existing deletion recovery is mistaken for fresh cancellation

**Trigger/current behavior:** an unresolved deletion operation is already stored; another delete attempt fails before issuing a new request (including preparation failure or another account's retained operation). The catch block treats `!requestStarted` as safe cancellation, clears the existing recovery journal, and may resume work through the cancellation callback. **Expected/impact:** retain the original unknown-outcome operation and safety barrier until terminal authenticated/capability-bound evidence resolves it. Losing the key prevents reliable cloud-success/local-cleanup recovery. **Root cause:** the lifetime of the retained operation is conflated with the current invocation's request-start flag. **Evidence/reproduction:** two tests in `test/supabase_auth_repository_test.dart`, `pre-request failure retains recovery for user-1` and `...previous-user`, fail with a null recovery operation. **Fix direction:** distinguish new preparation from an existing unresolved operation; cleanup/cancel only a safely rejected operation created by this invocation. Existing rejection tests all began with a fresh journal.

### BUG-005 — Browser receipt acknowledgement violates the Edge request contract

**Trigger/current behavior:** after website deletion/recovery, `requestAccountDeletionStatus` sends `capability_version: web-v1.0` with acknowledgement. `readRecoveryPayload` rejects the unrecognized field, so acknowledgement receives 400. The browser ignores failure and clears recovery state. **Expected/impact:** matching completed receipts can be acknowledged, allowing documented acknowledged-retention policy; current website completions retain unacknowledged records for up to 90 days instead of the acknowledged seven-day bound. **Root cause:** caller and strict server allowlist disagree. **Evidence/reproduction:** new Deno test calls the actual website helper through the actual status handler; 13 prior tests pass and this contract test fails. **Fix direction:** send exactly the implemented request shape; preserve strict server validation. Prior browser/server tests mocked opposite sides independently.

### BUG-006 — Cleanup deadline does not bound an in-flight operation

**Trigger/current behavior:** Storage removal never resolves. The batch loop checks time only between jobs, so the invocation remains hung beyond its documented overall budget and cron request timeout. Claim/ack operations have analogous exposure. **Expected/impact:** each invocation stops within the remaining budget without false success or late unsafe acknowledgement; leased work remains retryable. **Root cause:** cooperative loop deadline without bounded/cancellable awaited network operations. **Evidence/reproduction:** new cleanup Deno test uses a 20 ms budget and proves the operation is still unresolved 200 ms later; nine existing tests pass. Documentation specifies an overall 20-second worker bound. **Fix direction:** propagate remaining time/abort to external requests and bound awaits; handle timeout as retryable with no acknowledgement of unfinished work. Existing tests only advanced the clock between completed jobs.

### BUG-007 — Finalized photo response echoes inputs instead of stored state

**Trigger/current behavior:** replace an existing photo or finalize while keeping canonical caption/primary selection. SQL UPDATE triggers advance revision and SQL expressions preserve some existing values, but the returned object reports input expected revision/caption/is_primary. The Dart gateway adopts that response directly into a `SyncRecord`. **Expected/impact:** response and canonical persisted row agree, preventing stale shadows/revision conflicts and false local primary/caption state. **Root cause:** response constructed from request fields after an authoritative mutation. **Evidence:** traced SQL finalizer → row metadata trigger → gateway `finalizeRes`; focused pgTAP replacement regression, strict gateway tests and the real application/backend lane passed. **Fix direction:** return canonical persisted photo values and timestamps from both first execution and replay, parse those on the client. Existing tests cover initial attachment/replay, not replacement with preserved fields.

### BUG-008 — ABI download rendering bypasses historical release disposition

**Trigger/current behavior:** manifest contains verified withdrawn/superseded releases. Main archive renderer disables them, but the separately fetched ABI enhancer appends active APK links for every release. **Expected/impact:** every download affordance honors active disposition and publication trust; withdrawn artifacts must remain unavailable. **Root cause:** independent download producer fails to consume shared availability policy. **Evidence:** traced `enhanceArchive`/`appendVariantChooser` after main render; actual DOM behavioral regressions in `tool/versiondeck-abi.test.mjs` passed, including independent review of all download producers. **Fix direction:** enforce one trusted release/lease eligibility predicate for all variant links and recheck activation. Existing UI assertions inspected source strings rather than rendered disabled states.

### BUG-009 — Download lease is checked only at initial rendering

**Trigger/current behavior:** keep a valid VersionDeck tab open past `leaseExpiresAt`, then activate its still-enabled APK link. Visibility/pageshow handlers only refresh relative dates; link activation does not revalidate. **Expected/impact:** expiry revokes download affordances even on an already-open or back/forward-restored page. **Root cause:** time-varying trust treated as a permanent render result. **Evidence:** cache policy expires correctly but browser producers do not consume it after initial render; actual timer, resume and activation behavioral regressions passed. **Fix direction:** refresh authority on expiry, visibility/pageshow and activation, applying consistently to primary/archive/ABI links. Existing tests check policy functions in isolation.

### BUG-010 — Asset editor can save before tags and draft initialization

**Trigger/current behavior:** slow `assetTagsProvider` or draft storage; Save remains enabled with empty tag state, so `saveAsset` can replace existing tags with empty tags. Closing while tags load allows the continuation to use disposed `ref` when loading a draft. **Expected/impact:** initial state is complete before editable/save state is presented; failure is explicit and retryable; navigation does not cause stale writes/ref access. **Root cause:** unguarded asynchronous initialization, without readiness/error state. **Evidence:** added widget test captures an enabled Save while tag load is pending; the close-path, failure/retry and tag-preservation regressions passed. **Fix direction:** one awaited initialization sequence with lifetime checks, loading/error/retry state, and no late draft overwrite of edits. Prior editor tests resolved tags immediately.

### Remaining candidates and rejected explanations

The original notification, draft, suspension, and image candidates were accepted as BUG-011 through BUG-016 after verification. They are not separate additional findings.

- Charged asset type/task move response adoption was accepted as BUG-022 after the actual editor/Drift proof returned the original name instead of the edited name.
- Existing local pgTAP 0036 failure is **rejected as a source defect**: read-only deployed-function inspection proved drift, and the fresh isolated baseline passed all assertions.

## 5. Cross-Cutting Root Causes

Supported patterns: asynchronous work can outlive route or operation ownership (001/004/010); independently tested boundaries disagree on authority or valid payload/resource shapes (003/005/007/008/009); an advertised time bound does not constrain external I/O (006). These are evidence-backed mechanisms, not reasons for unrelated architectural rewriting.

## 6. End-to-End Remediation Strategy

Complete first discovery, independently challenge findings and under-reviewed boundaries, consolidate root causes, and reconcile plans before implementation. Prefer direct pre-launch corrections. Every change must map to a confirmed bug or required regression/documentation work. Preserve safety, authorization, ownership, verification, and privacy boundaries.

## 7. Detailed Implementation Plan

These plans were walked against source before implementation. Execution results and later discoveries below supersede preliminary proof status in the historical descriptions.

| Bug | Files/symbols and numbered implementation steps | Tests / verification | Dependencies, risks, done criteria |
| --- | --- | --- | --- |
| 001 | task_actions/task_disposal_actions/trash_actions; (1) capture repository/service and immutable labels before route can close; (2) callbacks use captured operations; (3) deliver failures through coordinator; (4) audit all batch/Undo callbacks | UI regression actual route pop; task completion/navigation and batch tests; Flutter focused then full | Independent; watch account-lifetime semantics and preserve guarded completion Undo. Done: durable action works after originating route disposal and failure is visible |
| 002 | all three date-picker entry points; (1) normalize selected date; (2) contain it within lower/upper range using min/max; (3) preserve normal date constraints | old/future task and asset widget date-picker tests, English/Arabic; Flutter analyze/full | Independent; do not alter persisted dates just to satisfy picker. Done: all valid stored selections open and save |
| 003 | backup_service export/self-verification/validation; (1) share writer-reader budget checks; (2) reject before publish; (3) verify hashes/manifest/aggregate framing; (4) cleanup partial file and preserve prior success state | large-manifest regression, entry/container boundaries, roundtrip, cleanup failure; backup tests/full | Independent; safety backup uses same writer. Done: every published success is reader-compatible within contract |
| 004 | auth repository _deleteAccount; (1) track existing versus newly created recovery operation; (2) preserve existing unknown outcome on preparation/identity failures; (3) cancel only fresh safely rejected attempt; (4) review retries/status paths | existing-operation tests for same/different user, fresh definitive rejection, restart and cloud-success cleanup; auth/safety tests/full | Safety-critical, precedes restore/sync changes if confirmed. Done: no unresolved existing recovery is erased without terminal proof |
| 005 | account-deletion.js status request; (1) remove unsupported field; (2) retain strict Edge payload rules; (3) validate acknowledgement path end-to-end | actual website helper→actual handler Deno test, Node deletion suite, site build | Independent; do not widen server authorization. Done: legitimate acknowledgement succeeds and invalid extras still fail |
| 006 | cleanup worker service adapters/batch; (1) derive remaining deadline; (2) bound and abort external operations; (3) release resources and preserve retry lease; (4) never acknowledge an unfinished removal | hang claim/remove/ack, timeout and late-result tests, frozen Deno check/test, endpoint lane | Independent; timeout after ambiguous removal must remain idempotent. Done: total elapsed bound and safe subsequent retry |
| 007 | SQL finalizer and gateway parser; (1) obtain full canonical row after insert/update; (2) return same shape on replay; (3) validate canonical revision/timestamps in client; (4) update response contract tests | replacement/replay pgTAP; gateway contract; blank-baseline plus two-user media integration | Review caller map before changing shape; one pre-launch SQL baseline. Done: returned photo/shadow equals canonical row |
| 008 | ABI enhancer/shared eligibility; (1) gate historical disposition; (2) enforce publication/lease state; (3) keep disabled UI accessible | behavioral withdrawn/superseded/disabled cases, all Node tests, site build/static validator | Shares eligibility with009; preserve verified variant identity. Done: no ineligible APK href/activation is introduced |
| 009 | main/ABI download lifecycle handlers; (1) recompute trust on lease expiry and resume; (2) revoke all download links; (3) revalidate at activation; (4) avoid stale async fetch re-enabling links | fake-time expiry/visibility/pageshow/click tests; Node/site validation | Coordinate with008 to avoid parallel competing policy. Done: stale tab cannot activate expired download authority |
| 010 | AssetEditorDialog initialization/build/save; (1) await initial tags/draft before enabling editing; (2) mounted checks after awaits; (3) explicit localized loading/error/retry; (4) prevent delayed initialization replacing edits | delayed/error tags/drafts, immediate close and Save, tag preservation; widget tests/full | English/Arabic generation if new strings. Done: save never consumes incomplete initialization and closed editor has no async effects |
| 022 | asset/task editors, charged controllers, LocalSyncStore and type-change RPC; (1) persist full draft and capture immutable form/baseline/account; (2) return canonical root and detail rows; (3) controller owns accepted response through transaction; (4) accept unchanged baseline or exact own canonical state, adopt shadows, then CAS form save atomically; (5) retain draft on failure and clear only after success | real editor/Drift own-feed race; task move, genuinely newer state, account change, route disposal, malformed/replayed canonical responses; pgTAP and application/backend lane | No transaction across network, no global sync pause, no latest-timestamp bypass; reconcile detail deletions and revisions. Done: own accepted mutation cannot reject or lose remaining form edits, while competing edits and wrong accounts remain protected |
| 023 | photo import metadata boundary; (1) validate and collect bounded JPEG ICC chunks by sequence/count; (2) join complete unique segments; (3) preserve raw PNG/WebP ICC; (4) provide required single-segment sequence/count framing to pinned JPEG encoder | byte-level output profile framing and equality; reordered segmented JPEG; compressed PNG profile; malformed/incomplete/duplicate/oversized profiles | Shares preflight code with016 but distinct data-fidelity root cause. Do not strip metadata silently. Done: supported bounded input ICC survives normalization as a complete valid JPEG ICC payload |
| 024 | both Shorebird workflow validation blocks; (1) enable terminating native-command failures explicitly; (2) execute actual YAML step with harmless PATH/script stubs; (3) inject failure at every native command and assert no later command runs | Node release-workflow suite/full Node; before proof fails on flutter clean, corrected matrix passes | Preserve all existing commands, signing, environment and exact-SHA guards. No protected execution. Done: any failed validation stops before publication; no later success masks it |
| 025 | SyncCoordinator.suspend/prepareForAccountDeletion; (1) own main and optional post-ready work in the barrier; (2) fail the barrier on timeout instead of treating unfinished work as stopped; (3) test actual cache writes gated across restore/deletion and timeout/retry | Real Drift/coordinator/cache/filesystem regressions; sync, backup, deletion/startup and full Flutter suites | Complements015 admission control with existing-writer ownership. No cleanup may proceed on timeout; existing restore journal and fresh deletion cancellation handle failure. Done: successful barrier proves all existing writers stopped and failed barrier grants no destructive continuation |
| 026 | Secure draft store and all asset/copy/task consumers; (1) generate a unique persisted draft generation per save; (2) restore/capture that generation per form operation; (3) conditionally clear only that generation; (4) serialize compare/delete with all store operations across instances; (5) propagate persistence failure before RPC | Actual gated editor/Drift lifecycle with replacement draft; secure-storage replacement, ABA, concurrent compare/delete and failed-save recovery; editor and full Flutter suites | No legacy fallback or unconditional completion delete. Account-wide deletion still removes all target-account drafts. Done: an old operation can clear only its own form, and a failed save cannot falsely authorize durable recovery |
| 027 | NotificationBootstrap; (1) reject retired owners before microtask work; (2) recheck lifetime after each awaited account/configuration/notification phase; (3) own initial and resume errors including provider reads; (4) start automatic backup only from a live owner | Widget with gated account read, initialization, background registration and refresh; initial read failure; current owner positive case; existing inbox/full suites | Preserve non-prompting initialization and optional startup behavior. Do not register new background work or start backup after disposal. Existing in-flight service operations keep their own internal lifecycle |
| 028 | run_local_backend_integration.ps1 server bootstrap; (1) encode every interpolated path as a correct PowerShell literal; (2) retain the same host, argument and redirection behavior; (3) test actual script generation with spaces/apostrophes | Before/after parser or harmless invocation regression; focused/full Node; disposable endpoint runner | Independent of application code; no credentials printed, no shell interpolation of local path contents. Done: exact paths survive into separate Set-Location and CLI commands and normal runner behavior remains valid |

Documentation per fix: 001 transient-feedback/feature-catalog/testing; 002 feature-catalog/localization/testing; 003 backup-and-restore; 004 auth-and-account-deletion plus PRIVACY/SECURITY review; 005 auth/deletion and retention docs; 006 backend/functions; 007 backend/media/sync; 008/009 VersionDeck runbook/ADR; 010 feature-catalog/localization/testing. Root consolidates CHANGELOG and shared overview/current-contract changes. No deployment or production signing is part of a plan entry.

## 8. Regression Test Plan

| Bug | Test level | Scenario | Expected result |
| --- | --- | --- | --- |
| 001 | Widget integration | Detail Trash → auto-pop → Undo | Original row restored |
| 002 | Widget | Old/future saved date opens picker | No assertion; initial date preserved |
| 003 | Encrypted file/SQLite | Large manifest export | Compatible export or explicit pre-publication failure |
| 004 | Auth service | Existing recovery + new preparation failure | Recovery and barrier preserved |
| 005 | Browser helper/Edge handler | Receipt acknowledgement | Strict authorized success |
| 006 | Worker service | Hung I/O / late response | Bounded retryable termination |
| 007 | SQL/gateway | Existing photo replacement/replay | Canonical fields/revision/timestamps |
| 008 | Browser DOM | Withdrawn/superseded ABI variants | No enabled download links |
| 009 | Browser time/lifecycle | Valid tab crosses lease expiry | All download authority revoked |
| 010 | Widget/controller | Delayed initial tags/draft | Save blocked then correct tags preserved |
| 011 | Scheduler/platform boundary | Failed cancel, partial success, disabled snooze | Retry state retained without resurrecting disabled work |
| 012 | Real SQLite, independent connections | Same-second replacement and delete/reinsert ABA | Old consumer cannot acknowledge new request |
| 013 | Production background operation | Local, matching account, identity changes, no work | Correct authorized dispatcher and safe mismatch cancellation |
| 014 | Secure draft store | All five key families and adjacent account IDs | Only target account drafts removed |
| 015 | Real coordinator and startup caller | New work after suspend, restore/rollback, sign-out retry | No admitted sync until safe owner replacement |
| 016 | Image codec boundary | Oversized dimensions, compressed bombs, cyclic/large metadata | Rejection before unsafe decoder allocation; valid samples normalize |
| 017 | Real startup controller | Early parallel failure and detached cleanup errors | Immediate failure ownership without uncaught errors |
| 018 | Real startup/coordinator | Retained, cleared, throwing or successful sign-out | UI/session agree and unsafe owner stays blocked |
| 019 | HTTP/cache repository | Malformed successful response with/without cache | Old cache preserved or unavailable; no fabricated zero readings |
| 020 | Real Drift/platform scheduler | 129 overdue plans before a valid future plan | Future alarm still scheduled |
| 021 | Actual disposable Windows runner | Success/failure and teardown inspection | Owned processes/containers/workspace removed or explicit failure |
| 022 | Editor/Drift/RPC integration | Own canonical feed applied before local form continuation | Form saved with canonical shadow, competing state rejected |
| 023 | Image byte contract | PNG and segmented JPEG ICC normalized to JPEG | Exact bounded ICC payload and valid segment framing |
| 024 | Actual workflow PowerShell | Each native check fails while later stubs could succeed | Nonzero step exit and no subsequent command |
| 025 | Real coordinator/cache/filesystem | Optional download overlaps restore/deletion, including deadline expiry | Barrier waits or fails; cleanup cannot precede old writer completion |
| 026 | Editor lifecycle and secure-storage boundary | New draft replaces one owned by a pending completed operation | New form survives; exact owner can clear; concurrent storage operations remain ordered |
| 027 | Actual NotificationBootstrap widget/provider boundary | Dispose at each startup await or fail first account read | No disposed-ref error, new registration/refresh/backup, or unowned failure; live startup still runs |
| 028 | Actual PowerShell bootstrap construction | Workspace or CLI paths include spaces and apostrophes | Exact literal arguments and redirections reach the intended commands |

Tests must reach the original failure and fail when the correction is removed where practical.

## 9. Integration Validation Plan

Run canonical Flutter, Node/tooling, Deno and safe local backend gates. Validate VersionDeck static packaging. Inspect local Android compilation availability; protected production signing/publication is excluded. Review producer/consumer contracts for every fix, including failure, replay, account switching, restart, and malformed input where relevant.

## 10. Security Validation

Review RLS and owner isolation, privileged RPC authorization, delete recovery capability/receipt binding, SSV authority/replay, backup extraction and integrity, private media cleanup, logging/Sentry scrubbing, shell/path input handling, and release fail-closed verification. Never print secrets or bypass guards to obtain a green result.

## 11. Data / Migration Validation

Review schema constraints and serializer contracts, outbox durability, completion idempotency, media saga, backup/restore rollback, account binding and deletion. BUG-012 increments the local pre-launch baseline for opaque reminder request versions. Drift output was regenerated with build_runner. Fresh-baseline and previous-version rejection tests pass; the latter verifies the rejected file retains its original rows and schema version. No user's existing database was migrated or reset.

## 12. Platform / Environment Validation

Host: Windows/PowerShell. Flutter, Dart, Node/npm, Deno and Java match the enforced toolchain; Docker is available and the isolated backend lane passed. Windows reserved the default shifted backend port during the final repeat, so the supported alternative offset was validated instead. Physical Android, hosted Supabase/Google/AdMob and protected release evidence remain distinct from local tests.

## 13. Final Verification Commands

Authoritative commands: `package.json`, `docs/development/testing.md`, `.github/workflows/validate-flutter.yml`, `.github/workflows/validate-google-backend.yml`, and `docs/versiondeck-release-runbook.md`. Executed gates include dependency restore; localization/Drift generation; Dart format/analyze/full tests and production example configuration; canonical Node inventory/tests/toolchain/dependency/Google contracts/docs links/secrets; frozen Deno checks/tests; local Supabase lint/pgTAP and disposable backend integration; VersionDeck syntax/build/static validation; and the development Android debug build. Exact results and externally unavailable gates appear in Final Validation Results.

## 14. Bug-to-Fix Traceability Matrix

| Bug | Severity | Fix / root-cause correction | Regression coverage | Implemented | Focused verification |
| --- | --- | --- | --- | --- | --- |
| 001 | Medium | Captured operation ownership and live feedback presentation | route-pop Undo, failure/account change, completion, batch deadline | yes | pass |
| 002 | Medium | Picker bounds contain saved date | old/future asset/task/postpone, English/Arabic | yes | pass |
| 003 | Medium | Shared reader/writer budgets and streamed hash validation | manifest/media limits, trailing bytes, roundtrip | yes | pass |
| 004 | High | Preserve older unresolved recovery on new preparation failure | same/different identity and existing recovery journal | yes | pass |
| 005 | Medium | Exact browser acknowledgement request | real browser helper to strict Edge handler | yes | pass |
| 006 | Medium | Invocation deadline owns all external awaits/abort | hung claim/remove/ack/failure and late completion | yes | pass |
| 007 | Medium | Canonical SQL RETURNING/replay and strict gateway adoption | pgTAP revision/fields, gateway timestamps and malformed response | yes | pass, including real application/backend lane |
| 008 | Medium | Shared trusted synchronous ABI rendering | actual withdrawn/superseded/disabled controls | yes | pass |
| 009 | Medium | Revoke authority on expiry, resume and activation | actual app/ABI fake clock and capture events | yes | pass |
| 010 | Medium | Owned initialization subscription and readiness/error gate | standalone editor tag/draft delay, close, failure/retry, Save | yes | pass |
| 011 | Medium | Preserve only failed/pending cancellation state | failure/retry and disabled missing-platform snooze | yes | pass |
| 012 | Medium | Opaque SQL request versions and exact acknowledgement | same-second/ABA/failure/reopen/independent connection | yes | pass |
| 013 | Medium | Guarded local/authenticated background dispatch | local/no-work/matching account/identity changes | yes | pass for extracted production operation; device pending |
| 014 | High | All five actual draft key families | target cleanup, adjacent account/local/unrelated preservation | yes | pass |
| 015 | High | Persistent sync admission gate; retire/rebuild after safe recovery | manual/automatic/realtime/restore/rollback and real startup-owner lifecycle | yes | pass, including startup caller expansion |
| 016 | High | Bounded source headers, metadata and inflate before decoder allocation | JPEG/BMP budgets, palette/EXIF/TIFF corruption, PNG expansion, GIF record framing, valid orientation | yes | expanded 23-case photo suite passed |
| 017 | Medium | Immediate ownership of parallel reads and detached cleanup errors | pending profile plus failed tasks; both sign-out cleanup failures | yes | pass |
| 018 | Medium | Publish state from actual session; retire sign-out coordinator | retained, no-op, cleared-then-error and success; blocked original owner and fresh replacement after retry/sign-out | yes | expanded real-coordinator matrix passed |
| 019 | Medium | Reject malformed requested weather data | malformed success with/without cache; shape/type/date cases | yes | expanded matrix passed in full run |
| 020 | Medium | Apply budget after task eligibility filtering | 129 overdue plans plus valid future reminder | yes | pass |
| 021 | Medium | Stop owned child processes; always restore directory; fail on residual workspace | real isolated runner plus process/container/filesystem inspection | yes | pass |
| 022 | Medium | Atomic own-canonical reconciliation and durable form continuation | real editor/Drift race, concurrency/account/draft cases | yes | 12 store, 9 controller and 4 lifecycle tests pass; all-type real RPC parser/replay passes |
| 023 | Medium | Reassemble input ICC and emit correct output ICC framing | byte-level normalization contracts | yes | raw dependency failure and corrected framing/reassembly proved; 23 photo tests pass |
| 024 | High | Terminating native-command failure policy in both workflow steps | actual step executed with every native failure injected | yes | before fails; corrected matrix and final 148-test Node suite pass |
| 025 | High | Barriers own main and optional work across coordinator generations; timeout is failure | current/retired owner, restore/deletion, timeout/retry and auth-failure self-barrier | yes | eight filesystem cases and both manual/enable auth-failure paths pass; all 47 coordinator tests pass |
| 026 | Medium | Generation-owned conditional draft cleanup serialized across stores | old editor completes after replacement; store ABA/concurrent read-delete/failure | yes | before fails; 4 actual editor scenarios, 21 editor widgets and 26 monetization cases pass |
| 027 | Medium | Owner checks after awaited startup phases and complete error ownership | account/init/registration/refresh disposal, initial failure and positive startup | yes | three original failures reproduced; 6 lifecycle and 9 existing inbox/notification cases pass |
| 028 | Medium | Escape all PowerShell quote delimiters and preserve Unicode source encoding | actual server bootstrap under ASCII/curly apostrophe and Arabic paths | yes | original ASCII and first-fix Unicode failures proved; all six path variants and all six source-policy tests pass |

Reconciliation: each accepted BUG has a documented mechanism, source-scoped plan, regression strategy, and verification criterion. The final relevant suites and post-implementation review passed. All 28 IDs occur exactly once in the inventory and this matrix; implementation and local evidence cover every ID, with BUG-013's native dispatch explicitly external. Tooling additions support isolated cross-layer verification and correct Windows runner behavior without changing protected release authorization.

Regression-file traceability (IDs are grouped only when they share the same
executable proof; the canonical inventory above retains one row per defect):

| Bug IDs | Changed regression files / actual integration evidence |
| --- | --- |
| 001, 002, 010 | `test/ui_audit_regressions_test.dart`, `test/feedback_coordinator_test.dart`, `test/widgets/tasks_editors_test.dart` |
| 003 | `test/backup_service_test.dart` |
| 004 | `test/supabase_auth_repository_test.dart` |
| 005 | `supabase/functions/account-deletion-status/index_test.ts` calls the actual browser helper |
| 006 | `supabase/functions/process-media-cleanup/index_test.ts`; real cleanup endpoint lane |
| 007 | `test/supabase_sync_gateway_contract_test.dart`, `supabase/tests/database/0022_media_saga.test.sql`, `test/backend_integration/local_backend_sync_test.dart` |
| 008, 009 | `tool/versiondeck-abi.test.mjs` runs actual app/ABI scripts and lifecycle events |
| 011, 020 | `test/notification_schedule_diff_resilience_test.dart` |
| 012 | `test/notification_background_consumers_test.dart`, `test/database_schema_test.dart`, `test/database_baseline_rejection_test.dart` |
| 013 | `test/notification_background_consumers_test.dart`; native device dispatch remains external |
| 014 | `test/monetization_test.dart` |
| 015, 017, 018 | `test/sync_coordinator_test.dart`, `test/ui_audit_regressions_test.dart`; existing restore/startup/auth suites also run in the full lane |
| 016, 023 | `test/photo_import_service_test.dart`, including raw dependency behavior and byte-level output inspection |
| 019 | `test/weather_refresh_ownership_test.dart` |
| 021 | Actual `tool/run_local_backend_integration.ps1` execution followed by independent process/container/workspace inspection |
| 022 | `test/authoritative_editor_store_test.dart`, `test/authoritative_editor_race_test.dart`, `test/asset_creation_controller_test.dart`, `test/backend_integration/local_backend_sync_test.dart`, `supabase/tests/database/0032_authoritative_mutation_remediation.test.sql` |
| 024 | `tool/release-workflows.test.mjs` executes the real YAML steps with injected harmless native failures |
| 025 | `test/ui_audit_regressions_test.dart`, `test/sync_coordinator_test.dart`; actual Drift, media cache and filesystem boundary |
| 026 | `test/authoritative_editor_race_test.dart`, `test/monetization_test.dart` |
| 027 | `test/notification_bootstrap_lifecycle_test.dart`; existing inbox/notification widgets remain intact |
| 028 | `tool/source-policy.test.mjs` executes actual generated bootstrap source against a harmless CLI stub and verifies exact working directory, arguments and output files |

## 15. Remaining Uncertainties

Local audit and validation are complete. Device behavior, hosted deployments/configuration, protected workflows, real release artifact trust, and production signing remain outside this evidence. Their exact limits and BUG-013's native verification status are recorded below.

## 16. Pre-Implementation Completeness Review

The first and independent discovery passes produced the reconciled plans below, after which implementation began. Root owns this shared record. The subsequent post-implementation review, additional findings and final gates are recorded in the later sections; this section preserves the pre-implementation checkpoint.

The first workers were interrupted by account usage limits after adding regression proofs. Fresh second-pass reviewers independently revisited core, UI, and backend/tooling, recorded rejected candidates, and challenged their predecessors' assumptions. Later independent review covered notification/startup ownership, pinned image decoder allocation, backend contracts and release gates. Further delegation for the final paid-editor/photo review was attempted but failed on usage limits; root continued a separate source/consumer/failure-path review locally.

## Implementation Results

All 28 accepted defects have implementation changes and focused passing evidence. Section 14 separates completed local verification from BUG-013's pending native evidence; the detailed plans identify participating files and symbols. Independent subsystem owners implemented and challenged the initial and second-pass fixes. Resumed independent reviews found BUG-026/027/028 and prepared corrections or proofs before hitting usage limits; root completed their implementations and regressions. Final broader validation and the concluding re-audit passed. No commit, pull request, deployment, protected workflow, production signing or publication was performed.

## Independent-pass inventory additions and reconciled plans

These extend the canonical inventory and traceability (stable IDs are global to this record). These entries retain the discovery evidence and reconciled plans; current implementation and passing local evidence are in section 14.

### BUG-011 — Failed alarm cancellation destroys retry state

**Severity:** Medium. **Confidence:** Confirmed. **Location:** `notification_service.dart`, `_applyScheduleDiff` and `_cancelPlanRemindersNow`. **Trigger/current:** the platform `cancel` call throws; refresh logs the exception, drops the old snapshot, and returns success, or direct cancellation drops the snapshot in `finally`. **Expected/impact:** preserve failed cancellation state, report failure to the durable consumer, and retry until the stale OS alarm is removed. Otherwise deleted/disabled tasks keep firing without a repair record. **Root cause:** bookkeeping assumes cancellation succeeded even on its failure path. **Evidence/falsification:** two real scheduler/plugin-boundary tests fail: refresh resolves instead of throwing; direct cancellation throws but leaves snapshots empty. Existing resilience test exercises only failed scheduling, so no upstream test compensates.

**Plan/files:** (1) initialize applied state from known snapshots needed for retry; (2) remove a snapshot only after successful platform cancellation; (3) retain original failed changes/removals and propagate the first failure after completing other independent operations; (4) eliminate destructive `finally` in direct cancellation and preserve each independently failed ID; (5) recheck later disabled/removed/snooze behavior. **Tests:** both added tests plus partial-success cancellation and restart repair; focused notification and full Flutter suites. **Dependencies:** none. **Risk:** retaining obsolete snooze intent may re-enable it unless desired/removal state is respected; test explicit refresh after deletion. **Done:** failed cancellations remain recoverable and a later successful refresh leaves both platform and snapshots empty. **Docs:** current-contracts, notification/permission reference, testing, changelog.

### BUG-012 — Timestamp-only acknowledgement erases newer reminder work

**Severity:** Medium. **Confidence:** Confirmed. **Location:** `reminder_schedule_reconciler.dart` delete/failure predicates and `NotificationReconciliationRequests`. **Trigger/current:** enqueue a new request for the same scope 125 ms after the captured request while scheduling runs. SQLite stores both timestamps at second precision; acknowledgement deletes the replacement. Concurrent consumers can also exhibit delete/reinsert ABA with timestamp or per-key counters. **Expected/impact:** acknowledge only the exact request consumed; new state must survive for reconciliation. **Root cause:** wall time is not a unique durable request-version identity. **Evidence:** `request replaced within the same second survives acknowledgement` fails with zero remaining rows; the older test used a two-second gap and missed this. Domain editor timestamps already have their own monotonic guards, so the finding is queue-specific.

**Plan/files:** (1) add an opaque `requestVersion` to the local-only queue with random SQL default; (2) regenerate it on each update through a guarded SQLite trigger, including UPSERT/failure metadata, so all producers and independent connections share the contract; (3) compare scope plus version when acknowledging or recording failures; (4) regenerate Drift; (5) verify fresh baseline, reopen and prior-schema handling; (6) cover same-second replacement, concurrent consumers, and delete/reinsert. **Schema policy:** increment local schema version per AGENTS schema rule, maintain one clean pre-launch baseline, and explicitly reject unsupported old pre-launch schemas rather than introduce a speculative legacy migration. Add a prior-version rejection test; do not mutate any user's existing database. Backup compatibility docs must reflect the new source version. **Tests:** real SQLite consumer tests, schema baseline/reopen/rejection, complete backup/database/sync/full Flutter. **Dependencies:** generated source must precede tests; coordinate backup owner. **Risk:** recursive trigger loops, mutable version during failure, backup schema agreement; guarded trigger and end-to-end tests cover these. **Done:** no older consumer can delete/update a newer request regardless of clock precision or row recreation. **Docs:** data-model, current-contracts, backup schema policy, testing, changelog.

### BUG-013 — Local background refresh dereferences an absent session

**Severity:** Medium. **Confidence:** High confidence. **Location:** `notification_service.dart`, `owntendWorkManagerCallback`. **Trigger/current:** local-only session/account pass `notificationBackgroundAccountMatches` and may register daily work, then worker executes `session!.user.id`; the catch returns failure and retries instead of refreshing. **Expected/impact:** local-only reminders/streak maintenance work without cloud identity; bound-account mismatches still fail closed. **Root cause:** authorization helper and worker dispatch disagree on allowed local mode. **Evidence:** guard tests explicitly require local mode and registration uses optional IDs; null assertion is reached in worker with no intervening session creation. **Plan:** extract one testable daily-worker operation with injected database/session boundary and scheduler, use `drainLocal` only after a fresh unbound/no-session check, retain `drainForAccount` for matching identity and safe cancellation for mismatches; production callback delegates to it. Add local/auth/mismatch/identity-change tests. **Dependencies/risk:** avoid admitting signed-out bound data or races during account deletion. **Done:** local worker runs to completion and mismatched binding never schedules. **Docs:** routes/permissions, system-overview, current-contracts, testing.

### BUG-014 — Account cleanup misses persisted editor drafts

**Severity:** High. **Confidence:** Confirmed. **Location:** `offline_creation_drafts.dart`, `clearForAccount`; editor key producers. **Trigger/current:** delete account with asset/task create/edit drafts; cleanup searches `asset_<user>_`/`task_<user>_`, while actual keys are `asset_create_<user>_`, `asset_edit_<user>_`, `task_create_<user>_`, `task_edit_<user>_`. Sensitive draft content remains in secure storage. **Expected:** purge that account's drafts without deleting another account's drafts. **Root cause:** key producer/cleanup prefix mismatch. **Evidence:** all callers traced, regression added in monetization suite. **Plan:** enumerate actual account-scoped key families in one shared key contract used by producers and cleaner, or directly correct canonical exact prefixes if no abstraction is needed; retain copy drafts; test user-ID boundary and other-account preservation. **Verification:** focused draft tests, monetization/full Flutter. **Docs:** auth/deletion, PRIVACY, testing. **Dependencies:** none. **Risk/done:** exact delimiter prevents cross-account deletion; all supported draft families erased for target only.

### BUG-015 — Restore suspension does not prevent new sync runs

**Severity:** High. **Confidence:** Confirmed. **Location:** `sync_coordinator.dart` and coordinator modules; backup restore caller. **Trigger/current:** after `suspend()` returns, new syncNow/resume/realtime/outbox scheduling can restart because suspension advances epoch and cancels existing work but leaves no lasting gate. **Expected/impact:** no cloud mutation or read/apply overlaps staged restore until explicit safe resume. **Root cause:** cancellation of current work mistaken for admission control on future work. **Evidence:** new sync-coordinator regression, independent caller/guard tracing. **Plan:** introduce one explicit suspension state at coordinator admission boundary; gate all manual/automatic/media/realtime/resume paths, drain existing ownership, resume only explicitly after restore/recovery policy; preserve account-deletion gate independently and avoid stale callback reactivation. **Verification:** suspend→syncNow/resume/realtime, in-flight drain, explicit resume, failed restore; sync/backup/full Flutter. **Docs:** sync-protocol, backup-and-restore, current-contracts. **Dependencies:** coordinate account safety and restore failure behavior. **Done:** no network or local remote application during suspension; explicit resume restores valid account-bound work.

### BUG-016 — Pixel budget is enforced after decoding allocation

**Severity:** High. **Confidence:** Confirmed. **Location:** `photo_import_service.dart` decode worker. **Trigger/current:** small compressed image declares excessive dimensions; full decode/allocation occurs before decoded pixel limit check. **Expected/impact:** reject oversized dimensions before allocating the frame, preventing avoidable out-of-memory termination on untrusted import. **Root cause:** check is placed after the resource-consuming operation. **Evidence:** header-based regression added; decoder header metadata API and corrupt-header behavior are being verified. **Plan:** identify decoder/read bounded header metadata, validate nonzero sane dimensions and multiplication-safe pixel budget before frame decode; retain post-decode verification/orientation/output budgets. **Tests:** oversized valid/truncated header, normal formats, malformed/unsupported input, original import suite; full Flutter. **Docs:** feature-catalog, media/current contracts. **Dependencies:** verified decoder API, no guessed behavior. **Done:** excessive dimensions rejected before full image materialization without rejecting supported valid images.

### BUG-017 — Parallel startup errors escape before sequential awaits

**Severity:** Medium. **Confidence:** Confirmed. **Location:** `startup_bootstrap.dart`, `_buildInitialHomeSnapshot`. **Trigger/current:** profile remains pending while task/asset/room critical future fails; the rethrowing future has no listener until a later sequential await and becomes unhandled. **Expected/impact:** every launched task has immediate failure ownership and startup presents its controlled retry surface. **Root cause:** concurrently started futures consumed sequentially without early aggregate error handling. **Plan:** aggregate/attach handlers at creation, await all critical results through one error-owning construct, preserve typed stage failures and generation/session checks; test early task failure with delayed profile and multiple failures. **Verification:** widget startup regression plus startup/full Flutter. **Docs:** system-overview/testing. **Dependencies/risk:** optional failures must remain optional; no late stale publish. **Done:** no unhandled errors and proper retry state regardless of completion order.

### BUG-018 — Startup reports sign-out success after failure

**Severity:** Medium. **Confidence:** Confirmed. **Location:** `StartupBootstrapController.signOutFromStartup`. **Trigger/current:** auth/cleanup throws; catch logs it, then unconditional unauthenticated state hides failure even when session remains active. **Expected/impact:** derive UI state from actual session and retain recoverable failure; users must not be told sign-out completed when it did not. **Root cause:** success publication outside the success branch. **Plan:** await coordinated sign-out, publish unauthenticated only after repository session cleared, surface safe localized failure and preserve the recovery/account state on failure; test thrown auth signout with session retained and cleanup-partial path. **Verification:** startup/auth widget tests/full Flutter. **Docs:** auth/deletion, system-overview, testing. **Dependencies/risk:** avoid recovery loops or opening a partially cleaned account. **Done:** UI and underlying authentication/account safety state agree on every outcome.

### Added bug-to-plan reconciliation

| Bug | Documented | Fix planned | Regression strategy | Verification | Status |
| --- | --- | --- | --- | --- | --- |
| 011 | yes | yes | two scheduler failure/retry tests already fail | notification/full Flutter | planned |
| 012 | yes | yes | same-second real SQLite regression fails; ABA/reopen next | schema/queue/full Flutter | planned |
| 013 | yes | yes | real worker extraction/local/auth guard | notification/full Flutter | planned |
| 014 | yes | yes | actual draft family cleanup | monetization/full Flutter | focused regression passed (section 14) |
| 015 | yes | yes | suspend admission/realtime/restore | sync/backup/full Flutter | focused regression passed (section 14) |
| 016 | yes | yes | oversized header and valid decoding | photo/full Flutter | pinned decoder review and 23-case photo suite passed |
| 017 | yes | yes | delayed profile/early critical failure | startup/full Flutter | focused regression passed (section 14) |
| 018 | yes | yes | failed signout retains session | startup/auth/full Flutter | focused regression passed (section 14) |

Root notification regressions completed: 11 pass, three expected failures (two BUG-011 and one BUG-012); log `.tmp-bug-audit/notification-regressions-before.log`. All changes in these plans are directly justified by a documented mechanism or its required regression/documentation validation.

## Post-Implementation Audit

The paragraphs below preserve the historical discovery sequence; current implementation and focused status are authoritative in section 14. Independent rotated review continues and the final repository-wide pass is not complete. Root continuation identified two additional concrete candidates, with regressions added before fixes:

- **BUG-019 (Medium, high confidence): malformed successful weather responses fabricate fresh zero-valued weather.** `_snapshotFromOpenMeteo` defaults absent `current`/daily fields to zero and invalid dates to now. HTTP 200 `{}` replaces a valid cache with a fresh timestamp, 0°C, and clear weather. Plan: reject missing, malformed, nonfinite, or structurally inconsistent requested weather data at parsing; preserve the old cache/timestamp or unavailable state through the existing failure path. Keep valid zero readings and aligned empty forecast arrays supported. Tests exercise the actual HTTP parser and persisted cache before/after valid and malformed payloads. Review weather consumers, feature-catalog/current-contracts/privacy (no new data or provider), and changelog. No new SDK or network request. The subsequent proof and correction are recorded below.
- **BUG-020 (Medium, high confidence): overdue rows starve future reminders.** `listTasks` orders by due date; `_refreshSchedulesNow` truncates to 128 rows before excluding expired reminder times. With 129 overdue plans followed by a valid future plan, the future alarm is never considered although the schedule budget is empty. Plan: iterate eligible tasks until the existing scheduled-reminder cap is reached; preserve horizon, per-day cap, quiet hours, and snooze behavior. Regression uses real Drift tasks and the scheduler's platform boundary. Review notification current-contracts/reference and changelog. The subsequent proof and correction are recorded below.

BUG-019 and BUG-020 are now **Confirmed**: the real weather repository returned 0°C instead of retained 27°C and fabricated a snapshot without a cache; the real scheduler produced zero alarms with 129 overdue tasks plus one eligible future task. Both are implemented and their regressions passed in later focused and broad runs. BUG-017's early failure proof also failed with an unhandled `StartupStepException`; the aggregate failure-owner correction passed its next run. BUG-018 failed by publishing `unauthenticated` while the repository retained its session; its expanded real-coordinator regression matrix passed.

The review also refined BUG-011 so missing-platform snooze intent is retained only when still desired: disabling reminders must not resurrect it later. The new disabled-snooze case passed. File-backed request-version reopening and independent-connection replacement also passed. The full five-file focused run had 61 passing cases and six failures: the four expected BUG-018/019/020 failures and two editor-error tests still under investigation.

Core focused run: 110 passed and one obsolete draft fixture failed. That fixture used `task_<user>` and `asset_<user>` prefixes that no current editor produces; preserving them would add the prohibited pre-launch compatibility path. It is replaced by the stronger BUG-014 test covering all five actual key families, adjacent account IDs, local-mode keys, and unrelated entries. This is a test-contract correction, not removal of valid account-isolation coverage. Full rerun remains required.

## Final Validation Results

### Latest source-state verification (2026-10-04 continuation)

| Gate | Latest result and scope |
| --- | --- |
| `npm ci`; `flutter pub get`; `flutter gen-l10n`; `dart run build_runner build` | PASS: dependencies restored and required source generated; lockfiles unchanged; later changes do not alter schema or localization inputs |
| `dart format --output=none --set-exit-if-changed lib test` | PASS: 358 files, zero changes |
| `flutter analyze --no-pub` | PASS: no issues, 57.6 seconds, after the final Dart changes |
| `flutter test --no-pub test/prod_build_config_test.dart --dart-define-from-file=config/prod.example.json --dart-define=VERIFY_PRODUCTION_CONFIG=true` | PASS: 1 test; example contract only, no real production credentials or signing |
| Paid-editor focused regressions | PASS: 12 real-Drift snapshot/conflict/rollback cases, 9 controller cases, 4 actual editor lifecycle cases, 21 existing editor widgets and 26 monetization cases |
| Sync/restore generation barriers | PASS: 8 filesystem current/retired-owner and timeout/retry cases; 127 coordinator/startup/widget cases; later all 47 coordinator cases including manual/initial-enable auth-failure sign-out |
| Ready-owner notification lifecycle | PASS: 6 lifecycle regressions and 9 existing inbox/notification widget cases |
| `npm run test:backend-integration -- -IncludeApplicationIntegration` | PASS: schema lint, 35 pgTAP files / 669 assertions, 8 HTTP cleanup steps, 8 Flutter application scenarios; exit 0 |
| `npm run test:backend-integration -- -PortOffset 800` | PASS after final runner correction: schema lint, 35 pgTAP files / 669 assertions, 8 HTTP cleanup steps; exit 0 (`backend-runner-final-unicode.log`) |
| Backend teardown inspection | PASS: run workspace `owntend-backend-integration-8b9a5b00a7ae4fad94e7230ff7de25ae` absent, no owning process, no disposable containers; developer stacks untouched |
| Final runner teardown inspection | PASS: workspace `owntend-backend-integration-8a41cb2a3e064256b1583b0a952770c2` absent, zero matching processes, zero disposable containers after exit; developer stacks untouched |
| Real canonical type response | PASS within the application lane: actual Flutter repository/parser handles device, pet, plant, safety and general details, ownership, revision/timestamps and exact replay |
| `flutter test --no-pub --concurrency=1 --timeout 3m --exclude-tags production-config` | PASS: 1,080 passed, one expected backend opt-in skip, zero failures, 11m58s, after BUG-027 (`flutter-full-final-lifecycle.log`). BUG-028 changes only the independent PowerShell/Node tooling lane |
| Photo regressions | PASS: all 23, including resource bounds, raw dependency ICC failures and corrected exact bytes |
| `npm run test:all` | PASS: 148 tests across all 21 canonical Node files, zero skips/failures, 90.6s, after final BUG-028 Unicode correction (`node-final-unicode.log`) |
| `npm run validate:toolchain`; `validate:dependency-policy`; `validate:google-contracts`; `validate:test-inventory` | PASS: enforced pins match, 305 packages compliant, all 21 Node files registered (each named script executed through `npm run`) |
| `npm run validate:asset-provenance`; `validate:docs-links`; `validate:secrets` | PASS: 15 assets, all local Markdown links, 698 repository files scanned (each named script executed through `npm run`) |
| Frozen Deno function lane | PASS: format check on 11 files, frozen installs/type checks, all 71 tests across five files; unchanged since this successful run |
| VersionDeck local static artifact | PASS: top-level JavaScript syntax, 30-file build and static validator; unchanged since this successful run |
| `npm run validate:supabase-parity` | NOT VALIDATED: command exits before requests because `SUPABASE_URL` is absent. Hosted service credentials/state remain external; local SQL/feed parity coverage passed in the isolated lane |
| `flutter build apk --flavor dev --debug` | PASS: final source, Gradle 577.2s, exit 0; `build/app/outputs/flutter-apk/app-dev-debug.apk`, 278,075,110 bytes. Development/debug artifact only |
| Final diff/record reconciliation | PASS: `git diff --check`; 28 unique inventory IDs and 28 traceability rows; all 90 changed paths match the final inventory; no lockfile/native-host changes or unintended tracked artifacts |

BUG-022's actual editor regression now confirms both route disposal while the
RPC is pending and a database-triggered form-write failure. The latter retains
the full secure draft, reopens against the canonical type and saves without a
second RPC/charge. Store tests reject competing local edits, replacement/ABA
outbox intent, newer remote values/revisions and account changes; a form-write
exception rolls canonical adoption and its queue/shadow changes back. Existing
pre-request intent may have been acknowledged by a background push without
creating a false conflict. Task-move coverage retains occurrence CAS and durable
notification reconciliation.

The following entries preserve earlier intermediate runs and proof failures;
they are historical evidence, not the latest completion status.

### BUG-021 — Disposable backend teardown falsely reports complete cleanup

**Severity/confidence:** Medium, Confirmed. **Location:** `tool/run_local_backend_integration.ps1`, `Stop-DisposableStack`. **Trigger:** a successful isolated run on Windows. **Actual/impact:** the run exits successfully and stops containers, but its GUID workspace remains with `functions.env` and serving logs/scripts; future application integration also writes temporary local service-role test defines there. **Expected:** stop the owned process tree and stack, delete owned credentials/workspace unless explicit `KeepWorkspace`, and report failed cleanup. **Root cause:** only the serving shell is killed, native stderr can bypass unguarded `Pop-Location`, and recursive deletion errors are explicitly suppressed. **Evidence:** `.tmp-bug-audit/backend-integration.log` identifies workspace `owntend-backend-integration-1292c21bb1f54f36be8e740068cfca63`; independent post-run filesystem inspection found it still present with no owned container/process. This defeats the script's documented teardown guarantee. **Falsification:** not `KeepWorkspace`; canonical invocation has no flags; the log and workspace IDs match. **Plan/implementation:** terminate only the owned serving process tree, restore PowerShell location in `finally`, keep temporary path/reparse checks, bounded delete retries, explicit failure on residual resources, and truthful credential-file documentation. **Test gap:** prior assertions verified endpoints and container shutdown, not filesystem/process teardown. **Verification:** rerun actual isolated backend/application lane and inspect all three boundaries. **Docs:** testing, changelog, script help and this record. No hosted resources are involved.

After correcting the obsolete fixtures and expanding BUG-016/017, `flutter test --no-pub --concurrency=1 --timeout 3m test/photo_import_service_test.dart test/ui_audit_regressions_test.dart test/widgets/tasks_editors_test.dart` passed all 65 tests. The first attempt had a test-compilation error (`const` on the Dart IO zlib decoder), corrected before this successful rerun. Focused Dart analysis passed with no issues. All 146 canonical Node tests were repeated after the runner edits and passed.

`npm run test:backend-integration -- -IncludeApplicationIntegration` then passed schema lint, all 659 pgTAP assertions, all eight real HTTP cleanup steps, and all eight Flutter application/backend scenarios (real Auth, RLS, PostgREST, Storage, gateway, hydration, charged mutation concurrency and history restore). Exit code was zero. After terminal completion, filesystem inspection confirmed the new `owntend-backend-integration-3120cc1bfbaf4dff9d591e1482bf04ea` workspace was absent, no serving process referenced it, and Docker listed only the untouched developer stacks. This verifies the corrected teardown on Windows.

The previous workspace `C:\Users\Thulfiqar AL-Zamili\AppData\Local\Temp\owntend-backend-integration-1292c21bb1f54f36be8e740068cfca63` remains: automatic approval review rejected its explicit task-owned cleanup with only `blocked by policy`. No alternative deletion route was attempted. It contains only local disposable-stack material, but manual cleanup remains an external operational limitation.

Post-fix review (2026-09-30 continuation): the first complete Flutter run finished with **1,025 passed, one skipped, four failed**. One failure was an obsolete test directly invoking a fictional schema-1-to-2 upgrade; that test was removed in favor of the existing stronger previous-schema rejection/preserved-data regression. Three editor tests used real secure storage under fake async; their fixtures now inject the explicit draft store, with their original layout/validation assertions unchanged. No passing full-suite claim is made until rerun.

BUG-017's async ownership review also found detached signed-out notification/inbox cleanup futures. A new real-controller widget regression failed with both uncaught cleanup errors, including an error after test completion. Both independent futures now immediately enter the existing guarded optional-startup error owner; actual signed-out state is published promptly, and one cleanup failure does not suppress the other. This is additional coverage of the same startup future-ownership defect, not a duplicate bug count.

BUG-016's initial fix failed independent pinned-dependency review: JPEG `startDecode` allocates coefficient blocks before returning dimensions, BMP metadata allocates an unchecked palette, TIFF metadata follows cyclic IFD links, and PNG inflation can exceed declared pixel dimensions. Bounded source-header/metadata/inflate preflight now runs before any decoder metadata API; TIFF is explicitly unsupported. All 14 expanded photo tests passed, including valid orientation and a small PNG fixture accepted by the raw decoder but rejected for excess inflation. Full final regression remains pending.

The isolated runner's earlier residual workspace was BUG-021, corrected and verified by the later successful application/backend run and filesystem/process/container inspection above. The earlier workspace still requires manual cleanup because automatic approval review rejected its removal.

Full final regression remains pending. Completed focused evidence:

- `dart run build_runner build`: succeeded; generated Drift request-version source refreshed.
- Notification scheduling/completion/schema suites: 24 tests passed; consumer suite initially had an ambiguous test-only `isNull` import, corrected before the next run.
- `flutter test --no-pub --concurrency=1 --timeout 3m test/notification_background_consumers_test.dart test/supabase_sync_gateway_contract_test.dart`: 32 passed, including local background identity changes, same-second queue replacement/ABA/failure, and canonical photo first/replay/malformed responses. The later matched-account and no-work cases also passed in the expanded suite.
- Frozen Deno checks and focused tests: deletion status 14 passed; media cleanup 13 passed, including hung claim/remove/ack/failure and late-completion behavior.
- `node --test tool/versiondeck-abi.test.mjs tool/account-deletion-site.test.mjs`: focused backend reviewer result 24 passed. Root then ran `npm run test:all`: all 146 tests across the 21 canonical files passed, including the new actual app/ABI expiry and withdrawn-release cases.
- `npm run test:backend-integration`: isolated fresh local stack passed all 35 pgTAP files / 659 assertions and the real Edge cleanup endpoint suite / eight steps. The existing developer stack was not reset. Its earlier input-validation failure was traced by read-only function inspection to stale deployed SQL; the fresh source baseline passes. Subsequent `docker ps` confirms no owned `owntend-integration` container remains running.
- Root repeated `npm run validate:docs-links`, `npm run validate:secrets`, and `npm run validate:google-contracts`: all passed (693 repository files in the secret scan).
- Complete locked Edge lane repeated from the workflow: `deno install --frozen --config deno.json`, explicit 11-file `deno fmt --check`, each function's frozen install/type-check, and all five test files passed: shared Sentry 1, SSV 22, deletion 21, deletion status 14, cleanup 13 (71 total).
- VersionDeck local build using the checked-in manifest generator revision and inert deletion configuration passed, followed by `node tool/validate_versiondeck.mjs .versiondeck-site` and `node --check` on every top-level site JavaScript file. This is the documented pull-request static artifact; it does not establish public APK trust or authorization to publish.

Logs live in ignored `.tmp-bug-audit/`; they are local evidence, not release or hosted-deployment proof.

## Remaining Known Issues

**Known actionable repository bugs remaining: none within the audited and
validated scope.** All 28 corrections have focused evidence and their relevant
final suites passed. Twenty-seven are locally verified; the remaining native
dispatch evidence for BUG-013 is explicitly external, even though its extracted
production operation passes. The older policy-blocked temporary workspace
requires manual cleanup and is listed separately from the corrected runner's
verified teardown behavior. No claim is made that unknown bugs cannot exist.

### BUG-022 — Own charged mutation rejects the editor's remaining form changes

**Severity/confidence:** Medium, Confirmed. **Location:** asset/task editor save,
charged type-change/task-move controller, LocalSyncStore. **Trigger/current:**
the authoritative RPC advances a row's revision/timestamp, its feed is applied,
then the editor calls local save with the original timestamp. Its own accepted
mutation is treated as a competing update; other form changes are not saved.
**Expected/impact:** preserve all accepted form intent without overwriting a
genuinely newer update or charging again for recovery. **Root cause:** wallet
adoption and local form save are separate from canonical domain reconciliation.
**Evidence/reproduction:** actual AssetEditorDialog plus real Drift repository
and remote-record application in `test/authoritative_editor_race_test.dart`;
`.tmp-bug-audit/paid-editor-before.log` fails with expected `Edited name`, actual
`Original`. The prior attempt failed on a mislabeled text-field finder and was
corrected before this product proof. **Falsification:** the RPC is successful,
the protected type changed, and the applied feed is the same operation, not a
separate user edit. Existing tests only asserted wallet changes. **Plan/tests:**
section 7's atomic reconciliation and recovery plan; canonical detail rows are
required because type changes also delete/recreate detail entities. **Docs:**
monetization, sync protocol, backend contracts, feature catalog and changelog.

### BUG-023 — Normalization corrupts or loses ICC profile metadata

**Severity/confidence:** Medium, Confirmed by byte-level proof.
**Location:** photo import → pinned image decoder/encoder. **Trigger/current:**
a JPEG has multiple ICC APP2 segments, or PNG/WebP supplies raw ICC data. The
pinned JPEG decoder retains only the last segment; its encoder writes profile
data directly after the ICC signature, so raw non-JPEG profiles lack required
sequence/count framing. **Expected/impact:** complete bounded color metadata
survives normalization with valid JPEG framing; otherwise downstream renderers
may ignore or misinterpret it. **Root cause:** the decoder and encoder expose
different ICC payload representations. **Falsification:** inspect exact pinned
dependency code and output bytes, not visual similarity. **Plan/tests:** section
7; bounded adapter at import boundary, no custom image codec. **Dependencies:**
shares016 resource preflight but is a separate fidelity defect. **Docs:** media
contracts/feature catalog and changelog. The 23-test photo suite proves the raw
dependency's PNG framing and segmented-JPEG loss, then verifies exact corrected
ICC bytes and framing together with resource-boundary regressions.

### BUG-024 — Failed validation can continue into protected release work

**Severity/confidence:** High, Confirmed. **Location:** `Install exact Shorebird
CLI and validate dependencies` in both Shorebird Android workflows. **Trigger:**
an early native dependency/generation/analysis/test/toolchain command exits
nonzero and a later command succeeds. **Current/impact:** PowerShell's ordinary
`ErrorActionPreference=Stop` does not make native nonzero exits terminating;
the final successful native command overwrites LASTEXITCODE. A publish dispatch
can therefore continue despite its failed prerequisite. **Expected:** any
failed required validation stops the step before release/patch execution.
**Evidence:** the regression parses and executes the actual YAML validation
block with harmless commands and task-owned script stubs. Before the fix it
reports exit 0 after failed `flutter clean`; after enabling native error handling,
every injected native-command failure stops both blocks. Logs:
`.tmp-bug-audit/release-gate-before.log` and `release-gate-after.log`.
**Falsification/test gap:** exact-SHA, backend-gate and protected-environment
checks do not validate these command results; existing workflow tests checked
command presence/order only. **Implementation:** explicit Stop plus
PSNativeCommandUseErrorActionPreference in each validation step. **Risk:**
commands with intentionally tolerated nonzero exits need explicit handling;
all commands in these blocks are mandatory and the successful path is tested.
**Docs:** release runbook, Shorebird code-push guide, changelog. No release,
signing, network installation or protected workflow was executed by this proof.

### BUG-025 — Optional photo writers outlive a destructive barrier

**Severity/confidence:** High, Confirmed. **Location:** `SyncCoordinator.suspend`
and `prepareForAccountDeletion`, `_postReadyWork`, `MediaDownloadCache`.
**Trigger/current:** a post-ready cloud photo download is still pending when
restore or account deletion requests suspension. The barrier observes only
`_activeSync`, and even that work is detached after a timeout. It returns before
the download creates and renames its local file. **Expected/impact:** successful
suspension must prove that no old writer can recreate deleted private media or
write into the replacement restore tree. **Root cause:** admission guards stop
new work and reject stale database rows, but do not own existing filesystem
writers. **Falsification:** the gateway's download/cache path has no cancellation
or account-epoch check; the real cache writes before the coordinator checks its
result. **Proof:** real Drift/coordinator plus the actual `MediaDownloadCache`
held on a download completer. Both restore and deletion returned before release;
the original run then logged a physical file write after the barrier. See
`.tmp-bug-audit/media-barrier-before.log`. Repeating the proof after disposing
the original owner and constructing a replacement exposed the same race across
provider generations (`media-retired-before.log`, two expected failures).
**Fix:** track whole main-sync and post-ready operation settlement across
coordinator generations; disposal closes admission and advances the old epoch.
A bounded barrier joins those completion signals, including work that has not
yet reached the filesystem. Timeout propagates as failed preparation instead
of permission to clean/replace media. The original current-owner proof passed;
the eight-case generation/timeout/retry matrix passed. A real
`AccountSafetyAuthRepository` regression then caught a self-join introduced by
the stricter timeout: sync awaited sign-out, whose barrier awaited that same
sync. Authentication-failure cleanup now owns its asynchronous error and waits
for the failed run and any enabling account transition to settle before invoking
sign-out; an epoch/account check rejects stale cleanup. Both manual sync and
initial-enable paths pass with all 47 coordinator cases.
**Failure/recovery:**
restore retains its pre-mutation journal; a fresh deletion attempt can cancel
before any destructive RPC, while an older unresolved deletion stays protected.
**Test gap:** existing barrier tests asserted late row rejection and admission
control, not optional filesystem writes. **Docs:** backup, sync, deletion,
privacy, changelog and this record. No cache rewrite or compatibility shim.

### BUG-026 — An older editor completion erases a replacement draft

**Severity/confidence:** Medium, Confirmed. **Location:** asset/copy/task editor
completion and `OfflineCreationDraftStore.clear`. **Trigger/current:** editor A
persists its form and waits on the charged RPC. It closes; a reopened editor B
persists a different unfinished form under the same account/record key. A then
commits its captured form and unconditionally deletes the shared key, losing B.
**Expected/impact:** each completion clears only the draft it owns; cancelling
B's confirmation or remaining offline must preserve B's recoverable intent.
**Root cause:** a key identifies the entity, not a particular saved form version.
**Falsification:** closure is supported while saving; the second form is saved
before quote/confirmation and need not perform a competing domain mutation.
The prior lifecycle test closed A but never replaced its draft. **Proof:** the
actual AssetEditorDialog/controller/Drift scenario with a gated response and a
replacement draft fails after A completes with no draft remaining, while A's
domain form commits correctly (`final-races-before.log`). **Correction:** a fresh
generation per persisted draft, owned generation captured/restored by all three
callers, conditional clear, and one store-operation lane across instances to
make compare/delete atomic relative to writes. Storage save failures propagate
before a caller can depend on durable recovery. **Regression:** actual editor
replacement plus secure-storage stale generation, ABA, read/delete/write
interleaving and failed-save recovery. **Docs:** monetization, feature catalog,
testing, privacy review, changelog and this record. The four actual editor cases,
21 editor widget cases and 26 monetization cases pass. An initially missing
`dart:async` test import prevented the monetization file from compiling; it was
corrected and that entire file rerun successfully, without weakening assertions.

The final full Flutter run also exposed four pending-timer failures introduced
by routing detached signed-out cleanup through the startup timeout wrapper.
BUG-017 now attaches immediate handlers directly to both independent cleanup
futures. It preserves error ownership without a timeout tied to an already
retired startup surface. No existing test assertion or fixture was weakened.

### BUG-027 — Notification initialization outlives its ready-screen owner

**Severity/confidence:** Medium, Confirmed. **Location:** NotificationBootstrap
in `startup_restoration_screen.dart`, mounted only for authenticated-ready app
state. **Trigger/current:** pause its account read or scheduler initialization,
leave that state/dispose the widget, then complete the pending future. The
continuation reads a disposed WidgetRef, can register background work after
disposal, and launches automatic backup through another unowned future. An
initial account-read failure is also unhandled. **Expected/impact:** retiring
the ready owner prevents its remaining startup/resume side effects and provider
access; optional startup failures stay owned. **Root cause:** a widget-bound
async sequence lacks lifecycle checks and an error boundary covering its initial
reads. **Falsification:** actual app composition removes the widget when leaving
authenticated-ready; neither scheduler nor Riverpod keeps that WidgetRef live.
The existing test only completed happy-path initialization without disposal.
**Proof:** `notification_bootstrap_lifecycle_test.dart` failed on both disposal
paths and initial account error; its live-owner control passed (before log:
`notification-bootstrap-before.log`). **Fix:** mounted checks at entry and after
each awaited phase, initial-sequence error ownership, and provider reads inside
the owned refresh/backup boundaries. **Tests:** the three proofs plus disposal
during registration/refresh and live-owner success, existing inbox widgets and
full Flutter regression. **Docs:** system overview, startup/deletion lifecycle,
testing, changelog and this record. All six lifecycle and nine existing inbox
cases passed after correction. No permission or background feature expansion.

### BUG-028 — Apostrophes in paths corrupt the backend server bootstrap

**Severity/confidence:** Medium, Confirmed. **Location:** generated
`run-functions-serve.ps1` in `tool/run_local_backend_integration.ps1`.
**Trigger/current:** a Windows profile/temp or repository path contains an
apostrophe, such as `C:\Users\O'Neil\...`. The parent concatenates these paths
between single quotes without escaping embedded quotes. **Expected/impact:**
the server starts with exact literal paths; currently the command is malformed
or absorbed into the preceding string and the integration lane times out.
**Root cause:** file paths are inserted into generated PowerShell source without
PowerShell literal encoding. **Falsification:** a bootstrap file solves the
separate spaces-in-process-arguments problem, but not quoting inside its source;
the filesystem allows apostrophes. Independent in-memory parsing of the exact
construction yielded two commands for a normal profile and only one for
`O'Neil`, losing the Supabase invocation. **Plan/risks:** section 7; encode all
workspace/CLI/env/stdout/stderr paths consistently, preserve hidden-window and
teardown behavior, and execute/parse the actual generated construction with
harmless paths. **Test gap:** previous real local runs use paths containing
spaces but no apostrophe. **Docs:** testing, changelog and this record.

The actual generated-script regression reproduced the ASCII workspace failure
(`backend-bootstrap-before.log`). The first ASCII-only correction passed, but
independent review identified PowerShell's four curly quote delimiters and
Windows PowerShell 5.1's ANSI interpretation of BOM-less script files. A curly
path then failed in the actual Windows host (`backend-bootstrap-unicode-before.log`).
The final implementation doubles each original delimiter (U+0027, U+2018–U+201B)
and writes BOM-marked UTF-8. Six actual invocation variants cover spaces,
workspace/CLI ASCII quotes, workspace/CLI curly quotes and Arabic paths, asserting
exact working directory, CLI arguments, stdout and stderr destinations. All six
source-policy tests pass; no real CLI or credentials run in this focused proof.

The first broader runner repeat failed before schema/function serving: the
default shifted database port, 55722, is inside Windows' current excluded range
55687–55786 (`netsh interface ipv4 show excludedportrange protocol=tcp`); a direct
loopback TCP bind probe returned `AccessDenied`. The
failed run's workspace was removed and no disposable container remained. This
is a host port allocation limit, not a passing integration run. The supported
`-PortOffset 800` repeat used ports outside those reservations and passed schema
lint, all 669 pgTAP assertions and all eight HTTP steps. Its workspace, processes
and containers were verified removed after exit 0. Independent review of the final helper, UTF-8 BOM
and all six executable path variants found no additional issue. Full Node
validation then passed all 148 tests with zero skips or failures. The native
CLI/Start-Process boundary is covered by the actual runner, separately from the
harmless script-stub proof.

### Final cross-boundary follow-up

- Android/native/release review traced manifest permissions, private receivers,
  foreground restore, WorkManager callback/account checks, native/Dart channel
  names, exact-main/backend/protected-environment guards, AAB/APK provenance,
  and Sentry ABI/debug identity evidence. BUG-024 was the additional confirmed
  issue; device/OEM/reboot and protected-run behavior remain external evidence.
- Backend/site reviewer rechecked canonical photo execution/replay, SQL owner
  and primary-photo uniqueness checks, real I/O deadline/abort semantics,
  bounded telemetry flush, all download producers, expiry/resume/activation
  guards, and Windows process/container/workspace teardown. No new actionable
  defect in those corrected paths.
- Root traced automatic-backup startup/resume/reset through backup serialization,
  Sentry bootstrap/optional scope/log error ownership and scrubbers, recurrence
  and task selection. A potential patch-provider lifetime issue was rejected
  as a reachable product finding: the provider currently has no runtime callers.
- BUG-015/018 startup regression now exercises real coordinator suspension and
  replacement: retained-session failure keeps the old owner blocked; verified
  sign-out or explicit retry creates a fresh owner. All 30 UI audit regressions
  passed and focused Dart analysis reported no issues. The actual workflow
  native-failure matrix passed; the complete Node inventory then passed 147 tests.

## Validation Limitations

No claim of absolute bug freedom is made. The zero-known-actionable-bug statement is limited to explicitly audited code and actually validated environments.

- **BLOCKED — EXTERNAL VALIDATION REQUIRED (BUG-013 native entry point):** the
  production daily-worker operation passes local/authenticated/account-change
  tests, but no Android device is attached (`adb devices -l` returned none).
  Actual WorkManager isolate dispatch, OEM limits, reboot/time-zone behavior,
  platform alarms and native UI remain device evidence.
- Hosted Supabase deployment/configuration and service-only parity, Google
  sign-in/re-authentication, UMP/AdMob callbacks and one-credit hosted settlement,
  Sentry ingestion, and public VersionDeck/APK trust were not mutated or claimed
  from local tests. `validate:supabase-parity` stopped before requests because its
  explicit URL was absent. The disposable real SQL/HTTP/Flutter lane passed.
- Production configuration, protected CI jobs, signing, publication, deployment
  and real production APK/AAB provenance require authorized protected evidence.
  The example configuration and local development APK checks are separate.
- The development build emitted the pinned dependencies' future Kotlin Gradle
  Plugin compatibility warning for `sentry_flutter` and `workmanager_android`.
  The current enforced toolchain builds successfully; no future-SDK compatibility
  or production release claim follows from that result.
- The general Flutter suite skips the opt-in live-backend file when its local
  defines are absent. Its eight actual scenarios were separately executed on a
  fresh disposable stack; it is not an unexplained skipped feature test.
- Final review delegation resumed and found BUG-026, then account usage limits
  interrupted the reviewers again. Root completed the fixes and continued source,
  caller, regression and diff review. Independent findings and limits are kept
  separate from root verification.
- The earlier exact task-owned temporary workspace cleanup was rejected by
  automatic approval review (`blocked by policy`); no alternate deletion route
  was attempted. Manual cleanup remains for
  `C:\Users\Thulfiqar AL-Zamili\AppData\Local\Temp\owntend-backend-integration-1292c21bb1f54f36be8e740068cfca63`.
  Later runner-owned workspaces were independently verified removed. Ignored
  test logs and local build/static artifacts are intentional validation evidence,
  not tracked release artifacts or credentials.

## Documentation Impact

Reviewed throughout: `AGENTS.md`, `docs/governance/documentation-maintenance.md`,
`docs/README.md`, `README.md`, `CONTRIBUTING.md`, the architecture and subsystem
documents below, development/testing/toolchain guidance, release workflows and
their runbooks. Documentation changes are in the same working tree as fixes.

| Documents changed | Verified contract |
| --- | --- |
| `CHANGELOG.md` | Material unreleased fixes; no publication claim |
| `PRIVACY.md`, `SECURITY.md` | Account draft removal, deletion recovery, bounded untrusted media and retained authorization |
| `docs/architecture/auth-and-account-deletion.md` | Recovery ownership, actual sign-out outcome, retired coordinator |
| `docs/architecture/backup-and-restore.md`, `docs/architecture/data-model.md` | Shared archive budgets, restore suspension/rollback and pre-launch schema rejection |
| `docs/architecture/sync-protocol.md`, `docs/architecture/monetization.md` | Durable reconciliation identity, canonical server authority and charged workflow contracts |
| `docs/architecture/current-contracts.md`, `docs/architecture/system-overview.md` | Startup error ownership, notifications, media and current architecture |
| `docs/backend/supabase.md`, `docs/backend/migrations-and-functions.md` | Canonical photo response, bounded cleanup worker, SQL baseline |
| `docs/development/testing.md`, `docs/development/localization-and-rtl.md`, `docs/development/transient-feedback.md` | Regression paths, optional isolated application/backend lane, safe temporary files, editor dates/readiness and Undo ownership |
| `docs/product/feature-catalog.md`, `docs/reference/routes-and-permissions.md` | Actual editor, background/local reminder, weather and media behavior |
| `docs/operations/release-runbook.md`, `docs/operations/shorebird-code-push.md` | Native validation failure stops both protected release paths; CI remains external evidence |
| `docs/versiondeck-release-runbook.md`, `docs/adr/0002-versiondeck-release-verification.md` | Download disposition, lease expiry/resume/activation authority |
| `BUG_AUDIT_AND_FIX_PLAN.md` | Canonical inventory, plans, tests, current status and limitations |

Reviewed unchanged: `README.md`, `CONTRIBUTING.md`, `AGENTS.md`, documentation
policy/index, configuration/toolchain references and `docs/SENTRY_OPERATIONS.md`.
Their high-level setup, toolchain pins, privacy scrubber and protected evidence
requirements remain accurate; no new permission, SDK, configuration key, Sentry
payload, or publication authorization was introduced. Internal Markdown links
were revalidated after the latest documentation edits. Native/OEM behavior,
hosted account/reward services, protected workflows and real signed release
artifacts still require their respective external evidence.

## Completion audit

This gate is checked against the current source and executed results, not the
number of implemented patches. A passing focused regression is not substituted
for the repository-wide completion requirement.

| Requirement group | Authoritative evidence | Current disposition |
| --- | --- | --- |
| Instructions, lifecycle and original worktree | AGENTS, documentation policy, original clean status/HEAD in section 1 | complete |
| Architecture, entry points, stores, flows and trust boundaries | section 2; traced Flutter startup/UI/Drift/outbox, SQL/RLS/RPC/Storage/Edge, Android/background, browser/service worker, scripts/workflows | complete |
| Baseline, dependencies, generated sources and canonical commands | baseline table, unchanged lockfiles, pub/npm restore, localization/build_runner, final format/analysis, toolchain/inventory validators | complete |
| Initial and independent discovery, falsification, edge and cross-layer review | stable inventory, candidate rejection notes, independent subsystem reports and root proofs | complete |
| Root-cause deduplication, plans, test gaps and bidirectional reconciliation | sections 4–8 and 14; each implementation maps to its bug or required verification | complete for accepted inventory |
| Persistence, compatibility and security | real SQLite generation/rollback/rejection; fresh pgTAP owner/anonymous/invalid-input assertions; auth/deletion/reward/archive/media/privacy review | locally verified, external evidence listed separately |
| Implement all actionable fixes and test the regressions | section 14 and actual before/after proofs; final Flutter/Deno/Node/SQL/HTTP results | each of 001–028 has matching focused and relevant suite evidence; BUG-013 native dispatch remains external |
| Re-audit modified code, callers, failure paths and tests | independent final reviews of drafts, notification lifecycle and PowerShell generation; root review of sync, startup, services, native, backend/site/tooling and every changed path | complete; no additional credible defect after final corrections |
| Full supported regression and build | final validation table, example contract, current development APK, final Node/SQL/HTTP and earlier unchanged Deno/site lanes | complete locally; production/device/hosted evidence explicitly external |
| Documentation, file inventory, clean diff and secret review | documentation-impact table; internal links/secret scan; all 90 paths reconciled; final diff check | complete |
| Zero additional credible actionable findings and final reread | final independent findings resolved, concluding whole-tree review, source/test/evidence reconciliation and final record reread | complete within stated scope; external limitations retained |

Review-round accounting, excluding repeated test invocations: (1) initial
repository discovery/audit; (2) independent subsystem audit; (3) pre-implementation
edge/cross-layer and plan walkthrough; (4) implementation adversarial review
(019–020); (5) post-implementation review (021–024); (6) destructive-barrier and
caller review (025); (7) independent draft/notification lifecycle review
(026–027); (8) final independent backend/tooling review (028), including its
Unicode falsification and correction; (9) concluding source/caller/test/diff and
requirement-to-evidence review. All nine rounds are complete. The ninth found no
additional credible defect after the final corrections; build, integration,
regression, teardown, documentation and record verification support completion.

## Final changed-path inventory

The task began clean; these paths comprise the audit changes. Generated Drift output was regenerated, not hand-edited. The deleted upgrade test is replaced by stronger explicit previous-baseline rejection and preserved-data coverage.

### Backend (6)

- supabase/functions/account-deletion-status/index_test.ts
- supabase/functions/process-media-cleanup/index_test.ts
- supabase/functions/process-media-cleanup/index.ts
- supabase/migrations/20260821124930_initial_schema.sql
- supabase/tests/database/0022_media_saga.test.sql
- supabase/tests/database/0032_authoritative_mutation_remediation.test.sql

### Dart tests/support (21)

- test/asset_creation_controller_test.dart
- test/authoritative_editor_race_test.dart
- test/authoritative_editor_store_test.dart
- test/backend_integration/local_backend_sync_test.dart
- test/backup_service_test.dart
- test/database_baseline_rejection_test.dart
- test/database_migration_upgrade_test.dart
- test/database_schema_test.dart
- test/feedback_coordinator_test.dart
- test/monetization_test.dart
- test/notification_background_consumers_test.dart
- test/notification_bootstrap_lifecycle_test.dart
- test/notification_schedule_diff_resilience_test.dart
- test/photo_import_service_test.dart
- test/supabase_auth_repository_test.dart
- test/supabase_sync_gateway_contract_test.dart
- test/support/widget_test_fakes.dart
- test/sync_coordinator_test.dart
- test/ui_audit_regressions_test.dart
- test/weather_refresh_ownership_test.dart
- test/widgets/tasks_editors_test.dart

### Documentation (22)

- BUG_AUDIT_AND_FIX_PLAN.md
- CHANGELOG.md
- docs/adr/0002-versiondeck-release-verification.md
- docs/architecture/auth-and-account-deletion.md
- docs/architecture/backup-and-restore.md
- docs/architecture/current-contracts.md
- docs/architecture/data-model.md
- docs/architecture/monetization.md
- docs/architecture/sync-protocol.md
- docs/architecture/system-overview.md
- docs/backend/migrations-and-functions.md
- docs/backend/supabase.md
- docs/development/localization-and-rtl.md
- docs/development/testing.md
- docs/development/transient-feedback.md
- docs/operations/release-runbook.md
- docs/operations/shorebird-code-push.md
- docs/product/feature-catalog.md
- docs/reference/routes-and-permissions.md
- docs/versiondeck-release-runbook.md
- PRIVACY.md
- SECURITY.md

### Flutter source (31)

- lib/src/core/database/app_database.dart
- lib/src/core/database/app_database.g.dart
- lib/src/core/providers/app_providers.dart
- lib/src/core/services/backup_service.dart
- lib/src/core/services/notification_service.dart
- lib/src/core/services/photo_import_preflight.dart
- lib/src/core/services/photo_import_service.dart
- lib/src/core/services/reminder_schedule_reconciler.dart
- lib/src/core/services/weather_service.dart
- lib/src/core/sync/coordinator/post_ready_coordinator.dart
- lib/src/core/sync/coordinator/run_coordinator.dart
- lib/src/core/sync/coordinator/runtime_coordinator.dart
- lib/src/core/sync/coordinator/schedule_controller.dart
- lib/src/core/sync/local_store/editor_mutation_store.dart
- lib/src/core/sync/local_sync_store.dart
- lib/src/core/sync/supabase_sync_gateway.dart
- lib/src/core/sync/sync_coordinator.dart
- lib/src/features/assets/application/asset_creation_controller.dart
- lib/src/features/assets/presentation/asset_dialogs.dart
- lib/src/features/auth/data/supabase_auth_repository.dart
- lib/src/features/maintenance/application/task_creation_controller.dart
- lib/src/features/maintenance/presentation/maintenance_dialogs.dart
- lib/src/features/maintenance/presentation/task_actions.dart
- lib/src/features/maintenance/presentation/task_disposal_actions.dart
- lib/src/features/monetization/src/offline_creation_drafts.dart
- lib/src/features/monetization/src/wallet_contracts.dart
- lib/src/features/startup/presentation/startup_bootstrap.dart
- lib/src/features/startup/presentation/startup_restoration_screen.dart
- lib/src/features/trash/presentation/trash_actions.dart
- lib/src/ui/components/state_feedback.dart
- lib/src/ui/feedback/feedback_coordinator.dart

### Tooling/tests (5)

- tool/release-workflows.test.mjs
- tool/run_local_backend_integration.mjs
- tool/run_local_backend_integration.ps1
- tool/source-policy.test.mjs
- tool/versiondeck-abi.test.mjs

### VersionDeck (3)

- download-site/abi-downloads.js
- download-site/account-deletion.js
- download-site/app.js

### Workflows (2)

- .github/workflows/shorebird-patch-android.yml
- .github/workflows/shorebird-release-android.yml

