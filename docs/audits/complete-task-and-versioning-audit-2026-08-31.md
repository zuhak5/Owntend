# Complete Task and versioning audit

> [!IMPORTANT]
> **Historical audit and remediation plan.** The findings below describe the
> inspected 2026-08-31 working tree. The remediation was implemented in the
> subsequent pre-launch worktree on 2026-09-01. Deleted migration names,
> superseded file paths, and line references are preserved here as audit
> evidence; current authority is the executable code, the single initial
> Supabase migration, and [`current-contracts.md`](../architecture/current-contracts.md).

Date: 2026-08-31
Scope: current working tree, including the six pre-existing uncommitted files listed below
Lifecycle authority: `AGENTS.md` is unchecked (`[ ]`), so Owntend is pre-launch with zero active users and zero production data
Change boundary: audit and plan only; no implementation, schema, migration, test, or runtime behavior was changed

The inspected working tree was already dirty before this report was created:

- `CHANGELOG.md`
- `lib/src/core/data/maintenance_repository.dart`
- `lib/src/features/maintenance/presentation/task_actions.dart`
- `supabase/migrations/20260828104729_version_maintenance_completion_contract.sql`
- `test/notification_completion_ack_test.dart`
- `test/recurring_completion_precision_test.dart`

This report audits that current state as the candidate change. Where a finding is caused by those edits, it says so explicitly. “Confirmed” means a deterministic code path or an executable test demonstrates the result. “Likely” means the failure follows from a real non-atomic boundary but requires an injected platform or storage failure not reproduced here. “Risk” means the architecture permits an undesirable outcome but product policy or external behavior is not sufficiently specified to call it a defect. “Intentional” means tests or implementation clearly pin the behavior, even if it needs a product decision.

## 1. Executive summary

The Complete Task flow is not one operation. The authoritative local database transition is atomic, but reminder scheduling, streak refresh, animation, undo presentation, reward eligibility, ad presentation, and cloud acceptance occur in separate failure domains. That split is the root of most defects.

The most serious confirmed defect is at the server boundary: the completion RPC locks the canonical plan but accepts the client’s computed `next_due_date`. On a stale-revision retry, the client changes only the expected revision and resends the old plan projection. A concurrent recurrence edit can therefore be overwritten semantically even though the RPC reports success. The server also accepts any client-selected next due date later than the client-selected completion time. This violates the documented server-authoritative mutation boundary.

The second major defect is reminder reconciliation. The current uncommitted helper launches cancellation and refresh independently. If refresh schedules the next occurrence first and cancellation runs second, the OS alarm is removed while the persisted snapshot still says it exists. The durable reconciliation consumer then sees no diff and cannot repair the missing alarm.

The local completion transaction itself has a good core: the plan compare-and-set, maintenance record, inbox acknowledgement, notification reconciliation request, and outbox command are written together. However, a four-second in-memory duplicate window can reject a genuinely new recurring occurrence; an uncommitted database lookup can label a stale attempt as an applied duplicate; and the in-memory duplicate maps are published before the outer transaction is known to have committed.

The current focused tests all pass, but several tests encode or merely scan for the broken behavior. The “two devices” test is sequential and uses an in-memory fake gateway; the Supabase “race” tests invoke RPCs sequentially; the new restart test creates another repository over the same live in-memory database rather than killing and reopening a process-backed database; and the notification acknowledgement test checks source order rather than executing the interleaving.

Key conclusions:

| ID | Classification | Severity | Conclusion |
|---|---|---:|---|
| CT-01 | Confirmed | Critical | Supabase trusts a stale client recurrence projection and can store the wrong next occurrence after a concurrent recurrence edit. |
| CT-02 | Confirmed in the current uncommitted flow | High | Concurrent reminder refresh and cancellation can permanently lose the next alarm while the snapshot claims it exists. |
| CT-03 | Confirmed and test-pinned | High | The four-second duplicate window rejects a legitimate next recurring occurrence. |
| CT-04 | Confirmed authority mismatch | High | The “Today’s care is complete” reward is client-qualified; the server verifies the ad claim but not the maintenance milestone. |
| CT-05 | Confirmed | High | Note collection can remain locked forever after a fetch error or widget unmount. |
| CT-06 | Confirmed in the current uncommitted flow | Medium | The record lookup can transform a stale occurrence into an “applied duplicate,” producing success effects for work this caller did not apply. |
| CT-07 | Confirmed | Medium | A terminal visible-failure outbox row can block its successor forever, and completion predecessor selection is not deterministically ordered. |
| CT-08 | Confirmed | Medium | UI helpers suppress reminder/streak failures and can report success after only the database portion succeeded. |
| CT-09 | Confirmed code-order defect | Medium | Duplicate state is cached before transaction commit; a late commit failure can leave false in-memory success state. |
| CT-10 | Confirmed | Low | A successful recurring completion normally reverses the TaskCard completion animation because the next occurrence is not represented as `completed`. |

The target should be an occurrence-command architecture: every plan carries a stable current occurrence identifier; each mutation states the expected occurrence; the local database writes one durable intent transaction; the server locks the plan and computes canonical recurrence; the response returns the complete canonical state; rewards bind to a server-accepted completion; and reminder reconciliation is serialized and owns both OS alarms and its snapshot.

Because the project is pre-launch, compatibility scaffolding that exists only for unpublished internal shapes should be deleted rather than extended. This includes the missing/1/2 completion request acceptance ladder, native-ad schema 1 fallback, version-suffixed internal storage keys, legacy entitlement backfills, the special Shorebird `1.0.0+4` patch bypass, and the patch migration chain after its final definitions are folded into one baseline. Technical and external versioning—database schema identity, backup format validation, change-feed protocol, native shell capabilities, application/build versions, release evidence, cache fingerprints, toolchain pins, and third-party API/schema versions—must remain.

## 2. Complete Task architecture and full call path

### Entry points

All production task-completion surfaces converge on `completeTaskWithFeedback`:

- Dashboard: `lib/src/features/dashboard/presentation/dashboard_screen.dart`, completion callback near line 373.
- Calendar: `lib/src/features/maintenance/presentation/calendar_screen.dart`, completion callback near line 168.
- Maintenance list: `lib/src/features/maintenance/presentation/maintenance_screen.dart`, completion callback near line 271.
- Asset detail: `lib/src/features/assets/presentation/thing_detail_screen.dart`, completion callback near line 457.
- Task detail: `lib/src/features/maintenance/presentation/task_detail_screen.dart`, completion callback near line 113.
- Notification inbox: `lib/src/features/notifications/presentation/notifications_screen.dart`, completion callback near lines 178-199; this surface reloads the task and only marks the inbox item read when the helper returns true.

The dashboard and calendar paths do not collect notes. The maintenance, asset-detail, task-detail, and inbox paths may collect notes. A displayed system notification does not mutate maintenance data; `NotificationService` routes notification actions into the app. Background work refreshes schedules and sync state but does not itself complete a task.

### Full text call path

```text
Dashboard / Calendar / Maintenance / Asset detail / Task detail / Inbox
    -> TaskCard or surface completion callback
    -> completeTaskWithFeedback(context, ref, task, ...)
       -> taskCompletionControllerProvider(planId)
       -> TaskCompletionController.complete(notes)
          -> DriftMaintenanceRepository.completePlanResult(...)
             -> one Drift transaction
                -> read active plan
                -> duplicate/stale checks
                -> compare-and-set plan due date
                -> calculate next recurrence locally
                -> insert maintenance record
                -> update or archive the plan
                -> acknowledge matching inbox rows
                -> insert durable notification reconciliation request
                -> insert composite outbox completion command
       -> task stream watchers publish local database state
       -> helper launches reminder cancellation and refresh
       -> helper refreshes streak state
       -> helper plays sound/animation, offers Undo
       -> helper may offer daily reward or completion ad

Pending outbox count changes
    -> SyncCoordinator wakes
    -> PushCoordinator dequeues dependency-eligible command
    -> SupabaseSyncGateway.completeMaintenanceTask(...)
    -> public SQL wrapper
    -> private complete_maintenance_task_impl(...)
       -> authenticate
       -> validate contract and payload
       -> advisory-lock user/plan and operation
       -> idempotency lookup
       -> lock canonical plan
       -> compare occurrence due date and revision
       -> insert canonical record
       -> update canonical plan from client projection
       -> write change feed and operation result
    -> strict response parser
    -> acknowledgement OR conflict reconciliation
       -> remove acknowledged outbox intent
       -> or remove losing local record and apply canonical/rollback state
       -> enqueue notification reconciliation request

Notification reconciliation request
    -> ReminderScheduleReconciliationConsumer
    -> NotificationService.refreshSchedules()
    -> derive desired alarms from current tasks/settings
    -> diff desired state against reminder snapshots
    -> cancel/schedule OS alarms
    -> replace reminder snapshots
    -> acknowledge durable request only after success
```

### State and authority boundaries

| Concern | Current authority | Durability | Assessment |
|---|---|---|---|
| Local plan/record/inbox/outbox/request transition | Drift transaction | Durable | Strong atomic core. |
| Duplicate suppression | Repository process memory plus an uncommitted record lookup | Partly durable | Incorrect identity model; time is being used as occurrence identity. |
| Recurrence calculation | Client `RecurrenceEngine` | Stored locally and then copied to server | Wrong authority for a server-accepted distributed command. |
| Cloud acceptance/conflict | Supabase RPC | Durable | Locking and operation idempotency are good, but recurrence projection is trusted. |
| Reminder alarm | Android/iOS scheduler | Platform state | Separate from Drift; snapshot is only a belief about platform state. |
| Reminder snapshot | Drift | Durable | Can become a false positive after cancel/refresh interleaving. |
| Streak | Local service derived after completion | Not in completion transaction | Eventually refreshed; helper suppresses failure. |
| Reward eligibility | Client task snapshot before the notes dialog | Not authoritative | Server validates SSV/cooldown/once-per-day, not completion eligibility. |
| UI feedback | Widget/controller memory | Ephemeral | Can celebrate duplicates and mask database/platform failures. |

The Riverpod/Drift watchers are not the primary consistency problem. Dashboard, task detail, asset detail, and statistics derive from watched database queries and converge after the transaction. The problem is that non-database effects are presented as though they were part of that same successful command.

## 3. Confirmed bugs

### CT-01 — server accepts a stale or arbitrary recurrence projection

- Severity: Critical.
- Classification: Confirmed data-integrity and authority defect.
- Files/functions: `lib/src/core/data/maintenance_repository.dart` (`completePlanResult`); `lib/src/core/sync/coordinator/push_coordinator.dart` (completion stale-revision retry near lines 542-710); `lib/src/core/sync/supabase_sync_gateway.dart` (completion RPC and strict parser near lines 706-743 and 1510-1701); `supabase/migrations/20260828104729_version_maintenance_completion_contract.sql` (`complete_maintenance_task_impl`, approximately lines 38-286).
- Root cause: the client sends a complete projected plan, including `next_due_date`; the server locks the canonical plan but does not calculate recurrence from it. When the server reports `stale_plan_revision`, `PushCoordinator` replaces only `expected_plan_revision` and resends the old projected plan.
- Exact sequence:
  1. Both devices have a plan due 2026-09-01 with monthly recurrence.
  2. Device A goes offline and completes it. The client calculates 2026-10-01.
  3. Device B changes recurrence to quarterly without changing the current due date; cloud plan revision advances.
  4. Device A reconnects and sends the old completion projection.
  5. The server correctly returns a stale revision while saying the occurrence is unchanged.
  6. The client retries with the new revision but the same 2026-10-01 projection.
  7. The RPC accepts it and stores 2026-10-01 even though the locked canonical quarterly plan implies 2026-12-01.
- More general exploit/failure: the SQL validation only requires the supplied next due date to be after the supplied completion time. A defective or hostile client can choose almost any future next due date.
- User result: a recurring task silently moves to the wrong schedule after sync.
- Data integrity: canonical cloud plan and recurrence rule disagree; all other devices hydrate the wrong next occurrence.
- Sync effect: the conflict-retry path turns a detectable stale projection into a successful corrupting write.
- Notification effect: later reconciliation schedules the wrong date consistently, so the UI and reminders agree on incorrect data.
- Reproducibility: deterministic with a fake gateway that changes only recurrence between first call and retry; current SQL tests cover a title-only stale edit, not recurrence.
- Required fix: send completion intent, not a full plan projection. The locked server plan must compute the next due date with the same canonical recurrence rules. The client must apply the full canonical response and must not retry by editing only the revision of a stale projection.

### CT-02 — refresh/cancel interleaving can permanently lose the next reminder

- Severity: High.
- Classification: Confirmed in the current uncommitted `task_actions.dart` flow.
- Files/functions: `lib/src/features/maintenance/presentation/task_actions.dart` (`completeTaskWithFeedback`, approximately lines 754-892); `lib/src/core/services/notification_service.dart` (`refreshSchedules`, `_refreshSchedulesNow`, `cancelPlanReminders`, `_applyScheduleDiff`, approximately lines 240-274, 395-520, 579-589, and 846-877); `lib/src/core/services/reminder_schedule_reconciler.dart` (`ReminderScheduleReconciliationConsumer`, approximately lines 164-258).
- Root cause: cancellation and full refresh are launched as independent unawaited futures. Cancellation removes platform alarms but does not remove their Drift reminder snapshots. Refresh treats an unchanged snapshot as proof that the OS alarm exists.
- Exact sequence:
  1. The completion transaction advances a recurring plan and writes a durable reconcile request.
  2. `completeTaskWithFeedback` starts `cancelPlanReminderSchedules(planId)` and `refreshNotificationSchedules()` independently.
  3. Refresh runs first, schedules the next occurrence using the stable plan notification ID, and persists the new snapshot.
  4. Cancellation runs second and cancels that same stable platform ID.
  5. The snapshot continues to say the new occurrence is scheduled.
  6. The durable consumer refreshes. Desired schedule equals the snapshot, so `_applyScheduleDiff` does nothing and acknowledges the request.
- Real example: complete a daily task while the device scheduler makes refresh faster than cancellation. Tomorrow’s alarm is canceled even though Settings and the database show reminders enabled.
- User result: a silently missing reminder.
- Data integrity: plan data is correct; the persisted platform-state projection is false.
- Sync effect: a later cloud acknowledgement cannot repair the alarm unless it changes schedule input or invalidates the snapshot.
- Notification effect: direct and durable; missing indefinitely rather than merely delayed.
- Reproducibility: deterministic with a controllable fake scheduler that pauses cancellation until refresh has persisted its snapshot. The current source-order test does not execute this schedule.
- Required fix: expose one serialized reconciliation operation per task/all schedules. It must calculate desired state, cancel obsolete IDs, schedule desired IDs, verify results where the platform permits, and publish the snapshot only after platform success. Completion must enqueue intent and wake that single owner; it must not launch separate cancel and refresh operations.

### CT-03 — four-second duplicate suppression drops a real next occurrence

- Severity: High.
- Classification: Confirmed and intentionally pinned by the current test suite, but wrong for recurrence identity.
- Files/functions: `lib/src/core/data/maintenance_repository.dart` (`_completionDuplicateWindow`, `_lastCompletionElapsedByPlanId`, `_lastCompletionResultByPlanId`, `completePlanResult`, approximately lines 3-24 and 329-365); `test/recurring_completion_precision_test.dart`, approximately lines 200-270.
- Root cause: elapsed process time and plan ID substitute for an occurrence identifier. A successful completion creates a new occurrence on the same plan immediately, but every call within four seconds is treated as the previous call.
- Exact sequence:
  1. Complete a daily recurring occurrence at time T.
  2. The transaction advances the plan to tomorrow and returns success.
  3. Complete tomorrow’s occurrence early at T + 500 ms from another surface or an automated test.
  4. `completePlanResult` returns the previous successful result with `duplicateIgnored=true` without evaluating tomorrow’s due date.
- Real example: a user intentionally clears two occurrences after a schedule edit or taps the next occurrence shown by another already-open view.
- User result: the second action appears handled but no second maintenance record is created and the plan does not advance.
- Data integrity: a valid user command is discarded.
- Sync effect: no second outbox intent exists, so reconnect cannot recover it.
- Notification effect: feedback/reconciliation may still run for the returned duplicate result while the new occurrence remains pending.
- Reproducibility: already deterministic in `recurring_completion_precision_test.dart`; the test currently expects suppression within the window and acceptance after five seconds.
- Required fix: delete all time-window maps. Use an explicit occurrence ID plus a unique database constraint and return an idempotent duplicate only when operation ID or occurrence ID matches the already-applied command.

### CT-04 — maintenance milestone reward eligibility is client-only

- Severity: High.
- Classification: Confirmed authority mismatch; ad reward verification itself remains server-authoritative.
- Files/functions: `lib/src/features/maintenance/presentation/task_actions.dart` (`completeTaskWithFeedback`, due-today snapshot near lines 769-778 and reward branch near the end); `lib/src/features/monetization/presentation/wallet_sheet.dart` (`showDailyRewardSheet`, approximately lines 3-28); `supabase/migrations/20260821124930_initial_schema.sql` (`create_reward_claim_request_impl`, approximately lines 631-747); `lib/l10n/app_en.arb` keys near lines 1492-1493.
- Root cause: the helper decides “final task due today” before an optional notes dialog and before cloud acceptance. The server checks authentication, reward configuration, cooldown, once-per-day rules, and SSV claim state, but it does not verify that a maintenance completion occurred or that no other task is due.
- Exact sequence:
  1. Client snapshot says this is the last due-today task.
  2. While the notes dialog is open, another task becomes due, the date rolls over, another screen changes state, or this completion later loses a cloud conflict.
  3. Local completion returns applied and the client presents “Today’s care is complete.”
  4. The rewarded ad flow can create a server-valid claim unrelated to the maintenance milestone.
- Real example: two devices complete the same occurrence; the losing device presents the milestone reward before reconciliation removes its local record.
- User result: points can be earned under a false maintenance-success explanation.
- Data integrity: wallet balances remain server-authoritative for SSV, but business eligibility and maintenance history are not atomically related.
- Sync effect: the maintenance completion can be rejected after the reward claim remains valid.
- Notification effect: none directly.
- Reproducibility: deterministic by invoking the reward request from an authenticated client without a maintenance completion; the SQL path has no maintenance predicate.
- Required fix: either remove the maintenance-milestone claim from the reward UX, or have the completion RPC issue a single-use server eligibility token after canonical acceptance and require that token in reward-claim creation. Re-evaluate today boundaries server-side under an explicitly documented timezone policy.

### CT-05 — note collection can remain permanently locked

- Severity: High.
- Classification: Confirmed controller-state defect.
- Files/functions: `lib/src/features/maintenance/presentation/task_completion_controller.dart` (`beginCollectingNotes`, `cancelCollectingNotes`, `complete`, approximately lines 33-111); `lib/src/features/maintenance/presentation/task_actions.dart` (`completeTaskWithFeedback`, approximately lines 754-792).
- Root cause: `beginCollectingNotes` mutates a long-lived non-auto-disposed family provider, but every exit between that mutation and `cancelCollectingNotes`/`complete` is not protected by `try/finally`.
- Exact sequence A: begin collection; the fallback tasks provider throws; the helper exits through the exception; controller remains `collectingNotes`.
- Exact sequence B: begin collection; awaiting task data or the dialog completes after the widget unmounts; the `!context.mounted` return executes without canceling; controller remains `collectingNotes`.
- Real example: navigate away while task loading or the notes sheet is resolving, then return and try to complete the same plan with notes.
- User result: future note-collection attempts for that plan return false and do not open the dialog.
- Data integrity: no database corruption, but a valid completion path is disabled until provider/container recreation.
- Sync/notification effect: no command or reconciliation request is created.
- Reproducibility: deterministic with a completer-backed task provider and widget disposal before resolution.
- Required fix: scope the controller lifecycle with `autoDispose` where appropriate and put collection ownership in a `try/finally`; distinguish dialog cancellation, widget disposal, fetch failure, and active commit.

### CT-06 — a stale occurrence can be reported as an applied duplicate

- Severity: Medium.
- Classification: Confirmed semantic defect introduced by the current uncommitted repository edit; cross-connection collision protection remains unproven.
- Files/functions: `lib/src/core/data/maintenance_repository.dart` (`completePlanResult`, record lookup by `plan_id` and `due_date`, approximately lines 372-393); `test/recurring_completion_precision_test.dart`, new test near lines 531-584.
- Root cause: before the due-date compare-and-set, the repository looks for any maintenance record with the submitted plan ID and due date. If found, it returns `applied=true, duplicateIgnored=true`, regardless of the caller’s operation identity.
- Exact sequence:
  1. Screen A displays occurrence X.
  2. Screen B completes X and advances the plan.
  3. Screen A submits stale X.
  4. The record lookup finds B’s record and labels A’s command an applied duplicate.
  5. The helper may play completion feedback, update streak presentation, or offer completion-related UI even though A applied nothing.
- User result: false success feedback and duplicate side effects.
- Data integrity: the stored record remains singular in the sequential case, but there is no unique `(plan, occurrence)` constraint proving singularity across independent database connections.
- Sync effect: A creates no new operation, so operation-specific acknowledgement cannot be correlated.
- Notification effect: helper side effects can still run against an already-advanced task.
- Reproducibility: deterministic sequentially. The new test creates a second repository around the same still-open in-memory database; it does not prove process restart or concurrent connection safety.
- Required fix: uniqueness and idempotency must be structural: explicit occurrence ID, operation ID, and a unique constraint. A stale caller should receive `already_completed_elsewhere` with canonical state, not `applied`.

### CT-07 — outbox dependency selection can block a successor forever

- Severity: Medium.
- Classification: Confirmed queue-state defect.
- Files/functions: `lib/src/core/sync/local_store/outbox_store.dart` (due-row filtering and dependency eligibility, approximately lines 395-480); `lib/src/core/sync/local_store/mutation_store.dart` (terminal `failedVisible` encoding with negative attempts, approximately lines 134-169); `lib/src/core/data/maintenance_repository.dart` (completion predecessor scan, approximately lines 419-446).
- Root cause: a referenced predecessor blocks a successor whenever its state is not `conflict`. A terminal visible failure remains stored with `attempts=-1` and is excluded from dequeue, but its state still blocks the successor. Completion predecessor selection also scans completion rows without a deterministic non-null insertion sequence; `createdAt` is nullable and the completion insert does not set it.
- Exact sequence:
  1. Operation A is selected as the predecessor for completion B.
  2. A reaches terminal visible failure and remains in outbox with negative attempts.
  3. B’s `depends_on_operation_id` continues to reference A.
  4. A is never due again; B remains dependency-ineligible forever.
- Real example: an older completion receives a non-retryable contract error; the next offline completion for the plan is chained behind it.
- User result: later valid work remains local and never reaches cloud.
- Data integrity: local and remote histories diverge indefinitely.
- Sync effect: direct permanent queue blockage.
- Notification effect: local reminders can advance while other devices never receive the corresponding history.
- Reproducibility: deterministic by inserting a terminal predecessor and a due successor.
- Required fix: model terminal predecessor outcomes explicitly. A failed predecessor must either cause deterministic rollback/conflict of dependents or release/rebase them. Use a non-null monotonically ordered local sequence and plan/occurrence scoping; do not discover dependencies by scanning nullable timestamps.

### CT-08 — partial success is presented as full success

- Severity: Medium.
- Classification: Confirmed error-propagation defect.
- Files/functions: `lib/src/features/maintenance/presentation/task_actions.dart` (`cancelPlanReminderSchedules`, `refreshNotificationSchedules`, `completeTaskWithFeedback`, and skip/postpone helpers); `lib/src/features/maintenance/presentation/task_disposal_actions.dart`; `lib/src/features/trash/presentation/trash_screen.dart`; `lib/src/core/data/streak_service.dart`.
- Root cause: reminder helper functions catch and suppress errors, return `void`, and callers surround them with ineffective `try/catch` blocks or launch them unawaited. Streak refresh errors are also intentionally swallowed. The UI success boolean therefore describes the Drift mutation only, not the user-visible operation advertised by the toast/animation.
- Exact sequence: database commit succeeds; platform scheduler throws; helper suppresses the exception; success sound/toast/animation proceeds; durable recovery may be absent for skip, postpone, edit, trash, or restore.
- Real example: exact-alarm scheduling fails after a task is postponed. The UI says the task was postponed, but the old/new alarm state is unknown and there is no durable reconciliation request for that mutation.
- User result: false assurance and possibly stale or missing reminders.
- Data integrity: domain data is correct; platform projection is not guaranteed.
- Sync effect: unrelated to cloud acknowledgement, so successful sync does not prove reminder success.
- Notification effect: direct.
- Reproducibility: deterministic with a throwing fake notification service.
- Required fix: return typed outcomes, persist reconciliation intent for every schedule-affecting mutation in the same database transaction, and let the durable consumer own retries. UI should say the task changed while reminder repair is pending if reconciliation is not yet confirmed.

### CT-09 — duplicate cache can publish success before commit

- Severity: Medium.
- Classification: Confirmed code-order defect; the platform-specific late-commit failure is a likely trigger.
- Files/functions: `lib/src/core/data/maintenance_repository.dart` (`completePlanResult`, assignments near the end of the transaction callback around lines 570-571).
- Root cause: `_lastCompletionElapsedByPlanId` and `_lastCompletionResultByPlanId` are assigned inside the Drift transaction callback. The outer transaction future has not yet completed its commit when those assignments occur.
- Exact sequence: transaction statements finish; maps receive success; commit fails or is rolled back by a late storage error; caller receives failure; a retry within four seconds returns the cached successful result without writing data.
- User result: apparent success with no record or plan advance.
- Data integrity: process memory claims a committed state that the database rejected.
- Sync/notification effect: no durable outbox or reconciliation request exists, but UI side effects can run on retry.
- Reproducibility: requires a database harness that fails commit after callback completion; the unsafe order is explicit in code even though that harness was not run.
- Required fix: delete the time-based cache. If any post-commit cache remains, populate it only after the transaction future resolves successfully.

### CT-10 — successful recurring completion reverses its own animation

- Severity: Low.
- Classification: Confirmed UI-state defect.
- Files/functions: `lib/src/ui/components/task_status.dart` (`TaskCard` completion handler, approximately lines 518-545); `lib/src/core/domain/task_selectors.dart`, status derivation near lines 70-79.
- Root cause: the card reverses the completion animation when the original widget task is not `TaskStatus.completed`. A recurring success advances to a new due/upcoming occurrence; `completed` represents inactive/archived state, and the original widget is not refreshed before the check.
- Exact sequence: animation plays before the callback; completion succeeds; original recurring task status remains due/upcoming; the success branch reverses the animation.
- User result: success visually resembles rollback or failure.
- Data integrity/sync/notification effect: none.
- Reproducibility: deterministic widget test for a successful recurring callback; the existing test asserts failure reversal only.
- Required fix: make the callback outcome authoritative for the immediate animation. Render the next occurrence when watched state arrives rather than using the stale input task to infer success.

### Important behavior that is not classified as a confirmed bug

- `RecurrenceEngine` anchors the next due date to actual completion time for all recurrence types. Tests pin this behavior. For example, quarterly due 1 January completed 20 January becomes 20 April, and an overdue monthly task completed 20 May becomes 20 June. This is intentional implementation behavior but a product-policy risk because the UI does not explain it.
- Hourly recurrence uses elapsed duration; daily/weekly/monthly/yearly recurrence uses local calendar arithmetic and month-end clamping. This is intentional code, but timezone and DST policy is undocumented and untested.
- Client device time is trusted as `completed_at`. That is an integrity risk until allowed clock skew and authoritative time semantics are specified; it is not called a confirmed defect here because offline completion policy is not stated.
- Drift watchers provide eventual UI convergence after a transaction. Temporary presentation lag is expected and is not itself evidence of lost data.

## 4. Race matrix

| Scenario | Correct outcome | Current behavior | Classification | Required test/fix |
|---|---|---|---|---|
| Rapid double tap in one `TaskCard` | One operation; second tap ignored before effects | Widget-local `_completing` generally blocks the second tap in that widget | Intentional/adequate locally | Keep UI guard, but do not treat it as idempotency. |
| Rapid taps in two cards/screens | One winner; loser gets explicit canonical `already completed` result without celebration | Separate widget guards and shared provider do not fully serialize note/no-note paths; repository time window or record lookup can return applied duplicate | Confirmed semantic defect | Occurrence ID + unique constraint + typed loser outcome. |
| Notes modal open while no-notes surface completes | Modal submit should resolve against the same occurrence and report it was completed elsewhere | `collectingNotes` does not prevent `complete`; later modal submit can be labeled applied duplicate | Confirmed | Controller command token must include occurrence ID; stale modal receives canonical loser state. |
| Stale screen submits old due date | No mutation; explicit stale occurrence response | Dirty record lookup can report applied duplicate; without a matching record, CAS reports occurrence changed | Confirmed for false applied classification | Remove record-presence-as-idempotency. |
| Legitimate next occurrence completed within four seconds | Second occurrence commits | Time window returns previous result | Confirmed | Delete time window. |
| Offline completion then reconnect | Durable local intent pushes once; canonical response reconciles | Basic path works and focused test passes | Covered with limitation | Add process-backed restart and real integration coverage. |
| Process death after local DB commit, before helper side effects | Outbox and reminder intent resume; no duplicate user reward | Completion/outbox/request survive; startup/daily/sync consumer can refresh. UI reward/streak state is not durable | Partly robust/risk | Persist only effects that need exactly-once behavior; recompute streak; bind reward to server operation. |
| Process death after cancel but before refresh | Durable request repairs alarms | Usually repairable because snapshot still differs, but not if a concurrent refresh already wrote the desired snapshot | Confirmed CT-02 branch | Serialized scheduler ownership and snapshot invalidation. |
| Two devices complete same occurrence | One canonical winner; loser rolls back local record and adopts canonical state | Advisory lock and due check support this; sequential fake test passes | Likely correct, concurrency unproven | Concurrent Supabase sessions plus device reconciliation test. |
| Two devices: one edits recurrence, one completes stale plan | Server computes from locked canonical recurrence | Client retries stale projection with only new revision | Confirmed CT-01 | Intent-only RPC and server recurrence engine. |
| RPC response lost after server commit | Same operation returns stored canonical result | Operation-level advisory lock and operation-result lookup appear idempotent | Intentional/strong | Real integration test that drops first response then repeats exact operation. |
| Reminder scheduler throws before any platform mutation | Domain mutation remains; durable repair should stay pending | Completion request can retry; other schedule-changing mutations often have no durable request and helper suppresses error | Confirmed coverage gap/defect | Generalize request insertion to all mutations. |
| Scheduler partially schedules then throws | Snapshot must not claim unknown platform state; next attempt repairs | Platform calls and snapshot replacement are not one transaction; partial platform state is possible | Likely | Fault-injection at every scheduler call; idempotent full reconciliation. |
| Undo after completion | Restore only if completion is still latest occurrence | `undoCompletion` finds latest record and uses expected due CAS; it also creates a compensating outbox command | Intentional/stronger design | Add two-screen/two-device stale undo tests. |
| Completion loses cloud conflict after local celebration | Roll back local record, adopt canonical state, repair reminders, do not grant milestone reward | Data reconciliation exists; already-presented UI/reward cannot be revoked atomically | Confirmed reward/UX mismatch | Delay authoritative reward until acceptance; present local completion as pending when offline. |
| Device clock jumps across midnight while notes modal is open | Eligibility and recurrence follow documented clock policy at commit | “Last due today” is captured before modal; completion time is captured later | Confirmed stale eligibility, policy risk | Evaluate at commit/acceptance under one timezone policy. |
| Terminal predecessor in outbox | Dependents rebase, fail visibly, or roll back | Negative-attempt predecessor is never retried yet blocks successors | Confirmed CT-07 | Explicit terminal dependency resolution. |

## 5. Similar bugs elsewhere

### SM-01 — stale Skip advances a newer occurrence

- Classification/severity: Confirmed, High.
- Files/functions: `lib/src/core/data/maintenance_repository.dart`, `skipPlanOccurrence` near lines 777-821; presentation helper in `task_actions.dart`.
- Pattern: the command accepts only plan ID, rereads whatever occurrence is current, and advances it. It has no expected occurrence ID or expected due date.
- Sequence: screen A shows occurrence 1; screen B completes or skips to occurrence 2; screen A confirms its stale skip; repository skips occurrence 2 to occurrence 3.
- Fix: every occurrence mutation must compare an expected occurrence ID inside its transaction.

### SM-02 — stale Postpone moves a newer occurrence

- Classification/severity: Confirmed, High.
- Files/functions: `lib/src/core/data/maintenance_repository.dart`, `postponePlan` near lines 824-871; presentation helper in `task_actions.dart`.
- Pattern: no expected occurrence is supplied. A stale dialog can postpone the new current occurrence if its selected target date still passes validation.
- Fix: same occurrence CAS; postponement keeps occurrence identity while changing its due date.

### SM-03 — schedule-changing mutations lack durable reminder intent

- Classification/severity: Confirmed design defect, High.
- Files/functions: skip/postpone/edit/enable/archive/trash/restore paths in `maintenance_repository.dart`, `task_actions.dart`, `maintenance_dialogs.dart`, `task_disposal_actions.dart`, and `trash_screen.dart`.
- Pattern: these paths mutate durable scheduling inputs, then call a best-effort helper outside the transaction. Completion and undo insert durable reconciliation requests; adjacent mutations generally do not.
- Result: process death or a suppressed scheduler exception can leave stale alarms forever.
- Fix: one repository-level schedule-affecting mutation primitive must insert a generalized reconciliation request transactionally.

### SM-04 — task plan editor is last-writer-wins

- Classification/severity: Likely concurrency defect, Medium.
- Files/functions: `lib/src/core/data/maintenance_repository.dart`, `savePlan` near lines 174-253.
- Pattern: a full plan snapshot is written without expected revision/updated-at/occurrence checks. Two open editors can overwrite unrelated changes.
- Why not “confirmed”: whether last-writer-wins is acceptable product behavior is not explicitly specified, but it conflicts with the sync system’s revision-aware intent.
- Fix: patch commands with expected revision and field-level intent, or explicit overwrite confirmation.

### SM-05 — area, room, and asset editors can overwrite concurrent changes

- Classification/severity: Architecture risk/likely defect, Medium.
- Files/functions: `lib/src/core/data/asset_repository.dart`, `saveArea` near lines 189-229, `saveRoom` near lines 439-487, `saveAsset` near lines 685-789, and `moveAsset` through snapshot save.
- Pattern: full-snapshot updates have no expected revision. Remote merge logic cannot reconstruct intent after one editor overwrites fields locally.
- Fix: use typed patch commands with revision CAS for remotely synchronized aggregates.

### SM-06 — deleting a primary photo can leave no primary photo

- Classification/severity: Likely partial-commit defect, Medium.
- Files/functions: `lib/src/core/data/asset_repository.dart`, `deletePhoto` near lines 1156-1177 and `setPrimaryPhoto`.
- Pattern: the photo row is deleted, then remaining photos are selected and a separate transaction assigns a new primary. Failure between operations leaves remaining photos without a primary.
- Fix: select, delete, and promote in one database transaction; keep file deletion as a retryable side effect.

### SM-07 — snooze can leave partial platform state

- Classification/severity: Likely, Medium.
- Files/functions: `task_actions.dart`, `snoozeTaskWithFeedback` near lines 13-105; `notification_service.dart`, snooze path near lines 523-575.
- Pattern: platform scheduling, task-alarm cancellation, and snapshot replacement span fallible calls without a durable command. A mid-sequence exception can leave an unknown combination.
- Fix: persist a snooze intent and make the scheduler reconcile to a complete desired state idempotently.

### SM-08 — dead archive APIs are both obsolete and unsafe

- Classification/severity: Confirmed dead code; latent TOCTOU risk.
- Files/functions: archive area/room/asset methods in `lib/src/core/data/asset_repository.dart`, corresponding interfaces and tests.
- Evidence: no production call sites; trash/cascade flows supersede them. Area/room archive performs a check and later update outside one transaction.
- Fix: delete methods, interface surface, tests, and documentation instead of hardening an unused parallel lifecycle.

### Patterns reviewed that should be retained

- `undoCompletion` uses latest-record and expected-due checks and produces a compensating outbox mutation. Its command shape should migrate to occurrence ID rather than be deleted.
- Local trash cascades that already execute within one Drift transaction are the correct atomic pattern; only reminder/file/cloud effects need durable follow-up.
- Auth account binding, durable outbox storage, server operation IDs, advisory locks, strict response parsing, and conflict rollback are valuable integrity mechanisms.
- Media cleanup queues and charged-operation recovery journals represent real external/unknown-outcome boundaries. They should be simplified to one current schema, not removed.

## 6. Versioning inventory and classification

Classification:

- A — mandatory technical versioning or invalidation identity. Keep it.
- B — unnecessary internal compatibility/history in this zero-user pre-launch repository. Delete, squash, or rename it.
- C — externally required application, protocol, artifact, or independently deployed service versioning. Keep a strict current contract; do not keep an acceptance ladder.

| Mechanism | Representative files | Class | Decision and reason |
|---|---|---:|---|
| Drift `currentSchemaVersion = 1` and SQLite `user_version` | `lib/src/core/database/app_database.dart`; generated `app_database.g.dart` | A | Drift requires schema identity. Keep one clean version-1 baseline and no upgrade ladder before launch. Never edit generated output manually. |
| Backup container format, manifest `schemaVersion`, SQLite schema, `OWNTDBK1`, hash/algorithm identifiers | `lib/src/core/services/backup_service.dart`; `docs/architecture/backup-and-restore.md` | A | Backups are untrusted external files and may outlive an install. Keep exact fail-closed validation, format detection, hashes, size/path limits. |
| Restore journal `version` | `lib/src/core/services/restore_journal.dart` | A+B | Interrupted restore safety requires one discriminator (A). The `_v3` key and older/newer compatibility prose are prelaunch history (B). Reset to one current exact format and semantic key. |
| Native shell version and capability versions | `lib/src/core/services/native_capabilities.dart`; `android/app/src/main/kotlin/app/owntend/mobile/MainActivity.kt` | A/C | Shorebird Dart patches can run on older installed native shells. Keep explicit capability negotiation. A clean prelaunch base can reset the current minimum. |
| Native ad palette schema 1/2 | `lib/src/features/monetization/src/native_ad_card.dart`; `OwntendNativeAdFactory.kt` | B | Both sides ship together in the unpublished base. Delete schema 1 fallback and keep one current capability payload. |
| Completion request missing/1/2 acceptance and response `contract_version` | `supabase/migrations/20260828104729_version_maintenance_completion_contract.sql`; `supabase_sync_gateway.dart` | B+C | Mobile and Supabase are independently deployed, so one strict protocol identity is C. Accepting missing/1/2 and duplicating version fields is B. Keep one exact current contract or a versioned RPC endpoint. |
| Change-feed `contract_version = 1` | `lib/src/core/sync/change_feed_contract.dart`; server change-feed functions/tests | C | Independently deployed mobile/server protocol. Keep strict fail-closed identity. |
| Outbox revisions, operation IDs, generations, feed sequence, row revisions | Drift tables, sync stores, Supabase functions | A | These are concurrency/order/idempotency data, not legacy compatibility. Keep and strengthen ordering. |
| Reminder snapshot `contentVersion` | `app_database.dart`; `reminder_schedule_reconciler.dart` | A | It is an input fingerprint/cache invalidator, not schema history. Keep; rename to `desiredStateFingerprint` if that removes ambiguity. |
| Media download cache object version | `lib/src/core/sync/media_download_cache.dart` | A | Prevents serving stale content for a stable path. Keep. |
| App semantic version/build number and Android version code/name | `pubspec.yaml`; `android/app/build.gradle.kts` | C | Required by package distribution, updates, diagnostics, Sentry, Shorebird, and artifact verification. Keep. |
| VersionDeck manifest/control/cache/build-status schemas and service-worker revision | `download-site/*.js`; `tool/versiondeck-control.json`; generation/verification tools | A/C | These secure public artifacts and reject stale or inconsistent metadata. Keep even while releases are disabled. |
| APK signer/ancestry, Sentry, Shorebird, SBOM, provenance and SLSA/in-toto evidence schema versions | `tool/*release*`, `tool/*evidence*`, `config/asset_provenance.json` | A/C | External trust and reproducibility boundaries. Keep exact validation. |
| Dependency/toolchain versions | `pubspec.lock`, `package-lock.json`, Gradle, `config/toolchain.json`, workflows | A/C | Required for reproducibility and security policy. Keep pins and supported ranges. Do not enumerate copies in prose. |
| Third-party API paths and external schema versions | Supabase `/v1`, Open-Meteo `/v1`, Android `values-vXX`, XML, GitHub Actions versions, Dependabot v2 | C | Owned externally or selected by platform. Keep. |
| Supabase dated migration chain | `supabase/migrations/*.sql` | B until launch | Eleven files preserve unpublished intermediate states. Fold final definitions into one baseline after explicit authorization for the exact hosted development target, then delete patch files. |
| `legacy_unverified` entitlement/backfill branches | `20260826234340...sql`; `20260826234405...sql` | B | They protect nonexistent historical rows. Remove and make current authorization data mandatory. |
| Versioned secure/local keys | `task_creation_op_v1_`, `owntend_creation_draft_v1_`, `monetization_has_completed_session_v1`, `owntend_sidecar_registry_v1`, `owntend_active_restore_journal_v3`, `owntend.account-deletion-recovery.v1`, `owntend.backup-auto-key.v1` | B, except stored content discriminator where needed | Zero users means there is no installed legacy keyspace to migrate. Rename to semantic keys; validate values with one explicit schema where recovery safety requires it. |
| `permission_education_seen_v2` historical absence assertions | tests/docs/config searches | B | Historical residue for an unpublished preference. Remove version-history assertions; test current behavior. |
| Same-repository config `schemaVersion` fields | `config/toolchain.json`; `config/asset_provenance.json` | B/A | File validation is A; a compatibility ladder is B. If tools and config always ship together, validate current required fields directly or enforce one exact value without legacy branches. |
| `docs/architecture/v1-contracts.md` and pervasive “production-v1” labels | docs index, architecture/backend/product docs, test names | B | They make a prelaunch snapshot sound like a supported historical contract. Rename to current contracts and remove historical language while retaining actual external version facts. |
| Special Shorebird `1.0.0+4` generated-asset bypass and legacy base configuration | `tool/invoke_shorebird_patch.ps1`; `tool/configure_shorebird.ps1`; `tool/shorebird.test.mjs` | B | `download-site/releases.json` is disabled and contains no public release. Abandon the unpublished base, remove its exception, and cut one clean prelaunch base. |
| Changelog entries for unpublished internal iterations | `CHANGELOG.md` | B unless tied to an externally published artifact | Consolidate into `Unreleased` and current behavior. Do not preserve claims that tests do not prove. Retain any entry only if trusted artifact evidence demonstrates external publication. |

The current uncommitted completion migration accepts missing version, version 1, and version 2. That is precisely the compatibility layering prohibited by the lifecycle rule. It also does not solve CT-01 because version acceptance is orthogonal to server authority.

## 7. Versioning deletion plan

1. Establish the clean current contract before deleting history.
   - Define one occurrence-intent completion RPC and one strict response schema.
   - Keep one change-feed contract version because mobile and backend deployment can differ.
   - Keep backup and release-evidence versions because their artifacts cross process/release boundaries.

2. Squash Supabase to a single baseline.
   - Fold final schema, grants, RLS, RPCs, triggers, change feed, media policies, and authoritative mutations into `supabase/migrations/20260821124930_initial_schema.sql` or a newly named single baseline.
   - Delete these patch migrations after their final definitions and tests are folded:
     - `20260826010000_harden_security_definer_execute_privileges.sql`
     - `20260826030000_public_rpcs_security_invoker.sql`
     - `20260826050000_accept_admob_unit_id_event_property.sql`
     - `20260826234340_harden_completion_and_add_authoritative_mutation_rpcs.sql`
     - `20260826234348_harden_media_staging_and_storage_rls.sql`
     - `20260826234356_fix_operator_change_feed_parity_rpc.sql`
     - `20260826234405_enforce_authoritative_plan_and_history_mutations.sql`
     - `20260827224407_add_explicit_private_table_deny_policies.sql`
     - `20260828052419_restrict_sync_update_columns.sql`
     - `20260828104729_version_maintenance_completion_contract.sql`
   - Delete `legacy_unverified` backfill branches and their compatibility assertions.
   - This report does not authorize or execute a linked Supabase reset. Resetting any hosted target requires the user to name and explicitly authorize that exact destructive target.

3. Keep Drift at one baseline.
   - Modify the source tables directly while prelaunch and keep `currentSchemaVersion = 1`.
   - Regenerate `app_database.g.dart` with `dart run build_runner build`.
   - Delete tests/prose that describe upgrading nonexistent installed databases. Keep schema-export/backup validation of the current baseline.

4. Remove internal request-shape ladders.
   - Delete missing/1/2 completion request acceptance.
   - Delete native-ad schema 1 generation and parsing.
   - Prefer a new exact completion RPC name if an explicit protocol generation is useful; otherwise one strict request schema plus one response contract version is sufficient.

5. Reset internal key names without migration code.
   - Replace version-suffixed keys with semantic names in charged-operation, offline-draft, ad-presentation, sidecar, restore, account-deletion, and auto-backup stores.
   - Delete old-key lookup, copy-forward, fallback, and absence tests. Do not add dual-read or dual-write logic.
   - Keep a payload discriminator inside restore/account-deletion journals only where recovery safety needs fail-closed parsing.

6. Remove the unpublished Shorebird exception.
   - Delete the `1.0.0+4` branch and warning from `tool/invoke_shorebird_patch.ps1`.
   - Remove legacy-base assumptions from `tool/configure_shorebird.ps1`.
   - Update `tool/shorebird.test.mjs` to require the clean base with no asset-difference bypass.
   - Preserve signer, release, patch, and evidence verification.

7. Normalize documentation.
   - Rename `docs/architecture/v1-contracts.md` to `current-contracts.md` and update `docs/README.md`.
   - Replace “production-v1” historical framing in data model, sync, monetization, backup, product catalog, and backend docs with current contract statements.
   - Archive or explicitly label implementation plans/reports that are historical rather than current authority.
   - Consolidate unpublished changelog history and remove the current uncommitted claims of durable multi-isolate/process idempotency and reminder correctness until executable tests prove them.

## 8. Database simplification

### Clean local baseline

Modify `lib/src/core/database/app_database.dart` directly:

- Add `currentOccurrenceId` to `MaintenancePlans` as a non-null UUID.
- Add `occurrenceId` to `MaintenanceRecords` as non-null.
- Add a unique constraint on `(planId, occurrenceId)`.
- Treat completion and skip as occurrence-consuming mutations that generate the next occurrence ID.
- Treat postpone and schedule edits as modifications of the same current occurrence unless product policy explicitly says an edit creates a new one.
- Add a non-null monotonically ordered local sequence to outbox rows, or make a dedicated command table with deterministic order. Stop relying on nullable `createdAt` and whole-second timestamps.
- Replace completion-specific notification reconciliation reasons with a generalized schedule-input-change request that covers complete, undo, skip, postpone, edit, enable, disable, archive, trash, restore, settings, timezone, and permission changes.
- Make the desired reminder fingerprint describe all inputs needed to reconstruct platform state. A snapshot is not proof of an OS alarm; record the last reconciliation attempt/result separately if operational visibility is needed.
- Remove the repository’s process-memory duplicate maps and stopwatch.
- Delete the bool-only `completePlan` wrapper if production still has no call sites after the refactor.

The cleanest model is two explicit concepts:

```text
maintenance_plans
  id
  current_occurrence_id
  current_due_at
  recurrence_rule
  revision
  ...current plan fields

maintenance_records
  id
  plan_id
  occurrence_id
  completed_at_client
  accepted_at_server (remote; nullable locally while pending)
  notes
  ...immutable history fields
  UNIQUE(plan_id, occurrence_id)

maintenance_commands / outbox
  operation_id PRIMARY KEY
  account_id
  plan_id
  occurrence_id
  kind
  expected_plan_revision
  intent fields only
  local_sequence NOT NULL
  predecessor_operation_id nullable
  state / retry metadata
```

Do not retain both a generic full-row mutation and a specialized completion projection for the same server-authoritative transition. A typed command is smaller, auditable, and cannot silently smuggle unrelated stale fields.

### Clean remote baseline

In the single Supabase baseline:

- Add non-null current occurrence IDs to plans.
- Add non-null occurrence IDs to history and unique `(user_id, plan_id, occurrence_id)`.
- Keep unique operation IDs and advisory locking.
- Centralize recurrence calculation in a private SQL function or a narrowly scoped server function tested against the Dart rule corpus.
- Derive owner ID from `auth.uid()` and do not accept an ownership parameter.
- Revoke generic direct writes to server-authoritative plan/history columns.
- Return the complete canonical plan, record, occurrence ID, revision, and operation disposition.
- Bound or classify client clock skew. Preserve client action time for offline UX/audit but use server acceptance time for server policy such as rewards and abuse limits.
- Keep explicit RLS, `SECURITY DEFINER` authorization, safe `search_path`, and least-privilege execute grants.

### Reset and backup implications

- Local developer databases and fixtures should be recreated from the new Drift baseline; no migration code is needed while lifecycle remains prelaunch.
- Local Supabase and test databases should be reset from the single SQL baseline.
- Any linked development Supabase reset is destructive and remains outside this plan until explicitly authorized for the exact target.
- Backup export/import sources and documentation must be updated for occurrence IDs. Preserve format, hash, path traversal, size, rollback, and schema compatibility checks.

## 9. Sync simplification

### Command contract

The completion request should contain only:

- strict contract identity or a versioned endpoint name;
- `operation_id`;
- authenticated account context derived server-side;
- `plan_id`;
- `occurrence_id`;
- expected plan revision;
- client completion time and optional notes;
- predecessor operation ID only if the queue truly requires it.

Delete duplicated `idempotency_key`, top-level and nested plan IDs, client-projected full plan state, client-projected record ownership, and client-computed next due date.

### Local processing

1. The controller captures the displayed occurrence ID.
2. The repository transaction compares that ID with the plan’s current occurrence.
3. A unique record insert applies the optimistic local completion once.
4. The transaction advances local display state using the shared recurrence rule, writes the typed outbox command, and writes generalized reminder intent.
5. UI receives a typed result: `appliedPendingSync`, `alreadyAppliedByThisOperation`, `completedElsewhere`, `staleOccurrence`, `inactive`, or `failed`.
6. No sound, reward, or “success” result is derived from the presence of someone else’s record.

Local recurrence remains useful for immediate offline UI, but it is provisional. The cloud response is canonical.

### Remote processing

1. Authenticate and validate one exact schema.
2. Lock operation ID and plan/occurrence.
3. Return stored result for an exact replay of the same operation.
4. Lock the canonical plan.
5. Compare occurrence ID and expected revision.
6. If recurrence or other relevant fields changed but the occurrence remains current, compute from the locked canonical rule; do not ask the client to mutate and retry a stale projection.
7. Insert exactly one record and advance exactly one occurrence.
8. Return canonical record/plan and explicit disposition.

### Acknowledgement and conflict

- Exact operation replay: acknowledge with stored canonical state.
- Different operation for the same consumed occurrence: return `completed_elsewhere` and the winner state.
- Stale occurrence: return current canonical occurrence without pretending the command applied.
- Stale revision with same occurrence: either apply against locked canonical fields if the command’s intent is independent, or return a typed conflict requiring user review. Never rewrite only the revision in an old projection.
- Terminal failure: resolve dependents immediately—rebase if safe, otherwise roll back/fail them explicitly. Never leave a permanent blocking row.
- Order commands by non-null local sequence with a stable tie-breaker.

### Offline and UX policy

- Offline completion can remain optimistic and should say “completed on this device” where conflict is possible.
- Streak can be derived from local records and recomputed after reconciliation.
- Maintenance-qualified rewards should wait for server acceptance or use a single-use eligibility token returned by the canonical completion.
- A conflict that removes a local record must enqueue reminder reconciliation in the same local transaction that applies canonical state.
- Realtime remains invalidation only; it must not replace authoritative pull/RPC responses.

## 10. Dead-code deletion map

| Delete/simplify | Files/symbols | Evidence/replacement |
|---|---|---|
| Time-based completion dedupe | `_completionDuplicateWindow`, stopwatch, two per-plan maps in `maintenance_repository.dart` | Replaced by occurrence and operation uniqueness. |
| Bool completion wrapper | `MaintenanceRepository.completePlan` and implementations/tests, if final call-site search remains production-empty | Production uses typed result; current direct callers are tests. |
| Dead controller phase | `TaskCompletionPhase.reconcilingReminder` | Never assigned; reminder repair belongs to durable consumer state, not controller fiction. |
| Record lookup as idempotency | Current uncommitted `(planId, dueDate)` lookup in `completePlanResult` | Replaced by unique occurrence and operation IDs. |
| Parallel cancellation/refresh completion helpers | Independent `unawaited` calls in `completeTaskWithFeedback` | Replaced by one durable reconciliation wake. |
| Full plan projection in completion outbox | `plan`, `record`, duplicated IDs/version/idempotency fields in payload | Replaced by typed intent. |
| Stale-revision projection rewrite | `PushCoordinator` branch that only replaces expected revision | Server applies intent to locked canonical plan. |
| Missing/1/2 contract acceptance | Dirty completion SQL branches and tests | One exact contract. |
| Native ad schema 1 branch | Dart palette emission and Kotlin parser acceptance | One current shell capability payload. |
| Dead asset archive APIs | `archiveArea`, `archiveRoom`, `archiveAsset`, interface entries, tests, obsolete docs | Trash/cascade lifecycle is the production path. |
| Legacy entitlement compatibility | `legacy_unverified` types/backfills/tests | Current authorization state is mandatory in clean baseline. |
| Versioned internal key names and migrations | charged operation, draft, first-session, sidecar, restore, account deletion, auto-backup keys | Semantic keys plus exact current value schema where needed. |
| Shorebird `1.0.0+4` exception | branch/warning/tests in patch/configure tooling | Clean unpublished base; retain verification. |
| Ten Supabase patch migrations | Files listed in section 7 | Fold into one tested baseline. |
| “v1 contracts” historical document identity | `docs/architecture/v1-contracts.md` and index links | Rename to current contracts. |
| Tests that pin the four-second suppression | Assertions near `recurring_completion_precision_test.dart:200-270` | Replace with immediate-next-occurrence success and same-occurrence idempotency tests. |
| Source-text notification ordering test | Current uncommitted `notification_completion_ack_test.dart` scan | Replace with executable fake-scheduler interleaving tests. |
| Sequential same-database “restart” claim | Current uncommitted test near `recurring_completion_precision_test.dart:531-584` | Replace with close/reopen file-backed DB and independent connection/process tests. |
| Inaccurate changelog claims | Current uncommitted Complete Task bullet(s) | Restore only claims proven by executable tests and implementation. |

No dependency removal is justified by this audit alone. Dependency versions are reproducibility/security controls, and determining that a package is unused requires the repository’s dependency-policy tooling. The implementation phase should not add a new package for occurrence IDs, queue ordering, or recurrence; existing UUID, Drift, Riverpod, and Supabase capabilities are sufficient.

## 11. Full phased fix plan

### Phase 0 — protect evidence and define product semantics

- Do not merge the six existing uncommitted edits as a fix; CT-02 and CT-06 are introduced or exposed by them, and the changelog overstates their guarantees.
- Decide and document recurrence anchoring: due-date anchored, completion-time anchored, or catch-up policy for overdue/early work.
- Decide timezone and DST rules and which clock controls “today,” recurrence, streak, and reward eligibility.
- Decide offline copy: optimistic local success versus pending-cloud wording.

Documents to modify: `docs/product/feature-catalog.md`, `docs/architecture/data-model.md`, `docs/architecture/sync-protocol.md`, `docs/architecture/monetization.md`, and the renamed current-contracts document.

### Phase 1 — occurrence identity and clean Drift baseline

Modify:

- `lib/src/core/database/app_database.dart`
- `lib/src/core/domain/contracts.dart`
- `lib/src/core/data/maintenance_repository.dart`
- `lib/src/core/services/recurrence_engine.dart` if the product decision changes anchoring
- repository/provider fakes and fixtures

Delete:

- time-window dedupe state;
- bool-only completion API if still unused;
- old tests that assert time-based suppression.

Regenerate:

- `lib/src/core/database/app_database.g.dart` via `dart run build_runner build`.

Add tests:

- same operation replay is idempotent;
- different operations for one occurrence produce one record and an explicit loser;
- immediate completion of the newly generated occurrence succeeds;
- stale task/skip/postpone/undo commands cannot affect the next occurrence;
- transaction rollback leaves no record, plan change, outbox, inbox acknowledgement, or reconcile request;
- injected commit failure does not populate success memory;
- close and reopen a file-backed database before replay;
- two independent Drift connections contend on the same occurrence.

### Phase 2 — controller and presentation outcomes

Modify:

- `lib/src/features/maintenance/presentation/task_completion_controller.dart`
- `lib/src/features/maintenance/presentation/task_actions.dart`
- `lib/src/ui/components/task_status.dart`
- all six completion entry surfaces only as needed for typed outcomes
- English and Arabic ARB source files for any new pending/conflict/repaired wording

Delete:

- dead `reconcilingReminder` phase;
- generic conversion of every exception into `occurrenceChanged`;
- feedback on `completedElsewhere`/duplicate paths;
- stale pre-dialog reward qualification.

Add widget/controller tests:

- unmount during task fetch and notes dialog always releases collection lock;
- fetch exception releases lock and exposes error;
- notes modal versus no-notes surface race;
- two screens submit one occurrence;
- recurring success animation remains a success until new watched state renders;
- Arabic/RTL and text-scaling coverage for new outcome messages.

### Phase 3 — server-authoritative completion and sync

Modify the final baseline definitions and client adapters:

- single Supabase baseline migration;
- `lib/src/core/sync/supabase_sync_gateway.dart`
- `lib/src/core/sync/coordinator/push_coordinator.dart`
- `lib/src/core/sync/local_store/outbox_store.dart`
- `lib/src/core/sync/local_store/mutation_store.dart`
- `lib/src/core/sync/change_feed_contract.dart` only if the response contract changes

Delete:

- client full-plan projection;
- duplicated idempotency/version fields;
- stale-revision revision-only retry;
- missing/1/2 acceptance ladder;
- terminal dependency state that blocks forever.

Add Dart tests:

- recurrence changes between offline completion and push;
- title-only changes, recurrence changes, disable/archive, and already-consumed occurrence each yield the intended disposition;
- lost response and exact replay return the stored result;
- terminal predecessor resolves every dependent;
- deterministic ordering for timestamp ties.

Add pgTAP/integration tests:

- malicious arbitrary next due is impossible because no such request field exists;
- owner, anonymous, cross-user, invalid occurrence, invalid clock, and invalid notes inputs;
- two truly concurrent database sessions completing one occurrence;
- concurrent recurrence edit and completion under both lock orders;
- RPC response loss simulation followed by exact operation replay;
- RLS, execute grants, `search_path`, direct-write denial, and change-feed parity.

### Phase 4 — reminder reconciliation as one durable subsystem

Modify:

- `lib/src/core/services/notification_service.dart`
- `lib/src/core/services/reminder_schedule_reconciler.dart`
- every repository transaction that changes schedule inputs
- startup, settings, timezone, permission, and background-worker wake paths

Delete:

- direct parallel cancel/refresh from completion;
- swallowed `void` helpers presented as successful repair;
- completion-only reconciliation reason assumptions.

Add tests with a step-controlled fake scheduler:

- refresh-before-cancel and cancel-before-refresh;
- process death after each platform call;
- schedule succeeds/snapshot fails and snapshot succeeds/cancel later runs;
- exact-alarm permission denial, notifications disabled, boot restore, timezone change, app update, stale snapshot, and stable-ID reuse;
- consumer retains request on every failure and acknowledges only verified convergence;
- physical Android validation for exact alarms, reboot, and OS notification state. This cannot be proven by unit tests.

### Phase 5 — reward, streak, and user feedback

Modify:

- reward-claim server function in the clean baseline;
- wallet/reward presentation;
- `streak_service.dart` integration and wording;
- completion response if it issues eligibility.

Add tests:

- no reward without a canonical eligible completion;
- exact eligible completion token is single-use and account-bound;
- losing device/conflict cannot claim;
- midnight/timezone behavior;
- ad SSV replay/cooldown remains enforced;
- streak recomputes after conflict rollback and restart.

### Phase 6 — adjacent mutations and dead APIs

Modify skip, postpone, edit, enable/disable, trash, restore, and photo deletion to use occurrence/revision CAS and durable side-effect intent. Delete unused area/room/asset archive APIs and tests. Add stale-dialog, concurrent-editor, partial-photo-failure, and schedule-repair tests.

### Phase 7 — prelaunch version and migration cleanup

- Execute section 7 after the new contract is passing locally.
- Reset local Supabase test data.
- Ask for explicit authorization before any named linked development reset.
- Cut a clean Shorebird base only through the protected documented workflow; do not publish from this audit task.
- Update `CHANGELOG.md` with the eventual user-visible architecture change only after it exists.

### Phase 8 — documentation and validation

Documents reviewed for this audit:

- `AGENTS.md`
- `docs/governance/documentation-maintenance.md`
- `docs/README.md`
- `docs/architecture/system-overview.md`
- `docs/architecture/data-model.md`
- `docs/architecture/sync-protocol.md`
- `docs/architecture/monetization.md`
- `docs/architecture/backup-and-restore.md`
- `docs/architecture/v1-contracts.md`
- `docs/backend/supabase.md`
- `docs/backend/migrations-and-functions.md`
- `docs/product/feature-catalog.md`
- `docs/reference/routes-and-permissions.md`
- `docs/versiondeck-release-runbook.md`
- `docs/operations/google-play-release-runbook.md`
- `docs/operations/shorebird-code-push.md`
- `docs/pre-launch-hardening-implementation-plan.md`
- `docs/pre-launch-hardening-implementation-report.md`
- `PRIVACY.md`
- `CHANGELOG.md`

Documents changed by this audit: this report and the `docs/README.md` index entry for it. Current behavior documentation was deliberately not rewritten because the task requested diagnosis and a plan, not implementation; section 11 identifies the exact documents that must change with the fix. Existing overclaims in the dirty changelog are findings, not silently corrected evidence.

Focused validation executed during the audit:

```powershell
flutter test --no-pub --concurrency=1 --timeout 3m `
  test/recurring_completion_precision_test.dart `
  test/notification_completion_ack_test.dart `
  test/reminder_schedule_reconciler_test.dart `
  test/widgets/tasks_editors_test.dart

flutter test --no-pub --concurrency=1 --timeout 3m `
  test/sync_coordinator_test.dart `
  --plain-name "offline maintenance completion syncs when connectivity returns"

flutter test --no-pub --concurrency=1 --timeout 3m `
  test/sync_coordinator_test.dart `
  --plain-name "two devices completing one occurrence converge on the first canonical completion"
```

Results: all 33 tests in the first focused run passed; both named sync tests passed. These results prove that the current implementation matches its focused test expectations. They do not prove true process restart, concurrent SQLite connections, concurrent Supabase sessions, Android alarm state, hosted RLS configuration, protected release behavior, or physical-device behavior.

Required implementation validation, in order:

```powershell
flutter pub get
flutter gen-l10n
dart run build_runner build
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --timeout 3m --exclude-tags production-config
npm ci
npm run supabase:lint
npm run supabase:test
npm run validate:test-inventory
npm run test:all
npm run validate:toolchain
npm run validate:dependency-policy
npm run validate:google-contracts
```

Also run the documented production-example config test. Do not claim real signed release, hosted Supabase reset, public VersionDeck publication, Shorebird patch, Sentry release mutation, real Google SSV, boot restoration, or physical notification validation from local results. Those require their protected environment, hosted service, or physical device and explicit authorization where state changes.

## 12. Final target architecture

```text
UI surface
  captures {planId, occurrenceId}
        |
        v
TaskCompletionController (auto-disposed, typed phases/outcomes)
        |
        v
MaintenanceCommandRepository
  ONE Drift transaction
    - CAS current occurrenceId
    - unique record(planId, occurrenceId)
    - optimistic next occurrence
    - typed outbox intent(operationId, occurrenceId, localSequence)
    - generalized reminder-reconcile intent
    - inbox acknowledgement
        |
        +-----------------------> watched Drift state -> UI/pending badge
        |
        +-----------------------> serialized Reminder Reconciler
        |                            desired state from DB
        |                            -> cancel obsolete OS alarms
        |                            -> schedule desired OS alarms
        |                            -> persist verified snapshot
        |                            -> acknowledge durable request
        |
        v
SyncCoordinator / ordered outbox
        |
        v
Supabase complete-occurrence RPC
  - auth.uid ownership
  - exact contract
  - operation + plan advisory locks
  - lock canonical plan
  - compare occurrenceId/revision
  - compute recurrence server-side
  - unique canonical record
  - advance canonical occurrence
  - record operation result
        |
        v
Canonical typed response
  applied | replayed | completed_elsewhere | stale | rejected
        |
        v
ONE local reconciliation transaction
  - apply canonical plan/record
  - acknowledge or resolve command/dependents
  - enqueue reminder repair when state changed
  - recompute derived streak
        |
        +-----------------------> reward eligibility token, only after canonical acceptance
```

Properties of the target:

- Occurrence identity, not elapsed time or due-date coincidence, defines idempotency.
- The client expresses intent; the server owns canonical recurrence and authorization.
- A local completion is one durable transaction and a remote completion is one idempotent canonical transaction.
- Every side effect that must survive process death has durable intent.
- Only one component mutates platform reminder state and its snapshot.
- UI outcomes distinguish local pending success, exact replay, another actor’s success, stale input, and failure.
- Rewards bind to canonical eligibility; streak remains derived and repairable.
- Queue dependencies always reach an explicit terminal resolution.
- The prelaunch repository contains one Drift baseline, one Supabase baseline, one current internal schema per component, and no legacy fallbacks for nonexistent users.
- Technical/external versions remain strict wherever artifacts, independently deployed components, platform capabilities, caches, or security evidence cross a boundary.

This architecture removes the current need for the four-second guard, record-presence dedupe, stale full-plan retries, parallel notification calls, compatibility acceptance ladders, and misleading success handling while preserving the repository’s strongest existing properties: offline durability, account isolation, server authentication, operation idempotency, explicit conflict reconciliation, RLS, backup safety, and release provenance.
