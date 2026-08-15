part of '../../../../main.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  bool _backupLoadingIndicatorVisible = false;
  int _backupOperationId = 0;
  Timer? _backupLoadingTimer;
  bool _showBackupDetails = false;
  String _busyLabel = '';
  BackupState _state = const BackupState();
  BackupPreview? _restorePreview;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_loadBackupState);
  }

  @override
  Widget build(BuildContext context) {
    final last = _state.lastBackup;
    final backupRunning = _busy && _busyLabel == context.l10n.creatingBackup;
    final canShare =
        !_busy && last?.successful == true && (last?.path?.isNotEmpty ?? false);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.backupAndRestore)),
      body: hk_ui.ProductivityBackdrop(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  HkSpacing.gutter,
                  HkSpacing.xs,
                  HkSpacing.gutter,
                  96 + bottomPadding,
                ),
                children: [
                  const HkNativeAdCard(placement: 'backup'),
                  _BackupStatusPanel(
                    status: last,
                    description: _statusDescription(context, last),
                    showDetails: _showBackupDetails,
                    onToggleDetails: last?.path == null
                        ? null
                        : () => setState(
                            () => _showBackupDetails = !_showBackupDetails,
                          ),
                  ),
                  const SizedBox(height: HkSpacing.sm),
                  _BackupCreatePanel(
                    busy: backupRunning,
                    showLoadingIndicator: _backupLoadingIndicatorVisible,
                    automaticBackupsEnabled: _state.automaticBackupsEnabled,
                    canShare: canShare,
                    onCreate: _exportBackup,
                    onShare: _shareBackup,
                    onAutomaticChanged: _setAutomaticBackupsEnabled,
                  ),
                  const SizedBox(height: HkSpacing.sm),
                  _BackupRestorePanel(
                    busy: _busy,
                    preview: _restorePreview,
                    onChoose: _chooseRestoreBackup,
                    onRestore: _confirmRestore,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadBackupState() async {
    try {
      final state = await ref.read(backupRepositoryProvider).backupState();
      if (mounted) {
        setState(() => _state = state);
      }
    } catch (_) {
      // The screen can still create a fresh backup if local status is unreadable.
    }
  }

  Future<void> _exportBackup() async {
    if (_busy) {
      return;
    }
    final operationId = ++_backupOperationId;
    _setBusy(context.l10n.creatingBackup);
    _scheduleBackupLoadingIndicator(operationId);
    try {
      final path = await ref.read(backupRepositoryProvider).exportBackup();
      if (!mounted || operationId != _backupOperationId) {
        return;
      }
      _cancelBackupLoadingIndicator();
      await _loadBackupState();
      if (!mounted) {
        return;
      }
      hk_ui.showToast(
        context,
        content: Text(context.l10n.backupCreatedFilename(p.basename(path))),
      );
    } catch (error) {
      if (mounted && operationId == _backupOperationId) {
        _cancelBackupLoadingIndicator();
        AppLogger.warning('backup_export', error: error);
        hk_ui.showToast(
          context,
          content: Text(
            _failureMessage(context, error, fallback: AppFailureCode.backup),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted && operationId == _backupOperationId) {
        _cancelBackupLoadingIndicator();
        _clearBusy();
      }
    }
  }

  Future<void> _shareBackup() async {
    final path = _state.lastBackup?.path;
    if (path == null) {
      return;
    }
    if (!await File(path).exists()) {
      if (mounted) {
        hk_ui.showToast(
          context,
          content: Text(context.l10n.lastBackupFileMissing),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
      return;
    }
    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        text: context.l10n.owntendBackupShareText,
      ),
    );
  }

  Future<void> _setAutomaticBackupsEnabled(bool enabled) async {
    _setBusy(context.l10n.updatingBackupSettings);
    try {
      await ref
          .read(backupRepositoryProvider)
          .setAutomaticBackupsEnabled(enabled);
      await _loadBackupState();
    } catch (error) {
      if (mounted) {
        AppLogger.warning('backup_settings_update', error: error);
        hk_ui.showToast(
          context,
          content: Text(
            _failureMessage(context, error, fallback: AppFailureCode.backup),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        _clearBusy();
      }
    }
  }

  Future<void> _chooseRestoreBackup() async {
    final result = await FilePickerPlatform.instance.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = result.isNotEmpty ? result.first.path : null;
    if (path == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    _setBusy(context.l10n.checkingBackup);
    try {
      final preview = await ref
          .read(backupRepositoryProvider)
          .inspectBackup(path);
      if (!mounted) {
        return;
      }
      setState(() => _restorePreview = preview);
    } catch (error) {
      if (mounted) {
        AppLogger.warning('backup_inspection', error: error);
        hk_ui.showToast(
          context,
          content: Text(
            _failureMessage(context, error, fallback: AppFailureCode.backup),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        _clearBusy();
      }
    }
  }

  Future<void> _confirmRestore() async {
    final preview = _restorePreview;
    if (preview == null) {
      return;
    }
    final syncStatus = await ref.read(cloudSyncRepositoryProvider).status();
    if (!mounted) return;
    final choice = await showDialog<_RestoreCloudChoice>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const _BackupIconBadge(
          icon: Symbols.restore_rounded,
          color: HkColors.green,
          size: 58,
        ),
        title: Text(context.l10n.restoreThisBackup),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.restoreReplacesLocalData(
                  _formatDate(context, preview.createdAt),
                ),
              ),
              const SizedBox(height: HkSpacing.sm),
              _BackupDialogNotice(
                icon: Symbols.warning_rounded,
                color: HkColors.appDanger,
                text: context.l10n.restoreReplacementWarning,
              ),
              if (syncStatus.enabled) ...[
                const SizedBox(height: HkSpacing.sm),
                _BackupDialogNotice(
                  icon: Symbols.cloud_sync_rounded,
                  color: HkColors.green,
                  text: context.l10n.cloudRestoreSafetyNotice,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancel),
          ),
          if (syncStatus.enabled)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_RestoreCloudChoice.updateCloud),
              child: Text(context.l10n.restoreAndUpdateCloudBackup),
            ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_RestoreCloudChoice.localOnlyPause),
            child: Text(
              syncStatus.enabled
                  ? context.l10n.restoreLocallyAndPauseCloudBackup
                  : context.l10n.restoreBackup,
            ),
          ),
        ],
      ),
    );
    if (choice != null) {
      await _restoreSelectedBackup(preview, choice);
    }
  }

  Future<void> _restoreSelectedBackup(
    BackupPreview preview,
    _RestoreCloudChoice choice,
  ) async {
    _setBusy(context.l10n.restoringBackup);
    try {
      if (choice == _RestoreCloudChoice.updateCloud) {
        await ref.read(cloudSyncRepositoryProvider).syncNow();
      } else {
        await ref.read(cloudSyncRepositoryProvider).disable();
      }
      await ref.read(backupRepositoryProvider).restoreBackup(preview.path);
      final localStore = ref.read(localSyncStoreProvider);
      if (choice == _RestoreCloudChoice.localOnlyPause) {
        await localStore?.pauseAfterLocalRestore();
      } else {
        await localStore?.enqueueRestoreSnapshot(DateTime.now());
        await ref.read(cloudSyncRepositoryProvider).fullReconcile();
      }
      _reloadRestoredProviders();
      await ref.read(searchRepositoryProvider).rebuildIndex();
      if (ref.read(notificationAutoStartProvider)) {
        final scheduler = ref.read(notificationSchedulerProvider);
        await scheduler.initialize();
        await scheduler.refreshSchedules();
      }
      await _loadBackupState();
      if (!mounted) {
        return;
      }
      setState(() => _restorePreview = null);
      hk_ui.showToast(context, content: Text(context.l10n.backupRestored));
    } catch (error) {
      if (mounted) {
        AppLogger.warning('backup_restore', error: error);
        hk_ui.showToast(
          context,
          content: Text(
            _failureMessage(context, error, fallback: AppFailureCode.backup),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        _clearBusy();
      }
    }
  }

  void _reloadRestoredProviders() {
    ref.invalidate(databaseProvider);
    ref.invalidate(assetRepositoryProvider);
    ref.invalidate(maintenanceRepositoryProvider);
    ref.invalidate(calendarRepositoryProvider);
    ref.invalidate(streakServiceProvider);
    ref.invalidate(statisticsRepositoryProvider);
    ref.invalidate(settingsRepositoryProvider);
    ref.invalidate(notificationInboxRepositoryProvider);
    ref.invalidate(weatherRepositoryProvider);
    ref.invalidate(backupRepositoryProvider);
    ref.invalidate(searchRepositoryProvider);
    ref.invalidate(notificationSchedulerProvider);
    ref.invalidate(profileProvider);
    ref.invalidate(homeLocationProvider);
    ref.invalidate(weatherProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadNotificationsProvider);
    ref.invalidate(notificationPreferencesProvider);
    ref.invalidate(tasksProvider);
    ref.invalidate(areasProvider);
    ref.invalidate(roomsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(assetsProvider);
    ref.invalidate(dashboardProvider);
    ref.invalidate(statisticsProvider);
    ref.invalidate(streakRefreshProvider);
  }

  void _setBusy(String label) {
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
  }

  void _clearBusy() {
    setState(() {
      _busy = false;
      _busyLabel = '';
      _backupLoadingIndicatorVisible = false;
    });
  }

  void _scheduleBackupLoadingIndicator(int operationId) {
    _backupLoadingTimer?.cancel();
    _backupLoadingTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || operationId != _backupOperationId || !_busy) {
        return;
      }
      setState(() {
        _backupLoadingIndicatorVisible = true;
      });
    });
  }

  void _cancelBackupLoadingIndicator() {
    _backupLoadingTimer?.cancel();
    _backupLoadingTimer = null;
    if (_backupLoadingIndicatorVisible && mounted) {
      setState(() {
        _backupLoadingIndicatorVisible = false;
      });
    } else {
      _backupLoadingIndicatorVisible = false;
    }
  }

  @override
  void dispose() {
    _backupLoadingTimer?.cancel();
    super.dispose();
  }

  String _statusDescription(BuildContext context, BackupStatus? status) {
    if (status == null) {
      return context.l10n.noBackupCreatedOnThisDevice;
    }
    final when = status.createdAt ?? status.updatedAt;
    final action = switch (status.trigger) {
      BackupTrigger.manual => context.l10n.manualBackup,
      BackupTrigger.automatic => context.l10n.automaticBackup,
      BackupTrigger.preRestore => context.l10n.safetyBackup,
    };
    if (status.successful) {
      final date = _formatDate(context, when);
      return status.sizeBytes == null
          ? context.l10n.lastBackupAt(date)
          : context.l10n.lastBackupAtWithSize(
              date,
              _formatBytes(context, status.sizeBytes!),
            );
    }
    return context.l10n.backupFailedAt(
      action,
      _formatDate(context, status.updatedAt),
    );
  }
}

class _BackupStatusPanel extends StatelessWidget {
  const _BackupStatusPanel({
    required this.status,
    required this.description,
    required this.showDetails,
    required this.onToggleDetails,
  });

  final BackupStatus? status;
  final String description;
  final bool showDetails;
  final VoidCallback? onToggleDetails;

  @override
  Widget build(BuildContext context) {
    final color = _backupStatusColor(context, status);
    final path = status?.path;
    return hk_ui.PremiumCard(
      padding: const EdgeInsets.all(HkSpacing.md),
      borderRadius: HkRadii.xxl,
      backgroundColor: _backupTintedSurface(context, color, 0.035),
      borderColor: color.withValues(alpha: 0.16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BackupIconBadge(
                icon: _backupStatusIcon(status),
                color: color,
                size: 50,
              ),
              const SizedBox(width: HkSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status?.successful == true
                          ? context.l10n.latestBackup
                          : context.l10n.backupStatus,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: HkSpacing.space4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HkSpacing.sm),
              hk_ui.StatusPill(
                label: _backupStatusLabel(context, status),
                color: color,
                icon: _backupStatusPillIcon(status),
                compact: true,
              ),
            ],
          ),
          if (status?.message != null) ...[
            const SizedBox(height: HkSpacing.sm),
            _BackupInlineNote(
              icon: Symbols.info_rounded,
              color: color,
              text: status!.successful
                  ? context.l10n.backupComplete
                  : context.l10n.backupFailedPleaseTryAgain,
            ),
          ],
          if (path != null) ...[
            const SizedBox(height: HkSpacing.sm),
            TextButton.icon(
              onPressed: onToggleDetails,
              icon: const Icon(Symbols.folder_rounded),
              label: Text(
                showDetails
                    ? context.l10n.hideBackupDetails
                    : context.l10n.viewBackupDetails,
              ),
            ),
            if (showDetails)
              _BackupPathBox(
                path: path,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class _BackupCreatePanel extends StatelessWidget {
  const _BackupCreatePanel({
    required this.busy,
    required this.showLoadingIndicator,
    required this.automaticBackupsEnabled,
    required this.canShare,
    required this.onCreate,
    required this.onShare,
    required this.onAutomaticChanged,
  });

  final bool busy;
  final bool showLoadingIndicator;
  final bool automaticBackupsEnabled;
  final bool canShare;
  final VoidCallback onCreate;
  final VoidCallback onShare;
  final ValueChanged<bool> onAutomaticChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return hk_ui.PremiumCard(
      padding: const EdgeInsets.all(HkSpacing.md),
      borderRadius: HkRadii.xxl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BackupPanelHeader(
            icon: Symbols.backup_rounded,
            color: HkColors.green,
            title: context.l10n.createBackup,
            subtitle: context.l10n.backupsAreSavedLocallyAsPrivateZipFiles,
          ),
          const SizedBox(height: HkSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 520;
              final createButton = Semantics(
                button: true,
                enabled: !busy,
                liveRegion: false,
                child: FilledButton(
                  onPressed: busy ? null : onCreate,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: showLoadingIndicator
                        ? Row(
                            key: const ValueKey('backup-loading'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: RepaintBoundary(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: HkSpacing.xs),
                              Flexible(
                                child: Text(
                                  context.l10n.creatingBackup,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            key: const ValueKey('backup-idle'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Symbols.backup_rounded),
                              const SizedBox(width: HkSpacing.xs),
                              Text(
                                context.l10n.createBackup,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                  ),
                ),
              );
              final shareButton = OutlinedButton.icon(
                onPressed: canShare ? onShare : null,
                icon: const Icon(Symbols.ios_share_rounded),
                label: Text(context.l10n.shareLatestBackup),
              );
              if (wide) {
                return Row(
                  children: [
                    Expanded(child: createButton),
                    const SizedBox(width: HkSpacing.sm),
                    Expanded(child: shareButton),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  createButton,
                  const SizedBox(height: HkSpacing.xs),
                  shareButton,
                ],
              );
            },
          ),
          const SizedBox(height: HkSpacing.md),
          Container(
            padding: const EdgeInsets.all(HkSpacing.sm),
            decoration: BoxDecoration(
              color: _backupTintedSurface(context, HkColors.green, 0.045),
              borderRadius: BorderRadius.circular(HkRadii.lg),
              border: Border.all(color: HkColors.green.withValues(alpha: 0.14)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BackupIconBadge(
                  icon: Symbols.autorenew_rounded,
                  color: HkColors.green,
                  size: 42,
                ),
                const SizedBox(width: HkSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.automaticLocalBackups,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: HkSpacing.space4),
                      Text(
                        context.l10n.automaticBackupsDescription,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: HkSpacing.xs),
                Switch(
                  value: automaticBackupsEnabled,
                  onChanged: busy ? null : onAutomaticChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupRestorePanel extends StatelessWidget {
  const _BackupRestorePanel({
    required this.busy,
    required this.preview,
    required this.onChoose,
    required this.onRestore,
  });

  final bool busy;
  final BackupPreview? preview;
  final VoidCallback onChoose;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return hk_ui.PremiumCard(
      padding: const EdgeInsets.all(HkSpacing.md),
      borderRadius: HkRadii.xxl,
      backgroundColor: _backupTintedSurface(context, HkColors.green, 0.026),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BackupPanelHeader(
            icon: Symbols.restore_rounded,
            color: HkColors.green,
            title: context.l10n.restoreFromABackup,
            subtitle: context.l10n.restorePreviewDescription,
          ),
          const SizedBox(height: HkSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onChoose,
              icon: const Icon(Symbols.upload_file_rounded),
              label: Text(context.l10n.chooseBackupZip),
            ),
          ),
          if (preview != null) ...[
            const SizedBox(height: HkSpacing.md),
            _BackupPreviewPanel(
              preview: preview!,
              onRestore: busy ? null : onRestore,
            ),
          ],
        ],
      ),
    );
  }
}

class _BackupPanelHeader extends StatelessWidget {
  const _BackupPanelHeader({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BackupIconBadge(icon: icon, color: color, size: 48),
        const SizedBox(width: HkSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: HkSpacing.space4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BackupIconBadge extends StatelessWidget {
  const _BackupIconBadge({
    required this.icon,
    required this.color,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _backupTintedSurface(context, color, 0.12),
        borderRadius: BorderRadius.circular(size * 0.34),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

class _BackupInlineNote extends StatelessWidget {
  const _BackupInlineNote({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HkSpacing.xs),
      decoration: BoxDecoration(
        color: _backupTintedSurface(context, color, 0.07),
        borderRadius: BorderRadius.circular(HkRadii.md),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: HkSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupPathBox extends StatelessWidget {
  const _BackupPathBox({required this.path, required this.color});

  final String path;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(HkSpacing.xs),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(HkRadii.md),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: SelectableText(path, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _BackupDialogNotice extends StatelessWidget {
  const _BackupDialogNotice({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return _BackupInlineNote(icon: icon, color: color, text: text);
  }
}

class _BackupPreviewPanel extends StatelessWidget {
  const _BackupPreviewPanel({required this.preview, required this.onRestore});

  final BackupPreview preview;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(HkSpacing.md),
      decoration: BoxDecoration(
        color: _backupTintedSurface(context, HkColors.green, 0.05),
        borderRadius: BorderRadius.circular(HkRadii.xl),
        border: Border.all(color: HkColors.green.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _BackupIconBadge(
                icon: Symbols.inventory_2_rounded,
                color: HkColors.green,
                size: 44,
              ),
              const SizedBox(width: HkSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.backupFromDate(
                        _formatDate(context, preview.createdAt),
                      ),
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: HkSpacing.space4),
                    Text(
                      context.l10n.backupFormatSummary(
                        preview.formatVersion,
                        preview.schemaVersion,
                        _formatBytes(context, preview.backupSizeBytes),
                      ),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: HkSpacing.md),
          Wrap(
            spacing: HkSpacing.xs,
            runSpacing: HkSpacing.xs,
            children: [
              _BackupMetric(
                label: context.l10n.tasks,
                value: preview.taskCount,
              ),
              _BackupMetric(
                label: context.l10n.items,
                value: preview.thingCount,
              ),
              _BackupMetric(
                label: context.l10n.history,
                value: preview.historyCount,
              ),
              _BackupMetric(
                label: context.l10n.files,
                value: preview.fileCount,
              ),
              _BackupMetric(
                label: context.l10n.notifications,
                value: preview.notificationCount,
              ),
            ],
          ),
          const SizedBox(height: HkSpacing.sm),
          _BackupInlineNote(
            icon: Symbols.check_circle_rounded,
            color: HkColors.green,
            text: context.l10n.backupWillRestore(
              preview.includedData
                  .map((value) => _localizedBackupDetail(context, value))
                  .join(', '),
            ),
          ),
          const SizedBox(height: HkSpacing.xs),
          _BackupInlineNote(
            icon: Symbols.remove_circle_rounded,
            color: scheme.onSurfaceVariant,
            text: context.l10n.backupNotIncluded(
              preview.excludedData
                  .map((value) => _localizedBackupDetail(context, value))
                  .join(', '),
            ),
          ),
          if (preview.warnings.isNotEmpty) ...[
            const SizedBox(height: HkSpacing.sm),
            for (final warning in preview.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: HkSpacing.space4),
                child: _BackupInlineNote(
                  icon: Symbols.warning_rounded,
                  color: HkColors.appWarning,
                  text: _localizedBackupWarning(context, warning),
                ),
              ),
          ],
          const SizedBox(height: HkSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onRestore,
              icon: const Icon(Symbols.restore_rounded),
              label: Text(context.l10n.restoreThisBackup2),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupMetric extends StatelessWidget {
  const _BackupMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HkSpacing.xs,
        vertical: HkSpacing.space6,
      ),
      decoration: BoxDecoration(
        color: _backupTintedSurface(context, HkColors.green, 0.08),
        borderRadius: BorderRadius.circular(HkRadii.full),
        border: Border.all(color: HkColors.green.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Symbols.check_circle_rounded,
            size: 16,
            color: HkColors.green,
          ),
          const SizedBox(width: HkSpacing.space4),
          Text(
            '$label $value',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: HkColors.green, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

String _backupStatusLabel(BuildContext context, BackupStatus? status) {
  if (status == null) {
    return context.l10n.noBackup;
  }
  return status.successful ? context.l10n.available : context.l10n.failed;
}

IconData _backupStatusIcon(BackupStatus? status) {
  if (status == null) {
    return Symbols.history_rounded;
  }
  return status.successful
      ? Symbols.verified_user_rounded
      : Symbols.error_rounded;
}

IconData _backupStatusPillIcon(BackupStatus? status) {
  if (status == null) {
    return Symbols.history_rounded;
  }
  return status.successful
      ? Symbols.check_circle_rounded
      : Symbols.error_rounded;
}

Color _backupStatusColor(BuildContext context, BackupStatus? status) {
  if (status == null) {
    return Theme.of(context).colorScheme.outline;
  }
  return status.successful
      ? HkColors.green
      : Theme.of(context).colorScheme.error;
}

Color _backupTintedSurface(BuildContext context, Color tint, double alpha) {
  final scheme = Theme.of(context).colorScheme;
  return Color.alphaBlend(
    tint.withValues(alpha: alpha),
    scheme.surfaceContainerLowest,
  );
}

String _formatDate(BuildContext context, DateTime value) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMMMd(locale).add_jm().format(value.toLocal());
}

String _formatBytes(BuildContext context, int bytes) {
  final number = NumberFormat.decimalPattern(
    Localizations.localeOf(context).toLanguageTag(),
  );
  if (bytes < 1024) {
    return '${number.format(bytes)} B';
  }
  if (bytes < 1024 * 1024) {
    return '${number.format(bytes / 1024)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${number.format(bytes / (1024 * 1024))} MB';
  }
  return '${number.format(bytes / (1024 * 1024 * 1024))} GB';
}

String _localizedBackupDetail(BuildContext context, String value) {
  return switch (value) {
    'Tasks and due dates' => context.l10n.backupIncludedTasks,
    'Items, rooms, areas, categories, tags, and photos' =>
      context.l10n.backupIncludedItems,
    'Task history, timeline, streaks, and statistics source data' =>
      context.l10n.backupIncludedHistory,
    'Notification preferences, inbox history, and snooze defaults' =>
      context.l10n.backupIncludedNotifications,
    'Theme, profile, weather location, and app settings' =>
      context.l10n.backupIncludedSettings,
    'Android scheduled alarm handles are recreated from restored tasks and settings' =>
      context.l10n.backupExcludedAlarms,
    _ => context.l10n.backupGenericWarning,
  };
}

String _localizedBackupWarning(BuildContext context, String value) {
  return switch (value) {
    'This is an older backup format. Owntend will migrate it during restore.' =>
      context.l10n.backupOlderFormatWarning,
    'Profile settings could not be previewed.' =>
      context.l10n.backupProfilePreviewWarning,
    _ => context.l10n.backupGenericWarning,
  };
}

Future<void> addPhotoToAsset(
  BuildContext context,
  WidgetRef ref,
  Asset asset,
) async {
  final image = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 82,
    maxWidth: 1800,
  );
  if (image == null) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  try {
    await ref.read(assetRepositoryProvider).addPhoto(asset.id, image.path);
    if (!context.mounted) {
      return;
    }
    hk_ui.showToast(context, content: Text(context.l10n.photoSaved));
  } catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          _failureMessage(context, error, fallback: AppFailureCode.photoSave),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
  }
}

enum _SnoozePreset { thirtyMinutes, oneHour, threeHours, tomorrow, custom }

Future<void> snoozeTaskWithFeedback(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  if (!task.plan.isEnabled) {
    hk_ui.showToast(
      context,
      content: Text(context.l10n.enableThisTaskBeforeSnoozingIt),
      severity: hk_ui.HkToastSeverity.error,
    );
    return;
  }
  final preferences =
      ref.read(notificationPreferencesProvider).value ??
      await ref.read(settingsRepositoryProvider).notificationPreferences();
  if (!context.mounted) {
    return;
  }
  final preset = await runWithNativeAdsSuspended(
    context,
    () => showModalBottomSheet<_SnoozePreset>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.snooze_rounded),
              title: Text(context.l10n.snoozeTask(task.plan.title)),
              subtitle: Text(context.l10n.snoozeReminderDescription),
            ),
            ListTile(
              leading: const Icon(Symbols.timer_rounded),
              title: Text(context.l10n.message30Minutes),
              onTap: () =>
                  Navigator.of(context).pop(_SnoozePreset.thirtyMinutes),
            ),
            ListTile(
              leading: const Icon(Symbols.schedule_rounded),
              title: Text(context.l10n.message1Hour),
              onTap: () => Navigator.of(context).pop(_SnoozePreset.oneHour),
            ),
            ListTile(
              leading: const Icon(Symbols.more_time_rounded),
              title: Text(context.l10n.message3Hours),
              onTap: () => Navigator.of(context).pop(_SnoozePreset.threeHours),
            ),
            ListTile(
              leading: const Icon(Symbols.today_rounded),
              title: Text(
                context.l10n.tomorrowAtTime(
                  _hourLabel(context, preferences.reminderHour),
                ),
              ),
              onTap: () => Navigator.of(context).pop(_SnoozePreset.tomorrow),
            ),
            ListTile(
              leading: const Icon(Symbols.edit_calendar_rounded),
              title: Text(context.l10n.customDateAndTime),
              onTap: () => Navigator.of(context).pop(_SnoozePreset.custom),
            ),
          ],
        ),
      ),
    ),
  );
  if (preset == null || !context.mounted) {
    return;
  }
  final duration = await _durationForSnoozePreset(context, preset, preferences);
  if (duration == null || !context.mounted) {
    return;
  }
  await ref
      .read(notificationSchedulerProvider)
      .snoozePlan(task.plan.id, duration);
  if (!context.mounted) {
    return;
  }
  hk_ui.showToast(
    context,
    content: Text(
      context.l10n.taskSnoozedForDuration(
        task.plan.title,
        _durationLabel(context, duration),
      ),
    ),
  );
}

Future<bool> skipTaskWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  final reason = await _taskReasonDialog(
    context,
    title: context.l10n.skipThisOccurrence2,
    message: context.l10n.skipCurrentCycleMessage,
    actionLabel: context.l10n.skipOccurrence,
    icon: Symbols.skip_next_rounded,
  );
  if (reason == null || !context.mounted) {
    return false;
  }
  try {
    await ref
        .read(maintenanceRepositoryProvider)
        .skipPlanOccurrence(task.plan.id, reason: reason);
    await cancelPlanReminderSchedules(ref, [task.plan.id]);
    await refreshNotificationSchedules(ref);
    if (!context.mounted) {
      return true;
    }
    hk_ui.showToast(
      context,
      content: Text(context.l10n.taskSkippedForThisCycle(task.plan.title)),
    );
    return true;
  } catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          _failureMessage(context, error, fallback: AppFailureCode.taskUpdate),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
    return false;
  }
}

Future<bool> postponeTaskWithDialog(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  final date = await showDatePicker(
    context: context,
    initialDate: task.plan.nextDueDate,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 3650)),
  );
  if (date == null || !context.mounted) {
    return false;
  }
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(task.plan.nextDueDate),
  );
  if (time == null || !context.mounted) {
    return false;
  }
  final nextDueDate = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  final reason = await _taskReasonDialog(
    context,
    title: context.l10n.postponeTask,
    message: context.l10n.postponeCurrentCycleMessage,
    actionLabel: context.l10n.postpone,
    icon: Symbols.edit_calendar_rounded,
  );
  if (reason == null || !context.mounted) {
    return false;
  }
  try {
    await ref
        .read(maintenanceRepositoryProvider)
        .postponePlan(task.plan.id, nextDueDate, reason: reason);
    await cancelPlanReminderSchedules(ref, [task.plan.id]);
    await refreshNotificationSchedules(ref);
    if (!context.mounted) {
      return true;
    }
    hk_ui.showToast(
      context,
      content: Text(
        context.l10n.taskPostponedUntil(
          task.plan.title,
          DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
              .add_jm()
              .format(nextDueDate),
        ),
      ),
    );
    return true;
  } catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          _failureMessage(context, error, fallback: AppFailureCode.taskUpdate),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
    return false;
  }
}

Future<String?> _taskReasonDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  required IconData icon,
}) async {
  final controller = TextEditingController();
  try {
    return await runWithNativeAdsSuspended(
      context,
      () => showDialog<String?>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(icon),
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              const SizedBox(height: HkSpacing.sm),
              TextField(
                controller: controller,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: context.l10n.reason,
                  hintText: context.l10n.optional,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<Duration?> _durationForSnoozePreset(
  BuildContext context,
  _SnoozePreset preset,
  NotificationPreferences preferences,
) async {
  final now = DateTime.now();
  switch (preset) {
    case _SnoozePreset.thirtyMinutes:
      return const Duration(minutes: 30);
    case _SnoozePreset.oneHour:
      return const Duration(hours: 1);
    case _SnoozePreset.threeHours:
      return const Duration(hours: 3);
    case _SnoozePreset.tomorrow:
      return DateTime(
        now.year,
        now.month,
        now.day + 1,
        preferences.reminderHour,
      ).difference(now);
    case _SnoozePreset.custom:
      final date = await showDatePicker(
        context: context,
        initialDate: now.add(const Duration(hours: 1)),
        firstDate: now,
        lastDate: now.add(const Duration(days: 30)),
      );
      if (date == null || !context.mounted) {
        return null;
      }
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      );
      if (time == null) {
        return null;
      }
      final scheduled = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      return scheduled.isAfter(now)
          ? scheduled.difference(now)
          : const Duration(minutes: 5);
  }
}

String _durationLabel(BuildContext context, Duration duration) {
  if (duration.inMinutes < 60) {
    return context.l10n.durationMinutesShort(duration.inMinutes);
  }
  if (duration.inHours < 24) {
    final minutes = duration.inMinutes.remainder(60);
    return minutes == 0
        ? context.l10n.durationHoursMinutesShort(duration.inHours, 0)
        : context.l10n.durationHoursMinutesShort(duration.inHours, minutes);
  }
  return duration.inDays == 1
      ? context.l10n.durationDay(duration.inDays)
      : context.l10n.durationDays(duration.inDays);
}

Future<void> refreshNotificationSchedules(WidgetRef ref) async {
  try {
    await ref.read(notificationSchedulerProvider).refreshSchedules();
  } catch (_) {
    // Reminder refresh should not block the primary task action.
  }
}

Future<void> cancelPlanReminderSchedules(
  WidgetRef ref,
  Iterable<String> planIds,
) async {
  final uniqueIds = planIds.toSet();
  if (uniqueIds.isEmpty) {
    return;
  }
  try {
    final scheduler = ref.read(notificationSchedulerProvider);
    for (final planId in uniqueIds) {
      await scheduler.cancelPlanReminders(planId);
    }
  } catch (_) {
    // Stale OS notifications are undesirable, but should not block data changes.
  }
}

Future<bool> setTaskEnabledWithFeedback(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
  bool enabled,
) async {
  try {
    await ref
        .read(maintenanceRepositoryProvider)
        .setTaskEnabled(task.plan.id, enabled);
  } catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          enabled
              ? _failureMessage(
                  context,
                  error,
                  fallback: AppFailureCode.taskUpdate,
                )
              : _failureMessage(
                  context,
                  error,
                  fallback: AppFailureCode.taskUpdate,
                ),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
    return false;
  }

  Object? reminderError;
  try {
    final scheduler = ref.read(notificationSchedulerProvider);
    if (!enabled) {
      await scheduler.cancelPlanReminders(task.plan.id);
    }
    await scheduler.refreshSchedules();
  } catch (error) {
    reminderError = error;
  }

  if (!context.mounted) {
    return true;
  }
  if (reminderError != null) {
    hk_ui.showToast(
      context,
      content: Text(
        _failureMessage(
          context,
          reminderError,
          fallback: AppFailureCode.notificationSetup,
        ),
      ),
      severity: hk_ui.HkToastSeverity.error,
    );
    return true;
  }
  hk_ui.showToast(
    context,
    content: Text(
      enabled
          ? context.l10n.taskEnabledConfirmation
          : context.l10n.taskDisabledConfirmation,
    ),
  );
  return true;
}

enum _TaskActionFeedbackType { created, completed, deleted }

void _showTaskActionFeedback(
  BuildContext context,
  _TaskActionFeedbackType type, {
  String? label,
}) {
  unawaited(_playTaskActionFeedback(type));
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    return;
  }
  var removed = false;
  late final OverlayEntry entry;
  void removeEntry() {
    if (removed) {
      return;
    }
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) => _TaskActionBurstOverlay(
      type: type,
      label: label ?? _taskActionFeedbackLabel(context, type),
      onDone: removeEntry,
    ),
  );
  overlay.insert(entry);
}

Future<void> _playTaskActionFeedback(_TaskActionFeedbackType type) async {
  switch (type) {
    case _TaskActionFeedbackType.completed:
      await hkActionFeedbackService.playCompleted();
    case _TaskActionFeedbackType.created:
      await hkActionFeedbackService.playCreated();
    case _TaskActionFeedbackType.deleted:
      await hkActionFeedbackService.playDeleted();
  }
}

String _taskActionFeedbackLabel(
  BuildContext context,
  _TaskActionFeedbackType type,
) {
  return switch (type) {
    _TaskActionFeedbackType.created => context.l10n.taskAdded,
    _TaskActionFeedbackType.completed => context.l10n.taskDone,
    _TaskActionFeedbackType.deleted => context.l10n.taskDeleted,
  };
}

class _TaskActionBurstOverlay extends StatefulWidget {
  const _TaskActionBurstOverlay({
    required this.type,
    required this.label,
    required this.onDone,
  });

  final _TaskActionFeedbackType type;
  final String label;
  final VoidCallback onDone;

  @override
  State<_TaskActionBurstOverlay> createState() =>
      _TaskActionBurstOverlayState();
}

class _TaskActionBurstOverlayState extends State<_TaskActionBurstOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1180),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            widget.onDone();
          }
        });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _TaskActionFeedbackStyle.from(context, widget.type);
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final progress = _controller.value;
            final intro = Curves.easeOutBack.transform(
              (progress / 0.36).clamp(0.0, 1.0),
            );
            final fadeOut = progress < 0.76
                ? 1.0
                : (1 - ((progress - 0.76) / 0.24)).clamp(0.0, 1.0);
            final slide = Curves.easeOutCubic.transform(
              progress.clamp(0.0, 1.0),
            );
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TaskActionBurstPainter(
                      progress: progress,
                      accent: style.accent,
                      secondary: style.secondary,
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Transform.translate(
                      offset: Offset(0, 50 - (18 * slide)),
                      child: Opacity(
                        opacity: fadeOut,
                        child: Transform.scale(
                          scale: 0.82 + (0.18 * intro),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color.alphaBlend(
                                style.accent.withValues(alpha: 0.07),
                                scheme.surfaceContainerLowest,
                              ).withValues(alpha: 0.96),
                              borderRadius: BorderRadius.circular(HkRadii.full),
                              border: Border.all(
                                color: style.accent.withValues(alpha: 0.24),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: style.accent.withValues(alpha: 0.22),
                                  blurRadius: 30,
                                  offset: const Offset(0, 12),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: HkSpacing.md,
                                vertical: HkSpacing.sm,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: style.accent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      style.icon,
                                      color: style.onAccent,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: HkSpacing.xs),
                                  Text(
                                    widget.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: scheme.onSurface,
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TaskActionFeedbackStyle {
  const _TaskActionFeedbackStyle({
    required this.icon,
    required this.accent,
    required this.secondary,
    required this.onAccent,
  });

  final IconData icon;
  final Color accent;
  final Color secondary;
  final Color onAccent;

  factory _TaskActionFeedbackStyle.from(
    BuildContext context,
    _TaskActionFeedbackType type,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return switch (type) {
      _TaskActionFeedbackType.created => _TaskActionFeedbackStyle(
        icon: Symbols.add_task_rounded,
        accent: scheme.primary,
        secondary: HkColors.appInfo,
        onAccent: scheme.onPrimary,
      ),
      _TaskActionFeedbackType.completed => _TaskActionFeedbackStyle(
        icon: Symbols.check_circle_rounded,
        accent: HkColors.green,
        secondary: scheme.primary,
        onAccent: Colors.white,
      ),
      _TaskActionFeedbackType.deleted => _TaskActionFeedbackStyle(
        icon: Symbols.delete_rounded,
        accent: scheme.error,
        secondary: HkColors.appWarning,
        onAccent: scheme.onError,
      ),
    };
  }
}

class _TaskActionBurstPainter extends CustomPainter {
  const _TaskActionBurstPainter({
    required this.progress,
    required this.accent,
    required this.secondary,
  });

  final double progress;
  final Color accent;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 92);
    final outward = Curves.easeOutCubic.transform(
      (progress / 0.72).clamp(0.0, 1.0),
    );
    final fade = progress < 0.72
        ? 1.0
        : (1 - ((progress - 0.72) / 0.28)).clamp(0.0, 1.0);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var index = 0; index < 18; index += 1) {
      final angle = (-math.pi * 0.88) + (index * math.pi * 1.76 / 17);
      final stagger = 0.76 + ((index % 4) * 0.08);
      final radius = (18 + (72 * outward)) * stagger;
      final particleCenter =
          center + Offset(math.cos(angle), math.sin(angle)) * radius;
      final particleSize = 3.5 + ((index % 3) * 1.8);
      paint.color = (index.isEven ? accent : secondary).withValues(
        alpha: (0.78 * fade).clamp(0.0, 1.0),
      );
      if (index % 5 == 0) {
        canvas.save();
        canvas.translate(particleCenter.dx, particleCenter.dy);
        canvas.rotate(angle + (progress * math.pi));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: particleSize * 2.2,
              height: particleSize,
            ),
            Radius.circular(particleSize / 2),
          ),
          paint,
        );
        canvas.restore();
      } else {
        canvas.drawCircle(particleCenter, particleSize, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TaskActionBurstPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        accent != oldDelegate.accent ||
        secondary != oldDelegate.secondary;
  }
}

Future<List<String>> _planIdsForAssets(
  WidgetRef ref,
  Iterable<String> assetIds,
) async {
  final maintenance = ref.read(maintenanceRepositoryProvider);
  final planIds = <String>{};
  for (final assetId in assetIds.toSet()) {
    final tasks = await maintenance.listTasksForAsset(assetId);
    planIds.addAll(tasks.map((task) => task.plan.id));
  }
  return planIds.toList();
}

Future<bool> completeTaskWithFeedback(
  BuildContext context,
  WidgetRef ref,
  TaskItem task, {
  bool collectNotes = false,
}) async {
  final controllerNotifier = ref.read(
    taskCompletionControllerProvider(task.plan.id),
  );
  if (collectNotes) {
    if (!controllerNotifier.tryBeginNotesCollection()) {
      return false;
    }
  }

  final dueTodayBefore = getTaskBuckets(
    ref.read(tasksProvider).value ?? const <TaskItem>[],
    DateTime.now(),
  ).today;
  final completesFinalDueToday =
      dueTodayBefore.length == 1 &&
      dueTodayBefore.single.plan.id == task.plan.id;
  String? notes;
  if (collectNotes) {
    notes = await _showEditorModal<String>(
      context,
      builder: (context) => CompleteTaskDialog(task: task),
    );
    if (notes == null) {
      controllerNotifier.cancelNotesCollection();
      return false;
    }
    if (!context.mounted) {
      return false;
    }
  }
  final previousDueDate = task.plan.nextDueDate;
  final result = await controllerNotifier.complete(
    completedAt: DateTime.now(),
    notes: notes,
    expectedNextDueDate: previousDueDate,
  );

  if (!context.mounted) {
    return result.isApplied;
  }
  if (!result.isApplied) {
    hk_ui.showToast(
      context,
      content: Text(context.l10n.thisTaskWasAlreadyUpdated),
      severity: hk_ui.HkToastSeverity.error,
    );
    return false;
  }
  try {
    await ref.read(streakServiceProvider).refresh(DateTime.now());
  } catch (_) {}
  if (!context.mounted) {
    return true;
  }
  _showTaskActionFeedback(context, _TaskActionFeedbackType.completed);
  if (!_prefersReducedMotion(context)) {
    await Future<void>.delayed(const Duration(milliseconds: 450));
  }
  if (!context.mounted) {
    return true;
  }
  hk_ui.showUndoToast(
    context,
    content: Text(context.l10n.taskCompleted),
    onUndo: () async {
      try {
        await ref
            .read(maintenanceRepositoryProvider)
            .undoLastCompletion(task.plan.id, previousDueDate);
        try {
          await ref.read(streakServiceProvider).refresh(DateTime.now());
          await refreshNotificationSchedules(ref);
        } catch (_) {}
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(context.l10n.completionUndone),
          );
        }
      } catch (error) {
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(
              _failureMessage(context, error, fallback: AppFailureCode.undo),
            ),
            severity: hk_ui.HkToastSeverity.error,
          );
        }
      }
    },
  );
  if (completesFinalDueToday) {
    try {
      await _offerDailyCompletionReward(context, ref);
    } catch (_) {}
  } else if (context.mounted) {
    final config =
        ref.read(monetizationConfigProvider).value ??
        const MonetizationConfig.failClosed();
    await ref
        .read(completionAdCoordinatorProvider)
        .onTaskCompleted(
          config: config,
          keyboardVisible: MediaQuery.viewInsetsOf(context).bottom > 0,
          modalActive: false,
        );
  }
  return true;
}

Future<void> _offerDailyCompletionReward(
  BuildContext context,
  WidgetRef ref,
) async {
  final config =
      ref.read(monetizationConfigProvider).value ??
      const MonetizationConfig.failClosed();
  final wallet = ref.read(pointWalletProvider).value;
  if (!config.adsEnabled ||
      !config.rewardedInterstitialEnabled ||
      (wallet?.balance ?? config.walletCap) + 2 > config.walletCap) {
    return;
  }
  final accepted = await runWithNativeAdsSuspended(
    context,
    () => showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              HkSpacing.gutter,
              0,
              HkSpacing.gutter,
              HkSpacing.gutter,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Symbols.celebration_rounded, size: 44),
                const SizedBox(height: HkSpacing.sm),
                Text(
                  context.l10n.todayCareComplete,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: HkSpacing.xs),
                Text(
                  context.l10n.optionalDailyRewardDescription,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: HkSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(context.l10n.notNow),
                        ),
                      ),
                    ),
                    const SizedBox(width: HkSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Symbols.play_circle_rounded),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(context.l10n.earnTwoPoints),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  if (accepted != true || !context.mounted) return;
  final result = await ref
      .read(owntendAdsProvider)
      .showReward(
        RewardAdType.rewardedInterstitial,
        timeZone: wallet?.timeZone,
        entryPoint: 'today_complete_milestone',
      );
  if (!context.mounted) return;
  final message = switch (result) {
    RewardShowResult.shownAwaitingServerVerification =>
      context.l10n.rewardWatchedVerifyingTwo,
    RewardShowResult.unavailable => context.l10n.noRewardAvailable,
    RewardShowResult.rejected => context.l10n.dailyRewardAlreadyClaimed,
    RewardShowResult.dismissed => context.l10n.rewardAdClosedEarly,
  };
  hk_ui.showToast(context, content: Text(message));
}

Future<void> showPointsWalletSheet(BuildContext context, WidgetRef ref) async {
  final repository = ref.read(monetizationRepositoryProvider);
  final transactions = repository?.listTransactions();
  await runWithNativeAdsSuspended(
    context,
    () => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final wallet = ref.watch(pointWalletProvider).value;
          final config =
              ref.watch(monetizationConfigProvider).value ??
              const MonetizationConfig.failClosed();
          final pendingClaims =
              ref.watch(pendingRewardClaimsProvider).value ?? const [];
          final sheetHeight = math.max(
            320.0,
            MediaQuery.sizeOf(context).height * 0.82,
          );
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 640,
                maxHeight: sheetHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  HkSpacing.gutter,
                  0,
                  HkSpacing.gutter,
                  HkSpacing.gutter,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Symbols.stars_rounded, size: 30),
                        const SizedBox(width: HkSpacing.sm),
                        Expanded(
                          child: Text(
                            context.l10n.pointsWallet,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        Text(
                          '${wallet?.balance ?? 0} / ${config.walletCap}',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: HkSpacing.sm),
                    if (pendingClaims.isNotEmpty) ...[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer
                              .withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(HkRadii.md),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(HkSpacing.sm),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: HkSpacing.sm),
                              Expanded(
                                child: Text(
                                  context.l10n.rewardVerificationPending,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: HkSpacing.sm),
                    ],
                    FilledButton.icon(
                      onPressed:
                          (wallet?.balance ?? config.walletCap) >=
                              config.walletCap
                          ? null
                          : () async {
                              await showEarnPointsFlow(
                                context,
                                ref,
                                entryPoint: 'wallet',
                              );
                            },
                      icon: const Icon(Symbols.play_circle_rounded),
                      label: Text(context.l10n.earnFreePoints),
                    ),
                    const SizedBox(height: HkSpacing.sm),
                    Text(
                      context.l10n.pointsRuleExplanation,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: HkSpacing.md),
                    Text(
                      context.l10n.recentActivity,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: HkSpacing.xs),
                    Expanded(
                      child: transactions == null
                          ? Center(
                              child: Text(context.l10n.activityUnavailable),
                            )
                          : FutureBuilder<List<Map<String, dynamic>>>(
                              future: transactions,
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                final rows = snapshot.data!;
                                if (rows.isEmpty) {
                                  return Center(
                                    child: Text(context.l10n.noPointActivity),
                                  );
                                }
                                return ListView.builder(
                                  itemCount: rows.length,
                                  itemBuilder: (context, index) {
                                    final row = rows[index];
                                    final amount = row['amount'] as int? ?? 0;
                                    final created = DateTime.tryParse(
                                      row['created_at'] as String? ?? '',
                                    )?.toLocal();
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: CircleAvatar(
                                        child: Icon(
                                          amount > 0
                                              ? Symbols.add_rounded
                                              : Symbols.remove_rounded,
                                        ),
                                      ),
                                      title: Text(
                                        _pointTransactionLabel(
                                          context,
                                          row['transaction_type'] as String? ??
                                              '',
                                        ),
                                      ),
                                      subtitle: created == null
                                          ? null
                                          : Text(
                                              DateFormat.yMMMd()
                                                  .add_jm()
                                                  .format(created),
                                            ),
                                      trailing: Text(
                                        '${amount > 0 ? '+' : ''}$amount',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: amount > 0
                                                  ? HkColors.green
                                                  : Theme.of(context)
                                                        .colorScheme
                                                        .error,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

String _pointTransactionLabel(BuildContext context, String type) =>
    switch (type) {
      'initial_grant' => context.l10n.startingPoints,
      'task_creation' => context.l10n.taskCreatedPointTransaction,
      'asset_creation' => context.l10n.itemCreatedPointTransaction,
      'rewarded_ad' => context.l10n.rewardedAdPointTransaction,
      'rewarded_interstitial' => context.l10n.dailyCompletionReward,
      'refund' => context.l10n.refundPointTransaction,
      _ => context.l10n.pointAdjustment,
    };

Future<void> showEarnPointsFlow(
  BuildContext context,
  WidgetRef ref, {
  required String entryPoint,
}) => runWithNativeAdsSuspended(
  context,
  () => _showEarnPointsFlow(context, ref, entryPoint: entryPoint),
);

Future<void> _showEarnPointsFlow(
  BuildContext context,
  WidgetRef ref, {
  required String entryPoint,
}) async {
  final config =
      ref.read(monetizationConfigProvider).value ??
      const MonetizationConfig.failClosed();
  final wallet = ref.read(pointWalletProvider).value;
  if (!config.adsEnabled || !config.rewardedAdsEnabled) {
    hk_ui.showToast(
      context,
      content: Text(context.l10n.pointRewardsUnavailable),
    );
    return;
  }
  if ((wallet?.balance ?? config.walletCap) >= config.walletCap) {
    hk_ui.showToast(context, content: Text(context.l10n.walletAlreadyFull));
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.earnOnePoint),
      content: Text(context.l10n.earnOnePointDescription),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Symbols.play_circle_rounded),
          label: Text(context.l10n.watchAd),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  hk_ui.showToast(context, content: Text(context.l10n.loadingRewardedAd));
  final result = await ref
      .read(owntendAdsProvider)
      .showReward(
        RewardAdType.rewardedAd,
        timeZone: wallet?.timeZone,
        entryPoint: entryPoint,
      );
  if (!context.mounted) return;
  switch (result) {
    case RewardShowResult.shownAwaitingServerVerification:
      hk_ui.showToast(
        context,
        content: Text(context.l10n.adWatchedVerifyingPoint),
      );
    case RewardShowResult.unavailable:
      hk_ui.showToast(
        context,
        content: Text(context.l10n.noRewardedAdAvailable),
      );
    case RewardShowResult.rejected:
      hk_ui.showToast(
        context,
        content: Text(context.l10n.rewardUnavailableOrClaimed),
      );
    case RewardShowResult.dismissed:
      hk_ui.showToast(context, content: Text(context.l10n.rewardAdClosedEarly));
  }
}

Future<void> showPointShortageDialog(
  BuildContext context,
  WidgetRef ref, {
  required String attemptedAction,
}) async {
  unawaited(
    ref.read(monetizationRepositoryProvider)?.recordEvent(
      'point_shortage_encountered',
      {'attempted_action': attemptedAction},
    ),
  );
  await runWithNativeAdsSuspended(
    context,
    () => showDialog<void>(
      context: context,
      builder: (context) => const _PointShortageDialog(),
    ),
  );
}
