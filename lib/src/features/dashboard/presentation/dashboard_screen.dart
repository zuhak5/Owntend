part of 'dashboard_presentation.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  final LayerLink _weatherEducationLink = LayerLink();
  final LayerLink _notificationEducationLink = LayerLink();
  final GlobalKey _weatherEducationTargetKey = GlobalKey();
  final GlobalKey _notificationEducationTargetKey = GlobalKey();
  late final NativeAdPresentationDepth _nativeAdPresentationDepth;
  bool _forcePermissionEducationHandled = false;
  bool _permissionOverlaySuspendsNativeAds = false;
  ProviderSubscription<PermissionEducationControllerState>?
  _permissionEducationSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nativeAdPresentationDepth = ref.read(
      nativeAdPresentationDepthProvider.notifier,
    );
    _permissionEducationSubscription = ref.listenManual(
      permissionEducationControllerProvider,
      (_, next) {
        if (!mounted) return;
        _setPermissionOverlayNativeAdSuspension(
          next.isVisible && next.activeCapability != null,
        );
      },
    );
    scheduleMicrotask(() {
      if (mounted) {
        ref.read(permissionEducationControllerProvider.notifier).initialize();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final force =
        GoRouter.maybeOf(context)
            ?.routeInformationProvider
            .value
            .uri
            .queryParameters['permissionSetup'] ==
        '1';
    if (force && !_forcePermissionEducationHandled) {
      _forcePermissionEducationHandled = true;
      scheduleMicrotask(() {
        if (mounted) {
          ref
              .read(permissionEducationControllerProvider.notifier)
              .initialize(
                source: PermissionEducationSource.settings,
                forceShow: true,
              );
          _clearPermissionSetupQuery();
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref
            .read(permissionEducationControllerProvider.notifier)
            .handleAppResume(),
      );
    }
  }

  @override
  void dispose() {
    _permissionEducationSubscription?.close();
    _permissionEducationSubscription = null;
    _setPermissionOverlayNativeAdSuspension(false, deferProviderUpdate: true);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _setPermissionOverlayNativeAdSuspension(
    bool shouldSuspend, {
    bool deferProviderUpdate = false,
  }) {
    if (_permissionOverlaySuspendsNativeAds == shouldSuspend) return;
    _permissionOverlaySuspendsNativeAds = shouldSuspend;
    if (shouldSuspend) {
      _nativeAdPresentationDepth.push();
    } else if (deferProviderUpdate) {
      _nativeAdPresentationDepth.popAfterWidgetTeardown();
    } else {
      _nativeAdPresentationDepth.pop();
    }
  }

  void _clearPermissionSetupQuery() {
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    final uri = router?.routeInformationProvider.value.uri;
    if (uri == null) return;
    if (uri.queryParameters.containsKey('permissionSetup')) {
      final newParams = Map<String, String>.from(uri.queryParameters)
        ..remove('permissionSetup');
      final newUri = uri.replace(
        queryParameters: newParams.isEmpty ? null : newParams,
      );
      router!.replace<void>(newUri.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final startupSnapshot = ref.watch(initialHomeSnapshotProvider).value;
    final tasksState = ref.watch(tasksProvider);
    final assetsState = ref.watch(assetsProvider);
    final roomsState = ref.watch(roomsProvider);
    final tasks =
        tasksState.value ?? startupSnapshot?.tasks ?? const <TaskItem>[];
    final assets =
        assetsState.value ?? startupSnapshot?.assets ?? const <Asset>[];
    final rooms = roomsState.value ?? startupSnapshot?.rooms ?? const <Room>[];
    final hasDomainFailure =
        tasksState.hasError || assetsState.hasError || roomsState.hasError;
    final waitingWithoutSnapshot =
        startupSnapshot == null &&
        (!tasksState.hasValue || !assetsState.hasValue || !roomsState.hasValue);
    if (waitingWithoutSnapshot) {
      final error = tasksState.error ?? assetsState.error ?? roomsState.error;
      return Scaffold(
        body: error == null
            ? const Center(child: CircularProgressIndicator())
            : hk_ui.ErrorPanel(
                message: failureMessage(context, error),
                onRetry: () {
                  ref.invalidate(tasksProvider);
                  ref.invalidate(assetsProvider);
                  ref.invalidate(roomsProvider);
                },
              ),
      );
    }
    final now =
        ref.watch(localClockProvider).value ?? ref.read(localNowProvider)();
    final taskBuckets = getTaskBuckets(tasks, now);
    final homeTaskSections = _homeTaskSections(context, taskBuckets);
    const homeTaskLimit = 3;
    final topPadding = MediaQuery.paddingOf(context).top;
    final headerExtent = _dashboardHeaderExtent(context, topPadding);
    final hasThings = assets.isNotEmpty;
    final canAddThing = rooms.isNotEmpty;
    final permissionState = ref.watch(permissionEducationControllerProvider);
    final weatherCapability = permissionState.setupSnapshot?.weather;
    return Scaffold(
      floatingActionButton: hasThings
          ? Padding(
              padding: const EdgeInsets.only(bottom: HkSpacing.bottomNav),
              child: hk_ui.OwntendFloatingActionButton(
                tooltip: context.l10n.addTask,
                onPressed: () => showPlanEditorSheet(context),
                icon: Symbols.add_task_rounded,
                label: context.l10n.addTask,
              ),
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            key: const ValueKey('home-stability-boundary'),
            child: RefreshIndicator(
              onRefresh: () => ref
                  .read(streakServiceProvider)
                  .refresh(ref.read(localNowProvider)()),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _DashboardHeaderDelegate(
                      topPadding: topPadding,
                      extent: headerExtent,
                      notificationEducationLink: _notificationEducationLink,
                      notificationEducationTargetKey:
                          _notificationEducationTargetKey,
                      onNotificationEducationTap: null,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            HkSpacing.gutter,
                            HkSpacing.sm,
                            HkSpacing.gutter,
                            HkSpacing.bottomAction + HkSpacing.bottomNav,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (hasDomainFailure) ...[
                                _DashboardDataWarning(
                                  onRetry: () {
                                    ref.invalidate(tasksProvider);
                                    ref.invalidate(assetsProvider);
                                    ref.invalidate(roomsProvider);
                                  },
                                ),
                                const SizedBox(height: HkSpacing.sm),
                              ],
                              RepaintBoundary(
                                child: _DashboardWeatherCard(
                                  educationLink: _weatherEducationLink,
                                  educationTargetKey:
                                      _weatherEducationTargetKey,
                                  capability: weatherCapability,
                                  onEducationTap: () => unawaited(
                                    ref
                                        .read(
                                          permissionEducationControllerProvider
                                              .notifier,
                                        )
                                        .initialize(
                                          source: PermissionEducationSource
                                              .weatherCard,
                                          forceShow: true,
                                        ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: HkSpacing.sm),
                              RepaintBoundary(
                                child: _DashboardReadinessCard(
                                  rooms: rooms,
                                  assets: assets,
                                  tasks: tasks,
                                  taskBuckets: taskBuckets,
                                ),
                              ),
                              const SizedBox(height: HkSpacing.sm),
                              const HkNativeAdCard(placement: 'home'),
                              if (homeTaskSections.isEmpty)
                                hk_ui.PremiumEmptyState(
                                  icon: hasThings
                                      ? Symbols.task_alt_rounded
                                      : Symbols.inventory_2_rounded,
                                  title: hasThings
                                      ? context.l10n.noMaintenancePlansYet
                                      : canAddThing
                                      ? context.l10n.createYourFirstItem
                                      : context.l10n.createYourFirstRoom,
                                  body: hasThings
                                      ? context
                                            .l10n
                                            .scheduleRecurringCareForAnItemToStartTracking
                                      : canAddThing
                                      ? context.l10n.addAHomeItemFirst
                                      : context
                                            .l10n
                                            .addARoomOrZoneBeforeAddingItems,
                                  action: FilledButton.icon(
                                    onPressed: () => hasThings
                                        ? showPlanEditorSheet(context)
                                        : startThingSetupFlow(context, ref),
                                    icon: Icon(
                                      hasThings
                                          ? Symbols.add_task_rounded
                                          : canAddThing
                                          ? Symbols.add_home_work_rounded
                                          : Symbols.meeting_room_rounded,
                                    ),
                                    label: Text(
                                      hasThings
                                          ? context.l10n.addTask
                                          : canAddThing
                                          ? context.l10n.createFirstItem
                                          : context.l10n.createFirstRoom,
                                    ),
                                  ),
                                )
                              else
                                Column(
                                  children: [
                                    for (final section in homeTaskSections) ...[
                                      hk_ui.SectionHeader(
                                        title: section.title,
                                        actionLabel: context.l10n.seeAll,
                                        onAction: () =>
                                            context.push('/maintenance'),
                                      ),
                                      for (final task in section.tasks.take(
                                        homeTaskLimit,
                                      ))
                                        hk_ui.SwipeDelete(
                                          margin: const EdgeInsets.only(
                                            bottom: HkSpacing.sm,
                                          ),
                                          dismissKey: ValueKey(
                                            'home-task-delete-${task.plan.id}',
                                          ),
                                          action: hk_ui.SwipeAction.moveToTrash(
                                            onAction: () =>
                                                deleteTaskWithConfirmation(
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
                                            onComplete: () => _completeTask(
                                              context,
                                              ref,
                                              task,
                                            ),
                                            onSnooze: () =>
                                                snoozeTaskWithFeedback(
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
                                          ),
                                        ),
                                    ],
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          PermissionEducationOverlayWrapper(
            targetLink: _weatherEducationLink,
            onChooseLocationManually: () => runWithNativeAdsSuspended(
              context,
              () => showEditorModal<HomeLocation>(
                context,
                builder: (_) => const LocationPickerSheet(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _completeTask(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
  ) async {
    return completeTaskWithFeedback(context, ref, task);
  }
}

class _DashboardDataWarning extends StatelessWidget {
  const _DashboardDataWarning({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return hk_ui.SurfaceCard(
      key: const ValueKey('dashboard-stale-data-warning'),
      padding: const EdgeInsets.all(HkSpacing.sm),
      borderColor: scheme.error.withValues(alpha: 0.35),
      child: Row(
        children: [
          Icon(Symbols.sync_problem_rounded, color: scheme.error),
          const SizedBox(width: HkSpacing.xs),
          Expanded(
            child: Text(
              context.l10n.showingSavedHomeDataRefreshFailed,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
        ],
      ),
    );
  }
}

class _HomeTaskSectionData {
  const _HomeTaskSectionData({required this.title, required this.tasks});

  final String title;
  final List<TaskItem> tasks;
}

List<_HomeTaskSectionData> _homeTaskSections(
  BuildContext context,
  TaskBuckets buckets,
) {
  if (buckets.today.isNotEmpty || buckets.tomorrow.isNotEmpty) {
    return [
      if (buckets.today.isNotEmpty)
        _HomeTaskSectionData(
          title: context.l10n.todaySTasks,
          tasks: buckets.today,
        ),
      if (buckets.tomorrow.isNotEmpty)
        _HomeTaskSectionData(
          title: context.l10n.tomorrowSTasks,
          tasks: buckets.tomorrow,
        ),
    ];
  }
  if (buckets.upcoming.isNotEmpty) {
    return [
      _HomeTaskSectionData(
        title: context.l10n.upcomingTasks,
        tasks: buckets.upcoming,
      ),
    ];
  }
  return const [];
}

class _DashboardWeatherCard extends ConsumerWidget {
  const _DashboardWeatherCard({
    required this.educationLink,
    required this.educationTargetKey,
    required this.capability,
    this.onEducationTap,
  });

  final LayerLink educationLink;
  final GlobalKey educationTargetKey;
  final WeatherAreaCapabilitySnapshot? capability;
  final VoidCallback? onEducationTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(initialHomeSnapshotProvider).value;
    final themeNow =
        ref.watch(localClockProvider).value ?? ref.read(localNowProvider)();
    final brightness = Theme.of(context).brightness;
    final location =
        ref.watch(homeLocationProvider).value ?? snapshot?.homeLocation;
    return CompositedTransformTarget(
      link: educationLink,
      child: KeyedSubtree(
        key: educationTargetKey,
        child: _WeatherCard(
          weather: ref.watch(weatherProvider).value ?? snapshot?.weather,
          location: location,
          capability: capability,
          localNow: themeNow,
          isDark: brightness == Brightness.dark,
          onToggleTheme: () => _toggleWeatherTheme(context, ref, brightness),
          onCapabilityAction: onEducationTap,
        ),
      ),
    );
  }

  Future<void> _toggleWeatherTheme(
    BuildContext context,
    WidgetRef ref,
    Brightness brightness,
  ) async {
    try {
      final repository = ref.read(settingsRepositoryProvider);
      final next = brightness == Brightness.dark
          ? ThemePreference.light
          : ThemePreference.dark;
      await repository.setThemePreference(next);
      await repository.setTimeOfDayThemeEnabled(false);
    } catch (error) {
      if (!context.mounted) return;
      hk_ui.showToast(
        context,
        content: Text(
          failureMessage(context, error, fallback: AppFailureCode.themeUpdate),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
  }
}

class _DashboardReadinessCard extends ConsumerWidget {
  const _DashboardReadinessCard({
    required this.rooms,
    required this.assets,
    required this.tasks,
    required this.taskBuckets,
  });

  final List<Room> rooms;
  final List<Asset> assets;
  final List<TaskItem> tasks;
  final TaskBuckets taskBuckets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = feature_selectors.homeSetupProgress(
      rooms: rooms,
      assets: assets,
      tasks: tasks,
    );
    final reduceMotion = prefersReducedMotion(context);
    if (!setup.isEligible) {
      return AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 260),
        child: _HomeSetupProgressCard(
          key: const ValueKey('home-setup-progress-card'),
          progress: setup,
          nextLabel: _setupNextLabel(context, setup.nextStep),
          onNext: () => unawaited(_openSetupStep(context, ref, setup.nextStep)),
        ),
      );
    }
    final snapshot = ref.watch(initialHomeSnapshotProvider).value;
    final readiness = feature_selectors.homeReadiness(
      rooms: rooms,
      assets: assets,
      tasks: tasks,
      backupState:
          ref.watch(backupStateProvider).value ??
          snapshot?.backupState ??
          const BackupState(),
      now: ref.watch(localClockProvider).value ?? ref.read(localNowProvider)(),
    );
    return AnimatedSwitcher(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 260),
      child: _HomeReadinessSummaryCard(
        key: const ValueKey('home-readiness-card'),
        score: readiness!.score,
        overdueCount: taskBuckets.overdueCount,
        todayCount: taskBuckets.todayCount,
        nextAction: localizedFeatureMessage(context, readiness.nextBestAction),
        today: taskBuckets.todayCount,
        nextSeven: taskBuckets.next7DaysCount,
        overdue: taskBuckets.overdueCount,
        onToday: () => context.push('/maintenance?filter=today'),
        onNextSeven: () => context.push('/maintenance?filter=next7'),
        onOverdue: () => context.push('/maintenance?filter=overdue'),
      ),
    );
  }

  String _setupNextLabel(BuildContext context, features.HomeSetupStep? step) =>
      switch (step) {
        features.HomeSetupStep.room => context.l10n.nextCreateFirstRoom,
        features.HomeSetupStep.maintainedItem =>
          context.l10n.nextAddMaintainedItem,
        features.HomeSetupStep.scheduledTask =>
          context.l10n.nextScheduleMaintenanceTask,
        null => '',
      };

  Future<void> _openSetupStep(
    BuildContext context,
    WidgetRef ref,
    features.HomeSetupStep? step,
  ) async {
    switch (step) {
      case features.HomeSetupStep.room:
        await startThingSetupFlow(context, ref);
        return;
      case features.HomeSetupStep.maintainedItem:
        await showAssetEditorSheet(context, roomId: rooms.first.id);
        return;
      case features.HomeSetupStep.scheduledTask:
        await showPlanEditorSheet(context, assetId: assets.first.id);
        return;
      case null:
        return;
    }
  }
}

double _dashboardHeaderExtent(BuildContext context, double topPadding) {
  final width = MediaQuery.sizeOf(context).width;
  final scaledUnit = MediaQuery.textScalerOf(context).scale(16);
  final scaleAdjustment = ((scaledUnit / 16) - 1).clamp(0.0, 1.0) * 14;
  final contentExtent = width < 600 ? 82.0 : 88.0;
  return topPadding + contentExtent + scaleAdjustment;
}

class _DashboardHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _DashboardHeaderDelegate({
    required this.topPadding,
    required this.extent,
    required this.notificationEducationLink,
    required this.notificationEducationTargetKey,
    this.onNotificationEducationTap,
  });

  final double topPadding;
  final double extent;
  final LayerLink notificationEducationLink;
  final GlobalKey notificationEducationTargetKey;
  final VoidCallback? onNotificationEducationTap;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return _DashboardHeader(
      overlapsContent: overlapsContent,
      notificationEducationLink: notificationEducationLink,
      notificationEducationTargetKey: notificationEducationTargetKey,
      onNotificationEducationTap: onNotificationEducationTap,
    );
  }

  @override
  bool shouldRebuild(_DashboardHeaderDelegate oldDelegate) {
    return topPadding != oldDelegate.topPadding ||
        extent != oldDelegate.extent ||
        notificationEducationLink != oldDelegate.notificationEducationLink ||
        notificationEducationTargetKey !=
            oldDelegate.notificationEducationTargetKey ||
        onNotificationEducationTap != oldDelegate.onNotificationEducationTap;
  }
}

class _DashboardHeader extends ConsumerWidget {
  const _DashboardHeader({
    required this.overlapsContent,
    required this.notificationEducationLink,
    required this.notificationEducationTargetKey,
    this.onNotificationEducationTap,
  });

  final bool overlapsContent;
  final LayerLink notificationEducationLink;
  final GlobalKey notificationEducationTargetKey;
  final VoidCallback? onNotificationEducationTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final snapshot = ref.watch(initialHomeSnapshotProvider).value;
    final unreadCount =
        ref.watch(unreadNotificationsProvider).value ??
        snapshot?.unreadNotifications ??
        0;
    final profile =
        ref.watch(profileProvider).value ??
        snapshot?.profile ??
        const AppProfile();
    final session = ref.watch(authSessionProvider).value ?? snapshot?.session;
    final greetingName = _greetingName(context, profile, session);
    // Step 2: The outer pill container is removed. Components now float
    // independently on the transparent canvas per the refactoring spec.
    // The bottom border is preserved via a thin DecoratedBox wrapper so the
    // scroll-depth affordance (overlapsContent) continues to function.
    return RepaintBoundary(
      key: const ValueKey('dashboard-header-card'),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.surface.withValues(alpha: 0.99),
                  scheme.surface.withValues(alpha: 0.96),
                  Color.alphaBlend(
                    scheme.primary.withValues(
                      alpha: overlapsContent ? 0.035 : 0.018,
                    ),
                    scheme.surface,
                  ).withValues(alpha: 0.94),
                ],
                stops: const [0, 0.72, 1],
              ),
              boxShadow: overlapsContent
                  ? [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.07),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : const [],
            ),
            child: SafeArea(
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final screenWidth = constraints.maxWidth;
                      final isCompact = screenWidth < 360;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(
                          HkSpacing.md,
                          HkSpacing.xs,
                          HkSpacing.md,
                          HkSpacing.xs,
                        ),
                        child: _DashboardHeaderActions(
                          screenWidth: screenWidth,
                          isCompact: isCompact,
                          unreadCount: unreadCount,
                          notificationEducationLink: notificationEducationLink,
                          notificationEducationTargetKey:
                              notificationEducationTargetKey,
                          avatarUrl: session?.avatarUrl,
                          avatarProvider: snapshot?.avatarProvider,
                          fallbackName: greetingName,
                          onSearch: () => context.push('/search'),
                          onPoints: () => showPointsWalletSheet(context, ref),
                          onNotifications:
                              onNotificationEducationTap ??
                              () => context.push('/notifications'),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardHeaderActions extends StatelessWidget {
  const _DashboardHeaderActions({
    required this.screenWidth,
    required this.isCompact,
    required this.unreadCount,
    required this.notificationEducationLink,
    required this.notificationEducationTargetKey,
    required this.avatarUrl,
    required this.avatarProvider,
    required this.fallbackName,
    required this.onSearch,
    required this.onPoints,
    required this.onNotifications,
  });

  /// Logical width of the header row, used for responsive placeholder text.
  final double screenWidth;

  /// True when [screenWidth] < 360 px (compact/small breakpoint).
  final bool isCompact;

  final int unreadCount;
  final LayerLink notificationEducationLink;
  final GlobalKey notificationEducationTargetKey;
  final String? avatarUrl;
  final ImageProvider<Object>? avatarProvider;
  final String fallbackName;
  final VoidCallback onSearch;
  final VoidCallback onPoints;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final componentHeight = 48.0;
    final gap = isCompact ? 6.0 : HkSpacing.xs;
    final search = _DashboardSearchField(
      onPressed: onSearch,
      isCompact: isCompact,
      screenWidth: screenWidth,
    );
    final points = HkPointsPill(
      key: const ValueKey('home-points-control'),
      onTap: onPoints,
      compact: isCompact,
    );
    final notifications = CompositedTransformTarget(
      link: notificationEducationLink,
      child: KeyedSubtree(
        key: notificationEducationTargetKey,
        child: _NotificationButton(
          key: const ValueKey('home-notifications-control'),
          size: componentHeight,
          isCompact: isCompact,
          unreadCount: unreadCount,
          onPressed: onNotifications,
        ),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _DashboardAvatarButton(
          size: componentHeight,
          avatarUrl: avatarUrl,
          avatarProvider: avatarProvider,
          fallbackName: fallbackName,
        ),
        SizedBox(width: gap),
        Expanded(child: search),
        SizedBox(width: gap),
        points,
        SizedBox(width: gap),
        notifications,
      ],
    );
  }
}

class _DashboardAvatarButton extends StatelessWidget {
  const _DashboardAvatarButton({
    required this.size,
    required this.avatarUrl,
    required this.avatarProvider,
    required this.fallbackName,
  });

  final double size;
  final String? avatarUrl;
  final ImageProvider<Object>? avatarProvider;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.openAccount,
      excludeSemantics: true,
      child: Tooltip(
        message: context.l10n.openAccount,
        child: SizedBox.square(
          dimension: size,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.push('/account'),
              child: Center(
                child: hk_ui.ProfileAvatar(
                  avatarUrl: avatarUrl,
                  imageProvider: avatarProvider,
                  fallbackName: fallbackName,
                  radius: (size - 4) / 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardSearchField extends StatelessWidget {
  const _DashboardSearchField({
    required this.onPressed,
    required this.isCompact,
    required this.screenWidth,
  });

  final VoidCallback onPressed;

  /// True when the available width is below 360 px.
  final bool isCompact;

  /// Available layout width, used to select the responsive placeholder text.
  final double screenWidth;

  /// Returns the responsive placeholder text for the three mobile breakpoints
  /// defined in the header refactoring spec (Section 3):
  ///   W < 360 px  → short form
  ///   360 ≤ W ≤ 400 px → medium form
  ///   W > 400 px  → full form
  String _placeholder(AppLocalizations l10n) {
    if (screenWidth < 360) return l10n.searchShort;
    if (screenWidth <= 400) return l10n.searchRoomsItems;
    return l10n.searchRoomsItemsTasksNotes;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = isCompact ? 40.0 : 44.0;
    final hPad = isCompact ? 10.0 : HkSpacing.sm;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(HkRadii.full),
      side: BorderSide(color: scheme.outlineVariant),
    );
    final placeholder = _placeholder(context.l10n);
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: context.l10n.searchOwntend,
      child: Tooltip(
        message: context.l10n.searchOwntend,
        excludeFromSemantics: true,
        child: SizedBox(
          key: const ValueKey('home-search-control'),
          height: height,
          child: Material(
            color: scheme.surfaceContainerLowest,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: shape,
              onTap: onPressed,
              child: Padding(
                padding: EdgeInsetsDirectional.only(start: hPad, end: hPad),
                child: Row(
                  children: [
                    Icon(
                      Symbols.search_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: HkSpacing.xs),
                    Expanded(
                      child: Text(
                        placeholder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.78,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({
    required this.size,
    required this.isCompact,
    required this.unreadCount,
    required this.onPressed,
    super.key,
  });

  /// Component height and width (44 px standard, 40 px compact).
  final double size;

  /// True when the available width is below 360 px.
  final bool isCompact;

  final int unreadCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semanticLabel = unreadCount > 0
        ? '${context.l10n.notifications}, ${context.l10n.unreadCount(unreadCount)}'
        : context.l10n.notifications;
    // Spec Component D: independent squircle tile with an inline absolute dot
    // badge (8 × 8 px at top: 10, right: 10) replacing the former oversized
    // external badge (20 px at top: -7, right: -7).
    final dotOffset = isCompact ? 8.0 : 10.0;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(HkRadii.lg),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.72)),
    );
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: semanticLabel,
      child: Tooltip(
        message: context.l10n.notifications,
        excludeFromSemantics: true,
        child: SizedBox.square(
          dimension: size,
          child: Material(
            color: scheme.surfaceContainerLowest,
            shape: shape,
            elevation: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HkRadii.lg),
                boxShadow: [
                  BoxShadow(
                    color: HkColors.appTextPrimary.withValues(alpha: 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: InkWell(
                customBorder: shape,
                onTap: onPressed,
                child: Stack(
                  children: [
                    Center(
                      child: Icon(
                        Symbols.notifications_rounded,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (unreadCount > 0)
                      PositionedDirectional(
                        top: dotOffset,
                        end: dotOffset,
                        child: Container(
                          key: const ValueKey('home-notification-unread-badge'),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            // spec: status_danger #EF4444
                            color: const Color(0xFFEF4444),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLowest,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeSetupProgressCard extends StatelessWidget {
  const _HomeSetupProgressCard({
    required this.progress,
    required this.nextLabel,
    required this.onNext,
    super.key,
  });

  final features.HomeSetupProgress progress;
  final String nextLabel;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return hk_ui.PremiumCard(
      padding: const EdgeInsets.all(HkSpacing.md),
      borderColor: scheme.primary.withValues(alpha: 0.20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(HkRadii.lg),
                ),
                child: Icon(Symbols.home_rounded, color: scheme.primary),
              ),
              const SizedBox(width: HkSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.setUpYourHome,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: HkSpacing.space4),
                    Text(
                      context.l10n.setupHomeSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: HkSpacing.md),
          Text(
            context.l10n.setupProgress(progress.completedSteps),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: HkSpacing.xs),
          Row(
            children: [
              for (
                var index = 0;
                index < features.HomeSetupProgress.totalSteps;
                index++
              ) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: prefersReducedMotion(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    height: 8,
                    decoration: BoxDecoration(
                      color: index < progress.completedSteps
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(HkRadii.full),
                    ),
                  ),
                ),
                if (index < features.HomeSetupProgress.totalSteps - 1)
                  const SizedBox(width: HkSpacing.space6),
              ],
            ],
          ),
          const SizedBox(height: HkSpacing.md),
          Semantics(
            button: true,
            label: context.l10n.nextValue(nextLabel),
            child: Material(
              color: scheme.primaryContainer.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(HkRadii.lg),
              child: InkWell(
                borderRadius: BorderRadius.circular(HkRadii.lg),
                onTap: onNext,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: HkSpacing.sm,
                      vertical: HkSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n.nextValue(nextLabel),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        hk_ui.DirectionalIcon(
                          Symbols.arrow_forward_rounded,
                          color: scheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeReadinessSummaryCard extends StatelessWidget {
  const _HomeReadinessSummaryCard({
    required this.score,
    required this.overdueCount,
    required this.todayCount,
    required this.nextAction,
    required this.today,
    required this.nextSeven,
    required this.overdue,
    required this.onToday,
    required this.onNextSeven,
    required this.onOverdue,
    super.key,
  });

  final int score;
  final int overdueCount;
  final int todayCount;
  final String nextAction;
  final int today;
  final int nextSeven;
  final int overdue;
  final VoidCallback onToday;
  final VoidCallback onNextSeven;
  final VoidCallback onOverdue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final alert = overdueCount > 0;
    final color = alert
        ? scheme.error
        : score >= 85
        ? HkColors.green
        : HkColors.appWarning;
    final progress = (score / 100).clamp(0.0, 1.0).toDouble();
    final headline = alert
        ? context.l10n.homeReadinessNeedsAttention
        : todayCount > 0
        ? context.l10n.homeReadinessNextTaskReady
        : context.l10n.homeReadinessReadyForToday;
    final cleanNextAction = nextAction.trim().isEmpty
        ? context.l10n.reviewUpcomingTasks
        : nextAction.trim();
    return hk_ui.PremiumCard(
      padding: const EdgeInsets.all(12),
      borderColor: color.withValues(alpha: 0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 6,
                        backgroundColor: scheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                    Text(
                      bidiIsolate(context, '$score%'),
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: color, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HkSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          alert
                              ? Symbols.warning_rounded
                              : Symbols.health_and_safety_rounded,
                          color: color,
                          size: 18,
                        ),
                        const SizedBox(width: HkSpacing.space4),
                        Expanded(
                          child: Text(
                            context.l10n.homeReadiness,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      headline,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.nextValue(cleanNextAction),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: HkSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: context.l10n.today,
                  value: today,
                  icon: Symbols.today_rounded,
                  onTap: onToday,
                ),
              ),
              const SizedBox(width: HkSpacing.space6),
              Expanded(
                child: _SummaryMetric(
                  label: context.l10n.next7,
                  value: nextSeven,
                  icon: Symbols.upcoming_rounded,
                  onTap: onNextSeven,
                ),
              ),
              const SizedBox(width: HkSpacing.space6),
              Expanded(
                child: _SummaryMetric(
                  label: context.l10n.overdue,
                  value: overdue,
                  icon: Symbols.warning_rounded,
                  alert: overdue > 0,
                  onTap: onOverdue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.alert = false,
  });

  final String label;
  final int value;
  final IconData icon;
  final VoidCallback onTap;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = alert ? HkColors.appDanger : scheme.primary;
    return Semantics(
      button: true,
      label: '$label, $value',
      child: Material(
        color: color.withValues(alpha: alert ? 0.12 : 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HkRadii.md),
          side: BorderSide(color: color.withValues(alpha: 0.14)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(HkRadii.md),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: HkSpacing.xs,
                vertical: HkSpacing.xs,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 15, color: color),
                      const SizedBox(width: HkSpacing.space4),
                      Text(
                        '$value',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
