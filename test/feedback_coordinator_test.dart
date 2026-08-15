import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/ui/feedback/feedback_coordinator.dart';
import 'package:owntend/src/ui/feedback/feedback_bar.dart';
import 'package:owntend/src/ui/feedback/feedback_model.dart';

void main() {
  final coordinator = FeedbackCoordinator.instance;

  setUp(coordinator.resetForTesting);
  tearDown(coordinator.resetForTesting);

  Future<BuildContext> pumpHarness(
    WidgetTester tester, {
    bool accessibleNavigation = false,
  }) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(accessibleNavigation: accessibleNavigation),
          child: Scaffold(
            body: Builder(
              builder: (value) {
                context = value;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    return context;
  }

  HkFeedbackItem undoItem({
    required String id,
    required String label,
    required Future<void> Function() undo,
    Future<void> Function()? finalize,
    String batchType = 'trash',
  }) => HkFeedbackItem(
    id: id,
    message: Text(label),
    mode: HkFeedbackMode.undoable,
    actionLabel: 'Undo',
    onUndo: undo,
    onFinalize: finalize,
    batchItemType: batchType,
    batchMessageBuilder: (count) => Text('$count items'),
  );

  testWidgets('error waits behind protected Undo', (tester) async {
    final context = await pumpHarness(tester);
    var undoCalls = 0;
    coordinator.show(
      context,
      undoItem(
        id: 'trash-1',
        label: 'Undo remains visible',
        undo: () async => undoCalls++,
      ),
    );
    await tester.pump();
    coordinator.show(
      context,
      const HkFeedbackItem(
        id: 'error-1',
        message: Text('Queued error'),
        tone: HkFeedbackTone.error,
      ),
    );
    await tester.pump();

    expect(find.text('Undo remains visible'), findsOneWidget);
    expect(find.text('Queued error'), findsNothing);
    expect(coordinator.pendingCount, 1);

    await coordinator.handleAction();
    await tester.pumpAndSettle();
    expect(undoCalls, 1);
    expect(find.text('Queued error'), findsOneWidget);
    coordinator.resetForTesting();
  });

  testWidgets('compatible batches re-render count and undo in LIFO order', (
    tester,
  ) async {
    final context = await pumpHarness(tester);
    final order = <String>[];
    coordinator.show(
      context,
      undoItem(
        id: 'trash-1',
        label: '1 item',
        undo: () async => order.add('first'),
      ),
    );
    await tester.pump();
    coordinator.show(
      context,
      undoItem(
        id: 'trash-2',
        label: '1 item',
        undo: () async => order.add('second'),
      ),
    );
    await tester.pump();

    expect(find.text('2 items'), findsOneWidget);
    expect(coordinator.activeItem?.batchCount, 2);

    await coordinator.handleAction();
    expect(order, ['second', 'first']);
    await coordinator.handleAction();
    expect(order, ['second', 'first']);
  });

  testWidgets('incompatible Undo waits and batch resets the deadline', (
    tester,
  ) async {
    final context = await pumpHarness(tester);
    var finalized = 0;
    coordinator.show(
      context,
      undoItem(
        id: 'trash-1',
        label: 'Trash undo',
        undo: () async {},
        finalize: () async => finalized++,
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    coordinator.show(
      context,
      undoItem(
        id: 'trash-2',
        label: 'Second trash',
        undo: () async {},
        finalize: () async => finalized++,
      ),
    );
    coordinator.show(
      context,
      undoItem(
        id: 'completion-1',
        label: 'Completion undo',
        batchType: 'completion',
        undo: () async {},
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));

    expect(coordinator.activeItem?.batchCount, 2);
    expect(finalized, 0);
    expect(coordinator.pendingCount, 1);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(finalized, 2);
    expect(coordinator.activeItem?.batchItemType, 'completion');
    coordinator.resetForTesting();
  });

  testWidgets('accessible Undo remains until explicit action', (tester) async {
    final context = await pumpHarness(tester, accessibleNavigation: true);
    var finalized = 0;
    coordinator.show(
      context,
      undoItem(
        id: 'accessible',
        label: 'Persistent undo',
        undo: () async {},
        finalize: () async => finalized++,
      ),
    );

    await tester.pump(const Duration(minutes: 1));
    expect(coordinator.activeItem?.id, 'accessible');
    expect(finalized, 0);

    await coordinator.handleAction();
    expect(coordinator.activeItem, isNull);
  });

  testWidgets('callback failure cannot strand queued feedback', (tester) async {
    final context = await pumpHarness(tester);
    coordinator.show(
      context,
      undoItem(
        id: 'failing',
        label: 'Failing undo',
        undo: () async => throw StateError('test failure'),
      ),
    );
    coordinator.show(
      context,
      const HkFeedbackItem(id: 'after', message: Text('After failure')),
    );

    await coordinator.handleAction();
    await tester.pumpAndSettle();
    expect(find.text('After failure'), findsOneWidget);
    coordinator.resetForTesting();
  });

  testWidgets('floating feedback keeps one visual gap above a Scaffold FAB', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late BuildContext context;
    const fabKey = ValueKey('feedback-test-fab');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox.expand();
            },
          ),
          bottomNavigationBar: const SizedBox(height: 80),
          floatingActionButton: FloatingActionButton(
            key: fabKey,
            onPressed: () {},
          ),
        ),
      ),
    );

    coordinator.show(
      context,
      const HkFeedbackItem(id: 'fab', message: Text('Above the FAB')),
    );
    await tester.pumpAndSettle();

    final feedback = tester.getRect(find.byType(HkFeedbackBar));
    final fab = tester.getRect(find.byKey(fabKey));
    expect(feedback.bottom, lessThan(fab.top));
    expect(fab.top - feedback.bottom, closeTo(12, 1));
  });

  testWidgets(
    'floating feedback keeps one visual gap above bottom navigation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late BuildContext context;
      const navigationKey = ValueKey('feedback-test-navigation');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (value) {
                context = value;
                return const SizedBox.expand();
              },
            ),
            bottomNavigationBar: const SizedBox(key: navigationKey, height: 80),
          ),
        ),
      );

      coordinator.show(
        context,
        const HkFeedbackItem(
          id: 'navigation',
          message: Text('Above navigation'),
        ),
      );
      await tester.pumpAndSettle();

      final feedback = tester.getRect(find.byType(HkFeedbackBar));
      final navigation = tester.getRect(find.byKey(navigationKey));
      expect(feedback.bottom, lessThan(navigation.top));
      expect(navigation.top - feedback.bottom, closeTo(12, 1));
    },
  );

  testWidgets('feedback triggered in a modal sheet stays above its barrier', (
    tester,
  ) async {
    final pageContext = await pumpHarness(tester);
    late BuildContext sheetContext;

    showModalBottomSheet<void>(
      context: pageContext,
      builder: (context) {
        sheetContext = context;
        return const SizedBox(height: 320, child: Text('Open sheet'));
      },
    );
    await tester.pumpAndSettle();

    coordinator.show(
      sheetContext,
      const HkFeedbackItem(
        id: 'modal-feedback',
        message: Text('Visible above sheet'),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('feedback-modal-overlay')),
      findsOneWidget,
    );
    expect(find.text('Visible above sheet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('feedback-dismiss')));
    await tester.pumpAndSettle();
    expect(coordinator.activeItem, isNull);
    expect(find.text('Visible above sheet'), findsNothing);
  });

  test('task, asset, room, and area Trash flows all expose restoration', () {
    final source = [
      File('lib/main.dart').readAsStringSync(),
      for (final entity in Directory('lib/src').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          entity.readAsStringSync(),
    ].join('\n');
    expect(source, contains('showTaskMovedToTrashSnackBar('));
    expect(source, contains('restorePlan(task.plan.id)'));
    for (final contract in [
      'restoreAsset(asset.id)',
      'restoreRoom(room.id)',
      'restoreArea(area.id)',
    ]) {
      expect(source, contains(contract));
    }
    expect(
      RegExp(r'showMovedToTrashSnackBar\(').allMatches(source).length,
      greaterThanOrEqualTo(3),
    );
  });
}
