from pathlib import Path

source_path = Path('tool/bug009_patch.py')
source = source_path.read_text(encoding='utf-8')

start = source.index("payload_constant = r'''  static const _assetPhotoDeletePayloadExpression")
end_marker = "text = replace_once(text, anchor, payload_constant + anchor, 'photo delete payload constant')"
end = source.index(end_marker, start)
payload_replacement = '''payload_constant = """  static const _assetPhotoDeletePayloadExpression = \'\'\'
CASE
  WHEN (SELECT bound_user_id FROM sync_account WHERE id = 1) IS NULL THEN NULL
  WHEN lower(OLD.relative_path) LIKE '%.jpeg' THEN json_object('cleanup_object_path', (SELECT bound_user_id FROM sync_account WHERE id = 1) || '/assets/' || OLD.asset_id || '/' || OLD.id || '.jpg')
  WHEN lower(OLD.relative_path) LIKE '%.jpg' THEN json_object('cleanup_object_path', (SELECT bound_user_id FROM sync_account WHERE id = 1) || '/assets/' || OLD.asset_id || '/' || OLD.id || '.jpg')
  WHEN lower(OLD.relative_path) LIKE '%.png' THEN json_object('cleanup_object_path', (SELECT bound_user_id FROM sync_account WHERE id = 1) || '/assets/' || OLD.asset_id || '/' || OLD.id || '.png')
  WHEN lower(OLD.relative_path) LIKE '%.webp' THEN json_object('cleanup_object_path', (SELECT bound_user_id FROM sync_account WHERE id = 1) || '/assets/' || OLD.asset_id || '/' || OLD.id || '.webp')
  ELSE NULL
END
\'\'\';

"""
'''
source = source[:start] + payload_replacement + source[end:]

patch_start = source.index(
    'old = """      for (var index = 0; index < spec.keyColumns.length; index++) {',
    source.index("path = Path('lib/src/core/sync/local_sync_store.dart')"),
)
marker = "text = replace_once(text, old, new, 'delete tombstone hydration')"
patch_end = source.index(marker, patch_start) + len(marker)
replacement = '''old = """      if (spec.entity != 'profile') {
        final keyParts = mutation.recordKey.split('|');
        for (var index = 0; index < spec.keyColumns.length; index++) {
          values[spec.keyColumns[index]] = keyParts[index];
        }
      }
      return SyncRecord(
        spec: spec,
"""
new = """      if (spec.entity != 'profile') {
        final keyParts = mutation.recordKey.split('|');
        for (var index = 0; index < spec.keyColumns.length; index++) {
          values[spec.keyColumns[index]] = keyParts[index];
        }
      }
      if (spec.entity == 'asset_photo') {
        final cleanupObjectPath = _photoDeleteCleanupObjectPath(mutation);
        if (cleanupObjectPath != null) {
          values['cleanup_object_path'] = cleanupObjectPath;
        }
      }
      return SyncRecord(
        spec: spec,
"""
text = replace_once(text, old, new, 'delete tombstone hydration')'''
source = source[:patch_start] + replacement + source[patch_end:]

compiled = compile(source, str(source_path), 'exec')
exec(compiled, {'__name__': '__main__'})
