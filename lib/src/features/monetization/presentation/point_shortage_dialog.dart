part of 'monetization_presentation.dart';

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
