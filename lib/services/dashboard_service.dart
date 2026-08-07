import '../models/analytics.dart';
import '../models/dashboard.dart';
import '../models/workout_model.dart';
import '../utils/fitness_formulas.dart';
import 'exercise_analytics_service.dart';
import 'plateau_detector.dart';

/// Pure, deterministic dashboard analytics (Phase 6). Accepts loaded domain
/// data and an injected reference date; never reads the wall clock, Firebase
/// or UI state. Metric definitions: docs/ANALYTICS_DEFINITIONS.md.
class DashboardService {
  /// Days covered by the "top exercises" ranking.
  static const int topExercisesWindowDays = 28;

  /// Days covered by "recent personal records".
  static const int recentPrWindowDays = 14;

  /// Maximum exercises analysed for trend warnings (the top exercises).
  static const int maxAnalysedExercises = 3;

  /// Maximum recent PRs reported.
  static const int maxRecentPrs = 5;

  static DashboardData build(
    List<WorkoutModel> workouts, {
    required DateTime referenceDate,
    int skippedRecords = 0,
  }) {
    final currentWeek = DatePeriod.weekContaining(referenceDate);
    final previousWeek = currentWeek.previousWeek;

    final activity = WeeklyActivity(
      thisWeek: _workoutsIn(workouts, currentWeek).length,
      previousWeek: _workoutsIn(workouts, previousWeek).length,
    );

    final volume = _weeklyVolume(workouts, currentWeek, previousWeek);

    final topExercises = _topExercises(
      workouts,
      DatePeriod.lastDays(topExercisesWindowDays, endingOn: referenceDate),
    );

    final recentPrs = personalRecordsIn(
      workouts,
      DatePeriod.lastDays(recentPrWindowDays, endingOn: referenceDate),
    );

    final warnings = <TrendWarning>[];
    final progressing = <String>[];
    for (final top in topExercises.take(maxAnalysedExercises)) {
      final series = ExerciseAnalyticsService.buildSeries(workouts, top.name);
      final trend = ExerciseAnalyticsService.e1RmTrend(series);
      switch (trend.status) {
        case PlateauStatus.progressing:
          progressing.add(top.name);
        case PlateauStatus.plateau || PlateauStatus.regressing:
          // Rising volume is not a true stall - same suppression rule as
          // the progress screen's banner.
          final volumeRising =
              ExerciseAnalyticsService.volumeTrend(series).status ==
              PlateauStatus.progressing;
          if (!volumeRising) {
            warnings.add(
              TrendWarning(
                exercise: top.name,
                concern: trend.status == PlateauStatus.plateau
                    ? TrendConcern.plateau
                    : TrendConcern.regression,
                sessionCount: series.sessions.length,
                slopeKgPerDay: trend.slope,
              ),
            );
          }
        case PlateauStatus.insufficientData:
          break; // not enough data is NOT a concern
      }
    }

    return DashboardData(
      currentWeek: currentWeek,
      activity: activity,
      volume: volume,
      topExercises: topExercises,
      recentPersonalRecords: recentPrs,
      trendWarnings: warnings,
      progressingExercises: progressing,
      status: _status(
        totalWorkouts: workouts.length,
        workoutsThisWeek: activity.thisWeek,
        warnings: warnings,
        progressing: progressing,
      ),
      dataQuality: _dataQuality(workouts.length),
      skippedRecords: skippedRecords,
    );
  }

  static List<WorkoutModel> _workoutsIn(
    List<WorkoutModel> workouts,
    DatePeriod period,
  ) => [
    for (final w in workouts)
      if (period.contains(w.date.toDate())) w,
  ];

  // Weekly volume: eligible sets only (warm-ups/malformed excluded - the
  // project-wide Phase 3 volume convention). Zero-volume workouts count
  // toward activity but contribute 0 here.
  static double _volumeIn(List<WorkoutModel> workouts, DatePeriod period) {
    double total = 0;
    for (final w in _workoutsIn(workouts, period)) {
      for (final ex in w.exercises) {
        for (final s in ex.sets) {
          if (isEligibleForStrengthAnalytics(s)) total += s.weight * s.reps;
        }
      }
    }
    return total;
  }

  static WeeklyVolume _weeklyVolume(
    List<WorkoutModel> workouts,
    DatePeriod currentWeek,
    DatePeriod previousWeek,
  ) {
    final thisWeekKg = _volumeIn(workouts, currentWeek);
    final previousWeekKg = _volumeIn(workouts, previousWeek);
    final previousCount = _workoutsIn(workouts, previousWeek).length;

    final MetricResult<PercentageChange> change;
    if (previousCount == 0) {
      change = const MetricUnavailable(InsufficiencyReason.noData);
    } else if (previousWeekKg == 0) {
      change = const MetricUnavailable(InsufficiencyReason.zeroBaseline);
    } else {
      change = MetricAvailable(
        PercentageChange(
          percent: (thisWeekKg - previousWeekKg) / previousWeekKg * 100,
          baselineValue: previousWeekKg,
          currentValue: thisWeekKg,
          baselinePeriod: previousWeek,
          currentPeriod: currentWeek,
        ),
      );
    }
    return WeeklyVolume(
      thisWeekKg: thisWeekKg,
      previousWeekKg: previousWeekKg,
      change: change,
    );
  }

  // Distinct exercises per workout over the period, ranked by workout count
  // descending with name-ascending tie-breaking (stable), top 3.
  static List<TopExercise> _topExercises(
    List<WorkoutModel> workouts,
    DatePeriod period,
  ) {
    final counts = <String, int>{};
    for (final w in _workoutsIn(workouts, period)) {
      final namesInWorkout = <String>{
        for (final ex in w.exercises)
          if (ex.name.trim().isNotEmpty) ex.name.trim(),
      };
      for (final name in namesInWorkout) {
        counts[name] = (counts[name] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return [
      for (final e in entries.take(3))
        TopExercise(name: e.key, workoutCount: e.value),
    ];
  }

  /// A PR: a day inside [period] whose best eligible e1RM strictly exceeds
  /// every EARLIER session's best for that exercise (earlier days inside the
  /// period count as "earlier" too). First-ever sessions are not records.
  /// Best qualifying day per exercise; newest first, name-ascending
  /// tie-break; capped at [maxRecords]. Public since Phase 8: the weekly
  /// review shares this exact definition over the review week.
  static List<RecentPersonalRecord> personalRecordsIn(
    List<WorkoutModel> workouts,
    DatePeriod period, {
    int maxRecords = maxRecentPrs,
  }) {
    // Only exercises trained inside the period can hold a recent PR.
    final candidates = <String>{};
    for (final w in _workoutsIn(workouts, period)) {
      for (final ex in w.exercises) {
        if (ex.name.trim().isNotEmpty) candidates.add(ex.name.trim());
      }
    }

    final records = <RecentPersonalRecord>[];
    for (final name in candidates) {
      final sessions = ExerciseAnalyticsService.buildSeries(
        workouts,
        name,
      ).sessions;
      RecentPersonalRecord? best;
      double priorMax = 0;
      var hasPrior = false;
      for (final s in sessions) {
        // sessions are ascending by day
        if (period.contains(s.day) && hasPrior && s.bestE1RmKg > priorMax) {
          if (best == null ||
              s.bestE1RmKg > best.e1RmKg ||
              (s.bestE1RmKg == best.e1RmKg && s.day.isAfter(best.day))) {
            best = RecentPersonalRecord(
              exercise: name,
              e1RmKg: s.bestE1RmKg,
              day: s.day,
            );
          }
        }
        if (s.bestE1RmKg > priorMax) priorMax = s.bestE1RmKg;
        hasPrior = true;
      }
      if (best != null) records.add(best);
    }

    records.sort((a, b) {
      final byDay = b.day.compareTo(a.day);
      return byDay != 0 ? byDay : a.exercise.compareTo(b.exercise);
    });
    return records.take(maxRecords).toList();
  }

  // Deterministic status rules, priority order (documented):
  // noData -> gettingStarted -> possibleRegression -> possiblePlateau ->
  // progressing -> activeWeek -> needsMoreData.
  static TrainingStatus _status({
    required int totalWorkouts,
    required int workoutsThisWeek,
    required List<TrendWarning> warnings,
    required List<String> progressing,
  }) {
    if (totalWorkouts == 0) return TrainingStatus.noData;
    if (totalWorkouts < 5) return TrainingStatus.gettingStarted;
    if (warnings.any((w) => w.concern == TrendConcern.regression)) {
      return TrainingStatus.possibleRegression;
    }
    if (warnings.any((w) => w.concern == TrendConcern.plateau)) {
      return TrainingStatus.possiblePlateau;
    }
    if (progressing.isNotEmpty) return TrainingStatus.progressing;
    if (workoutsThisWeek > 0) return TrainingStatus.activeWeek;
    return TrainingStatus.needsMoreData;
  }

  // Categorical data quality from history size (documented mapping).
  static DataQuality _dataQuality(int totalWorkouts) {
    if (totalWorkouts == 0) return DataQuality.insufficient;
    if (totalWorkouts < 5) return DataQuality.limited;
    if (totalWorkouts < 15) return DataQuality.moderate;
    return DataQuality.strong;
  }
}
