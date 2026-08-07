import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/services/plateau_diagnosis_service.dart';

const _ex = 'Bench Press';

// Builds a WorkoutModel with a single exercise containing one working set.
// Sessions should be passed to analyse() newest-first.
WorkoutModel _makeWorkout({
  required DateTime date,
  required double weight,
  int reps = 5,
  bool includeWarmup = false,
}) {
  final sets = <WorkoutSet>[];
  if (includeWarmup) {
    sets.add(WorkoutSet(weight: weight * 0.6, reps: 10, isWarmup: true));
  }
  sets.add(WorkoutSet(weight: weight, reps: reps));

  return WorkoutModel(
    id: 'test-${date.millisecondsSinceEpoch}',
    date: Timestamp.fromDate(date),
    exercises: [ExerciseEntry(name: _ex, sets: sets)],
  );
}

void main() {
  final now = DateTime.now();

  group('PlateauDiagnosisService.analyse', () {
    test('returns null when fewer than 4 sessions are available', () {
      final workouts = List.generate(
        3,
        (i) => _makeWorkout(
          date: now.subtract(Duration(days: i * 3)),
          weight: 100,
        ),
      );
      expect(
        PlateauDiagnosisService.analyse(workouts, _ex, referenceDate: now),
        isNull,
      );
    });

    test('returns null when exercise name does not match', () {
      final workouts = List.generate(
        6,
        (i) => _makeWorkout(
          date: now.subtract(Duration(days: i * 3)),
          weight: 100,
        ),
      );
      expect(
        PlateauDiagnosisService.analyse(workouts, 'Squat', referenceDate: now),
        isNull,
      );
    });

    group('Rule 1 - Frequency drop', () {
      test('fires when recent sessions are far fewer than prior period', () {
        // 1 session in last 28 days vs 5 in the prior 28 days
        final workouts = [
          _makeWorkout(
            date: now.subtract(const Duration(days: 5)),
            weight: 100,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 30)),
            weight: 100,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 36)),
            weight: 100,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 42)),
            weight: 100,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 48)),
            weight: 100,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 54)),
            weight: 100,
          ),
        ];
        final result = PlateauDiagnosisService.analyse(
          workouts,
          _ex,
          referenceDate: now,
        );
        expect(result, isNotNull);
        expect(result!.type, DiagnosisType.frequencyDrop);
      });

      test('a session exactly 28 days before the reference date counts as the '
          'prior window (isAfter is strict)', () {
        // Fixed reference date - deterministic regardless of wall clock.
        final ref = DateTime(2026, 6, 30, 12);
        // If the boundary session were "recent": recent=2, prior=3,
        // ratio 0.67 -> rule would NOT fire. Counted as "prior": recent=1,
        // prior=4, ratio 0.25 -> fires with the higher confidence (0.85),
        // beating rep monotony (0.75). Reps varied anyway for isolation.
        final reps = [4, 6, 8, 5, 7];
        final days = [1, 28, 35, 42, 49];
        final workouts = [
          for (var i = 0; i < days.length; i++)
            _makeWorkout(
              date: ref.subtract(Duration(days: days[i])),
              weight: 100,
              reps: reps[i],
            ),
        ];
        final result = PlateauDiagnosisService.analyse(
          workouts,
          _ex,
          referenceDate: ref,
        );
        expect(result, isNotNull);
        expect(result!.type, DiagnosisType.frequencyDrop);
      });

      test('is deterministic for a fixed reference date', () {
        final ref = DateTime(2026, 6, 30, 12);
        final reps = [4, 6, 8, 5, 7, 3];
        final days = [5, 30, 36, 42, 48, 54];
        final workouts = [
          for (var i = 0; i < days.length; i++)
            _makeWorkout(
              date: ref.subtract(Duration(days: days[i])),
              weight: 100,
              reps: reps[i],
            ),
        ];
        final a = PlateauDiagnosisService.analyse(
          workouts,
          _ex,
          referenceDate: ref,
        );
        final b = PlateauDiagnosisService.analyse(
          workouts,
          _ex,
          referenceDate: ref,
        );
        expect(a!.type, DiagnosisType.frequencyDrop);
        expect(b!.type, a.type);
        expect(b.message, a.message);
      });

      test(
        'does not fire when session frequency is consistent across both windows',
        () {
          // 2 sessions in each 28-day window
          final workouts = [
            _makeWorkout(
              date: now.subtract(const Duration(days: 7)),
              weight: 100,
            ),
            _makeWorkout(
              date: now.subtract(const Duration(days: 14)),
              weight: 100,
            ),
            _makeWorkout(
              date: now.subtract(const Duration(days: 35)),
              weight: 100,
            ),
            _makeWorkout(
              date: now.subtract(const Duration(days: 42)),
              weight: 100,
            ),
          ];
          final result = PlateauDiagnosisService.analyse(
            workouts,
            _ex,
            referenceDate: now,
          );
          if (result != null) {
            expect(result.type, isNot(DiagnosisType.frequencyDrop));
          }
        },
      );
    });

    group('Rule 2 - Rep monotony', () {
      test(
        'fires when the same rep count appears in 5 of the last 6 sessions',
        () {
          // All 6 sessions use 5 reps
          final workouts = List.generate(
            6,
            (i) => _makeWorkout(
              date: now.subtract(Duration(days: i * 3)),
              weight: 100.0 + i,
              reps: 5,
            ),
          );
          final result = PlateauDiagnosisService.analyse(
            workouts,
            _ex,
            referenceDate: now,
          );
          expect(result, isNotNull);
          expect(result!.type, DiagnosisType.repMonotony);
        },
      );

      test('does not fire when rep ranges vary across sessions', () {
        final repRanges = [3, 8, 5, 10, 6, 4];
        final workouts = List.generate(
          6,
          (i) => _makeWorkout(
            date: now.subtract(Duration(days: i * 3)),
            weight: 100,
            reps: repRanges[i],
          ),
        );
        final result = PlateauDiagnosisService.analyse(
          workouts,
          _ex,
          referenceDate: now,
        );
        if (result != null) {
          expect(result.type, isNot(DiagnosisType.repMonotony));
        }
      });
    });

    group('Rule 3 - Continuous escalation', () {
      test('fires when weight increases strictly every session', () {
        // Newest-first: 125, 120, 115, 110, 105, 100 - strictly increasing chronologically.
        // Reps are varied to prevent rep monotony from firing instead.
        final repVariations = [5, 8, 3, 5, 8, 3];
        final workouts = List.generate(
          6,
          (i) => _makeWorkout(
            date: now.subtract(Duration(days: i * 3)),
            weight: 125.0 - i * 5,
            reps: repVariations[i],
          ),
        );
        final result = PlateauDiagnosisService.analyse(
          workouts,
          _ex,
          referenceDate: now,
        );
        expect(result, isNotNull);
        expect(result!.type, DiagnosisType.continuousEscalation);
      });

      test('does not fire when any session repeats a weight', () {
        // Chronological order has 110 repeated - not strictly increasing
        // Newest-first: 125, 120, 110, 110, 105, 100
        final weights = [125.0, 120.0, 110.0, 110.0, 105.0, 100.0];
        final workouts = List.generate(
          6,
          (i) => _makeWorkout(
            date: now.subtract(Duration(days: i * 3)),
            weight: weights[i],
          ),
        );
        final result = PlateauDiagnosisService.analyse(
          workouts,
          _ex,
          referenceDate: now,
        );
        if (result != null) {
          expect(result.type, isNot(DiagnosisType.continuousEscalation));
        }
      });
    });

    group('Rule 4 - No recovery week', () {
      test('fires when no session in last 8 falls below 70% of peak weight', () {
        // Peak = 100 kg. Threshold = 70 kg. All sessions between 85-100 kg.
        // Weights vary non-monotonically and reps vary to prevent other rules firing.
        final weights = [95.0, 90.0, 88.0, 92.0, 87.0, 91.0, 89.0, 100.0];
        final repsPerSet = [5, 8, 3, 5, 8, 3, 5, 8];
        final workouts = List.generate(
          8,
          (i) => _makeWorkout(
            date: now.subtract(Duration(days: i * 4)),
            weight: weights[i],
            reps: repsPerSet[i],
          ),
        );
        final result = PlateauDiagnosisService.analyse(
          workouts,
          _ex,
          referenceDate: now,
        );
        expect(result, isNotNull);
        expect(result!.type, DiagnosisType.noRecoveryWeek);
      });

      test('does not fire when at least one session is below 70% of peak', () {
        final workouts = [
          _makeWorkout(
            date: now.subtract(const Duration(days: 4)),
            weight: 100,
          ),
          _makeWorkout(date: now.subtract(const Duration(days: 8)), weight: 95),
          _makeWorkout(
            date: now.subtract(const Duration(days: 12)),
            weight: 90,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 16)),
            weight: 85,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 20)),
            weight: 60,
          ), // 60% of 100 - deload
          _makeWorkout(
            date: now.subtract(const Duration(days: 24)),
            weight: 90,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 28)),
            weight: 95,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 32)),
            weight: 90,
          ),
        ];
        final result = PlateauDiagnosisService.analyse(
          workouts,
          _ex,
          referenceDate: now,
        );
        if (result != null) {
          expect(result.type, isNot(DiagnosisType.noRecoveryWeek));
        }
      });
    });

    group('Warm-up exclusion', () {
      test('warm-up sets are not included in weight analysis', () {
        // Each session has a warm-up set and an escalating working set.
        // Reps are varied to prevent rep monotony from firing instead.
        final repVariations = [5, 8, 3, 5, 8, 3];
        final workouts = List.generate(6, (i) {
          return WorkoutModel(
            id: 'w$i',
            date: Timestamp.fromDate(now.subtract(Duration(days: i * 3))),
            exercises: [
              ExerciseEntry(
                name: _ex,
                sets: [
                  WorkoutSet(weight: 60.0, reps: 10, isWarmup: true),
                  WorkoutSet(weight: 125.0 - i * 5, reps: repVariations[i]),
                ],
              ),
            ],
          );
        });
        final result = PlateauDiagnosisService.analyse(
          workouts,
          _ex,
          referenceDate: now,
        );
        expect(result, isNotNull);
        expect(result!.type, DiagnosisType.continuousEscalation);
      });

      test('sessions with only warm-up sets are excluded from analysis', () {
        // Enough total workouts but only warm-up sets - should be treated as no data
        final workouts = List.generate(6, (i) {
          return WorkoutModel(
            id: 'w$i',
            date: Timestamp.fromDate(now.subtract(Duration(days: i * 3))),
            exercises: [
              ExerciseEntry(
                name: _ex,
                sets: [WorkoutSet(weight: 60.0, reps: 10, isWarmup: true)],
              ),
            ],
          );
        });
        expect(
          PlateauDiagnosisService.analyse(workouts, _ex, referenceDate: now),
          isNull,
        );
      });
    });
  });
}
