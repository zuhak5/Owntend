part of 'startup_presentation.dart';

class _InitialCloudHydrationOverlay extends StatefulWidget {
  const _InitialCloudHydrationOverlay({
    required this.status,
    required this.failure,
    required this.canContinueOffline,
    required this.onRetry,
    required this.onCheckConnection,
    required this.onContinueOffline,
    required this.onSignOut,
  });

  final SyncStatus status;
  final StartupFailure? failure;
  final bool canContinueOffline;
  final Future<void> Function() onRetry;
  final Future<void> Function() onCheckConnection;
  final Future<void> Function()? onContinueOffline;
  final Future<void> Function() onSignOut;

  @override
  State<_InitialCloudHydrationOverlay> createState() =>
      _InitialCloudHydrationOverlayState();
}

class _InitialCloudHydrationOverlayState
    extends State<_InitialCloudHydrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambientController;
  bool? _reducedMotion;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = prefersReducedMotion(context);
    if (_reducedMotion == reducedMotion) {
      return;
    }
    _reducedMotion = reducedMotion;
    if (reducedMotion) {
      _ambientController
        ..stop()
        ..value = 0.28;
    } else {
      _ambientController.repeat();
    }
  }

  @override
  void dispose() {
    _ambientController.dispose();
    super.dispose();
  }

  bool get _failedStatus =>
      widget.status.phase == SyncPhase.error ||
      widget.status.phase == SyncPhase.offline ||
      widget.status.phase == SyncPhase.blocked;

  InitialHydrationProgress get _progress =>
      widget.status.initialHydrationProgress ??
      _syntheticStartupProgress(
        _failedStatus ? RestoreRunState.failed : RestoreRunState.running,
      );

  InitialHydrationStage get _stage => widget.failure?.stage ?? _progress.stage;

  double get _ambientProgress => _progress.fraction;

  String get _stageMessage => switch (_stage) {
    InitialHydrationStage.connecting =>
      context.l10n.hydrationConnectingSecurely,
    InitialHydrationStage.restoringCloudData =>
      context.l10n.hydrationRestoringCloudData,
    InitialHydrationStage.restoringPhotos =>
      context.l10n.hydrationRestoringPhotos,
    InitialHydrationStage.syncingLocalChanges =>
      context.l10n.hydrationSyncingLocalChanges,
    InitialHydrationStage.checkingLatestUpdates =>
      context.l10n.hydrationCheckingLatestUpdates,
    InitialHydrationStage.finalizing => context.l10n.finalizingOwntend,
  };

  String get failureMessage {
    final explicit = widget.failure?.message?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (widget.failure?.timedOut == true) {
      return context.l10n.hydrationStageTimedOutMessage(_stageMessage);
    }
    return context.l10n.hydrationStageFailedMessage(_stageMessage);
  }

  @override
  Widget build(BuildContext context) {
    final failed = _failedStatus;
    final reducedMotion = _reducedMotion ?? false;

    return FullCanvasSystemUi(
      child: Theme(
        data: OwntendTheme.light(),
        child: Builder(
          builder: (context) {
            return RepaintBoundary(
              key: const ValueKey('initial-cloud-hydration'),
              child: Material(
                color: HkColors.appBackground,
                child: FullBleedIllustrationBackground(
                  key: const ValueKey('restore-hero-illustration'),
                  illustration: _HydrationHero(
                    animation: _ambientController,
                    reducedMotion: reducedMotion,
                  ),
                  alignment: Alignment.center,
                  fit: BoxFit.contain,
                  backgroundGradient: const RadialGradient(
                    center: Alignment(0.08, -0.02),
                    radius: 1.15,
                    colors: [
                      Color(0xFFE3ECE2),
                      Color(0xFFF5F4F0),
                      HkColors.appBackground,
                    ],
                    stops: [0, 0.62, 1],
                  ),
                  topFade: 0.10,
                  bottomFade: 0.20,
                  leftFade: 0.08,
                  rightFade: 0.08,
                  decorativeOverlay: RepaintBoundary(
                    child: CustomPaint(
                      painter: _HydrationBackdropPainter(
                        animation: _ambientController,
                        progress: _ambientProgress,
                        parallax: Offset.zero,
                        reducedMotion: reducedMotion,
                      ),
                    ),
                  ),
                  illustrationOverlay: failed
                      ? ColoredBox(
                          color: Theme.of(context).colorScheme.errorContainer
                              .withValues(alpha: 0.16),
                        )
                      : null,
                  scrim: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xEBF5F4F0),
                      Color(0x00F5F4F0),
                      Color(0x00F5F4F0),
                      Color(0xE8F7F9FC),
                    ],
                    stops: [0, 0.18, 0.52, 1],
                  ),
                  child: SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final horizontalPadding = constraints.maxWidth < 400
                            ? 12.0
                            : 24.0;
                        final contentWidth = math.min(
                          640.0,
                          constraints.maxWidth - horizontalPadding * 2,
                        );
                        final textScale =
                            MediaQuery.textScalerOf(context).scale(10) / 10;
                        final compact =
                            constraints.maxHeight < 760 || textScale > 1.12;
                        final verticalPadding = compact ? 4.0 : 8.0;
                        final availableHeight = math.max(
                          0.0,
                          constraints.maxHeight - verticalPadding * 2,
                        );
                        final baseLayoutHeight = math.min(
                          compact ? 740.0 : 980.0,
                          availableHeight,
                        );
                        final rawScale = math
                            .min(
                              contentWidth / 560,
                              constraints.maxHeight / 844,
                            )
                            .clamp(0.68, 1.0);
                        final sizeScale =
                            (rawScale / math.max(1, textScale * 0.8)).clamp(
                              0.58,
                              1.0,
                            );
                        final progressHeight = failed
                            ? textScale > 1.25
                                  ? widget.canContinueOffline
                                        ? 290.0
                                        : 258.0
                                  : contentWidth < 420
                                  ? widget.canContinueOffline
                                        ? 246.0
                                        : 214.0
                                  : widget.canContinueOffline
                                  ? 220.0
                                  : 184.0
                            : compact
                            ? 82.0
                            : 100.0;
                        final stageHeight = compact ? 194.0 : 224.0;
                        final tipHeight = compact ? 60.0 : 72.0;
                        final gap = compact ? 7.0 : 10.0;
                        final minimumHeroHeight = failed
                            ? progressHeight + (compact ? 124.0 : 154.0)
                            : 250.0;
                        final minimumLayoutHeight =
                            minimumHeroHeight +
                            stageHeight +
                            tipHeight +
                            gap * 2;
                        final layoutHeight =
                            (failed || minimumLayoutHeight > baseLayoutHeight)
                            ? math.max(baseLayoutHeight, minimumLayoutHeight)
                            : baseLayoutHeight;
                        final needsScroll = layoutHeight > availableHeight;
                        final heroSectionHeight = math.max(
                          minimumHeroHeight,
                          layoutHeight - stageHeight - tipHeight - gap * 2,
                        );
                        final frame = ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: SizedBox(
                            key: const ValueKey('restore-reference-frame'),
                            width: contentWidth,
                            height: layoutHeight,
                            child: Column(
                              children: [
                                SizedBox(
                                  key: const ValueKey('restore-hero-section'),
                                  height: heroSectionHeight,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Positioned(
                                        left: 4,
                                        right: 4,
                                        top: 0,
                                        child: _HydrationTitle(
                                          failed: failed,
                                          stageLabel: _stageMessage,
                                          sizeScale: sizeScale,
                                        ),
                                      ),
                                      Positioned(
                                        left: compact ? 12 : 24,
                                        right: compact ? 12 : 24,
                                        top: failed
                                            ? compact
                                                  ? 58
                                                  : 72
                                            : compact
                                            ? 34
                                            : 46,
                                        child: _HydrationSubtitle(
                                          failed: failed,
                                          message: failed
                                              ? failureMessage
                                              : null,
                                          sizeScale: sizeScale,
                                        ),
                                      ),
                                      if (failed &&
                                          heroSectionHeight >
                                              progressHeight + 190)
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          top: compact ? 86 : 104,
                                          bottom: progressHeight + 8,
                                          child: Center(
                                            child: hk_ui.BreathingStatusIcon(
                                              icon: Symbols.cloud_off_rounded,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                              size: compact ? 52 : 64,
                                            ),
                                          ),
                                        ),
                                      Positioned(
                                        left: contentWidth >= 520 ? 30 : 0,
                                        right: contentWidth >= 520 ? 30 : 0,
                                        bottom: 0,
                                        height: progressHeight,
                                        child: failed
                                            ? _HydrationFailureActions(
                                                onRetry: widget.onRetry,
                                                onCheckConnection:
                                                    widget.onCheckConnection,
                                                onContinueOffline:
                                                    widget.onContinueOffline,
                                                onSignOut: widget.onSignOut,
                                                canContinueOffline:
                                                    widget.canContinueOffline,
                                                showConnectionCheck:
                                                    widget
                                                        .failure
                                                        ?.allowConnectionCheck ??
                                                    true,
                                                sizeScale: sizeScale,
                                                percentage:
                                                    _progress.percentage,
                                                stageLabel: _stageMessage,
                                              )
                                            : _HydrationProgress(
                                                label: _stageMessage,
                                                reducedMotion: reducedMotion,
                                                sizeScale: sizeScale,
                                                compact: compact,
                                                fraction: _progress.fraction,
                                                percentage:
                                                    _progress.percentage,
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: gap),
                                SizedBox(
                                  key: const ValueKey('restore-stage-card'),
                                  height: stageHeight,
                                  child: _RestoreStageList(
                                    stage: _stage,
                                    failed: failed,
                                    sizeScale: sizeScale,
                                    compact: compact,
                                  ),
                                ),
                                SizedBox(height: gap),
                                SizedBox(
                                  key: const ValueKey('restore-tip-card'),
                                  height: tipHeight,
                                  child: _HydrationTipCard(
                                    key: const ValueKey('hydration-tip'),
                                    tip: widget.canContinueOffline
                                        ? context
                                              .l10n
                                              .tipYourTasksStayAvailableEvenWhenYouAreOffline
                                        : context
                                              .l10n
                                              .yourTasksRoutinesAndRemindersRestoreInDependencyOrder,
                                    reducedMotion: reducedMotion,
                                    sizeScale: sizeScale,
                                    compact: compact,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                        return Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                            vertical: verticalPadding,
                          ),
                          child: needsScroll
                              ? SingleChildScrollView(
                                  key: const ValueKey('restore-scroll-view'),
                                  child: Center(child: frame),
                                )
                              : Center(child: frame),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HydrationTitle extends StatelessWidget {
  const _HydrationTitle({
    required this.failed,
    required this.stageLabel,
    required this.sizeScale,
  });

  final bool failed;
  final String stageLabel;
  final double sizeScale;

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Center(
        child: Text(
          context.l10n.hydrationStageFailureTitle(stageLabel),
          textAlign: TextAlign.center,
          maxLines: 2,
          style: TextStyle(
            color: HkColors.appTextPrimary,
            fontSize: 38 * sizeScale,
            height: 1.04,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      );
    }
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Text(
          context.l10n.restoringYourFlow,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: HkColors.appTextPrimary,
            fontFamily: 'Geist',
            fontSize: 38 * sizeScale,
            height: 1,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        PositionedDirectional(
          end: 25 * sizeScale,
          top: -4 * sizeScale,
          child: Transform.rotate(
            angle: -0.45,
            child: Icon(
              Symbols.trending_up_rounded,
              color: HkColors.appPrimary,
              size: 25 * sizeScale,
            ),
          ),
        ),
      ],
    );
  }
}

class _HydrationSubtitle extends StatelessWidget {
  const _HydrationSubtitle({
    required this.failed,
    required this.message,
    required this.sizeScale,
  });

  final bool failed;
  final String? message;
  final double sizeScale;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        failed
            ? message ?? context.l10n.hydrationStageFailedMessage('')
            : context.l10n.securelyRestoringTasksRoutinesAndReminders,
        maxLines: failed ? 3 : 2,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: HkColors.appTextSecondary,
          fontFamily: 'Geist',
          fontSize: 17.5 * sizeScale,
          height: 1.25,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _HydrationFailureActions extends StatelessWidget {
  const _HydrationFailureActions({
    required this.onRetry,
    required this.onCheckConnection,
    required this.onContinueOffline,
    required this.onSignOut,
    required this.canContinueOffline,
    required this.showConnectionCheck,
    required this.sizeScale,
    required this.percentage,
    required this.stageLabel,
  });

  final Future<void> Function() onRetry;
  final Future<void> Function() onCheckConnection;
  final Future<void> Function()? onContinueOffline;
  final Future<void> Function() onSignOut;
  final bool canContinueOffline;
  final bool showConnectionCheck;
  final double sizeScale;
  final int percentage;
  final String stageLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stackActions =
        MediaQuery.sizeOf(context).width < 400 ||
        MediaQuery.textScalerOf(context).scale(10) > 11.5;
    final actions = <Widget>[
      FilledButton.icon(
        key: const ValueKey('restore-retry-button'),
        onPressed: onRetry,
        icon: Icon(Symbols.refresh_rounded, size: 20 * sizeScale),
        label: Text(context.l10n.retry),
      ),
      if (showConnectionCheck)
        OutlinedButton.icon(
          key: const ValueKey('restore-check-connection-button'),
          onPressed: onCheckConnection,
          icon: Icon(Symbols.wifi_rounded, size: 20 * sizeScale),
          label: Text(context.l10n.checkConnection),
        ),
      if (canContinueOffline && onContinueOffline != null)
        OutlinedButton(
          key: const ValueKey('restore-continue-offline-button'),
          onPressed: onContinueOffline,
          child: Text(context.l10n.continueOffline),
        ),
      OutlinedButton(
        key: const ValueKey('restore-sign-out-button'),
        onPressed: onSignOut,
        child: Text(context.l10n.signOut),
      ),
    ];
    return _HydrationCard(
      radius: 28 * sizeScale,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 10 * sizeScale,
          vertical: 10 * sizeScale,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Symbols.cloud_off_rounded,
              color: scheme.error,
              size: 38 * sizeScale,
            ),
            SizedBox(height: 4 * sizeScale),
            Text(
              '$percentage% - $stageLabel',
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18 * sizeScale,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 7 * sizeScale),
            if (stackActions)
              Column(
                children: [
                  for (var index = 0; index < actions.length; index++) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: actions[index],
                    ),
                    if (index != actions.length - 1)
                      SizedBox(height: 5 * sizeScale),
                  ],
                ],
              )
            else
              Wrap(
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                spacing: 8 * sizeScale,
                runSpacing: 7 * sizeScale,
                children: actions,
              ),
          ],
        ),
      ),
    );
  }
}

class _HydrationHero extends StatelessWidget {
  const _HydrationHero({required this.animation, required this.reducedMotion});

  final Animation<double> animation;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: const RemoteOrBundledImage(
        assetPath: 'assets/illustrations/owntend-restore-hero-target.png',
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
      ),
      builder: (context, child) {
        final phase = animation.value * math.pi * 2;
        final float = reducedMotion ? 0.0 : math.sin(phase) * 3;
        return Transform.translate(offset: Offset(0, float), child: child);
      },
    );
  }
}

class _RestoreStageList extends StatelessWidget {
  const _RestoreStageList({
    required this.stage,
    required this.failed,
    required this.sizeScale,
    required this.compact,
  });

  final InitialHydrationStage stage;
  final bool failed;
  final double sizeScale;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final stages = <(InitialHydrationStage, String)>[
      (
        InitialHydrationStage.connecting,
        context.l10n.hydrationConnectingSecurely,
      ),
      (
        InitialHydrationStage.restoringCloudData,
        context.l10n.hydrationRestoringCloudData,
      ),
      (
        InitialHydrationStage.restoringPhotos,
        context.l10n.hydrationRestoringPhotos,
      ),
      (
        InitialHydrationStage.syncingLocalChanges,
        context.l10n.hydrationSyncingLocalChanges,
      ),
      (
        InitialHydrationStage.checkingLatestUpdates,
        context.l10n.hydrationCheckingLatestUpdates,
      ),
      (InitialHydrationStage.finalizing, context.l10n.finalizingOwntend),
    ];
    return _HydrationCard(
      radius: 24 * sizeScale,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var index = 0; index < stages.length; index++)
            _RestoreStageRow(
              label: stages[index].$2,
              rowStage: stages[index].$1,
              currentStage: stage,
              failed: failed,
              sizeScale: sizeScale,
              compact: compact,
              isLast: index == stages.length - 1,
            ),
        ],
      ),
    );
  }
}

class _RestoreStageRow extends StatelessWidget {
  const _RestoreStageRow({
    required this.label,
    required this.rowStage,
    required this.currentStage,
    required this.failed,
    required this.sizeScale,
    required this.compact,
    required this.isLast,
  });

  final String label;
  final InitialHydrationStage rowStage;
  final InitialHydrationStage currentStage;
  final bool failed;
  final double sizeScale;
  final bool compact;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final complete = rowStage.index < currentStage.index;
    final active = rowStage == currentStage;
    const activeColor = HkColors.appPrimary;
    const pendingColor = HkColors.appTextTertiary;
    final color = complete || active ? activeColor : pendingColor;
    final rowHeight = compact ? 31.0 : 36.0;
    final indicatorSize = compact ? 20.0 : 24.0;
    return SizedBox(
      height: rowHeight,
      child: Row(
        children: [
          SizedBox(
            width: compact ? 34 : 46,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (!isLast)
                  Positioned(
                    top: rowHeight / 2 + indicatorSize / 2,
                    bottom: -(rowHeight / 2 - indicatorSize / 2),
                    child: Container(
                      width: compact ? 1.5 : 2,
                      color: (complete || active ? activeColor : pendingColor)
                          .withValues(alpha: complete ? 0.72 : 0.42),
                    ),
                  ),
                Container(
                  width: indicatorSize,
                  height: indicatorSize,
                  decoration: BoxDecoration(
                    color: complete
                        ? activeColor
                        : active
                        ? HkColors.appPrimaryMuted
                        : HkColors.appSurface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: complete ? 1 : 0.86),
                      width: compact ? 1.4 : 1.7,
                    ),
                    boxShadow: active || complete
                        ? [
                            BoxShadow(
                              color: activeColor.withValues(alpha: 0.34),
                              blurRadius: compact ? 8 : 11,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: complete
                      ? Icon(
                          Symbols.check_rounded,
                          size: compact ? 13 : 16,
                          color: const Color(0xFFF6FFF9),
                        )
                      : active
                      ? Center(
                          child: Container(
                            width: compact ? 5 : 7,
                            height: compact ? 5 : 7,
                            decoration: BoxDecoration(
                              color: activeColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 5 : 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: active || complete
                    ? HkColors.appTextPrimary
                    : HkColors.appTextSecondary.withValues(alpha: 0.82),
                fontSize: (compact ? 16.5 : 17.5) * sizeScale,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: compact ? 6 : 9),
          Text(
            complete
                ? context.l10n.hydrationStepCompleted
                : active
                ? failed
                      ? context.l10n.hydrationStepNeedsAttention
                      : context.l10n.hydrationStepInProgress
                : context.l10n.hydrationStepPending,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: active || complete
                  ? activeColor
                  : HkColors.appTextTertiary,
              fontSize: (compact ? 13.5 : 15) * sizeScale,
              fontWeight: active || complete
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
          SizedBox(width: compact ? 9 : 16),
        ],
      ),
    );
  }
}

class _HydrationProgress extends StatelessWidget {
  const _HydrationProgress({
    required this.label,
    required this.reducedMotion,
    required this.sizeScale,
    required this.compact,
    required this.fraction,
    required this.percentage,
  });

  final String label;
  final bool reducedMotion;
  final double sizeScale;
  final bool compact;
  final double fraction;
  final int percentage;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.cloudRestorationInProgress,
      value: '$percentage percent, $label',
      child: _HydrationCard(
        radius: (compact ? 19 : 23) * sizeScale,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: (compact ? 14 : 22) * sizeScale,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Symbols.cloud_sync_rounded,
                    color: HkColors.appPrimary,
                    size: (compact ? 23 : 28) * sizeScale,
                  ),
                  SizedBox(width: (compact ? 7 : 9) * sizeScale),
                  Text(
                    bidiIsolate(context, '$percentage%'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: HkColors.appPrimary,
                      fontSize: (compact ? 20 : 24) * sizeScale,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(width: (compact ? 7 : 9) * sizeScale),
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: reducedMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 300),
                      child: Text(
                        label,
                        key: ValueKey(label),
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: HkColors.appTextPrimary,
                          fontSize: (compact ? 15.5 : 18) * sizeScale,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: (compact ? 7 : 9) * sizeScale),
              ClipRRect(
                key: const ValueKey('hydration-progress-bar'),
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: compact ? 5 : 7,
                  backgroundColor: HkColors.surfaceContainerHigh,
                  color: HkColors.appPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HydrationTipCard extends StatelessWidget {
  const _HydrationTipCard({
    required this.tip,
    required this.reducedMotion,
    required this.sizeScale,
    required this.compact,
    super.key,
  });

  final String tip;
  final bool reducedMotion;
  final double sizeScale;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _HydrationCard(
      radius: (compact ? 18 : 21) * sizeScale,
      child: Row(
        children: [
          SizedBox(width: (compact ? 14 : 24) * sizeScale),
          Container(
            width: (compact ? 38 : 50) * sizeScale,
            height: (compact ? 38 : 50) * sizeScale,
            decoration: BoxDecoration(
              color: Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFE9BD58).withValues(alpha: 0.92),
                width: (compact ? 1.4 : 1.8) * sizeScale,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE9BD58).withValues(alpha: 0.24),
                  blurRadius: (compact ? 10 : 14) * sizeScale,
                ),
              ],
            ),
            child: Icon(
              Symbols.lightbulb_rounded,
              color: const Color(0xFFE9BD58),
              size: (compact ? 21 : 28) * sizeScale,
            ),
          ),
          SizedBox(width: (compact ? 10 : 16) * sizeScale),
          Expanded(
            child: AnimatedSwitcher(
              duration: reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 360),
              child: Text(
                tip,
                key: ValueKey(tip),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: HkColors.appTextSecondary,
                  fontSize: (compact ? 15 : 17) * sizeScale,
                  height: 1.22,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          SizedBox(width: (compact ? 12 : 18) * sizeScale),
        ],
      ),
    );
  }
}

class _HydrationCard extends StatelessWidget {
  const _HydrationCard({required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: HkColors.appTextPrimary.withValues(alpha: 0.10),
            blurRadius: radius * 1.08,
            offset: Offset(0, radius * 0.36),
          ),
          BoxShadow(
            color: HkColors.appPrimary.withValues(alpha: 0.08),
            blurRadius: radius * 1.2,
            spreadRadius: -radius * 0.18,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: HkColors.appBorder.withValues(alpha: 0.88),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.surface.withValues(alpha: 0.98),
                  scheme.surface.withValues(alpha: 0.92),
                  scheme.surfaceContainerLow.withValues(alpha: 0.86),
                ],
                stops: const [0, 0.48, 1],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(child: child),
                Positioned(
                  left: radius * 0.8,
                  right: radius * 0.8,
                  top: 0,
                  height: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.surface.withValues(alpha: 0),
                          scheme.surface.withValues(alpha: 0.24),
                          scheme.surface.withValues(alpha: 0),
                        ],
                      ),
                    ),
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

class _HydrationBackdropPainter extends CustomPainter {
  _HydrationBackdropPainter({
    required this.animation,
    required this.progress,
    required this.parallax,
    required this.reducedMotion,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final double progress;
  final Offset parallax;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final phase = reducedMotion ? 0.28 : animation.value;
    final primaryGlowCenter = Offset(
      size.width * (0.18 + progress * 0.58) + parallax.dx * 24,
      size.height * 0.30 + parallax.dy * 20,
    );
    canvas.drawCircle(
      primaryGlowCenter,
      math.min(size.width, size.height) * 0.42,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                HkColors.appPrimary.withValues(alpha: 0.12),
                HkColors.appPrimaryMuted.withValues(alpha: 0.08),
                HkColors.appPrimary.withValues(alpha: 0),
              ],
              stops: const [0, 0.45, 1],
            ).createShader(
              Rect.fromCircle(
                center: primaryGlowCenter,
                radius: math.min(size.width, size.height) * 0.42,
              ),
            ),
    );

    final warmGlowCenter = Offset(size.width * 0.18, size.height * 0.86);
    canvas.drawCircle(
      warmGlowCenter,
      math.min(size.width, size.height) * 0.22,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFFE8BD58).withValues(alpha: 0.08),
                const Color(0xFFE8BD58).withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(
                center: warmGlowCenter,
                radius: math.min(size.width, size.height) * 0.22,
              ),
            ),
    );

    for (var index = 0; index < 28; index++) {
      final seed = index * 1.713;
      final x =
          ((math.sin(seed * 2.1) + 1) * 0.5 * size.width) +
          (parallax.dx * (12 + index));
      final travel = reducedMotion
          ? 0.0
          : ((phase * (18 + index * 1.6)) % (size.height + 80));
      final baseY = ((math.cos(seed) + 1) * 0.5 * size.height);
      final y = (baseY - travel + size.height + 40) % (size.height + 80) - 40;
      final radius = 1.2 + (index % 5) * 0.72;
      final pulse = reducedMotion
          ? 0.55
          : (0.45 + math.sin(phase * math.pi * 2 + seed) * 0.18);
      canvas.drawCircle(
        Offset(x, y + parallax.dy * (10 + index)),
        radius,
        Paint()
          ..color =
              (index.isEven ? const Color(0xFF58DD80) : const Color(0xFFE0C15D))
                  .withValues(alpha: (0.11 + progress * 0.08) * pulse),
      );
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.92,
          colors: [
            Colors.transparent,
            HkColors.appTextPrimary.withValues(alpha: 0.06),
          ],
          stops: const [0.56, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _HydrationBackdropPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.parallax != parallax ||
        oldDelegate.reducedMotion != reducedMotion;
  }
}
