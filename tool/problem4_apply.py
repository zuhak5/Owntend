from __future__ import annotations

from pathlib import Path
import re
import subprocess

# Temporary feature-branch helper. It is deleted before the final PR head.
ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def replace(path: str, old: str, new: str, *, required: bool = False) -> None:
    text = read(path)
    if old not in text:
        if required:
            raise RuntimeError(f"required text missing in {path}: {old[:160]!r}")
        return
    write(path, text.replace(old, new))


def regex(path: str, pattern: str, repl: str, *, required: bool = False, flags: int = 0) -> None:
    text = read(path)
    updated, count = re.subn(pattern, repl, text, flags=flags)
    if required and count == 0:
        raise RuntimeError(f"required pattern missing in {path}: {pattern}")
    if count:
        write(path, updated)


# ---------------------------------------------------------------------------
# Drift/domain/repository/search/sync/backup contract
# ---------------------------------------------------------------------------
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
text = read(p)
if "if (from < 3 && to >= 3)" not in text:
    anchor = """      if (from < 2 && to >= 2) {\n        await _createSearchIndexGenerationInfrastructure();\n      }\n"""
    if anchor not in text:
        raise RuntimeError("app_database.dart migration anchor changed")
    migration = anchor + """      if (from < 3 && to >= 3) {\n        await customStatement('DROP INDEX IF EXISTS idx_assets_category');\n        await customStatement('DROP INDEX IF EXISTS idx_categories_group');\n        await customStatement('DROP TRIGGER IF EXISTS search_categories_insert');\n        await customStatement('DROP TRIGGER IF EXISTS search_categories_update');\n        await customStatement('DROP TRIGGER IF EXISTS search_categories_delete');\n        await m.alterTable(TableMigration(assets));\n        await customStatement('DROP TABLE IF EXISTS categories');\n      }\n"""
    write(p, text.replace(anchor, migration))

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

p = "lib/src/core/data/search_repository.dart"
regex(
    p,
    r"  'category_(?:appliances|safety|plants|pets|cleaning|general)':\s*'[^']*',\n",
    "",
)
regex(
    p,
    r"\n      for \(final category in await db\.select\(db\.categories\)\.get\(\)\) \{.*?\n      \}\n",
    "\n",
    flags=re.S,
)

p = "lib/src/core/sync/sync_dtos.dart"
replace(p, "      'category_id',\n", "")

p = "lib/src/core/services/backup_service.dart"
replace(
    p,
    "  'Items, rooms, areas, categories, tags, and photos',\n",
    "  'Items, rooms, areas, tags, and photos',\n",
)
replace(p, "  'categories',\n", "")

p = "lib/src/features/backup/presentation/backup_screen.dart"
replace(p, "    ref.invalidate(categoriesProvider);\n", "")

# ---------------------------------------------------------------------------
# Localization/presentation: Item Type remains; Category disappears.
# ---------------------------------------------------------------------------
p = "lib/src/ui/domain_localization.dart"
regex(
    p,
    r"/// Localizes the built-in category catalog.*?\nString localizedCategoryLabel\(BuildContext context, Category category\) \{.*?\n\}\n\n",
    """String localizedAssetTypeLabel(BuildContext context, AssetType type) {\n  return switch (type) {\n    AssetType.device => context.l10n.deviceOrAppliance,\n    AssetType.pet => context.l10n.pet,\n    AssetType.plant => context.l10n.plant,\n    AssetType.safety => context.l10n.safetyItem,\n    AssetType.general => context.l10n.generalItem,\n  };\n}\n\n""",
    required=True,
    flags=re.S,
)

p = "lib/src/ui/enum_formatters.dart"
regex(
    p,
    r"String _assetTypeLabel\(BuildContext context, AssetType type\) \{.*?\n\}\n",
    "String _assetTypeLabel(BuildContext context, AssetType type) =>\n    localizedAssetTypeLabel(context, type);\n",
    flags=re.S,
)
regex(
    p,
    r"\nString _categoryLabel\(BuildContext context, Category category\) =>\n    localizedCategoryLabel\(context, category\);\n",
    "\n",
)
regex(
    p,
    r"\nCategory\? _categoryForType\(AssetType type, List<Category> categories\) \{\n  return categoryForAssetType\(type, categories\);\n\}\n",
    "\n",
)

p = "lib/src/ui/components.dart"
replace(
    p,
    "${localizedCategoryLabel(context, task.category)} · ${_localizedPriorityLabel(context, task.plan.priority)}",
    "${localizedAssetTypeLabel(context, task.asset.assetType)} · ${_localizedPriorityLabel(context, task.plan.priority)}",
)

p = "lib/src/features/maintenance/presentation/task_detail_screen.dart"
regex(
    p,
    r"\n                          _DetailRow\(\n                            icon: Symbols\.category_rounded,\n                            label: context\.l10n\.category,\n                            value: _categoryLabel\(context, task\.category\),\n                          \),",
    "",
)

p = "lib/src/features/rooms/presentation/room_detail_screen.dart"
replace(p, "    final categories = ref.watch(categoriesProvider).value ?? [];\n", "")
regex(
    p,
    r"    final categoryById = \{\n      for \(final category in categories\) category\.id: category,\n    \};\n",
    "",
)
replace(p, "                            category: categoryById[asset.categoryId],\n", "")

p = "lib/src/features/assets/presentation/thing_detail_screen.dart"
replace(p, "        final categories = ref.watch(categoriesProvider).value ?? [];\n", "")
regex(
    p,
    r"        final category = categories\n            \.where\(\(item\) => item\.id == asset\.categoryId\)\n            \.firstOrNull;\n",
    "",
)
replace(
    p,
    """                                        if (category != null)\n                                          _categoryLabel(context, category),\n""",
    "",
)
replace(p, "    required this.category,\n", "")
replace(p, "  final Category? category;\n", "")

p = "lib/src/features/search/presentation/search_screen.dart"
replace(p, "    'category' => Symbols.category_rounded,\n", "")
regex(
    p,
    r"String _searchResultTitle\(BuildContext context, SearchResult result\) \{\n  if \(result\.entityType == 'category'\) \{.*?\n  \}\n  return result\.title;\n\}",
    "String _searchResultTitle(BuildContext context, SearchResult result) => result.title;",
    flags=re.S,
)
replace(p, "    'category' => context.l10n.category,\n", "")
replace(
    p,
    "  final snippet = result.entityType == 'category' ? '' : result.snippet.trim();\n",
    "  final snippet = result.snippet.trim();\n",
)

# Asset editor: remove Category state, persistence, provider dependency, picker,
# RPC field, and repository argument. Keep the existing Item Type picker.
p = "lib/src/features/assets/presentation/asset_dialogs.dart"
replace(p, "                  'category_id': widget.asset.categoryId,\n", "")
replace(p, "  String? _categoryId;\n", "")
replace(p, "    _categoryId = asset?.categoryId;\n", "")
replace(p, "      'category_id': _categoryId,\n", "")
replace(p, "      _categoryId = draft['category_id'] as String?;\n", "")
replace(p, "    final categories = ref.watch(categoriesProvider);\n", "")
regex(
    p,
    r"    final categoryItems = categories\.value \?\? const <Category>\[\];\n    final selectedCategoryId =\n        _categoryId \?\?\n        _categoryForType\(_assetType, categoryItems\)\?\.id \?\?\n        categoryItems\.firstOrNull\?\.id;\n",
    "",
)
replace(
    p,
    """        _nameController.text.trim().isNotEmpty &&\n        selectedCategoryId != null &&\n        selectedRoomId != null;\n""",
    """        _nameController.text.trim().isNotEmpty &&\n        selectedRoomId != null;\n""",
)
replace(
    p,
    """          categories.when(\n            data: (items) => DropdownButtonFormField<AssetType>(\n              initialValue: _assetType,\n              decoration: InputDecoration(labelText: context.l10n.itemType),\n              items: [\n                for (final type in AssetType.values)\n                  DropdownMenuItem(\n                    value: type,\n                    child: Text(_assetTypeLabel(context, type)),\n                  ),\n              ],\n              onChanged: (value) {\n                if (value != null) {\n                  _changeType(value, items);\n                }\n              },\n            ),\n            error: (error, _) => Text(_failureMessage(context, error)),\n            loading: () => const LinearProgressIndicator(),\n          ),\n""",
    """          DropdownButtonFormField<AssetType>(\n            key: const ValueKey('asset-item-type-picker'),\n            initialValue: _assetType,\n            decoration: InputDecoration(labelText: context.l10n.itemType),\n            items: [\n              for (final type in AssetType.values)\n                DropdownMenuItem(\n                  value: type,\n                  child: Text(_assetTypeLabel(context, type)),\n                ),\n            ],\n            onChanged: (value) {\n              if (value != null) {\n                _changeType(value);\n              }\n            },\n          ),\n""",
    required=True,
)
regex(
    p,
    r"          categories\.when\(\n            data: \(items\) \{.*?\n            loading: \(\) => const LinearProgressIndicator\(\),\n          \),\n          const SizedBox\(height: 12\),\n(?=          TextField\(\n            controller: _placementController)",
    "",
    required=True,
    flags=re.S,
)
replace(
    p,
    "Future<void> _changeType(AssetType value, List<Category> categories) async {",
    "Future<void> _changeType(AssetType value) async {",
)
replace(
    p,
    """    setState(() {\n      _assetType = value;\n      _categoryId = _categoryForType(value, categories)?.id ?? _categoryId;\n    });\n""",
    "    setState(() => _assetType = value);\n",
)
regex(
    p,
    r"    final categoryItems =\n        ref\.read\(categoriesProvider\)\.value \?\? const <Category>\[\];\n    final categoryId =\n        _categoryId \?\?\n        _categoryForType\(_assetType, categoryItems\)\?\.id \?\?\n        categoryItems\.firstOrNull\?\.id;\n",
    "",
)
replace(
    p,
    """    if (_nameController.text.trim().isEmpty ||\n        categoryId == null ||\n        roomId == null) {\n""",
    """    if (_nameController.text.trim().isEmpty || roomId == null) {\n""",
)
replace(p, "            'category_id': categoryId,\n", "")
replace(p, "            categoryId: categoryId,\n", "")

# ---------------------------------------------------------------------------
# Pre-launch Supabase clean baseline. HealthGroup remains a Problem #5 field.
# ---------------------------------------------------------------------------
p = "supabase/migrations/20260815000001_core_schema.sql"
replace(
    p,
    "  asset_type TEXT NOT NULL DEFAULT 'general',\n  category_id TEXT,\n",
    "  asset_type TEXT NOT NULL DEFAULT 'general' CHECK (asset_type IN ('device', 'pet', 'plant', 'safety', 'general')),\n",
    required=True,
)
regex(
    p,
    r"  CONSTRAINT assets_category_id_check CHECK \(\n    category_id IS NULL OR category_id IN \(\n      'category_safety', 'category_pets', 'category_appliances',\n      'category_plants', 'category_cleaning', 'category_general'\n    \)\n  \),\n",
    "",
    required=True,
)
regex(
    p,
    r"\nCREATE INDEX IF NOT EXISTS assets_user_id_category_id_idx\n  ON public\.assets \(user_id, category_id\);\n",
    "",
    required=True,
)

for p in [
    "supabase/migrations/20260815000003_points_monetization.sql",
    "supabase/migrations/20260815000008_asset_device_contract.sql",
]:
    replace(p, "  category_health_group TEXT;\n", "")
    regex(
        p,
        r"\n  category_health_group := CASE asset_json->>'category_id'.*?\n  END IF;\n",
        "\n",
        flags=re.S,
    )
    replace(
        p,
        "    user_id, id, room_id, category_id, name,\n",
        "    user_id, id, room_id, name,\n",
    )
    replace(
        p,
        "    caller_id, asset_id, asset_json->>'room_id', asset_json->>'category_id',\n    BTRIM(asset_json->>'name'),\n",
        "    caller_id, asset_id, asset_json->>'room_id',\n    BTRIM(asset_json->>'name'),\n",
    )
    replace(
        p,
        "      CASE WHEN category_health_group = 'safety' THEN 'safety' ELSE plan_json->>'health_group' END,\n",
        "      CASE WHEN asset_kind = 'safety' THEN 'safety' ELSE plan_json->>'health_group' END,\n",
    )

p = "supabase/migrations/20260815000003_points_monetization.sql"
replace(
    p,
    "SELECT (assets.asset_type = 'safety' OR assets.category_id = 'category_safety')\n",
    "SELECT assets.asset_type = 'safety'\n",
    required=True,
)

# ---------------------------------------------------------------------------
# Focused test/source fixture updates for the Category-free asset shape.
# ---------------------------------------------------------------------------
p = "test/search_localization_test.dart"
regex(
    p,
    r"\n  test\(\n    'Arabic category aliases find canonical categories without leaking aliases',.*?\n  \);\n",
    """\n  test('Category is not a search entity or item class', () async {\n    await repository.rebuildIndex();\n\n    final results = await repository.search('تنظيف');\n    expect(results.where((result) => result.entityType == 'category'), isEmpty);\n  });\n""",
    flags=re.S,
)
replace(
    p,
    """      \"INSERT INTO assets(id, name, asset_type, category_id, room_id, notes) \"\n      \"VALUES ('search-device', 'Purifier', 'device', \"\n      \"'category_appliances', 'search-room', 'Quiet bedroom unit')\",\n""",
    """      \"INSERT INTO assets(id, name, asset_type, room_id, notes) \"\n      \"VALUES ('search-device', 'Purifier', 'device', \"\n      \"'search-room', 'Quiet bedroom unit')\",\n""",
)

p = "test/database_migration_test.dart"
replace(p, "group('AppDatabase schema v2 and lifecycle'", "group('AppDatabase schema v3 and lifecycle'")
replace(p, "owntend_schema_v2_", "owntend_schema_v3_")
replace(p, "test('initializes with schema version 2'", "test('initializes with schema version 3'")
replace(p, "expect(AppDatabase.currentSchemaVersion, 2);", "expect(AppDatabase.currentSchemaVersion, 3);")
replace(p, "expect(db.schemaVersion, 2);", "expect(db.schemaVersion, 3);")
replace(p, "expect(userVersionRow.read<int>('user_version'), 2);", "expect(userVersionRow.read<int>('user_version'), 3);")
replace(p, "        'categories',\n", "")
replace(p, "      expect(triggerNames, hasLength(36));", "      expect(triggerNames, hasLength(33));")
replace(p, "      expect(triggerNames, contains('search_categories_delete'));\n", "      expect(triggerNames, isNot(contains('search_categories_delete')));\n")
replace(p, "      expect(indexNames, contains('idx_assets_category'));\n", "      expect(indexNames, isNot(contains('idx_assets_category')));\n")
regex(
    p,
    r"\n    test\('seeds default categories, settings, and streak', \(\) async \{\n      final seededCategories = await db\.select\(db\.categories\)\.get\(\);.*?\n      final seededSettings =",
    "\n    test('seeds settings and streak without Category tables', () async {\n      final categoryTables = await db.customSelect(\n        \"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'categories'\",\n      ).get();\n      expect(categoryTables, isEmpty);\n\n      final assetColumns = await db.customSelect('PRAGMA table_info(assets)').get();\n      expect(\n        assetColumns.map((row) => row.read<String>('name')),\n        isNot(contains('category_id')),\n      );\n\n      final seededSettings =",
    flags=re.S,
)
# Replace the old v1->v2 scenario with an immediately-previous v2->v3 fixture.
regex(
    p,
    r"\n  test\('migrates schema v1 to search generation v2', \(\) async \{.*?\n  \}\);\n\}",
    r'''\n  test('migrates schema v2 assets and removes Category state', () async {\n    final dbFile = File(\n      '${Directory.systemTemp.path}/owntend_v2_to_v3_'\n      '${DateTime.now().microsecondsSinceEpoch}.sqlite',\n    );\n    AppDatabase? db;\n    try {\n      db = AppDatabase(executor: NativeDatabase(dbFile));\n      await db.customSelect('SELECT 1').get();\n      await db.customStatement(\n        'CREATE TABLE categories ('\n        'id TEXT PRIMARY KEY, name TEXT NOT NULL, health_group TEXT NOT NULL, '\n        'icon_name TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',\n      );\n      await db.customStatement(\n        "INSERT INTO categories(id, name, health_group, icon_name, created_at, updated_at) "\n        "VALUES ('category_appliances', 'Appliances', 'appliances', 'kitchen', 0, 0)",\n      );\n      await db.customStatement('ALTER TABLE assets ADD COLUMN category_id TEXT');\n      await db.customStatement(\n        "INSERT INTO areas(id, name, kind) VALUES ('legacy-area', 'Home', 'indoor')",\n      );\n      await db.customStatement(\n        "INSERT INTO rooms(id, area_id, name, room_type) "\n        "VALUES ('legacy-room', 'legacy-area', 'Kitchen', 'kitchen')",\n      );\n      await db.customStatement(\n        "INSERT INTO assets(id, name, asset_type, room_id, category_id) "\n        "VALUES ('legacy-asset', 'Purifier', 'device', 'legacy-room', 'category_appliances')",\n      );\n      await db.customStatement('PRAGMA user_version = 2');\n      await db.close();\n      db = null;\n\n      db = AppDatabase(executor: NativeDatabase(dbFile));\n      await db.customSelect('SELECT 1').get();\n\n      final userVersionRow = await db.customSelect('PRAGMA user_version').getSingle();\n      expect(userVersionRow.read<int>('user_version'), 3);\n      final categoryTables = await db.customSelect(\n        \"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'categories'\",\n      ).get();\n      expect(categoryTables, isEmpty);\n      final assetColumns = await db.customSelect('PRAGMA table_info(assets)').get();\n      expect(\n        assetColumns.map((row) => row.read<String>('name')),\n        isNot(contains('category_id')),\n      );\n      final migrated = await db.customSelect(\n        \"SELECT id, name, asset_type FROM assets WHERE id = 'legacy-asset'\",\n      ).getSingle();\n      expect(migrated.read<String>('name'), 'Purifier');\n      expect(migrated.read<String>('asset_type'), 'device');\n      final triggerRows = await db.customSelect(\n        \"SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'search_%'\",\n      ).get();\n      expect(triggerRows, hasLength(33));\n    } finally {\n      await db?.close();\n      if (await dbFile.exists()) {\n        await dbFile.delete();\n      }\n    }\n  });\n}\n''',
    required=True,
    flags=re.S,
)

# Remove now-invalid named/category fixture fields in Dart tests. These are
# mechanical shape updates only; assertions are left intact unless they assert
# Category itself.
for path in (ROOT / "test").glob("*.dart"):
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"^\s*categoryId:\s*'category_[^']+',\n", "", text, flags=re.M)
    text = re.sub(r"^\s*category:\s*(?:const\s+)?Category\(.*?\),\n", "", text, flags=re.M | re.S)
    path.write_text(text, encoding="utf-8")

# Add a compact backend contract regression without changing existing test
# semantics. It is numbered after the current 0020 suite.
backend_test = ROOT / "supabase/tests/database/0021_problem_004_remove_category.test.sql"
backend_test.write_text(
    """begin;\n\ncreate extension if not exists pgtap with schema extensions;\nset local role postgres;\nset search_path = public, extensions, pg_catalog;\n\nselect extensions.plan(5);\n\nselect extensions.hasnt_column(\n  'public', 'assets', 'category_id',\n  'assets no longer persist a Category classifier'\n);\nselect extensions.ok(\n  not exists (\n    select 1 from pg_indexes\n    where schemaname = 'public' and tablename = 'assets'\n      and indexdef ilike '%category_id%'\n  ),\n  'assets have no Category index'\n);\nselect extensions.ok(\n  strpos(\n    pg_get_functiondef(\n      'owntend_monetization_private.create_asset_with_point_debit_impl(jsonb)'::regprocedure\n    ),\n    'category_id'\n  ) = 0,\n  'asset creation implementation no longer reads or writes Category'\n);\nselect extensions.ok(\n  strpos(\n    pg_get_functiondef(\n      'owntend_monetization_private.create_task_with_point_debit_impl(jsonb)'::regprocedure\n    ),\n    'category_id'\n  ) = 0,\n  'task safety classification no longer falls back to Category'\n);\nselect extensions.ok(\n  strpos(\n    pg_get_constraintdef(\n      (select oid from pg_constraint\n       where conrelid = 'public.assets'::regclass\n         and contype = 'c'\n         and pg_get_constraintdef(oid) ilike '%asset_type%')\n    ),\n    'device'\n  ) > 0,\n  'Item Type remains the constrained asset classifier'\n);\n\nselect * from extensions.finish();\nrollback;\n""",
    encoding="utf-8",
)

# Make common SQL fixtures compatible with the Category-free assets table and
# RPC payload. Formatting/analyze/pgTAP will catch any shape we missed.
for path in [
    ROOT / "supabase/tests/database/0010_notification_localization.test.sql",
    ROOT / "supabase/tests/database/0011_complete_maintenance_task.test.sql",
    ROOT / "supabase/tests/database/0012_points_monetization.test.sql",
    ROOT / "supabase/tests/database/0017_charged_operation_status.test.sql",
    ROOT / "tool/test_points_concurrency.ps1",
]:
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"\s*'category_id'\s*:\s*'category_[^']+',?", "", text)
    text = re.sub(r"\s*\"category_id\"\s*:\s*\"category_[^\"]+\",?", "", text)
    text = re.sub(r"\bcategory_id\s*,\s*", "", text)
    text = re.sub(r",\s*category_id\b", "", text)
    # Most direct INSERT fixtures place the category value immediately after
    # asset_type; remove that obsolete literal while retaining asset_type.
    text = re.sub(r"('(?:device|pet|plant|safety|general)'\s*,)\s*'category_[^']+'\s*,", r"\1", text)
    path.write_text(text, encoding="utf-8")

# ---------------------------------------------------------------------------
# Report residuals. We deliberately do not treat generic UI wording like
# 'category' or Sentry's event category as a Problem #4 domain reference.
# ---------------------------------------------------------------------------
for pattern in [
    "Category|categoryId|category_id|categoriesProvider|categoryForAssetType|_categoryId",
    "category_appliances|category_safety|category_plants|category_pets|category_cleaning|category_general",
]:
    print(f"--- remaining: {pattern} ---")
    subprocess.run(
        ["rg", "-n", pattern, "lib", "test", "integration_test", "supabase", "docs", "tool"],
        cwd=ROOT,
        check=False,
    )
