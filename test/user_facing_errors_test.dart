import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/utils/user_facing_errors.dart';

void main() {
  test('database lock errors become actionable user-facing text', () {
    final message = userFacingErrorMessage(
      Exception(
        'SqliteException(5): database is locked, database is locked '
        'UPDATE sync_runtime SET suppress_outbox = 0',
      ),
    );

    expect(message, contains('local database operation'));
    expect(message, isNot(contains('UPDATE sync_runtime')));
    expect(message, isNot(contains('SqliteException')));
  });

  test('raw sql errors are replaced by the supplied fallback', () {
    final message = userFacingErrorMessage(
      Exception('SqliteException: near "UPDATE": syntax error'),
      fallback: 'Could not refresh items.',
    );

    expect(message, 'Could not refresh items.');
  });

  test('ordinary domain errors are preserved', () {
    expect(
      userFacingErrorMessage(Exception('Cloud sync is unavailable.')),
      'Cloud sync is unavailable.',
    );
  });
}
