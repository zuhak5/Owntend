part of '../monetization.dart';

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
    required String requestHash,
  }) async {
    try {
      final data = await client.rpc<Map<String, dynamic>>(
        'get_charged_operation_status',
        params: {'p_operation_id': operationId, 'p_request_hash': requestHash},
      );
      return ChargedOperationStatusResult.fromJson(data);
    } on PostgrestException catch (error) {
      if (error.message == 'OPERATION_ID_REUSED') {
        throw const OperationIdReusedException();
      }
      rethrow;
    }
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
      if (error.message == 'OPERATION_ID_REUSED') {
        throw const OperationIdReusedException();
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

final pointWalletControllerProvider =
    NotifierProvider<PointWalletController, AsyncValue<PointWallet?>>(
      PointWalletController.new,
    );

/// Read-only wallet view kept as the stable presentation/test seam.
/// State is owned only by [pointWalletControllerProvider].
final pointWalletProvider = Provider<AsyncValue<PointWallet?>>((ref) {
  return ref.watch(pointWalletControllerProvider);
});

/// The single auth-scoped owner for server-authoritative wallet state.
///
/// Ordering rule:
/// * canonical snapshots are ordered by the server's `updated_at`;
/// * a mutation-only balance is adopted immediately, without client arithmetic;
/// * while that balance awaits a post-mutation canonical read, older stream
///   snapshots cannot overwrite it;
/// * the post-mutation canonical read clears that gate and becomes the new
///   server-version baseline.
///
/// The wallet is intentionally not part of the local-first sync/change-feed
/// protocol.
