import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/config/app_config.dart';
import 'package:owntend/src/features/monetization/ad_cache.dart';
import 'package:owntend/src/features/monetization/ad_retry_policy.dart';
import 'package:owntend/src/features/monetization/ad_runtime.dart';
import 'package:owntend/src/features/monetization/monetization.dart';
import 'package:mocktail/mocktail.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('InterstitialEligibilityPolicy', () {
    late DateTime now;
    late InterstitialEligibilityPolicy policy;
    const config = MonetizationConfig(
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
      interstitialSessionCap: 2,
    );

    setUp(() {
      now = DateTime.utc(2026, 8, 1, 10);
      policy = InterstitialEligibilityPolicy(now: () => now)
        ..firstEverSession = false;
    });

    test('allows an eligible completion and enforces cooldown', () {
      expect(
        policy.registerCompletionAndCanShow(
          config: config,
          keyboardVisible: false,
          modalActive: false,
        ),
        isTrue,
      );
      policy.markShown();
      now = now.add(const Duration(seconds: 181));
      expect(
        policy.registerCompletionAndCanShow(
          config: config,
          keyboardVisible: false,
          modalActive: false,
        ),
        isTrue,
      );
    });

    test(
      'suppresses rapid completions, keyboard, modal, and first session',
      () {
        expect(
          policy.registerCompletionAndCanShow(
            config: config,
            keyboardVisible: false,
            modalActive: false,
          ),
          isTrue,
        );
        now = now.add(const Duration(seconds: 30));
        expect(
          policy.registerCompletionAndCanShow(
            config: config,
            keyboardVisible: false,
            modalActive: false,
          ),
          isFalse,
        );
        now = now.add(const Duration(seconds: 61));
        expect(
          policy.registerCompletionAndCanShow(
            config: config,
            keyboardVisible: true,
            modalActive: false,
          ),
          isFalse,
        );
        now = now.add(const Duration(seconds: 61));
        expect(
          policy.registerCompletionAndCanShow(
            config: config,
            keyboardVisible: false,
            modalActive: true,
          ),
          isFalse,
        );
        policy.firstEverSession = true;
        now = now.add(const Duration(seconds: 61));
        expect(
          policy.registerCompletionAndCanShow(
            config: config,
            keyboardVisible: false,
            modalActive: false,
          ),
          isFalse,
        );
      },
    );

    test('honors the remote session cap and kill switch', () {
      expect(
        policy.registerCompletionAndCanShow(
          config: config,
          keyboardVisible: false,
          modalActive: false,
        ),
        isTrue,
      );
      policy.markShown();
      now = now.add(const Duration(seconds: 181));
      expect(
        policy.registerCompletionAndCanShow(
          config: config,
          keyboardVisible: false,
          modalActive: false,
        ),
        isTrue,
      );
      policy.markShown();
      now = now.add(const Duration(seconds: 181));
      expect(
        policy.registerCompletionAndCanShow(
          config: config,
          keyboardVisible: false,
          modalActive: false,
        ),
        isFalse,
      );
      const disabled = MonetizationConfig.failClosed();
      expect(
        InterstitialEligibilityPolicy(now: () => now)..firstEverSession = false,
        isNotNull,
      );
      expect(
        policy.registerCompletionAndCanShow(
          config: disabled,
          keyboardVisible: false,
          modalActive: false,
        ),
        isFalse,
      );
    });
  });

  test('production and non-production builds use separate ad units', () {
    const production = OwntendAdUnits(production: true);
    const testUnits = OwntendAdUnits(production: false);
    expect(production.rewarded, contains('5274007212820203'));
    expect(testUnits.rewarded, contains('3940256099942544'));
    expect(production.native('home'), isNot(production.native('more')));
  });

  test('all native ad units use the server-accepted canonical format', () {
    final units = [
      for (final production in [true, false])
        for (final placement in [
          'home',
          'assets',
          'room_detail',
          'thing_detail',
          'task_detail',
          'maintenance',
          'calendar',
          'more',
          'search',
          'notifications',
          'statistics',
          'account',
          'backup',
          'trash',
          'settings',
          'permission_setup',
        ])
          OwntendAdUnits(production: production).native(placement),
    ];
    final canonicalAdMobId = RegExp(r'^ca-app-pub-[0-9]{16}/[0-9]{10}$');
    expect(units, everyElement(matches(canonicalAdMobId)));
  });

  test('consent debug settings map from app config', () {
    final config = AppConfig.configured(
      environment: AppEnvironment.dev,
      supabaseUrl: 'http://127.0.0.1:54321',
      supabasePublishableKey: 'sb_publishable_example',
      googleWebClientId: '123-example.apps.googleusercontent.com',
      adMobTestDeviceIds: 'ABCDEF1234567890,1234567890ABCDEF',
      adConsentDebugGeography: 'other',
    );

    final settings = consentDebugSettingsForAppConfig(config);

    expect(settings, isNotNull);
    expect(settings!.debugGeography, DebugGeography.debugGeographyOther);
    expect(settings.testIdentifiers, ['ABCDEF1234567890', '1234567890ABCDEF']);
  });

  test('request configuration keeps safe defaults and test devices', () {
    final configuration = adRequestConfiguration(
      testDeviceIds: const ['ABCDEF1234567890ABCDEF1234567890'],
    );

    expect(configuration.maxAdContentRating, MaxAdContentRating.pg);
    expect(
      configuration.ageRestrictedTreatment,
      AgeRestrictedTreatment.unspecified,
    );
    expect(configuration.testDeviceIds, ['ABCDEF1234567890ABCDEF1234567890']);
  });

  test('remote configuration controls wallet capacity', () {
    final config = MonetizationConfig.fromJson({
      'ads_enabled': true,
      'native_ads_enabled': true,
      'interstitial_ads_enabled': true,
      'rewarded_ads_enabled': true,
      'rewarded_interstitial_enabled': true,
      'points_enabled': true,
      'emergency_free_creation_mode': false,
      'wallet_cap': 25,
      'interstitial_cooldown_seconds': 180,
      'rapid_completion_window_seconds': 60,
      'interstitial_session_cap': 3,
    });

    expect(config.walletCap, 25);
    expect(config.creationIsFree, isFalse);
  });

  test('ad retry delay is epoch bounded', () {
    expect(adRetryDelayForFailure(1), const Duration(seconds: 2));
    expect(adRetryDelayForFailure(2), const Duration(seconds: 8));
    expect(adRetryDelayForFailure(3), const Duration(seconds: 30));
    expect(adRetryDelayForFailure(4), const Duration(seconds: 60));
    expect(adRetryDelayForFailure(5), Duration.zero);
    expect(adRetryDelayForFailure(99), Duration.zero);
  });

  group('ad runtime safety contracts', () {
    const eligible = AdRuntimeEligibility(
      platformSupported: true,
      appResumed: true,
      consentUpdated: true,
      canRequestAds: true,
      adsEnabled: true,
      nativeAdsEnabled: true,
      interstitialAdsEnabled: true,
      rewardedAdsEnabled: true,
      rewardedInterstitialEnabled: true,
    );

    test('requires every global gate and each format kill switch', () {
      for (final format in AdFormat.values) {
        expect(eligible.allows(format), isTrue);
      }
      const blockedBeforeConsentRefresh = AdRuntimeEligibility(
        platformSupported: true,
        appResumed: true,
        consentUpdated: false,
        canRequestAds: true,
        adsEnabled: true,
        nativeAdsEnabled: true,
        interstitialAdsEnabled: true,
        rewardedAdsEnabled: true,
        rewardedInterstitialEnabled: true,
      );
      const blockedInBackground = AdRuntimeEligibility(
        platformSupported: true,
        appResumed: false,
        consentUpdated: true,
        canRequestAds: true,
        adsEnabled: true,
        nativeAdsEnabled: true,
        interstitialAdsEnabled: true,
        rewardedAdsEnabled: true,
        rewardedInterstitialEnabled: true,
      );
      for (final format in AdFormat.values) {
        expect(blockedBeforeConsentRefresh.allows(format), isFalse);
        expect(blockedInBackground.allows(format), isFalse);
      }
      const nativeDisabled = AdRuntimeEligibility(
        platformSupported: true,
        appResumed: true,
        consentUpdated: true,
        canRequestAds: true,
        adsEnabled: true,
        nativeAdsEnabled: false,
        interstitialAdsEnabled: true,
        rewardedAdsEnabled: true,
        rewardedInterstitialEnabled: true,
      );
      expect(nativeDisabled.allows(AdFormat.native), isFalse);
      expect(nativeDisabled.allows(AdFormat.interstitial), isTrue);
    });

    test('generation advances only for material transitions', () {
      final controller = AdRuntimeController();
      final first = controller.apply(eligible);
      final duplicate = controller.apply(eligible);
      final blocked = controller.apply(const AdRuntimeEligibility.blocked());

      expect(first.changed, isTrue);
      expect(first.generation, 1);
      expect(duplicate.changed, isFalse);
      expect(duplicate.generation, 1);
      expect(blocked.generation, 2);
      expect(blocked.lost(AdFormat.rewarded), isTrue);
    });

    test('retry classification and budgets fail dormant', () {
      const policy = AdRetryPolicy();
      expect(
        classifyAdLoadFailure(code: 2, domain: 'mobile-ads'),
        AdLoadFailureKind.network,
      );
      expect(
        classifyAdLoadFailure(code: 3, domain: 'mobile-ads'),
        AdLoadFailureKind.noFill,
      );
      expect(
        classifyAdLoadFailure(code: 1, domain: 'mobile-ads'),
        AdLoadFailureKind.invalidRequest,
      );

      final lowerJitter = policy.decide(
        failure: AdLoadFailureKind.network,
        failedAttempt: 1,
        jitterUnit: 0,
      );
      final upperJitter = policy.decide(
        failure: AdLoadFailureKind.network,
        failedAttempt: 1,
        jitterUnit: 1,
      );
      expect(lowerJitter.delay, const Duration(milliseconds: 1600));
      expect(upperJitter.delay, const Duration(milliseconds: 2400));
      expect(
        [
          for (var failure = 1; failure <= 4; failure++)
            policy
                .decide(
                  failure: AdLoadFailureKind.network,
                  failedAttempt: failure,
                )
                .delay,
        ],
        const [
          Duration(seconds: 2),
          Duration(seconds: 8),
          Duration(seconds: 30),
          Duration(seconds: 60),
        ],
      );
      expect(
        policy
            .decide(failure: AdLoadFailureKind.network, failedAttempt: 5)
            .dormant,
        isTrue,
      );
      expect(
        policy
            .decide(failure: AdLoadFailureKind.noFill, failedAttempt: 1)
            .dormant,
        isTrue,
      );
      expect(
        policy
            .decide(failure: AdLoadFailureKind.internal, failedAttempt: 3)
            .dormant,
        isTrue,
      );
      expect(
        policy
            .decide(failure: AdLoadFailureKind.internal, failedAttempt: 2)
            .delay,
        const Duration(seconds: 8),
      );
    });

    test('cache is fresh until, but not at, 55 minutes', () {
      final loadedAt = DateTime.utc(2026, 8, 1, 12);
      final cached = CachedAd(value: Object(), loadedAt: loadedAt);

      expect(
        cached.isFresh(loadedAt.add(const Duration(minutes: 54, seconds: 59))),
        isTrue,
      );
      expect(
        cached.isFresh(loadedAt.add(const Duration(minutes: 55))),
        isFalse,
      );
    });

    test('reward presentation rechecks lifecycle generation before show', () {
      expect(
        rewardPresentationIsCurrent(
          disposed: false,
          requestGeneration: 7,
          currentGeneration: 7,
          formatAllowed: true,
        ),
        isTrue,
      );
      expect(
        rewardPresentationIsCurrent(
          disposed: false,
          requestGeneration: 7,
          currentGeneration: 8,
          formatAllowed: true,
        ),
        isFalse,
      );
      expect(
        rewardPresentationIsCurrent(
          disposed: false,
          requestGeneration: 7,
          currentGeneration: 7,
          formatAllowed: false,
        ),
        isFalse,
      );
      expect(
        rewardPresentationIsCurrent(
          disposed: true,
          requestGeneration: 7,
          currentGeneration: 7,
          formatAllowed: true,
        ),
        isFalse,
      );
    });

    test('leases dispose exactly once and serialize fullscreen ownership', () {
      var releases = 0;
      final lease = AdLease(Object(), (_) => releases++);
      lease.release();
      lease.release();
      expect(releases, 1);

      final gate = FullScreenAdGate();
      final first = gate.tryAcquire();
      expect(first, isNotNull);
      expect(gate.tryAcquire(), isNull);
      first!.release();
      first.release();
      expect(gate.tryAcquire(), isNotNull);
    });
  });

  test('native ads unmount whenever a modal route obscures the page', () {
    expect(
      nativeAdPlacementEnabled(
        routeIsCurrent: false,
        configEnabled: true,
        consentGranted: true,
        adsInitialized: true,
        platformSupported: true,
        enabledOverride: true,
      ),
      isFalse,
    );
    expect(
      nativeAdPlacementEnabled(
        routeIsCurrent: true,
        presentationSuppressed: true,
        configEnabled: true,
        consentGranted: true,
        adsInitialized: true,
        platformSupported: true,
        enabledOverride: true,
      ),
      isFalse,
    );
    expect(
      nativeAdPlacementEnabled(
        routeIsCurrent: true,
        configEnabled: true,
        consentGranted: true,
        adsInitialized: true,
        platformSupported: true,
      ),
      isTrue,
    );
    expect(
      nativeAdPlacementEnabled(
        routeIsCurrent: true,
        configEnabled: false,
        consentGranted: false,
        adsInitialized: false,
        platformSupported: false,
        enabledOverride: true,
      ),
      isFalse,
    );
  });

  test('native production placement mapping rejects unknown names', () {
    const production = OwntendAdUnits(production: true);
    expect(production.native('home'), 'ca-app-pub-5274007212820203/8393243294');
    const secondaryPlacements = [
      'assets',
      'room_detail',
      'thing_detail',
      'task_detail',
      'maintenance',
      'calendar',
      'more',
      'search',
      'notifications',
      'statistics',
      'account',
      'backup',
      'trash',
      'settings',
      'permission_setup',
    ];
    for (final placement in secondaryPlacements) {
      expect(
        production.native(placement),
        'ca-app-pub-5274007212820203/7543196051',
      );
    }
    expect(() => production.native('typo'), throwsArgumentError);
  });

  testWidgets(
    'native ad loading surface follows content cards in both themes',
    (tester) async {
      for (final brightness in Brightness.values) {
        final scheme = ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: brightness,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: const Scaffold(body: HkNativeAdLoadingSkeleton()),
          ),
        );
        await tester.pumpAndSettle();

        final decoration =
            tester
                    .widget<DecoratedBox>(
                      find.byKey(const ValueKey('native-ad-loading-skeleton')),
                    )
                    .decoration
                as BoxDecoration;
        expect(decoration.color, scheme.surfaceContainerLowest);
      }
    },
  );

  test('pending reward claim preserves recovery metadata', () {
    final claim = PendingRewardClaim.fromJson({
      'claim_id': 'claim-1',
      'reward_amount': 2,
      'expires_at': '2026-08-02T12:00:00Z',
    });

    expect(claim.claimId, 'claim-1');
    expect(claim.rewardAmount, 2);
    expect(claim.expiresAt, DateTime.utc(2026, 8, 2, 12));
  });

  test(
    'offline creation drafts persist, restore, and clear securely',
    () async {
      final secureStorage = _MockSecureStorage();
      String? encoded;
      when(
        () => secureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((invocation) async {
        encoded = invocation.namedArguments[#value] as String?;
      });
      when(() => secureStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => encoded);
      when(() => secureStorage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});
      final store = OfflineCreationDraftStore(secureStorage);

      await store.save('task_user_asset', {
        'operation_id': 'operation-1',
        'title': 'Inspect seals',
        'materials': ['cloth', 'sealant'],
      });

      expect(await store.load('task_user_asset'), {
        'operation_id': 'operation-1',
        'title': 'Inspect seals',
        'materials': ['cloth', 'sealant'],
      });
      await store.clear('task_user_asset');
      verify(
        () => secureStorage.delete(
          key: 'owntend_creation_draft_v1_task_user_asset',
        ),
      ).called(1);
    },
  );

  test('offline draft account cleanup preserves other accounts', () async {
    final secureStorage = _MockSecureStorage();
    final stored = <String, String>{
      'owntend_creation_draft_v1_task_user-1_asset-a': '{}',
      'owntend_creation_draft_v1_asset_user-1_room-a': '{}',
      'owntend_creation_draft_v1_asset_copy_user-1_asset-b': '{}',
      'owntend_creation_draft_v1_task_user-10_asset-c': '{}',
      'unrelated': '{}',
    };
    when(() => secureStorage.readAll()).thenAnswer((_) async => stored);
    when(() => secureStorage.delete(key: any(named: 'key')))
        .thenAnswer((invocation) async {
          stored.remove(invocation.namedArguments[#key] as String);
        });

    await OfflineCreationDraftStore(secureStorage).clearForAccount('user-1');

    expect(stored.keys, {
      'owntend_creation_draft_v1_task_user-10_asset-c',
      'unrelated',
    });
  });

  testWidgets('native slot owns visible spacing and removes it after no-fill', (
    tester,
  ) async {
    Future<void> pumpSlot(bool collapsed) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HkNativeAdSlotFrame(
              collapsed: collapsed,
              bottomSpacing: 12,
              child: const ColoredBox(color: Colors.green),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpSlot(false);
    expect(tester.getSize(find.byType(HkNativeAdSlotFrame)).height, 124);
    await pumpSlot(true);
    expect(tester.getSize(find.byType(HkNativeAdSlotFrame)).height, 0);
  });

  testWidgets('native loading state renders a labeled skeleton surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 112, child: HkNativeAdLoadingSkeleton()),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('native-ad-loading-skeleton')), findsOne);
    expect(find.byType(HkNativeAdLoadingSkeleton), findsOne);
  });
}
