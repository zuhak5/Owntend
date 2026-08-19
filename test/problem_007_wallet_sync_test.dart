import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/sync/sync_providers.dart';
import 'package:owntend/src/features/monetization/monetization.dart';

PointWallet _wallet(int balance, int minute) => PointWallet(
  balance: balance,
  timeZone: 'Asia/Baghdad',
  updatedAt: DateTime.utc(2026, 8, 20, 0, minute),
);

class _FakeWalletRepository extends MonetizationRepository {
  _FakeWalletRepository({PointWallet? canonical})
    : canonical = canonical ?? _wallet(5, 1);

  String? userId = 'user-a';
  PointWallet? canonical;
  int watchCount = 0;
  final events = StreamController<PointWallet?>.broadcast();
  Completer<PointWallet?>? _nextInitial;

  @override
  String? get currentUserId => userId;

  void delayNextCanonical() {
    _nextInitial = Completer<PointWallet?>();
  }

  void completeDelayedCanonical(PointWallet? wallet) {
    canonical = wallet;
    final completer = _nextInitial;
    _nextInitial = null;
    completer?.complete(wallet);
  }

  void emit(PointWallet? wallet) {
    canonical = wallet;
    events.add(wallet);
  }

  @override
  Stream<PointWallet?> watchWallet(String userId) async* {
    watchCount += 1;
    final delayed = _nextInitial;
    if (delayed != null) {
      yield await delayed.future;
    } else {
      yield canonical;
    }
    yield* events.stream;
  }

  @override
  Stream<MonetizationConfig> watchConfig() =>
      Stream.value(const MonetizationConfig.failClosed());

  @override
  Future<List<PendingRewardClaim>> fetchPendingRewardClaims(
    String userId,
  ) async => const [];

  @override
  Future<PointDebitResult> createAsset(Map<String, dynamic> operation) =>
      throw UnimplementedError();

  @override
  Future<PointDebitResult> createTask(Map<String, dynamic> operation) =>
      throw UnimplementedError();

  @override
  Future<ChargedOperationStatusResult> getChargedOperationStatus(
    String operationId, {
    required String requestHash,
  }) => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> listTransactions() async => const [];

  @override
  Future<RewardClaimRequest> createRewardClaim(
    RewardAdType type, {
    String? timeZone,
  }) => throw UnimplementedError();

  @override
  Future<void> recordEvent(
    String eventName, [
    Map<String, dynamic> properties = const {},
  ]) async {}

  Future<void> close() => events.close();
}

ProviderContainer _container(_FakeWalletRepository repository) {
  return ProviderContainer(
    overrides: [
      monetizationRepositoryProvider.overrideWith((ref) => repository),
      syncConnectivityProvider.overrideWith((ref) => Stream.value(true)),
    ],
  );
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test(
    'wallet owner loads, adopts mutations, and rejects stale snapshots',
    () async {
      final repository = _FakeWalletRepository();
      final container = _container(repository);
      addTearDown(container.dispose);
      addTearDown(repository.close);

      container.read(pointWalletProvider);
      await _settle();
      expect(container.read(pointWalletProvider).value?.balance, 5);

      repository.delayNextCanonical();
      container
          .read(pointWalletControllerProvider.notifier)
          .adoptAuthoritativeMutationResult(4, userId: 'user-a');
      expect(container.read(pointWalletProvider).value?.balance, 4);

      repository.emit(_wallet(5, 1));
      await _settle();
      expect(container.read(pointWalletProvider).value?.balance, 4);

      repository.completeDelayedCanonical(_wallet(5, 1));
      await _settle();
      expect(container.read(pointWalletProvider).value?.balance, 4);

      repository.emit(_wallet(4, 2));
      await _settle();
      expect(container.read(pointWalletProvider).value?.balance, 4);

      repository.emit(_wallet(6, 3));
      await _settle();
      expect(container.read(pointWalletProvider).value?.balance, 6);

      repository.emit(_wallet(3, 2));
      await _settle();
      expect(container.read(pointWalletProvider).value?.balance, 6);
    },
  );

  test(
    'same-account refresh and reconnect preserve last-good wallet',
    () async {
      final repository = _FakeWalletRepository(canonical: _wallet(8, 1));
      final container = _container(repository);
      addTearDown(container.dispose);
      addTearDown(repository.close);

      container.read(pointWalletProvider);
      await _settle();
      expect(container.read(pointWalletProvider).value?.balance, 8);

      repository.delayNextCanonical();
      final refresh = container
          .read(pointWalletControllerProvider.notifier)
          .refresh();
      await _settle();
      expect(container.read(pointWalletProvider).value?.balance, 8);
      repository.completeDelayedCanonical(_wallet(9, 2));
      await refresh;
      expect(container.read(pointWalletProvider).value?.balance, 9);

      repository.delayNextCanonical();
      final beforeReconnect = repository.watchCount;
      final reconnect = container
          .read(pointWalletControllerProvider.notifier)
          .reconnect();
      await _settle();
      expect(container.read(pointWalletProvider).value?.balance, 9);
      repository.completeDelayedCanonical(_wallet(10, 3));
      await reconnect;
      expect(container.read(pointWalletProvider).value?.balance, 10);
      expect(repository.watchCount, greaterThan(beforeReconnect));
    },
  );

  test(
    'auth switch and sign-out clear the previous account immediately',
    () async {
      final repository = _FakeWalletRepository(canonical: _wallet(7, 1));
      final container = _container(repository);
      addTearDown(container.dispose);
      addTearDown(repository.close);

      container.read(pointWalletProvider);
      await _settle();
      expect(container.read(pointWalletProvider).value?.balance, 7);

      repository.userId = 'user-b';
      repository.delayNextCanonical();
      final switching = container
          .read(pointWalletControllerProvider.notifier)
          .synchronizeAuthScope();
      await _settle();
      expect(container.read(pointWalletProvider).value, isNull);
      repository.completeDelayedCanonical(_wallet(2, 2));
      await switching;
      expect(container.read(pointWalletProvider).value?.balance, 2);

      repository.userId = null;
      await container
          .read(pointWalletControllerProvider.notifier)
          .synchronizeAuthScope();
      expect(container.read(pointWalletProvider).value, isNull);
    },
  );

  testWidgets(
    'points pill updates immediately and keeps last-good during refresh',
    (tester) async {
      final repository = _FakeWalletRepository(canonical: _wallet(5, 1));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            monetizationRepositoryProvider.overrideWith((ref) => repository),
            syncConnectivityProvider.overrideWith((ref) => Stream.value(true)),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: HkPointsPill(onTap: () {})),
          ),
        ),
      );
      addTearDown(repository.close);
      await tester.pump();
      await tester.pump();
      expect(find.text('5'), findsOneWidget);

      final element = tester.element(find.byType(HkPointsPill));
      final container = ProviderScope.containerOf(element);

      repository.delayNextCanonical();
      container
          .read(pointWalletControllerProvider.notifier)
          .adoptAuthoritativeMutationResult(4, userId: 'user-a');
      await tester.pump();
      expect(find.text('4'), findsOneWidget);
      expect(find.text('-'), findsNothing);

      repository.completeDelayedCanonical(_wallet(4, 2));
      await tester.pump();
      await tester.pump();

      repository.emit(_wallet(6, 3));
      await tester.pump();
      await tester.pump();
      expect(find.text('6'), findsOneWidget);

      final semantics = tester.getSemantics(find.byType(HkPointsPill));
      expect(semantics.label, contains('6'));

      repository.delayNextCanonical();
      unawaited(
        container.read(pointWalletControllerProvider.notifier).refresh(),
      );
      await tester.pump();
      expect(find.text('6'), findsOneWidget);
      expect(find.text('-'), findsNothing);
      repository.completeDelayedCanonical(_wallet(6, 3));
      await tester.pump();
    },
  );

  test('all charged mutation paths route server balances to the shared owner', () {
    final taskController = File(
      'lib/src/features/maintenance/application/task_creation_controller.dart',
    ).readAsStringSync();
    final assetDialogs = File(
      'lib/src/features/assets/presentation/asset_dialogs.dart',
    ).readAsStringSync();
    final resolver = File(
      'lib/src/features/monetization/charged_operation_resolver.dart',
    ).readAsStringSync();

    expect(taskController, contains('adoptAuthoritativeMutationResult'));
    expect(
      RegExp('adoptAuthoritativeMutationResult')
          .allMatches(assetDialogs)
          .length,
      greaterThanOrEqualTo(2),
    );
    expect(
      resolver,
      contains('_adoptAuthoritativeBalance(accountScope, balance)'),
    );
    expect(
      RegExp(r'_adoptAuthoritativeBalance\(accountScope, result\.balance\)')
          .allMatches(resolver)
          .length,
      2,
    );
  });

  test('wallet remains outside the generic local-first change-feed set', () {
    final realtimeSql = File(
      'supabase/tests/database/0006_realtime_sync.test.sql',
    ).readAsStringSync();
    final changeFeed = File('lib/src/core/sync/change_feed_contract.dart')
        .readAsStringSync();

    expect(realtimeSql, isNot(contains("'point_wallets'")));
    expect(changeFeed, isNot(contains('point_wallet')));
  });
}
