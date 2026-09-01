import '../application/task_creation_controller.dart';
import '../../monetization/monetization.dart';
import '../../../ui/components.dart' as hk_ui;
import '../../../ui/presentation_support.dart';
import '../../monetization/presentation/monetization_presentation.dart';
import 'task_actions.dart';

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
    scheduleMicrotask(
      () => _restoreOfflineDraft(overwriteExisting: plan != null),
    );
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
    final existingPlanId = widget.task?.plan.id;
    return existingPlanId == null
        ? 'task_create_${userId ?? 'local'}_${widget.assetId ?? 'any'}'
        : 'task_edit_${userId ?? 'local'}_$existingPlanId';
  }

  Future<void> _saveOfflineDraft() {
    return ref.read(offlineCreationDraftStoreProvider).save(_offlineDraftKey, {
      'operation_id': _creationOperationId ??= _uuid.v7(),
      'plan_id': widget.task?.plan.id ?? (_creationPlanId ??= _uuid.v7()),
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

  Future<void> _restoreOfflineDraft({bool overwriteExisting = false}) async {
    final draft = await ref
        .read(offlineCreationDraftStoreProvider)
        .load(_offlineDraftKey);
    if (!mounted ||
        draft == null ||
        (!overwriteExisting && _titleController.text.isNotEmpty)) {
      return;
    }
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
    return (durationText.isEmpty || (duration != null && duration >= 0)) &&
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
    return EditorSheetFrame(
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
                inputFormatters: limitInputLength(
                  InputValidationLimits.maintenanceTitle,
                ),
                decoration: InputDecoration(labelText: context.l10n.taskTitle),
              ),
              const SizedBox(height: HkSpacing.xs),
              TextField(
                controller: _instructionsController,
                maxLines: 3,
                inputFormatters: limitInputLength(
                  InputValidationLimits.maintenanceInstructions,
                ),
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
                            child: Text(recurrenceUnitLabel(context, item)),
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
                      child: Text(priorityLabel(context, item)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _priority = value ?? _priority),
              ),
              const SizedBox(height: HkSpacing.xs),
              TextField(
                controller: _taskTypeController,
                textInputAction: TextInputAction.next,
                inputFormatters: limitInputLength(
                  InputValidationLimits.maintenanceTaskType,
                ),
                decoration: InputDecoration(
                  labelText: context.l10n.taskType,
                  hintText: context.l10n.inspectionCleaningFeeding,
                ),
              ),
              const SizedBox(height: HkSpacing.xs),
              TextField(
                controller: _locationController,
                textInputAction: TextInputAction.next,
                inputFormatters: limitInputLength(
                  InputValidationLimits.maintenanceLocation,
                ),
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
                                        -1) <
                                    0
                            ? context.l10n.use0OrMore
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
                inputFormatters: limitInputLength(
                  InputValidationLimits.maintenanceReminderRecommendation,
                ),
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
                          formatShortDate(context, _dueDate),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: HkSpacing.xs),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Symbols.schedule_rounded),
                      label: Text(formatShortTime(context, _dueDate)),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
        error: (error, _) => Text(failureMessage(context, error)),
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
      validateMaintenancePlanInput(
        assetId: assetId,
        title: _titleController.text,
        instructions: _instructionsController.text,
        recurrence: RecurrenceRule(interval: interval, unit: _unit),
        reminderDaysBefore: reminderDaysBefore,
        metadata: metadata,
      );
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
                isInsufficientPointsError(state.failure!.message)) {
              await showPointShortageDialog(
                context,
                ref,
                attemptedAction: 'task',
              );
              return;
            }
            hk_ui.showToast(
              context,
              content: Text(switch (state.failure!.code) {
                TaskCreationFailureCode.invalidPayload =>
                  context.l10n.reviewInvalidFields,
                TaskCreationFailureCode.unauthenticated =>
                  context.l10n.serverSessionExpired,
                TaskCreationFailureCode.assetNotFound =>
                  context.l10n.authoritativeEntityNoLongerAvailable,
                _ => failureMessage(context, state.failure!.message),
              }),
              severity: hk_ui.HkToastSeverity.error,
            );
          }
          return;
        }
      } else if (widget.task!.plan.assetId != assetId) {
        final monetization = ref.read(monetizationRepositoryProvider);
        if (monetization == null || monetization.currentUserId == null) {
          throw StateError('Cloud points service is unavailable.');
        }
        final online = await ref
            .read(syncConnectivityInstanceProvider)
            .isOnline();
        if (!mounted) return;
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
        final quote = await monetization.quoteMaintenancePlanMove(
          planId: planId,
          targetAssetId: assetId,
        );
        if (!mounted) return;
        if (quote.charge > 0) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(context.l10n.confirmTaskMoveChargeTitle),
              content: Text(
                context.l10n.confirmTaskMoveChargeBody(quote.charge),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(context.l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(context.l10n.confirmPointChargeAction),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
        }
        final result = await ref
            .read(taskCreationControllerProvider)
            .movePlanWithPointDelta(
              operation: {
                'operation_id': _uuid.v7(),
                'plan_id': planId,
                'target_asset_id': assetId,
                'expected_plan_revision': quote.revision,
                'max_charge': quote.charge,
              },
              accountScope: monetization.currentUserId!,
            );
        if (!mounted) return;
        if (!result.applied) {
          throw StateError(
            result.status == 'charge_changed'
                ? context.l10n.authoritativeChargeChanged
                : result.conflictReason ?? result.status,
          );
        }
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
            expectedOccurrenceId: widget.task?.plan.currentOccurrenceId,
            expectedUpdatedAt: widget.task?.plan.updatedAt,
          );
      await ref.read(offlineCreationDraftStoreProvider).clear(_offlineDraftKey);

      await wakeNotificationReconciliation(ref);
      if (mounted) {
        if (widget.task == null) {
          showTaskActionFeedback(context, TaskActionFeedbackType.created);
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
        if (isInsufficientPointsError(error)) {
          await showPointShortageDialog(context, ref, attemptedAction: 'task');
          return;
        }
        hk_ui.showToast(
          context,
          content: Text(
            error is AuthoritativeRpcRejectionException
                ? authoritativeRpcRejectionMessage(context, error)
                : failureMessage(
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
      taskType: nullableEditText(_taskTypeController.text),
      locationLabel: nullableEditText(_locationController.text),
      estimatedDurationMinutes: duration,
      requiredMaterials: commaSeparatedValues(_materialsController.text),
      reminderRecommendation: nullableEditText(
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
