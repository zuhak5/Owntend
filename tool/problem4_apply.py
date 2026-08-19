from __future__ import annotations

from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text()


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text)


def replace(path: str, old: str, new: str, *, required: bool = False) -> None:
    text = read(path)
    if old not in text:
        if required:
            raise RuntimeError(f"required text missing in {path}: {old[:120]!r}")
        return
    write(path, text.replace(old, new))


def regex(path: str, pattern: str, repl: str, *, required: bool = False, flags: int = 0) -> None:
    text = read(path)
    updated, count = re.subn(pattern, repl, text, flags=flags)
    if required and count == 0:
        raise RuntimeError(f"required pattern missing in {path}: {pattern}")
    if count:
        write(path, updated)


# Drift source: Category disappears, while HealthGroup remains for Problem #5.
p = "lib/src/core/database/app_database.dart"
replace(p, "import '../domain/categories.dart';\n", "")
regex(
    p,
    r"@DataClassName\('CategoryRow'\)\nclass Categories extends Table \{.*?\n\}\n\n",
    "",
    flags=re.S,
)
replace(p, "  TextColumn get categoryId => text().references(Categories, #id)();\n", "")
replace(p, "    Categories,\n", "")
replace(p, "  static const currentSchemaVersion = 2;", "  static const currentSchemaVersion = 3;")
replace(p, "    'categories',\n", "")
replace(p, "      'CREATE INDEX IF NOT EXISTS idx_categories_group ON categories(health_group)',\n", "")
replace(p, "      'CREATE INDEX IF NOT EXISTS idx_assets_category ON assets(category_id)',\n", "")
replace(
    p,
    """      batch.insertAll(\n        categories,\n        appCategories.map(\n          (c) => _categorySeed(c.id, c.name, c.healthGroup, c.iconName, now),\n        ),\n        mode: InsertMode.insertOrIgnore,\n      );\n""",
    "",
)
regex(
    p,
    r"\n  CategoriesCompanion _categorySeed\(.*?\n  \}\n(?=\})",
    "\n",
    flags=re.S,
)
# Add schema-v3 migration after the schema-v2 generation-state migration.
text = read(p)
if "if (from < 3 && to >= 3)" not in text:
    anchor = """      if (from < 2 && to >= 2) {\n        await _createSearchIndexGenerationInfrastructure();\n      }\n"""
    if anchor not in text:
        raise RuntimeError("app_database.dart migration anchor changed")
    migration = anchor + """      if (from < 3 && to >= 3) {\n        await customStatement('DROP INDEX IF EXISTS idx_assets_category');\n        await customStatement('DROP INDEX IF EXISTS idx_categories_group');\n        await customStatement('DROP TRIGGER IF EXISTS search_categories_insert');\n        await customStatement('DROP TRIGGER IF EXISTS search_categories_update');\n        await customStatement('DROP TRIGGER IF EXISTS search_categories_delete');\n        await m.alterTable(TableMigration(assets));\n        await customStatement('DROP TABLE IF EXISTS categories');\n      }\n"""
    write(p, text.replace(anchor, migration))

# Asset repository uses Item Type only.
p = "lib/src/core/data/asset_repository.dart"
replace(p, "    required String categoryId,\n", "")
replace(p, "                categoryId: categoryId,\n", "")
replace(p, "            categoryId: Value(categoryId),\n", "")
replace(p, "      categoryId: asset.categoryId,\n", "")
replace(p, "      categoryId: source.categoryId,\n", "")
regex(
    p,
    r"\n  @override\n  Stream<List<domain\.Category>> watchCategories\(\) \{.*?\n  \}\n\n  @override\n  Future<List<domain\.Category>> listCategories\(\) async \{.*?\n  \}\n",
    "\n",
    flags=re.S,
)

# Task hydration must no longer require a Category row. HealthGroup stays intact.
p = "lib/src/core/data/maintenance_repository.dart"
replace(
    p,
    """    final categoryRows = await db.select(db.categories).get();\n    final categoryMap = {for (final row in categoryRows) row.id: row};\n""",
    "",
)
replace(p, "      final category = categoryMap[asset.categoryId];\n", "")
replace(p, "      if (category == null || room == null) {\n", "      if (room == null) {\n")
replace(p, "          category: _categoryFromRow(category),\n", "")
replace(p, "        db.select(db.categories).watch(),\n", "")

# Search keeps action vocabulary such as cleaning, but Category is no longer an entity/facet.
p = "lib/src/core/data/search_repository.dart"
regex(p, r"  'category_(?:appliances|safety|plants|pets|cleaning|general)':(?:\n      )?'[^']*',\n", "")
regex(
    p,
    r"      for \(final category in await db\.select\(db\.categories\)\.get\(\)\) \{.*?\n      \}\n",
    "",
    flags=re.S,
)

# Asset sync shape changes; entity/key identity does not.
p = "lib/src/core/sync/sync_dtos.dart"
replace(p, "      'category_id',\n", "")

# Current backup schema no longer includes or describes Category.
p = "lib/src/core/services/backup_service.dart"
replace(
    p,
    "  'Items, rooms, areas, categories, tags, and photos',\n",
    "  'Items, rooms, areas, tags, and photos',\n",
)
replace(p, "  'categories',\n", "")

# Print remaining Category-specific references for the next focused pass.
checks = [
    "Category|categoryId|category_id|categoriesProvider|categoryForAssetType|_categoryId",
]
for pattern in checks:
    print(f"--- remaining: {pattern} ---")
    subprocess.run(
        ["rg", "-n", pattern, "lib", "test", "integration_test", "supabase", "docs", "tool"],
        cwd=ROOT,
        check=False,
    )
