import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// WP-009 (F-016, F-017): feature import-boundary contract.
///
/// Cross-feature imports must stay one-directional. The single allowlisted
/// exception is the assets↔maintenance pair: thing detail screens embed task
/// actions while task screens open the owning thing's editors — a deliberate,
/// documented coupling of two views over the same domain objects. Any NEW
/// bidirectional pair fails this test and must be broken by hoisting shared
/// code into `lib/src/ui/` or an application-layer module.
void main() {
  const features = [
    'assets',
    'auth',
    'backup',
    'dashboard',
    'maintenance',
    'monetization',
    'more',
    'navigation',
    'notifications',
    'permissions',
    'rooms',
    'search',
    'settings',
    'startup',
    'statistics',
    'trash',
  ];

  /// Bidirectional pairs the architecture explicitly permits.
  const allowedBidirectional = <String, String>{
    'assets<->maintenance':
        'thing detail embeds task actions; task detail opens the owning '
        "thing's editor flows (WP-009 decision, see implementation "
        'report)',
  };

  test('no undocumented bidirectional feature-import pairs exist', () async {
    final edges = <String>{};
    final files = Directory('lib/src/features')
        .listSync(recursive: true)
        .whereType<File>();
    for (final entry in files) {
      if (!entry.path.endsWith('.dart')) continue;
      final normalized = entry.path.replaceAll('\\', '/');
      final from = features.firstWhere(
        (f) => normalized.contains('/features/$f/'),
        orElse: () => '',
      );
      if (from.isEmpty) continue;
      final content = File(entry.path).readAsStringSync();
      for (final match in RegExp(
        "import ['\"]((?:\\./|\\.\\./)+)+(\\w+)/",
      ).allMatches(content)) {
        // Only relative imports that climb out of this feature directory.
        final climb = match.group(1)!;
        if (!climb.contains('../../') && !climb.contains('../../../')) {
          if (!climb.startsWith('../')) continue;
        }
        final to = match.group(2)!;
        if (to == from || !features.contains(to)) continue;
        edges.add('$from->$to');
      }
    }
    expect(edges, isNotEmpty, reason: 'sanity: imports were discovered');

    final violations = <String>[];
    for (final edge in edges) {
      final parts = edge.split('->');
      final reverse = '${parts[1]}->${parts[0]}';
      if (!edges.contains(reverse)) continue;
      final key = parts[0].compareTo(parts[1]) < 0
          ? '${parts[0]}<->${parts[1]}'
          : '${parts[1]}<->${parts[0]}';
      if (!allowedBidirectional.containsKey(key)) {
        violations.add(edge);
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'New bidirectional feature cycles found. Break them by hoisting '
          'shared code into lib/src/ui/widgets or an application-layer '
          'module, or extend allowedBidirectional with explicit rationale.',
    );
  });

  test(
    'the god barrel no longer exports other features\u2019 internals',
    () async {
      final barrel = await File('lib/src/ui/presentation_support.dart')
          .readAsString();
      for (final forbidden in [
        'features/maintenance/',
        'features/auth/',
        'features/monetization/',
        'features/permissions/',
        'features/assets/',
        'features/dashboard/',
        'features/trash/',
        'features/notifications/',
      ]) {
        expect(
          barrel.contains(forbidden),
          isFalse,
          reason:
              'presentation_support.dart must export only lib/src/ui '
              'primitives; found $forbidden',
        );
      }
    },
  );
}
