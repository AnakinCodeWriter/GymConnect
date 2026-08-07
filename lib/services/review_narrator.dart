import '../models/analytics.dart';
import '../models/weekly_review.dart';
import '../utils/units.dart';

/// The narration boundary (Phase 8): converts a typed [WeeklyReview] into
/// user-facing copy.
///
/// Contract - a narrator may ONLY rephrase the supplied typed review:
/// - it must not invent metrics, values, causes or recommendations;
/// - it must preserve cautious "possible/appears/may" wording for concerns;
/// - it must handle empty and insufficient-data reviews;
/// - output lists are parallel to the review's typed lists (same length,
///   same order) so the UI pairs every sentence with typed evidence.
///
/// [TemplateReviewNarrator] is the default and only shipped implementation.
/// A future LLM-backed narrator would implement this same interface behind
/// the same contract, injected where the template narrator is constructed
/// today; no API client, secrets or network code exists in this repository
/// and the app must remain fully functional without one
/// (docs/ARCHITECTURE.md, docs/DECISIONS.md).
abstract interface class ReviewNarrator {
  /// [weightUnit] is the display unit ('kg'/'lbs') - presentation config
  /// passed in by the caller, since narrators never read UI state.
  ReviewNarration narrate(WeeklyReview review, {required String weightUnit});
}

/// Deterministic template-based narrator: fixed template per finding/action
/// kind, filled only with the review's typed values. Same input, same output.
class TemplateReviewNarrator implements ReviewNarrator {
  const TemplateReviewNarrator();

  @override
  ReviewNarration narrate(WeeklyReview review, {required String weightUnit}) {
    return ReviewNarration(
      headline: _headline(review),
      summary: _summary(review),
      improvements: [
        for (final f in review.improvements) _finding(f, weightUnit),
      ],
      stable: [for (final f in review.stable) _finding(f, weightUnit)],
      attention: [for (final f in review.attention) _finding(f, weightUnit)],
      actions: [for (final a in review.actions) _action(a)],
    );
  }

  String _headline(WeeklyReview r) {
    if (r.availability == ReviewAvailability.noData) {
      return 'No training data yet';
    }
    if (r.attention.any((f) => f.severity == Severity.warning)) {
      return 'Worth a closer look';
    }
    if (r.improvements.isNotEmpty &&
        r.attention.any((f) => f.severity == Severity.caution)) {
      return 'A mixed week';
    }
    if (r.improvements.isNotEmpty) return 'A positive week';
    if (r.attention.any((f) => f.severity == Severity.caution)) {
      return 'A quieter week';
    }
    return 'A steady week';
  }

  String _summary(WeeklyReview r) {
    if (r.availability == ReviewAvailability.noData) {
      return 'Log your first workout and the weekly review will start '
          'summarising your training here.';
    }
    final parts = <String>[
      r.workoutsThisWeek == 0
          ? 'No workouts were logged this week.'
          : 'You logged ${r.workoutsThisWeek} '
                'workout${r.workoutsThisWeek == 1 ? '' : 's'} this week.',
      if (r.improvements.isNotEmpty)
        '${r.improvements.length} thing${r.improvements.length == 1 ? '' : 's'} '
            'improved.',
      if (r.attention.isNotEmpty) '${r.attention.length} may need attention.',
    ];
    parts.add('Conclusions are based on ${_qualityLabel(r.dataQuality)} data.');
    return parts.join(' ');
  }

  String _finding(ReviewFinding f, String unit) {
    final n = f.observedValue;
    final c = f.comparisonValue;
    switch (f.kind) {
      case ReviewFindingKind.workoutCountIncreased:
        return 'You trained ${_count(n)} time${n == 1 ? '' : 's'} this week, '
            'up from ${_count(c)} last week.';
      case ReviewFindingKind.volumeIncreased:
        return 'Weekly volume rose to ${_weight(n, unit)}, from '
            '${_weight(c, unit)} last week.';
      case ReviewFindingKind.newPersonalRecord:
        return 'New best estimated 1RM on ${f.exercise}: '
            '${_exactWeight(n, unit)}.';
      case ReviewFindingKind.exerciseProgressing:
        return '${f.exercise} appears to be progressing across '
            '${_sessionCount(f)} recent sessions.';
      case ReviewFindingKind.feelImproved:
        return 'Sessions felt better on average than last week '
            '(${_stars(n)} vs ${_stars(c)} of 5).';
      case ReviewFindingKind.workoutCountStable:
        return 'Workout count held steady at ${_count(n)}, matching '
            'last week.';
      case ReviewFindingKind.volumeStable:
        return 'Weekly volume stayed close to last week '
            '(${_weight(n, unit)} vs ${_weight(c, unit)}).';
      case ReviewFindingKind.exerciseVolumeRising:
        return '${f.exercise}: estimated 1RM looks flat, but session volume '
            'is rising - not treated as a stall.';
      case ReviewFindingKind.repeatedExercises:
        return 'Trained in both weeks: ${f.exercises.join(', ')}.';
      case ReviewFindingKind.feelStable:
        return 'Sessions felt about the same as last week '
            '(${_stars(n)} vs ${_stars(c)} of 5).';
      case ReviewFindingKind.possibleRegression:
        return '${f.exercise}: estimated 1RM may be declining across '
            '${_sessionCount(f)} sessions. A possible trend, not a certainty.';
      case ReviewFindingKind.possiblePlateau:
        return '${f.exercise}: estimated 1RM looks flat across '
            '${_sessionCount(f)} sessions - a possible plateau.';
      case ReviewFindingKind.noTrainingThisWeek:
        return 'No workouts logged this week'
            '${c != null && c > 0 ? ' (last week: ${_count(c)})' : ''}.';
      case ReviewFindingKind.workoutCountDecreased:
        return 'You trained ${_count(n)} time${n == 1 ? '' : 's'} this week, '
            'down from ${_count(c)} last week.';
      case ReviewFindingKind.volumeDecreased:
        return 'Weekly volume fell to ${_weight(n, unit)}, from '
            '${_weight(c, unit)} last week.';
      case ReviewFindingKind.feelDeclined:
        return 'Sessions felt tougher on average than last week '
            '(${_stars(n)} vs ${_stars(c)} of 5).';
      case ReviewFindingKind.lowFeelWeek:
        return 'Average session feel this week was low (${_stars(n)} of 5).';
      case ReviewFindingKind.insufficientHistory:
        return 'Only ${_count(n)} workout${n == 1 ? '' : 's'} logged so far - '
            'trend conclusions need at least ${_count(c)}.';
      case ReviewFindingKind.skippedRecords:
        return '${_count(n)} stored workout record${n == 1 ? '' : 's'} '
            'couldn\'t be read and ${n == 1 ? 'is' : 'are'} not included.';
    }
  }

  String _action(SuggestedAction a) {
    switch (a.kind) {
      case SuggestedActionKind.maintainCurrentStructure:
        return 'Your current training appears to be working - keeping the '
            'same structure is a reasonable next step.';
      case SuggestedActionKind.logMoreSessions:
        return 'Log a few more sessions before judging trends - there is '
            'not enough data yet for reliable conclusions.';
      case SuggestedActionKind.reviewRecoveryAndTechnique:
        return 'If the possible decline on ${a.exercise} continues, '
            'reviewing recovery and technique may help. A training '
            'suggestion, not medical advice.';
      case SuggestedActionKind.considerVolumeReview:
        return 'For the possible plateau on ${a.exercise}, reviewing your '
            'training volume could be worth considering.';
      case SuggestedActionKind.keepLoggingFeel:
        return 'Keep rating how sessions feel - feel comparisons need at '
            'least 2 rated sessions per week.';
    }
  }

  // Trend findings carry their session count as workout-count evidence.
  String _sessionCount(ReviewFinding f) {
    for (final e in f.evidence) {
      if (e.metric == MetricType.workoutCount && e.observedValue != null) {
        return _count(e.observedValue);
      }
    }
    return 'several'; // unreachable for produced findings; safe fallback
  }

  String _count(double? v) => v == null ? '?' : v.round().toString();

  String _stars(double? v) => v == null ? '?' : v.toStringAsFixed(1);

  // Volume totals use compact formatting; single-lift values (PRs) keep
  // their exact value - the same split the dashboard uses.
  String _weight(double? kg, String unit) => kg == null
      ? '?'
      : '${formatCompactWeight(kgToDisplayUnit(kg, unit))} $unit';

  String _exactWeight(double? kg, String unit) =>
      kg == null ? '?' : '${formatWeight(kgToDisplayUnit(kg, unit))} $unit';

  String _qualityLabel(DataQuality q) => switch (q) {
    DataQuality.insufficient => 'insufficient',
    DataQuality.limited => 'limited',
    DataQuality.moderate => 'moderate',
    DataQuality.strong => 'strong',
  };
}
