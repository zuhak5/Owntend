part of '../monetization.dart';

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
    this.charged,
    this.balance,
    this.entityType,
    this.entityId,
    this.asset,
    this.plan,
    this.metadata,
  });

  final String status;
  final int? charged;
  final int? balance;
  final String? entityType;
  final String? entityId;
  final Map<String, dynamic>? asset;
  final Map<String, dynamic>? plan;
  final Map<String, dynamic>? metadata;

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
