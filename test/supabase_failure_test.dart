import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/supabase/supabase_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('missing auth session is reported without raw JWT details', () {
    final failure = SupabaseFailure.from(
      const AuthException(
        'Session from session_id claim in JWT does not exist',
        code: 'session_not_found',
      ),
    );

    expect(failure.kind, SupabaseFailureKind.authentication);
    expect(
      failure.message,
      'This cloud session expired or was revoked. Your local data is safe.',
    );
    expect(failure.message, isNot(contains('session_id')));
  });

  test('maps a maintenance business conflict as terminal', () {
    final failure = SupabaseFailure.from(
      const PostgrestException(
        message:
            'The maintenance plan changed before this completion '
            'reached the cloud',
        code: 'PT409',
        details: null,
        hint: null,
      ),
    );

    expect(failure.kind, SupabaseFailureKind.conflict);
    expect(failure.retryable, isFalse);
    expect(
      failure.message,
      'This maintenance completion conflicts with newer cloud data.',
    );
  });

  test('keeps genuine serialization failures retryable', () {
    final failure = SupabaseFailure.from(
      const PostgrestException(
        message: 'could not serialize access due to concurrent update',
        code: '40001',
        details: null,
        hint: null,
      ),
    );

    expect(failure.kind, SupabaseFailureKind.conflict);
    expect(failure.retryable, isTrue);
    expect(failure.message, 'The cloud record changed on another device.');
  });

  test('keeps uniqueness conflicts retryable', () {
    final failure = SupabaseFailure.from(
      const PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
        details: null,
        hint: null,
      ),
    );

    expect(failure.kind, SupabaseFailureKind.conflict);
    expect(failure.retryable, isTrue);
  });

  test('maps PGRST116 (0 rows returned on update/delete) to conflict', () {
    final failure = SupabaseFailure.from(
      const PostgrestException(
        message: 'JSON object requested, multiple (or no) rows returned',
        code: 'PGRST116',
        details: 'The result contains 0 rows',
        hint: null,
      ),
    );

    expect(failure.kind, SupabaseFailureKind.conflict);
    expect(failure.retryable, isTrue);
  });

  test('classifies Data API column ACL drift as incompatible schema', () {
    final failure = SupabaseFailure.from(
      const PostgrestException(
        message: 'permission denied for table assets',
        code: '42501',
        details: 'record id asset-private-123',
        hint: 'Grant UPDATE privilege on the required columns.',
      ),
    );

    expect(failure.kind, SupabaseFailureKind.incompatibleSchema);
    expect(failure.retryable, isFalse);
    expect(failure.diagnosticCode, dataApiAclContractMismatchCode);
    expect(failure.sqlState, '42501');
    expect(failure.message, isNot(contains('assets')));
    expect(failure.safeDiagnosticFields(entity: 'asset', operation: 'UPDATE'), {
      'sync_entity': 'asset',
      'sync_operation': 'UPDATE',
      'diagnostic_code': dataApiAclContractMismatchCode,
      'sql_state': '42501',
    });
    expect(
      failure
          .safeDiagnosticFields(entity: 'asset', operation: 'UPDATE')
          .toString(),
      isNot(contains('asset-private-123')),
    );
  });

  test('keeps RLS ownership failures distinct from ACL drift', () {
    final failure = SupabaseFailure.from(
      const PostgrestException(
        message:
            'new row violates row-level security policy for table "assets"',
        code: '42501',
        details: null,
        hint: null,
      ),
    );

    expect(failure.kind, SupabaseFailureKind.permissionDenied);
    expect(failure.retryable, isFalse);
    expect(failure.diagnosticCode, isNull);
    expect(failure.sqlState, isNull);
  });

  test('recognizes a privilege-specific 42501 hint without persisting it', () {
    final failure = SupabaseFailure.from(
      const PostgrestException(
        message: 'insufficient privilege',
        code: '42501',
        details: null,
        hint: 'GRANT UPDATE privilege before retrying.',
      ),
    );

    expect(failure.kind, SupabaseFailureKind.incompatibleSchema);
    expect(failure.diagnosticCode, dataApiAclContractMismatchCode);
    expect(failure.message, isNot(contains('GRANT')));
  });
}
