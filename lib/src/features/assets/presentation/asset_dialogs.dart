part of '../../../../main.dart';

class MoveCopyItemDialog extends ConsumerStatefulWidget {
  const MoveCopyItemDialog({required this.asset, super.key});

  final Asset asset;

  @override
  ConsumerState<MoveCopyItemDialog> createState() => _MoveCopyItemDialogState();
}

class _MoveCopyItemDialogState extends ConsumerState<MoveCopyItemDialog> {
  static const _uuid = Uuid();
  String? _roomId;
  bool _copy = false;
  bool _includeTasks = true;
  bool _includePhotos = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _roomId = widget.asset.roomId;
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomsProvider);
    return _EditorSheetFrame(
      title: context.l10n.moveOrCopyItem,
      saveLabel: _saving
          ? context.l10n.saving
          : _copy
          ? context.l10n.copyItem
          : context.l10n.moveItem,
      saveEnabled: !_saving,
      onCancel: () => Navigator.of(context).pop(),
      onSave: _save,
      child: rooms.when(
        data: (items) {
          final activeRooms = items
              .where((room) => room.archivedAt == null)
              .toList(growable: false);
          final selectedRoomId = activeRooms.any((room) => room.id == _roomId)
              ? _roomId
              : activeRooms.firstOrNull?.id;
          if (activeRooms.isEmpty) {
            return hk_ui.PremiumEmptyState(
              icon: Symbols.meeting_room_rounded,
              title: context.l10n.createARoomFirst,
              body: context.l10n.itemsNeedARoomToMoveOrCopy,
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              hk_ui.PremiumCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(_iconForAssetType(widget.asset.assetType)),
                    const SizedBox(width: HkSpacing.xs),
                    Expanded(
                      child: DynamicText(
                        widget.asset.name,
                        contentType: 'asset.name',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HkSpacing.sm),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Symbols.drive_file_move_rounded),
                    label: Text(context.l10n.move),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Symbols.content_copy_rounded),
                    label: Text(context.l10n.copy),
                  ),
                ],
                selected: {_copy},
                onSelectionChanged: (values) =>
                    setState(() => _copy = values.single),
              ),
              const SizedBox(height: HkSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: selectedRoomId,
                decoration: InputDecoration(labelText: context.l10n.room),
                items: [
                  for (final room in activeRooms)
                    DropdownMenuItem(
                      value: room.id,
                      child: DynamicText(room.name, contentType: 'room.name'),
                    ),
                ],
                onChanged: (value) => setState(() => _roomId = value),
              ),
              if (_copy) ...[
                const SizedBox(height: HkSpacing.xs),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _includeTasks,
                  onChanged: (value) =>
                      setState(() => _includeTasks = value ?? true),
                  title: Text(context.l10n.includeRelatedTasks),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _includePhotos,
                  onChanged: (value) =>
                      setState(() => _includePhotos = value ?? false),
                  title: Text(context.l10n.includePhotos),
                ),
              ],
            ],
          );
        },
        error: (error, _) =>
            ErrorPanel(message: _failureMessage(context, error)),
        loading: () => const LinearProgressIndicator(),
      ),
    );
  }

  Future<void> _save() async {
    final rooms = ref.read(roomsProvider).value ?? const <Room>[];
    final activeRooms = rooms
        .where((room) => room.archivedAt == null)
        .toList(growable: false);
    final roomId = activeRooms.any((room) => room.id == _roomId)
        ? _roomId
        : activeRooms.firstOrNull?.id;
    if (_saving || roomId == null) {
      return;
    }
    if (!_copy && roomId == widget.asset.roomId) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      final repository = ref.read(assetRepositoryProvider);
      if (_copy) {
        final copiedAssetId = _uuid.v7();
        final copyOperationId = _uuid.v7();
        final sourceTasks = _includeTasks
            ? await ref
                  .read(maintenanceRepositoryProvider)
                  .listTasksForAsset(widget.asset.id)
            : const <TaskItem>[];
        final copiedTaskIds = <String, String>{
          for (final task in sourceTasks) task.plan.id: _uuid.v7(),
        };
        final monetization = ref.read(monetizationRepositoryProvider);
        if (monetization != null) {
          final online = await ref
              .read(syncConnectivityInstanceProvider)
              .isOnline();
          if (online) {
            try {
              final walletUserId = monetization.currentUserId;
              final debit = await monetization.createAsset({
                'operation_id': copyOperationId,
                'asset': {
                  'id': copiedAssetId,
                  'name': widget.asset.name,
                  'asset_type': widget.asset.assetType.name,
                  'room_id': roomId,
                  'placement': widget.asset.placement,
                  'notes': widget.asset.notes,
                  'purchase_date': widget.asset.purchaseDate
                      ?.toUtc()
                      .toIso8601String(),
                },
                'details': _assetDetailsPayload(widget.asset),
                'initial_plans': [
                  for (final task in sourceTasks)
                    {
                      'id': copiedTaskIds[task.plan.id],
                      'asset_id': copiedAssetId,
                      'title': task.plan.title,
                      'instructions': task.plan.instructions,
                      'recurrence_interval': task.plan.recurrence.interval,
                      'recurrence_unit': task.plan.recurrence.unit.name,
                      'priority': task.plan.priority.name,
                      'next_due_date': task.plan.nextDueDate
                          .toUtc()
                          .toIso8601String(),
                      'reminder_days_before': task.plan.reminderDaysBefore,
                      'is_enabled': true,
                      'metadata': _taskMetadataPayload(task.plan.metadata),
                    },
                ],
              });
              if (walletUserId != null) {
                ref
                    .read(pointWalletControllerProvider.notifier)
                    .adoptAuthoritativeMutationResult(
                      debit.balance,
                      userId: walletUserId,
                    );
              }
              if (debit.charged == 1) {
                unawaited(
                  monetization.recordEvent('points_debited', {
                    'entity_type': 'asset_copy',
                    'entity_id': copiedAssetId,
                    'cost': debit.charged,
                    'new_balance': debit.balance,
                    'included_task_count': sourceTasks.length,
                  }),
                );
              }
            } catch (_) {
              // Local save and offline sync coordinator will handle durability.
            }
          }
        }
        await repository.copyAsset(
          assetId: widget.asset.id,
          roomId: roomId,
          includeTasks: _includeTasks,
          includePhotos: _includePhotos,
          newAssetId: copiedAssetId,
          taskIdBySource: copiedTaskIds,
        );
      } else {
        await repository.moveAsset(assetId: widget.asset.id, roomId: roomId);
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        if (_isInsufficientPointsError(error)) {
          await showPointShortageDialog(context, ref, attemptedAction: 'asset');
          return;
        }
        hk_ui.showToast(
          context,
          content: Text(_failureMessage(context, error)),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

Map<String, dynamic> _assetDetailsPayload(Asset asset) =>
    switch (asset.assetType) {
      AssetType.device => {
        'brand': asset.deviceDetails?.brand,
        'model': asset.deviceDetails?.model,
        'serial_number': asset.deviceDetails?.serialNumber,
        'power_source': asset.deviceDetails?.powerSource?.name,
        'warranty_until': asset.deviceDetails?.warrantyUntil
            ?.toUtc()
            .toIso8601String(),
        'manual_url': asset.deviceDetails?.manualUrl,
        'consumable': asset.deviceDetails?.consumable,
      },
      AssetType.pet => {
        'species': asset.petDetails?.species,
        'breed': asset.petDetails?.breed,
        'birth_date': asset.petDetails?.birthDate?.toUtc().toIso8601String(),
        'microchip_id': asset.petDetails?.microchipId,
        'vet_name': asset.petDetails?.vetName,
        'vet_phone': asset.petDetails?.vetPhone,
        'feeding_notes': asset.petDetails?.feedingNotes,
        'medical_notes': asset.petDetails?.medicalNotes,
      },
      AssetType.plant => {
        'species': asset.plantDetails?.species,
        'sunlight': asset.plantDetails?.sunlight?.name,
        'watering_interval_days': asset.plantDetails?.wateringIntervalDays,
        'pot_size': asset.plantDetails?.potSize,
        'last_repotted_at': asset.plantDetails?.lastRepottedAt
            ?.toUtc()
            .toIso8601String(),
        'toxicity_notes': asset.plantDetails?.toxicityNotes,
      },
      AssetType.safety => {
        'safety_type': asset.safetyDetails?.safetyType,
        'installed_at': asset.safetyDetails?.installedAt
            ?.toUtc()
            .toIso8601String(),
        'expires_at': asset.safetyDetails?.expiresAt?.toUtc().toIso8601String(),
        'battery_type': asset.safetyDetails?.batteryType,
        'test_interval_days': asset.safetyDetails?.testIntervalDays,
      },
      AssetType.general => const <String, dynamic>{},
    };

Map<String, dynamic> _taskMetadataPayload(TaskMetadata? metadata) =>
    metadata == null
    ? const <String, dynamic>{}
    : {
        'task_type': metadata.taskType,
        'location_label': metadata.locationLabel,
        'estimated_duration_minutes': metadata.estimatedDurationMinutes,
        'required_materials': metadata.requiredMaterials,
        'reminder_recommendation': metadata.reminderRecommendation,
        'sort_order': metadata.sortOrder,
      };

String? _nullableEditText(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _commaList(String value) {
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Future<String?> showAreaEditorSheet(BuildContext context, {Area? area}) {
  return _showEditorModal<String>(
    context,
    builder: (context) => AreaEditorDialog(area: area),
  );
}

Future<String?> showRoomEditorSheet(
  BuildContext context, {
  required String areaId,
  Room? room,
}) {
  return _showEditorModal<String>(
    context,
    builder: (context) => RoomEditorDialog(areaId: areaId, room: room),
  );
}

Future<void> showAssetEditorSheet(
  BuildContext context, {
  Asset? asset,
  String? roomId,
}) {
  return _showEditorModal<void>(
    context,
    builder: (context) => AssetEditorDialog(asset: asset, roomId: roomId),
  );
}

Future<void> showMoveCopyItemSheet(BuildContext context, Asset asset) {
  return _showEditorModal<void>(
    context,
    builder: (context) => MoveCopyItemDialog(asset: asset),
  );
}

Future<void> startThingSetupFlow(BuildContext context, WidgetRef ref) async {
  final rooms = ref.read(roomsProvider).value ?? const <Room>[];
  if (rooms.isNotEmpty) {
    return showAssetEditorSheet(context, roomId: rooms.first.id);
  }
  final areas = ref.read(areasProvider).value ?? const <Area>[];
  if (areas.isNotEmpty) {
    final roomId = await showRoomEditorSheet(context, areaId: areas.first.id);
    if (roomId != null && context.mounted) {
      await showAssetEditorSheet(context, roomId: roomId);
    }
    return;
  }
  final areaId = await showAreaEditorSheet(context);
  if (areaId != null && context.mounted) {
    final roomId = await showRoomEditorSheet(context, areaId: areaId);
    if (roomId != null && context.mounted) {
      await showAssetEditorSheet(context, roomId: roomId);
    }
  }
}

Future<void> showPlanEditorSheet(
  BuildContext context, {
  TaskItem? task,
  String? assetId,
}) {
  return _showEditorModal<void>(
    context,
    builder: (context) => PlanEditorDialog(task: task, assetId: assetId),
  );
}

class AssetEditorDialog extends ConsumerStatefulWidget {
  const AssetEditorDialog({this.asset, this.roomId, super.key});

  final Asset? asset;
  final String? roomId;

  @override
  ConsumerState<AssetEditorDialog> createState() => _AssetEditorDialogState();
}

class _AssetEditorDialogState extends ConsumerState<AssetEditorDialog> {
  static const _uuid = Uuid();
  late final TextEditingController _nameController;
  late final TextEditingController _placementController;
  late final TextEditingController _notesController;
  late final TextEditingController _tagsController;
  late final TextEditingController _brandController;
  late final TextEditingController _modelController;
  late final TextEditingController _serialController;
  late final TextEditingController _manualController;
  late final TextEditingController _consumableController;
  late final TextEditingController _petSpeciesController;
  late final TextEditingController _petBreedController;
  late final TextEditingController _microchipController;
  late final TextEditingController _vetNameController;
  late final TextEditingController _vetPhoneController;
  late final TextEditingController _feedingController;
  late final TextEditingController _medicalController;
  late final TextEditingController _plantSpeciesController;
  late final TextEditingController _wateringController;
  late final TextEditingController _potSizeController;
  late final TextEditingController _toxicityController;
  late final TextEditingController _safetyTypeController;
  late final TextEditingController _batteryTypeController;
  late final TextEditingController _testIntervalController;
  AssetType _assetType = AssetType.general;
  String _petType = 'Dog';
  String _fishType = 'Goldfish';
  PowerSource _powerSource = PowerSource.mains;
  Sunlight _sunlight = Sunlight.medium;
  DateTime? _purchaseDate;
  DateTime? _warrantyUntil;
  DateTime? _petBirthDate;
  DateTime? _lastRepottedAt;
  DateTime? _installedAt;
  DateTime? _expiresAt;
  String? _areaId;
  String? _roomId;
  bool _saving = false;
  String? _creationOperationId;
  String? _creationAssetId;

  @override
  void initState() {
    super.initState();
    final asset = widget.asset;
    final device = asset?.deviceDetails;
    final pet = asset?.petDetails;
    final plant = asset?.plantDetails;
    final safety = asset?.safetyDetails;
    _assetType = asset?.assetType ?? AssetType.general;
    _nameController = TextEditingController(text: asset?.name ?? '');
    _nameController.addListener(_onFormChanged);
    _placementController = TextEditingController(text: asset?.placement ?? '');
    _notesController = TextEditingController(text: asset?.notes ?? '');
    _tagsController = TextEditingController();
    _brandController = TextEditingController(text: device?.brand ?? '');
    _modelController = TextEditingController(text: device?.model ?? '');
    _serialController = TextEditingController(text: device?.serialNumber ?? '');
    _manualController = TextEditingController(text: device?.manualUrl ?? '');
    _consumableController = TextEditingController(
      text: device?.consumable ?? '',
    );
    _petSpeciesController = TextEditingController(text: pet?.species ?? '');
    _petBreedController = TextEditingController(text: pet?.breed ?? '');
    _microchipController = TextEditingController(text: pet?.microchipId ?? '');
    _vetNameController = TextEditingController(text: pet?.vetName ?? '');
    _vetPhoneController = TextEditingController(text: pet?.vetPhone ?? '');
    _feedingController = TextEditingController(text: pet?.feedingNotes ?? '');
    _medicalController = TextEditingController(text: pet?.medicalNotes ?? '');
    _plantSpeciesController = TextEditingController(text: plant?.species ?? '');
    _wateringController = TextEditingController(
      text: plant?.wateringIntervalDays?.toString() ?? '',
    );
    _potSizeController = TextEditingController(text: plant?.potSize ?? '');
    _toxicityController = TextEditingController(
      text: plant?.toxicityNotes ?? '',
    );
    _safetyTypeController = TextEditingController(
      text: safety?.safetyType ?? '',
    );
    _batteryTypeController = TextEditingController(
      text: safety?.batteryType ?? '',
    );
    _testIntervalController = TextEditingController(
      text: safety?.testIntervalDays?.toString() ?? '',
    );
    _powerSource = device?.powerSource ?? PowerSource.mains;
    _petType = _petTypeOptions.contains(pet?.species)
        ? pet!.species!
        : (pet?.species?.trim().isNotEmpty ?? false)
        ? 'Other'
        : 'Dog';
    _fishType = _fishTypeOptions.contains(pet?.breed)
        ? pet!.breed!
        : (pet?.breed?.trim().isNotEmpty ?? false)
        ? 'Other'
        : 'Goldfish';
    _sunlight = plant?.sunlight ?? Sunlight.medium;
    _purchaseDate = asset?.purchaseDate;
    _warrantyUntil = device?.warrantyUntil;
    _petBirthDate = pet?.birthDate;
    _lastRepottedAt = plant?.lastRepottedAt;
    _installedAt = safety?.installedAt;
    _expiresAt = safety?.expiresAt;
    _roomId = asset?.roomId ?? widget.roomId;
    if (asset != null) {
      scheduleMicrotask(_loadInitialTags);
    } else {
      scheduleMicrotask(_restoreOfflineDraft);
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFormChanged);
    _nameController.dispose();
    _placementController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _serialController.dispose();
    _manualController.dispose();
    _consumableController.dispose();
    _petSpeciesController.dispose();
    _petBreedController.dispose();
    _microchipController.dispose();
    _vetNameController.dispose();
    _vetPhoneController.dispose();
    _feedingController.dispose();
    _medicalController.dispose();
    _plantSpeciesController.dispose();
    _wateringController.dispose();
    _potSizeController.dispose();
    _toxicityController.dispose();
    _safetyTypeController.dispose();
    _batteryTypeController.dispose();
    _testIntervalController.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  Future<void> _loadInitialTags() async {
    final asset = widget.asset;
    if (asset == null) {
      return;
    }
    final tags = await ref.read(assetTagsProvider(asset.id).future);
    if (!mounted || _tagsController.text.trim().isNotEmpty) {
      return;
    }
    _tagsController.text = tags.map((tag) => tag.name).join(', ');
  }

  String get _offlineDraftKey {
    final userId = ref.read(monetizationRepositoryProvider)?.currentUserId;
    return 'asset_${userId ?? 'local'}_${widget.roomId ?? 'any'}';
  }

  Future<void> _saveOfflineDraft() {
    String? date(DateTime? value) => value?.toUtc().toIso8601String();
    return ref.read(offlineCreationDraftStoreProvider).save(_offlineDraftKey, {
      'operation_id': _creationOperationId ??= _uuid.v7(),
      'asset_id': _creationAssetId ??= _uuid.v7(),
      'name': _nameController.text,
      'placement': _placementController.text,
      'notes': _notesController.text,
      'tags': _tagsController.text,
      'asset_type': _assetType.name,
      'power_source': _powerSource.name,
      'pet_type': _petType,
      'fish_type': _fishType,
      'sunlight': _sunlight.name,
      'purchase_date': date(_purchaseDate),
      'warranty_until': date(_warrantyUntil),
      'pet_birth_date': date(_petBirthDate),
      'last_repotted_at': date(_lastRepottedAt),
      'installed_at': date(_installedAt),
      'expires_at': date(_expiresAt),
      'area_id': _areaId,
      'room_id': _roomId,
      'brand': _brandController.text,
      'model': _modelController.text,
      'serial': _serialController.text,
      'manual': _manualController.text,
      'consumable': _consumableController.text,
      'pet_species': _petSpeciesController.text,
      'pet_breed': _petBreedController.text,
      'microchip': _microchipController.text,
      'vet_name': _vetNameController.text,
      'vet_phone': _vetPhoneController.text,
      'feeding': _feedingController.text,
      'medical': _medicalController.text,
      'plant_species': _plantSpeciesController.text,
      'watering': _wateringController.text,
      'pot_size': _potSizeController.text,
      'toxicity': _toxicityController.text,
      'safety_type': _safetyTypeController.text,
      'battery_type': _batteryTypeController.text,
      'test_interval': _testIntervalController.text,
    });
  }

  Future<void> _restoreOfflineDraft() async {
    final draft = await ref
        .read(offlineCreationDraftStoreProvider)
        .load(_offlineDraftKey);
    if (!mounted || draft == null || _nameController.text.isNotEmpty) return;
    String text(String key) => draft[key] as String? ?? '';
    DateTime? date(String key) => DateTime.tryParse(text(key))?.toLocal();
    _creationOperationId = draft['operation_id'] as String?;
    _creationAssetId = draft['asset_id'] as String?;
    _nameController.text = text('name');
    _placementController.text = text('placement');
    _notesController.text = text('notes');
    _tagsController.text = text('tags');
    _brandController.text = text('brand');
    _modelController.text = text('model');
    _serialController.text = text('serial');
    _manualController.text = text('manual');
    _consumableController.text = text('consumable');
    _petSpeciesController.text = text('pet_species');
    _petBreedController.text = text('pet_breed');
    _microchipController.text = text('microchip');
    _vetNameController.text = text('vet_name');
    _vetPhoneController.text = text('vet_phone');
    _feedingController.text = text('feeding');
    _medicalController.text = text('medical');
    _plantSpeciesController.text = text('plant_species');
    _wateringController.text = text('watering');
    _potSizeController.text = text('pot_size');
    _toxicityController.text = text('toxicity');
    _safetyTypeController.text = text('safety_type');
    _batteryTypeController.text = text('battery_type');
    _testIntervalController.text = text('test_interval');
    setState(() {
      _assetType =
          AssetType.values
              .where((value) => value.name == text('asset_type'))
              .firstOrNull ??
          AssetType.general;
      _powerSource =
          PowerSource.values
              .where((value) => value.name == text('power_source'))
              .firstOrNull ??
          PowerSource.mains;
      _sunlight =
          Sunlight.values
              .where((value) => value.name == text('sunlight'))
              .firstOrNull ??
          Sunlight.medium;
      _petType = text('pet_type').isEmpty ? 'Dog' : text('pet_type');
      _fishType = text('fish_type').isEmpty ? 'Goldfish' : text('fish_type');
      _purchaseDate = date('purchase_date');
      _warrantyUntil = date('warranty_until');
      _petBirthDate = date('pet_birth_date');
      _lastRepottedAt = date('last_repotted_at');
      _installedAt = date('installed_at');
      _expiresAt = date('expires_at');
      _areaId = draft['area_id'] as String?;
      _roomId = draft['room_id'] as String? ?? widget.roomId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final areas = ref.watch(areasProvider).value ?? [];
    final rooms = ref.watch(roomsProvider);
    final roomItems = rooms.value ?? [];
    final selectedRoom = _roomId == null
        ? null
        : roomItems.where((room) => room.id == _roomId).firstOrNull;
    final selectedAreaId =
        _areaId ?? selectedRoom?.areaId ?? areas.firstOrNull?.id;
    final visibleRooms = selectedAreaId == null
        ? roomItems
        : roomItems.where((room) => room.areaId == selectedAreaId).toList();
    final selectedRoomId = _roomId ?? visibleRooms.firstOrNull?.id;
    final saveEnabled =
        !_saving &&
        _nameController.text.trim().isNotEmpty &&
        selectedRoomId != null;
    return _EditorSheetFrame(
      title: widget.asset == null
          ? context.l10n.addItem
          : context.l10n.editItem,
      saveLabel: widget.asset == null
          ? context.l10n.createItem
          : context.l10n.saveItem,
      saveEnabled: saveEnabled,
      onCancel: () => Navigator.of(context).pop(),
      onSave: _save,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          hk_ui.PremiumCard(
            padding: const EdgeInsets.all(14),
            backgroundColor: HkColors.appSurfaceGreen,
            child: Row(
              children: [
                Icon(
                  _iconForAssetType(_assetType),
                  color: HkColors.appPrimaryDark,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.trackItemBody,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: HkColors.appPrimaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SubsectionTitle(
            title: context.l10n.basic,
            icon: Symbols.inventory_2_rounded,
          ),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: context.l10n.itemName),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AssetType>(
            key: const ValueKey('asset-item-type-picker'),
            initialValue: _assetType,
            decoration: InputDecoration(labelText: context.l10n.itemType),
            items: [
              for (final type in AssetType.values)
                DropdownMenuItem(
                  value: type,
                  child: Text(_assetTypeLabel(context, type)),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                _changeType(value);
              }
            },
          ),
          const SizedBox(height: 12),
          _SubsectionTitle(
            title: context.l10n.location,
            icon: Symbols.location_on_rounded,
          ),
          if (areas.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: selectedAreaId,
              decoration: InputDecoration(labelText: context.l10n.area),
              items: [
                for (final area in areas)
                  DropdownMenuItem(
                    value: area.id,
                    child: DynamicText(area.name, contentType: 'area.name'),
                  ),
              ],
              onChanged: (value) {
                final firstRoom = roomItems
                    .where((room) => room.areaId == value)
                    .firstOrNull;
                setState(() {
                  _areaId = value;
                  _roomId = firstRoom?.id;
                });
              },
            ),
          if (areas.isNotEmpty) const SizedBox(height: 12),
          rooms.when(
            data: (_) {
              final selected =
                  _roomId != null &&
                      visibleRooms.any((item) => item.id == _roomId)
                  ? _roomId
                  : visibleRooms.firstOrNull?.id;
              return DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: InputDecoration(labelText: context.l10n.roomOrZone),
                items: [
                  for (final item in visibleRooms)
                    DropdownMenuItem(
                      value: item.id,
                      child: DynamicText(item.name, contentType: 'room.name'),
                    ),
                ],
                onChanged: (value) => setState(() => _roomId = value),
              );
            },
            error: (error, _) => Text(_failureMessage(context, error)),
            loading: () => const LinearProgressIndicator(),
          ),
          const SizedBox(height: 12),
          _SubsectionTitle(
            title: context.l10n.details,
            icon: Symbols.category_rounded,
          ),
          TextField(
            controller: _placementController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: context.l10n.placement,
              hintText: context.l10n.shelfCornerBalconyKennelArea,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _pickDate(_purchaseDate, (value) {
              setState(() => _purchaseDate = value);
            }),
            icon: const Icon(Symbols.event_rounded),
            label: Text(
              _purchaseDate == null
                  ? context.l10n.purchaseDate
                  : context.l10n.purchasedDate(
                      _formatShortDate(context, _purchaseDate!),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(labelText: context.l10n.notes),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tagsController,
            decoration: InputDecoration(
              labelText: context.l10n.tags,
              hintText: context.l10n.commaSeparated,
            ),
          ),
          const SizedBox(height: 12),
          _typeSpecificFields(),
        ],
      ),
    );
  }

  Widget _typeSpecificFields() {
    return switch (_assetType) {
      AssetType.device => _deviceFields(),
      AssetType.pet => _petFields(),
      AssetType.plant => _plantFields(),
      AssetType.safety => _safetyFields(),
      AssetType.general => const SizedBox.shrink(),
    };
  }

  Widget _deviceFields() {
    return Column(
      children: [
        _SubsectionTitle(
          title: context.l10n.deviceDetails,
          icon: Symbols.memory_rounded,
        ),
        TextField(
          controller: _brandController,
          decoration: InputDecoration(labelText: context.l10n.brand),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _modelController,
          decoration: InputDecoration(labelText: context.l10n.model),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _serialController,
          decoration: InputDecoration(labelText: context.l10n.serialNumber),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<PowerSource>(
          initialValue: _powerSource,
          decoration: InputDecoration(labelText: context.l10n.powerSource),
          items: [
            for (final source in PowerSource.values)
              DropdownMenuItem(
                value: source,
                child: Text(_powerSourceLabel(context, source)),
              ),
          ],
          onChanged: (value) =>
              setState(() => _powerSource = value ?? _powerSource),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _pickDate(_warrantyUntil, (value) {
            setState(() => _warrantyUntil = value);
          }),
          icon: const Icon(Symbols.verified_user_rounded),
          label: Text(
            _warrantyUntil == null
                ? context.l10n.warrantyDate
                : context.l10n.warrantyUntilDate(
                    _formatShortDate(context, _warrantyUntil!),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _manualController,
          decoration: InputDecoration(labelText: context.l10n.manualUrl),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _consumableController,
          decoration: InputDecoration(
            labelText: context.l10n.consumable,
            hintText: context.l10n.filterBatteriesCartridges,
          ),
        ),
      ],
    );
  }

  Widget _petFields() {
    return Column(
      children: [
        _SubsectionTitle(
          title: context.l10n.petDetails,
          icon: Symbols.pets_rounded,
        ),
        DropdownButtonFormField<String>(
          initialValue: _petType,
          decoration: InputDecoration(labelText: context.l10n.petType),
          items: [
            for (final item in _petTypeOptions)
              DropdownMenuItem(
                value: item,
                child: Text(_petTypeLabel(context, item)),
              ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() => _petType = value);
          },
        ),
        const SizedBox(height: 12),
        if (_petType == 'Fish') ...[
          DropdownButtonFormField<String>(
            initialValue: _fishType,
            decoration: InputDecoration(labelText: context.l10n.fishType),
            items: [
              for (final item in _fishTypeOptions)
                DropdownMenuItem(
                  value: item,
                  child: Text(_fishTypeLabel(context, item)),
                ),
            ],
            onChanged: (value) =>
                setState(() => _fishType = value ?? _fishType),
          ),
          const SizedBox(height: 12),
          if (_fishType == 'Other') ...[
            TextField(
              controller: _petBreedController,
              decoration: InputDecoration(
                labelText: context.l10n.fishBreedOrType,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ] else if (_petType == 'Other') ...[
          TextField(
            controller: _petSpeciesController,
            decoration: InputDecoration(labelText: context.l10n.species),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _petBreedController,
            decoration: InputDecoration(labelText: context.l10n.breed),
          ),
          const SizedBox(height: 12),
        ] else ...[
          TextField(
            controller: _petBreedController,
            decoration: InputDecoration(labelText: context.l10n.breed),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: () => _pickDate(_petBirthDate, (value) {
            setState(() => _petBirthDate = value);
          }),
          icon: const Icon(Symbols.cake_rounded),
          label: Text(
            _petBirthDate == null
                ? context.l10n.birthDate
                : context.l10n.bornDate(
                    _formatShortDate(context, _petBirthDate!),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _microchipController,
          decoration: InputDecoration(labelText: context.l10n.microchipId),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _vetNameController,
          decoration: InputDecoration(labelText: context.l10n.vetName),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _vetPhoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: context.l10n.vetPhone),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _feedingController,
          maxLines: 2,
          decoration: InputDecoration(labelText: context.l10n.feedingNotes),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _medicalController,
          maxLines: 2,
          decoration: InputDecoration(labelText: context.l10n.medicalNotes),
        ),
      ],
    );
  }

  Widget _plantFields() {
    return Column(
      children: [
        _SubsectionTitle(
          title: context.l10n.plantDetails,
          icon: Symbols.yard_rounded,
        ),
        TextField(
          controller: _plantSpeciesController,
          decoration: InputDecoration(labelText: context.l10n.species),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Sunlight>(
          initialValue: _sunlight,
          decoration: InputDecoration(labelText: context.l10n.sunlight),
          items: [
            for (final item in Sunlight.values)
              DropdownMenuItem(
                value: item,
                child: Text(_sunlightLabel(context, item)),
              ),
          ],
          onChanged: (value) => setState(() => _sunlight = value ?? _sunlight),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _wateringController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: context.l10n.wateringInterval,
            suffixText: context.l10n.days2,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _potSizeController,
          decoration: InputDecoration(labelText: context.l10n.potSize),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _pickDate(_lastRepottedAt, (value) {
            setState(() => _lastRepottedAt = value);
          }),
          icon: const Icon(Symbols.potted_plant_rounded),
          label: Text(
            _lastRepottedAt == null
                ? context.l10n.lastRepotted
                : context.l10n.repottedDate(
                    _formatShortDate(context, _lastRepottedAt!),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _toxicityController,
          decoration: InputDecoration(labelText: context.l10n.toxicityNotes),
        ),
      ],
    );
  }

  Widget _safetyFields() {
    return Column(
      children: [
        _SubsectionTitle(
          title: context.l10n.safetyDetails,
          icon: Symbols.health_and_safety_rounded,
        ),
        TextField(
          controller: _safetyTypeController,
          decoration: InputDecoration(labelText: context.l10n.safetyType),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _pickDate(_installedAt, (value) {
            setState(() => _installedAt = value);
          }),
          icon: const Icon(Symbols.construction_rounded),
          label: Text(
            _installedAt == null
                ? context.l10n.installedDate
                : context.l10n.installedDateValue(
                    _formatShortDate(context, _installedAt!),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _pickDate(_expiresAt, (value) {
            setState(() => _expiresAt = value);
          }),
          icon: const Icon(Symbols.event_busy_rounded),
          label: Text(
            _expiresAt == null
                ? context.l10n.expirationDate
                : context.l10n.expiresDate(
                    _formatShortDate(context, _expiresAt!),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _batteryTypeController,
          decoration: InputDecoration(labelText: context.l10n.batteryType),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _testIntervalController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: context.l10n.testInterval,
            suffixText: context.l10n.days2,
          ),
        ),
      ],
    );
  }

  Future<void> _changeType(AssetType value) async {
    if (value == _assetType) {
      return;
    }
    if (_hasTypedDetailInput()) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.changeItemType),
          content: Text(context.l10n.changeItemTypeWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.change),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() => _assetType = value);
  }

  bool _hasTypedDetailInput() {
    return [
      _brandController,
      _modelController,
      _serialController,
      _manualController,
      _consumableController,
      _petSpeciesController,
      _petBreedController,
      _microchipController,
      _vetNameController,
      _vetPhoneController,
      _feedingController,
      _medicalController,
      _plantSpeciesController,
      _wateringController,
      _potSizeController,
      _toxicityController,
      _safetyTypeController,
      _batteryTypeController,
      _testIntervalController,
    ].any((controller) => controller.text.trim().isNotEmpty);
  }

  Future<void> _pickDate(
    DateTime? current,
    ValueChanged<DateTime?> onSelected,
  ) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (selected != null && mounted) {
      onSelected(selected);
    }
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final roomItems = ref.read(roomsProvider).value ?? const <Room>[];
    final selectedRoom = _roomId == null
        ? null
        : roomItems.where((room) => room.id == _roomId).firstOrNull;
    final selectedAreaId =
        _areaId ??
        selectedRoom?.areaId ??
        ref.read(areasProvider).value?.firstOrNull?.id;
    final visibleRooms = selectedAreaId == null
        ? roomItems
        : roomItems.where((room) => room.areaId == selectedAreaId).toList();
    final roomId =
        _roomId != null && visibleRooms.any((room) => room.id == _roomId)
        ? _roomId
        : visibleRooms.firstOrNull?.id;
    if (_nameController.text.trim().isEmpty || roomId == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      final isCreating = widget.asset == null;
      final assetId = widget.asset?.id ?? (_creationAssetId ??= _uuid.v7());
      PointDebitResult? debitResult;
      if (isCreating) {
        final online = await ref
            .read(syncConnectivityInstanceProvider)
            .isOnline();
        if (!online) {
          await _saveOfflineDraft();
          if (mounted) {
            hk_ui.showToast(
              context,
              content: Text(context.l10n.offlineItemDraftMessage),
            );
          }
          return;
        }
        final monetization = ref.read(monetizationRepositoryProvider);
        if (monetization == null) {
          throw StateError('Cloud points service is unavailable.');
        }
        final walletUserId = monetization.currentUserId;
        final debit = await monetization.createAsset({
          'operation_id': _creationOperationId ??= _uuid.v7(),
          'asset': {
            'id': assetId,
            'name': _nameController.text.trim(),
            'asset_type': _assetType.name,
            'room_id': roomId,
            'placement': _placementController.text.trim(),
            'notes': _notesController.text.trim(),
            'purchase_date': _purchaseDate?.toUtc().toIso8601String(),
          },
          'details': _pointAssetDetailsPayload(),
          'initial_plans': const <Map<String, dynamic>>[],
        });
        debitResult = debit;
        if (walletUserId != null) {
          ref
              .read(pointWalletControllerProvider.notifier)
              .adoptAuthoritativeMutationResult(
                debit.balance,
                userId: walletUserId,
              );
        }
      }
      await ref
          .read(assetRepositoryProvider)
          .saveAsset(
            id: assetId,
            name: _nameController.text,
            assetType: _assetType,
            roomId: roomId,
            placement: _placementController.text,
            notes: _notesController.text,
            purchaseDate: _purchaseDate,
            tagNames: _tagsController.text.split(','),
            deviceDetails: _assetType == AssetType.device
                ? DeviceDetails(
                    brand: _brandController.text,
                    model: _modelController.text,
                    serialNumber: _serialController.text,
                    powerSource: _powerSource,
                    warrantyUntil: _warrantyUntil,
                    manualUrl: _manualController.text,
                    consumable: _consumableController.text,
                  )
                : null,
            petDetails: _assetType == AssetType.pet
                ? PetDetails(
                    species: _petType == 'Other'
                        ? _petSpeciesController.text
                        : _petType,
                    breed: _petType == 'Fish'
                        ? _fishType == 'Other'
                              ? _petBreedController.text
                              : _fishType
                        : _petBreedController.text,
                    birthDate: _petBirthDate,
                    microchipId: _microchipController.text,
                    vetName: _vetNameController.text,
                    vetPhone: _vetPhoneController.text,
                    feedingNotes: _feedingController.text,
                    medicalNotes: _medicalController.text,
                  )
                : null,
            plantDetails: _assetType == AssetType.plant
                ? PlantDetails(
                    species: _plantSpeciesController.text,
                    sunlight: _sunlight,
                    wateringIntervalDays: int.tryParse(
                      _wateringController.text,
                    ),
                    potSize: _potSizeController.text,
                    lastRepottedAt: _lastRepottedAt,
                    toxicityNotes: _toxicityController.text,
                  )
                : null,
            safetyDetails: _assetType == AssetType.safety
                ? SafetyDetails(
                    safetyType: _safetyTypeController.text,
                    installedAt: _installedAt,
                    expiresAt: _expiresAt,
                    batteryType: _batteryTypeController.text,
                    testIntervalDays: int.tryParse(
                      _testIntervalController.text,
                    ),
                  )
                : null,
          );
      if (isCreating) {
        await ref
            .read(offlineCreationDraftStoreProvider)
            .clear(_offlineDraftKey);
        if (debitResult?.asset != null) {
          await ref
              .read(localSyncStoreProvider)
              ?.reconcileAssetCreationComposite(
                assetId: assetId,
                assetJson: debitResult!.asset,
              );
        }
      }
      if (debitResult?.charged == 1) {
        unawaited(
          ref.read(monetizationRepositoryProvider)?.recordEvent(
            'points_debited',
            {
              'entity_type': 'asset',
              'entity_id': assetId,
              'cost': debitResult!.charged,
              'new_balance': debitResult.balance,
            },
          ),
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        if (_isInsufficientPointsError(error)) {
          await showPointShortageDialog(context, ref, attemptedAction: 'asset');
          return;
        }
        hk_ui.showToast(
          context,
          content: Text(_failureMessage(context, error)),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Map<String, dynamic> _pointAssetDetailsPayload() => switch (_assetType) {
    AssetType.device => {
      'brand': _brandController.text.trim(),
      'model': _modelController.text.trim(),
      'serial_number': _serialController.text.trim(),
      'power_source': _powerSource.name,
      'warranty_until': _warrantyUntil?.toUtc().toIso8601String(),
      'manual_url': _manualController.text.trim(),
      'consumable': _consumableController.text.trim(),
    },
    AssetType.pet => {
      'species': _petType == 'Other'
          ? _petSpeciesController.text.trim()
          : _petType,
      'breed': _petType == 'Fish'
          ? _fishType == 'Other'
                ? _petBreedController.text.trim()
                : _fishType
          : _petBreedController.text.trim(),
      'birth_date': _petBirthDate?.toUtc().toIso8601String(),
      'microchip_id': _microchipController.text.trim(),
      'vet_name': _vetNameController.text.trim(),
      'vet_phone': _vetPhoneController.text.trim(),
      'feeding_notes': _feedingController.text.trim(),
      'medical_notes': _medicalController.text.trim(),
    },
    AssetType.plant => {
      'species': _plantSpeciesController.text.trim(),
      'sunlight': _sunlight.name,
      'watering_interval_days': int.tryParse(_wateringController.text),
      'pot_size': _potSizeController.text.trim(),
      'last_repotted_at': _lastRepottedAt?.toUtc().toIso8601String(),
      'toxicity_notes': _toxicityController.text.trim(),
    },
    AssetType.safety => {
      'safety_type': _safetyTypeController.text.trim(),
      'installed_at': _installedAt?.toUtc().toIso8601String(),
      'expires_at': _expiresAt?.toUtc().toIso8601String(),
      'battery_type': _batteryTypeController.text.trim(),
      'test_interval_days': int.tryParse(_testIntervalController.text),
    },
    AssetType.general => const <String, dynamic>{},
  };
}

class _SubsectionTitle extends StatelessWidget {
  const _SubsectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: HkSpacing.xs, bottom: HkSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: HkSpacing.xs),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ],
      ),
    );
  }
}
