import '../models/workout_model.dart';
import 'plateau_detector.dart';

enum RecommendationType { startBeginner, balanceWorkout, plateauAdvice, keepGoing }

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

class NextWorkoutSuggestion {
  final String title;
  final String message;

  const NextWorkoutSuggestion({required this.title, required this.message});
}

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
          final e1rm = set.weight * (1 + set.reps / 30);
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

      final sessions = exerciseSessions[topExercise]!
          .entries
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
      message: 'Your training looks well-rounded. Keep logging your sessions to track your progress.',
    );
  }

  // Suggests what muscle group to train next based on the most recent workout.
  // Looks only at the last workout, not the full history.
  NextWorkoutSuggestion suggestNextWorkout(List<WorkoutModel> workouts) {
    if (workouts.isEmpty) {
      return const NextWorkoutSuggestion(
        title: 'Full Body Beginner Workout',
        message: 'You have not logged any workouts yet. A full body session is a great place to start.',
      );
    }

    // workouts are ordered newest first (see WorkoutService), so index 0 is most recent.
    final lastWorkout = workouts.first;

    // Count how many exercises in the last workout belong to upper vs lower body.
    int upperCount = 0;
    int lowerCount = 0;

    const upperKeywords = ['bench', 'press', 'row', 'pull', 'lat', 'curl', 'shoulder', 'chest', 'tricep', 'bicep', 'back', 'push'];
    const lowerKeywords = ['squat', 'leg', 'deadlift', 'lunge', 'calf'];

    for (final exercise in lastWorkout.exercises) {
      final name = exercise.name.toLowerCase();
      if (upperKeywords.any((k) => name.contains(k))) {
        upperCount++;
      } else if (lowerKeywords.any((k) => name.contains(k))) {
        lowerCount++;
      }
    }

    if (upperCount > lowerCount) {
      return const NextWorkoutSuggestion(
        title: 'Lower Body Workout',
        message: 'You recently focused on upper body, so training lower body next will help maintain balance.',
      );
    }

    if (lowerCount > upperCount) {
      return const NextWorkoutSuggestion(
        title: 'Upper Body Workout',
        message: 'You recently focused on lower body, so training upper body next will help maintain balance.',
      );
    }

    // Mixed or unclear - suggest full body
    return const NextWorkoutSuggestion(
      title: 'Full Body Workout',
      message: 'Your last session was mixed. A full body workout is a solid next choice.',
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
