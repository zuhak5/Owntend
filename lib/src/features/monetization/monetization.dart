import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../l10n/app_localizations_ext.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/redacting_logger.dart';
import '../../ui/app_theme.dart';
import '../auth/presentation/auth_providers.dart';
import 'ad_cache.dart';
import 'ad_retry_policy.dart';
import 'ad_runtime.dart';

const _nativeFactoryId = 'owntendNative';
const _firstSessionStorageKey = 'monetization_has_completed_session_v1';

enum RewardAdType { rewardedAd, rewardedInterstitial }

enum RewardShowResult {
  shownAwaitingServerVerification,
  unavailable,
  rejected,
  dismissed,
}

enum AdInspectorOpenResult { opened, unavailable, failed }

@visibleForTesting
Duration adRetryDelayForFailure(int failureCount) {
  if (failureCount <= 0 || failureCount > 4) return Duration.zero;
  const seconds = [2, 8, 30, 60];
  return Duration(seconds: seconds[failureCount - 1]);
}

@visibleForTesting
AdLoadFailureKind classifyAdLoadFailure({
  required int code,
  required String domain,
}) {
  final normalizedDomain = domain.toLowerCase();
  if (code == 1) return AdLoadFailureKind.invalidRequest;
  if (code == 2) return AdLoadFailureKind.network;
  if (code == 3) return AdLoadFailureKind.noFill;
  if (code == 0 || normalizedDomain.contains('internal')) {
    return AdLoadFailureKind.internal;
  }
  return AdLoadFailureKind.unknown;
}

@visibleForTesting
bool rewardPresentationIsCurrent({
  required bool disposed,
  required int requestGeneration,
  required int currentGeneration,
  required bool formatAllowed,
}) => !disposed && requestGeneration == currentGeneration && formatAllowed;

Timer _defaultAdTimer(Duration delay, void Function() callback) =>
    Timer(delay, callback);

double _defaultAdJitter() => math.Random().nextDouble();

@visibleForTesting
bool nativeAdPlacementEnabled({
  required bool routeIsCurrent,
  required bool configEnabled,
  required bool consentGranted,
  required bool adsInitialized,
  required bool platformSupported,
  bool presentationSuppressed = false,
  bool? enabledOverride,
}) =>
    routeIsCurrent &&
    !presentationSuppressed &&
    enabledOverride != false &&
    configEnabled &&
    consentGranted &&
    adsInitialized &&
    platformSupported;

@visibleForTesting
ConsentDebugSettings? consentDebugSettingsForAppConfig(AppConfig config) {
  final debugGeography = switch (config.adConsentDebugGeography) {
    AdConsentDebugGeography.eea => DebugGeography.debugGeographyEea,
    AdConsentDebugGeography.regulatedUsState =>
      DebugGeography.debugGeographyRegulatedUsState,
    AdConsentDebugGeography.other => DebugGeography.debugGeographyOther,
    null => null,
  };
  final testIdentifiers = config.adMobTestDeviceIds.isEmpty
      ? null
      : List<String>.unmodifiable(config.adMobTestDeviceIds);
  if (debugGeography == null && testIdentifiers == null) {
    return null;
  }
  return ConsentDebugSettings(
    debugGeography: debugGeography,
    testIdentifiers: testIdentifiers,
  );
}

@visibleForTesting
RequestConfiguration adRequestConfiguration({
  required List<String> testDeviceIds,
}) {
  return RequestConfiguration(
    maxAdContentRating: MaxAdContentRating.pg,
    ageRestrictedTreatment: AgeRestrictedTreatment.unspecified,
    testDeviceIds: testDeviceIds,
  );
}

final nativeAdPresentationDepthProvider =
    NotifierProvider<NativeAdPresentationDepth, int>(
      NativeAdPresentationDepth.new,
    );

class NativeAdPresentationDepth extends Notifier<int> {
  @override
  int build() => 0;

  void push() => state++;

  void pop() => state = (state - 1).clamp(0, 1 << 20);

  void popAfterWidgetTeardown() {
    scheduleMicrotask(() {
      if (ref.mounted) pop();
    });
  }
}

Future<T> runWithNativeAdsSuspended<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  final presentationDepth = ProviderScope.containerOf(context)
      .read(nativeAdPresentationDepthProvider.notifier);
  presentationDepth.push();
  try {
    if (Platform.isAndroid) {
      // Android platform views are torn down at the end of the frame. Waiting
      // before pushing an overlay prevents the disposed native view from
      // receiving the overlay's first gesture. Other platforms do not need
      // this delay, which also keeps host-side widget interactions immediate.
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return await action();
  } finally {
    presentationDepth.pop();
  }
}

const _systemUiChannel = MethodChannel('owntend/system_ui');

Future<String?> resolveSystemRewardTimeZone(String? fallback) async {
  if (!_supportsMobileAds || !Platform.isAndroid) return fallback;
  try {
    final value = await _systemUiChannel.invokeMethod<String>('getTimeZoneId');
    final timeZone = value?.trim();
    return timeZone == null || timeZone.isEmpty ? fallback : timeZone;
  } on Object catch (error) {
    AppLogger.warning('reward_time_zone_lookup', error: error);
    return fallback;
  }
}

class OfflineCreationDraftStore {
  const OfflineCreationDraftStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  Future<void> save(String key, Map<String, dynamic> value) async {
    try {
      await _storage.write(key: _storageKey(key), value: jsonEncode(value));
    } on Object catch (error) {
      AppLogger.warning('offline_creation_draft_save', error: error);
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> load(String key) async {
    try {
      final encoded = await _storage.read(key: _storageKey(key));
      if (encoded == null) return null;
      final decoded = jsonDecode(encoded);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on Object catch (error) {
      AppLogger.warning('offline_creation_draft_load', error: error);
      return null;
    }
  }

  Future<void> clear(String key) async {
    try {
      await _storage.delete(key: _storageKey(key));
    } on Object catch (error) {
      AppLogger.warning('offline_creation_draft_clear', error: error);
    }
  }

  Future<void> clearForAccount(String accountId) async {
    final normalized = accountId.trim();
    if (normalized.isEmpty) return;
    final prefixes = <String>[
      _storageKey('asset_copy_${normalized}_'),
      _storageKey('asset_${normalized}_'),
      _storageKey('task_${normalized}_'),
    ];
    try {
      final stored = await _storage.readAll();
      for (final key in stored.keys.toList(growable: false)) {
        if (prefixes.any(key.startsWith)) {
          await _storage.delete(key: key);
        }
      }
    } on Object catch (error) {
      AppLogger.warning('offline_creation_draft_account_clear', error: error);
      rethrow;
    }
  }

  String _storageKey(String key) => 'owntend_creation_draft_v1_$key';
}

final offlineCreationDraftStoreProvider = Provider<OfflineCreationDraftStore>(
  (_) => const OfflineCreationDraftStore(),
);

class PointWallet {
  const PointWallet({
    required this.balance,
    required this.timeZone,
    required this.updatedAt,
  });

  factory PointWallet.fromJson(Map<String, dynamic> json) => PointWallet(
    balance: json['balance'] as int? ?? 0,
    timeZone: json['reward_time_zone'] as String? ?? 'UTC',
    updatedAt:
        DateTime.tryParse(json['updated_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  final int balance;
  final String timeZone;
  final DateTime updatedAt;
}

class MonetizationConfig {
  const MonetizationConfig({
    required this.adsEnabled,
    required this.nativeAdsEnabled,
    required this.interstitialAdsEnabled,
    required this.rewardedAdsEnabled,
    required this.rewardedInterstitialEnabled,
    required this.pointsEnabled,
    required this.emergencyFreeCreationMode,
    required this.walletCap,
    required this.interstitialCooldownSeconds,
    required this.rapidCompletionWindowSeconds,
    required this.interstitialSessionCap,
  });

  const MonetizationConfig.failClosed()
    : adsEnabled = false,
      nativeAdsEnabled = false,
      interstitialAdsEnabled = false,
      rewardedAdsEnabled = false,
      rewardedInterstitialEnabled = false,
      pointsEnabled = true,
      emergencyFreeCreationMode = false,
      walletCap = 20,
      interstitialCooldownSeconds = 180,
      rapidCompletionWindowSeconds = 60,
      interstitialSessionCap = 3;

  factory MonetizationConfig.fromJson(Map<String, dynamic> json) =>
      MonetizationConfig(
        adsEnabled: json['ads_enabled'] as bool? ?? false,
        nativeAdsEnabled: json['native_ads_enabled'] as bool? ?? false,
        interstitialAdsEnabled:
            json['interstitial_ads_enabled'] as bool? ?? false,
        rewardedAdsEnabled: json['rewarded_ads_enabled'] as bool? ?? false,
        rewardedInterstitialEnabled:
            json['rewarded_interstitial_enabled'] as bool? ?? false,
        pointsEnabled: json['points_enabled'] as bool? ?? true,
        emergencyFreeCreationMode:
            json['emergency_free_creation_mode'] as bool? ?? false,
        walletCap: json['wallet_cap'] as int? ?? 20,
        interstitialCooldownSeconds:
            json['interstitial_cooldown_seconds'] as int? ?? 180,
        rapidCompletionWindowSeconds:
            json['rapid_completion_window_seconds'] as int? ?? 60,
        interstitialSessionCap: json['interstitial_session_cap'] as int? ?? 3,
      );

  final bool adsEnabled;
  final bool nativeAdsEnabled;
  final bool interstitialAdsEnabled;
  final bool rewardedAdsEnabled;
  final bool rewardedInterstitialEnabled;
  final bool pointsEnabled;
  final bool emergencyFreeCreationMode;
  final int walletCap;
  final int interstitialCooldownSeconds;
  final int rapidCompletionWindowSeconds;
  final int interstitialSessionCap;

  bool get creationIsFree => !pointsEnabled || emergencyFreeCreationMode;
}

class RewardClaimRequest {
  const RewardClaimRequest({
    required this.claimId,
    required this.userId,
    required this.rewardAmount,
  });

  factory RewardClaimRequest.fromJson(Map<String, dynamic> json) =>
      RewardClaimRequest(
        claimId: json['claim_id'] as String,
        userId: json['user_id'] as String,
        rewardAmount: json['reward_amount'] as int,
      );

  final String claimId;
  final String userId;
  final int rewardAmount;
}

class PendingRewardClaim {
  const PendingRewardClaim({
    required this.claimId,
    required this.rewardAmount,
    required this.expiresAt,
  });

  factory PendingRewardClaim.fromJson(Map<String, dynamic> json) =>
      PendingRewardClaim(
        claimId: json['claim_id'] as String,
        rewardAmount: json['reward_amount'] as int? ?? 0,
        expiresAt:
            DateTime.tryParse(json['expires_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  final String claimId;
  final int rewardAmount;
  final DateTime expiresAt;
}

class PointDebitResult {
  const PointDebitResult({
    required this.balance,
    required this.charged,
    required this.alreadyProcessed,
    this.asset,
    this.plan,
    this.metadata,
  });

  factory PointDebitResult.fromJson(Map<String, dynamic> json) =>
      PointDebitResult(
        balance: json['balance'] as int? ?? 0,
        charged: json['charged'] as int? ?? 0,
        alreadyProcessed: json['already_processed'] as bool? ?? false,
        asset: json['asset'] is Map
            ? Map<String, dynamic>.from(json['asset'] as Map)
            : null,
        plan: json['plan'] is Map
            ? Map<String, dynamic>.from(json['plan'] as Map)
            : null,
        metadata: json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : null,
      );

  final int balance;
  final int charged;
  final bool alreadyProcessed;
  final Map<String, dynamic>? asset;
  final Map<String, dynamic>? plan;
  final Map<String, dynamic>? metadata;
}

class ChargedOperationStatusResult {
  const ChargedOperationStatusResult({
    required this.status,
    required this.capabilityVersion,
    this.charged,
    this.balance,
    this.entityType,
    this.entityId,
    this.asset,
    this.plan,
    this.metadata,
  });

  final String status;
  final String capabilityVersion;
  final int? charged;
  final int? balance;
  final String? entityType;
  final String? entityId;
  final Map<String, dynamic>? asset;
  final Map<String, dynamic>? plan;
  final Map<String, dynamic>? metadata;

  factory ChargedOperationStatusResult.fromJson(Map<String, dynamic> json) {
    return ChargedOperationStatusResult(
      status: json['status'] as String? ?? 'not_found',
      capabilityVersion: json['capability_version'] as String? ?? '1.0.0',
      charged: json['charged'] as int?,
      balance: json['balance'] as int?,
      entityType: json['entity_type'] as String?,
      entityId: json['entity_id'] as String?,
      asset: json['asset'] != null
          ? Map<String, dynamic>.from(json['asset'] as Map)
          : null,
      plan: json['plan'] != null
          ? Map<String, dynamic>.from(json['plan'] as Map)
          : null,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
    );
  }
}

class InsufficientPointsException implements Exception {
  const InsufficientPointsException({required this.balance});

  final int balance;

  @override
  String toString() => 'INSUFFICIENT_POINTS';
}

abstract class MonetizationRepository {
  const MonetizationRepository();

  String? get currentUserId => null;

  Stream<PointWallet?> watchWallet(String userId) => Stream.value(null);

  Stream<MonetizationConfig> watchConfig() =>
      Stream.value(const MonetizationConfig.failClosed());

  Future<List<PendingRewardClaim>> fetchPendingRewardClaims(String userId) =>
      Future.value(const []);

  Future<PointDebitResult> createAsset(Map<String, dynamic> operation) =>
      Future.error(UnsupportedError('Asset point debit is unavailable.'));

  Future<PointDebitResult> createTask(Map<String, dynamic> operation) =>
      Future.error(UnsupportedError('Task point debit is unavailable.'));

  Future<ChargedOperationStatusResult> getChargedOperationStatus(
    String operationId, {
    String? requestHash,
  }) =>
      Future.error(UnsupportedError('Operation status lookup is unavailable.'));

  Future<List<Map<String, dynamic>>> listTransactions() async => const [];

  Future<RewardClaimRequest> createRewardClaim(
    RewardAdType type, {
    String? timeZone,
  }) => Future.error(UnsupportedError('Reward claims are unavailable.'));

  Future<void> recordEvent(
    String name, [
    Map<String, dynamic> properties = const {},
  ]) async {}
}

class SupabaseMonetizationRepository extends MonetizationRepository {
  const SupabaseMonetizationRepository(this.client);

  final SupabaseClient client;

  @override
  String? get currentUserId => client.auth.currentUser?.id;

  @override
  Stream<PointWallet?> watchWallet(String userId) {
    return client
        .from('point_wallets')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', userId)
        .map((rows) => rows.isEmpty ? null : PointWallet.fromJson(rows.single));
  }

  @override
  Stream<MonetizationConfig> watchConfig() {
    return client
        .from('monetization_config')
        .stream(primaryKey: ['singleton'])
        .eq('singleton', true)
        .map(
          (rows) => rows.isEmpty
              ? const MonetizationConfig.failClosed()
              : MonetizationConfig.fromJson(rows.single),
        );
  }

  @override
  Future<List<PendingRewardClaim>> fetchPendingRewardClaims(
    String userId,
  ) async {
    final rows = await client
        .from('reward_claim_requests')
        .select(
          'claim_id,user_id,reward_type,ad_unit_id,reward_amount,status,'
          'reward_day,expires_at,created_at,processed_at,rejection_reason',
        )
        .eq('user_id', userId)
        .eq('status', 'pending')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(10);
    return [
      for (final row in rows)
        PendingRewardClaim.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  Future<PointDebitResult> createAsset(Map<String, dynamic> operation) async {
    return _createWithPointDebit('create_asset_with_point_debit', operation);
  }

  @override
  Future<PointDebitResult> createTask(Map<String, dynamic> operation) async {
    return _createWithPointDebit('create_task_with_point_debit', operation);
  }

  @override
  Future<ChargedOperationStatusResult> getChargedOperationStatus(
    String operationId, {
    String? requestHash,
  }) async {
    final data = await client.rpc<Map<String, dynamic>>(
      'get_charged_operation_status',
      params: {'p_operation_id': operationId, 'p_request_hash': ?requestHash},
    );
    return ChargedOperationStatusResult.fromJson(data);
  }

  Future<PointDebitResult> _createWithPointDebit(
    String functionName,
    Map<String, dynamic> operation,
  ) async {
    late final Map<String, dynamic> data;
    try {
      data = await client.rpc<Map<String, dynamic>>(
        functionName,
        params: {'p_operation': operation},
      );
    } on PostgrestException catch (error) {
      // Compatibility with the immediately previous backend. Build 44 returns
      // this expected business state as HTTP 200 to avoid warning/error noise.
      if (error.message == 'INSUFFICIENT_POINTS') {
        throw const InsufficientPointsException(balance: 0);
      }
      rethrow;
    }
    if (data['status'] == 'insufficient_points') {
      throw InsufficientPointsException(balance: data['balance'] as int? ?? 0);
    }
    return PointDebitResult.fromJson(data);
  }

  @override
  Future<List<Map<String, dynamic>>> listTransactions() async {
    final rows = await client
        .from('point_transactions')
        .select('amount,balance_after,transaction_type,reference_id,created_at')
        .order('created_at', ascending: false)
        .limit(50);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  @override
  Future<RewardClaimRequest> createRewardClaim(
    RewardAdType type, {
    String? timeZone,
  }) async {
    final data = await client.rpc<Map<String, dynamic>>(
      'create_reward_claim_request',
      params: {
        'p_reward_type': switch (type) {
          RewardAdType.rewardedAd => 'rewarded_ad',
          RewardAdType.rewardedInterstitial => 'rewarded_interstitial',
        },
        'p_time_zone': timeZone,
      },
    );
    return RewardClaimRequest.fromJson(data);
  }

  @override
  Future<void> recordEvent(
    String name, [
    Map<String, dynamic> properties = const {},
  ]) async {
    try {
      await client.rpc<void>(
        'record_monetization_event',
        params: {'p_event_name': name, 'p_properties': properties},
      );
    } on Object catch (error) {
      AppLogger.warning('monetization_event_failed', error: error);
    }
  }
}

final monetizationRepositoryProvider = Provider<MonetizationRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseMonetizationRepository(client);
});

final pointWalletProvider = StreamProvider<PointWallet?>((ref) {
  ref.watch(authSessionProvider);
  final repository = ref.watch(monetizationRepositoryProvider);
  final userId = repository?.currentUserId;
  if (repository == null || userId == null) return Stream.value(null);
  return repository.watchWallet(userId);
});

final monetizationConfigProvider = StreamProvider<MonetizationConfig>((ref) {
  final repository = ref.watch(monetizationRepositoryProvider);
  if (repository == null) {
    return Stream.value(const MonetizationConfig.failClosed());
  }
  return repository.watchConfig();
});

final pendingRewardClaimsProvider = FutureProvider<List<PendingRewardClaim>>((
  ref,
) async {
  ref.watch(authSessionProvider);
  final repository = ref.watch(monetizationRepositoryProvider);
  final userId = repository?.currentUserId;
  if (repository == null || userId == null) return const [];
  return repository.fetchPendingRewardClaims(userId);
});

class ConsentSnapshot {
  const ConsentSnapshot({
    required this.canRequestAds,
    required this.privacyOptionsRequired,
    required this.updated,
  });

  const ConsentSnapshot.initial()
    : canRequestAds = false,
      privacyOptionsRequired = false,
      updated = false;

  final bool canRequestAds;
  final bool privacyOptionsRequired;
  final bool updated;
}

class OwntendConsentService {
  OwntendConsentService({ConsentRequestParameters? requestParameters})
    : _requestParameters = requestParameters ?? ConsentRequestParameters();

  final ConsentRequestParameters _requestParameters;
  final _states = StreamController<ConsentSnapshot>.broadcast();
  ConsentSnapshot _current = const ConsentSnapshot.initial();
  bool _started = false;

  Stream<ConsentSnapshot> get states async* {
    yield _current;
    yield* _states.stream;
  }

  Future<void> initialize() async {
    if (_started || !_supportsMobileAds) return;
    _started = true;
    final completion = Completer<void>();
    Future<void> finishRefresh() async {
      try {
        await _refresh();
      } on Object catch (error) {
        AppLogger.warning('ad_consent_refresh', error: error);
        _current = const ConsentSnapshot.initial();
        _states.add(_current);
      } finally {
        if (!completion.isCompleted) completion.complete();
      }
    }

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        _requestParameters,
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((error) {
              if (error != null) {
                AppLogger.warning('ad_consent_form', error: error);
              }
            });
          } on Object catch (error) {
            AppLogger.warning('ad_consent_form', error: error);
          } finally {
            await finishRefresh();
          }
        },
        (error) async {
          AppLogger.warning('ad_consent_update', error: error);
          await finishRefresh();
        },
      );
    } on Object catch (error) {
      AppLogger.warning('ad_consent_update', error: error);
      await finishRefresh();
    }
    try {
      await completion.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () async {
          AppLogger.warning('ad_consent_timeout');
          await finishRefresh();
        },
      );
    } catch (_) {}
  }

  Future<void> showPrivacyOptions() async {
    if (!_supportsMobileAds) return;
    await ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) AppLogger.warning('ad_privacy_options', error: error);
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final canRequestAds = await ConsentInformation.instance.canRequestAds();
    final privacyStatus = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();
    _current = ConsentSnapshot(
      canRequestAds: canRequestAds,
      privacyOptionsRequired:
          privacyStatus == PrivacyOptionsRequirementStatus.required,
      updated: true,
    );
    _states.add(_current);
  }

  void dispose() => _states.close();
}

final owntendAdsProvider = Provider<OwntendAdsService>((ref) {
  final config = ref.watch(appConfigProvider);
  final repository = ref.watch(monetizationRepositoryProvider);
  final service = OwntendAdsService(
    useProductionUnits: config.environment == AppEnvironment.prod,
    testDeviceIds: config.adMobTestDeviceIds,
    adInspectorEnabled: config.environment != AppEnvironment.prod,
    repository: repository,
  );
  ref.onDispose(service.dispose);
  return service;
});

final consentServiceProvider = Provider<OwntendConsentService>((ref) {
  final config = ref.watch(appConfigProvider);
  final service = OwntendConsentService(
    requestParameters: ConsentRequestParameters(
      consentDebugSettings: consentDebugSettingsForAppConfig(config),
    ),
  );
  ref.onDispose(service.dispose);
  return service;
});

final consentSnapshotProvider = StreamProvider<ConsentSnapshot>((ref) {
  return ref.watch(consentServiceProvider).states;
});

class MonetizationBootstrap extends ConsumerStatefulWidget {
  const MonetizationBootstrap({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<MonetizationBootstrap> createState() =>
      _MonetizationBootstrapState();
}

class _MonetizationBootstrapState extends ConsumerState<MonetizationBootstrap>
    with WidgetsBindingObserver {
  AppLifecycleState _lifecycleState = AppLifecycleState.detached;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.detached;
    ref.listenManual(monetizationConfigProvider, (_, _) => _applyRuntime());
    ref.listenManual(consentSnapshotProvider, (_, _) => _applyRuntime());
    scheduleMicrotask(() async {
      await ref.read(completionAdCoordinatorProvider).initializeSession();
      await ref.read(consentServiceProvider).initialize();
      _applyRuntime();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _applyRuntime();
  }

  void _applyRuntime() {
    if (!mounted) return;
    final config =
        ref.read(monetizationConfigProvider).value ??
        const MonetizationConfig.failClosed();
    final consent =
        ref.read(consentSnapshotProvider).value ??
        const ConsentSnapshot.initial();
    unawaited(
      ref
          .read(owntendAdsProvider)
          .applyEligibility(
            AdRuntimeEligibility(
              platformSupported: _supportsMobileAds,
              appResumed: _lifecycleState == AppLifecycleState.resumed,
              consentUpdated: consent.updated,
              canRequestAds: consent.canRequestAds,
              adsEnabled: config.adsEnabled,
              nativeAdsEnabled: config.nativeAdsEnabled,
              interstitialAdsEnabled: config.interstitialAdsEnabled,
              rewardedAdsEnabled: config.rewardedAdsEnabled,
              rewardedInterstitialEnabled: config.rewardedInterstitialEnabled,
            ),
          ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class OwntendAdUnits {
  const OwntendAdUnits({required this.production});

  final bool production;

  String native(String placement) {
    if (!production) return 'ca-app-pub-3940256099942544/2247696110';
    return switch (placement) {
      'home' => 'ca-app-pub-5274007212820203/8393243294',
      'assets' ||
      'room_detail' ||
      'thing_detail' ||
      'task_detail' ||
      'maintenance' ||
      'calendar' ||
      'more' ||
      'search' ||
      'notifications' ||
      'statistics' ||
      'account' ||
      'backup' ||
      'trash' ||
      'settings' ||
      'permission_setup' => 'ca-app-pub-5274007212820203/7543196051',
      _ => throw ArgumentError.value(placement, 'placement'),
    };
  }

  String get interstitial => production
      ? 'ca-app-pub-5274007212820203/3851363056'
      : 'ca-app-pub-3940256099942544/1033173712';

  String get rewarded => production
      ? 'ca-app-pub-5274007212820203/4541482404'
      : 'ca-app-pub-3940256099942544/5224354917';

  String get rewardedInterstitial => production
      ? 'ca-app-pub-5274007212820203/7295784043'
      : 'ca-app-pub-3940256099942544/5354046379';
}

class OwntendAdsService {
  OwntendAdsService({
    required this.useProductionUnits,
    required this.testDeviceIds,
    required this.adInspectorEnabled,
    required this.repository,
    this.timeZoneResolver = resolveSystemRewardTimeZone,
    DateTime Function()? now,
    this._retryPolicy = const AdRetryPolicy(),
    double Function()? jitterUnit,
    Timer Function(Duration, void Function())? timerFactory,
  }) : units = OwntendAdUnits(production: useProductionUnits),
       now = now ?? DateTime.now,
       _jitterUnit = jitterUnit ?? _defaultAdJitter,
       _timerFactory = timerFactory ?? _defaultAdTimer;

  final bool useProductionUnits;
  final List<String> testDeviceIds;
  final bool adInspectorEnabled;
  final MonetizationRepository? repository;
  final Future<String?> Function(String? fallback) timeZoneResolver;
  final DateTime Function() now;
  final OwntendAdUnits units;
  final AdRetryPolicy _retryPolicy;
  final double Function() _jitterUnit;
  final Timer Function(Duration, void Function()) _timerFactory;
  final AdRuntimeController _runtime = AdRuntimeController();
  final FullScreenAdGate _fullScreenGate = FullScreenAdGate();
  final StreamController<int> _states = StreamController<int>.broadcast();

  bool _initialized = false;
  bool _disposed = false;
  Future<void>? _initialization;
  int? _preloadingGeneration;
  int? _interstitialLoadGeneration;
  int? _rewardedLoadGeneration;
  int? _rewardedInterstitialLoadGeneration;
  int _interstitialFailures = 0;
  int _rewardedFailures = 0;
  int _rewardedInterstitialFailures = 0;
  Timer? _interstitialRetry;
  Timer? _rewardedRetry;
  Timer? _rewardedInterstitialRetry;
  CachedAd<InterstitialAd>? _interstitial;
  CachedAd<RewardedAd>? _rewarded;
  CachedAd<RewardedInterstitialAd>? _rewardedInterstitial;

  bool get initialized => _initialized;
  int get runtimeGeneration => _runtime.generation;
  AdRuntimeEligibility get eligibility => _runtime.current;
  Stream<int> get states => _states.stream;
  bool allows(AdFormat format) =>
      !_disposed && _initialized && _runtime.current.allows(format);
  bool get canOpenAdInspector =>
      !_disposed && _initialized && adInspectorEnabled && _supportsMobileAds;

  Future<void> applyEligibility(AdRuntimeEligibility eligibility) async {
    if (_disposed) return;
    final transition = _runtime.apply(eligibility);
    if (!transition.changed) return;
    _notifyState();

    _cancelRetries();
    _interstitialFailures = 0;
    _rewardedFailures = 0;
    _rewardedInterstitialFailures = 0;
    _preloadingGeneration = null;
    _interstitialLoadGeneration = null;
    _rewardedLoadGeneration = null;
    _rewardedInterstitialLoadGeneration = null;
    _disposeBlockedCaches();

    if (!eligibility.sdkEligible) return;
    try {
      await initialize();
    } on Object catch (error) {
      AppLogger.warning('ad_sdk_initialize', error: error);
      return;
    }
    if (_disposed || transition.generation != _runtime.generation) return;
    _notifyState();
    await preloadFullScreenAds();
  }

  Future<void> initialize() async {
    if (_initialized || _disposed || !_supportsMobileAds) return;
    final existing = _initialization;
    if (existing != null) {
      await existing;
      return;
    }
    late final Future<void> attempt;
    attempt = _initializeSdk();
    _initialization = attempt;
    try {
      await attempt;
    } on Object {
      if (identical(_initialization, attempt)) _initialization = null;
      rethrow;
    }
  }

  Future<void> _initializeSdk() async {
    if (useProductionUnits && testDeviceIds.isNotEmpty) {
      throw StateError(
        'Production ads cannot initialize with test devices configured.',
      );
    }
    await MobileAds.instance.updateRequestConfiguration(
      adRequestConfiguration(testDeviceIds: testDeviceIds),
    );
    await MobileAds.instance.initialize();
    if (!_disposed) _initialized = true;
  }

  Future<AdInspectorOpenResult> openAdInspector() async {
    if (!canOpenAdInspector) return AdInspectorOpenResult.unavailable;
    try {
      MobileAds.instance.openAdInspector((error) {
        if (error != null) {
          AppLogger.warning(
            'ad_inspector_closed',
            fields: {
              'code': error.code,
              'domain': error.domain,
              'message': error.message,
            },
          );
        } else {
          AppLogger.info('ad_inspector_closed');
        }
      });
      return AdInspectorOpenResult.opened;
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'ad_inspector_open',
        error: error,
        stackTrace: stackTrace,
      );
      return AdInspectorOpenResult.failed;
    }
  }

  Future<void> preloadFullScreenAds() async {
    if (!_initialized || _disposed) return;
    final generation = _runtime.generation;
    if (_preloadingGeneration == generation) return;
    _preloadingGeneration = generation;
    try {
      await Future.wait([
        if (_runtime.current.allows(AdFormat.interstitial)) _loadInterstitial(),
        if (_runtime.current.allows(AdFormat.rewarded)) _loadRewarded(),
        if (_runtime.current.allows(AdFormat.rewardedInterstitial))
          _loadRewardedInterstitial(),
      ]);
    } finally {
      if (_preloadingGeneration == generation) {
        _preloadingGeneration = null;
      }
    }
  }

  Future<bool> showInterstitial({
    Map<String, dynamic> analyticsProperties = const {},
  }) async {
    if (!allows(AdFormat.interstitial)) return false;
    final fullScreenLease = _fullScreenGate.tryAcquire();
    if (fullScreenLease == null) return false;
    final ad = _takeFreshInterstitial();
    if (ad == null) {
      fullScreenLease.release();
      unawaited(_loadInterstitial());
      return false;
    }
    final completion = Completer<bool>();
    var finished = false;

    void finish(InterstitialAd finishedAd, bool shown) {
      if (finished) return;
      finished = true;
      finishedAd.dispose();
      fullScreenLease.release();
      if (!completion.isCompleted) completion.complete(shown);
      if (allows(AdFormat.interstitial)) unawaited(_loadInterstitial());
    }

    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdShowedFullScreenContent: (_) {
        AppLogger.info('ad_impression', fields: {'ad_type': 'interstitial'});
        unawaited(
          repository?.recordEvent('ad_interstitial_shown', analyticsProperties),
        );
      },
      onAdDismissedFullScreenContent: (shownAd) => finish(shownAd, true),
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        AppLogger.warning('interstitial_show', error: error);
        finish(failedAd, false);
      },
    );
    try {
      await ad.show();
    } on Object catch (error) {
      AppLogger.warning('interstitial_show', error: error);
      finish(ad, false);
    }
    return completion.future;
  }

  Future<RewardShowResult> showReward(
    RewardAdType type, {
    required String? timeZone,
    required String entryPoint,
  }) async {
    final format = type == RewardAdType.rewardedAd
        ? AdFormat.rewarded
        : AdFormat.rewardedInterstitial;
    if (!allows(format) || repository == null || !_hasFreshReward(type)) {
      _loadRewardType(type);
      return RewardShowResult.unavailable;
    }
    final fullScreenLease = _fullScreenGate.tryAcquire();
    if (fullScreenLease == null) return RewardShowResult.unavailable;
    final generation = _runtime.generation;

    RewardClaimRequest claim;
    try {
      final resolvedTimeZone = await timeZoneResolver(timeZone);
      claim = await repository!.createRewardClaim(
        type,
        timeZone: resolvedTimeZone,
      );
    } on Object {
      fullScreenLease.release();
      return RewardShowResult.rejected;
    }
    if (_disposed ||
        generation != _runtime.generation ||
        !allows(format) ||
        !_hasFreshReward(type)) {
      fullScreenLease.release();
      return RewardShowResult.unavailable;
    }

    final earned = Completer<bool>();
    final dismissed = Completer<void>();
    var failedToShow = false;
    var finished = false;
    var activeAdDisposed = false;
    void Function()? disposeActiveAd;

    void finish({required bool failed}) {
      if (finished) return;
      finished = true;
      if (failed) failedToShow = true;
      fullScreenLease.release();
      if (!earned.isCompleted && failed) earned.complete(false);
      if (!dismissed.isCompleted) dismissed.complete();
      if (allows(format)) _loadRewardType(type);
    }

    try {
      if (type == RewardAdType.rewardedAd) {
        final ad = _takeFreshRewarded();
        if (ad == null) {
          fullScreenLease.release();
          return RewardShowResult.unavailable;
        }
        disposeActiveAd = () {
          if (activeAdDisposed) return;
          activeAdDisposed = true;
          ad.dispose();
        };
        await ad.setServerSideOptions(
          ServerSideVerificationOptions(
            userId: claim.userId,
            customData: claim.claimId,
          ),
        );
        if (!rewardPresentationIsCurrent(
          disposed: _disposed,
          requestGeneration: generation,
          currentGeneration: _runtime.generation,
          formatAllowed: allows(format),
        )) {
          disposeActiveAd();
          finish(failed: true);
          return RewardShowResult.unavailable;
        }
        ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
          onAdDismissedFullScreenContent: (shownAd) {
            disposeActiveAd?.call();
            finish(failed: false);
          },
          onAdFailedToShowFullScreenContent: (failedAd, error) {
            AppLogger.warning('rewarded_show', error: error);
            disposeActiveAd?.call();
            finish(failed: true);
          },
        );
        await ad.show(
          onUserEarnedReward: (_, reward) {
            AppLogger.info(
              'ad_rewarded',
              fields: {'ad_type': 'rewarded', 'reward_amount': reward.amount},
            );
            if (!earned.isCompleted) earned.complete(true);
          },
        );
      } else {
        final ad = _takeFreshRewardedInterstitial();
        if (ad == null) {
          fullScreenLease.release();
          return RewardShowResult.unavailable;
        }
        disposeActiveAd = () {
          if (activeAdDisposed) return;
          activeAdDisposed = true;
          ad.dispose();
        };
        await ad.setServerSideOptions(
          ServerSideVerificationOptions(
            userId: claim.userId,
            customData: claim.claimId,
          ),
        );
        if (!rewardPresentationIsCurrent(
          disposed: _disposed,
          requestGeneration: generation,
          currentGeneration: _runtime.generation,
          formatAllowed: allows(format),
        )) {
          disposeActiveAd();
          finish(failed: true);
          return RewardShowResult.unavailable;
        }
        ad.fullScreenContentCallback =
            FullScreenContentCallback<RewardedInterstitialAd>(
              onAdDismissedFullScreenContent: (shownAd) {
                disposeActiveAd?.call();
                finish(failed: false);
              },
              onAdFailedToShowFullScreenContent: (failedAd, error) {
                AppLogger.warning('rewarded_interstitial_show', error: error);
                disposeActiveAd?.call();
                finish(failed: true);
              },
            );
        await ad.show(
          onUserEarnedReward: (_, reward) {
            AppLogger.info(
              'ad_rewarded',
              fields: {
                'ad_type': 'rewarded_interstitial',
                'reward_amount': reward.amount,
              },
            );
            if (!earned.isCompleted) earned.complete(true);
          },
        );
      }
    } on Object catch (error) {
      AppLogger.warning('reward_show', error: error);
      disposeActiveAd?.call();
      finish(failed: true);
    }

    await dismissed.future;
    final wasEarned = earned.isCompleted ? await earned.future : false;
    if (!wasEarned) {
      return failedToShow
          ? RewardShowResult.unavailable
          : RewardShowResult.dismissed;
    }
    unawaited(
      repository!.recordEvent('ad_rewarded_watched', {
        'reward_amount': claim.rewardAmount,
        'entry_point': entryPoint,
        'verification': 'server_pending',
      }),
    );
    AppLogger.info(
      'ad_show_completed',
      fields: {
        'ad_type': type.name,
        'entry_point': entryPoint,
        'verification': 'server_pending',
      },
    );
    return RewardShowResult.shownAwaitingServerVerification;
  }

  Future<void> _loadInterstitial({bool retry = false}) async {
    _discardStaleInterstitial();
    if (!allows(AdFormat.interstitial) ||
        _interstitial != null ||
        _interstitialLoadGeneration != null ||
        (!retry && _interstitialRetry?.isActive == true)) {
      return;
    }
    _interstitialRetry?.cancel();
    _interstitialRetry = null;
    final generation = _runtime.generation;
    _interstitialLoadGeneration = generation;
    final completion = Completer<void>();
    AppLogger.info('ad_load_requested', fields: {'ad_type': 'interstitial'});
    try {
      await InterstitialAd.load(
        adUnitId: units.interstitial,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (_interstitialLoadGeneration == generation) {
              _interstitialLoadGeneration = null;
            }
            if (_accepts(generation, AdFormat.interstitial)) {
              _interstitialFailures = 0;
              _interstitial = CachedAd(value: ad, loadedAt: now());
              AppLogger.info('ad_loaded', fields: {'ad_type': 'interstitial'});
            } else {
              ad.dispose();
            }
            if (!completion.isCompleted) completion.complete();
          },
          onAdFailedToLoad: (error) {
            if (_interstitialLoadGeneration == generation) {
              _interstitialLoadGeneration = null;
            }
            AppLogger.warning(
              'ad_load_failed',
              error: error,
              fields: {'ad_type': 'interstitial'},
            );
            _scheduleInterstitialRetry(
              generation,
              classifyAdLoadFailure(code: error.code, domain: error.domain),
            );
            if (!completion.isCompleted) completion.complete();
          },
        ),
      );
    } on Object catch (error) {
      if (_interstitialLoadGeneration == generation) {
        _interstitialLoadGeneration = null;
      }
      AppLogger.warning(
        'ad_load_failed',
        error: error,
        fields: {'ad_type': 'interstitial'},
      );
      _scheduleInterstitialRetry(generation, AdLoadFailureKind.unknown);
      if (!completion.isCompleted) completion.complete();
    }
    await completion.future;
  }

  Future<void> _loadRewarded({bool retry = false}) async {
    _discardStaleRewarded();
    if (!allows(AdFormat.rewarded) ||
        _rewarded != null ||
        _rewardedLoadGeneration != null ||
        (!retry && _rewardedRetry?.isActive == true)) {
      return;
    }
    _rewardedRetry?.cancel();
    _rewardedRetry = null;
    final generation = _runtime.generation;
    _rewardedLoadGeneration = generation;
    final completion = Completer<void>();
    AppLogger.info('ad_load_requested', fields: {'ad_type': 'rewarded'});
    try {
      await RewardedAd.load(
        adUnitId: units.rewarded,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (_rewardedLoadGeneration == generation) {
              _rewardedLoadGeneration = null;
            }
            if (_accepts(generation, AdFormat.rewarded)) {
              _rewardedFailures = 0;
              _rewarded = CachedAd(value: ad, loadedAt: now());
              AppLogger.info('ad_loaded', fields: {'ad_type': 'rewarded'});
            } else {
              ad.dispose();
            }
            if (!completion.isCompleted) completion.complete();
          },
          onAdFailedToLoad: (error) {
            if (_rewardedLoadGeneration == generation) {
              _rewardedLoadGeneration = null;
            }
            AppLogger.warning(
              'ad_load_failed',
              error: error,
              fields: {'ad_type': 'rewarded'},
            );
            _scheduleRewardedRetry(
              generation,
              classifyAdLoadFailure(code: error.code, domain: error.domain),
            );
            if (!completion.isCompleted) completion.complete();
          },
        ),
      );
    } on Object catch (error) {
      if (_rewardedLoadGeneration == generation) {
        _rewardedLoadGeneration = null;
      }
      AppLogger.warning(
        'ad_load_failed',
        error: error,
        fields: {'ad_type': 'rewarded'},
      );
      _scheduleRewardedRetry(generation, AdLoadFailureKind.unknown);
      if (!completion.isCompleted) completion.complete();
    }
    await completion.future;
  }

  Future<void> _loadRewardedInterstitial({bool retry = false}) async {
    _discardStaleRewardedInterstitial();
    if (!allows(AdFormat.rewardedInterstitial) ||
        _rewardedInterstitial != null ||
        _rewardedInterstitialLoadGeneration != null ||
        (!retry && _rewardedInterstitialRetry?.isActive == true)) {
      return;
    }
    _rewardedInterstitialRetry?.cancel();
    _rewardedInterstitialRetry = null;
    final generation = _runtime.generation;
    _rewardedInterstitialLoadGeneration = generation;
    final completion = Completer<void>();
    AppLogger.info(
      'ad_load_requested',
      fields: {'ad_type': 'rewarded_interstitial'},
    );
    try {
      await RewardedInterstitialAd.load(
        adUnitId: units.rewardedInterstitial,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (_rewardedInterstitialLoadGeneration == generation) {
              _rewardedInterstitialLoadGeneration = null;
            }
            if (_accepts(generation, AdFormat.rewardedInterstitial)) {
              _rewardedInterstitialFailures = 0;
              _rewardedInterstitial = CachedAd(value: ad, loadedAt: now());
              AppLogger.info(
                'ad_loaded',
                fields: {'ad_type': 'rewarded_interstitial'},
              );
            } else {
              ad.dispose();
            }
            if (!completion.isCompleted) completion.complete();
          },
          onAdFailedToLoad: (error) {
            if (_rewardedInterstitialLoadGeneration == generation) {
              _rewardedInterstitialLoadGeneration = null;
            }
            AppLogger.warning(
              'ad_load_failed',
              error: error,
              fields: {'ad_type': 'rewarded_interstitial'},
            );
            _scheduleRewardedInterstitialRetry(
              generation,
              classifyAdLoadFailure(code: error.code, domain: error.domain),
            );
            if (!completion.isCompleted) completion.complete();
          },
        ),
      );
    } on Object catch (error) {
      if (_rewardedInterstitialLoadGeneration == generation) {
        _rewardedInterstitialLoadGeneration = null;
      }
      AppLogger.warning(
        'ad_load_failed',
        error: error,
        fields: {'ad_type': 'rewarded_interstitial'},
      );
      _scheduleRewardedInterstitialRetry(generation, AdLoadFailureKind.unknown);
      if (!completion.isCompleted) completion.complete();
    }
    await completion.future;
  }

  bool _accepts(int generation, AdFormat format) =>
      !_disposed && generation == _runtime.generation && allows(format);

  void _scheduleInterstitialRetry(int generation, AdLoadFailureKind failure) {
    if (!_accepts(generation, AdFormat.interstitial) ||
        _interstitialRetry?.isActive == true) {
      return;
    }
    _interstitialFailures++;
    final decision = _retryPolicy.decide(
      failure: failure,
      failedAttempt: _interstitialFailures,
      jitterUnit: _jitterUnit(),
    );
    if (!decision.shouldRetry) return;
    _interstitialRetry = _timerFactory(decision.delay, () {
      _interstitialRetry = null;
      if (_accepts(generation, AdFormat.interstitial)) {
        unawaited(_loadInterstitial(retry: true));
      }
    });
  }

  void _scheduleRewardedRetry(int generation, AdLoadFailureKind failure) {
    if (!_accepts(generation, AdFormat.rewarded) ||
        _rewardedRetry?.isActive == true) {
      return;
    }
    _rewardedFailures++;
    final decision = _retryPolicy.decide(
      failure: failure,
      failedAttempt: _rewardedFailures,
      jitterUnit: _jitterUnit(),
    );
    if (!decision.shouldRetry) return;
    _rewardedRetry = _timerFactory(decision.delay, () {
      _rewardedRetry = null;
      if (_accepts(generation, AdFormat.rewarded)) {
        unawaited(_loadRewarded(retry: true));
      }
    });
  }

  void _scheduleRewardedInterstitialRetry(
    int generation,
    AdLoadFailureKind failure,
  ) {
    if (!_accepts(generation, AdFormat.rewardedInterstitial) ||
        _rewardedInterstitialRetry?.isActive == true) {
      return;
    }
    _rewardedInterstitialFailures++;
    final decision = _retryPolicy.decide(
      failure: failure,
      failedAttempt: _rewardedInterstitialFailures,
      jitterUnit: _jitterUnit(),
    );
    if (!decision.shouldRetry) return;
    _rewardedInterstitialRetry = _timerFactory(decision.delay, () {
      _rewardedInterstitialRetry = null;
      if (_accepts(generation, AdFormat.rewardedInterstitial)) {
        unawaited(_loadRewardedInterstitial(retry: true));
      }
    });
  }

  void _loadRewardType(RewardAdType type) {
    if (type == RewardAdType.rewardedAd) {
      unawaited(_loadRewarded());
    } else {
      unawaited(_loadRewardedInterstitial());
    }
  }

  bool _hasFreshReward(RewardAdType type) {
    if (type == RewardAdType.rewardedAd) {
      _discardStaleRewarded();
      return _rewarded != null;
    }
    _discardStaleRewardedInterstitial();
    return _rewardedInterstitial != null;
  }

  InterstitialAd? _takeFreshInterstitial() {
    _discardStaleInterstitial();
    final cached = _interstitial;
    _interstitial = null;
    return cached?.value;
  }

  RewardedAd? _takeFreshRewarded() {
    _discardStaleRewarded();
    final cached = _rewarded;
    _rewarded = null;
    return cached?.value;
  }

  RewardedInterstitialAd? _takeFreshRewardedInterstitial() {
    _discardStaleRewardedInterstitial();
    final cached = _rewardedInterstitial;
    _rewardedInterstitial = null;
    return cached?.value;
  }

  void _discardStaleInterstitial() {
    final cached = _interstitial;
    if (cached != null && !cached.isFresh(now())) {
      cached.value.dispose();
      _interstitial = null;
    }
  }

  void _discardStaleRewarded() {
    final cached = _rewarded;
    if (cached != null && !cached.isFresh(now())) {
      cached.value.dispose();
      _rewarded = null;
    }
  }

  void _discardStaleRewardedInterstitial() {
    final cached = _rewardedInterstitial;
    if (cached != null && !cached.isFresh(now())) {
      cached.value.dispose();
      _rewardedInterstitial = null;
    }
  }

  void _disposeBlockedCaches() {
    if (!_runtime.current.allows(AdFormat.interstitial)) {
      _interstitial?.value.dispose();
      _interstitial = null;
    }
    if (!_runtime.current.allows(AdFormat.rewarded)) {
      _rewarded?.value.dispose();
      _rewarded = null;
    }
    if (!_runtime.current.allows(AdFormat.rewardedInterstitial)) {
      _rewardedInterstitial?.value.dispose();
      _rewardedInterstitial = null;
    }
  }

  void _cancelRetries() {
    _interstitialRetry?.cancel();
    _rewardedRetry?.cancel();
    _rewardedInterstitialRetry?.cancel();
    _interstitialRetry = null;
    _rewardedRetry = null;
    _rewardedInterstitialRetry = null;
  }

  void _notifyState() {
    if (!_disposed && !_states.isClosed) _states.add(_runtime.generation);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _runtime.apply(const AdRuntimeEligibility.blocked());
    _cancelRetries();
    _interstitial?.value.dispose();
    _rewarded?.value.dispose();
    _rewardedInterstitial?.value.dispose();
    _interstitial = null;
    _rewarded = null;
    _rewardedInterstitial = null;
    unawaited(_states.close());
  }
}

class InterstitialEligibilityPolicy {
  InterstitialEligibilityPolicy({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  DateTime? _lastCompletion;
  DateTime? _lastShown;
  int _shownThisSession = 0;
  bool firstEverSession = true;

  bool registerCompletionAndCanShow({
    required MonetizationConfig config,
    required bool keyboardVisible,
    required bool modalActive,
  }) {
    final now = _now();
    final rapid =
        _lastCompletion != null &&
        now.difference(_lastCompletion!).inSeconds <
            config.rapidCompletionWindowSeconds;
    _lastCompletion = now;
    if (firstEverSession ||
        rapid ||
        keyboardVisible ||
        modalActive ||
        !config.adsEnabled ||
        !config.interstitialAdsEnabled ||
        _shownThisSession >= config.interstitialSessionCap) {
      return false;
    }
    if (_lastShown != null &&
        now.difference(_lastShown!).inSeconds <
            config.interstitialCooldownSeconds) {
      return false;
    }
    return true;
  }

  void markShown() {
    _lastShown = _now();
    _shownThisSession++;
  }

  int get nextSessionAdCount => _shownThisSession + 1;
}

class CompletionAdCoordinator {
  CompletionAdCoordinator(this.ads, this.policy);

  final OwntendAdsService ads;
  final InterstitialEligibilityPolicy policy;

  Future<void> initializeSession() async {
    if (!_supportsMobileAds) return;
    const storage = FlutterSecureStorage();
    final prior = await storage.read(key: _firstSessionStorageKey);
    policy.firstEverSession = prior == null;
    if (prior == null) {
      await storage.write(key: _firstSessionStorageKey, value: 'true');
    }
  }

  Future<bool> onTaskCompleted({
    required MonetizationConfig config,
    required bool keyboardVisible,
    required bool modalActive,
  }) async {
    if (!policy.registerCompletionAndCanShow(
      config: config,
      keyboardVisible: keyboardVisible,
      modalActive: modalActive,
    )) {
      return false;
    }
    final shown = await ads.showInterstitial(
      analyticsProperties: {
        'cooldown_remaining_sec': 0,
        'session_ad_count': policy.nextSessionAdCount,
      },
    );
    if (shown) policy.markShown();
    return shown;
  }
}

final completionAdCoordinatorProvider = Provider<CompletionAdCoordinator>((
  ref,
) {
  return CompletionAdCoordinator(
    ref.watch(owntendAdsProvider),
    InterstitialEligibilityPolicy(),
  );
});

class HkNativeAdCard extends ConsumerStatefulWidget {
  const HkNativeAdCard({
    required this.placement,
    this.enabledOverride,
    super.key,
  });

  final String placement;
  final bool? enabledOverride;

  @override
  ConsumerState<HkNativeAdCard> createState() => _HkNativeAdCardState();
}

class _HkNativeAdCardState extends ConsumerState<HkNativeAdCard> {
  StreamSubscription<int>? _adsSubscription;
  OwntendAdsService? _ads;
  AdLease<NativeAd>? _displayLease;
  AdLease<NativeAd>? _pendingLease;
  DateTime? _loadedAt;
  int? _pendingRuntimeGeneration;
  int _requestGeneration = 0;
  bool _enabled = false;
  bool _failed = false;
  bool _syncScheduled = false;
  int _loadFailures = 0;
  String? _themeIdentity;
  Timer? _expiryTimer;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    ref.listenManual(owntendAdsProvider, (_, next) => _bindAds(next));
    ref.listenManual(nativeAdPresentationDepthProvider, (_, _) {
      _scheduleSynchronize();
    });
    scheduleMicrotask(() => _bindAds(ref.read(owntendAdsProvider)));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleSynchronize();
  }

  @override
  void didUpdateWidget(covariant HkNativeAdCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placement != widget.placement ||
        oldWidget.enabledOverride != widget.enabledOverride) {
      _deactivate();
    }
    _scheduleSynchronize();
  }

  @override
  void dispose() {
    _requestGeneration++;
    _adsSubscription?.cancel();
    _expiryTimer?.cancel();
    _retryTimer?.cancel();
    _displayLease?.release();
    _pendingLease?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HkNativeAdSlotFrame(
      collapsed: !_enabled || _failed,
      bottomSpacing: HkSpacing.sm,
      child: _displayLease != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AdWidget(ad: _displayLease!.value),
            )
          : const HkNativeAdLoadingSkeleton(),
    );
  }

  void _bindAds(OwntendAdsService ads) {
    if (identical(_ads, ads)) return;
    _adsSubscription?.cancel();
    _ads = ads;
    _adsSubscription = ads.states.listen((_) => _scheduleSynchronize());
    _deactivate();
    _scheduleSynchronize();
  }

  void _scheduleSynchronize() {
    if (!mounted || _syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) _synchronize();
    });
  }

  void _synchronize() {
    final ads = _ads;
    if (ads == null) return;
    final routeIsCurrent = ModalRoute.isCurrentOf(context) ?? true;
    final presentationSuppressed =
        ref.read(nativeAdPresentationDepthProvider) > 0;
    final enabled = nativeAdPlacementEnabled(
      routeIsCurrent: routeIsCurrent,
      presentationSuppressed: presentationSuppressed,
      configEnabled: ads.eligibility.adsEnabled,
      consentGranted:
          ads.eligibility.consentUpdated && ads.eligibility.canRequestAds,
      adsInitialized: ads.allows(AdFormat.native),
      platformSupported: ads.eligibility.platformSupported,
      enabledOverride: widget.enabledOverride,
    );
    final palette = _nativePalette(Theme.of(context).colorScheme);
    final themeIdentity = palette.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join('|');

    if (!enabled) {
      _deactivate();
      return;
    }

    var needsReplacement =
        _themeIdentity != null && _themeIdentity != themeIdentity;
    if (_loadedAt case final loadedAt?) {
      needsReplacement =
          needsReplacement || ads.now().difference(loadedAt) >= kAdCacheMaxAge;
    }
    if (_pendingLease != null &&
        _pendingRuntimeGeneration != ads.runtimeGeneration) {
      needsReplacement = true;
    }
    if (needsReplacement) {
      _requestGeneration++;
      _expiryTimer?.cancel();
      _expiryTimer = null;
      _retryTimer?.cancel();
      _retryTimer = null;
      _displayLease?.release();
      _pendingLease?.release();
      _displayLease = null;
      _pendingLease = null;
      _loadedAt = null;
      _pendingRuntimeGeneration = null;
      _failed = false;
      _loadFailures = 0;
    }
    _themeIdentity = themeIdentity;
    if (!_enabled || needsReplacement) {
      setState(() => _enabled = true);
    }
    if (_displayLease == null &&
        _pendingLease == null &&
        _retryTimer?.isActive != true) {
      unawaited(_load(ads, themeIdentity, palette));
    }
  }

  Future<void> _load(
    OwntendAdsService ads,
    String themeIdentity,
    Map<String, Object> palette,
  ) async {
    if (!mounted || !ads.allows(AdFormat.native)) return;
    final repository = ref.read(monetizationRepositoryProvider);
    final runtimeGeneration = ads.runtimeGeneration;
    final requestGeneration = ++_requestGeneration;
    late final NativeAd request;
    late final AdLease<NativeAd> lease;
    request = NativeAd(
      adUnitId: ads.units.native(widget.placement),
      factoryId: _nativeFactoryId,
      customOptions: {
        'schemaVersion': 2,
        'isDark': Theme.of(context).brightness == Brightness.dark,
        'placement': widget.placement,
        ...palette,
      },
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (loadedAd) {
          final currentRequest = identical(_pendingLease, lease);
          if (currentRequest) {
            _pendingLease = null;
            _pendingRuntimeGeneration = null;
          }
          if (!currentRequest ||
              !_requestIsCurrent(
                ads,
                runtimeGeneration,
                requestGeneration,
                themeIdentity,
              )) {
            lease.release();
            return;
          }
          _retryTimer?.cancel();
          _retryTimer = null;
          _loadFailures = 0;
          final loadedAt = ads.now();
          setState(() {
            _displayLease = lease;
            _loadedAt = loadedAt;
            _failed = false;
          });
          _scheduleExpiry(
            ads: ads,
            lease: lease,
            loadedAt: loadedAt,
            runtimeGeneration: runtimeGeneration,
            requestGeneration: requestGeneration,
            themeIdentity: themeIdentity,
          );
        },
        onAdFailedToLoad: (failedAd, error) {
          final currentRequest = identical(_pendingLease, lease);
          if (currentRequest) {
            _pendingLease = null;
            _pendingRuntimeGeneration = null;
          }
          lease.release();
          if (!currentRequest ||
              !_requestIsCurrent(
                ads,
                runtimeGeneration,
                requestGeneration,
                themeIdentity,
              )) {
            return;
          }
          _handleNativeFailure(
            ads,
            runtimeGeneration,
            requestGeneration,
            themeIdentity,
            classifyAdLoadFailure(code: error.code, domain: error.domain),
          );
        },
        onAdImpression: (_) {
          unawaited(
            repository?.recordEvent('ad_native_impression', {
              'screen_name': widget.placement,
              'ad_unit_id': ads.units.native(widget.placement),
            }),
          );
        },
        onAdClicked: (_) {
          unawaited(
            repository?.recordEvent('ad_native_click', {
              'screen_name': widget.placement,
              'ad_unit_id': ads.units.native(widget.placement),
            }),
          );
        },
      ),
    );
    lease = AdLease<NativeAd>(request, (ad) => ad.dispose());
    _pendingLease = lease;
    _pendingRuntimeGeneration = runtimeGeneration;
    try {
      await request.load();
    } on Object catch (error) {
      final currentRequest = identical(_pendingLease, lease);
      if (currentRequest) {
        _pendingLease = null;
        _pendingRuntimeGeneration = null;
      }
      lease.release();
      if (currentRequest &&
          _requestIsCurrent(
            ads,
            runtimeGeneration,
            requestGeneration,
            themeIdentity,
          )) {
        AppLogger.warning('native_ad_load', error: error);
        _handleNativeFailure(
          ads,
          runtimeGeneration,
          requestGeneration,
          themeIdentity,
          AdLoadFailureKind.unknown,
        );
      }
    }
  }

  bool _requestIsCurrent(
    OwntendAdsService ads,
    int runtimeGeneration,
    int requestGeneration,
    String themeIdentity,
  ) =>
      mounted &&
      identical(_ads, ads) &&
      runtimeGeneration == ads.runtimeGeneration &&
      requestGeneration == _requestGeneration &&
      themeIdentity == _themeIdentity &&
      ads.allows(AdFormat.native) &&
      (ModalRoute.isCurrentOf(context) ?? true) &&
      ref.read(nativeAdPresentationDepthProvider) == 0 &&
      widget.enabledOverride != false;

  void _handleNativeFailure(
    OwntendAdsService ads,
    int runtimeGeneration,
    int requestGeneration,
    String themeIdentity,
    AdLoadFailureKind failure,
  ) {
    _loadFailures++;
    final decision = const AdRetryPolicy().decide(
      failure: failure,
      failedAttempt: _loadFailures,
      jitterUnit: _defaultAdJitter(),
    );
    setState(() => _failed = true);
    if (!decision.shouldRetry) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(decision.delay, () {
      _retryTimer = null;
      if (!_requestIsCurrent(
        ads,
        runtimeGeneration,
        requestGeneration,
        themeIdentity,
      )) {
        return;
      }
      setState(() => _failed = false);
      _scheduleSynchronize();
    });
  }

  void _scheduleExpiry({
    required OwntendAdsService ads,
    required AdLease<NativeAd> lease,
    required DateTime loadedAt,
    required int runtimeGeneration,
    required int requestGeneration,
    required String themeIdentity,
  }) {
    _expiryTimer?.cancel();
    _expiryTimer = Timer(kAdCacheMaxAge, () {
      _expiryTimer = null;
      if (!mounted ||
          !identical(_ads, ads) ||
          !identical(_displayLease, lease) ||
          _loadedAt != loadedAt ||
          runtimeGeneration != ads.runtimeGeneration ||
          requestGeneration != _requestGeneration ||
          themeIdentity != _themeIdentity) {
        return;
      }

      final shouldReload = _requestIsCurrent(
        ads,
        runtimeGeneration,
        requestGeneration,
        themeIdentity,
      );
      _requestGeneration++;
      _displayLease = null;
      _loadedAt = null;
      _loadFailures = 0;
      lease.release();
      setState(() {
        _enabled = shouldReload;
        _failed = false;
      });
      if (shouldReload) _scheduleSynchronize();
    });
  }

  Map<String, Object> _nativePalette(ColorScheme scheme) => {
    'backgroundColor': _nativeHex(scheme.surfaceContainerLowest),
    'borderColor': _nativeHex(scheme.outlineVariant),
    'headlineColor': _nativeHex(scheme.onSurface),
    'bodyColor': _nativeHex(scheme.onSurfaceVariant),
    'advertiserColor': _nativeHex(scheme.onSurfaceVariant),
    'sponsoredColor': _nativeHex(scheme.onSurfaceVariant),
    'adBadgeBackgroundColor': _nativeHex(scheme.primaryContainer),
    'adBadgeTextColor': _nativeHex(scheme.onPrimaryContainer),
    'callToActionBackgroundColor': _nativeHex(scheme.primary),
    'callToActionTextColor': _nativeHex(scheme.onPrimary),
  };

  String _nativeHex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  void _deactivate() {
    final hadVisibleState =
        _enabled || _failed || _displayLease != null || _pendingLease != null;
    _requestGeneration++;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _displayLease?.release();
    _pendingLease?.release();
    _displayLease = null;
    _pendingLease = null;
    _loadedAt = null;
    _pendingRuntimeGeneration = null;
    _enabled = false;
    _failed = false;
    _loadFailures = 0;
    if (mounted && hadVisibleState) setState(() {});
  }
}

class HkNativeAdLoadingSkeleton extends StatelessWidget {
  const HkNativeAdLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = scheme.onSurfaceVariant.withValues(alpha: 0.14);
    return ExcludeSemantics(
      child: DecoratedBox(
        key: const ValueKey('native-ad-loading-skeleton'),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _NativeAdSkeletonBlock(
                width: 64,
                height: 64,
                color: placeholder,
                radius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _NativeAdSkeletonBlock(
                      width: 132,
                      height: 12,
                      color: placeholder,
                    ),
                    const SizedBox(height: 8),
                    _NativeAdSkeletonBlock(
                      width: double.infinity,
                      height: 8,
                      color: placeholder,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _NativeAdSkeletonBlock(
                            width: double.infinity,
                            height: 8,
                            color: placeholder,
                          ),
                        ),
                        const SizedBox(width: 16),
                        _NativeAdSkeletonBlock(
                          width: 82,
                          height: 28,
                          color: placeholder,
                          radius: 8,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NativeAdSkeletonBlock extends StatelessWidget {
  const _NativeAdSkeletonBlock({
    required this.width,
    required this.height,
    required this.color,
    this.radius = 4,
  });

  final double width;
  final double height;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class HkNativeAdSlotFrame extends StatelessWidget {
  const HkNativeAdSlotFrame({
    required this.collapsed,
    required this.child,
    this.bottomSpacing = 0,
    super.key,
  });

  final bool collapsed;
  final Widget child;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      child: SizedBox(
        height: collapsed ? 0 : 112 + bottomSpacing,
        width: double.infinity,
        child: collapsed
            ? null
            : Padding(
                padding: EdgeInsets.only(bottom: bottomSpacing),
                child: child,
              ),
      ),
    );
  }
}

class HkPointsPill extends ConsumerWidget {
  const HkPointsPill({required this.onTap, this.compact = false, super.key});

  static const width = 82.0;

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final balance = ref.watch(pointWalletProvider).value?.balance;
    final pointsLabel = balance == null
        ? context.l10n.pointsUnavailable
        : context.l10n.pointsCount(balance);

    // Spec Component C: independent squircle tile (border-radius: 16px).
    // The solid filled star is enclosed in a circular tinted container.
    final height = compact ? 40.0 : 44.0;
    final starCircleSize = compact ? 28.0 : 32.0;
    final innerGap = compact ? 6.0 : HkSpacing.space6;
    final hPadStart = compact ? 6.0 : HkSpacing.xs;
    final hPadEnd = compact ? 10.0 : 14.0;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(HkRadii.lg),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.72)),
    );
    return Semantics(
      button: true,
      container: true,
      excludeSemantics: true,
      label: pointsLabel,
      child: Tooltip(
        message: context.l10n.pointsWallet,
        excludeFromSemantics: true,
        child: SizedBox(
          height: height,
          child: Material(
            color: scheme.surfaceContainerLowest,
            shape: shape,
            elevation: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HkRadii.lg),
                boxShadow: [
                  BoxShadow(
                    color: HkColors.appTextPrimary.withValues(alpha: 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: InkWell(
                customBorder: shape,
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: hPadStart,
                    end: hPadEnd,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: starCircleSize,
                        height: starCircleSize,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              scheme.primaryContainer,
                              Color.alphaBlend(
                                scheme.tertiary.withValues(alpha: 0.13),
                                scheme.primaryContainer,
                              ),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(HkRadii.md),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.14),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Symbols.star_rounded,
                              size: 19,
                              color: scheme.primary,
                              fill: 1,
                            ),
                            PositionedDirectional(
                              end: 3,
                              top: 3,
                              child: Icon(
                                Symbols.auto_awesome_rounded,
                                size: 7,
                                color: scheme.tertiary,
                                fill: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: innerGap),
                      Text(
                        balance?.toString() ?? '-',
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool get _supportsMobileAds =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);
