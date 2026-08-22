import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:owntend/l10n/app_localizations_ext.dart';

import 'app_theme.dart';

class EditorSheetFrame extends StatelessWidget {
  const EditorSheetFrame({
    required this.title,
    required this.saveLabel,
    required this.onCancel,
    required this.onSave,
    required this.child,
    this.saveEnabled = true,
    this.secondarySaveLabel,
    this.onSecondarySave,
    super.key,
  });

  final String title;
  final String saveLabel;
  final bool saveEnabled;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final String? secondarySaveLabel;
  final VoidCallback? onSecondarySave;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight = MediaQuery.sizeOf(context).height - keyboardInset;
    final maxHeight = math.max(240.0, availableHeight * 0.92);
    return Material(
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(HkRadii.xxl),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: HkSpacing.xs),
            Center(
              child: Container(
                key: const ValueKey('editor-sheet-drag-handle'),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(HkRadii.full),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HkSpacing.md,
                HkSpacing.xs,
                HkSpacing.xs,
                HkSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.close,
                    onPressed: onCancel,
                    icon: const Icon(Symbols.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  HkSpacing.md,
                  0,
                  HkSpacing.md,
                  HkSpacing.md,
                ),
                child: child,
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  HkSpacing.md,
                  HkSpacing.xs,
                  HkSpacing.md,
                  HkSpacing.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (secondarySaveLabel != null &&
                        onSecondarySave != null) ...[
                      OutlinedButton(
                        onPressed: saveEnabled ? onSecondarySave : null,
                        child: Text(secondarySaveLabel!),
                      ),
                      const SizedBox(height: HkSpacing.xs),
                    ],
                    FilledButton(
                      onPressed: saveEnabled ? onSave : null,
                      child: Text(saveLabel),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
