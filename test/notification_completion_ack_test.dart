import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notification completion acknowledges only confirmed success', () {
    final source = File(
      'lib/src/features/notifications/presentation/notifications_screen.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    final methodStart = source.indexOf(
      'Future<void> _completeFromNotification(',
    );
    final methodEnd = source.indexOf(
      '\n  Future<void> _openNotification(',
      methodStart,
    );

    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));

    final method = source.substring(methodStart, methodEnd);
    final completionCall = method.indexOf(
      'final completed = await completeTaskWithFeedback(',
    );
    final failureGuard = method.indexOf('if (!completed) {');
    final failureReturn = method.indexOf('return;', failureGuard);
    final markRead = method.indexOf('.markRead(item.id);');

    expect(completionCall, greaterThanOrEqualTo(0));
    expect(failureGuard, greaterThan(completionCall));
    expect(failureReturn, greaterThan(failureGuard));
    expect(markRead, greaterThan(failureReturn));
    expect(RegExp(r'\.markRead\(item\.id\);').allMatches(method).length, 1);
  });
}
