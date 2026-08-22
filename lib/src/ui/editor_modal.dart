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
      builder: (sheetContext) {
        final keyboardInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return SizedBox(
          key: const ValueKey('editor-modal-hit-surface'),
          height: MediaQuery.sizeOf(sheetContext).height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(sheetContext).pop(),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: keyboardInset,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: builder(sheetContext),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
