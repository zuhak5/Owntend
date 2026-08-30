import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/l10n/app_localizations_ext.dart';

import '../../../core/sync/sync_contracts.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/utils/redacting_logger.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/components.dart' as hk_ui;

class SyncHealthSnapshot {
  const SyncHealthSnapshot({
    required this.failedMutations,
    required this.conflicts,
    this.accountId,
    this.deviceId,
  });

  final List<FailedSyncMutationSummary> failedMutations;
  final List<SyncConflictSummary> conflicts;
  final String? accountId;
  final String? deviceId;

  bool get needsAttention => failedMutations.isNotEmpty || conflicts.isNotEmpty;
}

final syncHealthSnapshotProvider =
    FutureProvider.autoDispose<SyncHealthSnapshot>((ref) async {
      final store = ref.watch(localSyncStoreProvider);
      if (store == null) {
        return const SyncHealthSnapshot(failedMutations: [], conflicts: []);
      }

      final account = await store.existingAccount();
      final failures = await store.listFailedVisibleMutations();
      final accountId = account?.boundUserId;
      final conflicts = accountId == null
          ? const <SyncConflictSummary>[]
          : await store.listUnresolvedSyncConflictSummaries(
              accountId: accountId,
            );
      return SyncHealthSnapshot(
        failedMutations: failures,
        conflicts: conflicts,
        accountId: accountId,
        deviceId: account?.deviceId,
      );
    });

class SyncHealthScreen extends ConsumerStatefulWidget {
  const SyncHealthScreen({super.key});

  @override
  ConsumerState<SyncHealthScreen> createState() => _SyncHealthScreenState();
}

class _SyncHealthScreenState extends ConsumerState<SyncHealthScreen> {
  bool _busy = false;

  Future<void> _refresh() async {
    ref.invalidate(syncHealthSnapshotProvider);
    await ref.read(syncHealthSnapshotProvider.future);
  }

  Future<void> _retryMutation(FailedSyncMutationSummary mutation) async {
    final store = ref.read(localSyncStoreProvider);
    if (store == null) return;
    await _runAction(() async {
      await store.resolveFailedMutation(
        entity: mutation.entity,
        recordKey: mutation.recordKey,
        action: 'retry',
      );
      await _requestSync();
    }, success: context.l10n.syncChangeQueuedForRetry);
  }

  Future<void> _dismissMutation(FailedSyncMutationSummary mutation) async {
    final confirmed = await _confirm(
      title: context.l10n.dismissSyncChange,
      body: context.l10n.dismissSyncChangeBody,
      action: context.l10n.dismiss,
    );
    if (!confirmed || !mounted) return;
    final store = ref.read(localSyncStoreProvider);
    if (store == null) return;
    await _runAction(() {
      return store.resolveFailedMutation(
        entity: mutation.entity,
        recordKey: mutation.recordKey,
        action: 'dismiss',
      );
    }, success: context.l10n.syncChangeDismissed);
  }

  Future<void> _resolveConflict(
    SyncHealthSnapshot snapshot,
    SyncConflictSummary conflict, {
    required bool keepLocal,
  }) async {
    final accountId = snapshot.accountId;
    final deviceId = snapshot.deviceId;
    if (accountId == null || deviceId == null) return;
    final confirmed = await _confirm(
      title: keepLocal
          ? context.l10n.keepThisDeviceVersion
          : context.l10n.keepCloudVersion,
      body: keepLocal
          ? context.l10n.keepThisDeviceVersionBody
          : context.l10n.keepCloudVersionBody,
      action: keepLocal ? context.l10n.keepThisDevice : context.l10n.keepCloud,
    );
    if (!confirmed || !mounted) return;
    final store = ref.read(localSyncStoreProvider);
    if (store == null) return;
    await _runAction(() async {
      final resolved = await store.resolveSyncConflict(
        entity: conflict.entity,
        recordKey: conflict.recordKey,
        accountId: accountId,
        deviceId: deviceId,
        keepLocal: keepLocal,
      );
      if (!resolved) {
        throw StateError('Sync conflict no longer belongs to this account.');
      }
      if (keepLocal) await _requestSync();
    }, success: context.l10n.syncConflictResolved);
  }

  Future<void> _requestSync() async {
    try {
      await ref.read(cloudSyncRepositoryProvider).syncNow();
    } on Object catch (error, stackTrace) {
      // The local intent is already pending and the coordinator will retry it.
      // A currently unavailable transport must not turn that durable action
      // into a false failure in the UI.
      AppLogger.warning(
        'sync_health_immediate_retry_deferred',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    required String success,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _refresh();
      if (mounted) hk_ui.showToast(context, content: Text(success));
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'sync_health_action_failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        hk_ui.showToast(
          context,
          content: Text(context.l10n.syncHealthActionFailed),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(syncHealthSnapshotProvider);
    final status = ref.watch(syncStatusProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.syncHealth),
        actions: [
          IconButton(
            onPressed: _busy ? null : () => unawaited(_refresh()),
            tooltip: context.l10n.refresh,
            icon: const Icon(Symbols.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            HkSpacing.gutter,
            HkSpacing.sm,
            HkSpacing.gutter,
            HkSpacing.bottomAction,
          ),
          children: [
            _SyncStatusCard(status: status, busy: _busy),
            const SizedBox(height: HkSpacing.sm),
            snapshot.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(HkSpacing.xl),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (_, _) => _SyncHealthMessageCard(
                icon: Symbols.error_rounded,
                title: context.l10n.syncHealthUnavailable,
                body: context.l10n.syncHealthUnavailableBody,
                action: OutlinedButton.icon(
                  onPressed: _busy ? null : () => unawaited(_refresh()),
                  icon: const Icon(Symbols.refresh_rounded),
                  label: Text(context.l10n.retry),
                ),
              ),
              data: (data) {
                if (!data.needsAttention) {
                  return _SyncHealthMessageCard(
                    key: const ValueKey('sync-health-empty'),
                    icon: Symbols.check_circle_rounded,
                    title: context.l10n.syncHealthLooksGood,
                    body: context.l10n.syncHealthLooksGoodBody,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (data.failedMutations.isNotEmpty) ...[
                      _SectionHeading(
                        title: context.l10n.changesNeedingAttention,
                        body: context.l10n.changesNeedingAttentionBody,
                      ),
                      for (final mutation in data.failedMutations)
                        _FailedMutationCard(
                          mutation: mutation,
                          busy: _busy,
                          onRetry: () => _retryMutation(mutation),
                          onDismiss: () => _dismissMutation(mutation),
                        ),
                    ],
                    if (data.conflicts.isNotEmpty) ...[
                      _SectionHeading(
                        title: context.l10n.syncConflicts,
                        body: context.l10n.syncConflictsBody,
                      ),
                      for (final conflict in data.conflicts)
                        _SyncConflictCard(
                          conflict: conflict,
                          busy: _busy,
                          onKeepLocal: () =>
                              _resolveConflict(data, conflict, keepLocal: true),
                          onKeepCloud: () => _resolveConflict(
                            data,
                            conflict,
                            keepLocal: false,
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({required this.status, required this.busy});

  final SyncStatus? status;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phase = status?.phase;
    final needsAttention =
        phase == SyncPhase.blocked || phase == SyncPhase.error;
    return hk_ui.PremiumCard(
      padding: const EdgeInsets.all(HkSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            needsAttention
                ? Symbols.cloud_alert_rounded
                : Symbols.cloud_done_rounded,
            color: needsAttention ? scheme.error : scheme.primary,
          ),
          const SizedBox(width: HkSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _syncStatusTitle(context.l10n, status),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: HkSpacing.space4),
                Text(
                  context.l10n.pendingSyncChanges(status?.pendingChanges ?? 0),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (busy) ...[
                  const SizedBox(height: HkSpacing.sm),
                  const LinearProgressIndicator(
                    key: ValueKey('sync-health-action-progress'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, HkSpacing.sm, 4, HkSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: HkSpacing.space4),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _FailedMutationCard extends StatelessWidget {
  const _FailedMutationCard({
    required this.mutation,
    required this.busy,
    required this.onRetry,
    required this.onDismiss,
  });

  final FailedSyncMutationSummary mutation;
  final bool busy;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HkSpacing.sm),
      child: hk_ui.SurfaceCard(
        padding: const EdgeInsets.all(HkSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _syncChangeTitle(context.l10n, mutation),
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: HkSpacing.space4),
            Text(
              context.l10n.syncStoppedAfterRepeatedAttempts,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: HkSpacing.sm),
            Wrap(
              spacing: HkSpacing.xs,
              runSpacing: HkSpacing.xs,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : onRetry,
                  icon: const Icon(Symbols.refresh_rounded),
                  label: Text(context.l10n.retry),
                ),
                TextButton(
                  onPressed: busy ? null : onDismiss,
                  child: Text(context.l10n.dismiss),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncConflictCard extends StatelessWidget {
  const _SyncConflictCard({
    required this.conflict,
    required this.busy,
    required this.onKeepLocal,
    required this.onKeepCloud,
  });

  final SyncConflictSummary conflict;
  final bool busy;
  final VoidCallback onKeepLocal;
  final VoidCallback onKeepCloud;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HkSpacing.sm),
      child: hk_ui.SurfaceCard(
        padding: const EdgeInsets.all(HkSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.syncConflictForCategory(
                _syncCategory(context.l10n, conflict.entity),
              ),
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: HkSpacing.space4),
            Text(
              context.l10n.chooseWhichVersionToKeep,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: HkSpacing.sm),
            Wrap(
              spacing: HkSpacing.xs,
              runSpacing: HkSpacing.xs,
              children: [
                FilledButton(
                  onPressed: busy ? null : onKeepLocal,
                  child: Text(context.l10n.keepThisDevice),
                ),
                OutlinedButton(
                  onPressed: busy ? null : onKeepCloud,
                  child: Text(context.l10n.keepCloud),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncHealthMessageCard extends StatelessWidget {
  const _SyncHealthMessageCard({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return hk_ui.SurfaceCard(
      padding: const EdgeInsets.all(HkSpacing.lg),
      child: Column(
        children: [
          Icon(icon, size: 42),
          const SizedBox(height: HkSpacing.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: HkSpacing.xs),
          Text(body, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: HkSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}

String _syncStatusTitle(AppLocalizations l10n, SyncStatus? status) {
  return switch (status?.phase) {
    SyncPhase.offline => l10n.waitingForInternet,
    SyncPhase.syncing || SyncPhase.initializing => l10n.backingUpChanges,
    SyncPhase.blocked || SyncPhase.error => l10n.needsAttention,
    SyncPhase.disabled ||
    SyncPhase.signedOut => l10n.savedOnThisDeviceCloudBackupIsPaused,
    _ => l10n.allInSync,
  };
}

String _syncChangeTitle(
  AppLocalizations l10n,
  FailedSyncMutationSummary mutation,
) {
  final category = _syncCategory(l10n, mutation.entity);
  return mutation.operation == 'delete'
      ? l10n.removedCategoryCouldNotSync(category)
      : l10n.updatedCategoryCouldNotSync(category);
}

String _syncCategory(AppLocalizations l10n, String entity) {
  return switch (entity) {
    'area' || 'room' => l10n.syncCategoryHomeStructure,
    'asset' ||
    'device_detail' ||
    'pet_detail' ||
    'plant_detail' ||
    'safety_detail' ||
    'tag' ||
    'asset_tag' => l10n.syncCategoryItem,
    'asset_photo' => l10n.syncCategoryPhoto,
    'maintenance_plan' ||
    'maintenance_plan_metadata' ||
    'maintenance_record' => l10n.syncCategoryTask,
    'profile' || 'user_setting' || 'streak' => l10n.syncCategoryPreference,
    'notification_inbox' => l10n.syncCategoryNotification,
    _ => l10n.syncCategoryOther,
  };
}
