import '../models/workout_model.dart';
import '../utils/fitness_formulas.dart';

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
  static FeelInsight? analyse(List<WorkoutModel> workouts) {
    final rated = workouts.where((w) => w.feelRating != null).toList();
    if (rated.length < 3) return null;

    return _checkLowStreak(rated) ??
        _checkPerformanceCorrelation(workouts) ??
        _checkBestDayOfWeek(rated);
  }

  // rated is newest-first. Count the leading run of sessions rated <= 2.
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

  // Needs >= 3 workouts in each of high (4-5) and low (1-2) buckets. Rating 3 excluded.
  static FeelInsight? _checkPerformanceCorrelation(
    List<WorkoutModel> workouts,
  ) {
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

  static double _bestE1RM(WorkoutModel w) {
    double best = 0;
    for (final ex in w.exercises) {
      for (final s in ex.sets) {
        if (!isEligibleForStrengthAnalytics(s)) continue;
        final e1rm = estimatedOneRepMax(s.weight, s.reps);
        if (e1rm > best) best = e1rm;
      }
    }
    return best;
  }

  // Only considers weekdays with >= 2 ratings.
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
      message:
          'You consistently feel best training on ${_weekdayName(best.key)}.',
    );
  }

  static String _weekdayName(int weekday) =>
      const {
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
