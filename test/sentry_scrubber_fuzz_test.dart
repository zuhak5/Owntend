import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/observability/sentry_event_scrubber.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Property-style fuzz coverage for the Sentry scrubber (WP-017).
///
/// Arbitrary hostile payloads — user names, emails, room and asset names,
/// filesystem paths, bearer tokens, raw URLs, and nested unknown objects —
/// must never survive into tags, extras, breadcrumbs, messages, or exception
/// values outside the strict allowlist.
// ignore_for_file: deprecated_member_use

void main() {
  const hostileValues = <String>[
    'Zuhayr Abd Al-Rahman',
    'user@example.com',
    'user+tag@sub.example.co.uk',
    r'C:\Users\alice\Documents\photos\vaction.jpg',
    '/home/bob/private/notes.txt',
    'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMifQ.sig',
    'https://example.supabase.co/rest/v1/assets?select=*',
    'Living Room Thermostat warranty until 2027',
    'postgresql://postgres:hunter2@db.local:5432/owntend',
    'recovery_key=AaaaaaaaBbbbbbbbCccccccccDddddddddEeeeeeeeee43',
  ];

  SentryEvent baseEvent() =>
      SentryEvent(message: SentryMessage('seed'), level: SentryLevel.error);

  group('scrubSentryEvent fuzz properties', () {
    test(
      'drops user, request, and server identity on arbitrary events',
      () async {
        for (final hostile in hostileValues) {
          final event = baseEvent()
            ..user = SentryUser(id: hostile, username: hostile, email: hostile)
            ..request = SentryRequest(url: hostile)
            ..serverName = hostile;

          final result = (await scrubSentryEvent(event, Hint()))!;

          expect(result.user, isNull, reason: hostile);
          expect(result.request, isNull, reason: hostile);
          expect(result.serverName, isNull, reason: hostile);
        }
      },
    );

    test('keeps only allowlisted tags', () async {
      for (final hostile in hostileValues) {
        final event = baseEvent()
          ..tags = {
            'operation': 'sync.pull',
            'room_name': hostile,
            'email': hostile,
            'unknown_tag': hostile,
          };

        final result = (await scrubSentryEvent(event, Hint()))!;

        expect(result.tags!.containsKey('room_name'), isFalse, reason: hostile);
        expect(result.tags!.containsKey('email'), isFalse, reason: hostile);
        expect(
          result.tags!.containsKey('unknown_tag'),
          isFalse,
          reason: hostile,
        );
        // Allowlisted technical tags survive.
        expect(result.tags!['operation'], 'sync.pull');
      }
    });

    test('keeps only allowlisted extras', () async {
      for (final hostile in hostileValues) {
        final event = baseEvent()
          ..extra = {
            'attempt': 3,
            'raw_response': hostile,
            'file_path': hostile,
          };

        final result = (await scrubSentryEvent(event, Hint()))!;

        expect(result.extra!.containsKey('raw_response'), isFalse);
        expect(result.extra!.containsKey('file_path'), isFalse);
        expect(result.extra!['attempt'], 3);
      }
    });

    test(
      'sanitizes breadcrumbs to allowlisted data keys without messages',
      () async {
        for (final hostile in hostileValues) {
          final event = baseEvent()
            ..breadcrumbs = [
              Breadcrumb(message: hostile, timestamp: DateTime.now()),
              Breadcrumb(
                category: 'http',
                data: {'url': hostile, 'response_body': hostile},
                timestamp: DateTime.now(),
              ),
            ];

          final result = (await scrubSentryEvent(event, Hint()))!;

          for (final breadcrumb in result.breadcrumbs ?? const <Breadcrumb>[]) {
            expect(breadcrumb.message, isNull, reason: hostile);
            for (final key in breadcrumb.data?.keys ?? const <String>{}) {
              expect(allowedSentryExtras.contains(key), isTrue, reason: key);
            }
          }
        }
      },
    );

    test('exception values are replaced by bounded type-only text', () async {
      for (final hostile in hostileValues) {
        final event = baseEvent()
          ..exceptions = [
            SentryException(type: 'StateError', value: 'Bad state: $hostile'),
          ];

        final result = (await scrubSentryEvent(event, Hint()))!;

        final value = result.exceptions!.single.value ?? '';
        expect(value.contains(hostile), isFalse, reason: hostile);
      }
    });

    test('unknown protocol fields are always cleared', () async {
      final event = baseEvent();
      // ignore: invalid_use_of_internal_member
      event.unknown?['fingerprint_user'] = 'someone';
      // ignore: invalid_use_of_internal_member
      event.unknown?['token'] = 'abc';

      final result = (await scrubSentryEvent(event, Hint()))!;
      // ignore: invalid_use_of_internal_member
      expect(result.unknown ?? const <String, dynamic>{}, isEmpty);
    });
  });
}
