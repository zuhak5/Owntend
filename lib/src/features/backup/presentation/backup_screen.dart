import 'package:path/path.dart' as p;

import '../../monetization/monetization.dart';
import '../../../ui/components.dart' as hk_ui;
import '../../../ui/presentation_support.dart';

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
  String? _restorePassphrase;

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

  /// Returns null when cancelled, an empty string for a device-protected
  /// backup, or the chosen passphrase.
  Future<String?> _promptForExportPassphrase() => showDialog<String>(
    context: context,
    builder: (_) => const _ExportPassphraseDialog(),
  );

  Future<void> _exportBackup() async {
    if (_busy) {
      return;
    }
    final passphraseChoice = await _promptForExportPassphrase();
    if (!mounted || passphraseChoice == null) {
      return;
    }
    final passphrase = passphraseChoice.isEmpty ? null : passphraseChoice;
    final operationId = ++_backupOperationId;
    _setBusy(context.l10n.creatingBackup);
    _scheduleBackupLoadingIndicator(operationId);
    try {
      final path = await ref
          .read(backupRepositoryProvider)
          .exportBackup(passphrase: passphrase);
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
            failureMessage(context, error, fallback: AppFailureCode.backup),
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
            failureMessage(context, error, fallback: AppFailureCode.backup),
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
      allowedExtensions: ['owntend-backup'],
    );
    final path = result.isNotEmpty ? result.first.path : null;
    if (path == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    _restorePassphrase = null;
    _setBusy(context.l10n.checkingBackup);
    try {
      BackupPreview preview;
      try {
        preview = await ref
            .read(backupRepositoryProvider)
            .inspectBackup(path, passphrase: null);
      } on BackupPassphraseRequiredException {
        if (!mounted) {
          return;
        }
        final entered = await _promptForRestorePassphrase();
        if (!mounted || entered == null || entered.isEmpty) {
          return;
        }
        _setBusy(context.l10n.checkingBackup);
        _restorePassphrase = entered;
        preview = await ref
            .read(backupRepositoryProvider)
            .inspectBackup(path, passphrase: entered);
      }
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
            failureMessage(context, error, fallback: AppFailureCode.backup),
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

  Future<String?> _promptForRestorePassphrase() => showDialog<String>(
    context: context,
    builder: (_) => const _RestorePassphraseDialog(),
  );

  Future<void> _confirmRestore() async {
    final preview = _restorePreview;
    if (preview == null) {
      return;
    }
    final syncStatus = await ref.read(cloudSyncRepositoryProvider).status();
    if (!mounted) return;
    final choice = await showDialog<RestoreCloudDisposition>(
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
                  Navigator.of(context)
                      .pop(RestoreCloudDisposition.updateCloud),
              child: Text(context.l10n.restoreAndUpdateCloudBackup),
            ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context)
                    .pop(RestoreCloudDisposition.localOnlyPaused),
            child: Text(
              syncStatus.enabled
                  ? context.l10n.restoreLocallyAndPauseCloudBackup
                  : context.l10n.restoreBackup,
            ),
          ),
        ],
      ),
    );
    if (choice == null) {
      if (mounted) {
        setState(() {
          _restorePreview = null;
          _restorePassphrase = null;
        });
      }
      return;
    }
    await _restoreSelectedBackup(preview, choice);
  }

  Future<void> _restoreSelectedBackup(
    BackupPreview preview,
    RestoreCloudDisposition choice,
  ) async {
    _setBusy(context.l10n.restoringBackup);
    try {
      if (choice == RestoreCloudDisposition.updateCloud) {
        await ref.read(cloudSyncRepositoryProvider).syncNow();
      } else {
        await ref.read(cloudSyncRepositoryProvider).disable();
      }
      await ref
          .read(backupRepositoryProvider)
          .restoreBackup(
            preview.path,
            passphrase: _restorePassphrase,
            cloudDisposition: choice,
          );
      if (choice == RestoreCloudDisposition.updateCloud) {
        await ref.read(cloudSyncRepositoryProvider).fullReconcile();
      }
      // WP-005 (F-007): the restore service publishes the database epoch on
      // verified commit, so every completion path — not just this screen —
      // rebuilds dependent streams.
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
      setState(() {
        _restorePreview = null;
        _restorePassphrase = null;
      });
      hk_ui.showToast(context, content: Text(context.l10n.backupRestored));
    } catch (error) {
      if (mounted) {
        AppLogger.warning('backup_restore', error: error);
        hk_ui.showToast(
          context,
          content: Text(
            failureMessage(context, error, fallback: AppFailureCode.backup),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _restorePreview = null;
          _restorePassphrase = null;
        });
        _clearBusy();
      } else {
        _restorePassphrase = null;
      }
    }
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
    _restorePassphrase = null;
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

class _ExportPassphraseDialog extends StatefulWidget {
  const _ExportPassphraseDialog();

  @override
  State<_ExportPassphraseDialog> createState() =>
      _ExportPassphraseDialogState();
}

class _ExportPassphraseDialogState extends State<_ExportPassphraseDialog> {
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _passphraseController.clear();
    _confirmController.clear();
    _passphraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validationError() {
    final passphrase = _passphraseController.text;
    if (passphrase.isEmpty) return null;
    if (passphrase.length < 8) {
      return context.l10n.backupPassphraseTooShort;
    }
    if (passphrase != _confirmController.text) {
      return context.l10n.backupPassphraseMismatch;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.backupPassphraseDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _passphraseController,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: context.l10n.backupPassphraseLabel,
                helperText: context.l10n.backupPassphraseHelp,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: context.l10n.backupPassphraseConfirmLabel,
                errorText: _validationError(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () {
            if (_validationError() != null) {
              setState(() {});
              return;
            }
            Navigator.of(context).pop(_passphraseController.text);
          },
          child: Text(context.l10n.createBackup),
        ),
      ],
    );
  }
}

class _RestorePassphraseDialog extends StatefulWidget {
  const _RestorePassphraseDialog();

  @override
  State<_RestorePassphraseDialog> createState() =>
      _RestorePassphraseDialogState();
}

class _RestorePassphraseDialogState extends State<_RestorePassphraseDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.backupEnterPassphraseTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        autofillHints: const [AutofillHints.password],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: context.l10n.backupPassphraseLabel,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(context.l10n.restoreBackup),
        ),
      ],
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
            subtitle:
                context.l10n.backupsAreSavedLocallyAsEncryptedOwntendFiles,
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
              label: Text(context.l10n.chooseOwntendBackup),
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
