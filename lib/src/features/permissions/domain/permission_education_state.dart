import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'permission_capability.dart';

@immutable
class StepEducationState {
  const StepEducationState({
    this.educationSeen = false,
    this.deferredAt,
    this.deferCount = 0,
    this.lastOutcome = PermissionEducationOutcome.deferred,
  });

  final bool educationSeen;
  final DateTime? deferredAt;
  final int deferCount;
  final PermissionEducationOutcome lastOutcome;

  StepEducationState copyWith({
    bool? educationSeen,
    DateTime? deferredAt,
    int? deferCount,
    PermissionEducationOutcome? lastOutcome,
  }) {
    return StepEducationState(
      educationSeen: educationSeen ?? this.educationSeen,
      deferredAt: deferredAt ?? this.deferredAt,
      deferCount: deferCount ?? this.deferCount,
      lastOutcome: lastOutcome ?? this.lastOutcome,
    );
  }

  Map<String, dynamic> toJson() => {
    'educationSeen': educationSeen,
    'deferredAt': deferredAt?.toIso8601String(),
    'deferCount': deferCount,
    'lastOutcome': lastOutcome.name,
  };

  factory StepEducationState.fromJson(Map<String, dynamic> json) {
    return StepEducationState(
      educationSeen: json['educationSeen'] as bool? ?? false,
      deferredAt: json['deferredAt'] != null
          ? DateTime.tryParse(json['deferredAt'] as String)
          : null,
      deferCount: json['deferCount'] as int? ?? 0,
      lastOutcome: json['lastOutcome'] != null
          ? PermissionEducationOutcome.values.firstWhere(
              (e) => e.name == json['lastOutcome'],
              orElse: () => PermissionEducationOutcome.deferred,
            )
          : PermissionEducationOutcome.deferred,
    );
  }
}

@immutable
class PermissionEducationDeviceState {
  const PermissionEducationDeviceState({
    this.schema = 3,
    this.lastShownAt,
    this.completedAt,
    this.dismissedUntil,
    this.showCount = 0,
    this.source = PermissionEducationSource.firstDashboardVisit,
    this.steps = const {},
  });

  final int schema;
  final DateTime? lastShownAt;
  final DateTime? completedAt;
  final DateTime? dismissedUntil;
  final int showCount;
  final PermissionEducationSource source;
  final Map<PermissionCapability, StepEducationState> steps;

  bool isDeferredFor(PermissionCapability capability, DateTime now) {
    final step = steps[capability];
    if (step?.deferredAt == null) return false;
    final deferCount = step!.deferCount;
    final cooldownDays = deferCount <= 1 ? 7 : 30;
    return now.difference(step.deferredAt!).inDays < cooldownDays;
  }

  PermissionEducationDeviceState copyWith({
    int? schema,
    DateTime? lastShownAt,
    DateTime? completedAt,
    DateTime? dismissedUntil,
    int? showCount,
    PermissionEducationSource? source,
    Map<PermissionCapability, StepEducationState>? steps,
  }) {
    return PermissionEducationDeviceState(
      schema: schema ?? this.schema,
      lastShownAt: lastShownAt ?? this.lastShownAt,
      completedAt: completedAt ?? this.completedAt,
      dismissedUntil: dismissedUntil ?? this.dismissedUntil,
      showCount: showCount ?? this.showCount,
      source: source ?? this.source,
      steps: steps ?? this.steps,
    );
  }

  Map<String, dynamic> toJson() => {
    'schema': schema,
    'lastShownAt': lastShownAt?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'dismissedUntil': dismissedUntil?.toIso8601String(),
    'showCount': showCount,
    'source': source.name,
    'steps': steps.map((k, v) => MapEntry(k.name, v.toJson())),
  };

  factory PermissionEducationDeviceState.fromJson(Map<String, dynamic> json) {
    final stepsMap = <PermissionCapability, StepEducationState>{};
    if (json['steps'] is Map) {
      final rawSteps = json['steps'] as Map<String, dynamic>;
      for (final entry in rawSteps.entries) {
        final cap = PermissionCapability.values.firstWhere(
          (c) => c.name == entry.key,
          orElse: () => PermissionCapability.deviceLocation,
        );
        if (entry.value is Map<String, dynamic>) {
          stepsMap[cap] = StepEducationState.fromJson(
            entry.value as Map<String, dynamic>,
          );
        }
      }
    }
    return PermissionEducationDeviceState(
      schema: json['schema'] as int? ?? 3,
      lastShownAt: json['lastShownAt'] != null
          ? DateTime.tryParse(json['lastShownAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      dismissedUntil: json['dismissedUntil'] != null
          ? DateTime.tryParse(json['dismissedUntil'] as String)
          : null,
      showCount: json['showCount'] as int? ?? 0,
      source: json['source'] != null
          ? PermissionEducationSource.values.firstWhere(
              (s) => s.name == json['source'],
              orElse: () => PermissionEducationSource.firstDashboardVisit,
            )
          : PermissionEducationSource.firstDashboardVisit,
      steps: stepsMap,
    );
  }

  String encode() => jsonEncode(toJson());

  factory PermissionEducationDeviceState.decode(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return PermissionEducationDeviceState.fromJson(json);
    } catch (_) {
      return const PermissionEducationDeviceState();
    }
  }
}
