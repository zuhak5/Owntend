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

class DriftSearchRepository implements SearchRepository {
  DriftSearchRepository(this.db);

  final AppDatabase db;

  @override
  Future<void> rebuildIndex() async {
    await db.transaction(() async {
      await db.customStatement('DELETE FROM search_index');
      final areaRows = await (db.select(
        db.areas,
      )..where((area) => area.archivedAt.isNull())).get();
      final areaById = {for (final area in areaRows) area.id: area};
      for (final area in areaRows) {
        await _insert(
          'area',
          area.id,
          area.name,
          '${area.kind} ${_localizedSearchAlias(area.kind)}',
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
          '$areaName ${room.roomType} ${_localizedSearchAlias(room.roomType)} ${room.notes ?? ''}',
        );
      }
      for (final category in await db.select(db.categories).get()) {
        await _insert(
          'category',
          category.id,
          category.name,
          '${category.healthGroup} ${_localizedSearchAlias(category.id)} ${_localizedSearchAlias(category.healthGroup)}',
        );
      }
      for (final asset in await (db.select(
        db.assets,
      )..where((asset) => asset.archivedAt.isNull())).get()) {
        await _insert(
          'asset',
          asset.id,
          asset.name,
          '${asset.assetType} ${_localizedSearchAlias(asset.assetType)} '
              '${asset.placement ?? ''} ${asset.notes ?? ''} '
              '${await _assetDetailSearchBody(asset)} '
              '${await _assetTagSearchBody(asset.id)} '
              '${await _assetPhotoSearchBody(asset.id)}',
        );
      }
      for (final tag in await db.select(db.tags).get()) {
        await _insert('tag', tag.id, tag.name, '');
      }
      for (final plan in await (db.select(
        db.maintenancePlans,
      )..where((plan) => plan.archivedAt.isNull())).get()) {
        await _insert('plan', plan.id, plan.title, plan.instructions ?? '');
      }
    });
  }

  @override
  Future<List<domain.SearchResult>> search(String query) async {
    final match = _searchMatch(query);
    if (match == null) {
      return [];
    }
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
    String body,
  ) async {
    await db.customStatement(
      'INSERT INTO search_index(entity_type, entity_id, title, body) VALUES (?, ?, ?, ?)',
      [type, id, title, body],
    );
  }

  Future<String> _assetDetailSearchBody(AssetRow asset) async {
    switch (_assetType(asset.assetType)) {
      case domain.AssetType.device:
        final row =
            await (db.select(db.deviceDetailsTable)
                  ..where((detail) => detail.assetId.equals(asset.id)))
                .getSingleOrNull();
        if (row == null) {
          return '';
        }
        return [
          row.brand,
          row.model,
          row.serialNumber,
          row.powerSource,
          _localizedSearchAlias(row.powerSource),
          row.manualUrl,
          row.consumable,
        ].whereType<String>().join(' ');
      case domain.AssetType.pet:
        final row =
            await (db.select(db.petDetailsTable)
                  ..where((detail) => detail.assetId.equals(asset.id)))
                .getSingleOrNull();
        if (row == null) {
          return '';
        }
        return [
          row.species,
          _localizedSearchAlias(row.species),
          row.breed,
          _localizedSearchAlias(row.breed),
          row.microchipId,
          row.vetName,
          row.vetPhone,
          row.feedingNotes,
          row.medicalNotes,
        ].whereType<String>().join(' ');
      case domain.AssetType.plant:
        final row =
            await (db.select(db.plantDetailsTable)
                  ..where((detail) => detail.assetId.equals(asset.id)))
                .getSingleOrNull();
        if (row == null) {
          return '';
        }
        return [
          row.species,
          row.sunlight,
          _localizedSearchAlias(row.sunlight),
          row.potSize,
          row.toxicityNotes,
        ].whereType<String>().join(' ');
      case domain.AssetType.safety:
        final row =
            await (db.select(db.safetyDetailsTable)
                  ..where((detail) => detail.assetId.equals(asset.id)))
                .getSingleOrNull();
        if (row == null) {
          return '';
        }
        return [row.safetyType, row.batteryType].whereType<String>().join(' ');
      case domain.AssetType.general:
        return '';
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
