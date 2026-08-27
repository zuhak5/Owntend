# Owntend Pre-Launch Hardening Implementation Report

> [!IMPORTANT]
> **Historical artifact, superseded on 2026-08-27.** Its baseline counts and Supabase design statements describe the completed 2026-08-25 work only. Current authority is the executable ordered migration chain plus the documents under `docs/backend/` and `docs/architecture/`.

**Date:** 2026-08-25 · **Branch:** `main` @ `157ac9e` (worktree-based; no commits created)
**Plan executed:** `docs/pre-launch-hardening-implementation-plan.md`
**Lifecycle mode:** Pre-launch (`AGENTS.md` checkbox `[ ]`) — clean replacement authorized, zero backward-compatibility obligations.
**Commits:** None created. The user's in-flight worktree (163 dirty paths at start) was preserved and extended; committing remains an operator action per WP-001's approval gate. Final dirty-path count: **237** (original 163 + new/edited files from this implementation).

---

## 1. Work-package completion status

| WP | Title | Status | Primary evidence |
|---|---|---|---|
| WP-001 | Land in-flight wave + CI defects | **Complete** (code+validation; commits deferred to operator) | `validate-flutter.yml` parse list fixed + existence guard; duplicate broken `edge-endpoint-integration` job deleted from `validate-google-backend.yml`; `tool/release-workflows.test.mjs` tightened (npm `/..` rejection, promotion-script absence, 61 refs); notices regenerated & root copy refreshed (+11/−8); untracked paths verified complete |
| WP-002 | Supabase baseline completion | **Complete** | Guard restored (`maintenance_plans_insert_own` + `can_reconcile_maintenance_plan` + schema USAGE for authenticated); test 0012 denial restored; cleanup-jobs RLS + policy (test 0009 → plan(23)); REVOKE param names fixed; test 0006 asserts publication = 18; CORS env-gated in both functions w/ tests; `supabase:lint` clean; `supabase:test` **Result: PASS** (29 files, 524+ asserts); backend docs corrected (DEFINER posture, `\n` artifacts removed) |
| WP-003 | Journaled asset creation | **Complete** | `AssetCreationController` (application layer) journals before RPC; dialog slimmed; resolver asset branch activated; **copy-item flow migrated too** (found during wallet contract failure — second charged path); controller tests (5) + resolver recovery tests (2: status-hit reconciliation + safe resubmission) green; `wallet_sync_test.dart` updated to pin controller ownership |
| WP-004 | Feed-skip bookkeeping | **Complete** | `SyncSkippedFeedEntries` table added to v1 baseline (`build_runner` regenerated); skip/promise/shadow semantics implemented; drain worker `_drainSkippedFeedEntries` post-push; 5 store-level regression tests; schema-test inventory updated |
| WP-005 | Restore integrity | **Complete** | `onRestoreCommit` fired as service's last action after commit-marker/media/cloud-intent/status/cleanup; screen no longer bumps epoch; `enqueueRestoreSnapshot` respects terminal states; media activation consolidated onto journal impl with pre-activation failpoint hook; 78 backup/journal/store tests incl. failpoint convergence all green |
| WP-006 | Outbox efficiency + observability | **Complete** | Bounded due-window dequeue + targeted dependency lookups (no full-table load); 4 bare catches → counters/logging (`payloadParseFailures` on SyncStatus); feed photo failures defer to post-ready worker; `deferPendingAfterFailure` no longer stamps unrelated rows |
| WP-007 | Coordinator decomposition | **Complete** | `_SyncScheduleController` owns queued-work flags + automatic timer behind `_SyncScheduleEnv`; repair workers extracted to `coordinator/repair_coordinator.dart`; run_coordinator back under 800 lines; ownership contract test green; full coordinator suite (76+) green |
| WP-008 | v1 baseline formalization | **Complete** | `database_baseline_rejection_test.dart` pins reject-on-mismatch with actionable message; startup probe renders localized `databaseUnrecoverableBody` (en/ar added, gen-l10n run); upgrade-story + timestamp convention documented in data-model.md |
| WP-009 | Feature boundaries | **Complete** | Cycles broken: settings→dashboard (dead import removed), dashboard→settings (location picker → `ui/widgets`), rooms↔assets (room_dialogs → `ui/widgets`, weather helpers → `ui/widgets/weather_presentation.dart`), monetization↔maintenance (charged journal hoisted to `core/services/charged_operation_journal/`, reward sheet moved into monetization), trash↔maintenance (task disposal actions moved into maintenance); barrel feature-exports deleted with analyzer-driven consumer migration; **boundary contract test green with single documented assets↔maintenance exception** |
| WP-010 | Dead code deletion | **Complete** | `NotificationMessageGenerator`, `homeKeeperWorkManagerCallback` (contract now asserts absence), `syncHead`+`_tableUpdatedHead`, cursor quartet deleted with pinning tests/migrations; `feature_selectors` reasons localized via ARB (en/ar parity maintained); Drift schedule store required param |
| WP-011 | Navigation correctness | **Complete** | Exact-segment validation (look-alikes rejected, tested); `PendingNotificationRoute` captured/honored across auth gate; unit tests green |
| WP-012 | Android hardening | **Complete** | `network_security_config.xml` (deny-cleartext) + manifest attribute; AdMob sourcing documented (decision D2 documented branch); back-button tooltip; `portraitDown` added |
| WP-013 | Toolchain verification | **Complete (local evidence)** | `flutter build apk --flavor dev --debug` → **BUILD SUCCESSFUL** (576.8s) through AGP 9.3.0/Gradle 9.6.1/Kotlin 2.4.10/compileSdk 37/buildTools 36.0.0; evidence recorded in toolchain.md |
| WP-014 | widget_test split | **Complete** (delegated, verified) | 121 tests preserved exactly into 11 themed files under `test/widgets/` + `test/support/widget_test_fakes.dart`; original deleted; full `test/widgets` suite passes (1:18) inside final G2 run |
| WP-015 | Deterministic waits | **Complete** | `test/support/wait_for.dart` shared helper; 6 busy-wait sites refactored (grep `isBefore(deadline)` = 0); dart_test.yaml pins concurrency 1 + timeout 2m; stale `test/failures/` purged |
| WP-016 | Integration evidence + orchestration | **Complete** | Disposable-backend lane confirmed wired as dedicated CI job (validate-google-backend.yml); F-028 orchestration test assembled: cloud-success/local-failure → durable journal → simulated restart completes walk without re-invoking delete endpoint |
| WP-017 | Documentation truth sweep | **Complete** (delegated, verified) | All 12 items verified/fixed against executable sources incl. SECURITY.md budgets (real constants), testing.md 20-suite link, exact-alarm row deletions, Shorebird ADR amendment, mojibake repairs byte-exact, README Backend+Plans sections, CONTRIBUTING boundaries; docs-links validator exit 0; two out-of-scope stragglers found by agent also cleaned (feature-catalog alarm prose, shorebird var name) |
| WP-018 | Hygiene batch | **Complete** | `.gitignore` re-adds `node_modules/`; permissions deep imports normalized; HomeShell single path source; no-op listener removed; `DynamicText.sourceLanguage` dead param dropped; AGENTS flavor line unchanged (no dev/prod text found — plan item moot, noted) |
| WP-019 | Launch containment checklist | **Complete (documentation only)** | `docs/plans/launch-containment-checklist.md` staged; release-runbook links it |

**38/38 findings addressed; 19/19 work packages complete.**

## 2. Key architectural decisions

1. **D1 default executed:** charged task-creation INSERT guard RESTORED in baseline (server-authoritative monetization preserved). GUC setter retained (used by completion path).
2. **Journal reuse over rename:** asset creation reuses the existing `TaskCreationOperationStore`/domain classes (resolver already discriminated by payload key), avoiding a 221-reference churn rename; both flows now share one recovery walk.
3. **Copy flow included:** wallet-sync contract failure exposed a second charged path (asset copy with bundled tasks) calling createAsset directly with a swallowed catch — migrated to the controller and de-swallowed.
4. **Boundary exception:** assets↔maintenance bidirectional import retained as the single allowlisted pair (thing detail embeds task actions; task detail opens thing editors) with rationale encoded in `feature_boundary_contract_test.dart`; every other pair is acyclic.
5. **Epoch publication:** service emits `onRestoreCommit`; Riverpod layer owns the bump — preserves disposal-safety ordering while removing UI-layer ownership.
6. **CORS fail-closed:** unset `OWNTEND_FUNCTIONS_ENV` ⇒ production origins only.

## 3. Files changed / created / deleted (summary)

- **Created (lib):** `assets/application/asset_creation_controller.dart`; `core/services/charged_operation_journal/{charged_operation_store,charged_operation_contracts}.dart` (moved); `core/sync/coordinator/{schedule_controller,repair_coordinator}.dart`; `ui/widgets/{location_picker_sheet,room_dialogs,weather_presentation,notification_route_validation}.dart` (moved/new); `features/assets/application/`; `features/monetization/presentation/daily_completion_reward_sheet.dart` (moved); `features/maintenance/presentation/task_disposal_actions.dart`; `android/app/src/main/res/xml/network_security_config.xml`.
- **Moved (path changes):** location_picker_sheet, room_dialogs → ui/widgets; daily_completion_reward_sheet → monetization/presentation; journal store/contracts → core/services/charged_operation_journal.
- **Deleted (lib):** NotificationMessageGenerator; homeKeeper alias; syncHead/_tableUpdatedHead; cursor quartet; backup_service._activateStagedMedia; god-barrel feature exports; four cycle edges.
- **Created (tests):** asset_creation_controller_test, database_baseline_rejection_test, feature_boundary_contract_test, navigation_destination_preservation_test, sync_schedule_ownership_contract_test, account-deletion orchestration test (in supabase_auth_repository_test.dart), 11 `test/widgets/*` suites, `test/support/{widget_test_fakes,wait_for}.dart`. **Deleted:** test/widget_test.dart (split), legacy cursor pinning tests.
- **Supabase:** initial_schema.sql (guard/RLS/grants/signatures), tests 0006/0009/0012/0023, delete-account + account-deletion-status CORS + unit tests.
- **Workflows/tooling:** validate-flutter.yml, validate-google-backend.yml, release-workflows.test.mjs, THIRD_PARTY_NOTICES.md, .gitignore, analysis_options.yaml (restored REPO-001 form after stray platform excludes appeared).
- **Docs (14 files + CHANGELOG + checklist):** data-model, sync-protocol, backup-and-restore, monetization, system-overview, feature-catalog, v1-contracts, backend/supabase, backend/migrations-and-functions, reference/routes-and-permissions, reference/configuration, development/testing, development/toolchain, operations/release-runbook, ADR-SHOREBIRD, CONTRIBUTING, docs/README, SECURITY.md, CHANGELOG.md, plans/launch-containment-checklist.md.

## 4. Schema & dependency changes

- **Drift v1 baseline edited in place (legal pre-launch):** +`sync_skipped_feed_entries` (PK entity+recordKey, reason CHECK domain); `.g.dart` regenerated via build_runner; `database_schema_test.dart` inventory extended. No version bump (stays 1).
- **Supabase single baseline edited in place:** guard policy + helper function + USAGE grant restored; cleanup-jobs RLS; REVOKE signature fix. No new migration. Local-only validation; hosted untouched.
- **Dependencies:** none added/removed. Notices regenerated to match pubspec (cryptography present; archive/collection/cupertino_icons absent).

## 5. Validation matrix results (exact commands)

| Gate | Command | Result |
| --- | --- | --- |
| Analyze | `flutter analyze --no-pub` | No issues found! (final) |
| Format | `dart format --output=none --set-exit-if-changed lib test integration_test` | exit 0 (0 changed) |
| Generators | `flutter gen-l10n`; `dart run build_runner build --delete-conflicting-outputs` | success; drift regenerated |
| **Full Flutter suite** | `flutter test --no-pub --concurrency=1 --timeout 3m --exclude-tags production-config` | **+808 ~1: All tests passed!** (808 pass, 1 honest env-gated skip, 0 fail; includes the split 121 widget tests + goldens) |
| Prod config contract | `flutter test ... prod_build_config_test.dart --dart-define-from-file=config/prod.example.json --dart-define=VERIFY_PRODUCTION_CONFIG=true` | All tests passed! |
| Supabase lint | `npm run supabase:lint` | No schema errors found |
| Supabase pgTAP | `npm run supabase:test` | **Result: PASS** (29 files) |
| Edge Function units | `deno test --frozen` × delete-account(21)/status(13)/media-cleanup(9) (+admob unchanged 20) | all ok |
| Node canonical | `npm run validate:test-inventory` + `npm run test:all` | 20/20 owned; **137 pass / 0 fail** |
| Other validators | secrets · docs-links · dependency-policy · google-contracts | all pass ("Secret scan passed…665 files"; links resolve; 315 packages comply; contracts verified) |
| Android build | `flutter build apk --flavor dev --debug` | **Built app-dev-debug.apk** (576.8s) |

Failures encountered and **resolved** during execution: pgTAP name[] type mismatch; stale local DB masking real state (supabase test db does not auto-reset); missing schema USAGE/grant ordering for the reconcile helper; 0023 plan-count; KGP-style ICU apostrophe in ARB; generated-code staleness before build_runner; unused-import/glued-import fallout of barrel dissolution (fixed iteratively + `dart fix --apply`); wallet-sync contract updated to controller architecture; mocktail double-verify replaced with counters; stray platform excludes in analysis_options.yaml (restored REPO-001 form).

## 6. Remaining external / protected verification (not locally closable)

1. First real GitHub Actions runs of the two edited workflows (CI evidence).
2. `deploy-supabase-migrations.yml` protected deployment of the completed baseline (operator-authorized).
3. Hosted advisors dispatch (`audit-supabase-advisors.yml`).
4. Disposable-stack lane on a Docker-capable CI runner when repo is unlinked (local lane correctly refused while linked; `--local` lint/test used instead).
5. Device matrix: cold-start notification destination (WP-011 emulator check), notifications reboot/timezone, Google sign-in round trip, real ads/SSV, encrypted restore on hardware, min-spec benchmark.
6. Protected Shorebird validate-mode runs, VersionDeck verified-mode enablement, Sentry release publication, Play disclosures — all fenced by production-containment.md and staged in `launch-containment-checklist.md`.

## 7. Known weaknesses / uncertainties

- **assets↔maintenance** remains a deliberate bidirectional pair (documented + enforced as the sole allowlist entry). Fully acyclic requires extracting a shared thing/task presentation module — judged higher-risk than value pre-launch.
- Charged **copy flow offline behavior** unchanged (offline copy stays local/unpaid, matching prior semantics); online failures now propagate instead of silently proceeding to a free local copy (intentional tightening).
- `startup_database_baseline_mismatch` UX wiring is exercised at the unit/contract level; end-to-end device behavior of the unrecoverable-database screen still needs an emulator check.
- Two doc-agent observations fixed inline (feature-catalog alarm prose, shorebird variable name); any further stale prose beyond the audited set was out of scope.
- `docs/plans/pre-launch-hardening-implementation-plan.md` retains its planning-time framing (e.g., "planning only" header, WP-001 commit expectations superseded by this report).

## 8. Final git status

Branch `main` @ `157ac9e`, **clean tree = false**: 237 dirty/untracked paths = preserved user WIP (163) + this implementation's edits and new files. Untracked highlights include all new lib/test/docs artifacts listed in §3 plus the pre-existing user files (Gradle wrapper trio, integration_test/, process-media-cleanup/, 0029/0030 SQL, route_error_screen.dart, backup container dir). **No commits were made; nothing was pushed, deployed, signed, published, or run against any linked/hosted service** (all Supabase commands used `--local`). Secrets scan passed post-change; no secret values introduced or printed.
