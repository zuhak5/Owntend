import 'dart:math' as math;

import 'package:flutter/foundation.dart';

enum AdLoadFailureKind { network, internal, noFill, invalidRequest, unknown }

@immutable
class AdRetryDecision {
  const AdRetryDecision.retry(this.delay) : dormant = false;

  const AdRetryDecision.dormant() : delay = Duration.zero, dormant = true;

  final Duration delay;
  final bool dormant;

  bool get shouldRetry => !dormant;
}

class AdRetryPolicy {
  const AdRetryPolicy({this.jitterFraction = 0.2});

  final double jitterFraction;

  AdRetryDecision decide({
    required AdLoadFailureKind failure,
    required int failedAttempt,
    double jitterUnit = 0.5,
  }) {
    final maxAutomaticRetries = switch (failure) {
      AdLoadFailureKind.network => 4,
      AdLoadFailureKind.internal || AdLoadFailureKind.unknown => 2,
      AdLoadFailureKind.noFill || AdLoadFailureKind.invalidRequest => 0,
    };
    if (failedAttempt <= 0 || failedAttempt > maxAutomaticRetries) {
      return const AdRetryDecision.dormant();
    }
    const baseSeconds = [2, 8, 30, 60];
    final base = baseSeconds[(failedAttempt - 1).clamp(0, 3)];
    final normalized = jitterUnit.clamp(0.0, 1.0);
    final factor = 1 - jitterFraction + (2 * jitterFraction * normalized);
    final milliseconds = math.max(1, (base * 1000 * factor).round());
    return AdRetryDecision.retry(Duration(milliseconds: milliseconds));
  }
}
