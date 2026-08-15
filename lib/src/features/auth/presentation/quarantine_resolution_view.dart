import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntend/l10n/app_localizations_ext.dart';

import '../../../core/domain/contracts.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_providers.dart';
import 'auth_providers.dart';

class QuarantineResolutionView extends ConsumerStatefulWidget {
  const QuarantineResolutionView({required this.database, super.key});

  final AppDatabase database;

  @override
  ConsumerState<QuarantineResolutionView> createState() =>
      _QuarantineResolutionViewState();
}

class _QuarantineResolutionViewState
    extends ConsumerState<QuarantineResolutionView> {
  bool _busy = false;
  String? _statusMessage;

  Future<void> _exportBackup() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final service = ZipBackupService(widget.database);
      final filePath = await service.exportBackup(
        trigger: BackupTrigger.preRestore,
      );
      if (mounted) {
        setState(() {
          _statusMessage = 'Backup saved to: $filePath';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Backup failed: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.resetLocalData),
        content: Text(context.l10n.resetLocalDataConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });

    try {
      final store = ref.read(localSyncStoreProvider);
      if (store != null) {
        await store.resolveQuarantineWithReset();
      }
      final coordinator = ref.read(syncCoordinatorProvider);
      final userId = ref.read(authSessionProvider).value?.userId;
      if (coordinator != null && userId != null) {
        await coordinator.enable();
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Reset failed: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmImport() async {
    final userId = ref.read(authSessionProvider).value?.userId;
    if (userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.importLocalData),
        content: Text(context.l10n.importLocalDataConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.importLocalData),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });

    try {
      final store = ref.read(localSyncStoreProvider);
      if (store != null) {
        await store.resolveQuarantineWithImport(userId);
      }
      final coordinator = ref.read(syncCoordinatorProvider);
      if (coordinator != null) {
        await coordinator.enable();
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Import failed: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.security_outlined, size: 48, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                context.l10n.quarantinedDataTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.quarantinedDataDescription,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusMessage!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _busy ? null : _exportBackup,
                icon: const Icon(Icons.download_rounded),
                label: Text(context.l10n.exportSafetyBackup),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _confirmImport,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(context.l10n.importLocalData),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _busy ? null : _confirmReset,
                style: TextButton.styleFrom(foregroundColor: colorScheme.error),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(context.l10n.resetLocalData),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
