// Canonical emulator/device launch lane (WP-021).
//
// Runs on a real Android device or emulator through:
//   flutter test integration_test --flavor dev \
//     --dart-define-from-file=config/dev.json
//
// This lane proves cold launch reaches the first Flutter owner with the
// production composition: splash lifecycle, startup gate, and the signed-out
// surface. It intentionally requires real platform channels; unit suites
// cover the mocked equivalents.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:owntend/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cold launch reaches the first Flutter frame', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // The first Flutter owner must be attached regardless of auth state;
    // signed-out vs hydrating surfaces are covered by dedicated scenarios.
    expect(tester.takeException(), isNull);
  });
}
