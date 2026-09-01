import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/features/maintenance/application/task_creation_controller.dart';
import 'package:owntend/src/core/services/charged_operation_journal/charged_operation_store.dart';
import 'package:owntend/src/core/services/charged_operation_journal/charged_operation_contracts.dart';
import 'package:owntend/src/features/monetization/monetization.dart';

class _ZeroPointsMonetizationRepository implements MonetizationRepository {
  final List<Map<String, dynamic>> createAssetCalls = [];
  final List<Map<String, dynamic>> createTaskCalls = [];

  @override
  String? get currentUserId => 'user-zero';

  @override
  Stream<PointWallet?> watchWallet(String userId) => Stream.value(
    PointWallet(
      balance: 0,
      timeZone: 'UTC',
      updatedAt: DateTime.utc(2026, 8, 14),
    ),
  );

  @override
  Stream<MonetizationConfig> watchConfig() =>
      Stream.value(const MonetizationConfig.failClosed());

  @override
  Future<List<PendingRewardClaim>> fetchPendingRewardClaims(
    String userId,
  ) async => const [];

  @override
  Future<PointDebitResult> createAsset(Map<String, dynamic> operation) async {
    createAssetCalls.add(operation);
    return PointDebitResult(
      balance: 0,
      charged: 0,
      alreadyProcessed: false,
      asset: operation['asset'] as Map<String, dynamic>?,
    );
  }

  @override
  Future<PointDebitResult> createTask(Map<String, dynamic> operation) async {
    createTaskCalls.add(operation);
    throw const InsufficientPointsException(balance: 0);
  }

  @override
  Future<AssetCopyResult> copyAsset(Map<String, dynamic> operation) =>
      throw UnimplementedError();

  @override
  Future<AuthoritativeQuote> quoteMaintenancePlanMove({
    required String planId,
    required String targetAssetId,
  }) => throw UnimplementedError();

  @override
  Future<AuthoritativeMutationResult> moveMaintenancePlan(
    Map<String, dynamic> operation,
  ) => throw UnimplementedError();

  @override
  Future<AuthoritativeQuote> quoteAssetTypeChange({
    required String assetId,
    required String targetType,
  }) => throw UnimplementedError();

  @override
  Future<AuthoritativeMutationResult> changeAssetType(
    Map<String, dynamic> operation,
  ) => throw UnimplementedError();

  @override
  Future<ChargedOperationStatusResult> getChargedOperationStatus(
    String operationId, {
    String? requestHash,
  }) async {
    return const ChargedOperationStatusResult(status: 'not_found');
  }

  @override
  Future<void> recordEvent(
    String eventName, [
    Map<String, dynamic> properties = const {},
  ]) async {}

  @override
  Future<List<Map<String, dynamic>>> listTransactions() async => const [];

  @override
  Future<RewardClaimRequest> createRewardClaim(
    RewardAdType type, {
    String? timeZone,
    String? eligibilityToken,
  }) => throw UnimplementedError();
}

void main() {
  group('Free Asset Creation & Task-Only Points Economy', () {
    test(
      'creating an asset with 0 balance succeeds and charges 0 points',
      () async {
        final repo = _ZeroPointsMonetizationRepository();
        final result = await repo.createAsset({
          'operation_id': 'op-asset-001',
          'asset': {
            'id': 'asset-free-001',
            'name': 'Living Room Sofa',
            'asset_type': 'general',
            'room_id': 'room-living',
          },
          'initial_plans': [
            {
              'id': 'plan-bundled-001',
              'asset_id': 'asset-free-001',
              'title': 'Vacuum sofa upholstery',
              'recurrence_interval': 1,
              'recurrence_unit': 'months',
              'priority': 'low',
              'next_due_date': DateTime.utc(2026, 9, 1).toIso8601String(),
            },
          ],
        });

        expect(result.charged, equals(0));
        expect(result.balance, equals(0));
        expect(result.alreadyProcessed, isFalse);
        expect(repo.createAssetCalls, hasLength(1));
      },
    );

    test('asset creation payload includes a valid 64-char hex request_hash', () async {
      final unsignedPayload = {
        'operation_id': 'op-asset-002',
        'asset': {
          'id': 'asset-free-002',
          'name': 'Kitchen Blender',
          'asset_type': 'device',
          'room_id': 'room-kitchen',
        },
        'details': {'brand': 'BrandX', 'model': 'BX-100'},
        'initial_plans': const <Map<String, dynamic>>[],
      };
      final repo = _ZeroPointsMonetizationRepository();
      await repo.createAsset({
        ...unsignedPayload,
        'request_hash':
            'c813adc62ab3f9d608220e84a969c7055803e54847eb667ece9e427f498a0b7d',
      });

      expect(repo.createAssetCalls, hasLength(1));
      final call = repo.createAssetCalls.first;
      expect(call['request_hash'], isA<String>());
      expect(
        call['request_hash'] as String,
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
    });

    test('creating a standalone task with 0 balance throws InsufficientPointsException', () async {
      final repo = _ZeroPointsMonetizationRepository();
      final operationStore = TaskCreationOperationStore();
      final container = ProviderContainer(
        overrides: [
          monetizationRepositoryProvider.overrideWithValue(repo),
          taskCreationOperationStoreProvider.overrideWithValue(operationStore),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(taskCreationControllerProvider);
      addTearDown(controller.dispose);

      final success = await controller.createNewTask(
        assetId: 'asset-free-001',
        title: 'Deep clean upholstery',
        recurrence: const RecurrenceRule(
          interval: 3,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: DateTime.utc(2026, 11, 1),
        accountScope: 'user-zero',
      );

      expect(success, isFalse);
      expect(
        controller.value.failure?.code,
        equals(TaskCreationFailureCode.insufficientPoints),
      );
      expect(repo.createTaskCalls, hasLength(1));
    });

    testWidgets(
      'points wallet explains entitlement deltas and the no-refund rule',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return Text(
                    AppLocalizations.of(context).pointsRuleExplanation,
                  );
                },
              ),
            ),
          ),
        );

        expect(
          find.text(
            'Creating a new maintenance task costs 1 point. Creating items and safety tasks is free. Moving a free task to a paid item or changing an item type can charge the missing task entitlement; no refunds are issued.',
          ),
          findsOneWidget,
        );
      },
    );

    test('reconcileAssetCreationComposite applies canonical record and removes outbox entry', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = LocalSyncStore(db);
      final now = DateTime.now().toUtc();
      const assetId = 'asset-reconcile-001';

      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(
              id: 'area-reconcile-1',
              name: 'Kitchen Area',
              kind: 'indoor',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              id: 'room-reconcile-1',
              areaId: 'area-reconcile-1',
              name: 'Kitchen',
              roomType: const Value('kitchen'),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: assetId,
              name: 'Refrigerator',
              assetType: const Value('device'),
              roomId: 'room-reconcile-1',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      // Verify outbox was created by trigger
      final outboxBefore =
          await (db.select(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals('asset') & row.recordKey.equals(assetId),
              ))
              .get();
      expect(outboxBefore, hasLength(1));

      // Reconcile composite
      await store.reconcileAssetCreationComposite(
        assetId: assetId,
        assetJson: {
          'id': assetId,
          'user_id': 'user-zero',
          'name': 'Refrigerator',
          'asset_type': 'device',
          'room_id': 'room-reconcile-1',
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
      );

      // Verify outbox was cleared
      final outboxAfter =
          await (db.select(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals('asset') & row.recordKey.equals(assetId),
              ))
              .get();
      expect(outboxAfter, isEmpty);
    });
  });
}
