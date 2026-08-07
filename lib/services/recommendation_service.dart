import '../models/workout_model.dart';
import '../utils/fitness_formulas.dart';
import 'plateau_detector.dart';

enum RecommendationType {
  startBeginner,
  balanceWorkout,
  plateauAdvice,
  keepGoing,
}

class Recommendation {
  final RecommendationType type;
  final String title;
  final String message;

  const Recommendation({
    required this.type,
    required this.title,
    required this.message,
  });
}

/// Legacy rule-based recommendation helper from the dissertation build.
/// [generate] still powers the dashboard's "Recommended Next Step" card,
/// but only its balance/keep-going branches are rendered - the
/// plateau/regression branch is superseded by the typed, evidence-backed
/// training status (Phase 6) and the Weekly Review's suggested actions
/// (Phase 8). `suggestNextWorkout` (an upper/lower/full-body keyword
/// heuristic) was never rendered post-redesign and was deleted in Phase 11
/// (backlog #14; docs/DECISIONS.md). Do not grow this class: new coaching
/// advice belongs in the typed weekly-review suggestion model.
class RecommendationService {
  // muscle groups used to detect whether training is balanced.
  // each entry maps a keyword (found in exercise names) to a group label.
  static const _muscleKeywords = {
    'squat': 'legs',
    'leg': 'legs',
    'deadlift': 'legs',
    'lunge': 'legs',
    'calf': 'legs',
    'bench': 'chest',
    'chest': 'chest',
    'push': 'chest',
    'row': 'back',
    'pull': 'back',
    'lat': 'back',
    'back': 'back',
    'press': 'shoulders',
    'shoulder': 'shoulders',
    'curl': 'arms',
    'tricep': 'arms',
    'bicep': 'arms',
  };

  Recommendation generate(List<WorkoutModel> workouts) {
    // rule 1: no workouts logged yet
    if (workouts.isEmpty) {
      return const Recommendation(
        type: RecommendationType.startBeginner,
        title: 'Get started',
        message:
            'You have not logged any workouts yet. Try the Full Body Beginner plan to get started.',
      );
    }

    // rule 2: check for plateau in the most frequently logged exercise
    final exerciseCounts = <String, int>{};
    final exerciseSessions = <String, Map<DateTime, double>>{};

    for (final workout in workouts) {
      final day = DateTime(
        workout.date.toDate().year,
        workout.date.toDate().month,
        workout.date.toDate().day,
      );
      for (final exercise in workout.exercises) {
        final name = exercise.name;
        exerciseCounts[name] = (exerciseCounts[name] ?? 0) + 1;
        exerciseSessions[name] ??= {};
        for (final set in exercise.sets) {
          // canonical capped formula; warm-up and malformed sets don't
          // drive strength comparisons (Phase 3, D3).
          if (!isEligibleForStrengthAnalytics(set)) continue;
          final e1rm = estimatedOneRepMax(set.weight, set.reps);
          final current = exerciseSessions[name]![day];
          if (current == null || e1rm > current) {
            exerciseSessions[name]![day] = e1rm;
          }
        }
      }
    }

    // find the most logged exercise and check it for plateau
    if (exerciseCounts.isNotEmpty) {
      final topExercise = exerciseCounts.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;

      final sessions = exerciseSessions[topExercise]!.entries
          .map((e) => (e.key, e.value))
          .toList();

      final result = PlateauDetector.analyse(sessions);

      if (result.status == PlateauStatus.plateau) {
        return Recommendation(
          type: RecommendationType.plateauAdvice,
          title: '$topExercise Plateau Alert',
          message:
              'Your progress on $topExercise appears to have stalled. Try reducing the weight slightly and increasing reps, or take an extra rest day before your next session.',
        );
      }

      if (result.status == PlateauStatus.regressing) {
        return Recommendation(
          type: RecommendationType.plateauAdvice,
          title: '$topExercise Progress Alert',
          message:
              'Your estimated 1RM on $topExercise has been dropping. Consider a recovery week with lighter weights and focus on form.',
        );
      }
    }

    // Rule 3: check if training is unbalanced (only one muscle group logged)
    final groupsSeen = <String>{};
    for (final name in exerciseCounts.keys) {
      final lower = name.toLowerCase();
      for (final entry in _muscleKeywords.entries) {
        if (lower.contains(entry.key)) {
          groupsSeen.add(entry.value);
          break;
        }
      }
    }

    if (groupsSeen.length == 1) {
      final group = groupsSeen.first;
      final opposite = _oppositeGroup(group);
      return Recommendation(
        type: RecommendationType.balanceWorkout,
        title: 'Consider balancing your training',
        message:
            'Most of your logged workouts focus on $group. Adding some $opposite work will help keep your training balanced.',
      );
    }

    // Default: everything looks good
    return const Recommendation(
      type: RecommendationType.keepGoing,
      title: 'Keep it up!',
      message:
          'Your training looks well-rounded. Keep logging your sessions to track your progress.',
    );
  }

  String _oppositeGroup(String group) {
    const opposites = {
      'legs': 'upper body',
      'chest': 'back',
      'back': 'chest',
      'shoulders': 'leg',
      'arms': 'compound movements',
    };
    return opposites[group] ?? 'other muscle groups';
  }
}
