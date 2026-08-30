import 'dart:convert';

import 'models.dart';

/// Input limits shared by presentation, domain, and local persistence.
///
/// These values mirror the authoritative constraints in the Supabase schema.
abstract final class InputValidationLimits {
  static const assetName = 200;
  static const assetPlacement = 300;
  static const assetNotes = 10000;
  static const tagName = 120;

  static const deviceBrand = 120;
  static const deviceModel = 120;
  static const deviceSerialNumber = 160;
  static const devicePowerSource = 80;
  static const deviceManualUrl = 1000;
  static const deviceConsumable = 500;

  static const petSpecies = 120;
  static const petBreed = 120;
  static const petMicrochipId = 120;
  static const petVetName = 200;
  static const petVetPhone = 80;
  static const petNotes = 4000;

  static const plantSpecies = 200;
  static const plantSunlight = 120;
  static const plantPotSize = 120;
  static const plantToxicityNotes = 4000;

  static const safetyType = 120;
  static const safetyBatteryType = 120;

  static const maintenanceTitle = 200;
  static const maintenanceInstructions = 4000;
  static const maintenanceTaskType = 120;
  static const maintenanceLocation = 240;
  static const maintenanceRequiredMaterialsJson = 4000;
  static const maintenanceReminderRecommendation = 1000;
}

enum InputValidationIssue {
  required,
  invalidFormat,
  tooLong,
  mustBePositive,
  mustBeNonNegative,
}

void validateAuthoritativeAssetPayload(
  Map<String, dynamic> asset,
  Map<String, dynamic> details,
) {
  final typeName = _wireRequiredString(asset, 'asset_type');
  final assetType = AssetType.values.where((value) => value.name == typeName);
  if (assetType.isEmpty) {
    throw const InputValidationException(
      code: 'asset_type_invalid',
      issue: InputValidationIssue.invalidFormat,
    );
  }
  validateAssetInput(
    name: _wireRequiredString(asset, 'name'),
    roomId: _wireRequiredString(asset, 'room_id'),
    assetType: assetType.single,
    placement: _wireOptionalString(asset, 'placement'),
    notes: _wireOptionalString(asset, 'notes'),
    deviceDetails: typeName == AssetType.device.name
        ? DeviceDetails(
            brand: _wireOptionalString(details, 'brand'),
            model: _wireOptionalString(details, 'model'),
            serialNumber: _wireOptionalString(details, 'serial_number'),
            manualUrl: _wireOptionalString(details, 'manual_url'),
            consumable: _wireOptionalString(details, 'consumable'),
          )
        : null,
    petDetails: typeName == AssetType.pet.name
        ? PetDetails(
            species: _wireOptionalString(details, 'species'),
            breed: _wireOptionalString(details, 'breed'),
            microchipId: _wireOptionalString(details, 'microchip_id'),
            vetName: _wireOptionalString(details, 'vet_name'),
            vetPhone: _wireOptionalString(details, 'vet_phone'),
            feedingNotes: _wireOptionalString(details, 'feeding_notes'),
            medicalNotes: _wireOptionalString(details, 'medical_notes'),
          )
        : null,
    plantDetails: typeName == AssetType.plant.name
        ? PlantDetails(
            species: _wireOptionalString(details, 'species'),
            wateringIntervalDays: _wireOptionalInt(
              details,
              'watering_interval_days',
            ),
            potSize: _wireOptionalString(details, 'pot_size'),
            toxicityNotes: _wireOptionalString(details, 'toxicity_notes'),
          )
        : null,
    safetyDetails: typeName == AssetType.safety.name
        ? SafetyDetails(
            safetyType: _wireOptionalString(details, 'safety_type'),
            batteryType: _wireOptionalString(details, 'battery_type'),
            testIntervalDays: _wireOptionalInt(details, 'test_interval_days'),
          )
        : null,
  );
  if (typeName == AssetType.device.name) {
    _max(
      _wireOptionalString(details, 'power_source'),
      InputValidationLimits.devicePowerSource,
      code: 'device_power_source_too_long',
    );
  } else if (typeName == AssetType.plant.name) {
    _max(
      _wireOptionalString(details, 'sunlight'),
      InputValidationLimits.plantSunlight,
      code: 'plant_sunlight_too_long',
    );
  }
}

/// A privacy-safe validation error that never retains the rejected input.
class InputValidationException implements Exception {
  const InputValidationException({
    required this.code,
    required this.issue,
    this.maxLength,
  });

  final String code;
  final InputValidationIssue issue;
  final int? maxLength;

  @override
  String toString() => code;
}

void validateAssetInput({
  required String name,
  required String roomId,
  required AssetType assetType,
  String? placement,
  String? notes,
  List<String> tagNames = const [],
  DeviceDetails? deviceDetails,
  PetDetails? petDetails,
  PlantDetails? plantDetails,
  SafetyDetails? safetyDetails,
}) {
  _required(name, code: 'asset_name_required');
  _required(roomId, code: 'asset_room_required');
  _max(name, InputValidationLimits.assetName, code: 'asset_name_too_long');
  _max(
    placement,
    InputValidationLimits.assetPlacement,
    code: 'asset_placement_too_long',
  );
  _max(notes, InputValidationLimits.assetNotes, code: 'asset_notes_too_long');
  for (final tagName in tagNames) {
    _max(tagName, InputValidationLimits.tagName, code: 'asset_tag_too_long');
  }

  switch (assetType) {
    case AssetType.device:
      final details = deviceDetails ?? const DeviceDetails();
      _max(
        details.brand,
        InputValidationLimits.deviceBrand,
        code: 'device_brand_too_long',
      );
      _max(
        details.model,
        InputValidationLimits.deviceModel,
        code: 'device_model_too_long',
      );
      _max(
        details.serialNumber,
        InputValidationLimits.deviceSerialNumber,
        code: 'device_serial_number_too_long',
      );
      _max(
        details.powerSource?.name,
        InputValidationLimits.devicePowerSource,
        code: 'device_power_source_too_long',
      );
      _max(
        details.manualUrl,
        InputValidationLimits.deviceManualUrl,
        code: 'device_manual_url_too_long',
      );
      _max(
        details.consumable,
        InputValidationLimits.deviceConsumable,
        code: 'device_consumable_too_long',
      );
    case AssetType.pet:
      final details = petDetails ?? const PetDetails();
      _max(
        details.species,
        InputValidationLimits.petSpecies,
        code: 'pet_species_too_long',
      );
      _max(
        details.breed,
        InputValidationLimits.petBreed,
        code: 'pet_breed_too_long',
      );
      _max(
        details.microchipId,
        InputValidationLimits.petMicrochipId,
        code: 'pet_microchip_id_too_long',
      );
      _max(
        details.vetName,
        InputValidationLimits.petVetName,
        code: 'pet_vet_name_too_long',
      );
      _max(
        details.vetPhone,
        InputValidationLimits.petVetPhone,
        code: 'pet_vet_phone_too_long',
      );
      _max(
        details.feedingNotes,
        InputValidationLimits.petNotes,
        code: 'pet_feeding_notes_too_long',
      );
      _max(
        details.medicalNotes,
        InputValidationLimits.petNotes,
        code: 'pet_medical_notes_too_long',
      );
    case AssetType.plant:
      final details = plantDetails ?? const PlantDetails();
      _max(
        details.species,
        InputValidationLimits.plantSpecies,
        code: 'plant_species_too_long',
      );
      _max(
        details.sunlight?.name,
        InputValidationLimits.plantSunlight,
        code: 'plant_sunlight_too_long',
      );
      _positiveIfPresent(
        details.wateringIntervalDays,
        code: 'plant_watering_interval_invalid',
      );
      _max(
        details.potSize,
        InputValidationLimits.plantPotSize,
        code: 'plant_pot_size_too_long',
      );
      _max(
        details.toxicityNotes,
        InputValidationLimits.plantToxicityNotes,
        code: 'plant_toxicity_notes_too_long',
      );
    case AssetType.safety:
      final details = safetyDetails ?? const SafetyDetails();
      _max(
        details.safetyType,
        InputValidationLimits.safetyType,
        code: 'safety_type_too_long',
      );
      _max(
        details.batteryType,
        InputValidationLimits.safetyBatteryType,
        code: 'safety_battery_type_too_long',
      );
      _positiveIfPresent(
        details.testIntervalDays,
        code: 'safety_test_interval_invalid',
      );
    case AssetType.general:
      break;
  }
}

void validateMaintenancePlanInput({
  required String assetId,
  required String title,
  String? instructions,
  required RecurrenceRule recurrence,
  required int reminderDaysBefore,
  TaskMetadata? metadata,
}) {
  _required(assetId, code: 'maintenance_asset_required');
  _required(title, code: 'maintenance_title_required');
  _max(
    title,
    InputValidationLimits.maintenanceTitle,
    code: 'maintenance_title_too_long',
  );
  _max(
    instructions,
    InputValidationLimits.maintenanceInstructions,
    code: 'maintenance_instructions_too_long',
  );
  _positive(recurrence.interval, code: 'maintenance_recurrence_invalid');
  _nonNegative(reminderDaysBefore, code: 'maintenance_reminder_days_invalid');

  if (metadata == null) {
    return;
  }
  _max(
    metadata.taskType,
    InputValidationLimits.maintenanceTaskType,
    code: 'maintenance_task_type_too_long',
  );
  _max(
    metadata.locationLabel,
    InputValidationLimits.maintenanceLocation,
    code: 'maintenance_location_too_long',
  );
  _nonNegativeIfPresent(
    metadata.estimatedDurationMinutes,
    code: 'maintenance_duration_invalid',
  );
  _max(
    jsonEncode(metadata.requiredMaterials),
    InputValidationLimits.maintenanceRequiredMaterialsJson,
    trim: false,
    code: 'maintenance_materials_too_long',
  );
  _max(
    metadata.reminderRecommendation,
    InputValidationLimits.maintenanceReminderRecommendation,
    code: 'maintenance_reminder_recommendation_too_long',
  );
}

void _required(String value, {required String code}) {
  if (value.trim().isEmpty) {
    throw InputValidationException(
      code: code,
      issue: InputValidationIssue.required,
    );
  }
}

String _wireRequiredString(Map<String, dynamic> value, String key) {
  final field = value[key];
  if (field is! String) {
    throw InputValidationException(
      code: '${key}_invalid',
      issue: InputValidationIssue.invalidFormat,
    );
  }
  return field;
}

String? _wireOptionalString(Map<String, dynamic> value, String key) {
  final field = value[key];
  if (field == null) {
    return null;
  }
  if (field is! String) {
    throw InputValidationException(
      code: '${key}_invalid',
      issue: InputValidationIssue.invalidFormat,
    );
  }
  return field;
}

int? _wireOptionalInt(Map<String, dynamic> value, String key) {
  final field = value[key];
  if (field == null) {
    return null;
  }
  if (field is! int) {
    throw InputValidationException(
      code: '${key}_invalid',
      issue: InputValidationIssue.invalidFormat,
    );
  }
  return field;
}

void _max(String? value, int limit, {required String code, bool trim = true}) {
  if (value == null) {
    return;
  }
  final normalized = trim ? value.trim() : value;
  if (normalized.runes.length > limit) {
    throw InputValidationException(
      code: code,
      issue: InputValidationIssue.tooLong,
      maxLength: limit,
    );
  }
}

void _positive(int value, {required String code}) {
  if (value < 1) {
    throw InputValidationException(
      code: code,
      issue: InputValidationIssue.mustBePositive,
    );
  }
}

void _positiveIfPresent(int? value, {required String code}) {
  if (value != null) {
    _positive(value, code: code);
  }
}

void _nonNegative(int value, {required String code}) {
  if (value < 0) {
    throw InputValidationException(
      code: code,
      issue: InputValidationIssue.mustBeNonNegative,
    );
  }
}

void _nonNegativeIfPresent(int? value, {required String code}) {
  if (value != null) {
    _nonNegative(value, code: code);
  }
}
