import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:owntend/l10n/app_localizations_ext.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/components.dart' as hk_ui;
import '../monetization.dart';

Future<void> showEarnPointsFlow(
  BuildContext context,
  WidgetRef ref, {
  required String entryPoint,
}) => runWithNativeAdsSuspended(
  context,
  () => _showEarnPointsFlow(context, ref, entryPoint: entryPoint),
);

Future<void> _showEarnPointsFlow(
  BuildContext context,
  WidgetRef ref, {
  required String entryPoint,
}) async {
  final config =
      ref.read(monetizationConfigProvider).value ??
      const MonetizationConfig.failClosed();
  final wallet = ref.read(pointWalletProvider).value;
  if (!config.adsEnabled || !config.rewardedAdsEnabled) {
    hk_ui.showToast(
      context,
      content: Text(context.l10n.pointRewardsUnavailable),
    );
    return;
  }
  if ((wallet?.balance ?? config.walletCap) >= config.walletCap) {
    hk_ui.showToast(context, content: Text(context.l10n.walletAlreadyFull));
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      actionsOverflowButtonSpacing: HkSpacing.xs,
      title: Text(context.l10n.earnOnePoint),
      content: Text(context.l10n.earnOnePointDescription),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Symbols.play_circle_rounded),
          label: Text(context.l10n.watchAd),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  hk_ui.showToast(context, content: Text(context.l10n.loadingRewardedAd));
  final result = await ref
      .read(owntendAdsProvider)
      .showReward(
        RewardAdType.rewardedAd,
        timeZone: wallet?.timeZone,
        entryPoint: entryPoint,
      );
  if (!context.mounted) return;
  switch (result) {
    case RewardShowResult.shownAwaitingServerVerification:
      ref
          .read(pointWalletControllerProvider.notifier)
          .pollForServerVerification();
      hk_ui.showToast(
        context,
        content: Text(context.l10n.adWatchedVerifyingPoint),
      );
    case RewardShowResult.unavailable:
      hk_ui.showToast(
        context,
        content: Text(context.l10n.noRewardedAdAvailable),
      );
    case RewardShowResult.rejected:
      hk_ui.showToast(
        context,
        content: Text(context.l10n.rewardUnavailableOrClaimed),
      );
    case RewardShowResult.dismissed:
      hk_ui.showToast(context, content: Text(context.l10n.rewardAdClosedEarly));
  }
}
