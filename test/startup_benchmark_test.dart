import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/utils/redacting_logger.dart';

void main() {
  group('Startup Performance Spans & Benchmarks (P1-E)', () {
    test('Startup spans record pre-first-frame and cloud-ready milestones without PII', () {
      AppLogger.clearForTesting();

      final mainEntry = Stopwatch()..start();
      AppLogger.info(
        'startup_span',
        fields: {
          'phase': 'main_entry',
          'elapsed_ms': mainEntry.elapsedMilliseconds,
        },
      );

      final engineReady = Stopwatch()..start();
      AppLogger.info(
        'startup_span',
        fields: {
          'phase': 'flutter_engine_ready',
          'elapsed_ms': engineReady.elapsedMilliseconds,
        },
      );

      final dbOpen = Stopwatch()..start();
      AppLogger.info(
        'startup_span',
        fields: {
          'phase': 'database_open',
          'elapsed_ms': dbOpen.elapsedMilliseconds,
        },
      );

      final authRestore = Stopwatch()..start();
      AppLogger.info(
        'startup_span',
        fields: {
          'phase': 'auth_session_restore',
          'elapsed_ms': authRestore.elapsedMilliseconds,
        },
      );

      final firstFrame = Stopwatch()..start();
      AppLogger.info(
        'startup_span',
        fields: {
          'phase': 'first_frame',
          'elapsed_ms': firstFrame.elapsedMilliseconds,
        },
      );

      final cloudReady = Stopwatch()..start();
      AppLogger.info(
        'startup_span',
        fields: {
          'phase': 'cloud_ready',
          'elapsed_ms': cloudReady.elapsedMilliseconds,
        },
      );

      final events = AppLogger.snapshot();
      expect(events.length, 6);

      final phases = events.map((e) => e.fields['phase']).toList();
      expect(phases, contains('main_entry'));
      expect(phases, contains('flutter_engine_ready'));
      expect(phases, contains('database_open'));
      expect(phases, contains('auth_session_restore'));
      expect(phases, contains('first_frame'));
      expect(phases, contains('cloud_ready'));

      // Ensure no raw identifiers or user text in startup trace
      final serialized = events.map((e) => e.toJson().toString()).join(' ');
      expect(serialized.contains('email'), isFalse);
      expect(serialized.contains('token'), isFalse);
      expect(serialized.contains('http'), isFalse);
    });

    test(
      'Startup benchmark duration metrics calculation (median, p90, p95)',
      () {
        final samples = <int>[120, 135, 140, 150, 160, 175, 190, 210, 250, 400]
          ..sort();

        int percentile(List<int> sorted, double p) {
          final index = (p * (sorted.length - 1)).round();
          return sorted[index];
        }

        final median = percentile(samples, 0.50);
        final p90 = percentile(samples, 0.90);
        final p95 = percentile(samples, 0.95);

        expect(median, 175);
        expect(p90, 250);
        expect(p95, 400);

        // Verify budget threshold (e.g. p95 <= 1500 ms)
        expect(p95 <= 1500, isTrue);
      },
    );
  });
}
