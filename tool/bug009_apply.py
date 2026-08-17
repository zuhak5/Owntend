from pathlib import Path

source_path = Path('tool/bug009_patch.py')
source = source_path.read_text(encoding='utf-8')
start = source.index("payload_constant = r'''  static const _assetPhotoDeletePayloadExpression")
end_marker = "text = replace_once(text, anchor, payload_constant + anchor, 'photo delete payload constant')"
end = source.index(end_marker, start)

replacement = '''payload_constant = """  static const _assetPhotoDeletePayloadExpression = \'\'\'
CASE
  WHEN (SELECT bound_user_id FROM sync_account WHERE id = 1) IS NULL THEN NULL
  WHEN lower(OLD.relative_path) LIKE '%.jpeg' THEN json_object(
    'cleanup_object_path',
    (SELECT bound_user_id FROM sync_account WHERE id = 1) ||
      '/assets/' || OLD.asset_id || '/' || OLD.id || '.jpg'
  )
  WHEN lower(OLD.relative_path) LIKE '%.jpg' THEN json_object(
    'cleanup_object_path',
    (SELECT bound_user_id FROM sync_account WHERE id = 1) ||
      '/assets/' || OLD.asset_id || '/' || OLD.id || '.jpg'
  )
  WHEN lower(OLD.relative_path) LIKE '%.png' THEN json_object(
    'cleanup_object_path',
    (SELECT bound_user_id FROM sync_account WHERE id = 1) ||
      '/assets/' || OLD.asset_id || '/' || OLD.id || '.png'
  )
  WHEN lower(OLD.relative_path) LIKE '%.webp' THEN json_object(
    'cleanup_object_path',
    (SELECT bound_user_id FROM sync_account WHERE id = 1) ||
      '/assets/' || OLD.asset_id || '/' || OLD.id || '.webp'
  )
  ELSE NULL
END
\'\'\';

"""
'''
fixed = source[:start] + replacement + source[end:]
compile(fixed, str(source_path), 'exec')
exec(compile(fixed, str(source_path), 'exec'), {'__name__': '__main__'})
