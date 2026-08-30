import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/domain/input_validation.dart';
import 'package:owntend/src/core/domain/models.dart';

String _text(int length, [String value = 'x']) =>
    List<String>.filled(length, value).join();

void main() {
  group('asset validation contract', () {
    test('accepts the maximum asset name and rejects max + 1', () {
      validateAssetInput(
        name: _text(InputValidationLimits.assetName, 'a'),
        roomId: 'room-1',
        assetType: AssetType.general,
      );

      expect(
        () => validateAssetInput(
          name: _text(InputValidationLimits.assetName + 1, 'a'),
          roomId: 'room-1',
          assetType: AssetType.general,
        ),
        throwsA(
          isA<InputValidationException>()
              .having((error) => error.code, 'code', 'asset_name_too_long')
              .having(
                (error) => error.maxLength,
                'maxLength',
                InputValidationLimits.assetName,
              ),
        ),
      );
    });

    test('enforces detail text limits before persistence or RPC', () {
      validateAssetInput(
        name: 'Device',
        roomId: 'room-1',
        assetType: AssetType.device,
        deviceDetails: DeviceDetails(
          manualUrl: _text(InputValidationLimits.deviceManualUrl, 'm'),
          consumable: _text(InputValidationLimits.deviceConsumable, 'c'),
        ),
      );

      expect(
        () => validateAssetInput(
          name: 'Device',
          roomId: 'room-1',
          assetType: AssetType.device,
          deviceDetails: DeviceDetails(
            manualUrl: _text(InputValidationLimits.deviceManualUrl + 1, 'm'),
          ),
        ),
        throwsA(
          isA<InputValidationException>().having(
            (error) => error.code,
            'code',
            'device_manual_url_too_long',
          ),
        ),
      );
    });

    test('watering and safety intervals must be positive when present', () {
      validateAssetInput(
        name: 'Plant',
        roomId: 'room-1',
        assetType: AssetType.plant,
        plantDetails: const PlantDetails(wateringIntervalDays: 1),
      );

      for (final invalid in [0, -1]) {
        expect(
          () => validateAssetInput(
            name: 'Plant',
            roomId: 'room-1',
            assetType: AssetType.plant,
            plantDetails: PlantDetails(wateringIntervalDays: invalid),
          ),
          throwsA(
            isA<InputValidationException>().having(
              (error) => error.code,
              'code',
              'plant_watering_interval_invalid',
            ),
          ),
        );
        expect(
          () => validateAssetInput(
            name: 'Alarm',
            roomId: 'room-1',
            assetType: AssetType.safety,
            safetyDetails: SafetyDetails(testIntervalDays: invalid),
          ),
          throwsA(isA<InputValidationException>()),
        );
      }
    });

    test(
      'wire payload validation rejects invalid values before journaling',
      () {
        expect(
          () => validateAuthoritativeAssetPayload(
            {'name': 'Plant', 'room_id': 'room-1', 'asset_type': 'plant'},
            {'watering_interval_days': 0},
          ),
          throwsA(
            isA<InputValidationException>().having(
              (error) => error.code,
              'code',
              'plant_watering_interval_invalid',
            ),
          ),
        );
      },
    );
  });

  group('maintenance validation contract', () {
    const recurrence = RecurrenceRule(interval: 1, unit: RecurrenceUnit.months);

    test('accepts title maximum and rejects max + 1', () {
      validateMaintenancePlanInput(
        assetId: 'asset-1',
        title: _text(InputValidationLimits.maintenanceTitle, 't'),
        recurrence: recurrence,
        reminderDaysBefore: 0,
      );

      expect(
        () => validateMaintenancePlanInput(
          assetId: 'asset-1',
          title: _text(InputValidationLimits.maintenanceTitle + 1, 't'),
          recurrence: recurrence,
          reminderDaysBefore: 0,
        ),
        throwsA(
          isA<InputValidationException>().having(
            (error) => error.code,
            'code',
            'maintenance_title_too_long',
          ),
        ),
      );
    });

    test('serialized material maximum is enforced exactly', () {
      validateMaintenancePlanInput(
        assetId: 'asset-1',
        title: 'Task',
        recurrence: recurrence,
        reminderDaysBefore: 0,
        metadata: TaskMetadata(
          requiredMaterials: [
            _text(
              InputValidationLimits.maintenanceRequiredMaterialsJson - 4,
              'm',
            ),
          ],
        ),
      );

      expect(
        () => validateMaintenancePlanInput(
          assetId: 'asset-1',
          title: 'Task',
          recurrence: recurrence,
          reminderDaysBefore: 0,
          metadata: TaskMetadata(
            requiredMaterials: [
              _text(
                InputValidationLimits.maintenanceRequiredMaterialsJson - 3,
                'm',
              ),
            ],
          ),
        ),
        throwsA(
          isA<InputValidationException>().having(
            (error) => error.code,
            'code',
            'maintenance_materials_too_long',
          ),
        ),
      );
    });

    test('duration accepts zero and rejects negative values', () {
      validateMaintenancePlanInput(
        assetId: 'asset-1',
        title: 'Task',
        recurrence: recurrence,
        reminderDaysBefore: 0,
        metadata: const TaskMetadata(estimatedDurationMinutes: 0),
      );

      expect(
        () => validateMaintenancePlanInput(
          assetId: 'asset-1',
          title: 'Task',
          recurrence: recurrence,
          reminderDaysBefore: 0,
          metadata: const TaskMetadata(estimatedDurationMinutes: -1),
        ),
        throwsA(
          isA<InputValidationException>().having(
            (error) => error.code,
            'code',
            'maintenance_duration_invalid',
          ),
        ),
      );
    });

    test('recurrence and reminder reject zero or negative boundaries', () {
      expect(
        () => validateMaintenancePlanInput(
          assetId: 'asset-1',
          title: 'Task',
          recurrence: const RecurrenceRule(
            interval: 0,
            unit: RecurrenceUnit.days,
          ),
          reminderDaysBefore: 0,
        ),
        throwsA(isA<InputValidationException>()),
      );
      expect(
        () => validateMaintenancePlanInput(
          assetId: 'asset-1',
          title: 'Task',
          recurrence: recurrence,
          reminderDaysBefore: -1,
        ),
        throwsA(isA<InputValidationException>()),
      );
    });
  });
}
