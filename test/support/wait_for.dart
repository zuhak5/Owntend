import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// WP-015 (F-024): the single bounded async-condition wait used by sync
/// tests. It replaces per-file wall-clock busy-wait loops
/// (`while (DateTime.now().isBefore(deadline))`) with one generously-bounded,
/// sleep-free-when-satisfied helper so flakiness has exactly one place to be
/// tuned.
///
/// The condition is polled with short real-async yields; tests that can use
/// completers or stream `firstWhere` should prefer those. This helper exists
/// for state that only becomes observable through side effects (database
/// rows, log counters).
Future<void> waitFor(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String? because,
}) async {
  final sw = Stopwatch()..start();
  while (!await condition()) {
    if (sw.elapsed > timeout) {
      fail(
        because ??
            'Timed out after ${timeout.inSeconds}s waiting for a '
                'sync test condition.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
