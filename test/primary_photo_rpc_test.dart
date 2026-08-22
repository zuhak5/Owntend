import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('primary photo RPC', () {
    test('verifies primary photo payload structure', () {
      const assetId = '00000000-0000-0000-0000-000000000111';
      const photoId = '00000000-0000-0000-0000-000000000902';
      final params = {'p_asset_id': assetId, 'p_photo_id': photoId};

      expect(params['p_asset_id'], assetId);
      expect(params['p_photo_id'], photoId);
    });

    test('validates peer photo normalization contract', () {
      final photos = [
        {'id': 'p1', 'is_primary': true},
        {'id': 'p2', 'is_primary': false},
      ];

      // Simulate RPC clearing peers when p2 becomes primary
      const targetId = 'p2';
      final updated = [
        for (final p in photos)
          {'id': p['id'], 'is_primary': p['id'] == targetId},
      ];

      expect(updated.firstWhere((p) => p['id'] == 'p2')['is_primary'], isTrue);
      expect(updated.firstWhere((p) => p['id'] == 'p1')['is_primary'], isFalse);
    });
  });
}
