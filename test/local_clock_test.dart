import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';

void main() {
  test('nextLocalClockDelay targets the next minute boundary', () {
    final now = DateTime(2026, 8, 30, 23, 59, 50, 400);

    expect(
      nextLocalClockDelay(now),
      const Duration(seconds: 9, milliseconds: 625),
    );
  });

  testWidgets('local clock emits the current injected wall time on resume', (
    tester,
  ) async {
    var current = DateTime(2026, 8, 30, 23, 59, 50);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localNowProvider.overrideWithValue(() => current)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) {
              final value = ref.watch(localClockProvider).value;
              return Text(value?.toIso8601String() ?? 'loading');
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('2026-08-30T23:59:50.000'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    current = DateTime(2026, 8, 31, 0, 0, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('2026-08-31T00:00:01.000'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
