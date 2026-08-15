import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/utils/redacting_logger.dart';

void main() {
  group('Data Loss Prevention (DLP) Release Log Scanner', () {
    test('redactDiagnosticValue redacts sensitive keys and values', () {
      expect(redactDiagnosticValue('secret-value', key: 'token'), '[redacted]');
      expect(
        redactDiagnosticValue('secret-value', key: 'authorization'),
        '[redacted]',
      );
      expect(
        redactDiagnosticValue('user@example.com', key: 'user'),
        '[redacted-email]',
      );
      expect(
        redactDiagnosticValue(
          'https://example.supabase.co/rest/v1/user_settings',
          key: 'url',
        ),
        '[redacted-url]',
      );
      expect(
        redactDiagnosticValue(
          '12345678-1234-4234-8234-123456789012',
          key: 'id',
        ),
        '[redacted-id]',
      );
      expect(
        redactDiagnosticValue(
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature',
          key: 'other',
        ),
        '[redacted-token]',
      );
      expect(
        redactDiagnosticValue(
          '/data/user/0/app.owntend.mobile/files/db.sqlite',
          key: 'file',
        ),
        '[redacted-path]',
      );
      expect(
        redactDiagnosticValue(
          r'C:\Users\User\AppData\Local\Temp\db.sqlite',
          key: 'file',
        ),
        '[redacted-path]',
      );
    });

    test(
      'AppLogger snapshot contains sanitized metadata without sensitive values',
      () {
        AppLogger.clearForTesting();
        AppLogger.info(
          'test_event',
          fields: {
            'clean_counter': 42,
            'user_token': 'secret-token-value',
            'target_url': 'https://example.supabase.co/rest/v1/user_settings',
            'raw_uuid': '12345678-1234-4234-8234-123456789012',
          },
        );

        final events = AppLogger.snapshot();
        expect(events.length, 1);
        final jsonStr = events.first.toJson().toString();

        expect(jsonStr.contains('secret-token-value'), isFalse);
        expect(jsonStr.contains('https://example.supabase.co'), isFalse);
        expect(
          jsonStr.contains('12345678-1234-4234-8234-123456789012'),
          isFalse,
        );
        expect(jsonStr.contains('[redacted]'), isTrue);
      },
    );
  });
}
