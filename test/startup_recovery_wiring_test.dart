import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authenticated startup recovers charges before cached readiness', () {
    final source = File(
      'lib/src/features/startup/presentation/startup_bootstrap.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    const recoveryCall =
        'await _recoverPendingChargedOperations(session, generation);';
    const cachedReadyShortcut =
        'final offlineSnapshot = _offlineSnapshotCandidate;';

    expect(source, contains(recoveryCall));
    expect(source, contains(cachedReadyShortcut));
    expect(
      source.indexOf(recoveryCall),
      lessThan(source.indexOf(cachedReadyShortcut)),
    );
    expect(
      source,
      contains('final resolver = _ref.read(chargedOperationResolverProvider);'),
    );
    expect(
      source,
      contains('await resolver.resolvePendingOperations(session.userId);'),
    );
  });
}
