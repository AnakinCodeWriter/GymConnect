// Typed weekly review domain (Phase 8). Pure Dart: no Flutter, Firebase or
// prose - user-facing wording is produced by a ReviewNarrator from these
// typed values, and every conclusion keeps its structured evidence.
// Definitions: docs/ANALYTICS_DEFINITIONS.md.

import 'analytics.dart';

/// Whether a review can be produced at all. Individual metrics inside an
/// available review may still be unavailable with typed reasons.
enum ReviewAvailability {
  /// No workout history exists - the UI shows an encouraging empty state.
  noData,

  /// History exists; the review is available.
  available,
}

/// The typed conclusion a finding represents. Every kind has a documented
/// deterministic rule in docs/ANALYTICS_DEFINITIONS.md; a narrator may only
/// rephrase a kind, never introduce one.
enum ReviewFindingKind {
  // Improvements
  workoutCountIncreased,
  volumeIncreased,
  newPersonalRecord,
  exerciseProgressing,
  feelImproved,

  // Stable areas
  workoutCountStable,
  volumeStable,

  /// Estimated 1RM looks flat/declining but session volume is rising - the
  /// concern is suppressed (same rule as the dashboard and Progress).
  exerciseVolumeRising,
  repeatedExercises,
  feelStable,

  // Needs attention
  possibleRegression,
  possiblePlateau,
  noTrainingThisWeek,
  workoutCountDecreased,
  volumeDecreased,
  feelDeclined,
  lowFeelWeek,
  insufficientHistory,
  skippedRecords,
}

/// One evidence-backed conclusion inside a review section.
class ReviewFinding {
  final ReviewFindingKind kind;

  /// How much attention the finding warrants (never encodes data quantity -
  /// that is [WeeklyReview.dataQuality]).
  final Severity severity;

  /// The exercise this finding is about; null for whole-week findings.
  final String? exercise;

  /// Exercises supporting a multi-exercise finding ([ReviewFindingKind
  /// .repeatedExercises]); empty otherwise.
  final List<String> exercises;

  /// Observed/comparison values in the kind's documented natural unit
  /// (counts, kg, stars, or kg/day slope for trend kinds).
  final double? observedValue;
  final double? comparisonValue;
  final DatePeriod? period;

  /// Structured observations backing the finding. Never empty: a finding
  /// without evidence must not be produced.
  final List<EvidenceItem> evidence;

  const ReviewFinding({
    required this.kind,
    required this.severity,
    this.exercise,
    this.exercises = const [],
    this.observedValue,
    this.comparisonValue,
    this.period,
    required this.evidence,
  }) : assert(evidence.length > 0, 'a finding requires evidence');
}

/// The typed next-step suggestions the review may make. Deliberately a
/// closed set of cautious, non-prescriptive training suggestions - never
/// medical advice, never a claimed proven cause.
enum SuggestedActionKind {
  maintainCurrentStructure,
  logMoreSessions,
  reviewRecoveryAndTechnique,
  considerVolumeReview,
  keepLoggingFeel,
}

/// One suggested action, always traceable to the evidence that produced it.
class SuggestedAction {
  final SuggestedActionKind kind;

  /// The exercise the suggestion concerns; null for whole-week suggestions.
  final String? exercise;

  /// Never empty: an action without evidence must not be produced.
  final List<EvidenceItem> evidence;

  const SuggestedAction({
    required this.kind,
    this.exercise,
    required this.evidence,
  }) : assert(evidence.length > 0, 'an action requires evidence');
}

/// Session-feel (1-5 stars) summary. Feel is rated per WORKOUT, so it is
/// session-wide context - never exercise-specific. Weekly averages require
/// a documented minimum of rated sessions; too-sparse data surfaces as
/// [MetricUnavailable], never as an invented trend.
class FeelSummary {
  final int ratedThisWeek;
  final int ratedPreviousWeek;

  /// Mean rating, unavailable(noData/tooFewSessions) below the minimum.
  final MetricResult<double> averageThisWeek;
  final MetricResult<double> averagePreviousWeek;

  const FeelSummary({
    required this.ratedThisWeek,
    required this.ratedPreviousWeek,
    required this.averageThisWeek,
    required this.averagePreviousWeek,
  });
}

/// The complete typed weekly review payload.
class WeeklyReview {
  /// The Monday-Sunday week under review (contains the reference date).
  final DatePeriod week;
  final DatePeriod previousWeek;

  final ReviewAvailability availability;

  /// Same total-history mapping as the dashboard (shared definition).
  final DataQuality dataQuality;

  final int workoutsThisWeek;
  final int workoutsPreviousWeek;
  final int totalWorkouts;

  /// Weekly volume (eligible sets only, kg) - identical definition to the
  /// dashboard's weekly volume metric.
  final double volumeThisWeekKg;
  final double volumePreviousWeekKg;
  final MetricResult<PercentageChange> volumeChange;

  final FeelSummary feel;

  final List<ReviewFinding> improvements;
  final List<ReviewFinding> stable;
  final List<ReviewFinding> attention;
  final List<SuggestedAction> actions;

  /// Stored workout documents skipped as unreadable - partial data is never
  /// silent.
  final int skippedRecords;

  const WeeklyReview({
    required this.week,
    required this.previousWeek,
    required this.availability,
    required this.dataQuality,
    required this.workoutsThisWeek,
    required this.workoutsPreviousWeek,
    required this.totalWorkouts,
    required this.volumeThisWeekKg,
    required this.volumePreviousWeekKg,
    required this.volumeChange,
    required this.feel,
    required this.improvements,
    required this.stable,
    required this.attention,
    required this.actions,
    required this.skippedRecords,
  });
}

/// Narrated copy for one review. The finding/action lists are PARALLEL to
/// the corresponding [WeeklyReview] lists (same length, same order) so the
/// UI can pair each sentence with its typed severity and evidence.
class ReviewNarration {
  final String headline;
  final String summary;
  final List<String> improvements;
  final List<String> stable;
  final List<String> attention;
  final List<String> actions;

  const ReviewNarration({
    required this.headline,
    required this.summary,
    required this.improvements,
    required this.stable,
    required this.attention,
    required this.actions,
  });
}
