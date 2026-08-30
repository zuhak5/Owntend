import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:owntend/l10n/app_localizations_ext.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/components.dart' as hk_ui;
import '../../monetization/monetization.dart';
import '../../monetization/presentation/earn_points_flow.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.tools)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              HkSpacing.gutter,
              HkSpacing.xs,
              HkSpacing.gutter,
              HkSpacing.bottomAction + HkSpacing.bottomNav,
            ),
            children: [
              const HkNativeAdCard(placement: 'more'),
              hk_ui.ToolTile(
                icon: Symbols.stars_rounded,
                title: context.l10n.earnFreePoints,
                subtitle: context.l10n.earnFreePointsSubtitle,
                onTap: () =>
                    showEarnPointsFlow(context, ref, entryPoint: 'more'),
              ),
              hk_ui.ToolTile(
                icon: Symbols.search_rounded,
                title: context.l10n.search,
                subtitle: context.l10n.findRoomsItemsTagsNotesPhotosAndTasks,
                onTap: () => context.push('/search'),
              ),
              hk_ui.SectionHeader(title: context.l10n.insights),
              hk_ui.ToolTile(
                icon: Symbols.query_stats_rounded,
                title: context.l10n.statistics,
                subtitle: context.l10n.completionTrendsAndTaskDistribution,
                onTap: () => context.push('/statistics'),
              ),
              hk_ui.SectionHeader(title: context.l10n.data),
              hk_ui.ToolTile(
                icon: Symbols.cloud_sync_rounded,
                title: context.l10n.accountAndCloudSync,
                subtitle: context.l10n.requiredGoogleSignInAndPrivateDeviceSync,
                onTap: () => context.push('/account'),
              ),
              hk_ui.ToolTile(
                icon: Symbols.cloud_upload_rounded,
                title: context.l10n.backupAndRestore,
                subtitle:
                    context.l10n.createShareOrRestoreEncryptedOwntendBackups,
                onTap: () => context.push('/backup'),
              ),
              hk_ui.ToolTile(
                icon: Symbols.restore_from_trash_rounded,
                title: context.l10n.trash,
                subtitle: context.l10n.restoreRecentlyRemovedRoomsItemsAndTasks,
                onTap: () => context.push('/trash'),
              ),
              hk_ui.SectionHeader(title: context.l10n.system),
              hk_ui.ToolTile(
                icon: Symbols.settings_rounded,
                title: context.l10n.settings,
                subtitle: context.l10n.themeRemindersPrivacyAndReleaseReadiness,
                onTap: () => context.push('/settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
