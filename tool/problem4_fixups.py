from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: Path | str) -> str:
    return (ROOT / path).read_text(encoding='utf-8') if isinstance(path, str) else path.read_text(encoding='utf-8')


def write(path: Path | str, text: str) -> None:
    target = ROOT / path if isinstance(path, str) else path
    target.write_text(text, encoding='utf-8')


def sub(path: Path | str, pattern: str, repl: str, *, flags: int = 0) -> None:
    text = read(path)
    write(path, re.sub(pattern, repl, text, flags=flags))


def replace(path: Path | str, old: str, new: str) -> None:
    text = read(path)
    if old in text:
        write(path, text.replace(old, new))


# Fix quoting in the synthetic v2 -> v3 migration fixture emitted by the
# primary transform.
p = 'test/database_migration_test.dart'
replace(p, r'\"', '"')

# Mechanical Dart fixture migration: Category was only a named asset/task
# fixture field. Remove that field and obsolete catalog lookups while leaving
# HealthGroup plan fixtures untouched for Problem #5.
for path in list((ROOT / 'test').rglob('*.dart')) + list((ROOT / 'integration_test').rglob('*.dart')):
    text = path.read_text(encoding='utf-8')
    # Remove multiline Category-derived switch arguments before the generic
    # one-line categoryId cleanup so the switch body cannot be orphaned.
    text = re.sub(
        r'^\s*categoryId:\s*switch \([^\n]+\) \{.*?^\s*\},\n',
        '',
        text,
        flags=re.M | re.S,
    )
    text = re.sub(r'^\s*categoryId:\s*[^\n]+\n', '', text, flags=re.M)
    text = re.sub(
        r'^\s*final categories = await [^\n]*\.listCategories\(\);\n',
        '',
        text,
        flags=re.M,
    )
    text = re.sub(
        r'^\s*final categoryId = \(await [^\n]*\.listCategories\(\)\)\.first\.id;\n',
        '',
        text,
        flags=re.M,
    )
    text = re.sub(r'^\s*final categoryId = categories\.first\.id;\n', '', text, flags=re.M)
    text = re.sub(r'^\s*final categoryId = _categoryId\([^\n]+\);\n', '', text, flags=re.M)
    text = re.sub(r'^\s*category:\s*category,\n', '', text, flags=re.M)
    text = re.sub(r"^\s*'category_id':\s*[^\n]+\n", '', text, flags=re.M)
    # Local Category objects used only to populate the removed TaskItem field.
    text = re.sub(
        r'^(\s*)final category = Category\(\n(?:.*\n)*?^\1\);\n',
        '',
        text,
        flags=re.M,
    )
    # Common helper that selected a catalog row only to obtain categoryId.
    text = re.sub(
        r'\nString _categoryId\(List<Category> categories, HealthGroup group\) \{\n'
        r'  return categories\.singleWhere\(\(category\) => category\.healthGroup == group\)\.id;\n'
        r'\}\n',
        '\n',
        text,
    )
    # Test doubles may still implement the now-removed repository members.
    text = re.sub(
        r'\n\s*@override\n\s*Stream<List<Category>> watchCategories\(\)\s*(?:=>[^;]+;|\{.*?\n\s*\})',
        '',
        text,
        flags=re.S,
    )
    text = re.sub(
        r'\n\s*@override\n\s*Future<List<Category>> listCategories\(\)\s*(?:async\s*)?(?:=>[^;]+;|\{.*?\n\s*\})',
        '',
        text,
        flags=re.S,
    )
    path.write_text(text, encoding='utf-8')

# Widget fixture/provider catalog is obsolete; Item Type remains in each Asset.
p = 'test/widget_test.dart'
replace(p, '    categoriesProvider.overrideWithValue(AsyncData(_categories(now))),\n', '')
sub(
    p,
    r'\nList<Category> _categories\(DateTime now\) \{.*?\n\}\n\n(?=List<Asset> _things)',
    '\n',
    flags=re.S,
)
sub(
    p,
    r'\n\s*categoryId: switch \(type\) \{.*?\n\s*\},',
    '',
    flags=re.S,
)

# Room route tests used a Category provider only because the old card API did.
p = 'test/room_route_state_and_editor_guard_test.dart'
sub(
    p,
    r'\s*categoriesProvider\.overrideWith\(\n\s*\(ref\) => Stream\.value\(<Category>\[\]\),\n\s*\),\n',
    '',
)

# BUG-015 keeps generation-bound invalidation for all remaining searchable
# sources; Category itself is intentionally no longer a source family.
p = 'test/bug_015_search_generation_test.dart'
sub(
    p,
    r'\n\s*final categoryId = _categoryId\(categories, HealthGroup\.appliances\);\n'
    r'\s*await \(db\.update\(db\.categories\).*?\n\s*\);\n',
    '\n',
    flags=re.S,
)

# Localization contract now verifies Item Type presentation and that Category
# presentation/search aliases are gone; recurrence and Arabic Item Type search
# coverage remain.
p = 'test/localization_test.dart'
old = """      expect(taskDetail, contains('_categoryLabel(context, task.category)'));
      expect(taskDetail, contains('reminderDaysBeforeDue'));
"""
replace(p, old, """      expect(taskDetail, isNot(contains('_categoryLabel')));
      expect(taskDetail, contains('reminderDaysBeforeDue'));
""")
replace(p, "      expect(thingDetail, contains('_categoryLabel(context, category)'));\n", "      expect(thingDetail, isNot(contains('_categoryLabel')));\n")
replace(p, "      expect(assetDialogs, contains('_categoryLabel(context, item)'));\n", "      expect(assetDialogs, contains('_assetTypeLabel(context, type)'));\n")
replace(p, "      expect(domainLocalization, contains(\"'category_cleaning'\"));\n", "      expect(domainLocalization, contains('localizedAssetTypeLabel'));\n")
replace(
    p,
    """      expect(
        components,
        contains('localizedCategoryLabel(context, task.category)'),
      );
""",
    """      expect(
        components,
        contains('localizedAssetTypeLabel(context, task.asset.assetType)'),
      );
""",
)
replace(p, "      expect(components, isNot(contains('_localizedCategoryName')));\n", "      expect(components, isNot(contains('localizedCategoryLabel')));\n")
replace(p, "      expect(search, contains('category_cleaning'));\n", "      expect(search, isNot(contains(\"'category'\")));\n")

# Current-format backup fixtures no longer need a catalog lookup. The explicit
# v1 backup schema below intentionally retains Category to prove legacy restore.
p = 'test/backup_service_test.dart'
replace(p, '  final categories = await repo.listCategories();\n', '')

# Supabase pgTAP/RPC fixtures: drop only the removed Category key/value and
# index expectation. HealthGroup payloads are intentionally preserved.
for path in (ROOT / 'supabase/tests/database').glob('*.sql'):
    text = path.read_text(encoding='utf-8')
    text = re.sub(
        r"^\s*'category_id',\s*'category_[^']+',\n",
        '',
        text,
        flags=re.M,
    )
    path.write_text(text, encoding='utf-8')

p = 'supabase/tests/database/0010_notification_localization.test.sql'
replace(p, "      'assets_user_id_category_id_idx',\n", '')
replace(p, 'all eight relationship indexes are represented by migrations', 'all seven relationship indexes are represented by migrations')

# Concurrency fixture uses Item Type only.
p = 'tool/test_points_concurrency.ps1'
sub(p, r'\n  category_id text;\n', '\n')
sub(
    p,
    r"\n  select id into category_id\n  from public\.categories\n  where user_id = '\$userId' and health_group = 'other'\n  order by id\n  limit 1;\n",
    '\n',
)
replace(
    p,
    """  insert into public.assets (
    user_id, id, name, asset_type, category_id, room_id,
    created_at, updated_at
  ) values (
    '$userId', '$assetId', 'Concurrency item', 'general', category_id,
    '$roomId', now(), now()
  );
""",
    """  insert into public.assets (
    user_id, id, name, asset_type, room_id, created_at, updated_at
  ) values (
    '$userId', '$assetId', 'Concurrency item', 'general', '$roomId', now(), now()
  );
""",
)
