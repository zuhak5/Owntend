import '../../../ui/components.dart' as hk_ui;
import '../../../ui/presentation_support.dart';

class AreaEditorDialog extends ConsumerStatefulWidget {
  const AreaEditorDialog({this.area, super.key});

  final Area? area;

  @override
  ConsumerState<AreaEditorDialog> createState() => _AreaEditorDialogState();
}

class _AreaEditorDialogState extends ConsumerState<AreaEditorDialog> {
  late final TextEditingController _nameController;
  late AreaKind _kind;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.area?.name ?? '');
    _nameController.addListener(_onFormChanged);
    _kind = widget.area?.kind ?? AreaKind.indoor;
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFormChanged);
    _nameController.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return EditorSheetFrame(
      title: widget.area == null ? context.l10n.addArea : context.l10n.editArea,
      saveLabel: widget.area == null
          ? context.l10n.createArea
          : context.l10n.saveArea,
      saveEnabled: !_saving && _nameController.text.trim().isNotEmpty,
      onCancel: () => Navigator.of(context).pop(),
      onSave: _save,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: context.l10n.areaName),
          ),
          const SizedBox(height: HkSpacing.sm),
          DropdownButtonFormField<AreaKind>(
            initialValue: _kind,
            decoration: InputDecoration(labelText: context.l10n.areaType),
            items: [
              for (final kind in AreaKind.values)
                DropdownMenuItem(
                  value: kind,
                  child: Text(areaKindLabel(context, kind)),
                ),
            ],
            onChanged: (value) => setState(() => _kind = value ?? _kind),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || _nameController.text.trim().isEmpty) {
      return;
    }
    setState(() => _saving = true);
    final editing = widget.area != null;
    AppLogger.info('area_save_started', fields: {'editing': editing});
    try {
      final repository = ref.read(assetRepositoryProvider);
      final areaId = await repository.saveArea(
        id: widget.area?.id,
        name: _nameController.text,
        kind: _kind,
      );
      final localAreaCount = (await repository.listAreas()).length;
      AppLogger.info(
        'area_save_completed',
        fields: {'editing': editing, 'local_area_count': localAreaCount},
      );
      if (mounted) {
        Navigator.of(context).pop(areaId);
      }
    } catch (error) {
      AppLogger.warning(
        'area_save_failed',
        error: error,
        fields: {'editing': editing},
      );
      if (mounted) {
        hk_ui.showToast(
          context,
          content: Text(failureMessage(context, error)),
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

class RoomEditorDialog extends ConsumerStatefulWidget {
  const RoomEditorDialog({required this.areaId, this.room, super.key});

  final String areaId;
  final Room? room;

  @override
  ConsumerState<RoomEditorDialog> createState() => _RoomEditorDialogState();
}

class _RoomEditorDialogState extends ConsumerState<RoomEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  late RoomType _roomType;
  late String _areaId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.room?.name ?? '');
    _nameController.addListener(_onFormChanged);
    _notesController = TextEditingController(text: widget.room?.notes ?? '');
    _roomType = widget.room?.roomType ?? RoomType.other;
    _areaId = widget.room?.areaId ?? widget.areaId;
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFormChanged);
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  bool get _isDirty {
    final initialName = widget.room?.name ?? '';
    final initialNotes = widget.room?.notes ?? '';
    final initialType = widget.room?.roomType ?? RoomType.other;
    final initialAreaId = widget.room?.areaId ?? widget.areaId;
    return _nameController.text != initialName ||
        _notesController.text != initialNotes ||
        _roomType != initialType ||
        _areaId != initialAreaId;
  }

  Future<void> _handleCancel() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.discardChangesTitle),
        content: Text(context.l10n.discardChangesMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.keepEditingAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.discardChangesAction),
          ),
        ],
      ),
    );
    if (shouldDiscard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final areas = ref.watch(areasProvider).value ?? [];
    final selectedArea = areas.where((area) => area.id == _areaId).firstOrNull;
    final areaKind = selectedArea?.kind ?? AreaKind.indoor;
    final isOutdoor = areaKind == AreaKind.outdoor;
    final typeItems = roomTypesFor(areaKind);
    final selectedType = typeItems.contains(_roomType)
        ? _roomType
        : typeItems.first;
    return EditorSheetFrame(
      title: widget.room == null
          ? isOutdoor
                ? context.l10n.addZone
                : context.l10n.addRoom
          : isOutdoor
          ? context.l10n.editZone
          : context.l10n.editRoom,
      saveLabel: widget.room == null
          ? isOutdoor
                ? context.l10n.createZone
                : context.l10n.createRoom
          : isOutdoor
          ? context.l10n.saveZone
          : context.l10n.saveRoom,
      saveEnabled: !_saving && _nameController.text.trim().isNotEmpty,
      onCancel: _handleCancel,
      onSave: _save,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: isOutdoor
                  ? context.l10n.zoneName
                  : context.l10n.roomName,
            ),
          ),
          const SizedBox(height: HkSpacing.sm),
          DropdownButtonFormField<RoomType>(
            initialValue: selectedType,
            decoration: InputDecoration(
              labelText: isOutdoor
                  ? context.l10n.zoneType
                  : context.l10n.roomType,
            ),
            items: [
              for (final type in typeItems)
                DropdownMenuItem(
                  value: type,
                  child: Text(roomTypeLabel(context, type)),
                ),
            ],
            onChanged: (value) =>
                setState(() => _roomType = value ?? _roomType),
          ),
          const SizedBox(height: HkSpacing.sm),
          if (areas.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              initialValue: areas.any((area) => area.id == _areaId)
                  ? _areaId
                  : areas.first.id,
              decoration: InputDecoration(labelText: context.l10n.area),
              items: [
                for (final area in areas)
                  DropdownMenuItem(
                    value: area.id,
                    child: DynamicText(area.name, contentType: 'area.name'),
                  ),
              ],
              onChanged: (value) {
                final nextArea = areas
                    .where((area) => area.id == value)
                    .firstOrNull;
                final nextTypes = roomTypesFor(
                  nextArea?.kind ?? AreaKind.indoor,
                );
                setState(() {
                  _areaId = value ?? _areaId;
                  if (!nextTypes.contains(_roomType)) {
                    _roomType = nextTypes.first;
                  }
                });
              },
            ),
            const SizedBox(height: HkSpacing.sm),
          ],
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(labelText: context.l10n.notes),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || _nameController.text.trim().isEmpty) {
      return;
    }
    final areas = ref.read(areasProvider).value ?? [];
    final areaKind =
        areas.where((area) => area.id == _areaId).firstOrNull?.kind ??
        AreaKind.indoor;
    final allowedTypes = roomTypesFor(areaKind);
    setState(() => _saving = true);
    try {
      final roomId = await ref
          .read(assetRepositoryProvider)
          .saveRoom(
            id: widget.room?.id,
            areaId: _areaId,
            name: _nameController.text,
            roomType: allowedTypes.contains(_roomType)
                ? _roomType
                : allowedTypes.first,
            notes: _notesController.text,
          );
      if (mounted) {
        Navigator.of(context).pop(roomId);
      }
    } catch (error) {
      if (mounted) {
        hk_ui.showToast(
          context,
          content: Text(failureMessage(context, error)),
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
