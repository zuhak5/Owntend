import 'package:flutter/material.dart';
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
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
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
  testWidgets('reward sheet is compact with balanced horizontal actions', (
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
    expect(
      find.text('Watch a short video to earn 2 bonus points.'),
      findsOneWidget,
    );
    expect(tester.getSize(sheet).height, lessThan(340));
    expect(
      (tester.getCenter(notNow).dy - tester.getCenter(reward).dy).abs(),
      lessThan(1),
    );
    expect(
      (tester.getSize(notNow).width - tester.getSize(reward).width).abs(),
      lessThan(2),
    );
    expect(container.read(nativeAdPresentationDepthProvider), 1);

    await tester.tap(notNow);
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(container.read(nativeAdPresentationDepthProvider), 0);
  });

  testWidgets(
    'reward actions stack without truncation at narrow high text scale',
    (tester) async {
      _setViewport(tester, size: const Size(300, 640));
      await _pumpSheetLauncher(tester, textScale: 1.8);

      await tester.tap(find.text('Open reward'));
      await tester.pumpAndSettle();

      final notNow = find.byKey(const ValueKey('daily-completion-not-now'));
      final reward = find.byKey(const ValueKey('daily-completion-reward'));
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Earn 2 points'), findsOneWidget);
      expect(
        tester.getCenter(reward).dy,
        lessThan(tester.getCenter(notNow).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets(
    'reduced motion presents the reward sheet without transition delay',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      _setViewport(tester, size: const Size(390, 844));
      await _pumpSheetLauncher(tester);

      await tester.tap(find.text('Open reward'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('daily-completion-reward-sheet')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'pending reward stays verification-only and does not credit wallet',
    (tester) async {
      _setViewport(tester, size: const Size(390, 844));
      final wallet = PointWallet(
        balance: 5,
        timeZone: 'Asia/Baghdad',
        updatedAt: DateTime.utc(2026, 8, 19),
      );
      final container = ProviderContainer(
        overrides: [
          monetizationConfigProvider.overrideWithValue(
            const AsyncData(_rewardConfig),
          ),
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
    },
  );

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
