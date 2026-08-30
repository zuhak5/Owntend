import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';

void main() {
  test(
    'unsafe pending cleanup blocks deferred startup before cloud bootstrap',
    () {
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
    },
  );

  test('successful sign-out completion cannot resume account-scoped work', () {
    final startup = File(
      'lib/src/features/startup/presentation/startup_bootstrap.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final sync = File('lib/src/core/sync/sync_coordinator.dart')
        .readAsStringSync();

    expect(
      startup,
      contains(
        'final session = ref\n                      .read(authRepositoryProvider)',
      ),
    );
    expect(
      startup,
      contains('await coordinator?.completeAccountSignOut(userId);'),
    );
    expect(startup, contains('await cancelAccountScopedBackgroundWork();'));

    final completionStart = sync.indexOf(
      '  Future<void> completeAccountSignOut(String userId) {',
    );
    final rollbackStart = sync.indexOf(
      '  Future<void> cancelAccountDeletion(String userId) {',
      completionStart,
    );
    expect(completionStart, greaterThanOrEqualTo(0));
    expect(rollbackStart, greaterThan(completionStart));

    final completion = sync.substring(completionStart, rollbackStart);
    expect(
      completion,
      contains("_advanceAccountEpoch('account_sign_out_completed')"),
    );
    expect(completion, contains('_cancelScheduledSyncWork();'));
    expect(completion, contains('await _stopRealtime();'));
    expect(completion, isNot(contains('configureBackgroundSync')));
    expect(completion, isNot(contains('_ensureRealtime')));
    expect(completion, isNot(contains('_scheduleAutomaticSync')));
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

  test('cloud bootstrap failures remain blocking until an explicit retry', () {
    final source = File(
      'lib/src/features/startup/presentation/startup_bootstrap.dart',
    ).readAsStringSync();

    expect(source, contains('_cloudInitializationFailure = error'));
    expect(source, contains('cloudUnavailable: true'));
    expect(source, contains('_retryCloudInitialization'));
    expect(
      source,
      isNot(contains('_supabaseClient = client;\n      _ready = true')),
    );
  });

  testWidgets('cloud startup failure surface exposes an explicit retry', (
    tester,
  ) async {
    var retries = 0;

    await tester.pumpWidget(
      OwntendStartupFailure(
        cloudUnavailable: true,
        onRetry: () async {
          retries++;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Cloud services are unavailable. Please try again later.'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(retries, 1);
  });
}
