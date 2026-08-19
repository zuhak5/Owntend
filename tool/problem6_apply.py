from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding="utf-8")
    if new in text:
        return
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one old match, found {count}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


main = Path("lib/main.dart")
text = main.read_text(encoding="utf-8")
anchor = "part 'src/features/maintenance/presentation/task_detail_screen.dart';\n"
part_line = "part 'src/features/maintenance/presentation/daily_completion_reward_sheet.dart';\n"
if part_line not in text:
    if anchor not in text:
        raise SystemExit("main.dart maintenance part anchor missing")
    main.write_text(text.replace(anchor, anchor + part_line, 1), encoding="utf-8")

Path("lib/src/features/maintenance/presentation/daily_completion_reward_sheet.dart").write_text(
    r'''part of '../../../../main.dart';

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
            constraints: BoxConstraints(maxWidth: 520, maxHeight: availableHeight),
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
''',
    encoding="utf-8",
)

backup = Path("lib/src/features/backup/presentation/backup_screen.dart")
source = backup.read_text(encoding="utf-8")
old_sheet = '''  final accepted = await runWithNativeAdsSuspended(
    context,
    () => showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              HkSpacing.gutter,
              0,
              HkSpacing.gutter,
              HkSpacing.gutter,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Symbols.celebration_rounded, size: 44),
                const SizedBox(height: HkSpacing.sm),
                Text(
                  context.l10n.todayCareComplete,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: HkSpacing.xs),
                Text(
                  context.l10n.optionalDailyRewardDescription,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: HkSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(context.l10n.notNow),
                        ),
                      ),
                    ),
                    const SizedBox(width: HkSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Symbols.play_circle_rounded),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(context.l10n.earnTwoPoints),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );'''
new_sheet = "  final accepted = await showDailyCompletionRewardSheet(context);"
if old_sheet in source:
    source = source.replace(old_sheet, new_sheet, 1)
elif new_sheet not in source:
    raise SystemExit("completion reward sheet block not found")
source = source.replace(
    "await _offerDailyCompletionReward(context, ref);",
    "await offerDailyCompletionReward(context, ref);",
    1,
)
source = source.replace(
    "Future<void> _offerDailyCompletionReward(",
    "Future<void> offerDailyCompletionReward(",
    1,
)
old_message = '''  final message = switch (result) {
    RewardShowResult.shownAwaitingServerVerification =>
      context.l10n.rewardWatchedVerifyingTwo,
    RewardShowResult.unavailable => context.l10n.noRewardAvailable,
    RewardShowResult.rejected => context.l10n.dailyRewardAlreadyClaimed,
    RewardShowResult.dismissed => context.l10n.rewardAdClosedEarly,
  };'''
new_message = "  final message = dailyCompletionRewardResultMessage(context, result);"
if old_message in source:
    source = source.replace(old_message, new_message, 1)
elif new_message not in source:
    raise SystemExit("reward result message block not found")
backup.write_text(source, encoding="utf-8")

replace_once(
    "lib/l10n/app_en.arb",
    '  "optionalDailyRewardDescription": "Optionally watch a rewarded interstitial to earn 2 points. Your reward is credited only after secure server verification.",',
    '  "optionalDailyRewardDescription": "Watch a short video to earn 2 bonus points.",',
)
replace_once(
    "lib/l10n/app_en.arb",
    '  "rewardWatchedVerifyingTwo": "Reward watched. Verifying 2 points securely…",',
    '  "rewardWatchedVerifyingTwo": "Verifying your reward…",',
)
replace_once(
    "lib/l10n/app_ar.arb",
    '  "optionalDailyRewardDescription": "يمكنك اختياريًا مشاهدة إعلان بيني بمكافأة لكسب نقطتين. تُضاف مكافأتك بعد التحقق الآمن من الخادم فقط.",',
    '  "optionalDailyRewardDescription": "شاهد فيديو قصيرًا لتحصل على نقطتين إضافيتين.",',
)
replace_once(
    "lib/l10n/app_ar.arb",
    '  "earnTwoPoints": "اكسب نقطتين",',
    '  "earnTwoPoints": "احصل على نقطتين",',
)
replace_once(
    "lib/l10n/app_ar.arb",
    '  "rewardWatchedVerifyingTwo": "تمت مشاهدة المكافأة. جارٍ التحقق الآمن من نقطتين…",',
    '  "rewardWatchedVerifyingTwo": "جارٍ التحقق من مكافأتك…",',
)

monetization_doc = Path("docs/architecture/monetization.md")
doc = monetization_doc.read_text(encoding="utf-8")
paragraph = (
    "After the final due-today task is completed, the optional daily reward decision is presented as a compact, content-sized bottom sheet. "
    "It uses user-facing video/reward wording, keeps both actions close to the explanation, stacks them when width or text scaling requires it, "
    "preserves bottom safe-area/keyboard reachability, and removes the sheet transition when reduced motion is requested. After the device reward "
    "callback, the client reports only that the reward is being verified; it does not present the points as credited or mutate the wallet.\n\n"
)
if paragraph not in doc:
    marker = "A rewarded flow is stricter:\n\n"
    if marker not in doc:
        raise SystemExit("monetization doc insertion point missing")
    monetization_doc.write_text(doc.replace(marker, marker + paragraph, 1), encoding="utf-8")

changelog = Path("CHANGELOG.md")
ch = changelog.read_text(encoding="utf-8")
bullet = "- Made the “Today’s care is complete” reward prompt content-sized and accessible, with concise English/Arabic copy, responsive non-truncated actions, reduced-motion handling, and verification-pending messaging that never implies device-side reward credit.\n"
if bullet not in ch:
    fixed = "### Fixed\n\n"
    if fixed not in ch:
        raise SystemExit("changelog Fixed section missing")
    changelog.write_text(ch.replace(fixed, fixed + bullet, 1), encoding="utf-8")

Path("test/problem_006_completion_reward_sheet_test.dart").write_text(
    r'''import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/features/monetization/monetization.dart';

import 'test_theme.dart';

class _PendingRewardAdsService extends OwntendAdsService {
  _PendingRewardAdsService()
    : super(
        useProductionUnits: false,
        testDeviceIds: const [],
        adInspectorEnabled: false,
        repository: null,
      );

  @override
  Future<RewardShowResult> showReward(
    RewardAdType type, {
    required String? timeZone,
    required String entryPoint,
  }) async => RewardShowResult.shownAwaitingServerVerification;
}

const _rewardConfig = MonetizationConfig(
  adsEnabled: true,
  nativeAdsEnabled: true,
  interstitialAdsEnabled: true,
  rewardedAdsEnabled: true,
  rewardedInterstitialEnabled: true,
  pointsEnabled: true,
  emergencyFreeCreationMode: false,
  walletCap: 20,
  interstitialCooldownSeconds: 180,
  rapidCompletionWindowSeconds: 60,
  interstitialSessionCap: 3,
);

void _setViewport(WidgetTester tester, {required Size size}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<ProviderContainer> _pumpSheetLauncher(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: testLightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDailyCompletionRewardSheet(context),
              child: const Text('Open reward'),
            ),
          ),
        ),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('reward sheet is compact and uses balanced horizontal actions', (
    tester,
  ) async {
    _setViewport(tester, size: const Size(390, 844));
    final container = await _pumpSheetLauncher(tester);

    await tester.tap(find.text('Open reward'));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const ValueKey('daily-completion-reward-sheet'));
    final notNow = find.byKey(const ValueKey('daily-completion-not-now'));
    final reward = find.byKey(const ValueKey('daily-completion-reward'));
    expect(sheet, findsOneWidget);
    expect(find.text('Today’s care is complete'), findsOneWidget);
    expect(find.text('Watch a short video to earn 2 bonus points.'), findsOneWidget);
    expect(tester.getSize(sheet).height, lessThan(340));
    expect((tester.getCenter(notNow).dy - tester.getCenter(reward).dy).abs(), lessThan(1));
    expect((tester.getSize(notNow).width - tester.getSize(reward).width).abs(), lessThan(2));
    expect(container.read(nativeAdPresentationDepthProvider), 1);

    await tester.tap(notNow);
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(container.read(nativeAdPresentationDepthProvider), 0);
  });

  testWidgets('reward actions stack without truncation at narrow high text scale', (
    tester,
  ) async {
    _setViewport(tester, size: const Size(300, 640));
    await _pumpSheetLauncher(tester, textScale: 1.8);

    await tester.tap(find.text('Open reward'));
    await tester.pumpAndSettle();

    final notNow = find.byKey(const ValueKey('daily-completion-not-now'));
    final reward = find.byKey(const ValueKey('daily-completion-reward'));
    expect(find.text('Not now'), findsOneWidget);
    expect(find.text('Earn 2 points'), findsOneWidget);
    expect(tester.getCenter(reward).dy, lessThan(tester.getCenter(notNow).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reward sheet uses natural Arabic copy and RTL direction', (
    tester,
  ) async {
    _setViewport(tester, size: const Size(390, 844));
    await _pumpSheetLauncher(tester, locale: const Locale('ar'));

    await tester.tap(find.text('Open reward'));
    await tester.pumpAndSettle();

    final arabic = lookupAppLocalizations(const Locale('ar'));
    final sheet = find.byKey(const ValueKey('daily-completion-reward-sheet'));
    expect(find.text(arabic.todayCareComplete), findsOneWidget);
    expect(find.text(arabic.optionalDailyRewardDescription), findsOneWidget);
    expect(Directionality.of(tester.element(sheet)), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion presents the reward sheet without transition delay', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    _setViewport(tester, size: const Size(390, 844));
    await _pumpSheetLauncher(tester);

    await tester.tap(find.text('Open reward'));
    await tester.pump();
    expect(find.byKey(const ValueKey('daily-completion-reward-sheet')), findsOneWidget);
  });

  testWidgets('pending reward stays verification-only and does not credit wallet', (
    tester,
  ) async {
    _setViewport(tester, size: const Size(390, 844));
    final wallet = PointWallet(
      balance: 5,
      timeZone: 'Asia/Baghdad',
      updatedAt: DateTime.utc(2026, 8, 19),
    );
    final container = ProviderContainer(
      overrides: [
        monetizationConfigProvider.overrideWithValue(const AsyncData(_rewardConfig)),
        pointWalletProvider.overrideWithValue(AsyncData(wallet)),
        owntendAdsProvider.overrideWithValue(_PendingRewardAdsService()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: testLightTheme(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => FilledButton(
                onPressed: () => offerDailyCompletionReward(context, ref),
                child: const Text('Offer reward'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Offer reward'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('daily-completion-reward')));
    await tester.pumpAndSettle();

    expect(find.text('Verifying your reward…'), findsOneWidget);
    expect(container.read(pointWalletProvider).value?.balance, 5);
    expect(container.read(nativeAdPresentationDepthProvider), 0);
  });

  testWidgets('native ad suspension depth balances after presentation errors', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  try {
                    await runWithNativeAdsSuspended<void>(
                      context,
                      () async => throw StateError('presentation failed'),
                    );
                  } catch (_) {}
                },
                child: const Text('Trigger error'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Trigger error'));
    await tester.pump();
    expect(container.read(nativeAdPresentationDepthProvider), 0);
  });
}
''',
    encoding="utf-8",
)
