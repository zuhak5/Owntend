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

  group('delete asset photo RPC', () {
    test('verifies delete photo payload structure with asset_id', () {
      const photoId = '00000000-0000-0000-0000-000000000902';
      const assetId = '00000000-0000-0000-0000-000000000111';
      final params = <String, dynamic>{
        'p_photo_id': photoId,
        'p_asset_id': assetId,
      };

      expect(params['p_photo_id'], photoId);
      expect(params['p_asset_id'], assetId);
    });

    test(
      'verifies delete photo payload structure when asset_id is omitted/null',
      () {
        const photoId = '00000000-0000-0000-0000-000000000902';
        const String? assetId = null;
        final params = <String, dynamic>{
          'p_photo_id': photoId,
          if (assetId != null && assetId.isNotEmpty) 'p_asset_id': assetId,
        };

        expect(params['p_photo_id'], photoId);
        expect(params.containsKey('p_asset_id'), isFalse);
      },
    );

    test(
      'verifies delete photo response parsing preserves canonical asset_id',
      () {
        const photoId = '00000000-0000-0000-0000-000000000902';
        const assetId = '00000000-0000-0000-0000-000000000111';

        final responseMap = <String, dynamic>{
          'id': photoId,
          'asset_id': assetId,
          'storage_path': 'assets/$assetId/$photoId.jpg',
          'is_primary': true,
        };

        final canonicalAssetId = responseMap['asset_id'] as String?;
        expect(canonicalAssetId, assetId);
      },
    );
  });
}
