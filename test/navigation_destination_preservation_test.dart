import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/features/navigation/app_navigation.dart';

void main() {
  group('WP-011 validatedNotificationRoute exact-segment matching', () {
    test('allows every documented root and the two-segment exception', () {
      expect(validatedNotificationRoute('/maintenance/plan-1'), isNotNull);
      expect(validatedNotificationRoute('/notifications'), isNotNull);
      expect(validatedNotificationRoute('/assets/thing/a-1'), isNotNull);
      expect(validatedNotificationRoute('/assets/room/r-1'), isNotNull);
      expect(validatedNotificationRoute('/calendar'), isNotNull);
      expect(validatedNotificationRoute('/search'), isNotNull);
      expect(validatedNotificationRoute('/settings'), isNotNull);
      expect(validatedNotificationRoute('/account'), isNotNull);
      expect(validatedNotificationRoute('/backup'), isNotNull);
      expect(validatedNotificationRoute('/trash'), isNotNull);
      expect(validatedNotificationRoute('/statistics'), isNotNull);
      expect(validatedNotificationRoute('/more'), isNotNull);
      expect(validatedNotificationRoute('/permissions/setup'), isNotNull);
    });

    test('rejects look-alike prefixes under exact-segment matching', () {
      expect(validatedNotificationRoute('/assets-anything'), isNull);
      expect(validatedNotificationRoute('/settings-malicious'), isNull);
      expect(validatedNotificationRoute('/permissions/setup-extra'), isNull);
      expect(validatedNotificationRoute('/permissions'), isNull);
    });

    test('rejects malformed payloads', () {
      expect(validatedNotificationRoute(''), isNull);
      expect(validatedNotificationRoute('   '), isNull);
      expect(validatedNotificationRoute('relative/path'), isNull);
      expect(validatedNotificationRoute('/home#fragment'), isNull);
      expect(validatedNotificationRoute('/unknown'), isNull);
    });
  });

  group('WP-011 PendingNotificationRoute', () {
    test('take() consumes exactly once', () {
      PendingNotificationRoute.pending = '/assets/thing/a-1';
      expect(PendingNotificationRoute.take(), '/assets/thing/a-1');
      expect(PendingNotificationRoute.take(), isNull);
    });
  });
}
