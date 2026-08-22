import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:owntend/l10n/app_localizations_ext.dart';

import '../core/domain/models.dart';
import 'app_theme.dart';
import 'domain_localization.dart';

const petTypeOptions = [
  'Dog',
  'Cat',
  'Fish',
  'Bird',
  'Rabbit',
  'Reptile',
  'Small mammal',
  'Other',
];

const fishTypeOptions = [
  'Goldfish',
  'Betta',
  'Guppy',
  'Tetra',
  'Molly',
  'Platy',
  'Koi',
  'Other',
];

String petTypeLabel(BuildContext context, String value) => switch (value) {
  'Dog' => context.l10n.petTypeDog,
  'Cat' => context.l10n.petTypeCat,
  'Fish' => context.l10n.petTypeFish,
  'Bird' => context.l10n.petTypeBird,
  'Rabbit' => context.l10n.petTypeRabbit,
  'Reptile' => context.l10n.petTypeReptile,
  'Small mammal' => context.l10n.petTypeSmallMammal,
  'Other' => context.l10n.petTypeOther,
  _ => value,
};

String fishTypeLabel(BuildContext context, String value) => switch (value) {
  'Goldfish' => context.l10n.fishTypeGoldfish,
  'Betta' => context.l10n.fishTypeBetta,
  'Guppy' => context.l10n.fishTypeGuppy,
  'Tetra' => context.l10n.fishTypeTetra,
  'Molly' => context.l10n.fishTypeMolly,
  'Platy' => context.l10n.fishTypePlaty,
  'Koi' => context.l10n.fishTypeKoi,
  'Other' => context.l10n.petTypeOther,
  _ => value,
};

String petSpeciesLabel(BuildContext context, String value) =>
    petTypeOptions.contains(value) ? petTypeLabel(context, value) : value;

IconData iconForArea(Area area) {
  return switch (area.kind) {
    AreaKind.indoor => Symbols.home_work_rounded,
    AreaKind.outdoor => Symbols.yard_rounded,
  };
}

IconData iconForRoom(Room room) {
  return switch (room.roomType) {
    RoomType.living => Symbols.chair_rounded,
    RoomType.bedroom => Symbols.bed_rounded,
    RoomType.kitchen => Symbols.skillet_rounded,
    RoomType.bathroom => Symbols.bathtub_rounded,
    RoomType.utility => Symbols.build_rounded,
    RoomType.storage => Symbols.inventory_2_rounded,
    RoomType.office => Symbols.desk_rounded,
    RoomType.dining => Symbols.dining_rounded,
    RoomType.hallway => Symbols.door_front_rounded,
    RoomType.entry => Symbols.door_open_rounded,
    RoomType.garage => Symbols.garage_home_rounded,
    RoomType.garden => Symbols.yard_rounded,
    RoomType.outdoor => Symbols.deck_rounded,
    RoomType.patio => Symbols.deck_rounded,
    RoomType.balcony => Symbols.balcony_rounded,
    RoomType.pool => Symbols.pool_rounded,
    RoomType.lawn => Symbols.grass_rounded,
    RoomType.shed => Symbols.cabin_rounded,
    RoomType.driveway => Symbols.local_parking_rounded,
    RoomType.other => Symbols.meeting_room_rounded,
  };
}

IconData iconForAssetType(AssetType type) {
  return switch (type) {
    AssetType.device => Symbols.memory_rounded,
    AssetType.pet => Symbols.pets_rounded,
    AssetType.plant => Symbols.yard_rounded,
    AssetType.safety => Symbols.health_and_safety_rounded,
    AssetType.general => Symbols.inventory_2_rounded,
  };
}

String areaKindLabel(BuildContext context, AreaKind kind) {
  return switch (kind) {
    AreaKind.indoor => context.l10n.indoor,
    AreaKind.outdoor => context.l10n.outdoor,
  };
}

String roomTypeLabel(BuildContext context, RoomType type) {
  return switch (type) {
    RoomType.living => context.l10n.livingRoom,
    RoomType.bedroom => context.l10n.bedroom,
    RoomType.kitchen => context.l10n.kitchen,
    RoomType.bathroom => context.l10n.bathroom,
    RoomType.utility => context.l10n.utility,
    RoomType.storage => context.l10n.storage,
    RoomType.office => context.l10n.office,
    RoomType.dining => context.l10n.diningRoom,
    RoomType.hallway => context.l10n.hallway,
    RoomType.entry => context.l10n.entry,
    RoomType.garage => context.l10n.garage,
    RoomType.garden => context.l10n.garden,
    RoomType.outdoor => context.l10n.outdoorZone,
    RoomType.patio => context.l10n.patio,
    RoomType.balcony => context.l10n.balcony,
    RoomType.pool => context.l10n.pool,
    RoomType.lawn => context.l10n.lawn,
    RoomType.shed => context.l10n.shed,
    RoomType.driveway => context.l10n.driveway,
    RoomType.other => context.l10n.other,
  };
}

List<RoomType> roomTypesFor(AreaKind kind) {
  return switch (kind) {
    AreaKind.indoor => const [
      RoomType.living,
      RoomType.bedroom,
      RoomType.kitchen,
      RoomType.bathroom,
      RoomType.dining,
      RoomType.office,
      RoomType.entry,
      RoomType.hallway,
      RoomType.utility,
      RoomType.storage,
      RoomType.garage,
      RoomType.other,
    ],
    AreaKind.outdoor => const [
      RoomType.garden,
      RoomType.patio,
      RoomType.balcony,
      RoomType.pool,
      RoomType.lawn,
      RoomType.shed,
      RoomType.driveway,
      RoomType.outdoor,
      RoomType.other,
    ],
  };
}

String assetTypeLabel(BuildContext context, AssetType type) =>
    localizedAssetTypeLabel(context, type);

String assetTypePluralLabel(BuildContext context, AssetType type) {
  return switch (type) {
    AssetType.device => context.l10n.devicesAndAppliances,
    AssetType.pet => context.l10n.pets,
    AssetType.plant => context.l10n.plants,
    AssetType.safety => context.l10n.safetyItems,
    AssetType.general => context.l10n.generalItems,
  };
}

String powerSourceLabel(BuildContext context, PowerSource source) {
  return switch (source) {
    PowerSource.mains => context.l10n.mains,
    PowerSource.battery => context.l10n.battery,
    PowerSource.solar => context.l10n.solar,
    PowerSource.none => context.l10n.none,
    PowerSource.other => context.l10n.other,
  };
}

String sunlightLabel(BuildContext context, Sunlight sunlight) {
  return switch (sunlight) {
    Sunlight.low => context.l10n.lowLight,
    Sunlight.medium => context.l10n.mediumLight,
    Sunlight.brightIndirect => context.l10n.brightIndirect,
    Sunlight.fullSun => context.l10n.fullSun,
  };
}

String taskStatusLabel(BuildContext context, TaskStatus status) {
  return switch (status) {
    TaskStatus.overdue => context.l10n.overdue,
    TaskStatus.dueToday => context.l10n.dueToday,
    TaskStatus.upcoming => context.l10n.upcoming,
    TaskStatus.completed => context.l10n.completed,
  };
}

String priorityLabel(BuildContext context, PriorityLevel priority) {
  return switch (priority) {
    PriorityLevel.low => context.l10n.routine,
    PriorityLevel.medium => context.l10n.medium,
    PriorityLevel.high => context.l10n.high,
    PriorityLevel.critical => context.l10n.critical,
  };
}

String recurrenceUnitLabel(BuildContext context, RecurrenceUnit unit) {
  return switch (unit) {
    RecurrenceUnit.hours => context.l10n.hours2,
    RecurrenceUnit.days => context.l10n.days2,
    RecurrenceUnit.weeks => context.l10n.weeks2,
    RecurrenceUnit.months => context.l10n.months2,
    RecurrenceUnit.years => context.l10n.years2,
  };
}

String recurrenceLabel(BuildContext context, RecurrenceRule rule) =>
    localizedRecurrenceLabel(context, rule);

Color taskStatusColor(BuildContext context, TaskStatus status) {
  return switch (status) {
    TaskStatus.overdue => HkColors.tertiary,
    TaskStatus.dueToday => HkColors.amber,
    TaskStatus.upcoming => Theme.of(context).colorScheme.primary,
    TaskStatus.completed => HkColors.primary,
  };
}
