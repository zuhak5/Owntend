import 'dart:async';

import 'package:flutter/material.dart';
import 'package:owntend/src/core/services/feedback_messenger.dart';
import 'package:owntend/src/core/utils/redacting_logger.dart';

import 'feedback_bar.dart';
import 'feedback_model.dart';

class FeedbackCoordinator extends ChangeNotifier {
  FeedbackCoordinator._();

  static final FeedbackCoordinator instance = FeedbackCoordinator._();

  int _currentToken = 0;
  HkFeedbackItem? _activeItem;
  final List<HkFeedbackItem> _pendingQueue = [];
  bool _actionExecuted = false;
  bool _accessibleNavigation = false;
  ScaffoldMessengerState? _messenger;
  BuildContext? _lastContext;
  OverlayEntry? _overlayEntry;
  Timer? _overlayTimer;

  HkFeedbackItem? get activeItem => _activeItem;
  int get pendingCount => _pendingQueue.length;

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? show(
    BuildContext context,
    HkFeedbackItem item,
  ) {
    final incoming = _withStandardActionDuration(item);
    final active = _activeItem;
    if (active != null) {
      if (active.mode == HkFeedbackMode.undoable &&
          incoming.mode == HkFeedbackMode.undoable &&
          _canBatchUndo(active, incoming)) {
        _batchUndoItem(incoming);
        notifyListeners();
        _refreshActivePresentation();
        return null;
      }
      if (_isProtected(active)) {
        _enqueue(incoming);
        return null;
      }
      final replacesActive =
          incoming.id == active.id || _priority(incoming) > _priority(active);
      if (!replacesActive) {
        _enqueue(incoming);
        return null;
      }
      _supersedeActiveNonProtected();
    }
    return _showItem(context, incoming);
  }

  HkFeedbackItem _withStandardActionDuration(HkFeedbackItem item) {
    if (item.mode != HkFeedbackMode.undoable &&
        item.mode != HkFeedbackMode.actionable) {
      return item;
    }
    return item.copyWith(duration: const Duration(seconds: 5));
  }

  bool _isProtected(HkFeedbackItem item) =>
      item.mode == HkFeedbackMode.undoable;

  bool _canBatchUndo(HkFeedbackItem active, HkFeedbackItem incoming) =>
      active.batchItemType != null &&
      active.batchItemType == incoming.batchItemType;

  void _batchUndoItem(HkFeedbackItem incoming) {
    final active = _activeItem;
    if (active == null) return;
    final newCount = active.batchCount + incoming.batchCount;
    final previousUndo = active.onUndo;
    final incomingUndo = incoming.onUndo;
    final previousFinalize = active.onFinalize;
    final incomingFinalize = incoming.onFinalize;
    final messageBuilder =
        incoming.batchMessageBuilder ?? active.batchMessageBuilder;
    final semanticBuilder =
        incoming.batchSemanticLabelBuilder ?? active.batchSemanticLabelBuilder;
    final successBuilder =
        incoming.batchActionSuccessMessageBuilder ??
        active.batchActionSuccessMessageBuilder;

    _activeItem = active.copyWith(
      batchCount: newCount,
      message: messageBuilder?.call(newCount) ?? active.message,
      batchMessageBuilder: messageBuilder,
      semanticLabel: semanticBuilder?.call(newCount) ?? incoming.semanticLabel,
      batchSemanticLabelBuilder: semanticBuilder,
      actionSuccessMessage:
          successBuilder?.call(newCount) ?? active.actionSuccessMessage,
      batchActionSuccessMessageBuilder: successBuilder,
      actionFailureMessage:
          incoming.actionFailureMessage ?? active.actionFailureMessage,
      onUndo: () =>
          _runCallbacks([incomingUndo, previousUndo], event: 'feedback_undo'),
      onFinalize: () => _runCallbacks([
        previousFinalize,
        incomingFinalize,
      ], event: 'feedback_finalize'),
    );
  }

  void _enqueue(HkFeedbackItem item) {
    final existing = _pendingQueue.indexWhere((queued) => queued.id == item.id);
    if (existing >= 0) {
      _pendingQueue.removeAt(existing);
    } else if (_isCoalescible(item)) {
      _pendingQueue.removeWhere(
        (queued) => _isCoalescible(queued) && queued.tone == item.tone,
      );
    }
    final priority = _priority(item);
    final insertion = _pendingQueue.indexWhere(
      (queued) => _priority(queued) < priority,
    );
    if (insertion < 0) {
      _pendingQueue.add(item);
    } else {
      _pendingQueue.insert(insertion, item);
    }
    notifyListeners();
  }

  bool _isCoalescible(HkFeedbackItem item) =>
      item.mode == HkFeedbackMode.passive &&
      item.tone != HkFeedbackTone.error &&
      item.tone != HkFeedbackTone.destructive;

  int _priority(HkFeedbackItem item) {
    if (item.mode == HkFeedbackMode.undoable) return 100;
    if (item.mode == HkFeedbackMode.actionable) return 50;
    return switch (item.tone) {
      HkFeedbackTone.error || HkFeedbackTone.destructive => 80,
      HkFeedbackTone.warning => 60,
      HkFeedbackTone.success => 40,
      HkFeedbackTone.info => 30,
      HkFeedbackTone.neutral => 20,
    };
  }

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _showItem(
    BuildContext context,
    HkFeedbackItem item,
  ) {
    final modalOverlay = ModalRoute.of(context) is PopupRoute
        ? Overlay.maybeOf(context, rootOverlay: true)
        : null;
    if (modalOverlay != null) {
      _messenger = null;
      _lastContext = context;
      _accessibleNavigation =
          MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
      _activeItem = item;
      _actionExecuted = false;
      notifyListeners();
      _presentActiveOverlay(modalOverlay, item);
      return null;
    }

    final messenger =
        ScaffoldMessenger.maybeOf(context) ??
        (hkRootScaffoldMessengerKey.currentState?.mounted == true
            ? hkRootScaffoldMessengerKey.currentState
            : null);
    if (messenger == null) {
      _enqueue(item);
      return null;
    }

    _messenger = messenger;
    _lastContext = context;
    _accessibleNavigation =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
    _activeItem = item;
    _actionExecuted = false;
    notifyListeners();
    return _presentActive(messenger, item, context);
  }

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _presentActive(
    ScaffoldMessengerState messenger,
    HkFeedbackItem item,
    BuildContext context,
  ) {
    _removeOverlayPresentation();
    final token = ++_currentToken;
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: AnimatedBuilder(
          animation: this,
          builder: (context, child) {
            final current = _currentToken == token ? _activeItem : null;
            final rendered = current ?? item;
            return HkFeedbackBar(
              item: rendered,
              message: rendered.message,
              onAction: rendered.actionLabel == null ? null : handleAction,
              onDismiss: dismissCurrent,
              showCountdown:
                  !_accessibleNavigation &&
                  rendered.mode == HkFeedbackMode.undoable,
            );
          },
        ),
        duration: item.duration,
        persist: _accessibleNavigation && item.actionLabel != null,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        behavior: SnackBarBehavior.floating,
        margin: _resolvedMargin(context, item),
      ),
    );
    unawaited(
      controller.closed.then((reason) {
        if (_currentToken != token || _activeItem == null) return;
        final dismissReason = reason == SnackBarClosedReason.timeout
            ? HkFeedbackDismissReason.timeout
            : HkFeedbackDismissReason.userDismiss;
        unawaited(_dismissCurrent(dismissReason));
      }),
    );
    return controller;
  }

  void _presentActiveOverlay(OverlayState overlay, HkFeedbackItem item) {
    _removeOverlayPresentation();
    final token = ++_currentToken;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        final media = MediaQuery.maybeOf(context);
        final safeBottom = media?.viewPadding.bottom ?? 0;
        final keyboardBottom = media?.viewInsets.bottom ?? 0;
        final obstruction = keyboardBottom > safeBottom
            ? keyboardBottom
            : safeBottom;
        return PositionedDirectional(
          key: const ValueKey('feedback-modal-overlay'),
          start: 16,
          end: 16,
          bottom: obstruction + 12,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Transform.translate(
              offset: Offset(0, 12 * (1 - value)),
              child: Opacity(opacity: value, child: child),
            ),
            child: AnimatedBuilder(
              animation: this,
              builder: (context, child) {
                final current = _currentToken == token ? _activeItem : null;
                final rendered = current ?? item;
                return HkFeedbackBar(
                  item: rendered,
                  message: rendered.message,
                  onAction: rendered.actionLabel == null ? null : handleAction,
                  onDismiss: dismissCurrent,
                  showCountdown:
                      !_accessibleNavigation &&
                      rendered.mode == HkFeedbackMode.undoable,
                );
              },
            ),
          ),
        );
      },
    );
    _overlayEntry = entry;
    overlay.insert(entry);
    _restartOverlayTimeout(item);
  }

  void _restartOverlayTimeout(HkFeedbackItem item) {
    _overlayTimer?.cancel();
    _overlayTimer = null;
    if (_accessibleNavigation && item.actionLabel != null) return;
    _overlayTimer = Timer(item.duration, () {
      if (identical(_activeItem, item) || _activeItem?.id == item.id) {
        unawaited(_dismissCurrent(HkFeedbackDismissReason.timeout));
      }
    });
  }

  void _removeOverlayPresentation() {
    _overlayTimer?.cancel();
    _overlayTimer = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  EdgeInsetsGeometry _resolvedMargin(
    BuildContext context,
    HkFeedbackItem item,
  ) {
    if (item.margin != null) return item.margin!;
    // Floating SnackBars are positioned by Scaffold above its real bottom
    // navigation, persistent footer, FAB, safe area, and keyboard-adjusted
    // content bounds. Keep this margin to the visual gap only; duplicating
    // those insets here pushes feedback unnecessarily high.
    return const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12);
  }

  void _refreshActivePresentation() {
    final item = _activeItem;
    final context = _lastContext;
    if (item == null || context == null || !context.mounted) {
      return;
    }
    if (_overlayEntry != null) {
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay != null) _presentActiveOverlay(overlay, item);
      return;
    }
    final messenger = _messenger;
    if (messenger == null || !messenger.mounted) return;
    _presentActive(messenger, item, context);
  }

  Future<void> handleAction() async {
    if (_actionExecuted || _activeItem == null) return;
    _actionExecuted = true;
    final item = _activeItem!;
    _activeItem = null;
    _currentToken++;
    _removeOverlayPresentation();
    _messenger?.hideCurrentSnackBar();
    notifyListeners();

    HkFeedbackItem? outcome;
    try {
      if (item.onUndo != null) {
        await item.onUndo!();
      } else if (item.onAction != null) {
        await item.onAction!();
      }
      final message = item.actionSuccessMessage;
      if (message != null) {
        outcome = _outcomeItem(item, message, HkFeedbackTone.success);
      }
    } on HkFeedbackPartialSuccess catch (partial) {
      outcome = _outcomeItem(item, partial.message, HkFeedbackTone.warning);
    } on Object catch (error) {
      AppLogger.warning('feedback_action', error: error);
      final message = item.actionFailureMessage;
      if (message != null) {
        outcome = _outcomeItem(item, message, HkFeedbackTone.error);
      }
    } finally {
      item.onDismiss?.call(HkFeedbackDismissReason.userAction);
      if (outcome != null) _enqueue(outcome);
      _processNextQueue();
    }
  }

  HkFeedbackItem _outcomeItem(
    HkFeedbackItem source,
    Widget message,
    HkFeedbackTone tone,
  ) {
    return HkFeedbackItem(
      id: '${source.id}-outcome-${tone.name}',
      message: message,
      tone: tone,
      duration: const Duration(seconds: 4),
    );
  }

  void dismissCurrent() {
    unawaited(_dismissCurrent(HkFeedbackDismissReason.userDismiss));
  }

  Future<void> _dismissCurrent(HkFeedbackDismissReason reason) async {
    if (_actionExecuted || _activeItem == null) return;
    _actionExecuted = true;
    final item = _activeItem!;
    _activeItem = null;
    _currentToken++;
    _removeOverlayPresentation();
    _messenger?.hideCurrentSnackBar();
    notifyListeners();
    try {
      if (item.onFinalize != null) await item.onFinalize!();
    } on Object catch (error) {
      AppLogger.warning('feedback_finalize', error: error);
      if (item.actionFailureMessage != null) {
        _enqueue(
          _outcomeItem(item, item.actionFailureMessage!, HkFeedbackTone.error),
        );
      }
    } finally {
      item.onDismiss?.call(reason);
      _processNextQueue();
    }
  }

  void _supersedeActiveNonProtected() {
    final item = _activeItem;
    if (item == null) return;
    assert(!_isProtected(item));
    _actionExecuted = true;
    _activeItem = null;
    _currentToken++;
    _removeOverlayPresentation();
    if (item.onFinalize != null) {
      unawaited(
        Future<void>.sync(item.onFinalize!).catchError((Object error) {
          AppLogger.warning('feedback_finalize', error: error);
        }),
      );
    }
    item.onDismiss?.call(HkFeedbackDismissReason.superceded);
  }

  Future<void> _runCallbacks(
    List<FutureOr<void> Function()?> callbacks, {
    required String event,
  }) async {
    final errors = <Object>[];
    final partials = <HkFeedbackPartialSuccess>[];
    for (final callback in callbacks) {
      if (callback == null) continue;
      try {
        await callback();
      } on HkFeedbackPartialSuccess catch (partial) {
        partials.add(partial);
      } on Object catch (error) {
        AppLogger.warning(event, error: error);
        errors.add(error);
      }
    }
    if (errors.isNotEmpty) throw HkFeedbackAggregateFailure(errors);
    if (partials.isNotEmpty) throw partials.last;
  }

  void _processNextQueue() {
    if (_activeItem != null || _pendingQueue.isEmpty) return;
    BuildContext? context = _lastContext;
    if (context == null || !context.mounted) {
      context = hkRootScaffoldMessengerKey.currentContext;
    }
    if (context != null && context.mounted) {
      final next = _pendingQueue.removeAt(0);
      _showItem(context, next);
    }
  }

  void resetForTesting() {
    _currentToken++;
    _activeItem = null;
    _pendingQueue.clear();
    _actionExecuted = false;
    _accessibleNavigation = false;
    _removeOverlayPresentation();
    _messenger = null;
    _lastContext = null;
    try {
      hkRootScaffoldMessengerKey.currentState?.clearSnackBars();
    } on Object {
      // Tests may tear down the binding before the global messenger.
    }
    notifyListeners();
  }
}
