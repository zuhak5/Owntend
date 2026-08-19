part of '../../../../main.dart';

String dailyCompletionRewardResultMessage(
  BuildContext context,
  RewardShowResult result,
) {
  return switch (result) {
    RewardShowResult.shownAwaitingServerVerification =>
      context.l10n.rewardWatchedVerifyingTwo,
    RewardShowResult.unavailable => context.l10n.noRewardAvailable,
    RewardShowResult.rejected => context.l10n.dailyRewardAlreadyClaimed,
    RewardShowResult.dismissed => context.l10n.rewardAdClosedEarly,
  };
}

Future<bool?> showDailyCompletionRewardSheet(BuildContext context) {
  final reducedMotion = _prefersReducedMotion(context);
  return runWithNativeAdsSuspended(
    context,
    () => showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: false,
      showDragHandle: true,
      isScrollControlled: true,
      sheetAnimationStyle: reducedMotion ? AnimationStyle.noAnimation : null,
      builder: (context) => const DailyCompletionRewardSheet(),
    ),
  );
}

class DailyCompletionRewardSheet extends StatelessWidget {
  const DailyCompletionRewardSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableHeight = math.max(
      0.0,
      media.size.height -
          media.viewInsets.bottom -
          media.padding.top -
          HkSpacing.sm,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: HkSpacing.xs),
        child: Align(
          alignment: AlignmentDirectional.bottomCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            key: const ValueKey('daily-completion-reward-sheet'),
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: availableHeight,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                HkSpacing.gutter,
                0,
                HkSpacing.gutter,
                HkSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Symbols.celebration_rounded,
                    size: 36,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: HkSpacing.xs),
                  Semantics(
                    header: true,
                    child: Text(
                      context.l10n.todayCareComplete,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: HkSpacing.space4),
                  Text(
                    context.l10n.optionalDailyRewardDescription,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: HkSpacing.sm),
                  const _DailyCompletionRewardActions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyCompletionRewardActions extends StatelessWidget {
  const _DailyCompletionRewardActions();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledLabelHeight = MediaQuery.textScalerOf(context).scale(14);
        final stack = constraints.maxWidth < 340 || scaledLabelHeight > 18;
        final notNow = OutlinedButton(
          key: const ValueKey('daily-completion-not-now'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.notNow, textAlign: TextAlign.center),
        );
        final reward = FilledButton.icon(
          key: const ValueKey('daily-completion-reward'),
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Symbols.play_circle_rounded),
          label: Text(context.l10n.earnTwoPoints, textAlign: TextAlign.center),
        );

        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              reward,
              const SizedBox(height: HkSpacing.xs),
              notNow,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: notNow),
            const SizedBox(width: HkSpacing.sm),
            Expanded(child: reward),
          ],
        );
      },
    );
  }
}
