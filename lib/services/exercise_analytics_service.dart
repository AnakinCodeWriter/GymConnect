import 'dart:math';

import '../models/analytics.dart';
import '../models/exercise_detail.dart';
import '../models/workout_model.dart';
import '../utils/fitness_formulas.dart';
import 'plateau_detector.dart';
import 'plateau_diagnosis_service.dart';

/// Which per-session value a period comparison aggregates.
enum SessionMetric {
  /// Best e1RM: aggregated with max over the period.
  bestE1Rm,

  /// Session volume: aggregated with sum over the period.
  sessionVolume,
}

/// Pure, deterministic per-exercise analytics. Extracted from
/// progress_screen.dart in Phase 2; metric definitions live in
/// docs/ANALYTICS_DEFINITIONS.md.
///
/// No Firebase, widgets or presentation strings. Time windows are always
/// explicit [DatePeriod]s built by the caller (who injects "today"), so no
/// calculation here reads the wall clock.
class ExerciseAnalyticsService {
  /// Builds the per-calendar-day session series for [exerciseName].
  ///
  /// - Matching: trim + case-insensitive EXACT name equality. (The previous
  ///   in-screen implementation substring-matched the e1RM series, letting
  ///   "Incline Bench Press" pollute "Bench Press" - fixed here.)
  /// - All matching entries in a workout are counted, including duplicate
  ///   same-named entries (the old volume path stopped at the first).
  /// - Warm-up sets are excluded. Malformed sets (weight < 0 or reps < 1)
  ///   are ignored so invalid records cannot distort valid analytics;
  ///   zero weight is a valid value. A day with no valid working sets
  ///   produces no session.
  /// - Workouts on the same local calendar day merge into one session:
  ///   best e1RM = max, volume = sum. Sessions are returned ascending by
  ///   day, which makes ordering deterministic (days are unique).
  static ExerciseSeries buildSeries(
    List<WorkoutModel> workouts,
    String exerciseName,
  ) {
    final target = exerciseName.trim().toLowerCase();
    final best = <DateTime, double>{};
    final volume = <DateTime, double>{};
    final setCount = <DateTime, int>{};

    for (final workout in workouts) {
      final day = dateOnly(workout.date.toDate());
      for (final exercise in workout.exercises) {
        if (exercise.name.trim().toLowerCase() != target) continue;
        for (final set in exercise.sets) {
          // shared eligibility rule (Phase 3): excludes warm-ups and
          // malformed sets (negative/non-finite weight, reps < 1).
          if (!isEligibleForStrengthAnalytics(set)) continue;
          final e1rm = estimatedOneRepMax(set.weight, set.reps);
          best[day] = max(best[day] ?? 0, e1rm);
          volume[day] = (volume[day] ?? 0) + set.weight * set.reps;
          setCount[day] = (setCount[day] ?? 0) + 1;
        }
      }
    }

    final days = best.keys.toList()..sort();
    return ExerciseSeries(
      exerciseName: exerciseName.trim(),
      sessions: [
        for (final day in days)
          ExerciseSession(
            day: day,
            bestE1RmKg: best[day]!,
            volumeKg: volume[day]!,
            workingSetCount: setCount[day]!,
          ),
      ],
    );
  }

  /// Strength trend: WLS regression over (day, best e1RM) via
  /// [PlateauDetector] (>= 5 sessions, +/-0.1%/day thresholds).
  static PlateauResult e1RmTrend(ExerciseSeries series) {
    return PlateauDetector.analyse([
      for (final s in series.sessions) (s.day, s.bestE1RmKg),
    ]);
  }

  /// Volume trend over (day, session volume). Zero-volume sessions are
  /// excluded, preserving the pre-extraction behaviour of the progress
  /// screen's volume series.
  static PlateauResult volumeTrend(ExerciseSeries series) {
    return PlateauDetector.analyse([
      for (final s in series.sessions)
        if (s.volumeKg > 0) (s.day, s.volumeKg),
    ]);
  }

  /// Average sessions per week within [period]: sessions in period divided
  /// by period length in weeks (dayCount / 7). Zero sessions inside the
  /// period is a genuine 0 when the exercise has any history at all;
  /// an entirely empty series is unavailable.
  static MetricResult<double> trainingFrequencyPerWeek(
    ExerciseSeries series,
    DatePeriod period,
  ) {
    if (series.isEmpty) {
      return const MetricUnavailable(InsufficiencyReason.noData);
    }
    final count = series.sessions.where((s) => period.contains(s.day)).length;
    return MetricAvailable(count / (period.dayCount / 7));
  }

  /// Best e1RM among sessions within [period]; unavailable when the period
  /// contains no sessions.
  static MetricResult<double> bestE1RmIn(
    ExerciseSeries series,
    DatePeriod period,
  ) {
    double? bestVal;
    for (final s in series.sessions) {
      if (!period.contains(s.day)) continue;
      if (bestVal == null || s.bestE1RmKg > bestVal) bestVal = s.bestE1RmKg;
    }
    if (bestVal == null) {
      return const MetricUnavailable(InsufficiencyReason.noData);
    }
    return MetricAvailable(bestVal);
  }

  /// Percentage change of [metric] between two explicit periods.
  /// bestE1Rm compares the max per period; sessionVolume compares the sum.
  ///
  /// - Either period without sessions -> unavailable(noData).
  /// - Baseline aggregate of exactly 0 -> unavailable(zeroBaseline); an
  ///   undefined change is never reported as 0% or infinity.
  /// - Current 0 against a positive baseline is a genuine -100%.
  static MetricResult<PercentageChange> percentageChange(
    ExerciseSeries series, {
    required SessionMetric metric,
    required DatePeriod baseline,
    required DatePeriod current,
  }) {
    final baselineValue = _aggregate(series, metric, baseline);
    final currentValue = _aggregate(series, metric, current);
    if (baselineValue == null || currentValue == null) {
      return const MetricUnavailable(InsufficiencyReason.noData);
    }
    if (baselineValue == 0) {
      return const MetricUnavailable(InsufficiencyReason.zeroBaseline);
    }
    return MetricAvailable(
      PercentageChange(
        percent: (currentValue - baselineValue) / baselineValue * 100,
        baselineValue: baselineValue,
        currentValue: currentValue,
        baselinePeriod: baseline,
        currentPeriod: current,
      ),
    );
  }

  /// Days covered by the Progress screen's "recent" window (Phase 7); the
  /// comparison baseline is the [detailWindowDays] before it.
  static const int detailWindowDays = 28;

  /// Full typed per-exercise analysis for the Progress screen (Phase 7).
  /// Deterministic: all recency windows derive from [referenceDate].
  /// Definitions: docs/ANALYTICS_DEFINITIONS.md.
  static ExerciseDetail analyseExercise(
    List<WorkoutModel> workouts,
    String exerciseName, {
    required DateTime referenceDate,
  }) {
    final series = buildSeries(workouts, exerciseName);
    final recent = DatePeriod.lastDays(
      detailWindowDays,
      endingOn: referenceDate,
    );
    final baseline = DatePeriod.lastDays(
      detailWindowDays,
      endingOn: DateTime(
        recent.start.year,
        recent.start.month,
        recent.start.day - 1,
      ),
    );

    final strengthTrend = e1RmTrend(series);
    final volumeTrendResult = volumeTrend(series);
    final concerning =
        strengthTrend.status == PlateauStatus.plateau ||
        strengthTrend.status == PlateauStatus.regressing;
    final suppressed =
        concerning && volumeTrendResult.status == PlateauStatus.progressing;

    // Recent best + the (latest) day it was achieved.
    MetricResult<RecentBest> recentBest = const MetricUnavailable(
      InsufficiencyReason.noData,
    );
    for (final s in series.sessions) {
      if (!recent.contains(s.day)) continue;
      final current = recentBest.valueOrNull;
      if (current == null || s.bestE1RmKg >= current.e1RmKg) {
        recentBest = MetricAvailable(
          RecentBest(e1RmKg: s.bestE1RmKg, day: s.day),
        );
      }
    }

    final strengthChange = percentageChange(
      series,
      metric: SessionMetric.bestE1Rm,
      baseline: baseline,
      current: recent,
    );
    final volumeChange = percentageChange(
      series,
      metric: SessionMetric.sessionVolume,
      baseline: baseline,
      current: recent,
    );
    final frequency = trainingFrequencyPerWeek(series, recent);
    final sessionsInWindow = series.sessions
        .where((s) => recent.contains(s.day))
        .length;
    final totalSessions = series.sessions.length;

    final evidence = <EvidenceItem>[
      EvidenceItem(
        metric: MetricType.workoutCount,
        observedValue: totalSessions.toDouble(),
        comparisonValue: PlateauDetector.minSessions.toDouble(),
        dataSufficient: totalSessions >= PlateauDetector.minSessions,
      ),
      if (strengthChange.valueOrNull != null)
        EvidenceItem(
          metric: MetricType.estimatedOneRepMax,
          observedValue: strengthChange.valueOrNull!.currentValue,
          comparisonValue: strengthChange.valueOrNull!.baselineValue,
          period: recent,
        ),
      if (volumeChange.valueOrNull != null)
        EvidenceItem(
          metric: MetricType.sessionVolume,
          observedValue: volumeChange.valueOrNull!.currentValue,
          comparisonValue: volumeChange.valueOrNull!.baselineValue,
          period: recent,
        ),
      if (frequency.valueOrNull != null)
        EvidenceItem(
          metric: MetricType.trainingFrequency,
          observedValue: frequency.valueOrNull,
          period: recent,
        ),
    ];

    return ExerciseDetail(
      exerciseName: series.exerciseName,
      series: series,
      strengthStatus: strengthTrend.status,
      strengthSlopeKgPerDay: strengthTrend.slope,
      volumeStatus: volumeTrendResult.status,
      volumeProgressionSuppressed: suppressed,
      recentBest: recentBest,
      strengthChange: strengthChange,
      volumeChange: volumeChange,
      sessionsPerWeek: frequency,
      sessionsInWindow: sessionsInWindow,
      totalSessions: totalSessions,
      dataQuality: _detailQuality(totalSessions),
      evidence: evidence,
      possibleExplanation: concerning && !suppressed
          ? PlateauDiagnosisService.analyse(
              workouts,
              series.exerciseName,
              referenceDate: referenceDate,
            )
          : null,
    );
  }

  // Per-exercise data quality (documented): 0 -> insufficient; below the
  // 5-session trend minimum -> limited; 5-9 -> moderate; >= 10 -> strong.
  static DataQuality _detailQuality(int totalSessions) {
    if (totalSessions == 0) return DataQuality.insufficient;
    if (totalSessions < PlateauDetector.minSessions) return DataQuality.limited;
    if (totalSessions < 10) return DataQuality.moderate;
    return DataQuality.strong;
  }

  /// Aggregate of [metric] over sessions in [period]; null when the period
  /// contains no sessions (distinct from a genuine zero aggregate).
  static double? _aggregate(
    ExerciseSeries series,
    SessionMetric metric,
    DatePeriod period,
  ) {
    final inPeriod = series.sessions
        .where((s) => period.contains(s.day))
        .toList();
    if (inPeriod.isEmpty) return null;
    switch (metric) {
      case SessionMetric.bestE1Rm:
        return inPeriod.map((s) => s.bestE1RmKg).reduce(max);
      case SessionMetric.sessionVolume:
        return inPeriod
            .map((s) => s.volumeKg)
            .fold<double>(0.0, (sum, v) => sum + v);
    }
  }
}
