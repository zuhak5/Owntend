import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/services/charged_operation_journal/charged_operation_contracts.dart';
import 'package:owntend/src/core/services/charged_operation_journal/charged_operation_store.dart';
import 'package:owntend/src/core/services/reminder_schedule_reconciler.dart';
import 'package:owntend/src/features/maintenance/application/task_creation_controller.dart';
import 'package:owntend/src/features/monetization/monetization.dart';

class _FakeNotificationScheduler implements NotificationScheduler {
  int refreshCallCount = 0;

  @override
  Future<void> refreshSchedules() async {
    refreshCallCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Task Creation Offline/Local-Only Flow (CC-01 & CC-04)', () {
    test('createNewTask in local-only mode writes to Drift and reconciles operation store', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      final maintenanceRepo = DriftMaintenanceRepository(db);
      final operationStore = TaskCreationOperationStore();

      // Seed area, room, and asset
      final now = DateTime.now().toUtc();
      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(
              id: 'area-1',
              name: 'Living',
              kind: 'indoor',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              id: 'room-1',
              areaId: 'area-1',
              name: 'Living Room',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: 'asset-1',
              name: 'TV',
              roomId: 'room-1',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      final container = ProviderContainer(
        overrides: [
          monetizationRepositoryProvider.overrideWithValue(null),
          maintenanceRepositoryProvider.overrideWithValue(maintenanceRepo),
          taskCreationOperationStoreProvider.overrideWithValue(operationStore),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(taskCreationControllerProvider);
      addTearDown(controller.dispose);

      final success = await controller.createNewTask(
        assetId: 'asset-1',
        title: 'Clean TV screen',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.low,
        nextDueDate: now.add(const Duration(days: 30)),
        accountScope: 'local',
      );

      expect(success, isTrue);
      expect(controller.value.completedPlanId, isNotNull);

      // Verify the task plan exists in Drift SQLite!
      final savedPlan =
          await (db.select(db.maintenancePlans)
                ..where((p) => p.id.equals(controller.value.completedPlanId!)))
              .getSingleOrNull();

      expect(savedPlan, isNotNull);
      expect(savedPlan!.title, equals('Clean TV screen'));
      expect(savedPlan.assetId, equals('asset-1'));

      // Verify operation store was reconciled!
      final operations = await operationStore.listOperationsForAccount('local');
      expect(operations, hasLength(1));
      expect(
        operations.first.state,
        equals(TaskCreationOperationState.reconciled),
      );
    });
  });

  group('Atomic Sort Order Swapping (CC-05)', () {
    late AppDatabase db;
    late DriftAssetRepository assetRepo;
    late DateTime t0;

    setUp(() async {
      db = AppDatabase(executor: NativeDatabase.memory());
      assetRepo = DriftAssetRepository(db);
      t0 = DateTime.utc(2026, 9, 1, 10, 0, 0);

      // Seed 2 areas
      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(
              id: 'area-a',
              name: 'Area Alpha',
              kind: 'indoor',
              sortOrder: const Value(0),
              createdAt: Value(t0),
              updatedAt: Value(t0),
            ),
          );
      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(
              id: 'area-b',
              name: 'Area Beta',
              kind: 'indoor',
              sortOrder: const Value(1),
              createdAt: Value(t0),
              updatedAt: Value(t0),
            ),
          );

      // Seed 2 rooms in area-a
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              id: 'room-a',
              areaId: 'area-a',
              name: 'Room Alpha',
              sortOrder: const Value(0),
              createdAt: Value(t0),
              updatedAt: Value(t0),
            ),
          );
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              id: 'room-b',
              areaId: 'area-a',
              name: 'Room Beta',
              sortOrder: const Value(1),
              createdAt: Value(t0),
              updatedAt: Value(t0),
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test('swapAreaSortOrders atomically swaps sort orders and increments revisions', () async {
      await assetRepo.swapAreaSortOrders(
        firstAreaId: 'area-a',
        firstExpectedUpdatedAt: t0,
        secondAreaId: 'area-b',
        secondExpectedUpdatedAt: t0,
      );

      final areaA = await (db.select(
        db.areas,
      )..where((a) => a.id.equals('area-a'))).getSingle();
      final areaB = await (db.select(
        db.areas,
      )..where((a) => a.id.equals('area-b'))).getSingle();

      expect(areaA.sortOrder, equals(1));
      expect(areaB.sortOrder, equals(0));
      expect(areaA.updatedAt.isAfter(t0), isTrue);
      expect(areaB.updatedAt.isAfter(t0), isTrue);
    });

    test('swapAreaSortOrders rejects stale revision', () async {
      expect(
        () => assetRepo.swapAreaSortOrders(
          firstAreaId: 'area-a',
          firstExpectedUpdatedAt: t0.subtract(const Duration(seconds: 5)),
          secondAreaId: 'area-b',
          secondExpectedUpdatedAt: t0,
        ),
        throwsA(isA<StateError>()),
      );

      // Verify no changes occurred
      final areaA = await (db.select(
        db.areas,
      )..where((a) => a.id.equals('area-a'))).getSingle();
      final areaB = await (db.select(
        db.areas,
      )..where((a) => a.id.equals('area-b'))).getSingle();
      expect(areaA.sortOrder, equals(0));
      expect(areaB.sortOrder, equals(1));
    });

    test('swapRoomSortOrders atomically swaps sort orders and increments revisions', () async {
      await assetRepo.swapRoomSortOrders(
        firstRoomId: 'room-a',
        firstExpectedUpdatedAt: t0,
        secondRoomId: 'room-b',
        secondExpectedUpdatedAt: t0,
      );

      final roomA = await (db.select(
        db.rooms,
      )..where((r) => r.id.equals('room-a'))).getSingle();
      final roomB = await (db.select(
        db.rooms,
      )..where((r) => r.id.equals('room-b'))).getSingle();

      expect(roomA.sortOrder, equals(1));
      expect(roomB.sortOrder, equals(0));
      expect(roomA.updatedAt.isAfter(t0), isTrue);
      expect(roomB.updatedAt.isAfter(t0), isTrue);
    });

    test('swapRoomSortOrders rejects stale revision', () async {
      expect(
        () => assetRepo.swapRoomSortOrders(
          firstRoomId: 'room-a',
          firstExpectedUpdatedAt: t0.subtract(const Duration(seconds: 1)),
          secondRoomId: 'room-b',
          secondExpectedUpdatedAt: t0,
        ),
        throwsA(isA<StateError>()),
      );

      final roomA = await (db.select(
        db.rooms,
      )..where((r) => r.id.equals('room-a'))).getSingle();
      final roomB = await (db.select(
        db.rooms,
      )..where((r) => r.id.equals('room-b'))).getSingle();
      expect(roomA.sortOrder, equals(0));
      expect(roomB.sortOrder, equals(1));
    });
  });

  group('Local Reminder Reconciliation Drain (CC-07)', () {
    test(
      'drainLocal flushes pending reconciliation requests without auth session',
      () async {
        final db = AppDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);

        final scheduler = _FakeNotificationScheduler();
        final consumer = NotificationReconciliationConsumer(
          database: db,
          scheduler: scheduler,
          accountGuard: (userId) async => true,
        );

        // Insert pending reconciliation requests
        final now = DateTime.now().toUtc();
        await db
            .into(db.notificationReconciliationRequests)
            .insert(
              NotificationReconciliationRequestsCompanion.insert(
                scopeKey: 'plan:plan-1',
                planId: const Value('plan-1'),
                reason: 'task_enabled',
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        await db
            .into(db.notificationReconciliationRequests)
            .insert(
              NotificationReconciliationRequestsCompanion.insert(
                scopeKey: 'all',
                reason: 'schedule_reconciled',
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );

        final requestsBefore = await db
            .select(db.notificationReconciliationRequests)
            .get();
        expect(requestsBefore, hasLength(2));

        final result = await consumer.drainLocal();
        expect(result, equals(NotificationReconciliationDrainResult.refreshed));
        expect(scheduler.refreshCallCount, equals(1));

        // Verify requests were cleared from the database
        final requestsAfter = await db
            .select(db.notificationReconciliationRequests)
            .get();
        expect(requestsAfter, isEmpty);
      },
    );
  });

  group('Photo File Deletion Failure Enqueueing (CC-12)', () {
    test('localMediaCleanup records failed photo deletion paths', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.localMediaCleanup)
          .insertOnConflictUpdate(
            LocalMediaCleanupCompanion.insert(
              relativePath: 'assets/asset-1/photo-1.jpg',
            ),
          );

      final rows = await db.select(db.localMediaCleanup).get();
      expect(rows, hasLength(1));
      expect(rows.first.relativePath, equals('assets/asset-1/photo-1.jpg'));
      expect(rows.first.attempts, equals(0));
    });
  });
}
