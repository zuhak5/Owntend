from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected one match, found {count}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8')


replace_once(
    'lib/src/core/database/app_database.dart',
    """  Future<void> _createSearchIndex() async {
    await customStatement(
      'CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5('
      'entity_type UNINDEXED, entity_id UNINDEXED, title, body)',
    );
  }
""",
    """  Future<void> _createSearchIndex() async {
    final existing = await customSelect(
      \"SELECT sql FROM sqlite_master \"
      \"WHERE type = 'table' AND name = 'search_index'\",
    ).getSingleOrNull();
    if (existing != null) {
      final definition = existing.read<String>('sql');
      if (!definition.contains('display_body') ||
          !definition.contains('search_terms')) {
        // The FTS table is a derived cache. Recreate legacy layouts instead of
        // carrying machine aliases in the user-visible snippet column.
        await customStatement('DROP TABLE search_index');
      }
    }
    await customStatement(
      'CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5('
      'entity_type UNINDEXED, entity_id UNINDEXED, title, '
      'display_body, search_terms)',
    );
  }
""",
)

replace_once(
    'test/database_migration_test.dart',
    """      expect(rows, hasLength(1));
      expect(rows.first.read<String>('sql'), contains('fts5'));
""",
    """      expect(rows, hasLength(1));
      final definition = rows.first.read<String>('sql');
      expect(definition, contains('fts5'));
      expect(definition, contains('display_body'));
      expect(definition, contains('search_terms'));
""",
)

replace_once(
    'docs/development/localization-and-rtl.md',
    "Search indexes include English and Arabic aliases for controlled values so either language can discover the same canonical record without translating persisted data. Controlled search results must render through the same localized presenters used by the rest of the UI.",
    "Search indexes include English and Arabic aliases for controlled values so either language can discover the same canonical record without translating persisted data. User-authored display text and machine search aliases live in separate FTS columns, so snippets never expose canonical aliases merely because an Arabic synonym matched. Controlled search results must render through the same localized presenters used by the rest of the UI.",
)

print('Search index schema hardening applied.')
