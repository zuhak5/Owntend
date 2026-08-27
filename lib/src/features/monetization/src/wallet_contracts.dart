part of '../monetization.dart';

/// Returns the complete, allowlisted wire contract for an authoritative
/// owned-asset copy. Local recovery context may live beside these keys in the
/// durable journal, but it must never cross the RPC trust boundary.
Map<String, dynamic> authoritativeAssetCopyPayload(
  Map<String, dynamic> journalPayload,
) => <String, dynamic>{
  for (final key in const <String>[
    'operation_id',
    'request_hash',
    'source_asset_id',
    'target_asset_id',
    'destination_room_id',
    'include_tasks',
    'plan_id_map',
  ])
    key: journalPayload[key],
};

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

class AuthoritativeQuote {
  const AuthoritativeQuote({
    required this.charge,
    required this.balance,
    required this.revision,
    this.subjectCount = 1,
  });

  factory AuthoritativeQuote.fromJson(
    Map<String, dynamic> json, {
    required String revisionKey,
  }) => AuthoritativeQuote(
    charge: (json['charge'] as num?)?.toInt() ?? 0,
    balance: (json['balance'] as num?)?.toInt() ?? 0,
    revision: (json[revisionKey] as num?)?.toInt() ?? 0,
    subjectCount: (json['plan_count'] as num?)?.toInt() ?? 1,
  );

  final int charge;
  final int balance;
  final int revision;
  final int subjectCount;
}

class AuthoritativeMutationResult {
  const AuthoritativeMutationResult({
    required this.status,
    required this.charged,
    required this.balance,
    required this.alreadyProcessed,
    this.conflictReason,
    this.asset,
    this.plan,
  });

  factory AuthoritativeMutationResult.fromJson(Map<String, dynamic> json) =>
      AuthoritativeMutationResult(
        status: json['status'] as String? ?? 'invalid',
        charged: (json['charged'] as num?)?.toInt() ?? 0,
        balance: (json['balance'] as num?)?.toInt() ?? 0,
        alreadyProcessed: json['already_processed'] as bool? ?? false,
        conflictReason: json['conflict_reason'] as String?,
        asset: json['asset'] is Map
            ? Map<String, dynamic>.from(json['asset'] as Map)
            : null,
        plan: json['plan'] is Map
            ? Map<String, dynamic>.from(json['plan'] as Map)
            : null,
      );

  final String status;
  final int charged;
  final int balance;
  final bool alreadyProcessed;
  final String? conflictReason;
  final Map<String, dynamic>? asset;
  final Map<String, dynamic>? plan;

  bool get applied => status == 'applied';
}

class AssetCopyResult extends PointDebitResult {
  const AssetCopyResult({
    required super.balance,
    required super.charged,
    required super.alreadyProcessed,
    super.asset,
    this.plans = const [],
    this.planMetadata = const [],
    this.detailRows = const [],
  });

  factory AssetCopyResult.fromJson(Map<String, dynamic> json) =>
      AssetCopyResult(
        balance: (json['balance'] as num?)?.toInt() ?? 0,
        charged: (json['charged'] as num?)?.toInt() ?? 0,
        alreadyProcessed: json['already_processed'] as bool? ?? false,
        asset: json['asset'] is Map
            ? Map<String, dynamic>.from(json['asset'] as Map)
            : null,
        plans: _jsonMapList(json['plans']),
        planMetadata: _jsonMapList(json['plan_metadata']),
        detailRows: _jsonMapList(json['detail_rows']),
      );

  final List<Map<String, dynamic>> plans;
  final List<Map<String, dynamic>> planMetadata;
  final List<Map<String, dynamic>> detailRows;
}

List<Map<String, dynamic>> _jsonMapList(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map) Map<String, dynamic>.from(item),
      ]
    : const [];

class ChargedOperationStatusResult {
  const ChargedOperationStatusResult({
    required this.status,
    this.charged,
    this.balance,
    this.entityType,
    this.entityId,
    this.asset,
    this.plan,
    this.metadata,
    this.plans = const [],
    this.planMetadata = const [],
    this.detailRows = const [],
  });

  final String status;
  final int? charged;
  final int? balance;
  final String? entityType;
  final String? entityId;
  final Map<String, dynamic>? asset;
  final Map<String, dynamic>? plan;
  final Map<String, dynamic>? metadata;
  final List<Map<String, dynamic>> plans;
  final List<Map<String, dynamic>> planMetadata;
  final List<Map<String, dynamic>> detailRows;

  factory ChargedOperationStatusResult.fromJson(Map<String, dynamic> json) {
    return ChargedOperationStatusResult(
      status: json['status'] as String,
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
      plans: _jsonMapList(json['plans']),
      planMetadata: _jsonMapList(json['plan_metadata']),
      detailRows: _jsonMapList(json['detail_rows']),
    );
  }
}

class InsufficientPointsException implements Exception {
  const InsufficientPointsException({required this.balance});

  final int balance;

  @override
  String toString() => 'INSUFFICIENT_POINTS';
}

bool isInsufficientPointsError(Object error) {
  if (error is InsufficientPointsException) return true;
  if (error case PostgrestException(:final message)) {
    return message == 'INSUFFICIENT_POINTS';
  }
  return error.toString().contains('INSUFFICIENT_POINTS');
}

class OperationIdReusedException implements Exception {
  const OperationIdReusedException();

  @override
  String toString() => 'OPERATION_ID_REUSED';
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

  Future<AssetCopyResult> copyAsset(Map<String, dynamic> operation) =>
      Future.error(
        UnsupportedError('Authoritative asset copy is unavailable.'),
      );

  Future<AuthoritativeQuote> quoteMaintenancePlanMove({
    required String planId,
    required String targetAssetId,
  }) => Future.error(UnsupportedError('Task move quote is unavailable.'));

  Future<AuthoritativeMutationResult> moveMaintenancePlan(
    Map<String, dynamic> operation,
  ) =>
      Future.error(UnsupportedError('Authoritative task move is unavailable.'));

  Future<AuthoritativeQuote> quoteAssetTypeChange({
    required String assetId,
    required String targetType,
  }) => Future.error(UnsupportedError('Asset type quote is unavailable.'));

  Future<AuthoritativeMutationResult> changeAssetType(
    Map<String, dynamic> operation,
  ) => Future.error(
    UnsupportedError('Authoritative type change is unavailable.'),
  );

  Future<ChargedOperationStatusResult> getChargedOperationStatus(
    String operationId, {
    required String requestHash,
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
