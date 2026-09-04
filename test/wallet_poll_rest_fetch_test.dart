import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/features/monetization/monetization.dart';

class _TrackingMonetizationRepository extends MonetizationRepository {
  int getWalletCalls = 0;
  int watchWalletCalls = 0;

  @override
  String? get currentUserId => 'test-user-1';

  @override
  Future<PointWallet?> getWallet(String userId) async {
    getWalletCalls++;
    return PointWallet(
      balance: 50,
      timeZone: 'UTC',
      updatedAt: DateTime.utc(2026, 9, 1),
    );
  }

  @override
  Stream<PointWallet?> watchWallet(String userId) {
    watchWalletCalls++;
    return Stream.value(
      PointWallet(
        balance: 50,
        timeZone: 'UTC',
        updatedAt: DateTime.utc(2026, 9, 1),
      ),
    );
  }
}

void main() {
  group('PointWalletController REST Polling (BUG-06)', () {
    test('refresh uses discrete getWallet instead of creating stream subscriptions', () async {
      final repository = _TrackingMonetizationRepository();
      final container = ProviderContainer(
        overrides: [
          monetizationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      // Trigger initial read
      container.read(pointWalletProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final initialWatchCalls = repository.watchWalletCalls;

      // Call refresh explicitly (as done during polling):
      await container.read(pointWalletControllerProvider.notifier).refresh();

      // Verify that getWallet was invoked and watchWallet was NOT called again:
      expect(repository.getWalletCalls, greaterThanOrEqualTo(1));
      expect(repository.watchWalletCalls, initialWatchCalls);
      expect(container.read(pointWalletProvider).value?.balance, 50);
    });
  });
}
