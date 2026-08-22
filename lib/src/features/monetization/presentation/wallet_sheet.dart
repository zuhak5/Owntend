part of 'monetization_presentation.dart';

Future<void> offerDailyCompletionReward(
  BuildContext context,
  WidgetRef ref,
) async {
  final config =
      ref.read(monetizationConfigProvider).value ??
      const MonetizationConfig.failClosed();
  final wallet = ref.read(pointWalletProvider).value;
  if (!config.adsEnabled ||
      !config.rewardedInterstitialEnabled ||
      (wallet?.balance ?? config.walletCap) + 2 > config.walletCap) {
    return;
  }
  final accepted = await showDailyCompletionRewardSheet(context);
  if (accepted != true || !context.mounted) return;
  final result = await ref
      .read(owntendAdsProvider)
      .showReward(
        RewardAdType.rewardedInterstitial,
        timeZone: wallet?.timeZone,
        entryPoint: 'today_complete_milestone',
      );
  if (!context.mounted) return;
  final message = dailyCompletionRewardResultMessage(context, result);
  hk_ui.showToast(context, content: Text(message));
}

Future<void> showPointsWalletSheet(BuildContext context, WidgetRef ref) async {
  final repository = ref.read(monetizationRepositoryProvider);
  final transactions = repository?.listTransactions();
  await runWithNativeAdsSuspended(
    context,
    () => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final wallet = ref.watch(pointWalletProvider).value;
          final config =
              ref.watch(monetizationConfigProvider).value ??
              const MonetizationConfig.failClosed();
          final pendingClaims =
              ref.watch(pendingRewardClaimsProvider).value ?? const [];
          final sheetHeight = math.max(
            320.0,
            MediaQuery.sizeOf(context).height * 0.82,
          );
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 640,
                maxHeight: sheetHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  HkSpacing.gutter,
                  0,
                  HkSpacing.gutter,
                  HkSpacing.gutter,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Symbols.stars_rounded, size: 30),
                        const SizedBox(width: HkSpacing.sm),
                        Expanded(
                          child: Text(
                            context.l10n.pointsWallet,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        Text(
                          '${wallet?.balance ?? 0} / ${config.walletCap}',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: HkSpacing.sm),
                    if (pendingClaims.isNotEmpty) ...[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer
                              .withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(HkRadii.md),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(HkSpacing.sm),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: HkSpacing.sm),
                              Expanded(
                                child: Text(
                                  context.l10n.rewardVerificationPending,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: HkSpacing.sm),
                    ],
                    FilledButton.icon(
                      onPressed:
                          (wallet?.balance ?? config.walletCap) >=
                              config.walletCap
                          ? null
                          : () async {
                              await showEarnPointsFlow(
                                context,
                                ref,
                                entryPoint: 'wallet',
                              );
                            },
                      icon: const Icon(Symbols.play_circle_rounded),
                      label: Text(context.l10n.earnFreePoints),
                    ),
                    const SizedBox(height: HkSpacing.sm),
                    Text(
                      context.l10n.pointsRuleExplanation,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: HkSpacing.md),
                    Text(
                      context.l10n.recentActivity,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: HkSpacing.xs),
                    Expanded(
                      child: transactions == null
                          ? Center(
                              child: Text(context.l10n.activityUnavailable),
                            )
                          : FutureBuilder<List<Map<String, dynamic>>>(
                              future: transactions,
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                final rows = snapshot.data!;
                                if (rows.isEmpty) {
                                  return Center(
                                    child: Text(context.l10n.noPointActivity),
                                  );
                                }
                                return ListView.builder(
                                  itemCount: rows.length,
                                  itemBuilder: (context, index) {
                                    final row = rows[index];
                                    final amount = row['amount'] as int? ?? 0;
                                    final created = DateTime.tryParse(
                                      row['created_at'] as String? ?? '',
                                    )?.toLocal();
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: CircleAvatar(
                                        child: Icon(
                                          amount > 0
                                              ? Symbols.add_rounded
                                              : Symbols.remove_rounded,
                                        ),
                                      ),
                                      title: Text(
                                        _pointTransactionLabel(
                                          context,
                                          row['transaction_type'] as String? ??
                                              '',
                                        ),
                                      ),
                                      subtitle: created == null
                                          ? null
                                          : Text(
                                              DateFormat.yMMMd()
                                                  .add_jm()
                                                  .format(created),
                                            ),
                                      trailing: Text(
                                        '${amount > 0 ? '+' : ''}$amount',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: amount > 0
                                                  ? HkColors.green
                                                  : Theme.of(context)
                                                        .colorScheme
                                                        .error,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

String _pointTransactionLabel(BuildContext context, String type) =>
    switch (type) {
      'initial_grant' => context.l10n.startingPoints,
      'task_creation' => context.l10n.taskCreatedPointTransaction,
      'asset_creation' => context.l10n.itemCreatedPointTransaction,
      'rewarded_ad' => context.l10n.rewardedAdPointTransaction,
      'rewarded_interstitial' => context.l10n.dailyCompletionReward,
      'refund' => context.l10n.refundPointTransaction,
      _ => context.l10n.pointAdjustment,
    };

Future<void> showPointShortageDialog(
  BuildContext context,
  WidgetRef ref, {
  required String attemptedAction,
}) async {
  unawaited(
    ref.read(monetizationRepositoryProvider)?.recordEvent(
      'point_shortage_encountered',
      {'attempted_action': attemptedAction},
    ),
  );
  await runWithNativeAdsSuspended(
    context,
    () => showDialog<void>(
      context: context,
      builder: (context) => const _PointShortageDialog(),
    ),
  );
}
