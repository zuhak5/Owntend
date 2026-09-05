part of 'assets_presentation.dart';

class ThingDetailScreen extends ConsumerStatefulWidget {
  const ThingDetailScreen({required this.assetId, super.key});

  final String assetId;

  @override
  ConsumerState<ThingDetailScreen> createState() => _ThingDetailScreenState();
}

class _ItemActionButtons extends StatelessWidget {
  const _ItemActionButtons({required this.onAddPhoto, required this.onAddTask});

  final VoidCallback onAddPhoto;
  final VoidCallback onAddTask;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 304;
        final photo = _ItemActionButton(
          key: const ValueKey('item-add-photo'),
          icon: Symbols.add_photo_alternate_rounded,
          label: context.l10n.addPhoto,
          onPressed: onAddPhoto,
        );
        final task = _ItemActionButton(
          key: const ValueKey('item-add-task'),
          icon: Symbols.add_task_rounded,
          label: context.l10n.addTask,
          onPressed: onAddTask,
        );
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [photo, const SizedBox(height: 8), task],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: photo),
            const SizedBox(width: 10),
            Expanded(child: task),
          ],
        );
      },
    );
  }
}

class _ItemActionButton extends StatelessWidget {
  const _ItemActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 21),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, textAlign: TextAlign.center, maxLines: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemHealthCard extends StatelessWidget {
  const _ItemHealthCard({required this.score, this.warrantyUntil});

  final features.EntityHealthScore score;
  final DateTime? warrantyUntil;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (score.state) {
      features.HealthState.excellent ||
      features.HealthState.good => scheme.primary,
      features.HealthState.attention => HkColors.amber,
      features.HealthState.critical => scheme.error,
      features.HealthState.insufficientData => scheme.outline,
    };
    final healthValue = score.state == features.HealthState.insufficientData
        ? context.l10n.needsSetup
        : context.l10n.itemHealthPercent(score.score);
    return hk_ui.PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.health_and_safety_rounded, color: color),
              const SizedBox(width: HkSpacing.xs),
              Expanded(
                child: Text(
                  context.l10n.itemHealthSemantic(healthValue),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              hk_ui.StatusPill(
                compact: true,
                label: healthStateLabel(context, score.state),
                color: color,
              ),
            ],
          ),
          const SizedBox(height: HkSpacing.xs),
          for (final reason in score.reasons)
            Text('- ${localizedFeatureMessage(context, reason)}'),
          if (score.nextBestAction != null) ...[
            const SizedBox(height: HkSpacing.space4),
            Text(
              context.l10n.nextValue(
                localizedFeatureMessage(context, score.nextBestAction!),
              ),
            ),
          ],
          if (warrantyUntil != null) ...[
            const SizedBox(height: HkSpacing.xs),
            Text(
              context.l10n.warrantyUntilDate(
                formatShortDate(context, warrantyUntil!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

List<Widget> taskMetadataRows(BuildContext context, TaskMetadata? metadata) {
  if (metadata == null) {
    return const [];
  }
  return [
    if (metadata.taskType?.trim().isNotEmpty ?? false)
      DetailRow(
        icon: Symbols.build_circle_rounded,
        label: context.l10n.taskType,
        value: metadata.taskType!.trim(),
      ),
    if (metadata.locationLabel?.trim().isNotEmpty ?? false)
      DetailRow(
        icon: Symbols.place_rounded,
        label: context.l10n.location,
        value: metadata.locationLabel!.trim(),
      ),
    if (metadata.estimatedDurationMinutes != null)
      DetailRow(
        icon: Symbols.timer_rounded,
        label: context.l10n.duration,
        value: context.l10n.durationMinutes(metadata.estimatedDurationMinutes!),
      ),
    if (metadata.requiredMaterials.isNotEmpty)
      DetailRow(
        icon: Symbols.construction_rounded,
        label: context.l10n.materials,
        value: metadata.requiredMaterials.join(', '),
      ),
    if (metadata.reminderRecommendation?.trim().isNotEmpty ?? false)
      DetailRow(
        icon: Symbols.notification_important_rounded,
        label: context.l10n.reminder,
        value: metadata.reminderRecommendation!.trim(),
      ),
  ];
}

class _ThingDetailScreenState extends ConsumerState<ThingDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final assetState = ref.watch(assetDetailProvider(widget.assetId));
    return assetState.when(
      data: (asset) {
        if (asset == null) {
          return Scaffold(
            appBar: AppBar(title: Text(context.l10n.item)),
            body: Center(
              child: hk_ui.PremiumEmptyState(
                icon: Symbols.inventory_2_rounded,
                title: context.l10n.itemNotFound,
                body: '',
                action: FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(context.l10n.back),
                ),
              ),
            ),
          );
        }
        final roomsState = ref.watch(roomsProvider);
        final tasks = ref.watch(assetSavedTasksProvider(asset.id));
        final tagsState = ref.watch(assetTagsProvider(asset.id));
        final photosState = ref.watch(assetPhotosProvider(asset.id));
        final dependenciesReady =
            roomsState.hasValue &&
            tasks.hasValue &&
            tagsState.hasValue &&
            photosState.hasValue;
        if (!dependenciesReady) {
          final dependencyError =
              roomsState.error ??
              tasks.error ??
              tagsState.error ??
              photosState.error;
          return Scaffold(
            appBar: AppBar(
              title: DynamicText(asset.name, contentType: 'asset.name'),
            ),
            body: dependencyError == null
                ? const Center(child: CircularProgressIndicator())
                : hk_ui.ErrorPanel(
                    message: failureMessage(context, dependencyError),
                    onRetry: () {
                      ref.invalidate(roomsProvider);
                      ref.invalidate(assetSavedTasksProvider(asset.id));
                      ref.invalidate(assetTagsProvider(asset.id));
                      ref.invalidate(assetPhotosProvider(asset.id));
                    },
                  ),
          );
        }
        final rooms = roomsState.value!;
        final room = rooms.where((item) => item.id == asset.roomId).firstOrNull;
        final tags = tagsState.value!;
        final photos = photosState.value!;
        final relatedTasks = tasks.value!;
        final hasCriticalAlert = relatedTasks.any(
          (task) =>
              isTaskActionable(task) &&
              task.plan.priority == PriorityLevel.critical,
        );
        final activeRelatedTaskCount = relatedTasks
            .where(isTaskActionable)
            .length;
        return Scaffold(
          appBar: AppBar(
            title: DynamicText(asset.name, contentType: 'asset.name'),
            actions: [
              IconButton(
                tooltip: context.l10n.editItem,
                onPressed: () => showAssetEditorSheet(context, asset: asset),
                icon: const Icon(Symbols.edit_rounded),
              ),
              PopupMenuButton<String>(
                useRootNavigator: true,
                tooltip: context.l10n.itemActions,
                onSelected: (value) async {
                  if (value == 'move_copy') {
                    await showMoveCopyItemSheet(context, asset);
                    return;
                  }
                  if (value == 'delete') {
                    final deleted = await deleteThingWithConfirmation(
                      context,
                      ref,
                      asset,
                    );
                    if (deleted && context.mounted) {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/assets/room/${asset.roomId}');
                      }
                    }
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'move_copy',
                    child: hk_ui.PopupActionLabel(
                      icon: Symbols.drive_file_move_rounded,
                      label: context.l10n.moveOrCopy,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: hk_ui.PopupActionLabel(
                      icon: Symbols.delete_rounded,
                      label: context.l10n.moveItemToTrash,
                      destructive: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: RepaintBoundary(
            key: const ValueKey('item-detail-stability-boundary'),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    HkSpacing.gutter,
                    8,
                    HkSpacing.gutter,
                    HkSpacing.xl,
                  ),
                  children: [
                    if (!hasCriticalAlert) ...[
                      const HkNativeAdCard(placement: 'thing_detail'),
                    ],
                    hk_ui.PremiumCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _ThingAvatar(
                                asset: asset,
                                photos: photos,
                                size: 40,
                              ),
                              const SizedBox(width: HkSpacing.xs),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    DynamicText(
                                      asset.name,
                                      contentType: 'asset.name',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Text(
                                      [
                                        assetTypeLabel(
                                          context,
                                          asset.assetType,
                                        ),
                                        if (room != null) room.name,
                                        if (asset.placement != null)
                                          asset.placement!,
                                      ].join(' \u00B7 '),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: HkSpacing.xs),
                          _ThingDetailFields(asset: asset),
                          if (tags.isNotEmpty) ...[
                            const SizedBox(height: HkSpacing.sm),
                            Wrap(
                              spacing: HkSpacing.xs,
                              runSpacing: HkSpacing.xs,
                              children: [
                                for (final tag in tags)
                                  hk_ui.StatusPill(
                                    label: tag.name,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    contentType: 'tag.name',
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: HkSpacing.sm),
                          _ItemActionButtons(
                            onAddPhoto: () =>
                                addPhotoToAsset(context, ref, asset),
                            onAddTask: () =>
                                showPlanEditorSheet(context, assetId: asset.id),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: HkSpacing.sm),
                    _ItemHealthCard(
                      score: feature_selectors.itemHealthScore(
                        asset: asset,
                        tasks: relatedTasks,
                        now: DateTime.now(),
                      ),
                      warrantyUntil: asset.deviceDetails?.warrantyUntil,
                    ),
                    hk_ui.SectionHeader(
                      title: context.l10n.relatedTasks,
                      subtitle: context.l10n.activeTaskCount(
                        activeRelatedTaskCount,
                      ),
                    ),
                    tasks.when(
                      data: (items) {
                        if (items.isEmpty) {
                          return hk_ui.PremiumEmptyState(
                            icon: Symbols.task_alt_rounded,
                            title: context.l10n.noTasksYet,
                            body: context.l10n.createRecurringCareForThisItem,
                            action: hk_ui.CompactActionGroup(
                              children: [
                                FilledButton.icon(
                                  onPressed: () => showPlanEditorSheet(
                                    context,
                                    assetId: asset.id,
                                  ),
                                  icon: const Icon(Symbols.add_task_rounded),
                                  label: Text(context.l10n.addTask),
                                ),
                              ],
                            ),
                          );
                        }
                        return Column(
                          children: [
                            for (final task in items)
                              hk_ui.SwipeDelete(
                                margin: const EdgeInsets.only(
                                  bottom: HkSpacing.sm,
                                ),
                                dismissKey: ValueKey(
                                  'thing-task-delete-${task.plan.id}',
                                ),
                                action: hk_ui.SwipeAction.moveToTrash(
                                  onAction: () => deleteTaskWithConfirmation(
                                    context,
                                    ref,
                                    task,
                                  ),
                                ),
                                child: hk_ui.TaskCard(
                                  task: task,
                                  margin: EdgeInsets.zero,
                                  onTap: () => context.push(
                                    '/maintenance/${task.plan.id}',
                                  ),
                                  onComplete: () => completeTaskWithFeedback(
                                    context,
                                    ref,
                                    task,
                                    collectNotes: true,
                                  ),
                                  onEdit: () =>
                                      showPlanEditorSheet(context, task: task),
                                  onSnooze: () => snoozeTaskWithFeedback(
                                    context,
                                    ref,
                                    task,
                                  ),
                                  onSetEnabled: (enabled) =>
                                      setTaskEnabledWithFeedback(
                                        context,
                                        ref,
                                        task,
                                        enabled,
                                      ),
                                  onArchive: () => deleteTaskWithConfirmation(
                                    context,
                                    ref,
                                    task,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                      error: (error, _) => hk_ui.ErrorPanel(
                        message: failureMessage(context, error),
                      ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                    ),
                    hk_ui.SectionHeader(
                      title: context.l10n.timeline,
                      subtitle:
                          context.l10n.completionHistoryAcrossRelatedTasks,
                    ),
                    _ThingTimeline(
                      tasks: relatedTasks,
                      records: ref.watch(assetRecordsProvider(asset.id)),
                    ),
                    if (photos.isNotEmpty) ...[
                      hk_ui.SectionHeader(
                        title: context.l10n.photos,
                        subtitle: context.l10n.savedPhotoCount(photos.length),
                      ),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 520 ? 3 : 2;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: photos.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: HkSpacing.sm,
                                  mainAxisSpacing: HkSpacing.sm,
                                  mainAxisExtent: 176,
                                ),
                            itemBuilder: (context, index) {
                              final photo = photos[index];
                              return _ThingPhotoTile(
                                photo: photo,
                                onPrimary: () => _setPrimaryPhoto(
                                  context,
                                  ref,
                                  asset,
                                  photo,
                                ),
                                onDelete: () =>
                                    _deletePhoto(context, ref, asset, photo),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.item)),
        body: hk_ui.ErrorPanel(
          message: failureMessage(context, error),
          onRetry: () => ref.invalidate(assetDetailProvider(widget.assetId)),
        ),
      ),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }

  Future<void> _setPrimaryPhoto(
    BuildContext context,
    WidgetRef ref,
    Asset asset,
    AssetPhoto photo,
  ) async {
    try {
      await ref
          .read(assetRepositoryProvider)
          .setPrimaryPhoto(asset.id, photo.id);
    } catch (e) {
      if (context.mounted) {
        hk_ui.showToast(
          context,
          content: Text(failureMessage(context, e)),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    }
  }

  Future<void> _deletePhoto(
    BuildContext context,
    WidgetRef ref,
    Asset asset,
    AssetPhoto photo,
  ) async {
    final confirmed = await confirmPermanentDelete(
      context,
      title: context.l10n.deletePhoto,
      message: context.l10n.deleteSavedPhotoFromItem(asset.name),
    );
    if (!confirmed) {
      return;
    }
    try {
      await ref.read(assetRepositoryProvider).deletePhoto(photo.id);
    } catch (e) {
      if (context.mounted) {
        hk_ui.showToast(
          context,
          content: Text(failureMessage(context, e)),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    }
  }
}

class _ThingDetailFields extends StatelessWidget {
  const _ThingDetailFields({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (asset.notes?.trim().isNotEmpty ?? false)
        DetailRow(
          icon: Symbols.notes_rounded,
          label: context.l10n.notes,
          value: asset.notes!,
          contentType: 'asset.notes',
        ),
      if (asset.purchaseDate != null)
        DetailRow(
          icon: Symbols.shopping_bag_rounded,
          label: context.l10n.purchased,
          value: formatShortDate(context, asset.purchaseDate!),
        ),
      ..._typedRows(context),
    ];
    if (rows.isEmpty) {
      return Row(
        children: [
          const hk_ui.HkStateIllustration(
            icon: Symbols.info_rounded,
            tone: hk_ui.HkIllustrationTone.neutral,
            size: 42,
            compact: true,
          ),
          const SizedBox(width: HkSpacing.xs),
          Expanded(
            child: Text(
              context.l10n.noExtraDetailsYet,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }
    return Column(children: rows);
  }

  List<Widget> _typedRows(BuildContext context) {
    final device = asset.deviceDetails;
    final pet = asset.petDetails;
    final plant = asset.plantDetails;
    final safety = asset.safetyDetails;
    return [
      if (device?.brand != null)
        DetailRow(
          icon: Symbols.memory_rounded,
          label: context.l10n.brand,
          value: device!.brand!,
        ),
      if (device?.model != null)
        DetailRow(
          icon: Symbols.info_rounded,
          label: context.l10n.model,
          value: device!.model!,
        ),
      if (device?.consumable != null)
        DetailRow(
          icon: Symbols.inventory_2_rounded,
          label: context.l10n.consumable,
          value: device!.consumable!,
          contentType: 'asset.device.consumable',
        ),
      if (pet?.species != null)
        DetailRow(
          icon: Symbols.pets_rounded,
          label: context.l10n.species,
          value: petSpeciesLabel(context, pet!.species!),
          contentType: 'asset.pet.species',
        ),
      if (pet?.feedingNotes != null)
        DetailRow(
          icon: Symbols.restaurant_rounded,
          label: context.l10n.feeding,
          value: pet!.feedingNotes!,
          contentType: 'asset.pet.feeding_notes',
        ),
      if (plant?.species != null)
        DetailRow(
          icon: Symbols.yard_rounded,
          label: context.l10n.species,
          value: plant!.species!,
          contentType: 'asset.plant.species',
        ),
      if (plant?.wateringIntervalDays != null)
        DetailRow(
          icon: Symbols.water_drop_rounded,
          label: context.l10n.watering,
          value: context.l10n.recurrenceEveryMany(
            plant!.wateringIntervalDays!,
            context.l10n.days2,
          ),
        ),
      if (safety?.safetyType != null)
        DetailRow(
          icon: Symbols.health_and_safety_rounded,
          label: context.l10n.safetyType,
          value: safety!.safetyType!,
          contentType: 'asset.safety.type',
        ),
      if (safety?.testIntervalDays != null)
        DetailRow(
          icon: Symbols.fact_check_rounded,
          label: context.l10n.testInterval,
          value: context.l10n.recurrenceEveryMany(
            safety!.testIntervalDays!,
            context.l10n.days2,
          ),
        ),
    ];
  }
}

class _ThingTimeline extends StatelessWidget {
  const _ThingTimeline({required this.tasks, required this.records});

  final List<TaskItem> tasks;
  final AsyncValue<List<MaintenanceRecord>> records;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return hk_ui.PremiumEmptyState(
        icon: Symbols.history_rounded,
        title: context.l10n.noTimelineYet,
        body: context.l10n.completedTasksForThisItemAppearHere,
      );
    }
    return records.when(
      data: (items) => MaintenanceTimeline(
        records: items,
        taskTitleByPlanId: {
          for (final task in tasks) task.plan.id: task.plan.title,
        },
      ),
      error: (error, _) =>
          hk_ui.ErrorPanel(message: failureMessage(context, error)),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class MaintenanceTimeline extends StatelessWidget {
  const MaintenanceTimeline({
    required this.records,
    this.taskTitle,
    this.taskTitleByPlanId = const {},
    super.key,
  });

  final List<MaintenanceRecord> records;
  final String? taskTitle;
  final Map<String, String> taskTitleByPlanId;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return hk_ui.PremiumEmptyState(
        icon: Symbols.history_rounded,
        title: context.l10n.noTimelineYet,
        body: context.l10n.completedWorkWillAppearHere,
      );
    }
    final sorted = [...records]
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    final children = <Widget>[];
    DateTime? previousDay;
    for (var index = 0; index < sorted.length; index++) {
      final record = sorted[index];
      final day = hk_dates.dateOnly(record.completedAt);
      if (previousDay == null || !hk_dates.isSameDate(day, previousDay)) {
        children.add(_TimelineDateHeader(date: record.completedAt));
        previousDay = day;
      }
      final title =
          taskTitleByPlanId[record.planId] ?? taskTitle ?? context.l10n.task;
      children.add(
        _TimelineRecordTile(
          record: record,
          title: title,
          isLast: index == sorted.length - 1,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _TimelineDateHeader extends StatelessWidget {
  const _TimelineDateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, HkSpacing.sm, 2, HkSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(HkRadii.md),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.28),
              ),
            ),
            child: Icon(
              Symbols.calendar_month_rounded,
              color: scheme.primary,
              size: 16,
            ),
          ),
          const SizedBox(width: HkSpacing.xs),
          Expanded(
            child: Text(
              formatLongDate(context, date),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRecordTile extends StatelessWidget {
  const _TimelineRecordTile({
    required this.record,
    required this.title,
    required this.isLast,
  });

  final MaintenanceRecord record;
  final String title;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notes = record.notes?.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          child: Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: HkShadows.ambient(tint: scheme.primary),
                ),
                child: Icon(
                  Symbols.check_rounded,
                  color: scheme.onPrimary,
                  size: 14,
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 64,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant.withValues(alpha: 0.34),
                    borderRadius: BorderRadius.circular(HkRadii.full),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: HkSpacing.xs),
        Expanded(
          child: hk_ui.PremiumCard(
            margin: const EdgeInsets.only(bottom: HkSpacing.xs),
            padding: const EdgeInsets.all(10),
            borderRadius: HkRadii.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    hk_ui.StatusPill(
                      label: formatShortTime(context, record.completedAt),
                      color: HkColors.green,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: HkSpacing.space4),
                Text(
                  context.l10n.dueDateTimeLabel(
                    formatShortDateTime(context, record.dueDate),
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: HkSpacing.xs),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(HkRadii.md),
                    ),
                    child: Text(
                      notes,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class DetailRow extends StatelessWidget {
  const DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.contentType,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? contentType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HkSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: HkSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 92, maxWidth: 140),
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Expanded(
            child: contentType == null
                ? Text(value)
                : DynamicText(value, contentType: contentType!),
          ),
        ],
      ),
    );
  }
}

class _ThingAvatar extends StatelessWidget {
  const _ThingAvatar({
    required this.asset,
    required this.photos,
    this.size = 52,
  });

  final Asset asset;
  final List<AssetPhoto> photos;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary =
        photos.where((photo) => photo.isPrimary).firstOrNull ??
        photos.firstOrNull;
    return FutureBuilder<File?>(
      future: localMediaFile(primary?.relativePath),
      builder: (context, snapshot) {
        final file = snapshot.data;
        final hasImage = file != null && file.existsSync();
        return ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: Container(
            width: size,
            height: size,
            color: scheme.secondaryContainer,
            child: hasImage
                ? Image.file(file, fit: BoxFit.cover)
                : Icon(
                    iconForAssetType(asset.assetType),
                    color: scheme.primary,
                  ),
          ),
        );
      },
    );
  }
}

class _ThingPhotoTile extends StatelessWidget {
  const _ThingPhotoTile({
    required this.photo,
    required this.onPrimary,
    required this.onDelete,
  });

  final AssetPhoto photo;
  final VoidCallback onPrimary;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return hk_ui.PremiumCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: FutureBuilder<File?>(
              future: localMediaFile(photo.relativePath),
              builder: (context, snapshot) {
                final file = snapshot.data;
                final hasImage = file != null && file.existsSync();
                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(HkRadii.lg),
                  ),
                  child: ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: hasImage
                        ? Image.file(file, fit: BoxFit.cover)
                        : const Icon(Symbols.broken_image_rounded),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 6, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    photo.isPrimary
                        ? context.l10n.primary
                        : formatMonthDay(context, photo.createdAt),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: photo.isPrimary ? scheme.primary : null,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  useRootNavigator: true,
                  tooltip: context.l10n.photoActions,
                  onSelected: (value) {
                    if (value == 'primary') {
                      onPrimary();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'primary',
                      enabled: !photo.isPrimary,
                      child: hk_ui.PopupActionLabel(
                        icon: Symbols.account_circle_rounded,
                        label: context.l10n.setPrimary,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: hk_ui.PopupActionLabel(
                        icon: Symbols.delete_rounded,
                        label: context.l10n.delete,
                        destructive: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ThingCard extends ConsumerWidget {
  const ThingCard({
    required this.asset,
    required this.onTap,
    required this.onEdit,
    required this.onPhoto,
    required this.onArchive,
    this.dueStatus,
    this.margin,
    super.key,
  });

  final Asset asset;
  final ItemTaskStatusSummary? dueStatus;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onPhoto;
  final VoidCallback onArchive;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(assetPhotosProvider(asset.id)).value ?? const [];
    final status = dueStatus;
    final statusColor = status == null
        ? null
        : hk_ui.itemDueAccentColor(context, status.status);
    final subtitle = [
      assetTypeLabel(context, asset.assetType),
      if (asset.placement != null) asset.placement!,
    ].join(' · ');
    final card = hk_ui.PremiumCard(
      margin: margin ?? const EdgeInsets.only(bottom: HkSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      borderRadius: hk_ui.kSwipeRowRadius,
      borderColor: statusColor?.withValues(alpha: 0.22),
      child: Stack(
        children: [
          if (statusColor != null)
            PositionedDirectional(
              start: -10,
              top: -8,
              bottom: -8,
              child: Container(width: 3, color: statusColor),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ThingAvatar(asset: asset, photos: photos, size: 32),
              const SizedBox(width: HkSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DynamicText(
                      asset.name,
                      contentType: 'asset.name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    DynamicText(
                      subtitle,
                      contentType: 'asset.summary',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (status != null) ...[
                      const SizedBox(height: HkSpacing.space4),
                      Wrap(
                        spacing: HkSpacing.space4,
                        runSpacing: HkSpacing.space4,
                        children: [
                          hk_ui.ItemDueIndicator(summary: status),
                          if (status.priority == PriorityLevel.critical)
                            hk_ui.StatusPill(
                              label: context.l10n.critical,
                              color: HkColors.appDanger,
                              compact: true,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: HkSpacing.space4),
              SizedBox(
                width: 44,
                height: 44,
                child: PopupMenuButton<String>(
                  useRootNavigator: true,
                  tooltip: context.l10n.itemActions,
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  icon: const Icon(Symbols.more_vert_rounded),
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else if (value == 'photo') {
                      onPhoto();
                    } else if (value == 'archive') {
                      onArchive();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(context.l10n.edit),
                    ),
                    PopupMenuItem(
                      value: 'photo',
                      child: Text(context.l10n.addPhoto),
                    ),
                    PopupMenuItem(
                      value: 'archive',
                      child: Text(context.l10n.moveItemToTrash),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: [
        asset.name,
        subtitle,
        if (status != null) hk_ui.itemDueLabel(context, status),
        if (status?.priority == PriorityLevel.critical) context.l10n.critical,
      ].join(', '),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      ),
    );
  }
}

String healthStateLabel(BuildContext context, features.HealthState state) {
  return switch (state) {
    features.HealthState.excellent => context.l10n.excellent,
    features.HealthState.good => context.l10n.good,
    features.HealthState.attention => context.l10n.needsAttention,
    features.HealthState.critical => context.l10n.critical,
    features.HealthState.insufficientData => context.l10n.needsSetup,
  };
}
