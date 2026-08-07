// Typed per-exercise analytics detail for the Progress screen (Phase 7).
// Pure Dart; prose is a presentation concern. Definitions:
// docs/ANALYTICS_DEFINITIONS.md.

import '../services/plateau_detector.dart';
import '../services/plateau_diagnosis_service.dart';
import 'analytics.dart';

/// The best session e1RM within the recent window, with its (latest) day.
class RecentBest {
  final double e1RmKg;
  final DateTime day;

  const RecentBest({required this.e1RmKg, required this.day});
}

/// Complete typed analysis of one exercise. Structured evidence is retained
/// in [evidence]; the UI derives all wording from these fields.
class ExerciseDetail {
  final String exerciseName;

  /// Per-day session series (chart + counts); may be empty.
  final ExerciseSeries series;

  /// e1RM trend over the full history (PlateauDetector).
  final PlateauStatus strengthStatus;
  final double strengthSlopeKgPerDay;

  /// Session-volume trend over the full history.
  final PlateauStatus volumeStatus;

  /// True when the e1RM trend is plateau/regressing but volume is rising -
  /// the plateau concern (and diagnosis) is suppressed, same rule as the
  /// dashboard and the pre-Phase-7 banner.
  final bool volumeProgressionSuppressed;

  /// Best session e1RM in the recent window (28 days) + its day.
  final MetricResult<RecentBest> recentBest;

  /// Best-e1RM change: prior 28 days vs recent 28 days.
  final MetricResult<PercentageChange> strengthChange;

  /// Total-volume change: prior 28 days vs recent 28 days.
  final MetricResult<PercentageChange> volumeChange;

  /// Average sessions/week over the recent window.
  final MetricResult<double> sessionsPerWeek;

  final int sessionsInWindow;
  final int totalSessions;
  final DataQuality dataQuality;

  /// Typed observations backing the status (counts, changes, frequency).
  final List<EvidenceItem> evidence;

  /// Rule-based possible explanation; only attached for an unsuppressed
  /// plateau/regression. Presented as a possibility, never a proven cause.
  final PlateauDiagnosis? possibleExplanation;

  const ExerciseDetail({
    required this.exerciseName,
    required this.series,
    required this.strengthStatus,
    required this.strengthSlopeKgPerDay,
    required this.volumeStatus,
    required this.volumeProgressionSuppressed,
    required this.recentBest,
    required this.strengthChange,
    required this.volumeChange,
    required this.sessionsPerWeek,
    required this.sessionsInWindow,
    required this.totalSessions,
    required this.dataQuality,
    required this.evidence,
    required this.possibleExplanation,
  });
}
