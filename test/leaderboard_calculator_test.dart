// D3 regression suite (deferred from Phase 1, landed with the Phase 3 fix):
// the leaderboard calculation now uses the canonical capped Epley formula
// and the shared strength-analytics eligibility rule.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/services/exercise_analytics_service.dart';
import 'package:gymconnect/services/leaderboard_service.dart';
import 'package:gymconnect/utils/fitness_formulas.dart';

WorkoutModel _workout(List<ExerciseEntry> exercises) => WorkoutModel(
  id: 'w',
  date: Timestamp.fromDate(DateTime(2026, 6, 1, 10)),
  exercises: exercises,
);

WorkoutSet _set(double weight, int reps, {bool warmup = false}) =>
    WorkoutSet(weight: weight, reps: reps, isWarmup: warmup);

void main() {
  group('LeaderboardService.bestEligibleE1RmPerExercise', () {
    test('warm-up sets are ignored, even when numerically stronger', () {
      final workout = _workout([
        ExerciseEntry(
          name: 'Bench Press',
          sets: [
            _set(200, 10, warmup: true), // stronger warm-up must not count
            _set(60, 5),
          ],
        ),
      ]);
      final bests = LeaderboardService.bestEligibleE1RmPerExercise(workout);
      expect(bests['Bench Press'], closeTo(estimatedOneRepMax(60, 5), 1e-9));
    });

    test('repetitions above the cap do not inflate e1RM', () {
      final workout = _workout([
        ExerciseEntry(name: 'Squat', sets: [_set(100, 20)]),
      ]);
      final bests = LeaderboardService.bestEligibleE1RmPerExercise(workout);
      // Capped at 10 reps: 100 * (1 + 10/30), NOT 100 * (1 + 20/30).
      expect(bests['Squat'], closeTo(estimatedOneRepMax(100, 10), 1e-9));
      expect(bests['Squat'], lessThan(100 * (1 + 20 / 30)));
    });

    test('leaderboard, exercise analytics and the canonical formula agree '
        'for the same eligible set', () {
      final set = _set(82.5, 6);
      final workout = _workout([
        ExerciseEntry(name: 'Bench Press', sets: [set]),
      ]);
      final leaderboardValue = LeaderboardService.bestEligibleE1RmPerExercise(
        workout,
      )['Bench Press'];
      final analyticsValue = ExerciseAnalyticsService.buildSeries([
        workout,
      ], 'Bench Press').sessions.single.bestE1RmKg;
      final formulaValue = estimatedOneRepMax(set.weight, set.reps);

      expect(leaderboardValue, closeTo(formulaValue, 1e-9));
      expect(analyticsValue, closeTo(formulaValue, 1e-9));
    });

    test('an empty workout produces no leaderboard values', () {
      expect(
        LeaderboardService.bestEligibleE1RmPerExercise(_workout([])),
        isEmpty,
      );
      expect(
        LeaderboardService.bestEligibleE1RmPerExercise(
          _workout([ExerciseEntry(name: 'Bench Press', sets: [])]),
        ),
        isEmpty,
      );
    });

    test('a warm-up-only workout produces no leaderboard values', () {
      final workout = _workout([
        ExerciseEntry(name: 'Bench Press', sets: [_set(40, 10, warmup: true)]),
      ]);
      expect(LeaderboardService.bestEligibleE1RmPerExercise(workout), isEmpty);
    });

    test('malformed sets are safely ignored', () {
      final workout = _workout([
        ExerciseEntry(
          name: 'Bench Press',
          sets: [
            _set(-50, 5), // negative weight
            _set(60, 0), // zero reps
            _set(double.nan, 5), // non-finite weight
            _set(60, 5), // the only eligible set
          ],
        ),
      ]);
      final bests = LeaderboardService.bestEligibleE1RmPerExercise(workout);
      expect(bests['Bench Press'], closeTo(estimatedOneRepMax(60, 5), 1e-9));
    });

    test('the best eligible set is selected within an exercise', () {
      final workout = _workout([
        ExerciseEntry(
          name: 'Bench Press',
          sets: [_set(60, 5), _set(70, 3), _set(55, 8)],
        ),
      ]);
      final expected = [
        estimatedOneRepMax(60, 5),
        estimatedOneRepMax(70, 3),
        estimatedOneRepMax(55, 8),
      ].reduce((a, b) => a > b ? a : b);
      expect(
        LeaderboardService.bestEligibleE1RmPerExercise(workout)['Bench Press'],
        closeTo(expected, 1e-9),
      );
    });

    test('multiple exercises and duplicate same-named entries are handled', () {
      final workout = _workout([
        ExerciseEntry(name: 'Bench Press', sets: [_set(60, 5)]),
        ExerciseEntry(name: 'Squat', sets: [_set(100, 5)]),
        ExerciseEntry(name: 'Bench Press', sets: [_set(70, 3)]), // duplicate
      ]);
      final bests = LeaderboardService.bestEligibleE1RmPerExercise(workout);
      expect(bests.keys.toSet(), {'Bench Press', 'Squat'});
      expect(bests['Bench Press'], closeTo(estimatedOneRepMax(70, 3), 1e-9));
      expect(bests['Squat'], closeTo(estimatedOneRepMax(100, 5), 1e-9));
    });
  });
}
