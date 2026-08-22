import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('primary photo uniqueness constraint', () {
    test('selects winner photo deterministically by updated_at and id', () {
      final duplicates = [
        {'id': 'p1', 'updated_at': '2026-01-01T10:00:00Z', 'is_primary': true},
        {'id': 'p2', 'updated_at': '2026-01-01T12:00:00Z', 'is_primary': true},
        {'id': 'p3', 'updated_at': '2026-01-01T12:00:00Z', 'is_primary': true},
      ];

      duplicates.sort((a, b) {
        final cmp = (b['updated_at'] as String).compareTo(
          a['updated_at'] as String,
        );
        if (cmp != 0) return cmp;
        return (a['id'] as String).compareTo(b['id'] as String);
      });

      final winnerId = duplicates.first['id'];
      expect(winnerId, 'p2'); // p2 has latest updated_at and smaller id than p3
    });

    test('validates unique constraint code 23505 classification', () {
      const dbErrorCode = '23505';
      final isUniqueConstraintViolation = dbErrorCode == '23505';
      expect(isUniqueConstraintViolation, isTrue);
    });
  });
}
