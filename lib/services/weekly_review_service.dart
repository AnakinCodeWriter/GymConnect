import '../models/analytics.dart';
import '../models/dashboard.dart';
import '../models/weekly_review.dart';
import '../models/workout_model.dart';
import 'dashboard_service.dart';
import 'exercise_analytics_service.dart';
import 'plateau_detector.dart';

/// Pure, deterministic weekly review analytics (Phase 8). Accepts loaded
/// domain data and an injected reference date; never reads the wall clock,
/// Firebase or UI state, and never calls an external API.
///
/// Shared definitions (docs/ANALYTICS_DEFINITIONS.md): the review reuses
/// DashboardService for weekly activity/volume, top exercises, personal
/// records and data quality, and ExerciseAnalyticsService/PlateauDetector
/// for trends - a metric never has two competing definitions.
///
/// Every finding and suggested action carries structured evidence; nothing
/// here fabricates values, invents causes or makes medical claims.
class WeeklyReviewService {
  /// Volume week-over-week changes within +/- this band are "stable";
  /// beyond it they become an improvement or an attention finding.
  static const double volumeStableBandPercent = 10;

  /// Feel averages must differ by at least this many stars (of 5) before
  /// the review calls the change improving/declining.
  static const double feelChangeThresholdStars = 0.5;

  /// A weekly feel average at or below this is flagged as a low-feel week.
  static const double lowFeelThresholdStars = 2.5;

  /// Minimum rated sessions in a week before a feel average is reported.
  static const int minRatedSessionsForFeelAverage = 2;

  /// Total workouts below this leave trend-level conclusions unreliable
  /// (same boundary as the dashboard's getting-started status).
  static const int minHistoryForConclusions = 5;

  /// Personal-record findings reported per review (newest first).
  static const int maxPersonalRecordFindings = 3;

  /// Exercises listed in the repeated-exercises stable finding.
  static const int maxRepeatedExercises = 3;

  static WeeklyReview build(
    List<WorkoutModel> workouts, {
    required DateTime referenceDate,
    int skippedRecords = 0,
  }) {
    // Shared weekly metrics: identical to what the dashboard shows.
    final dashboard = DashboardService.build(
      workouts,
      referenceDate: referenceDate,
      skippedRecords: skippedRecords,
    );
    final week = dashboard.currentWeek;
    final previousWeek = week.previousWeek;
    final totalWorkouts = workouts.length;

    final feel = _feelSummary(workouts, week, previousWeek);

    if (totalWorkouts == 0) {
      return WeeklyReview(
        week: week,
        previousWeek: previousWeek,
        availability: ReviewAvailability.noData,
        dataQuality: dashboard.dataQuality,
        workoutsThisWeek: 0,
        workoutsPreviousWeek: 0,
        totalWorkouts: 0,
        volumeThisWeekKg: 0,
        volumePreviousWeekKg: 0,
        volumeChange: dashboard.volume.change,
        feel: feel,
        improvements: const [],
        stable: const [],
        attention: const [],
        actions: const [],
        skippedRecords: skippedRecords,
      );
    }

    // Per-exercise trend classification for the dashboard's analysed (top)
    // exercises - the same series/trend/suppression calls the dashboard
    // makes, so both screens always agree.
    final progressingFindings = <ReviewFinding>[];
    final volumeRisingFindings = <ReviewFinding>[];
    final regressionFindings = <ReviewFinding>[];
    final plateauFindings = <ReviewFinding>[];
    for (final top in dashboard.topExercises) {
      final series = ExerciseAnalyticsService.buildSeries(workouts, top.name);
      final trend = ExerciseAnalyticsService.e1RmTrend(series);
      if (trend.status == PlateauStatus.insufficientData) continue;

      final sessionEvidence = EvidenceItem(
        metric: MetricType.workoutCount,
        observedValue: series.sessions.length.toDouble(),
        comparisonValue: PlateauDetector.minSessions.toDouble(),
      );
      switch (trend.status) {
        case PlateauStatus.progressing:
          progressingFindings.add(
            ReviewFinding(
              kind: ReviewFindingKind.exerciseProgressing,
              severity: Severity.info,
              exercise: top.name,
              observedValue: trend.slope, // kg/day
              evidence: [sessionEvidence],
            ),
          );
        case PlateauStatus.plateau || PlateauStatus.regressing:
          final volumeRising =
              ExerciseAnalyticsService.volumeTrend(series).status ==
              PlateauStatus.progressing;
          if (volumeRising) {
            // Suppression rule shared with dashboard/Progress: rising
            // volume means the flat e1RM is not treated as a concern.
            volumeRisingFindings.add(
              ReviewFinding(
                kind: ReviewFindingKind.exerciseVolumeRising,
                severity: Severity.info,
                exercise: top.name,
                observedValue: trend.slope,
                evidence: [sessionEvidence],
              ),
            );
          } else if (trend.status == PlateauStatus.regressing) {
            regressionFindings.add(
              ReviewFinding(
                kind: ReviewFindingKind.possibleRegression,
                severity: Severity.warning,
                exercise: top.name,
                observedValue: trend.slope,
                evidence: [sessionEvidence],
              ),
            );
          } else {
            plateauFindings.add(
              ReviewFinding(
                kind: ReviewFindingKind.possiblePlateau,
                severity: Severity.caution,
                exercise: top.name,
                observedValue: trend.slope,
                evidence: [sessionEvidence],
              ),
            );
          }
        case PlateauStatus.insufficientData:
          break; // unreachable (filtered above)
      }
    }

    final improvements = _improvements(
      dashboard: dashboard,
      workouts: workouts,
      week: week,
      feel: feel,
      progressingFindings: progressingFindings,
    );
    final stable = _stable(
      dashboard: dashboard,
      workouts: workouts,
      week: week,
      previousWeek: previousWeek,
      feel: feel,
      volumeRisingFindings: volumeRisingFindings,
    );
    final attention = _attention(
      dashboard: dashboard,
      totalWorkouts: totalWorkouts,
      week: week,
      feel: feel,
      regressionFindings: regressionFindings,
      plateauFindings: plateauFindings,
      skippedRecords: skippedRecords,
    );
    final actions = _actions(
      improvements: improvements,
      attention: attention,
      workoutsThisWeek: dashboard.activity.thisWeek,
      totalWorkouts: totalWorkouts,
      week: week,
      feel: feel,
    );

    return WeeklyReview(
      week: week,
      previousWeek: previousWeek,
      availability: ReviewAvailability.available,
      dataQuality: dashboard.dataQuality,
      workoutsThisWeek: dashboard.activity.thisWeek,
      workoutsPreviousWeek: dashboard.activity.previousWeek,
      totalWorkouts: totalWorkouts,
      volumeThisWeekKg: dashboard.volume.thisWeekKg,
      volumePreviousWeekKg: dashboard.volume.previousWeekKg,
      volumeChange: dashboard.volume.change,
      feel: feel,
      improvements: improvements,
      stable: stable,
      attention: attention,
      actions: actions,
      skippedRecords: skippedRecords,
    );
  }

  // ---- sections (fixed, documented order within each) ----

  static List<ReviewFinding> _improvements({
    required DashboardData dashboard,
    required List<WorkoutModel> workouts,
    required DatePeriod week,
    required FeelSummary feel,
    required List<ReviewFinding> progressingFindings,
  }) {
    final activity = dashboard.activity;
    final findings = <ReviewFinding>[];

    // 1. More workouts than the previous week (a comparison needs a
    //    non-empty previous week - a first-ever week is not "up").
    if (activity.previousWeek > 0 &&
        activity.thisWeek > activity.previousWeek) {
      findings.add(
        ReviewFinding(
          kind: ReviewFindingKind.workoutCountIncreased,
          severity: Severity.info,
          observedValue: activity.thisWeek.toDouble(),
          comparisonValue: activity.previousWeek.toDouble(),
          period: week,
          evidence: [_activityEvidence(activity, week)],
        ),
      );
    }

    // 2. Weekly volume up beyond the stable band.
    final volumeChange = dashboard.volume.change.valueOrNull;
    if (volumeChange != null &&
        volumeChange.percent > volumeStableBandPercent) {
      findings.add(
        ReviewFinding(
          kind: ReviewFindingKind.volumeIncreased,
          severity: Severity.info,
          observedValue: dashboard.volume.thisWeekKg,
          comparisonValue: dashboard.volume.previousWeekKg,
          period: week,
          evidence: [_volumeEvidence(dashboard.volume, week)],
        ),
      );
    }

    // 3. Personal records inside the review week (shared PR definition;
    //    a first-ever session is never a record, warm-ups never count).
    for (final pr in DashboardService.personalRecordsIn(
      workouts,
      week,
      maxRecords: maxPersonalRecordFindings,
    )) {
      findings.add(
        ReviewFinding(
          kind: ReviewFindingKind.newPersonalRecord,
          severity: Severity.info,
          exercise: pr.exercise,
          observedValue: pr.e1RmKg,
          period: week,
          evidence: [
            EvidenceItem(
              metric: MetricType.estimatedOneRepMax,
              observedValue: pr.e1RmKg,
              period: week,
            ),
          ],
        ),
      );
    }

    // 4. Progressing exercise trends (analysed exercises).
    findings.addAll(progressingFindings);

    // 5. Feel improved (both weekly averages must be reportable).
    final thisAvg = feel.averageThisWeek.valueOrNull;
    final prevAvg = feel.averagePreviousWeek.valueOrNull;
    if (thisAvg != null &&
        prevAvg != null &&
        thisAvg - prevAvg >= feelChangeThresholdStars) {
      findings.add(
        ReviewFinding(
          kind: ReviewFindingKind.feelImproved,
          severity: Severity.info,
          observedValue: thisAvg,
          comparisonValue: prevAvg,
          period: week,
          evidence: [_feelEvidence(thisAvg, prevAvg, week)],
        ),
      );
    }

    return findings;
  }

  static List<ReviewFinding> _stable({
    required DashboardData dashboard,
    required List<WorkoutModel> workouts,
    required DatePeriod week,
    required DatePeriod previousWeek,
    required FeelSummary feel,
    required List<ReviewFinding> volumeRisingFindings,
  }) {
    final activity = dashboard.activity;
    final findings = <ReviewFinding>[];

    // 1. Same workout count as last week (both weeks trained).
    if (activity.thisWeek > 0 && activity.thisWeek == activity.previousWeek) {
      findings.add(
        ReviewFinding(
          kind: ReviewFindingKind.workoutCountStable,
          severity: Severity.info,
          observedValue: activity.thisWeek.toDouble(),
          comparisonValue: activity.previousWeek.toDouble(),
          period: week,
          evidence: [_activityEvidence(activity, week)],
        ),
      );
    }

    // 2. Weekly volume within the stable band.
    final volumeChange = dashboard.volume.change.valueOrNull;
    if (volumeChange != null &&
        volumeChange.percent.abs() <= volumeStableBandPercent) {
      findings.add(
        ReviewFinding(
          kind: ReviewFindingKind.volumeStable,
          severity: Severity.info,
          observedValue: dashboard.volume.thisWeekKg,
          comparisonValue: dashboard.volume.previousWeekKg,
          period: week,
          evidence: [_volumeEvidence(dashboard.volume, week)],
        ),
      );
    }

    // 3. Flat e1RM with rising volume (suppressed concerns).
    findings.addAll(volumeRisingFindings);

    // 4. Exercises trained in both weeks (consistency).
    final repeated = _repeatedExercises(workouts, week, previousWeek);
    if (repeated.isNotEmpty) {
      findings.add(
        ReviewFinding(
          kind: ReviewFindingKind.repeatedExercises,
          severity: Severity.info,
          exercises: repeated,
          observedValue: repeated.length.toDouble(),
          period: week,
          evidence: [
            EvidenceItem(
              metric: MetricType.workoutCount,
              observedValue: repeated.length.toDouble(),
              period: week,
            ),
          ],
        ),
      );
    }

    // 5. Feel stable (both averages reportable, change inside threshold).
    final thisAvg = feel.averageThisWeek.valueOrNull;
    final prevAvg = feel.averagePreviousWeek.valueOrNull;
    if (thisAvg != null &&
        prevAvg != null &&
        (thisAvg - prevAvg).abs() < feelChangeThresholdStars) {
      findings.add(
        ReviewFinding(
          kind: ReviewFindingKind.feelStable,
          severity: Severity.info,
          observedValue: thisAvg,
          comparisonValue: prevAvg,
          period: week,
          evidence: [_feelEvidence(thisAvg, prevAvg, week)],
        ),
      );
    }

    return findings;
  }

  static List<ReviewFinding> _attention({
    required DashboardData dashboard,
    required int totalWorkouts,
    required DatePeriod week,
    required FeelSummary feel,
    required List<ReviewFinding> regressionFindings,
    required List<ReviewFinding> plateauFindings,
    required int skippedRecords,
  }) {
    final activity = dashboard.activity;
    final findings = <ReviewFinding>[
      // 1./2. Possible regressions before possible plateaus.
      ...regressionFindings,
      ...plateauFindings,
    ];

    // 3. No training this week / fewer workouts than last week. A zero
    //    week reports only noTrainingThisWeek, not also "decreased".
    if (activity.thisWeek == 0) {
      findings.add(
        ReviewFinding(
          kind: ReviewFindingKind.noTrainingThisWeek,
          severity: Severity.caution,
          observedValue: 0,
          comparisonValue: activity.previousWeek.toDouble(),
          period: week,
          evidence: [_activityEvidence(activity, week)],
        ),
      );
    } else if (activity.previousWeek > 0 &&
        activity.thisWeek < activity.previousWeek) {
      findings.add(
        ReviewFinding(
          kind: ReviewFindingKind.workoutCountDecreased,
          severity: Severity.caution,
          observedValue: activity.thisWeek.toDouble(),
          comparisonValue: activity.previousWeek.toDouble(),
          period: week,
          evidence: [_activityEvidence(activity, week)],
        ),
      );
    }

    // 4. Weekly volume down beyond the stable band.
    final volumeChange = dashboard.volume.change.valueOrNull;
    if (volumeChange != null &&
        volumeChange.percent < -volumeStableBandPercent) {
      findings.add(
        ReviewFinding(
          kind: ReviewFindingKind.volumeDecreased,
          severity: Severity.caution,
          observedValue: dashboard.volume.thisWeekKg,
          comparisonValue: dashboard.volume.previousWeekKg,
          period: week,
          evidence: [_volumeEvidence(dashboard.volume, week)],
        ),
      );
    }

    // 5. Feel declined; a low-feel week is reported separately only when
    //    the decline finding didn't already cover it.
    final thisAvg = feel.averageThisWeek.valueOrNull;
    final prevAvg = feel.averagePreviousWeek.valueOrNull;
    final declined =
        thisAvg != null &&
        prevAvg != null &&
        prevAvg - thisAvg >= feelChangeThresholdStars;
    if (declined) {
      findings.add(
        ReviewFinding(
          kind: ReviewFindingKind.feelDeclined,
          severity: Severity.caution,
          observedValue: thisAvg,
          comparisonValue: prevAvg,
          period: week,
          evidence: [_feelEvidence(thisAvg, prevAvg, week)],
        ),
      );
    } else if (thisAvg != null && thisAvg <= lowFeelThresholdStars) {
      findings.add(
        ReviewFinding(
          kind: ReviewFindingKind.lowFeelWeek,
          severity: Severity.caution,
          observedValue: thisAvg,
          comparisonValue: lowFeelThresholdStars,
          period: week,
          evidence: [
            EvidenceItem(
              metric: MetricType.feelRating,
              observedValue: thisAvg,
              comparisonValue: lowFeelThresholdStars,
              period: week,
            ),
          ],
        ),
      );
    }

    // 6. Too little history for trend-level conclusions.
    if (totalWorkouts < minHistoryForConclusions) {
      findings.add(
        ReviewFinding(
          kind: ReviewFindingKind.insufficientHistory,
          severity: Severity.info,
          observedValue: totalWorkouts.toDouble(),
          comparisonValue: minHistoryForConclusions.toDouble(),
          evidence: [
            EvidenceItem(
              metric: MetricType.workoutCount,
              observedValue: totalWorkouts.toDouble(),
              comparisonValue: minHistoryForConclusions.toDouble(),
              dataSufficient: false,
            ),
          ],
        ),
      );
    }

    // 7. Unreadable stored records - partial data is never silent.
    if (skippedRecords > 0) {
      findings.add(
        ReviewFinding(
          kind: ReviewFindingKind.skippedRecords,
          severity: Severity.caution,
          observedValue: skippedRecords.toDouble(),
          evidence: [
            EvidenceItem(
              metric: MetricType.workoutCount,
              observedValue: skippedRecords.toDouble(),
              dataSufficient: false,
            ),
          ],
        ),
      );
    }

    return findings;
  }

  // Actions in fixed priority order. Every action inherits the evidence of
  // the finding(s) that triggered it - no finding, no action.
  static List<SuggestedAction> _actions({
    required List<ReviewFinding> improvements,
    required List<ReviewFinding> attention,
    required int workoutsThisWeek,
    required int totalWorkouts,
    required DatePeriod week,
    required FeelSummary feel,
  }) {
    final actions = <SuggestedAction>[];

    final regressions = attention
        .where((f) => f.kind == ReviewFindingKind.possibleRegression)
        .toList();
    final plateaus = attention
        .where((f) => f.kind == ReviewFindingKind.possiblePlateau)
        .toList();

    // 1. Possible regression -> cautiously suggest reviewing recovery and
    //    technique (a possibility to look into, never a proven cause).
    for (final f in regressions) {
      actions.add(
        SuggestedAction(
          kind: SuggestedActionKind.reviewRecoveryAndTechnique,
          exercise: f.exercise,
          evidence: f.evidence,
        ),
      );
    }

    // 2. Possible plateau -> volume worth reviewing. By construction the
    //    exercise's volume is not rising (rising volume suppresses the
    //    plateau finding entirely).
    for (final f in plateaus) {
      actions.add(
        SuggestedAction(
          kind: SuggestedActionKind.considerVolumeReview,
          exercise: f.exercise,
          evidence: f.evidence,
        ),
      );
    }

    // 3. Progress detected and no trend concerns -> keep the structure.
    final progressFindings = improvements
        .where(
          (f) =>
              f.kind == ReviewFindingKind.exerciseProgressing ||
              f.kind == ReviewFindingKind.newPersonalRecord,
        )
        .toList();
    if (progressFindings.isNotEmpty &&
        regressions.isEmpty &&
        plateaus.isEmpty) {
      actions.add(
        SuggestedAction(
          kind: SuggestedActionKind.maintainCurrentStructure,
          evidence: [for (final f in progressFindings) ...f.evidence],
        ),
      );
    }

    // 4. Too little history -> log more sessions before judging trends.
    if (totalWorkouts < minHistoryForConclusions) {
      actions.add(
        SuggestedAction(
          kind: SuggestedActionKind.logMoreSessions,
          evidence: [
            EvidenceItem(
              metric: MetricType.workoutCount,
              observedValue: totalWorkouts.toDouble(),
              comparisonValue: minHistoryForConclusions.toDouble(),
              dataSufficient: false,
            ),
          ],
        ),
      );
    }

    // 5. Trained this week but feel data too sparse for an average.
    if (workoutsThisWeek > 0 && !feel.averageThisWeek.isAvailable) {
      actions.add(
        SuggestedAction(
          kind: SuggestedActionKind.keepLoggingFeel,
          evidence: [
            EvidenceItem(
              metric: MetricType.feelRating,
              observedValue: feel.ratedThisWeek.toDouble(),
              comparisonValue: minRatedSessionsForFeelAverage.toDouble(),
              period: week,
              dataSufficient: false,
            ),
          ],
        ),
      );
    }

    return actions;
  }

  // ---- helpers ----

  static FeelSummary _feelSummary(
    List<WorkoutModel> workouts,
    DatePeriod week,
    DatePeriod previousWeek,
  ) {
    List<int> ratingsIn(DatePeriod period) => [
      for (final w in workouts)
        if (w.feelRating != null && period.contains(w.date.toDate()))
          w.feelRating!,
    ];

    MetricResult<double> average(List<int> ratings) {
      if (ratings.isEmpty) {
        return const MetricUnavailable(InsufficiencyReason.noData);
      }
      if (ratings.length < minRatedSessionsForFeelAverage) {
        return MetricUnavailable(
          InsufficiencyReason.tooFewSessions,
          observedCount: ratings.length,
          requiredCount: minRatedSessionsForFeelAverage,
        );
      }
      return MetricAvailable(ratings.reduce((a, b) => a + b) / ratings.length);
    }

    final thisWeek = ratingsIn(week);
    final prevWeek = ratingsIn(previousWeek);
    return FeelSummary(
      ratedThisWeek: thisWeek.length,
      ratedPreviousWeek: prevWeek.length,
      averageThisWeek: average(thisWeek),
      averagePreviousWeek: average(prevWeek),
    );
  }

  // Exercises trained in BOTH weeks (trim + case-insensitive match, first
  // display casing kept), name-ascending, capped for scannability.
  static List<String> _repeatedExercises(
    List<WorkoutModel> workouts,
    DatePeriod week,
    DatePeriod previousWeek,
  ) {
    Map<String, String> namesIn(DatePeriod period) {
      final names = <String, String>{};
      for (final w in workouts) {
        if (!period.contains(w.date.toDate())) continue;
        for (final ex in w.exercises) {
          final display = ex.name.trim();
          if (display.isEmpty) continue;
          names.putIfAbsent(display.toLowerCase(), () => display);
        }
      }
      return names;
    }

    final current = namesIn(week);
    final previous = namesIn(previousWeek);
    final repeated = [
      for (final e in current.entries)
        if (previous.containsKey(e.key)) e.value,
    ]..sort();
    return repeated.take(maxRepeatedExercises).toList();
  }

  static EvidenceItem _activityEvidence(WeeklyActivity a, DatePeriod week) =>
      EvidenceItem(
        metric: MetricType.workoutCount,
        observedValue: a.thisWeek.toDouble(),
        comparisonValue: a.previousWeek.toDouble(),
        period: week,
      );

  static EvidenceItem _volumeEvidence(WeeklyVolume v, DatePeriod week) =>
      EvidenceItem(
        metric: MetricType.sessionVolume,
        observedValue: v.thisWeekKg,
        comparisonValue: v.previousWeekKg,
        period: week,
      );

  static EvidenceItem _feelEvidence(
    double thisAvg,
    double prevAvg,
    DatePeriod week,
  ) => EvidenceItem(
    metric: MetricType.feelRating,
    observedValue: thisAvg,
    comparisonValue: prevAvg,
    period: week,
  );
}
