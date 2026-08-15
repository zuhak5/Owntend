import 'models.dart';

final _categoryEpoch = DateTime.utc(2026, 1, 1);

/// Canonical static categories for Owntend.
final appCategories = <Category>[
  Category(
    id: 'category_appliances',
    name: 'Appliances',
    healthGroup: HealthGroup.appliances,
    iconName: 'kitchen',
    createdAt: _categoryEpoch,
    updatedAt: _categoryEpoch,
  ),
  Category(
    id: 'category_safety',
    name: 'Safety',
    healthGroup: HealthGroup.safety,
    iconName: 'shield',
    createdAt: _categoryEpoch,
    updatedAt: _categoryEpoch,
  ),
  Category(
    id: 'category_plants',
    name: 'Plants',
    healthGroup: HealthGroup.plants,
    iconName: 'yard',
    createdAt: _categoryEpoch,
    updatedAt: _categoryEpoch,
  ),
  Category(
    id: 'category_pets',
    name: 'Pets',
    healthGroup: HealthGroup.pets,
    iconName: 'pets',
    createdAt: _categoryEpoch,
    updatedAt: _categoryEpoch,
  ),
  Category(
    id: 'category_cleaning',
    name: 'Cleaning',
    healthGroup: HealthGroup.cleaning,
    iconName: 'cleaning_services',
    createdAt: _categoryEpoch,
    updatedAt: _categoryEpoch,
  ),
  Category(
    id: 'category_general',
    name: 'General',
    healthGroup: HealthGroup.other,
    iconName: 'home',
    createdAt: _categoryEpoch,
    updatedAt: _categoryEpoch,
  ),
];

final appCategoryById = {
  for (final category in appCategories) category.id: category,
};

Category? categoryForAssetType(AssetType type, [List<Category>? candidates]) {
  final list = candidates ?? appCategories;
  final preferredGroup = switch (type) {
    AssetType.device => HealthGroup.appliances,
    AssetType.pet => HealthGroup.pets,
    AssetType.plant => HealthGroup.plants,
    AssetType.safety => HealthGroup.safety,
    AssetType.general => HealthGroup.other,
  };
  return list.where((item) => item.healthGroup == preferredGroup).firstOrNull ??
      list.firstOrNull;
}
