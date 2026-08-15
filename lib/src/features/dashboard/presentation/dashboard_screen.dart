part of '../../../../main.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  static const _homeDataSettleDuration = Duration(milliseconds: 180);

  late _HomeRenderData _homeData;
  Timer? _homeDataTimer;
  final LayerLink _weatherEducationLink = LayerLink();
  final LayerLink _notificationEducationLink = LayerLink();
  final GlobalKey _weatherEducationTargetKey = GlobalKey();
  final GlobalKey _notificationEducationTargetKey = GlobalKey();
  late final NativeAdPresentationDepth _nativeAdPresentationDepth;
  bool _forcePermissionEducationHandled = false;
  bool _permissionOverlaySuspendsNativeAds = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nativeAdPresentationDepth = ref.read(
      nativeAdPresentationDepthProvider.notifier,
    );
    _homeData = _readHomeData();
    ref.listenManual(tasksProvider, (_, _) => _scheduleHomeDataCommit());
    ref.listenManual(assetsProvider, (_, _) => _scheduleHomeDataCommit());
    ref.listenManual(roomsProvider, (_, _) => _scheduleHomeDataCommit());
    ref.listenManual(permissionEducationControllerProvider, (_, next) {
      _setPermissionOverlayNativeAdSuspension(
        next.isVisible && next.activeCapability != null,
      );
    });
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
    _setPermissionOverlayNativeAdSuspension(false, deferProviderUpdate: true);
    WidgetsBinding.instance.removeObserver(this);
    _homeDataTimer?.cancel();
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

  _HomeRenderData _readHomeData() {
    final snapshot = ref.read(initialHomeSnapshotProvider).value;
    if (snapshot != null) {
      return _HomeRenderData(
        tasks: snapshot.tasks,
        assets: snapshot.assets,
        rooms: snapshot.rooms,
      );
    }
    return _HomeRenderData(
      tasks: ref.read(tasksProvider).value ?? const [],
      assets: ref.read(assetsProvider).value ?? const [],
      rooms: ref.read(roomsProvider).value ?? const [],
    );
  }

  void _scheduleHomeDataCommit() {
    _homeDataTimer?.cancel();
    _homeDataTimer = Timer(_homeDataSettleDuration, () {
      if (!mounted) {
        return;
      }
      final next = _HomeRenderData(
        tasks: ref.read(tasksProvider).value ?? _homeData.tasks,
        assets: ref.read(assetsProvider).value ?? _homeData.assets,
        rooms: ref.read(roomsProvider).value ?? _homeData.rooms,
      );
      if (next.fingerprint == _homeData.fingerprint) {
        return;
      }
      setState(() => _homeData = next);
    });
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
    final tasks = _homeData.tasks;
    final now = DateTime.now();
    final taskBuckets = getTaskBuckets(tasks, now);
    final homeTaskSections = _homeTaskSections(context, taskBuckets);
    const homeTaskLimit = 3;
    final assets = _homeData.assets;
    final rooms = _homeData.rooms;
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
              onRefresh: () =>
                  ref.read(streakServiceProvider).refresh(DateTime.now()),
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
              () => showModalBottomSheet<HomeLocation>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
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

class _HomeRenderData {
  _HomeRenderData({
    required this.tasks,
    required this.assets,
    required this.rooms,
  }) : fingerprint = Object.hash(
         taskListFingerprint(tasks),
         assetListFingerprint(assets),
         roomListFingerprint(rooms),
       );

  final List<TaskItem> tasks;
  final List<Asset> assets;
  final List<Room> rooms;
  final int fingerprint;
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
        ref.watch(localThemeClockProvider).value ?? DateTime.now().toLocal();
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
          _failureMessage(context, error, fallback: AppFailureCode.themeUpdate),
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
    final reduceMotion = _prefersReducedMotion(context);
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
      now: DateTime.now(),
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
        nextAction: _localizedFeatureMessage(context, readiness.nextBestAction),
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
    final componentHeight = isCompact ? 40.0 : 44.0;
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
                        // Neutral dark icon per spec (icon_neutral: #344054)
                        color: const Color(0xFF344054),
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
                            border: Border.all(color: Colors.white, width: 1.5),
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

// Legacy implementation retained for source compatibility; all live identity
// surfaces use the shared fixed-square ProfileAvatar component.
// ignore: unused_element

class _GoogleProfileAvatar extends StatefulWidget {
  const _GoogleProfileAvatar({
    required this.avatarUrl,
    required this.fallbackName,
    required this.radius,
  });

  final String? avatarUrl;
  final String fallbackName;
  final double radius;

  @override
  State<_GoogleProfileAvatar> createState() => _GoogleProfileAvatarState();
}

class _GoogleProfileAvatarState extends State<_GoogleProfileAvatar> {
  String? _failedAvatarUrl;

  @override
  void didUpdateWidget(covariant _GoogleProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl) {
      _failedAvatarUrl = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = _profileInitials(widget.fallbackName);
    final avatarUrl = widget.avatarUrl;
    final showNetworkAvatar =
        avatarUrl != null &&
        avatarUrl.trim().isNotEmpty &&
        avatarUrl != _failedAvatarUrl;
    final size = (widget.radius * 2).round();
    return Container(
      width: widget.radius * 2,
      height: widget.radius * 2,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surfaceContainerLowest, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: showNetworkAvatar
          ? Image.network(
              avatarUrl,
              fit: BoxFit.cover,
              cacheWidth: size * MediaQuery.devicePixelRatioOf(context).ceil(),
              cacheHeight: size * MediaQuery.devicePixelRatioOf(context).ceil(),
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded || frame != null) {
                  return child;
                }
                return const Center(
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _failedAvatarUrl != avatarUrl) {
                    setState(() => _failedAvatarUrl = avatarUrl);
                  }
                });
                return _AvatarFallback(initials: initials);
              },
            )
          : _AvatarFallback(initials: initials),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: initials.isEmpty
          ? Icon(Symbols.person_rounded, color: scheme.primary)
          : Text(
              initials,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

String _profileInitials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return 'H';
  return parts
      .take(2)
      .map((part) => part.characters.first)
      .join()
      .toUpperCase();
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
                    duration: _prefersReducedMotion(context)
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
                        Icon(
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
                      '$score%',
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
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: HkSpacing.xs,
              vertical: HkSpacing.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 15, color: color),
                    const SizedBox(width: HkSpacing.space4),
                    Text(
                      '$value',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: color, fontWeight: FontWeight.w900),
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
    );
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({
    required this.weather,
    required this.location,
    required this.capability,
    required this.localNow,
    required this.isDark,
    required this.onToggleTheme,
    required this.onCapabilityAction,
  });

  final WeatherSnapshot? weather;
  final HomeLocation? location;
  final WeatherAreaCapabilitySnapshot? capability;
  final DateTime localNow;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback? onCapabilityAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = weather;
    final day = _isLocalDaytime(localNow);
    final usesCurrentLocation =
        capability?.mode == WeatherAreaMode.device &&
        capability?.effectiveState == EffectiveCapabilityState.active;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.18),
            HkColors.secondaryFixed.withValues(alpha: 0.78),
            scheme.surfaceContainerLowest,
          ],
          stops: const [0, 0.58, 1],
        ),
        borderRadius: BorderRadius.circular(HkRadii.xl),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          PositionedDirectional(
            end: -12,
            top: -18,
            child: Icon(
              current == null
                  ? Symbols.cloud_rounded
                  : _weatherIcon(current.weatherCode),
              size: 96,
              color: scheme.primary.withValues(alpha: 0.055),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(HkSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (current == null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _WeatherIconBadge(icon: Symbols.location_on_rounded),
                      const SizedBox(width: HkSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              location == null
                                  ? context.l10n.weatherNotSet
                                  : context.l10n.weatherUnavailable,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: HkSpacing.space2),
                            Text(
                              location == null
                                  ? context.l10n.addHomeLocationInSettings
                                  : context
                                        .l10n
                                        .weatherWillUpdateWhenConnectionReturns,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: HkSpacing.xs),
                      _WeatherThemeButton(
                        daytime: day,
                        isDark: isDark,
                        onPressed: onToggleTheme,
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final textScale =
                              MediaQuery.textScalerOf(context).scale(10) / 10;
                          final compactHeader =
                              constraints.maxWidth < 300 || textScale > 1.3;
                          final gap = compactHeader
                              ? HkSpacing.xs
                              : HkSpacing.sm;
                          final temperatureWidth = compactHeader ? 46.0 : 58.0;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _shortWeatherLocationLabel(
                                              context,
                                              current.location.label,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                        if (usesCurrentLocation) ...[
                                          const SizedBox(
                                            width: HkSpacing.space6,
                                          ),
                                          const _WeatherCurrentLocationBadge(),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: HkSpacing.space2),
                                    Text(
                                      '${_localizedWeatherSummary(context, current.weatherCode)} \u00B7 ${context.l10n.updatedTime(_formatShortTime(context, current.updatedAt))}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: gap),
                              _WeatherThemeButton(
                                daytime: day,
                                isDark: isDark,
                                onPressed: onToggleTheme,
                              ),
                              SizedBox(width: gap),
                              SizedBox(
                                width: temperatureWidth,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: Text(
                                    '${current.temperature.round()}\u00B0C',
                                    style: Theme.of(context)
                                        .textTheme
                                        .displaySmall
                                        ?.copyWith(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w800,
                                          height: 1,
                                        ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: HkSpacing.xs),
                      WeatherDetailChips(weather: current),
                    ],
                  ),
                if (capability != null && !usesCurrentLocation) ...[
                  const SizedBox(height: HkSpacing.xs),
                  _WeatherCapabilityStatus(
                    capability: capability!,
                    onAction: onCapabilityAction,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherCurrentLocationBadge extends StatelessWidget {
  const _WeatherCurrentLocationBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: context.l10n.permissionUsingCurrentLocation,
      child: Semantics(
        container: true,
        label: context.l10n.permissionUsingCurrentLocation,
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(6, 3, 7, 3),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(HkRadii.full),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Symbols.my_location_rounded,
                  size: 12,
                  color: scheme.primary,
                ),
                const SizedBox(width: HkSpacing.space4),
                Text(
                  context.l10n.weatherCurrentLocationShort,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeatherCapabilityStatus extends StatelessWidget {
  const _WeatherCapabilityStatus({
    required this.capability,
    required this.onAction,
  });

  final WeatherAreaCapabilitySnapshot capability;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isManual = capability.mode == WeatherAreaMode.manual;
    final isDeviceActive =
        capability.mode == WeatherAreaMode.device &&
        capability.effectiveState == EffectiveCapabilityState.active;
    final label = isManual && capability.selectedArea != null
        ? context.l10n.permissionSelectedArea(capability.selectedArea!.label)
        : isDeviceActive
        ? context.l10n.permissionUsingCurrentLocation
        : capability.locationServiceEnabled == false
        ? context.l10n.locationServicesAreOff
        : capability.isConfigured
        ? context.l10n.permissionLocationAccessRequired
        : context.l10n.weatherNotSet;
    final showAction = !isDeviceActive;
    final actionLabel = isManual
        ? context.l10n.change
        : capability.locationServiceEnabled == false
        ? context.l10n.turnOnLocationServices
        : context.l10n.configure;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Row(
        children: [
          Icon(
            isManual
                ? Symbols.location_city_rounded
                : isDeviceActive
                ? Symbols.my_location_rounded
                : Symbols.location_off_rounded,
            size: 18,
            color: isManual || isDeviceActive ? scheme.primary : scheme.error,
          ),
          const SizedBox(width: HkSpacing.xs),
          Expanded(
            child: Text(
              label,
              key: const ValueKey('dashboard-weather-capability-status'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (showAction)
            SizedBox(
              height: 48,
              child: TextButton.icon(
                onPressed: onAction,
                icon: const Icon(Symbols.settings_rounded, size: 18),
                label: Text(actionLabel),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeatherThemeButton extends StatelessWidget {
  const _WeatherThemeButton({
    required this.daytime,
    required this.isDark,
    required this.onPressed,
  });

  final bool daytime;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = isDark
        ? context.l10n.switchToLightMode
        : context.l10n.switchToDarkMode;
    return Tooltip(
      message: message,
      child: Semantics(
        button: true,
        label: message,
        child: SizedBox.square(
          dimension: 44,
          child: IconButton(
            onPressed: onPressed,
            style: IconButton.styleFrom(
              backgroundColor: scheme.surfaceContainerLowest.withValues(
                alpha: 0.86,
              ),
              foregroundColor: daytime ? HkColors.appWarning : scheme.primary,
              shape: const CircleBorder(),
              side: BorderSide(color: scheme.primary.withValues(alpha: 0.12)),
            ),
            icon: Icon(
              daytime ? Symbols.wb_sunny_rounded : Symbols.dark_mode_rounded,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class WeatherDetailChips extends StatelessWidget {
  const WeatherDetailChips({required this.weather, super.key});

  final WeatherSnapshot weather;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
        final compact = constraints.maxWidth < 340 || textScale > 1.3;
        final showIcons = constraints.maxWidth >= 320 && textScale <= 1.3;
        final gap = compact ? HkSpacing.space4 : HkSpacing.space6;
        return Row(
          children: [
            Expanded(
              child: _WeatherDetailChip(
                icon: Symbols.thermostat_rounded,
                label: context.l10n.feels,
                value: '${weather.apparentTemperature.round()}\u00B0C',
                compact: compact,
                showIcon: showIcons,
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: _WeatherDetailChip(
                icon: Symbols.water_drop_rounded,
                label: context.l10n.humidity,
                value: '${weather.humidity}%',
                compact: compact,
                showIcon: showIcons,
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: _WeatherDetailChip(
                icon: Symbols.air_rounded,
                label: context.l10n.wind,
                value: '${weather.windSpeed.round()} km/h',
                compact: compact,
                showIcon: showIcons,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WeatherIconBadge extends StatelessWidget {
  const _WeatherIconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.82),
        shape: BoxShape.circle,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, color: scheme.primary, size: 20),
    );
  }
}

bool _prefersReducedMotion(BuildContext context) {
  final media = MediaQuery.maybeOf(context);
  return media?.disableAnimations == true ||
      media?.accessibleNavigation == true;
}

class _WeatherDetailChip extends StatelessWidget {
  const _WeatherDetailChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.compact,
    required this.showIcon,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool compact;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 32 : 34),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? HkSpacing.space4 : HkSpacing.xs,
        vertical: HkSpacing.space6,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(HkRadii.full),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: showIcon
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: compact ? 13 : 15, color: scheme.primary),
                    SizedBox(width: compact ? 3 : HkSpacing.space4),
                    _WeatherDetailText(
                      label: label,
                      value: value,
                      compact: compact,
                    ),
                  ],
                )
              : _WeatherDetailText(
                  label: label,
                  value: value,
                  compact: compact,
                ),
        ),
      ),
    );
  }
}

class _WeatherDetailText extends StatelessWidget {
  const _WeatherDetailText({
    required this.label,
    required this.value,
    required this.compact,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label $value',
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w800,
        fontSize: compact ? 10.5 : null,
      ),
    );
  }
}

Future<File?> _localFile(String? relativePath) async {
  if (relativePath == null || relativePath.trim().isEmpty) {
    return null;
  }
  final path = relativePath.trim();
  final file = p.isAbsolute(path)
      ? File(path)
      : File(
          p.joinAll([
            (await getApplicationDocumentsDirectory()).path,
            ...path.split('/'),
          ]),
        );
  return await file.exists() ? file : null;
}

Future<void> _syncProfileIfEnabled(WidgetRef ref) async {
  try {
    final sync = ref.read(cloudSyncRepositoryProvider);
    final status = await sync.status();
    if (status.enabled) {
      await sync.syncNow();
    }
  } catch (_) {
    // Profile sync is best-effort; visible sync status surfaces failures.
  }
}

String _shortWeatherLocationLabel(BuildContext context, String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) {
    return context.l10n.home;
  }
  final firstPart = trimmed.split(RegExp(r'[,\n]')).first.trim();
  final withoutDistrict = firstPart.replaceFirst(
    RegExp(r'\s+District$', caseSensitive: false),
    '',
  );
  if (withoutDistrict.trim().isNotEmpty) {
    return withoutDistrict.trim();
  }
  return firstPart.isEmpty ? trimmed : firstPart;
}

IconData _weatherIcon(int code) {
  return switch (code) {
    0 => Symbols.sunny_rounded,
    1 || 2 || 3 => Symbols.partly_cloudy_day_rounded,
    45 || 48 => Symbols.foggy_rounded,
    51 || 53 || 55 || 56 || 57 => Symbols.rainy_light_rounded,
    61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => Symbols.rainy_rounded,
    71 || 73 || 75 || 77 || 85 || 86 => Symbols.weather_snowy_rounded,
    95 || 96 || 99 => Symbols.thunderstorm_rounded,
    _ => Symbols.cloud_rounded,
  };
}

String _localizedWeatherSummary(BuildContext context, int code) {
  return switch (code) {
    0 => context.l10n.clearWeather,
    1 || 2 => context.l10n.partlyCloudy,
    3 => context.l10n.cloudy,
    45 || 48 => context.l10n.fog,
    51 || 53 || 55 || 56 || 57 => context.l10n.drizzle,
    61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => context.l10n.rain,
    71 || 73 || 75 || 77 || 85 || 86 => context.l10n.snow,
    95 || 96 || 99 => context.l10n.storms,
    _ => context.l10n.weather,
  };
}

String _greetingName(
  BuildContext context,
  AppProfile profile,
  AuthSession? session,
) {
  for (final candidate in [
    profile.nickname,
    session?.fullName,
    session?.name,
    _emailUsername(session?.email),
    context.l10n.there,
  ]) {
    final trimmed = candidate?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return context.l10n.there;
}

String? _emailUsername(String? email) {
  final trimmed = email?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final atIndex = trimmed.indexOf('@');
  if (atIndex <= 0) {
    return trimmed;
  }
  return trimmed.substring(0, atIndex);
}

String _taskGroupCountLabel(BuildContext context, int count) {
  return context.l10n.taskCountLabel(count);
}
