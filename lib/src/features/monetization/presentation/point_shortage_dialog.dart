part of '../../../../main.dart';

class _PointShortageDialog extends ConsumerStatefulWidget {
  const _PointShortageDialog();

  @override
  ConsumerState<_PointShortageDialog> createState() =>
      _PointShortageDialogState();
}

class _PointShortageDialogState extends ConsumerState<_PointShortageDialog> {
  bool _loading = false;
  bool _verificationPending = false;
  String? _status;
  bool _statusIsError = false;

  Future<void> _tryReward() async {
    if (_loading || _verificationPending) return;
    final config =
        ref.read(monetizationConfigProvider).value ??
        const MonetizationConfig.failClosed();
    if (!config.adsEnabled || !config.rewardedAdsEnabled) {
      setState(() {
        _status = context.l10n.pointRewardsUnavailable;
        _statusIsError = true;
      });
      return;
    }

    final wallet = ref.read(pointWalletProvider).value;
    setState(() {
      _loading = true;
      _status = context.l10n.loadingRewardedAd;
      _statusIsError = false;
    });
    final result = await ref
        .read(owntendAdsProvider)
        .showReward(
          RewardAdType.rewardedAd,
          timeZone: wallet?.timeZone,
          entryPoint: 'shortage',
        );
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case RewardShowResult.shownAwaitingServerVerification:
          _verificationPending = true;
          _status = context.l10n.rewardVerificationPending;
          _statusIsError = false;
        case RewardShowResult.unavailable:
          _status = context.l10n.noRewardedAdAvailable;
          _statusIsError = true;
        case RewardShowResult.rejected:
          _status = context.l10n.rewardUnavailableOrClaimed;
          _statusIsError = true;
        case RewardShowResult.dismissed:
          _status = context.l10n.rewardAdClosedEarly;
          _statusIsError = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final balance = ref.watch(pointWalletProvider).value?.balance ?? 0;
    return AlertDialog(
      actionsOverflowButtonSpacing: HkSpacing.xs,
      icon: Icon(Symbols.stars_rounded, color: scheme.primary, size: 32),
      title: Text(context.l10n.needOnePoint),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HkSpacing.sm,
                    vertical: HkSpacing.space6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(HkRadii.full),
                  ),
                  child: Text(
                    context.l10n.pointsCount(balance),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: HkSpacing.sm),
              Text(context.l10n.pointShortageDescription),
              if (_status case final status?) ...[
                const SizedBox(height: HkSpacing.sm),
                Semantics(
                  liveRegion: true,
                  child: Container(
                    key: const ValueKey('point-shortage-status'),
                    padding: const EdgeInsets.all(HkSpacing.xs),
                    decoration: BoxDecoration(
                      color: (_statusIsError ? scheme.error : scheme.primary)
                          .withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(HkRadii.md),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_loading)
                          const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            _statusIsError
                                ? Symbols.info_rounded
                                : Symbols.verified_rounded,
                            size: 20,
                            color: _statusIsError
                                ? scheme.error
                                : scheme.primary,
                          ),
                        const SizedBox(width: HkSpacing.xs),
                        Expanded(child: Text(status)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text(context.l10n.keepEditing),
        ),
        FilledButton.icon(
          key: const ValueKey('point-shortage-watch-ad'),
          onPressed: _loading || _verificationPending ? null : _tryReward,
          icon: const Icon(Symbols.play_circle_rounded),
          label: Text(context.l10n.earnAPoint),
        ),
      ],
    );
  }
}

bool _isInsufficientPointsError(Object error) {
  if (error is InsufficientPointsException) return true;
  if (error case PostgrestException(:final message)) {
    return message == 'INSUFFICIENT_POINTS';
  }
  return error.toString().contains('INSUFFICIENT_POINTS');
}

Future<bool> confirmPermanentDelete(
  BuildContext context, {
  required String title,
  required String message,
  String? actionLabel,
}) async {
  final confirmed = await runWithNativeAdsSuspended(
    context,
    () => showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        actionsOverflowButtonSpacing: HkSpacing.xs,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Symbols.delete_rounded),
            label: Text(actionLabel ?? context.l10n.delete),
          ),
        ],
      ),
    ),
  );
  return confirmed == true;
}

Future<bool> deleteTaskWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  final confirmed = await confirmPermanentDelete(
    context,
    title: context.l10n.moveTaskToTrash2,
    message: context.l10n.moveTaskToTrashMessage(task.plan.title),
    actionLabel: context.l10n.moveToTrash,
  );
  if (!confirmed || !context.mounted) {
    return false;
  }
  return moveTaskToTrashWithUndo(context, ref, task);
}

Future<bool> moveTaskToTrashWithUndo(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  try {
    await ref.read(maintenanceRepositoryProvider).archivePlan(task.plan.id);
  } on Object catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          _failureMessage(context, error, fallback: AppFailureCode.taskUpdate),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
    return false;
  }
  try {
    await cancelPlanReminderSchedules(ref, [task.plan.id]);
    await refreshNotificationSchedules(ref);
  } on Object catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          _failureMessage(
            context,
            error,
            fallback: AppFailureCode.notificationSetup,
          ),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
  }
  if (!context.mounted) {
    return true;
  }
  hk_ui.showTaskMovedToTrashSnackBar(
    context,
    duration: const Duration(seconds: 5),
    onUndo: () async {
      try {
        await ref.read(maintenanceRepositoryProvider).restorePlan(task.plan.id);
        await refreshNotificationSchedules(ref);
        if (context.mounted) {
          hk_ui.showToast(context, content: Text(context.l10n.taskRestored));
        }
      } on Object catch (error) {
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(
              _failureMessage(context, error, fallback: AppFailureCode.undo),
            ),
            severity: hk_ui.HkToastSeverity.error,
          );
        }
      }
    },
  );
  return true;
}

Future<bool> deleteThingWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  Asset asset,
) async {
  final confirmed = await confirmPermanentDelete(
    context,
    title: context.l10n.moveItemToTrash2,
    message: context.l10n.moveItemToTrashMessage(asset.name),
    actionLabel: context.l10n.moveToTrash,
  );
  if (!confirmed || !context.mounted) {
    return false;
  }
  final planIds = await _planIdsForAssets(ref, [asset.id]);
  if (!context.mounted) {
    return false;
  }
  await ref.read(assetRepositoryProvider).trashAsset(asset.id);
  if (!context.mounted) {
    return false;
  }
  await cancelPlanReminderSchedules(ref, planIds);
  await refreshNotificationSchedules(ref);
  if (!context.mounted) {
    return false;
  }
  unawaited(hkActionFeedbackService.playDeleted());
  hk_ui.showMovedToTrashSnackBar(
    context,
    content: Text(context.l10n.nameMovedToTrash(asset.name)),
    onUndo: () async {
      try {
        await ref.read(assetRepositoryProvider).restoreAsset(asset.id);
        await refreshNotificationSchedules(ref);
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(context.l10n.nameRestored(asset.name)),
          );
        }
      } on Object catch (error) {
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(
              _failureMessage(context, error, fallback: AppFailureCode.undo),
            ),
            severity: hk_ui.HkToastSeverity.error,
          );
        }
      }
    },
  );
  return true;
}

Future<bool> deleteRoomWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  Room room,
) async {
  final confirmed = await confirmPermanentDelete(
    context,
    title: context.l10n.moveRoomToTrash2,
    message: context.l10n.moveRoomToTrashMessage(room.name),
    actionLabel: context.l10n.moveToTrash,
  );
  if (!confirmed || !context.mounted) {
    return false;
  }
  final assets = await ref
      .read(assetRepositoryProvider)
      .listAssets(roomId: room.id);
  final planIds = await _planIdsForAssets(ref, assets.map((asset) => asset.id));
  if (!context.mounted) {
    return false;
  }
  await ref.read(assetRepositoryProvider).trashRoom(room.id);
  if (!context.mounted) {
    return false;
  }
  await cancelPlanReminderSchedules(ref, planIds);
  await refreshNotificationSchedules(ref);
  if (!context.mounted) {
    return false;
  }
  unawaited(hkActionFeedbackService.playDeleted());
  hk_ui.showMovedToTrashSnackBar(
    context,
    content: Text(context.l10n.nameMovedToTrash(room.name)),
    onUndo: () async {
      try {
        await ref.read(assetRepositoryProvider).restoreRoom(room.id);
        await refreshNotificationSchedules(ref);
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(context.l10n.nameRestored(room.name)),
          );
        }
      } on Object catch (error) {
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(
              _failureMessage(context, error, fallback: AppFailureCode.undo),
            ),
            severity: hk_ui.HkToastSeverity.error,
          );
        }
      }
    },
  );
  return true;
}

Future<bool> deleteAreaWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  Area area,
) async {
  final confirmed = await confirmPermanentDelete(
    context,
    title: context.l10n.moveAreaToTrash2,
    message: context.l10n.moveAreaToTrashMessage(area.name),
    actionLabel: context.l10n.moveToTrash,
  );
  if (!confirmed || !context.mounted) {
    return false;
  }
  final rooms = await ref
      .read(assetRepositoryProvider)
      .listRooms(areaId: area.id);
  final assetIds = <String>[];
  for (final room in rooms) {
    final assets = await ref
        .read(assetRepositoryProvider)
        .listAssets(roomId: room.id);
    assetIds.addAll(assets.map((asset) => asset.id));
  }
  final planIds = await _planIdsForAssets(ref, assetIds);
  if (!context.mounted) {
    return false;
  }
  await ref.read(assetRepositoryProvider).trashArea(area.id);
  if (!context.mounted) {
    return false;
  }
  await cancelPlanReminderSchedules(ref, planIds);
  await refreshNotificationSchedules(ref);
  if (!context.mounted) {
    return false;
  }
  unawaited(hkActionFeedbackService.playDeleted());
  hk_ui.showMovedToTrashSnackBar(
    context,
    content: Text(context.l10n.nameMovedToTrash(area.name)),
    onUndo: () async {
      try {
        await ref.read(assetRepositoryProvider).restoreArea(area.id);
        await refreshNotificationSchedules(ref);
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(context.l10n.nameRestored(area.name)),
          );
        }
      } on Object catch (error) {
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(
              _failureMessage(context, error, fallback: AppFailureCode.undo),
            ),
            severity: hk_ui.HkToastSeverity.error,
          );
        }
      }
    },
  );
  return true;
}
