part of '../../../../main.dart';

class CompleteTaskDialog extends StatefulWidget {
  const CompleteTaskDialog({required this.task, super.key});

  final TaskItem task;

  @override
  State<CompleteTaskDialog> createState() => _CompleteTaskDialogState();
}

class _CompleteTaskDialogState extends State<CompleteTaskDialog> {
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _EditorSheetFrame(
      title: context.l10n.completeTaskTitleCase,
      saveLabel: context.l10n.completeAction,
      onCancel: () => Navigator.of(context).pop(),
      onSave: () => Navigator.of(context).pop(_notesController.text),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          hk_ui.PremiumCard(
            padding: const EdgeInsets.all(14),
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              '${widget.task.plan.title} - ${widget.task.asset.name}',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onPrimary),
            ),
          ),
          const SizedBox(height: HkSpacing.sm),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: context.l10n.completionNotes,
              hintText:
                  context.l10n.whatChangedWhatWasReplacedOrWhatNeedsFollowUp,
            ),
          ),
        ],
      ),
    );
  }
}

Future<T?> _showEditorModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return runWithNativeAdsSuspended(
    context,
    () => showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (sheetContext) {
        final keyboardInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return SizedBox(
          key: const ValueKey('editor-modal-hit-surface'),
          height: MediaQuery.sizeOf(sheetContext).height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(sheetContext).pop(),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: keyboardInset,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: builder(sheetContext),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _EditorSheetFrame extends StatelessWidget {
  const _EditorSheetFrame({
    required this.title,
    required this.saveLabel,
    required this.onCancel,
    required this.onSave,
    required this.child,
    this.saveEnabled = true,
    this.secondarySaveLabel,
    this.onSecondarySave,
  });

  final String title;
  final String saveLabel;
  final bool saveEnabled;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final String? secondarySaveLabel;
  final VoidCallback? onSecondarySave;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight = MediaQuery.sizeOf(context).height - keyboardInset;
    final maxHeight = math.max(240.0, availableHeight * 0.92);
    return Material(
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(HkRadii.xxl),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: HkSpacing.xs),
            Center(
              child: Container(
                key: const ValueKey('editor-sheet-drag-handle'),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(HkRadii.full),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HkSpacing.md,
                HkSpacing.xs,
                HkSpacing.xs,
                HkSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.close,
                    onPressed: onCancel,
                    icon: const Icon(Symbols.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  HkSpacing.md,
                  0,
                  HkSpacing.md,
                  HkSpacing.md,
                ),
                child: child,
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  HkSpacing.md,
                  HkSpacing.xs,
                  HkSpacing.md,
                  HkSpacing.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (secondarySaveLabel != null &&
                        onSecondarySave != null) ...[
                      OutlinedButton(
                        onPressed: saveEnabled ? onSecondarySave : null,
                        child: Text(secondarySaveLabel!),
                      ),
                      const SizedBox(height: HkSpacing.xs),
                    ],
                    FilledButton(
                      onPressed: saveEnabled ? onSave : null,
                      child: Text(saveLabel),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlanEditorDialog extends ConsumerStatefulWidget {
  const PlanEditorDialog({this.task, this.assetId, super.key});

  final TaskItem? task;
  final String? assetId;

  @override
  ConsumerState<PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends ConsumerState<PlanEditorDialog> {
  static const _uuid = Uuid();
  late final TextEditingController _titleController;
  late final TextEditingController _instructionsController;
  late final TextEditingController _intervalController;
  late final TextEditingController _taskTypeController;
  late final TextEditingController _locationController;
  late final TextEditingController _durationController;
  late final TextEditingController _materialsController;
  late final TextEditingController _reminderDaysController;
  late final TextEditingController _reminderRecommendationController;
  String? _assetId;
  late RecurrenceUnit _unit;
  late PriorityLevel _priority;
  late DateTime _dueDate;
  bool _saving = false;
  String? _creationOperationId;
  String? _creationPlanId;

  @override
  void initState() {
    super.initState();
    final plan = widget.task?.plan;
    _titleController = TextEditingController(text: plan?.title ?? '');
    _titleController.addListener(_onFormChanged);
    _instructionsController = TextEditingController(
      text: plan?.instructions ?? '',
    );
    _intervalController = TextEditingController(
      text: plan?.recurrence.interval.toString() ?? '1',
    );
    _intervalController.addListener(_onFormChanged);
    final metadata = plan?.metadata;
    _taskTypeController = TextEditingController(text: metadata?.taskType ?? '');
    _locationController = TextEditingController(
      text: metadata?.locationLabel ?? '',
    );
    _durationController = TextEditingController(
      text: metadata?.estimatedDurationMinutes?.toString() ?? '',
    );
    _durationController.addListener(_onFormChanged);
    _materialsController = TextEditingController(
      text: metadata?.requiredMaterials.join(', ') ?? '',
    );
    _reminderDaysController = TextEditingController(
      text: plan?.reminderDaysBefore.toString() ?? '0',
    );
    _reminderDaysController.addListener(_onFormChanged);
    _reminderRecommendationController = TextEditingController(
      text: metadata?.reminderRecommendation ?? '',
    );
    _assetId = plan?.assetId ?? widget.assetId;
    _unit = plan?.recurrence.unit ?? RecurrenceUnit.months;
    _priority = plan?.priority ?? PriorityLevel.medium;
    _dueDate = plan?.nextDueDate ?? _nextDefaultPlanDueDate();
    if (plan == null) scheduleMicrotask(_restoreOfflineDraft);
  }

  @override
  void dispose() {
    _titleController.removeListener(_onFormChanged);
    _intervalController.removeListener(_onFormChanged);
    _durationController.removeListener(_onFormChanged);
    _reminderDaysController.removeListener(_onFormChanged);
    _titleController.dispose();
    _instructionsController.dispose();
    _intervalController.dispose();
    _taskTypeController.dispose();
    _locationController.dispose();
    _durationController.dispose();
    _materialsController.dispose();
    _reminderDaysController.dispose();
    _reminderRecommendationController.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  DateTime _nextDefaultPlanDueDate() {
    final reminderHour =
        ref.read(notificationPreferencesProvider).value?.reminderHour ??
        const NotificationPreferences().reminderHour;
    return _defaultPlanDueDate(reminderHour: reminderHour);
  }

  String get _offlineDraftKey {
    final userId = ref.read(monetizationRepositoryProvider)?.currentUserId;
    return 'task_${userId ?? 'local'}_${widget.assetId ?? 'any'}';
  }

  Future<void> _saveOfflineDraft() {
    return ref.read(offlineCreationDraftStoreProvider).save(_offlineDraftKey, {
      'operation_id': _creationOperationId ??= _uuid.v7(),
      'plan_id': _creationPlanId ??= _uuid.v7(),
      'asset_id': _assetId,
      'title': _titleController.text,
      'instructions': _instructionsController.text,
      'interval': _intervalController.text,
      'unit': _unit.name,
      'priority': _priority.name,
      'due_date': _dueDate.toUtc().toIso8601String(),
      'task_type': _taskTypeController.text,
      'location': _locationController.text,
      'duration': _durationController.text,
      'materials': _materialsController.text,
      'reminder_days': _reminderDaysController.text,
      'reminder_recommendation': _reminderRecommendationController.text,
    });
  }

  Future<void> _restoreOfflineDraft() async {
    final draft = await ref
        .read(offlineCreationDraftStoreProvider)
        .load(_offlineDraftKey);
    if (!mounted || draft == null || _titleController.text.isNotEmpty) return;
    String text(String key) => draft[key] as String? ?? '';
    _creationOperationId = draft['operation_id'] as String?;
    _creationPlanId = draft['plan_id'] as String?;
    _titleController.text = text('title');
    _instructionsController.text = text('instructions');
    _intervalController.text = text('interval').isEmpty
        ? '1'
        : text('interval');
    _taskTypeController.text = text('task_type');
    _locationController.text = text('location');
    _durationController.text = text('duration');
    _materialsController.text = text('materials');
    _reminderDaysController.text = text('reminder_days').isEmpty
        ? '0'
        : text('reminder_days');
    _reminderRecommendationController.text = text('reminder_recommendation');
    setState(() {
      _assetId = draft['asset_id'] as String? ?? widget.assetId;
      _unit =
          RecurrenceUnit.values
              .where((value) => value.name == text('unit'))
              .firstOrNull ??
          RecurrenceUnit.months;
      _priority =
          PriorityLevel.values
              .where((value) => value.name == text('priority'))
              .firstOrNull ??
          PriorityLevel.medium;
      _dueDate =
          DateTime.tryParse(text('due_date'))?.toLocal() ??
          _nextDefaultPlanDueDate();
    });
  }

  bool get _metadataNumbersValid {
    final durationText = _durationController.text.trim();
    final reminderText = _reminderDaysController.text.trim();
    final duration = durationText.isEmpty ? null : int.tryParse(durationText);
    final reminder = reminderText.isEmpty ? 0 : int.tryParse(reminderText);
    return (durationText.isEmpty || (duration != null && duration > 0)) &&
        reminder != null &&
        reminder >= 0;
  }

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(assetsProvider);
    final saveEnabled = assets.maybeWhen(
      data: (items) =>
          !_saving &&
          items.isNotEmpty &&
          _titleController.text.trim().isNotEmpty &&
          (int.tryParse(_intervalController.text) ?? 0) > 0 &&
          _metadataNumbersValid,
      orElse: () => false,
    );
    return _EditorSheetFrame(
      title: widget.task == null ? context.l10n.addTask : context.l10n.editTask,
      saveLabel: widget.task == null
          ? context.l10n.createTask
          : context.l10n.saveTask,
      secondarySaveLabel: widget.task == null
          ? context.l10n.createAndAddAnother
          : null,
      onSecondarySave: widget.task == null
          ? () => _save(closeAfterSave: false)
          : null,
      saveEnabled: saveEnabled,
      onCancel: () => Navigator.of(context).pop(),
      onSave: () => _save(closeAfterSave: true),
      child: assets.when(
        data: (items) {
          if (items.isEmpty) {
            return hk_ui.PremiumEmptyState(
              icon: Icons.inventory_2_outlined,
              title: context.l10n.createAnItemFirst,
              body: context.l10n.maintenancePlansNeedItemBody,
            );
          }
          final selected =
              _assetId != null && items.any((item) => item.id == _assetId)
              ? _assetId
              : items.first.id;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              hk_ui.PremiumCard(
                padding: const EdgeInsets.all(10),
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.task_alt_rounded,
                      color: Theme.of(context).colorScheme.onPrimary,
                      size: 18,
                    ),
                    const SizedBox(width: HkSpacing.xs),
                    Expanded(
                      child: Text(
                        context.l10n.planEditorIntro,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HkSpacing.xs),
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: InputDecoration(labelText: context.l10n.item),
                items: [
                  for (final item in items)
                    DropdownMenuItem(
                      value: item.id,
                      child: DynamicText(item.name, contentType: 'asset.name'),
                    ),
                ],
                onChanged: (value) => setState(() => _assetId = value),
              ),
              const SizedBox(height: HkSpacing.xs),
              TextField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: context.l10n.taskTitle),
              ),
              const SizedBox(height: HkSpacing.xs),
              TextField(
                controller: _instructionsController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.l10n.instructions,
                ),
              ),
              const SizedBox(height: HkSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _intervalController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.l10n.every,
                      ),
                    ),
                  ),
                  const SizedBox(width: HkSpacing.xs),
                  Expanded(
                    child: DropdownButtonFormField<RecurrenceUnit>(
                      initialValue: _unit,
                      decoration: InputDecoration(labelText: context.l10n.unit),
                      items: [
                        for (final item in RecurrenceUnit.values)
                          DropdownMenuItem(
                            value: item,
                            child: Text(_recurrenceUnitLabel(context, item)),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _unit = value ?? _unit),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HkSpacing.xs),
              DropdownButtonFormField<PriorityLevel>(
                initialValue: _priority,
                decoration: InputDecoration(labelText: context.l10n.priority),
                items: [
                  for (final item in PriorityLevel.values)
                    DropdownMenuItem(
                      value: item,
                      child: Text(_priorityLabel(context, item)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _priority = value ?? _priority),
              ),
              const SizedBox(height: HkSpacing.xs),
              TextField(
                controller: _taskTypeController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.l10n.taskType,
                  hintText: context.l10n.inspectionCleaningFeeding,
                ),
              ),
              const SizedBox(height: HkSpacing.xs),
              TextField(
                controller: _locationController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.l10n.locationLabel,
                  hintText: context.l10n.topShelfLeftCabinet,
                ),
              ),
              const SizedBox(height: HkSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _durationController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.l10n.estMinutes,
                        errorText:
                            _durationController.text.trim().isNotEmpty &&
                                (int.tryParse(
                                          _durationController.text.trim(),
                                        ) ??
                                        0) <
                                    1
                            ? context.l10n.use1OrMore
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: HkSpacing.xs),
                  Expanded(
                    child: TextField(
                      controller: _reminderDaysController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.l10n.remindDaysBefore,
                        errorText:
                            (int.tryParse(
                                      _reminderDaysController.text.trim(),
                                    ) ??
                                    -1) <
                                0
                            ? context.l10n.use0OrMore
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HkSpacing.xs),
              TextField(
                controller: _materialsController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.l10n.requiredMaterials,
                  hintText: context.l10n.commaSeparated2,
                ),
              ),
              const SizedBox(height: HkSpacing.xs),
              TextField(
                controller: _reminderRecommendationController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: context.l10n.reminderNote,
                  hintText: context.l10n.optionalContextForNotifications,
                ),
              ),
              const SizedBox(height: HkSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event),
                      label: Text(
                        context.l10n.dueDate(
                          _formatShortDate(context, _dueDate),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: HkSpacing.xs),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Symbols.schedule_rounded),
                      label: Text(_formatShortTime(context, _dueDate)),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
        error: (error, _) => Text(_failureMessage(context, error)),
        loading: () => const LinearProgressIndicator(),
      ),
    );
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (selected != null && mounted) {
      setState(
        () => _dueDate = DateTime(
          selected.year,
          selected.month,
          selected.day,
          _dueDate.hour,
          _dueDate.minute,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueDate),
    );
    if (selected != null && mounted) {
      setState(
        () => _dueDate = DateTime(
          _dueDate.year,
          _dueDate.month,
          _dueDate.day,
          selected.hour,
          selected.minute,
        ),
      );
    }
  }

  Future<void> _save({required bool closeAfterSave}) async {
    if (_saving) {
      return;
    }
    final assets = ref.read(assetsProvider).value ?? [];
    final assetId = _assetId ?? assets.firstOrNull?.id;
    final interval = int.tryParse(_intervalController.text) ?? 1;
    final reminderText = _reminderDaysController.text.trim();
    final reminderDaysBefore = reminderText.isEmpty
        ? 0
        : int.tryParse(reminderText);
    if (assetId == null ||
        _titleController.text.trim().isEmpty ||
        interval < 1 ||
        reminderDaysBefore == null ||
        !_metadataNumbersValid) {
      return;
    }
    final metadata = _metadataFromForm();
    setState(() => _saving = true);
    try {
      final isCreating = widget.task == null;
      final planId = widget.task?.plan.id ?? (_creationPlanId ??= _uuid.v7());
      final operationId = _creationOperationId ??= _uuid.v7();

      if (isCreating) {
        final monetizationRepo = ref.read(monetizationRepositoryProvider);
        if (monetizationRepo != null) {
          final online = await ref
              .read(syncConnectivityInstanceProvider)
              .isOnline();
          if (!online) {
            await _saveOfflineDraft();
            if (mounted) {
              hk_ui.showToast(
                context,
                content: Text(context.l10n.offlineTaskDraftMessage),
              );
            }
            return;
          }
        }

        final creationController = ref.read(taskCreationControllerProvider);
        final accountScope =
            ref.read(monetizationRepositoryProvider)?.currentUserId ?? 'local';

        final existingOp = TaskCreationOperation(
          operationId: operationId,
          planId: planId,
          accountScope: accountScope,
          requestPayload: const <String, dynamic>{},
          requestHash: '',
          state: TaskCreationOperationState.submitting,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final success = await creationController.createNewTask(
          assetId: assetId,
          title: _titleController.text,
          instructions: _instructionsController.text,
          recurrence: RecurrenceRule(interval: interval, unit: _unit),
          priority: _priority,
          nextDueDate: _dueDate,
          reminderDaysBefore: reminderDaysBefore,
          metadata: metadata,
          accountScope: accountScope,
          existingOperation: existingOp,
        );

        if (!success) {
          final state = creationController.value;
          if (mounted && state.failure != null) {
            if (state.failure!.code ==
                    TaskCreationFailureCode.insufficientPoints ||
                _isInsufficientPointsError(state.failure!.message)) {
              await showPointShortageDialog(
                context,
                ref,
                attemptedAction: 'task',
              );
              return;
            }
            hk_ui.showToast(
              context,
              content: Text(_failureMessage(context, state.failure!.message)),
              severity: hk_ui.HkToastSeverity.error,
            );
          }
          return;
        }

        await ref
            .read(offlineCreationDraftStoreProvider)
            .clear(_offlineDraftKey);
      }

      await ref
          .read(maintenanceRepositoryProvider)
          .savePlan(
            id: planId,
            assetId: assetId,
            title: _titleController.text,
            instructions: _instructionsController.text,
            recurrence: RecurrenceRule(interval: interval, unit: _unit),
            priority: _priority,
            nextDueDate: _dueDate,
            reminderDaysBefore: reminderDaysBefore,
            metadata: metadata,
          );

      await refreshNotificationSchedules(ref);
      if (mounted) {
        if (widget.task == null) {
          _showTaskActionFeedback(context, _TaskActionFeedbackType.created);
        }
        if (closeAfterSave) {
          Navigator.of(context).pop();
        } else {
          _creationOperationId = null;
          _creationPlanId = null;
          _titleController.clear();
          _instructionsController.clear();
          _taskTypeController.clear();
          _locationController.clear();
          _durationController.clear();
          _materialsController.clear();
          _reminderRecommendationController.clear();
          setState(() {
            _dueDate = _nextDefaultPlanDueDate();
          });
          hk_ui.showToast(context, content: Text(context.l10n.taskCreated));
        }
      }
    } catch (error) {
      if (mounted) {
        if (_isInsufficientPointsError(error)) {
          await showPointShortageDialog(context, ref, attemptedAction: 'task');
          return;
        }
        hk_ui.showToast(
          context,
          content: Text(
            _failureMessage(
              context,
              error,
              fallback: AppFailureCode.taskUpdate,
            ),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  TaskMetadata? _metadataFromForm() {
    final durationText = _durationController.text.trim();
    final duration = durationText.isEmpty ? null : int.tryParse(durationText);
    final metadata = TaskMetadata(
      taskType: _nullableEditText(_taskTypeController.text),
      locationLabel: _nullableEditText(_locationController.text),
      estimatedDurationMinutes: duration,
      requiredMaterials: _commaList(_materialsController.text),
      reminderRecommendation: _nullableEditText(
        _reminderRecommendationController.text,
      ),
    );
    if (metadata.taskType == null &&
        metadata.locationLabel == null &&
        metadata.estimatedDurationMinutes == null &&
        metadata.requiredMaterials.isEmpty &&
        metadata.reminderRecommendation == null) {
      return null;
    }
    return metadata;
  }
}

DateTime _defaultPlanDueDate({required int reminderHour, DateTime? clock}) {
  final now = clock ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day, reminderHour);
  if (today.isAfter(now)) return today;
  return DateTime(now.year, now.month, now.day + 1, reminderHour);
}
