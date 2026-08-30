import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/features/monetization/monetization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('classifies allowlisted PostgreSQL validation rejection', () {
    final classified = classifyAuthoritativePostgrestException(
      const PostgrestException(message: 'INVALID_ASSET_PAYLOAD', code: '22023'),
    );

    expect(
      classified,
      isA<AuthoritativeRpcRejectionException>()
          .having(
            (error) => error.code,
            'code',
            AuthoritativeRpcRejectionCode.invalidPayload,
          )
          .having(
            (error) => error.serverCode,
            'serverCode',
            'INVALID_ASSET_PAYLOAD',
          ),
    );
  });

  test('classification requires both stable code and allowlisted message', () {
    const error = PostgrestException(
      message: 'INVALID_ASSET_PAYLOAD',
      code: 'PGRST003',
    );

    expect(classifyAuthoritativePostgrestException(error), same(error));
  });

  test('maps operation reuse to its dedicated conflict type', () {
    final classified = classifyAuthoritativePostgrestException(
      const PostgrestException(message: 'OPERATION_ID_REUSED', code: '23505'),
    );

    expect(classified, isA<OperationIdReusedException>());
  });

  test('maps auth and not-found responses to definitive safe categories', () {
    final auth = classifyAuthoritativePostgrestException(
      const PostgrestException(message: 'AUTH_REQUIRED', code: '42501'),
    );
    final missing = classifyAuthoritativePostgrestException(
      const PostgrestException(message: 'ASSET_NOT_FOUND', code: '23503'),
    );

    expect(
      (auth as AuthoritativeRpcRejectionException).code,
      AuthoritativeRpcRejectionCode.unauthenticated,
    );
    expect(
      (missing as AuthoritativeRpcRejectionException).code,
      AuthoritativeRpcRejectionCode.entityNotFound,
    );
  });
}
