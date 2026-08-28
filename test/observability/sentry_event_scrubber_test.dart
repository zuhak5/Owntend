// ignore_for_file: deprecated_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/observability/sentry_event_scrubber.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  test('removes identity, request data, unsafe fields, and raw messages', () {
    final stackTrace = SentryStackTrace(
      frames: [
        SentryStackFrame(
          absPath: r'C:\Users\person\owntend\lib\secret.dart',
          fileName: r'C:\Users\person\owntend\lib\secret.dart',
          function: 'loadHome',
          lineNo: 42,
          vars: {'email': 'person@example.com'},
        ),
      ],
    );
    final event = SentryEvent(
      user: SentryUser(
        id: '7f66f02e-6b71-4adb-a7ba-b962c837b131',
        ipAddress: '203.0.113.42',
      ),
      request: SentryRequest(
        url: 'https://example.com/path?token=secret',
        headers: {'Authorization': 'Bearer secret'},
        data: {'email': 'person@example.com'},
      ),
      message: SentryMessage(
        'Failure for person@example.com at '
        r'C:\Users\person\backup.zip',
      ),
      tags: {'app_environment': 'prod', 'unknown': 'person@example.com'},
      extra: {
        'elapsed_ms': 12,
        'attempt': 2,
        'unknown': 'eyJabcdefghijklmnopqrstuvwxyz',
      },
      contexts: Contexts()
        ..['account'] = {'email': 'person@example.com'}
        ..['geo'] = {'city': 'Private city', 'country_code': 'XX'}
        ..['network'] = {'ip_address': '203.0.113.42'},
      exceptions: [
        SentryException(
          type: 'StateError',
          value: 'user 7f66f02e-6b71-4adb-a7ba-b962c837b131 failed',
          module: r'C:\Users\person\owntend',
          stackTrace: stackTrace,
        ),
      ],
    );

    final scrubbed = scrubSentryEvent(event, Hint()) as SentryEvent;

    expect(scrubbed.user, isNull);
    expect(scrubbed.request, isNull);
    expect(scrubbed.tags, {'app_environment': 'prod'});
    expect(scrubbed.extra, {'elapsed_ms': 12, 'attempt': 2});
    expect(scrubbed.contexts.containsKey('account'), isFalse);
    expect(scrubbed.contexts.containsKey('geo'), isFalse);
    expect(scrubbed.contexts.containsKey('network'), isFalse);
    expect(scrubbed.message?.formatted, 'Owntend exception');
    expect(scrubbed.exceptions!.single.type, 'StateError');
    expect(scrubbed.exceptions!.single.value, 'Owntend StateError');
    expect(scrubbed.exceptions!.single.module, isNull);
    final frame = scrubbed.exceptions!.single.stackTrace!.frames.single;
    expect(frame.absPath, isNull);
    expect(frame.fileName, 'package:owntend/secret.dart');
    expect(frame.function, 'loadHome');
    expect(frame.lineNo, 42);
    expect(frame.toJson(), isNot(contains('vars')));
  });

  test('preserves technical exception messages and package URIs', () {
    final stackTrace = SentryStackTrace(
      frames: [
        SentryStackFrame(
          fileName: 'package:sentry_flutter/sentry_flutter.dart',
          function: 'init',
          lineNo: 10,
        ),
        SentryStackFrame(
          fileName: 'dart:async/zone.dart',
          function: '_run',
          lineNo: 50,
        ),
      ],
    );
    final event = SentryEvent(
      exceptions: [
        SentryException(
          type: 'StateError',
          value: 'Database constraint violation on check',
          stackTrace: stackTrace,
        ),
      ],
    );

    final scrubbed = scrubSentryEvent(event, Hint()) as SentryEvent;

    expect(
      // WP-017 hardening: exception payloads never reach Sentry; only the
      // sanitized exception type survives.
      scrubbed.exceptions!.single.value,
      'Owntend StateError',
    );
    final frames = scrubbed.exceptions!.single.stackTrace!.frames;
    expect(frames[0].fileName, 'package:sentry_flutter/sentry_flutter.dart');
    expect(frames[1].fileName, 'dart:async/zone.dart');
  });

  test('clears unknown protocol fields without dropping crash event', () {
    final event = SentryEvent(
      unknown: {'future_protocol_extension': 'test'},
      exceptions: [
        SentryException(
          type: 'StateError',
          value: 'Critical database deadlock',
        ),
      ],
    );

    final scrubbed = scrubSentryEvent(event, Hint()) as SentryEvent;

    expect(scrubbed, isNotNull);
    // ignore: invalid_use_of_internal_member
    expect(scrubbed.unknown, isEmpty);
    expect(scrubbed.exceptions!.single.value, 'Owntend StateError');
  });

  test('drops HTTP and UI breadcrumbs but preserves sanitized app events', () {
    final event = SentryEvent(
      breadcrumbs: [
        Breadcrumb.http(
          url: Uri.parse('https://example.com?q=secret'),
          method: 'GET',
        ),
        Breadcrumb.userInteraction(subCategory: 'click', message: 'Room name'),
        Breadcrumb(
          category: 'owntend',
          message: 'sync started',
          data: {
            'event': 'sync_start_manual',
            'attempt': 2,
            'email': 'person@example.com',
          },
        ),
      ],
    );

    final scrubbed = scrubSentryEvent(event, Hint()) as SentryEvent;

    expect(scrubbed.breadcrumbs, hasLength(1));
    expect(scrubbed.breadcrumbs!.single.category, 'owntend');
    expect(scrubbed.breadcrumbs!.single.message, 'sync_started');
    expect(scrubbed.breadcrumbs!.single.data, {
      'event': 'sync_start_manual',
      'attempt': 2,
    });
  });

  test('drops recoverable operational events', () {
    final event = SentryEvent(tags: {'failure_kind': 'offline'});

    expect(scrubSentryEvent(event, Hint()), isNull);
  });
}
