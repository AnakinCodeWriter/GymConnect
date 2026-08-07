// Characterisation tests for RecommendationService, written in Phase 1 and
// extended in Phase 3 after the D3 correction: the service now uses the
// canonical capped Epley formula and the shared eligibility rule (warm-up
// and malformed sets no longer drive strength comparisons).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/services/recommendation_service.dart';

WorkoutModel _workout({
  required DateTime date,
  required String exercise,
  required double weight,
  int reps = 5,
}) => WorkoutModel(
  id: 'w-${exercise.hashCode}-${date.millisecondsSinceEpoch}',
  date: Timestamp.fromDate(date),
  exercises: [
    ExerciseEntry(
      name: exercise,
      sets: [WorkoutSet(weight: weight, reps: reps)],
    ),
  ],
);

void main() {
  final service = RecommendationService();
  final base = DateTime(2026, 6, 1, 10);

  group('RecommendationService.generate', () {
    test('no workouts returns the get-started recommendation', () {
      final rec = service.generate([]);
      expect(rec.type, RecommendationType.startBeginner);
    });

    test('flat e1RM on the most-logged exercise (>=5 sessions) returns '
        'plateau advice naming the exercise', () {
      // 6 sessions of Bench Press at a constant 100 kg x 5 -> plateau.
      final workouts = List.generate(
        6,
        (i) => _workout(
          date: base.add(Duration(days: i * 3)),
          exercise: 'Bench Press',
          weight: 100,
        ),
      );
      final rec = service.generate(workouts);
      expect(rec.type, RecommendationType.plateauAdvice);
      expect(rec.title, contains('Bench Press'));
      expect(rec.title, contains('Plateau'));
    });

    test(
      'declining e1RM on the most-logged exercise returns a progress alert',
      () {
        // 100 -> 75 kg over 6 sessions: clear regression.
        final workouts = List.generate(
          6,
          (i) => _workout(
            date: base.add(Duration(days: i * 3)),
            exercise: 'Bench Press',
            weight: 100.0 - i * 5,
          ),
        );
        final rec = service.generate(workouts);
        expect(rec.type, RecommendationType.plateauAdvice);
        expect(rec.title, contains('Progress Alert'));
      },
    );

    test('progressing single-muscle-group history returns the balance '
        'recommendation', () {
      // Rising bench: no plateau, all exercises map to "chest".
      final workouts = List.generate(
        6,
        (i) => _workout(
          date: base.add(Duration(days: i * 3)),
          exercise: 'Bench Press',
          weight: 60.0 + i * 4,
        ),
      );
      final rec = service.generate(workouts);
      expect(rec.type, RecommendationType.balanceWorkout);
      expect(rec.message, contains('chest'));
    });

    test('progressing multi-group training returns keep-going', () {
      final workouts = <WorkoutModel>[];
      for (var i = 0; i < 6; i++) {
        workouts.add(
          _workout(
            date: base.add(Duration(days: i * 3)),
            exercise: 'Bench Press',
            weight: 60.0 + i * 4,
          ),
        );
        workouts.add(
          _workout(
            date: base.add(Duration(days: i * 3 + 1)),
            exercise: 'Squat',
            weight: 80.0 + i * 5,
          ),
        );
      }
      final rec = service.generate(workouts);
      expect(rec.type, RecommendationType.keepGoing);
    });

    test('fewer than 5 sessions is insufficient data - no plateau advice even '
        'for flat weights', () {
      final workouts = <WorkoutModel>[];
      for (var i = 0; i < 4; i++) {
        workouts.add(
          _workout(
            date: base.add(Duration(days: i * 3)),
            exercise: 'Bench Press',
            weight: 100,
          ),
        );
        workouts.add(
          _workout(
            date: base.add(Duration(days: i * 3 + 1)),
            exercise: 'Squat',
            weight: 100,
          ),
        );
      }
      final rec = service.generate(workouts);
      expect(rec.type, RecommendationType.keepGoing);
    });

    test('warm-up sets do not drive strength comparisons (D3): flat heavy '
        'warm-ups cannot mask progressing working sets', () {
      // Working sets rise 60 -> 80 kg (progressing); every session also has
      // a flat 100 kg x 10 warm-up. If warm-ups counted, best e1RM would be
      // a constant 133.3 -> plateau advice. They must not.
      final workouts = List.generate(
        8,
        (i) => WorkoutModel(
          id: 'w$i',
          date: Timestamp.fromDate(base.add(Duration(days: i * 3))),
          exercises: [
            ExerciseEntry(
              name: 'Bench Press',
              sets: [
                WorkoutSet(weight: 100, reps: 10, isWarmup: true),
                WorkoutSet(weight: 60.0 + i * 2.5, reps: 5),
              ],
            ),
          ],
        ),
      );
      final rec = service.generate(workouts);
      expect(rec.type, isNot(RecommendationType.plateauAdvice));
    });

    test('rep counts above the cap use the capped formula (D3): rising reps '
        'beyond 10 at a flat weight no longer read as progress', () {
      // Flat 100 kg with reps 11..16: uncapped e1RM would rise every
      // session (progressing); capped e1RM is constant -> plateau advice.
      final workouts = List.generate(
        6,
        (i) => _workout(
          date: base.add(Duration(days: i * 3)),
          exercise: 'Bench Press',
          weight: 100,
          reps: 11 + i,
        ),
      );
      final rec = service.generate(workouts);
      expect(rec.type, RecommendationType.plateauAdvice);
      expect(rec.title, contains('Plateau'));
    });

    test('malformed sets are ignored in strength comparisons', () {
      // Valid working sets are flat (plateau). Each session also has a
      // malformed zero-rep set with a strongly rising weight: if it were
      // counted, the trend would read as progressing and no plateau advice
      // would fire.
      final workouts = List.generate(
        6,
        (i) => WorkoutModel(
          id: 'w$i',
          date: Timestamp.fromDate(base.add(Duration(days: i * 3))),
          exercises: [
            ExerciseEntry(
              name: 'Bench Press',
              sets: [
                WorkoutSet(weight: 200.0 + i * 20, reps: 0), // malformed
                WorkoutSet(weight: 100, reps: 5),
              ],
            ),
          ],
        ),
      );
      final rec = service.generate(workouts);
      expect(rec.type, RecommendationType.plateauAdvice);
    });
  });
}
