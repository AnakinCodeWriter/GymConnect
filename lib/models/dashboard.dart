// Typed dashboard domain (Phase 6). Pure Dart: no Flutter, Firebase or
// prose - user-facing wording is built by the dashboard UI from these typed
// values. Metric definitions: docs/ANALYTICS_DEFINITIONS.md.

import 'analytics.dart';

/// Workouts completed in the current and previous Monday-Sunday weeks.
class WeeklyActivity {
  final int thisWeek;
  final int previousWeek;

  const WeeklyActivity({required this.thisWeek, required this.previousWeek});

  int get change => thisWeek - previousWeek;
}

/// Training volume (eligible sets only, kg) for the current and previous
/// Monday-Sunday weeks, with a safe week-over-week change.
class WeeklyVolume {
  final double thisWeekKg;
  final double previousWeekKg;

  /// Unavailable(noData) when the previous week had no workouts;
  /// unavailable(zeroBaseline) when it had workouts but zero volume.
  final MetricResult<PercentageChange> change;

  const WeeklyVolume({
    required this.thisWeekKg,
    required this.previousWeekKg,
    required this.change,
  });
}

/// One frequently trained exercise over the recent period (28 days):
/// [workoutCount] = number of workouts containing it (a workout counts once
/// even with duplicate same-named entries).
class TopExercise {
  final String name;
  final int workoutCount;

  const TopExercise({required this.name, required this.workoutCount});
}

/// A personal record set within the recent period (14 days): the day's best
/// eligible e1RM strictly exceeded every earlier session's best for that
/// exercise. A first-ever session is not a record.
class RecentPersonalRecord {
  final String exercise;
  final double e1RmKg;
  final DateTime day;

  const RecentPersonalRecord({
    required this.exercise,
    required this.e1RmKg,
    required this.day,
  });
}

enum TrendConcern { plateau, regression }

/// An evidence-backed concern for one analysed exercise. Presented as a
/// POSSIBLE plateau/regression - never as certainty or medical advice.
class TrendWarning {
  final String exercise;
  final TrendConcern concern;

  /// Evidence: how many sessions the trend is based on.
  final int sessionCount;

  /// Evidence: raw e1RM slope in kg/day from the trend regression.
  final double slopeKgPerDay;

  const TrendWarning({
    required this.exercise,
    required this.concern,
    required this.sessionCount,
    required this.slopeKgPerDay,
  });
}

/// Deterministic overall status; rules in docs/ANALYTICS_DEFINITIONS.md.
enum TrainingStatus {
  noData,
  gettingStarted,
  possibleRegression,
  possiblePlateau,
  progressing,
  activeWeek,
  needsMoreData,
}

/// The complete typed dashboard payload.
class DashboardData {
  final DatePeriod currentWeek;
  final WeeklyActivity activity;
  final WeeklyVolume volume;
  final List<TopExercise> topExercises;
  final List<RecentPersonalRecord> recentPersonalRecords;
  final List<TrendWarning> trendWarnings;

  /// Analysed exercises whose e1RM trend is progressing (evidence for the
  /// [TrainingStatus.progressing] status).
  final List<String> progressingExercises;

  final TrainingStatus status;
  final DataQuality dataQuality;

  /// Number of stored workout documents skipped as unreadable - surfaced so
  /// partial data is never silent.
  final int skippedRecords;

  const DashboardData({
    required this.currentWeek,
    required this.activity,
    required this.volume,
    required this.topExercises,
    required this.recentPersonalRecords,
    required this.trendWarnings,
    required this.progressingExercises,
    required this.status,
    required this.dataQuality,
    required this.skippedRecords,
  });
}
