import '../models/workout_model.dart';
import '../utils/fitness_formulas.dart';

// Priority order for surfacing insights on the home screen:
//  1. lowStreakWarning       — last 3+ consecutive rated sessions all ≤ 2
//  2. performanceCorrelation — user lifts measurably more on high-feel days
//  3. bestDayOfWeek          — day with consistently highest feel average
// null is returned when fewer than 3 workouts carry a feel rating.
enum FeelInsightType { lowStreakWarning, performanceCorrelation, bestDayOfWeek }

class FeelInsight {
  final FeelInsightType type;
  final String title;
  final String message;

  const FeelInsight({
    required this.type,
    required this.title,
    required this.message,
  });
}

class FeelAnalysisService {
  /// Returns the single highest-priority insight, or null when fewer than
  /// 3 workouts have been rated. workouts must be sorted newest-first
  /// (the ordering guarantee from WorkoutService.getWorkouts).
  static FeelInsight? analyse(List<WorkoutModel> workouts) {
    final rated = workouts.where((w) => w.feelRating != null).toList();
    if (rated.length < 3) return null;

    return _checkLowStreak(rated) ??
        _checkPerformanceCorrelation(workouts) ??
        _checkBestDayOfWeek(rated);
  }

  // ── priority 1: low-feel streak ──────────────────────────────────────────

  // rated is newest-first. Count the leading run of sessions rated ≤ 2.
  static FeelInsight? _checkLowStreak(List<WorkoutModel> rated) {
    int streak = 0;
    for (final w in rated) {
      if (w.feelRating! <= 2) {
        streak++;
      } else {
        break;
      }
    }
    if (streak < 3) return null;
    return const FeelInsight(
      type: FeelInsightType.lowStreakWarning,
      title: 'Feeling the strain?',
      message:
          'Your last few sessions have felt tough. Consider a rest day or lighter session.',
    );
  }

  // ── priority 2: performance correlation ──────────────────────────────────

  // Epley e1RM = weight × (1 + reps / 30). Takes the best set across all
  // exercises in a session as the session benchmark.
  // Needs ≥ 3 workouts in each of the high (4–5) and low (1–2) buckets.
  // Rating 3 is neutral and is intentionally excluded from both buckets.
  static FeelInsight? _checkPerformanceCorrelation(
      List<WorkoutModel> workouts) {
    final highE1RMs = <double>[];
    final lowE1RMs = <double>[];

    for (final w in workouts) {
      final rating = w.feelRating;
      if (rating == null) continue;
      final best = _bestE1RM(w);
      if (best == 0) continue;

      if (rating >= 4) {
        highE1RMs.add(best);
      } else if (rating <= 2) {
        lowE1RMs.add(best);
      }
    }

    if (highE1RMs.length < 3 || lowE1RMs.length < 3) return null;

    final avgHigh = highE1RMs.reduce((a, b) => a + b) / highE1RMs.length;
    final avgLow = lowE1RMs.reduce((a, b) => a + b) / lowE1RMs.length;
    if (avgLow == 0) return null;

    final pct = ((avgHigh - avgLow) / avgLow * 100).round();
    if (pct <= 0) return null;

    return FeelInsight(
      type: FeelInsightType.performanceCorrelation,
      title: 'Energy drives performance',
      message: 'You lift $pct% heavier on high-energy days.',
    );
  }

  // Warm-up sets are excluded: their lower weights would drag the session
  // e1RM downward for any session where the user logged a warm-up, making
  // the high-feel vs low-feel comparison less accurate.
  static double _bestE1RM(WorkoutModel w) {
    double best = 0;
    for (final ex in w.exercises) {
      for (final s in ex.sets) {
        if (s.isWarmup) continue;
        final e1rm = estimatedOneRepMax(s.weight, s.reps);
        if (e1rm > best) best = e1rm;
      }
    }
    return best;
  }

  // ── priority 3: best day of week ─────────────────────────────────────────

  // Groups rated sessions by weekday (DateTime.weekday: 1=Mon … 7=Sun).
  // Only considers days with ≥ 2 ratings. Returns the day with the highest
  // average feel rating, or null if no day qualifies.
  static FeelInsight? _checkBestDayOfWeek(List<WorkoutModel> rated) {
    final sums = <int, double>{};
    final counts = <int, int>{};

    for (final w in rated) {
      final day = w.date.toDate().weekday;
      sums[day] = (sums[day] ?? 0) + w.feelRating!;
      counts[day] = (counts[day] ?? 0) + 1;
    }

    final averages = <int, double>{};
    for (final e in counts.entries) {
      if (e.value >= 2) averages[e.key] = sums[e.key]! / e.value;
    }
    if (averages.isEmpty) return null;

    final best = averages.entries.reduce((a, b) => a.value >= b.value ? a : b);

    return FeelInsight(
      type: FeelInsightType.bestDayOfWeek,
      title: 'Peak training day',
      message: 'You consistently feel best training on ${_weekdayName(best.key)}.',
    );
  }

  static String _weekdayName(int weekday) => const {
        1: 'Monday',
        2: 'Tuesday',
        3: 'Wednesday',
        4: 'Thursday',
        5: 'Friday',
        6: 'Saturday',
        7: 'Sunday',
      }[weekday] ??
      'Unknown';
}
