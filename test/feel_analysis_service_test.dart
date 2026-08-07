import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/services/feel_analysis_service.dart';

// Builds a rated workout. Pass workouts to analyse() newest-first.
WorkoutModel _makeWorkout({
  required DateTime date,
  required int? feelRating,
  double weight = 100.0,
  int reps = 5,
}) {
  return WorkoutModel(
    id: 'test-${date.millisecondsSinceEpoch}',
    date: Timestamp.fromDate(date),
    feelRating: feelRating,
    exercises: [
      ExerciseEntry(
        name: 'Squat',
        sets: [WorkoutSet(weight: weight, reps: reps)],
      ),
    ],
  );
}

void main() {
  final now = DateTime.now();

  group('FeelAnalysisService.analyse', () {
    group('Minimum data requirement', () {
      test('returns null when fewer than 3 workouts have a feel rating', () {
        final workouts = [
          _makeWorkout(
            date: now.subtract(const Duration(days: 2)),
            feelRating: 5,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 4)),
            feelRating: 4,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 6)),
            feelRating: null,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 8)),
            feelRating: null,
          ),
        ];
        expect(FeelAnalysisService.analyse(workouts), isNull);
      });

      test('returns null when no workouts carry a feel rating', () {
        final workouts = List.generate(
          5,
          (i) => _makeWorkout(
            date: now.subtract(Duration(days: i * 2)),
            feelRating: null,
          ),
        );
        expect(FeelAnalysisService.analyse(workouts), isNull);
      });
    });

    group('Priority 1 - Low feel streak', () {
      test(
        'fires when the last 3 consecutive sessions are rated 2 or below',
        () {
          final workouts = [
            _makeWorkout(
              date: now.subtract(const Duration(days: 2)),
              feelRating: 1,
            ),
            _makeWorkout(
              date: now.subtract(const Duration(days: 4)),
              feelRating: 2,
            ),
            _makeWorkout(
              date: now.subtract(const Duration(days: 6)),
              feelRating: 1,
            ),
            _makeWorkout(
              date: now.subtract(const Duration(days: 8)),
              feelRating: 5,
            ),
            _makeWorkout(
              date: now.subtract(const Duration(days: 10)),
              feelRating: 4,
            ),
          ];
          final result = FeelAnalysisService.analyse(workouts);
          expect(result, isNotNull);
          expect(result!.type, FeelInsightType.lowStreakWarning);
        },
      );

      test('fires with a streak of 4 or more consecutive low sessions', () {
        final workouts = List.generate(
          5,
          (i) => _makeWorkout(
            date: now.subtract(Duration(days: i * 2)),
            feelRating: 1,
          ),
        );
        final result = FeelAnalysisService.analyse(workouts);
        expect(result, isNotNull);
        expect(result!.type, FeelInsightType.lowStreakWarning);
      });

      test('does not fire when a rating of 3 breaks the streak', () {
        final workouts = [
          _makeWorkout(
            date: now.subtract(const Duration(days: 2)),
            feelRating: 1,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 4)),
            feelRating: 3,
          ), // breaks streak
          _makeWorkout(
            date: now.subtract(const Duration(days: 6)),
            feelRating: 1,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 8)),
            feelRating: 2,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 10)),
            feelRating: 1,
          ),
        ];
        final result = FeelAnalysisService.analyse(workouts);
        if (result != null) {
          expect(result.type, isNot(FeelInsightType.lowStreakWarning));
        }
      });

      test('does not fire when only 2 consecutive low sessions exist', () {
        final workouts = [
          _makeWorkout(
            date: now.subtract(const Duration(days: 2)),
            feelRating: 2,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 4)),
            feelRating: 1,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 6)),
            feelRating: 4,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 8)),
            feelRating: 5,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 10)),
            feelRating: 4,
          ),
        ];
        final result = FeelAnalysisService.analyse(workouts);
        if (result != null) {
          expect(result.type, isNot(FeelInsightType.lowStreakWarning));
        }
      });
    });

    group('Priority 2 - Performance correlation', () {
      test('fires when mean e1RM is measurably higher on high-feel days', () {
        // 3 high-feel sessions (4-5) with heavy weights, 3 low-feel (1-2) with light weights
        final workouts = [
          _makeWorkout(
            date: now.subtract(const Duration(days: 2)),
            feelRating: 5,
            weight: 130,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 4)),
            feelRating: 4,
            weight: 125,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 6)),
            feelRating: 5,
            weight: 120,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 8)),
            feelRating: 2,
            weight: 80,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 10)),
            feelRating: 1,
            weight: 75,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 12)),
            feelRating: 2,
            weight: 70,
          ),
        ];
        final result = FeelAnalysisService.analyse(workouts);
        expect(result, isNotNull);
        expect(result!.type, FeelInsightType.performanceCorrelation);
      });

      test(
        'does not fire when fewer than 3 sessions are in the high-feel bucket',
        () {
          // Only 2 high-feel sessions - threshold not met
          final workouts = [
            _makeWorkout(
              date: now.subtract(const Duration(days: 2)),
              feelRating: 5,
              weight: 130,
            ),
            _makeWorkout(
              date: now.subtract(const Duration(days: 4)),
              feelRating: 4,
              weight: 125,
            ),
            _makeWorkout(
              date: now.subtract(const Duration(days: 6)),
              feelRating: 2,
              weight: 80,
            ),
            _makeWorkout(
              date: now.subtract(const Duration(days: 8)),
              feelRating: 1,
              weight: 75,
            ),
            _makeWorkout(
              date: now.subtract(const Duration(days: 10)),
              feelRating: 2,
              weight: 70,
            ),
          ];
          final result = FeelAnalysisService.analyse(workouts);
          if (result != null) {
            expect(result.type, isNot(FeelInsightType.performanceCorrelation));
          }
        },
      );

      test('neutral sessions rated 3 are excluded from both buckets', () {
        // 3 high-feel sessions, 0 low-feel sessions - only neutral sessions otherwise
        final workouts = [
          _makeWorkout(
            date: now.subtract(const Duration(days: 2)),
            feelRating: 5,
            weight: 130,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 4)),
            feelRating: 4,
            weight: 125,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 6)),
            feelRating: 5,
            weight: 120,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 8)),
            feelRating: 3,
            weight: 100,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 10)),
            feelRating: 3,
            weight: 95,
          ),
          _makeWorkout(
            date: now.subtract(const Duration(days: 12)),
            feelRating: 3,
            weight: 90,
          ),
        ];
        final result = FeelAnalysisService.analyse(workouts);
        // Cannot fire: no low-feel bucket to compare against
        if (result != null) {
          expect(result.type, isNot(FeelInsightType.performanceCorrelation));
        }
      });
    });

    group('Priority 3 - Best day of week', () {
      test(
        'fires when one weekday consistently has the highest feel scores',
        () {
          // Two Monday sessions rated 5, two Wednesday sessions rated 2
          final monday1 = DateTime(2024, 1, 1); // Monday
          final monday2 = DateTime(2024, 1, 8); // Monday
          final wed1 = DateTime(2024, 1, 3); // Wednesday
          final wed2 = DateTime(2024, 1, 10); // Wednesday
          final fri = DateTime(2024, 1, 5); // Friday

          final workouts = [
            _makeWorkout(date: monday2, feelRating: 5),
            _makeWorkout(date: wed2, feelRating: 2),
            _makeWorkout(date: monday1, feelRating: 5),
            _makeWorkout(date: wed1, feelRating: 2),
            _makeWorkout(date: fri, feelRating: 3),
          ];
          final result = FeelAnalysisService.analyse(workouts);
          expect(result, isNotNull);
          expect(result!.type, FeelInsightType.bestDayOfWeek);
        },
      );

      test('does not fire when every day has only one rating', () {
        // Each session on a different day of the week - no day meets the >=2 threshold
        final workouts = [
          _makeWorkout(date: DateTime(2024, 1, 1), feelRating: 5), // Mon
          _makeWorkout(date: DateTime(2024, 1, 2), feelRating: 4), // Tue
          _makeWorkout(date: DateTime(2024, 1, 3), feelRating: 5), // Wed
          _makeWorkout(date: DateTime(2024, 1, 4), feelRating: 4), // Thu
          _makeWorkout(date: DateTime(2024, 1, 5), feelRating: 5), // Fri
        ];
        final result = FeelAnalysisService.analyse(workouts);
        if (result != null) {
          expect(result.type, isNot(FeelInsightType.bestDayOfWeek));
        }
      });
    });

    group('Priority ordering', () {
      test(
        'low streak is returned even when performance correlation data exists',
        () {
          final workouts = [
            // Newest 3 sessions: low feel (streak = 3)
            _makeWorkout(
              date: now.subtract(const Duration(days: 2)),
              feelRating: 1,
              weight: 100,
            ),
            _makeWorkout(
              date: now.subtract(const Duration(days: 4)),
              feelRating: 2,
              weight: 105,
            ),
            _makeWorkout(
              date: now.subtract(const Duration(days: 6)),
              feelRating: 1,
              weight: 100,
            ),
            // Older sessions: high feel with high weights - performance correlation would fire
            _makeWorkout(
              date: now.subtract(const Duration(days: 8)),
              feelRating: 5,
              weight: 130,
            ),
            _makeWorkout(
              date: now.subtract(const Duration(days: 10)),
              feelRating: 4,
              weight: 125,
            ),
            _makeWorkout(
              date: now.subtract(const Duration(days: 12)),
              feelRating: 5,
              weight: 120,
            ),
          ];
          final result = FeelAnalysisService.analyse(workouts);
          expect(result, isNotNull);
          expect(result!.type, FeelInsightType.lowStreakWarning);
        },
      );
    });
  });
}
