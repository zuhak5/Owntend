import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/services/notification_service.dart';

void main() {
  group('notificationBackgroundAccountMatches (BUG-05)', () {
    test('allows background refresh for local unauthenticated users', () {
      final allowed = notificationBackgroundAccountMatches(
        sessionUserId: null,
        boundUserId: null,
        accountEnabled: false,
      );
      expect(allowed, isTrue);
    });

    test(
      'allows background refresh for empty string local unauthenticated users',
      () {
        final allowed = notificationBackgroundAccountMatches(
          sessionUserId: '   ',
          boundUserId: '',
          accountEnabled: false,
        );
        expect(allowed, isTrue);
      },
    );

    test(
      'rejects background refresh when session does not match bound user',
      () {
        final allowed = notificationBackgroundAccountMatches(
          sessionUserId: 'user-google-1',
          boundUserId: 'user-google-2',
          accountEnabled: true,
        );
        expect(allowed, isFalse);
      },
    );

    test('allows background refresh when session matches bound user and sync enabled', () {
      final allowed = notificationBackgroundAccountMatches(
        sessionUserId: 'user-google-1',
        boundUserId: 'user-google-1',
        accountEnabled: true,
      );
      expect(allowed, isTrue);
    });

    test('rejects background refresh when bound account has sync disabled', () {
      final allowed = notificationBackgroundAccountMatches(
        sessionUserId: 'user-google-1',
        boundUserId: 'user-google-1',
        accountEnabled: false,
      );
      expect(allowed, isFalse);
    });
  });
}
