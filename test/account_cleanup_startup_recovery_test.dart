import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';

void main() {
  test('unsafe pending cleanup blocks deferred startup before cloud bootstrap', () {
    final source = File(
      'lib/src/features/startup/presentation/startup_bootstrap.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('if (!await _resumePendingAccountCleanup()) return;'),
    );
    expect(source, contains('account_deletion_local_cleanup_resume_blocked'));
    expect(source, contains('accountCleanupBlocked: true'));
    expect(source, contains('_retryPendingAccountCleanup'));
  });

  testWidgets('blocked cleanup startup state exposes an explicit retry', (
    tester,
  ) async {
    var retries = 0;

    await tester.pumpWidget(
      OwntendStartupFailure(
        accountCleanupBlocked: true,
        onRetry: () async {
          retries++;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(retries, 1);
  });
}
