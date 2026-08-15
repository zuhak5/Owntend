import 'models.dart';

enum HealthState { excellent, good, attention, critical, insufficientData }

class AttachmentSummary {
  const AttachmentSummary({
    required this.id,
    required this.assetId,
    required this.type,
    required this.label,
    required this.relativePath,
    required this.createdAt,
  });

  final String id;
  final String assetId;
  final String type;
  final String label;
  final String relativePath;
  final DateTime createdAt;
}

class EntityHealthScore {
  const EntityHealthScore({
    required this.score,
    required this.state,
    required this.reasons,
    this.nextBestAction,
  });

  final int score;
  final HealthState state;
  final List<String> reasons;
  final String? nextBestAction;
}

enum HomeSetupStep { room, maintainedItem, scheduledTask }

class HomeSetupProgress {
  const HomeSetupProgress({
    required this.completedSteps,
    required this.nextStep,
  });

  static const totalSteps = 3;

  final int completedSteps;
  final HomeSetupStep? nextStep;

  bool get isEligible => completedSteps == totalSteps;
}

class HomeReadiness {
  const HomeReadiness({
    required this.score,
    required this.state,
    required this.reasons,
    required this.nextBestAction,
  });

  final int score;
  final HealthState state;
  final List<String> reasons;
  final String nextBestAction;
}

class WarrantyAlert {
  const WarrantyAlert({
    required this.asset,
    required this.expiresAt,
    required this.daysRemaining,
  });

  final Asset asset;
  final DateTime expiresAt;
  final int daysRemaining;
}
