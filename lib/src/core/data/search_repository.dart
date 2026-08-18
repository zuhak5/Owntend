part of 'repositories.dart';

const _localizedSearchAliases = <String, String>{
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
  'category_appliances':
      'appliances appliance أجهزة جهاز كهربائي أجهزة كهربائية',
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

String _joinSearchParts(Iterable<String?> parts) => parts
    .whereType<String>()
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty)
    .join(' ');

typedef _SearchIndexState = ({int sourceGeneration, int indexedGeneration});

class DriftSearchRepository implements SearchRepository {
  DriftSearchRepository(this.db, {this.beforeIndexCommit});

  final AppDatabase db;
  final Future<void> Function()? beforeIndexCommit;
  Future<void>? _rebuildInFlight;

  @override
  Future<void> rebuildIndex() => _serializeRebuild(force: true);

  @override
  Future<List<domain.SearchResult>> search(String query) async {
    final match = _searchMatch(query);
    if (match == null) {
      return [];
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      await _ensureFreshIndex();
      final results = await _queryIndex(match);
      final state = await _readIndexState();
      if (_stateIsValid(state) &&
          state!.sourceGeneration == state.indexedGeneration) {
        return results;
      }
    }

    throw StateError(
      'Searchable data changed repeatedly while the search index was being read.',
    );
  }

  Future<void> _ensureFreshIndex() async {
    final state = await _readIndexState();
    final storageValid = await _searchIndexStorageIsValid();
    final stateValid = _stateIsValid(state);
    if (storageValid &&
        stateValid &&
        state!.sourceGeneration == state.indexedGeneration) {
      return;
    }
    await _serializeRebuild(force: !storageValid || !stateValid);
  }

  Future<void> _serializeRebuild({required bool force}) {
    final active = _rebuildInFlight;
    if (active != null) {
      return active;
    }

    late final Future<void> rebuild;
    rebuild = _rebuildIndex(force: force).whenComplete(() {
      if (identical(_rebuildInFlight, rebuild)) {
        _rebuildInFlight = null;
      }
    });
    _rebuildInFlight = rebuild;
    return rebuild;
  }

  Future<void> _rebuildIndex({required bool force}) async {
    await db.transaction(() async {
      var state = await _readIndexState();
      if (!_stateIsValid(state)) {
        await _resetIndexState();
        state = (sourceGeneration: 1, indexedGeneration: 0);
      }
      if (!force && state!.sourceGeneration == state.indexedGeneration) {
        return;
      }

      final representedGeneration = state!.sourceGeneration;
      if (force) {
        await _recreateSearchIndexStorage();
      } else {
        await db.customStatement('DELETE FROM search_index');
      }

      final areaRows = await (db.select(
        db.areas,
      )..where((area) => area.archivedAt.isNull())).get();
      final areaById = {for (final area in areaRows) area.id: area};
      for (final area in areaRows) {
        await _insert(
          'area',
          area.id,
          area.name,
          '',
          _joinSearchParts([area.kind, _localizedSearchAlias(area.kind)]),
        );
      }
      for (final room in await (db.select(
        db.rooms,
      )..where((room) => room.archivedAt.isNull())).get()) {
        final areaName = areaById[room.areaId]?.name ?? '';
        await _insert(
          'room',
          room.id,
          room.name,
          _joinSearchParts([areaName, room.notes]),
          _joinSearchParts([
            room.roomType,
            _localizedSearchAlias(room.roomType),
          ]),
        );
      }
      for (final category in await db.select(db.categories).get()) {
        await _insert(
          'category',
          category.id,
          category.name,
          '',
          _joinSearchParts([
            category.name,
            category.healthGroup,
            _localizedSearchAlias(category.id),
            _localizedSearchAlias(category.healthGroup),
          ]),
        );
      }
      for (final asset in await (db.select(
        db.assets,
      )..where((asset) => asset.archivedAt.isNull())).get()) {
        final detail = await _assetDetailSearchContent(asset);
        await _insert(
          'asset',
          asset.id,
          asset.name,
          _joinSearchParts([
            asset.placement,
            asset.notes,
            detail.displayBody,
            await _assetTagSearchBody(asset.id),
            await _assetPhotoSearchBody(asset.id),
          ]),
          _joinSearchParts([
            asset.assetType,
            _localizedSearchAlias(asset.assetType),
            detail.searchTerms,
          ]),
        );
      }
      for (final tag in await db.select(db.tags).get()) {
        await _insert('tag', tag.id, tag.name, '', '');
      }
      for (final plan in await (db.select(
        db.maintenancePlans,
      )..where((plan) => plan.archivedAt.isNull())).get()) {
        await _insert('plan', plan.id, plan.title, plan.instructions ?? '', '');
      }

      await beforeIndexCommit?.call();
      await db.customStatement(
        'UPDATE search_index_state '
        'SET indexed_generation = ? WHERE id = 1',
        [representedGeneration],
      );
    });
  }

  Future<_SearchIndexState?> _readIndexState() async {
    try {
      final row = await db
          .customSelect(
            'SELECT source_generation, indexed_generation '
            'FROM search_index_state WHERE id = 1',
            readsFrom: {},
          )
          .getSingleOrNull();
      if (row == null) {
        return null;
      }
      return (
        sourceGeneration: row.read<int>('source_generation'),
        indexedGeneration: row.read<int>('indexed_generation'),
      );
    } catch (_) {
      return null;
    }
  }

  bool _stateIsValid(_SearchIndexState? state) {
    return state != null &&
        state.sourceGeneration >= 0 &&
        state.indexedGeneration >= 0 &&
        state.indexedGeneration <= state.sourceGeneration;
  }

  Future<bool> _searchIndexStorageIsValid() async {
    final row = await db
        .customSelect(
          "SELECT sql FROM sqlite_master "
          "WHERE type = 'table' AND name = 'search_index'",
          readsFrom: {},
        )
        .getSingleOrNull();
    if (row == null) {
      return false;
    }
    final definition = row.read<String>('sql').toLowerCase();
    return definition.contains('fts5') &&
        definition.contains('display_body') &&
        definition.contains('search_terms');
  }

  Future<void> _resetIndexState() async {
    await db.customStatement('''
CREATE TABLE IF NOT EXISTS search_index_state (
  id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
  source_generation INTEGER NOT NULL CHECK (source_generation >= 0),
  indexed_generation INTEGER NOT NULL CHECK (indexed_generation >= 0)
)
''');
    await db.customStatement('DELETE FROM search_index_state');
    await db.customStatement(
      'INSERT INTO search_index_state('
      'id, source_generation, indexed_generation'
      ') VALUES (1, 1, 0)',
    );
  }

  Future<void> _recreateSearchIndexStorage() async {
    await db.customStatement('DROP TABLE IF EXISTS search_index');
    await db.customStatement(
      'CREATE VIRTUAL TABLE search_index USING fts5('
      'entity_type UNINDEXED, entity_id UNINDEXED, title, '
      'display_body, search_terms)',
    );
  }

  Future<List<domain.SearchResult>> _queryIndex(String match) async {
    final rows = await db
        .customSelect(
          "SELECT entity_type, entity_id, title, snippet(search_index, 3, '', '', '...', 12) AS snippet "
          "FROM search_index WHERE search_index MATCH ? ORDER BY rank LIMIT 25",
          variables: [Variable.withString(match)],
          readsFrom: {},
        )
        .get();
    return rows
        .map(
          (row) => domain.SearchResult(
            entityType: row.read<String>('entity_type'),
            entityId: row.read<String>('entity_id'),
            title: row.read<String>('title'),
            snippet: row.read<String>('snippet'),
          ),
        )
        .toList();
  }

  Future<void> _insert(
    String type,
    String id,
    String title,
    String displayBody,
    String searchTerms,
  ) async {
    await db.customStatement(
      'INSERT INTO search_index('
      'entity_type, entity_id, title, display_body, search_terms'
      ') VALUES (?, ?, ?, ?, ?)',
      [type, id, title, displayBody, searchTerms],
    );
  }

  Future<({String displayBody, String searchTerms})> _assetDetailSearchContent(
    AssetRow asset,
  ) async {
    switch (_assetType(asset.assetType)) {
      case domain.AssetType.device:
        final row =
            await (db.select(db.deviceDetailsTable)
                  ..where((detail) => detail.assetId.equals(asset.id)))
                .getSingleOrNull();
        if (row == null) {
          return (displayBody: '', searchTerms: '');
        }
        return (
          displayBody: _joinSearchParts([
            row.brand,
            row.model,
            row.serialNumber,
            row.manualUrl,
            row.consumable,
          ]),
          searchTerms: _joinSearchParts([
            row.powerSource,
            _localizedSearchAlias(row.powerSource),
          ]),
        );
      case domain.AssetType.pet:
        final row =
            await (db.select(db.petDetailsTable)
                  ..where((detail) => detail.assetId.equals(asset.id)))
                .getSingleOrNull();
        if (row == null) {
          return (displayBody: '', searchTerms: '');
        }
        return (
          displayBody: _joinSearchParts([
            row.microchipId,
            row.vetName,
            row.vetPhone,
            row.feedingNotes,
            row.medicalNotes,
          ]),
          searchTerms: _joinSearchParts([
            row.species,
            _localizedSearchAlias(row.species),
            row.breed,
            _localizedSearchAlias(row.breed),
          ]),
        );
      case domain.AssetType.plant:
        final row =
            await (db.select(db.plantDetailsTable)
                  ..where((detail) => detail.assetId.equals(asset.id)))
                .getSingleOrNull();
        if (row == null) {
          return (displayBody: '', searchTerms: '');
        }
        return (
          displayBody: _joinSearchParts([
            row.species,
            row.potSize,
            row.toxicityNotes,
          ]),
          searchTerms: _joinSearchParts([
            row.sunlight,
            _localizedSearchAlias(row.sunlight),
          ]),
        );
      case domain.AssetType.safety:
        final row =
            await (db.select(db.safetyDetailsTable)
                  ..where((detail) => detail.assetId.equals(asset.id)))
                .getSingleOrNull();
        if (row == null) {
          return (displayBody: '', searchTerms: '');
        }
        return (
          displayBody: _joinSearchParts([row.safetyType, row.batteryType]),
          searchTerms: '',
        );
      case domain.AssetType.general:
        return (displayBody: '', searchTerms: '');
    }
  }

  Future<String> _assetTagSearchBody(String assetId) async {
    final links = await (db.select(
      db.assetTags,
    )..where((tag) => tag.assetId.equals(assetId))).get();
    final tagIds = links.map((link) => link.tagId).toList();
    if (tagIds.isEmpty) {
      return '';
    }
    final tags = await (db.select(
      db.tags,
    )..where((tag) => tag.id.isIn(tagIds))).get();
    return tags.map((tag) => tag.name).join(' ');
  }

  Future<String> _assetPhotoSearchBody(String assetId) async {
    final photos = await (db.select(
      db.assetPhotos,
    )..where((photo) => photo.assetId.equals(assetId))).get();
    return photos.map((photo) => photo.caption).whereType<String>().join(' ');
  }

  String? _searchMatch(String query) {
    final tokens = RegExp(
      r'[\p{L}\p{N}]+',
      unicode: true,
    ).allMatches(query).map((match) => '${match.group(0)}*').toList();
    if (tokens.isEmpty) {
      return null;
    }
    return tokens.join(' ');
  }
}
