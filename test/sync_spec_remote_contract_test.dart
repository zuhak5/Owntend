import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';

void main() {
  test('asset photo remote selection exposes only server columns', () {
    final spec = syncSpecByEntity['asset_photo']!;
    expect(spec.localOnlyColumns, contains('relative_path'));
    expect(spec.remoteDataColumns, contains('object_path'));
    expect(spec.remoteDataColumns, isNot(contains('relative_path')));
    expect(spec.selectClause, contains('object_path'));
    expect(spec.selectClause, isNot(contains('relative_path')));
  });

  test('local-only columns never leak into outgoing write payloads', () {
    final spec = syncSpecByEntity['asset_photo']!;
    const userId = 'user-1';
    final record = SyncRecord(
      spec: spec,
      recordKey: 'photo-1',
      values: {
        'id': 'photo-1',
        'asset_id': 'asset-1',
        'relative_path': 'photos/asset-1/photo-1.jpg',
        'cloud_object_path': '$userId/media/asset-1/photo-1.jpg',
        'caption': 'Front view',
        'is_primary': true,
        'created_at': '2026-01-01T00:00:00.000Z',
      },
      clientModifiedAt: DateTime.utc(2026, 1, 1),
    );

    final payload = record.toRemoteCreatePayload(userId);

    expect(payload, isNot(contains('relative_path')));
    expect(payload['object_path'], '$userId/media/asset-1/photo-1.jpg');
    expect(payload['caption'], 'Front view');
  });

  test('every sync spec round-trips its keys through remote columns', () {
    for (final spec in [...syncEntitySpecs, profileSyncSpec]) {
      for (final column in spec.remoteDataColumns) {
        expect(
          spec.localColumns,
          contains(spec.localColumnFor(column)),
          reason: '${spec.entity}: $column must map back to a local column',
        );
      }
      for (final key in spec.keyColumns) {
        expect(
          spec.remoteDataColumns,
          contains(spec.remoteColumnFor(key)),
          reason:
              '${spec.entity}: key column $key missing from remote selection',
        );
      }
    }
  });
}
