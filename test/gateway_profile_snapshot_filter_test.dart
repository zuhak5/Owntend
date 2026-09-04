import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/sync/supabase_sync_gateway.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';

void main() {
  group('SupabaseSyncGateway Snapshot Key Filter (BUG-07)', () {
    test('returns empty filter string for entities without keyColumns (profileSyncSpec)', () {
      expect(profileSyncSpec.keyColumns, isEmpty);
      final filter = SupabaseSyncGateway.computeKeyOnlyFilter(
        profileSyncSpec,
        'profile',
      );
      expect(filter, isEmpty);
    });

    test('generates compound comparator when entity has keyColumns', () {
      final specWithKeys = syncSpecByEntity['asset_tag']!;
      expect(specWithKeys.keyColumns.length, 2);
      final filter = SupabaseSyncGateway.computeKeyOnlyFilter(
        specWithKeys,
        'valA|valB',
      );
      expect(filter, isNotEmpty);
      expect(filter, contains('asset_id.gt.valA'));
      expect(filter, contains('asset_id.eq.valA,tag_id.gt.valB'));
    });
  });
}
