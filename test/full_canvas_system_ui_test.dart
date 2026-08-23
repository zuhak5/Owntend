import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/ui/full_canvas_system_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FullCanvasSystemUi mounts and renders child cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FullCanvasSystemUi(child: Text('Full Canvas Content')),
      ),
    );

    expect(find.text('Full Canvas Content'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'StandardSystemUi mounts and restores standard system bars cleanly',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: StandardSystemUi(child: Text('Standard System Content')),
        ),
      );

      expect(find.text('Standard System Content'), findsOneWidget);
      await tester.pumpAndSettle();
    },
  );
}
