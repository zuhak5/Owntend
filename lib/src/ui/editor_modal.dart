import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../features/monetization/monetization.dart';

Future<T?> showEditorModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return runWithNativeAdsSuspended(
    context,
    () => showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (sheetContext) => _EditorModalHost(builder: builder),
    ),
  );
}

class _EditorModalHost extends StatelessWidget {
  const _EditorModalHost({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final totalHeight = mediaQuery.size.height;

    return SizedBox(
      key: const ValueKey('editor-modal-hit-surface'),
      height: totalHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: mediaQuery.padding.top + 16,
            bottom: keyboardInset,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 640,
                  maxHeight: math.max(
                    160.0,
                    totalHeight - keyboardInset - mediaQuery.padding.top - 32,
                  ),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: builder(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
