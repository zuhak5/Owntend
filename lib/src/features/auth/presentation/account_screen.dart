import 'dart:io';

import 'package:flutter/material.dart';
import 'package:owntend/l10n/app_localizations_ext.dart';

import '../../../core/utils/app_failure.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/domain/models.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/components.dart' as hk_ui;
import '../domain/auth_repository.dart';
import 'auth_providers.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({
    this.profile,
    this.onSaveNickname,
    this.sponsoredContent,
    super.key,
  });

  final AppProfile? profile;
  final Future<void> Function(String? nickname)? onSaveNickname;
  final Widget? sponsoredContent;

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authRepositoryProvider);
    final session =
        ref.watch(authSessionProvider).value ?? auth?.currentSession;
    final buildInfo = ref.watch(appBuildInfoProvider);

    return Scaffold(
      appBar: null,
      body: hk_ui.ProductivityBackdrop(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                HkSpacing.gutter,
                HkSpacing.xs,
                HkSpacing.gutter,
                HkSpacing.bottomAction,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      hk_ui.AppPageHeader(
                        title: context.l10n.account,
                        onBack: () {
                          final router = GoRouter.maybeOf(context);
                          if (router != null) {
                            if (router.canPop()) {
                              router.pop();
                            } else {
                              router.go('/');
                            }
                          } else {
                            final navigator = Navigator.maybeOf(context);
                            if (navigator != null && navigator.canPop()) {
                              navigator.pop();
                            }
                          }
                        },
                      ),
                      if (widget.sponsoredContent case final content?) ...[
                        const SizedBox(height: HkSpacing.sm),
                        content,
                      ] else
                        const SizedBox(height: HkSpacing.sm),
                      _NicknameCard(
                        profile: widget.profile,
                        session: session,
                        onSaveNickname: widget.onSaveNickname,
                      ),
                      const SizedBox(height: HkSpacing.sm),
                      _AccountNavigationCard(
                        onSettings: () => context.push('/settings'),
                        onSyncHealth: () => context.push('/sync-health'),
                        onBackup: () => context.push('/backup'),
                      ),
                      if (session != null) ...[
                        const SizedBox(height: HkSpacing.sm),
                        _AccountControlsCard(
                          busy: _busy,
                          onSignOut: _signOut,
                          onDelete: _deleteAccount,
                        ),
                      ],
                      const SizedBox(height: HkSpacing.md),
                      Center(
                        child: Text(
                          buildInfo.when(
                            data: (info) => info.label,
                            loading: () => context.l10n.checkingAppBuild,
                            error: (_, _) =>
                                context.l10n.appBuildInformationUnavailable,
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
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

  Future<void> _run(
    Future<void> Function() action, {
    required String success,
    AppFailureCode failureCode = AppFailureCode.general,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });
    try {
      await action();
      if (mounted) {
        hk_ui.showToast(context, content: Text(success));
      }
    } on Object catch (error) {
      if (mounted) {
        hk_ui.showToast(
          context,
          content: Text(
            localizedFailureMessage(
              context.l10n,
              appFailureCodeFor(error, fallback: failureCode),
            ),
          ),
          severity: hk_ui.HkToastSeverity.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final l10n = context.l10n;
    final confirmed = await _confirm(
      title: l10n.signOut2,
      body: l10n.accountSignOutBody,
      action: l10n.signOut,
    );
    if (!confirmed) return;
    await _run(() async {
      await ref.read(authRepositoryProvider)!.signOut();
    }, success: l10n.signedOut);
  }

  Future<void> _deleteAccount() async {
    final l10n = context.l10n;
    final confirmed = await _confirm(
      title: l10n.deleteOwntendAccount,
      body: l10n.deleteAccountBody,
      action: l10n.deleteAccount,
      destructive: true,
    );
    if (!confirmed) return;
    await _run(
      () async {
        await ref.read(authRepositoryProvider)!.deleteAccount();
      },
      success: l10n.accountDeleted,
      failureCode: AppFailureCode.accountDeletion,
    );
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            actionsOverflowButtonSpacing: HkSpacing.xs,
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      )
                    : null,
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }
}

ImageProvider<Object>? _localAvatarProvider(String? path) {
  final resolved = path?.trim();
  if (resolved == null || resolved.isEmpty) return null;
  final file = File(resolved);
  return file.existsSync() ? FileImage(file) : null;
}

class _NicknameCard extends StatefulWidget {
  const _NicknameCard({
    required this.profile,
    required this.session,
    required this.onSaveNickname,
  });

  final AppProfile? profile;
  final AuthSession? session;
  final Future<void> Function(String? nickname)? onSaveNickname;

  @override
  State<_NicknameCard> createState() => _NicknameCardState();
}

class _NicknameCardState extends State<_NicknameCard> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return hk_ui.SurfaceCard(
      padding: const EdgeInsets.all(16),
      borderColor: scheme.primary.withValues(alpha: 0.18),
      backgroundColor: Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.05),
        scheme.surfaceContainerLowest,
      ),
      child: ListTile(
        key: const ValueKey('account-nickname-option'),
        contentPadding: EdgeInsets.zero,
        leading: hk_ui.ProfileAvatar(
          radius: 24,
          fallbackName:
              widget.profile?.nickname ??
              widget.session?.displayName ??
              widget.session?.email ??
              'Owntend',
          imageProvider: _localAvatarProvider(widget.profile?.avatarPath),
          avatarUrl: widget.session?.avatarUrl,
        ),
        title: Text(
          context.l10n.nickname,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          widget.profile?.nickname ?? context.l10n.notSet,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        trailing: _saving
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.3),
              )
            : const Icon(Symbols.edit_rounded),
        onTap: widget.onSaveNickname == null ? null : _edit,
      ),
    );
  }

  Future<void> _edit() async {
    if (_saving) {
      return;
    }
    final result = await showDialog<dynamic>(
      context: context,
      builder: (context) =>
          _NicknameDialog(initialValue: widget.profile?.nickname),
    );
    if (!mounted || result == null) {
      return;
    }
    final next = switch (result) {
      _NicknameDialogAction.clear => null,
      final String value => value.trim().isEmpty ? null : value.trim(),
      _ => null,
    };
    if (next == widget.profile?.nickname) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSaveNickname!(next);
      if (mounted) {
        hk_ui.showToast(context, content: Text(context.l10n.nicknameUpdated));
      }
    } catch (error) {
      if (mounted) {
        hk_ui.showToast(
          context,
          content: Text(
            localizedFailureMessage(context.l10n, appFailureCodeFor(error)),
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
}

enum _NicknameDialogAction { cancel, clear }

class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({this.initialValue});

  final String? initialValue;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      actionsOverflowButtonSpacing: HkSpacing.xs,
      title: Text(context.l10n.nickname),
      content: TextField(
        key: const ValueKey('account-nickname-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        decoration: InputDecoration(labelText: context.l10n.nickname),
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_NicknameDialogAction.cancel),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_NicknameDialogAction.clear),
          child: Text(context.l10n.clear),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}

class _AccountNavigationCard extends StatelessWidget {
  const _AccountNavigationCard({
    required this.onSettings,
    required this.onSyncHealth,
    required this.onBackup,
  });

  final VoidCallback onSettings;
  final VoidCallback onSyncHealth;
  final VoidCallback onBackup;

  @override
  Widget build(BuildContext context) {
    return hk_ui.SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          hk_ui.SettingsRow(
            icon: Symbols.settings_rounded,
            title: context.l10n.settings,
            subtitle: context.l10n.appearanceLocationAndNotifications,
            onTap: onSettings,
          ),
          const Divider(height: 1),
          hk_ui.SettingsRow(
            icon: Symbols.cloud_sync_rounded,
            title: context.l10n.syncHealth,
            subtitle: context.l10n.reviewChangesThatNeedSyncAttention,
            onTap: onSyncHealth,
          ),
          const Divider(height: 1),
          hk_ui.SettingsRow(
            icon: Symbols.backup_rounded,
            title: context.l10n.backupAndRestore,
            subtitle: context.l10n.exportOrRestoreAnEncryptedOwntendArchive,
            onTap: onBackup,
          ),
        ],
      ),
    );
  }
}

class _AccountControlsCard extends StatelessWidget {
  const _AccountControlsCard({
    required this.busy,
    required this.onSignOut,
    required this.onDelete,
  });

  final bool busy;
  final VoidCallback onSignOut;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return hk_ui.PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.accountControls,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.accountControlsBody,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (busy) ...[
            const SizedBox(height: HkSpacing.xs),
            const LinearProgressIndicator(
              key: ValueKey('account-action-progress'),
            ),
          ],
          const SizedBox(height: HkSpacing.sm),
          hk_ui.CompactActionGroup(
            minButtonWidth: 196,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onSignOut,
                icon: const Icon(Icons.logout_rounded),
                label: Text(context.l10n.signOut),
              ),
              TextButton.icon(
                onPressed: busy ? null : onDelete,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(context.l10n.deleteAccount),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
