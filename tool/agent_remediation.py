from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected exactly one occurrence, found {count}: {old[:100]!r}")
    write(path, text.replace(old, new, 1))


def regex_once(path: str, pattern: str, replacement: str) -> None:
    text = read(path)
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"{path}: regex expected exactly one match, found {count}: {pattern}")
    write(path, updated)


def insert_before_once(path: str, anchor: str, addition: str) -> None:
    text = read(path)
    count = text.count(anchor)
    if count != 1:
        raise RuntimeError(f"{path}: expected one insertion anchor, found {count}: {anchor!r}")
    write(path, text.replace(anchor, addition + anchor, 1))


# ---------------------------------------------------------------------------
# UI/domain localization boundary
# ---------------------------------------------------------------------------

enum_path = "lib/src/ui/enum_formatters.dart"
insert_before_once(
    enum_path,
    "final _rootNavigatorKey = GlobalKey<NavigatorState>();",
    """String _petSpeciesLabel(BuildContext context, String value) =>
    _petTypeOptions.contains(value) ? _petTypeLabel(context, value) : value;

String _fishBreedLabel(BuildContext context, String value) =>
    _fishTypeOptions.contains(value) ? _fishTypeLabel(context, value) : value;

""",
)

insert_before_once(
    enum_path,
    "String _recurrenceUnitLabel(BuildContext context, RecurrenceUnit unit) {",
    """String _categoryLabel(BuildContext context, Category category) {
  return switch (category.id) {
    'category_appliances' => context.l10n.appliances,
    'category_safety' => context.l10n.safety,
    'category_plants' => context.l10n.plants,
    'category_pets' => context.l10n.pets,
    'category_cleaning' => context.l10n.cleaning,
    'category_general' => context.l10n.general,
    _ => category.name,
  };
}

""",
)

regex_once(
    enum_path,
    r"String _recurrenceLabel\(BuildContext context, RecurrenceRule rule\) \{.*?\n\}\n\nColor _taskStatusColor",
    """String _recurrenceLabel(BuildContext context, RecurrenceRule rule) {
  return switch (rule.unit) {
    RecurrenceUnit.hours => context.l10n.recurrenceHours(rule.interval),
    RecurrenceUnit.days => context.l10n.recurrenceDays(rule.interval),
    RecurrenceUnit.weeks => context.l10n.recurrenceWeeks(rule.interval),
    RecurrenceUnit.months => context.l10n.recurrenceMonths(rule.interval),
    RecurrenceUnit.years => context.l10n.recurrenceYears(rule.interval),
  };
}

Color _taskStatusColor""",
)

# Task detail: controlled category + existing ICU reminder message.
replace_once(
    "lib/src/features/maintenance/presentation/task_detail_screen.dart",
    "value: task.category.name,",
    "value: _categoryLabel(context, task.category),",
)
replace_once(
    "lib/src/features/maintenance/presentation/task_detail_screen.dart",
    """value:
                                  '${task.plan.reminderDaysBefore} ${task.plan.reminderDaysBefore == 1 ? 'day' : 'days'} before due',""",
    """value: context.l10n.reminderDaysBeforeDue(
                                task.plan.reminderDaysBefore,
                              ),""",
)

# Thing detail: localized category, localized built-in pet token, ICU duration.
replace_once(
    "lib/src/features/assets/presentation/thing_detail_screen.dart",
    "if (category != null) category.name,",
    "if (category != null) _categoryLabel(context, category),",
)
replace_once(
    "lib/src/features/assets/presentation/thing_detail_screen.dart",
    """value:
            '${metadata.estimatedDurationMinutes} ${metadata.estimatedDurationMinutes == 1 ? 'minute' : 'minutes'}',""",
    """value: context.l10n.durationMinutes(
          metadata.estimatedDurationMinutes!,
        ),""",
)
replace_once(
    "lib/src/features/assets/presentation/thing_detail_screen.dart",
    "value: pet!.species!,",
    "value: _petSpeciesLabel(context, pet!.species!),",
)

# Asset editor category choices use presentation labels but persist stable IDs.
replace_once(
    "lib/src/features/assets/presentation/asset_dialogs.dart",
    "DropdownMenuItem(value: item.id, child: Text(item.name)),",
    "DropdownMenuItem(value: item.id, child: Text(_categoryLabel(context, item))),",
)

# The standalone shared component library already localizes category names; remove
# English grammar from the asset/room relationship and use neutral metadata.
replace_once(
    "lib/src/ui/components.dart",
    "final locationText = '${task.asset.name} in ${task.room.name}';",
    "final locationText = '${task.asset.name} · ${task.room.name}';",
)

# Neutral metadata separators avoid English punctuation/composition assumptions.
replace_once(
    "lib/src/ui/shared_widgets.dart",
    "'${task.asset.name} - ${_formatShortDate(context, task.plan.nextDueDate)} - ${_recurrenceLabel(context, task.plan.recurrence)}',",
    "'${task.asset.name} · ${_formatShortDate(context, task.plan.nextDueDate)} · ${_recurrenceLabel(context, task.plan.recurrence)}',",
)
replace_once(
    "lib/src/features/trash/presentation/trash_screen.dart",
    "subtitle: '${task.asset.name} - ${task.room.name}',",
    "subtitle: '${task.asset.name} · ${task.room.name}',",
)

# ---------------------------------------------------------------------------
# Bilingual search aliases + localized controlled result titles
# ---------------------------------------------------------------------------

search_repo = "lib/src/core/data/search_repository.dart"
insert_before_once(
    search_repo,
    "class DriftSearchRepository implements SearchRepository {",
    r"""const _localizedSearchAliases = <String, String>{
  'indoor': 'indoor داخل داخلي داخلية',
  'outdoor': 'outdoor خارج خارجي خارجية',
  'living': 'living room غرفة معيشة صالة',
  'bedroom': 'bedroom غرفة نوم نوم',
  'kitchen': 'kitchen مطبخ',
  'bathroom': 'bathroom حمام',
  'utility': 'utility خدمات مرافق',
  'storage': 'storage مخزن تخزين',
  'office': 'office مكتب',
  'dining': 'dining dining room غرفة طعام سفرة',
  'hallway': 'hallway ممر',
  'entry': 'entry entrance مدخل',
  'garage': 'garage كراج مرآب',
  'garden': 'garden حديقة',
  'patio': 'patio فناء',
  'balcony': 'balcony شرفة',
  'pool': 'pool مسبح',
  'lawn': 'lawn عشب حديقة',
  'shed': 'shed مخزن كوخ',
  'driveway': 'driveway ممر سيارات',
  'other': 'other أخرى اخر عام عامة',
  'device': 'device appliance devices appliances جهاز أجهزة جهاز كهربائي أجهزة كهربائية',
  'pet': 'pet pets حيوان حيوانات حيوان أليف حيوانات أليفة',
  'plant': 'plant plants نبات نباتات',
  'safety': 'safety أمان سلامة',
  'general': 'general عام عامة',
  'appliances': 'appliances appliance أجهزة جهاز كهربائي أجهزة كهربائية',
  'pets': 'pets pet حيوانات حيوان حيوانات أليفة',
  'plants': 'plants plant نباتات نبات',
  'cleaning': 'cleaning clean تنظيف التنظيف نظافة',
  'category_appliances': 'appliances appliance أجهزة جهاز كهربائي أجهزة كهربائية',
  'category_safety': 'safety أمان سلامة',
  'category_plants': 'plants plant نباتات نبات',
  'category_pets': 'pets pet حيوانات حيوان حيوانات أليفة',
  'category_cleaning': 'cleaning clean تنظيف التنظيف نظافة',
  'category_general': 'general عام عامة',
  'mains': 'mains electricity كهرباء تيار كهربائي',
  'battery': 'battery batteries بطارية بطاريات',
  'solar': 'solar شمسي شمسية طاقة شمسية',
  'none': 'none بدون لا شيء',
  'low': 'low light إضاءة منخفضة ضوء منخفض',
  'medium': 'medium light إضاءة متوسطة ضوء متوسط',
  'brightIndirect': 'bright indirect light إضاءة ساطعة غير مباشرة',
  'fullSun': 'full sun شمس كاملة شمس مباشرة',
  'Dog': 'dog dogs كلب كلاب',
  'Cat': 'cat cats قطة قطط',
  'Fish': 'fish سمك أسماك اسماك',
  'Bird': 'bird birds طائر طيور',
  'Rabbit': 'rabbit rabbits أرنب أرانب ارنب ارانب',
  'Reptile': 'reptile reptiles زواحف زاحف',
  'Small mammal': 'small mammal ثديي صغير حيوان صغير',
  'Goldfish': 'goldfish سمكة ذهبية سمك ذهبي',
  'Betta': 'betta بيتا',
  'Guppy': 'guppy غوبي',
  'Tetra': 'tetra تترا',
  'Molly': 'molly مولي',
  'Platy': 'platy بلاتي',
  'Koi': 'koi كوي',
};

String _localizedSearchAlias(String? value) =>
    value == null ? '' : (_localizedSearchAliases[value] ?? '');

""",
)
replace_once(
    search_repo,
    "await _insert('area', area.id, area.name, area.kind);",
    "await _insert(\n          'area',\n          area.id,\n          area.name,\n          '${area.kind} ${_localizedSearchAlias(area.kind)}',\n        );",
)
replace_once(
    search_repo,
    "'$areaName ${room.roomType} ${room.notes ?? ''}',",
    "'$areaName ${room.roomType} ${_localizedSearchAlias(room.roomType)} ${room.notes ?? ''}',",
)
replace_once(
    search_repo,
    "category.healthGroup,",
    "'${category.healthGroup} ${_localizedSearchAlias(category.id)} ${_localizedSearchAlias(category.healthGroup)}',",
)
replace_once(
    search_repo,
    """'${asset.assetType} ${asset.placement ?? ''} ${asset.notes ?? ''} '
              '${await _assetDetailSearchBody(asset)} '""",
    """'${asset.assetType} ${_localizedSearchAlias(asset.assetType)} '
              '${asset.placement ?? ''} ${asset.notes ?? ''} '
              '${await _assetDetailSearchBody(asset)} '""",
)
replace_once(
    search_repo,
    """          row.powerSource,
          row.manualUrl,""",
    """          row.powerSource,
          _localizedSearchAlias(row.powerSource),
          row.manualUrl,""",
)
replace_once(
    search_repo,
    """          row.species,
          row.breed,""",
    """          row.species,
          _localizedSearchAlias(row.species),
          row.breed,
          _localizedSearchAlias(row.breed),""",
)
replace_once(
    search_repo,
    """          row.sunlight,
          row.potSize,""",
    """          row.sunlight,
          _localizedSearchAlias(row.sunlight),
          row.potSize,""",
)

search_screen = "lib/src/features/search/presentation/search_screen.dart"
replace_once(
    search_screen,
    "title: Text(result.title),",
    "title: Text(_searchResultTitle(context, result)),",
)
insert_before_once(
    search_screen,
    "String _searchResultSubtitle(BuildContext context, SearchResult result) {",
    """String _searchResultTitle(BuildContext context, SearchResult result) {
  if (result.entityType == 'category') {
    final category = appCategoryById[result.entityId];
    if (category != null) {
      return _categoryLabel(context, category);
    }
  }
  return result.title;
}

""",
)
replace_once(
    search_screen,
    "final snippet = result.snippet.trim();",
    "final snippet = result.entityType == 'category' ? '' : result.snippet.trim();",
)

# ---------------------------------------------------------------------------
# Forward Supabase migration: align the text contract and preserve placement.
# ---------------------------------------------------------------------------

source_sql = read("supabase/migrations/20260815000003_points_monetization.sql")
fn_start_marker = (
    "CREATE OR REPLACE FUNCTION "
    "owntend_monetization_private.create_asset_with_point_debit_impl("
)
fn_end_marker = (
    "GRANT EXECUTE ON FUNCTION "
    "owntend_monetization_private.create_asset_with_point_debit_impl(JSONB) "
    "TO authenticated, service_role;"
)
start = source_sql.find(fn_start_marker)
end_start = source_sql.find(fn_end_marker, start)
if start < 0 or end_start < 0:
    raise RuntimeError("could not extract create_asset_with_point_debit_impl from baseline migration")
end = end_start + len(fn_end_marker)
function_block = source_sql[start:end]

old_columns = """    user_id, id, room_id, category_id, name,
    purchase_date, notes, created_at, updated_at,
    archived_at, revision, asset_type"""
new_columns = """    user_id, id, room_id, category_id, name,
    placement, purchase_date, notes, created_at, updated_at,
    archived_at, revision, asset_type"""
if function_block.count(old_columns) != 1:
    raise RuntimeError("asset INSERT column anchor changed")
function_block = function_block.replace(old_columns, new_columns, 1)

old_values = """    BTRIM(asset_json->>'name'),
    (asset_json->>'purchase_date')::date,"""
new_values = """    BTRIM(asset_json->>'name'),
    NULLIF(BTRIM(asset_json->>'placement'), ''),
    (asset_json->>'purchase_date')::date,"""
if function_block.count(old_values) != 1:
    raise RuntimeError("asset INSERT value anchor changed")
function_block = function_block.replace(old_values, new_values, 1)

old_consumable = "COALESCE((details_json->>'consumable')::boolean, false),"
new_consumable = "NULLIF(BTRIM(details_json->>'consumable'), ''),"
if function_block.count(old_consumable) != 1:
    raise RuntimeError("device consumable RPC anchor changed")
function_block = function_block.replace(old_consumable, new_consumable, 1)

migration = f"""-- Align device consumable semantics with Flutter/Drift and persist asset placement.
-- The client models consumable as optional descriptive text (filters, batteries,
-- cartridges, etc.); Boolean values from the original cloud baseline were a
-- schema/RPC mismatch that caused INVALID_ASSET_PAYLOAD on normal text input.

BEGIN;

ALTER TABLE public.device_details
  ALTER COLUMN consumable DROP DEFAULT;

ALTER TABLE public.device_details
  ALTER COLUMN consumable DROP NOT NULL;

ALTER TABLE public.device_details
  ALTER COLUMN consumable TYPE TEXT
  USING CASE WHEN consumable IS TRUE THEN 'true' ELSE NULL END;

ALTER TABLE public.device_details
  ADD CONSTRAINT device_details_consumable_length_check
  CHECK (consumable IS NULL OR CHAR_LENGTH(consumable) <= 500);

{function_block}

COMMIT;
"""
write(
    "supabase/migrations/20260816210000_fix_asset_device_contract.sql",
    migration,
)

# ---------------------------------------------------------------------------
# Database regression coverage
# ---------------------------------------------------------------------------

sql_test = "supabase/tests/database/0012_points_monetization.test.sql"
replace_once(sql_test, "select extensions.plan(75);", "select extensions.plan(80);")
insert_before_once(
    sql_test,
    "select extensions.is(\n  (\n    public.create_task_with_point_debit(",
    """select extensions.is(
  (
    select data_type
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'device_details'
      and column_name = 'consumable'
  ),
  'text',
  'device consumable uses the same text contract as Flutter and Drift'
);
select extensions.is(
  (
    select is_nullable
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'device_details'
      and column_name = 'consumable'
  ),
  'YES',
  'device consumable remains optional'
);
select extensions.is(
  (
    public.create_asset_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000009',
        'asset', jsonb_build_object(
          'id', 'points-device-asset',
          'name', 'Air purifier',
          'asset_type', 'device',
          'category_id', 'category_appliances',
          'room_id', 'points-room',
          'placement', 'Utility shelf'
        ),
        'details', jsonb_build_object(
          'brand', 'Example',
          'power_source', 'mains',
          'consumable', 'HEPA filter'
        )
      )
    )->>'asset_id'
  ),
  'points-device-asset',
  'device creation accepts descriptive consumable text'
);
select extensions.is(
  (select placement from public.assets where id = 'points-device-asset'),
  'Utility shelf',
  'asset creation RPC persists placement'
);
select extensions.is(
  (select consumable from public.device_details where asset_id = 'points-device-asset'),
  'HEPA filter',
  'asset creation RPC preserves descriptive consumable text'
);

""",
)

# ---------------------------------------------------------------------------
# Source-level localization regression guard
# ---------------------------------------------------------------------------

localization_test = "test/localization_test.dart"
insert_before_once(
    localization_test,
    "  test(\n    'unknown controlled notifications use the localized generic fallback',",
    """  test('controlled domain values use localization at presentation boundaries', () {
    final taskDetail = File(
      'lib/src/features/maintenance/presentation/task_detail_screen.dart',
    ).readAsStringSync();
    expect(taskDetail, contains('_categoryLabel(context, task.category)'));
    expect(taskDetail, contains('reminderDaysBeforeDue'));
    expect(taskDetail, isNot(contains("'day' : 'days'")));
    expect(taskDetail, isNot(contains(' before due')));

    final thingDetail = File(
      'lib/src/features/assets/presentation/thing_detail_screen.dart',
    ).readAsStringSync();
    expect(thingDetail, contains('_categoryLabel(context, category)'));
    expect(thingDetail, contains('durationMinutes'));
    expect(thingDetail, contains('_petSpeciesLabel(context, pet!.species!)'));
    expect(thingDetail, isNot(contains("'minute' : 'minutes'")));

    final assetDialogs = File(
      'lib/src/features/assets/presentation/asset_dialogs.dart',
    ).readAsStringSync();
    expect(assetDialogs, contains('_categoryLabel(context, item)'));

    final recurrence = File('lib/src/ui/enum_formatters.dart').readAsStringSync();
    expect(recurrence, contains('recurrenceDays(rule.interval)'));
    expect(recurrence, contains('recurrenceWeeks(rule.interval)'));
    expect(recurrence, contains('recurrenceMonths(rule.interval)'));
    expect(recurrence, contains('recurrenceYears(rule.interval)'));

    final components = File('lib/src/ui/components.dart').readAsStringSync();
    expect(components, isNot(contains(" in \\${task.room.name}")));

    final search = File(
      'lib/src/core/data/search_repository.dart',
    ).readAsStringSync();
    expect(search, contains('category_cleaning'));
    expect(search, contains('تنظيف'));
    expect(search, contains('حيوانات أليفة'));
  });

""",
)

# ---------------------------------------------------------------------------
# Documentation synchronization
# ---------------------------------------------------------------------------

replace_once(
    "CHANGELOG.md",
    "## 1.0.0 (Build 1) — 2026-08-15",
    """## Unreleased

### Fixed

- Aligned the Supabase device `consumable` field with Flutter's optional descriptive-text contract so normal filter, battery, and cartridge descriptions no longer fail asset creation.
- Preserved item `placement` during the server-authoritative asset-creation RPC.
- Localized built-in categories and pet species at presentation boundaries, corrected Arabic recurrence/reminder/duration grammar, and removed English-only relationship fragments from Arabic UI surfaces.
- Added Arabic search aliases for controlled categories, room/item types, power sources, sunlight, and built-in pet/fish values while keeping canonical stored values locale-neutral.

## 1.0.0 (Build 1) — 2026-08-15""",
)

insert_before_once(
    "docs/backend/supabase.md",
    "## RPCs\n",
    """### Asset detail contract

`device_details.consumable` is optional descriptive text end to end, matching the Flutter domain model and Drift schema. It stores user-entered consumable or replacement-part descriptions such as filters, batteries, and cartridges; it is not a Boolean capability flag. The atomic asset-creation RPC normalizes blank consumable text to `NULL` and persists the optional `assets.placement` field supplied by Flutter. Database regression coverage exercises this contract through `create_asset_with_point_debit`.

""",
)

insert_before_once(
    "docs/development/localization-and-rtl.md",
    "## RTL layout\n",
    """## Controlled domain values

Stable stored identifiers and wire values remain locale-neutral. Built-in category IDs, enum names, pet/fish tokens, and similar controlled values must be converted to localized display labels at the presentation boundary; user-entered names, notes, species, breeds, placement, and other free text remain exactly as entered.

Category presentation is keyed by stable category ID rather than English category spelling. Quantity and recurrence text must use the existing ICU messages rather than manually composing English singular/plural fragments. Search indexes include English and Arabic aliases for controlled values so either language can discover the same canonical record without translating persisted data. Controlled search results must render through the same localized presenters used by the rest of the UI.

For relationship metadata that is not a sentence, use a direction-neutral separator such as `·` instead of embedding English grammar such as `in` or manually concatenating translated sentence fragments.

""",
)

print("Owntend remediation patch applied successfully.")
