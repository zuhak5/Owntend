import 'dart:async';

import 'package:flutter/material.dart';

enum HkFeedbackTone { neutral, info, success, warning, error, destructive }

enum HkFeedbackMode { passive, actionable, undoable, progress }

enum HkFeedbackDismissReason {
  timeout,
  userAction,
  userDismiss,
  superceded,
  routeChange,
}

@immutable
class HkFeedbackItem {
  const HkFeedbackItem({
    required this.id,
    required this.message,
    this.tone = HkFeedbackTone.neutral,
    this.mode = HkFeedbackMode.passive,
    this.actionLabel,
    this.onAction,
    this.onUndo,
    this.onFinalize,
    this.onDismiss,
    this.duration = const Duration(seconds: 4),
    this.batchCount = 1,
    this.batchItemType,
    this.batchMessageBuilder,
    this.semanticLabel,
    this.batchSemanticLabelBuilder,
    this.actionSuccessMessage,
    this.batchActionSuccessMessageBuilder,
    this.actionFailureMessage,
    this.margin,
  });

  final String id;
  final Widget message;
  final HkFeedbackTone tone;
  final HkFeedbackMode mode;
  final String? actionLabel;
  final FutureOr<void> Function()? onAction;
  final FutureOr<void> Function()? onUndo;
  final FutureOr<void> Function()? onFinalize;
  final void Function(HkFeedbackDismissReason)? onDismiss;
  final Duration duration;
  final int batchCount;
  final String? batchItemType;
  final Widget Function(int count)? batchMessageBuilder;
  final String? semanticLabel;
  final String Function(int count)? batchSemanticLabelBuilder;
  final Widget? actionSuccessMessage;
  final Widget Function(int count)? batchActionSuccessMessageBuilder;
  final Widget? actionFailureMessage;
  final EdgeInsetsGeometry? margin;

  HkFeedbackItem copyWith({
    String? id,
    Widget? message,
    HkFeedbackTone? tone,
    HkFeedbackMode? mode,
    String? actionLabel,
    FutureOr<void> Function()? onAction,
    FutureOr<void> Function()? onUndo,
    FutureOr<void> Function()? onFinalize,
    void Function(HkFeedbackDismissReason)? onDismiss,
    Duration? duration,
    int? batchCount,
    String? batchItemType,
    Widget Function(int count)? batchMessageBuilder,
    String? semanticLabel,
    String Function(int count)? batchSemanticLabelBuilder,
    Widget? actionSuccessMessage,
    Widget Function(int count)? batchActionSuccessMessageBuilder,
    Widget? actionFailureMessage,
    EdgeInsetsGeometry? margin,
  }) {
    return HkFeedbackItem(
      id: id ?? this.id,
      message: message ?? this.message,
      tone: tone ?? this.tone,
      mode: mode ?? this.mode,
      actionLabel: actionLabel ?? this.actionLabel,
      onAction: onAction ?? this.onAction,
      onUndo: onUndo ?? this.onUndo,
      onFinalize: onFinalize ?? this.onFinalize,
      onDismiss: onDismiss ?? this.onDismiss,
      duration: duration ?? this.duration,
      batchCount: batchCount ?? this.batchCount,
      batchItemType: batchItemType ?? this.batchItemType,
      batchMessageBuilder: batchMessageBuilder ?? this.batchMessageBuilder,
      semanticLabel: semanticLabel ?? this.semanticLabel,
      batchSemanticLabelBuilder:
          batchSemanticLabelBuilder ?? this.batchSemanticLabelBuilder,
      actionSuccessMessage: actionSuccessMessage ?? this.actionSuccessMessage,
      batchActionSuccessMessageBuilder:
          batchActionSuccessMessageBuilder ??
          this.batchActionSuccessMessageBuilder,
      actionFailureMessage: actionFailureMessage ?? this.actionFailureMessage,
      margin: margin ?? this.margin,
    );
  }
}

class HkFeedbackPartialSuccess implements Exception {
  const HkFeedbackPartialSuccess(this.message);

  final Widget message;
}

class HkFeedbackAggregateFailure implements Exception {
  const HkFeedbackAggregateFailure(this.errors);

  final List<Object> errors;
}
