import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/models/analytics.dart';
import 'package:gymconnect/models/dashboard.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/services/dashboard_service.dart';
import 'package:gymconnect/utils/fitness_formulas.dart';

// Reference date: Wednesday 1 July 2026.
// Current week: Mon 29 Jun - Sun 5 Jul. Previous: Mon 22 - Sun 28 Jun.
final ref = DateTime(2026, 7, 1, 12);

WorkoutModel _workout(
  DateTime date, {
  String exercise = 'Bench Press',
  double weight = 60,
  int reps = 5,
  List<ExerciseEntry>? exercises,
}) => WorkoutModel(
  id: 'w-${date.millisecondsSinceEpoch}-${exercise.hashCode}',
  date: Timestamp.fromDate(date),
  exercises:
      exercises ??
      [
        ExerciseEntry(
          name: exercise,
          sets: [WorkoutSet(weight: weight, reps: reps)],
        ),
      ],
);

DashboardData _build(List<WorkoutModel> workouts, {int skipped = 0}) =>
    DashboardService.build(
      workouts,
      referenceDate: ref,
      skippedRecords: skipped,
    );

void main() {
  group('week boundaries', () {
    test('weekContaining is Monday-Sunday around the reference date', () {
      final week = DatePeriod.weekContaining(ref);
      expect(week.start, DateTime(2026, 6, 29)); // Monday
      expect(week.end, DateTime(2026, 7, 5)); // Sunday
      expect(week.previousWeek.start, DateTime(2026, 6, 22));
      expect(week.previousWeek.end, DateTime(2026, 6, 28));
    });

    test('a Sunday workout counts in the same week, Monday next week starts '
        'fresh (boundary)', () {
      final d = _build([
        _workout(DateTime(2026, 6, 28, 23)), // Sunday prev week
        _workout(DateTime(2026, 6, 29, 0, 30)), // Monday this week
      ]);
      expect(d.activity.thisWeek, 1);
      expect(d.activity.previousWeek, 1);
    });

    test('reference date is injected - same data, different week', () {
      final workouts = [_workout(DateTime(2026, 6, 24))];
      final thisWeek = DashboardService.build(
        workouts,
        referenceDate: DateTime(2026, 6, 24),
      );
      final nextWeek = DashboardService.build(workouts, referenceDate: ref);
      expect(thisWeek.activity.thisWeek, 1);
      expect(nextWeek.activity.thisWeek, 0);
      expect(nextWeek.activity.previousWeek, 1);
    });
  });

  group('weekly activity', () {
    test('empty history: zero counts, noData status', () {
      final d = _build([]);
      expect(d.activity.thisWeek, 0);
      expect(d.activity.previousWeek, 0);
      expect(d.status, TrainingStatus.noData);
      expect(d.dataQuality, DataQuality.insufficient);
    });

    test('one workout this week', () {
      final d = _build([_workout(DateTime(2026, 6, 30))]);
      expect(d.activity.thisWeek, 1);
      expect(d.activity.change, 1);
    });

    test(
      'multiple this week and previous week, increase/decrease/unchanged',
      () {
        final increase = _build([
          _workout(DateTime(2026, 6, 29)),
          _workout(DateTime(2026, 6, 30)),
          _workout(DateTime(2026, 6, 24)),
        ]);
        expect(increase.activity.thisWeek, 2);
        expect(increase.activity.previousWeek, 1);
        expect(increase.activity.change, 1);

        final decrease = _build([
          _workout(DateTime(2026, 6, 29)),
          _workout(DateTime(2026, 6, 23)),
          _workout(DateTime(2026, 6, 25)),
        ]);
        expect(decrease.activity.change, -1);

        final unchanged = _build([
          _workout(DateTime(2026, 6, 29)),
          _workout(DateTime(2026, 6, 23)),
        ]);
        expect(unchanged.activity.change, 0);
      },
    );
  });

  group('weekly volume', () {
    test('sums eligible sets only: warm-ups and malformed sets excluded', () {
      final d = _build([
        _workout(
          DateTime(2026, 6, 30),
          exercises: [
            ExerciseEntry(
              name: 'Bench Press',
              sets: [
                WorkoutSet(weight: 40, reps: 10, isWarmup: true), // excluded
                WorkoutSet(weight: -5, reps: 5), // malformed, excluded
                WorkoutSet(weight: 60, reps: 5), // 300 kg
              ],
            ),
          ],
        ),
      ]);
      expect(d.volume.thisWeekKg, 300);
    });

    test('previous week without workouts: change unavailable(noData)', () {
      final d = _build([_workout(DateTime(2026, 6, 30))]);
      expect(d.volume.change, isA<MetricUnavailable<PercentageChange>>());
      expect(
        (d.volume.change as MetricUnavailable).reason,
        InsufficiencyReason.noData,
      );
    });

    test('previous week with only zero-volume workouts: unavailable('
        'zeroBaseline), never infinity', () {
      final d = _build([
        _workout(DateTime(2026, 6, 24), weight: 0, reps: 10), // bodyweight
        _workout(DateTime(2026, 6, 30), weight: 60),
      ]);
      expect(d.volume.previousWeekKg, 0);
      expect(
        (d.volume.change as MetricUnavailable).reason,
        InsufficiencyReason.zeroBaseline,
      );
    });

    test('volume increase and decrease compute signed percentages', () {
      final up = _build([
        _workout(DateTime(2026, 6, 24), weight: 100), // 500 kg prev
        _workout(DateTime(2026, 6, 30), weight: 110), // 550 kg now
      ]);
      expect(up.volume.change.valueOrNull!.percent, closeTo(10, 1e-9));

      final down = _build([
        _workout(DateTime(2026, 6, 24), weight: 100),
        _workout(DateTime(2026, 6, 30), weight: 90),
      ]);
      expect(down.volume.change.valueOrNull!.percent, closeTo(-10, 1e-9));
    });
  });

  group('top exercises', () {
    test('ranks by workout count over 28 days with name tie-breaking, '
        'duplicates within a workout counted once', () {
      final d = _build([
        // Squat 3 workouts; Bench 2; Deadlift 2 (tie with Bench -> B first)
        _workout(DateTime(2026, 6, 10), exercise: 'Squat'),
        _workout(DateTime(2026, 6, 15), exercise: 'Squat'),
        _workout(DateTime(2026, 6, 20), exercise: 'Squat'),
        _workout(DateTime(2026, 6, 12), exercise: 'Bench Press'),
        _workout(
          DateTime(2026, 6, 18),
          exercises: [
            ExerciseEntry(
              name: 'Bench Press',
              sets: [WorkoutSet(weight: 60, reps: 5)],
            ),
            ExerciseEntry(
              name: 'Bench Press', // duplicate entry, same workout
              sets: [WorkoutSet(weight: 65, reps: 3)],
            ),
          ],
        ),
        _workout(DateTime(2026, 6, 13), exercise: 'Deadlift'),
        _workout(DateTime(2026, 6, 19), exercise: 'Deadlift'),
        // outside the 28-day window - ignored
        _workout(DateTime(2026, 5, 1), exercise: 'Overhead Press'),
      ]);
      expect(d.topExercises.map((t) => t.name).toList(), [
        'Squat',
        'Bench Press',
        'Deadlift',
      ]);
      expect(d.topExercises.first.workoutCount, 3);
      expect(d.topExercises[1].workoutCount, 2);
    });

    test('empty period produces an empty list', () {
      final d = _build([_workout(DateTime(2026, 1, 1))]);
      expect(d.topExercises, isEmpty);
    });
  });

  group('recent personal records', () {
    test('detects a PR set within 14 days that beats all earlier sessions', () {
      final d = _build([
        _workout(DateTime(2026, 6, 1), weight: 60),
        _workout(DateTime(2026, 6, 10), weight: 62.5),
        _workout(DateTime(2026, 6, 25), weight: 65), // in window, beats prior
      ]);
      expect(d.recentPersonalRecords, hasLength(1));
      final pr = d.recentPersonalRecords.single;
      expect(pr.exercise, 'Bench Press');
      expect(pr.day, DateTime(2026, 6, 25));
      expect(pr.e1RmKg, closeTo(estimatedOneRepMax(65, 5), 1e-9));
    });

    test('a first-ever session is not a record', () {
      final d = _build([_workout(DateTime(2026, 6, 30), weight: 100)]);
      expect(d.recentPersonalRecords, isEmpty);
    });

    test('warm-up sets cannot create a PR', () {
      final d = _build([
        _workout(DateTime(2026, 6, 1), weight: 60),
        _workout(
          DateTime(2026, 6, 30),
          exercises: [
            ExerciseEntry(
              name: 'Bench Press',
              sets: [
                WorkoutSet(weight: 200, reps: 5, isWarmup: true),
                WorkoutSet(weight: 55, reps: 5), // below prior best
              ],
            ),
          ],
        ),
      ]);
      expect(d.recentPersonalRecords, isEmpty);
    });

    test('reps above the cap do not inflate a PR', () {
      final d = _build([
        // prior best: 100x10 capped -> 133.3
        _workout(DateTime(2026, 6, 1), weight: 100, reps: 10),
        // 100x20 capped is the same 133.3 - NOT strictly greater, no PR
        _workout(DateTime(2026, 6, 30), weight: 100, reps: 20),
      ]);
      expect(d.recentPersonalRecords, isEmpty);
    });

    test('malformed sets cannot create a PR', () {
      final d = _build([
        _workout(DateTime(2026, 6, 1), weight: 60),
        _workout(
          DateTime(2026, 6, 30),
          exercises: [
            ExerciseEntry(
              name: 'Bench Press',
              sets: [WorkoutSet(weight: 500, reps: 0)], // malformed
            ),
          ],
        ),
      ]);
      expect(d.recentPersonalRecords, isEmpty);
    });

    test('multiple PRs order newest first', () {
      final d = _build([
        _workout(DateTime(2026, 6, 1), exercise: 'Squat', weight: 100),
        _workout(DateTime(2026, 6, 1), weight: 60),
        _workout(DateTime(2026, 6, 24), weight: 65),
        _workout(DateTime(2026, 6, 27), exercise: 'Squat', weight: 110),
      ]);
      expect(d.recentPersonalRecords.map((p) => p.exercise).toList(), [
        'Squat',
        'Bench Press',
      ]);
    });
  });

  group('trend warnings and status', () {
    List<WorkoutModel> flat(String name, int n, {double weight = 100}) => [
      for (var i = 0; i < n; i++)
        _workout(
          DateTime(2026, 6, 29 - i * 3), // recent, inside 28d window
          exercise: name,
          weight: weight,
        ),
    ];

    test('insufficient data produces no warning and no false concern', () {
      final d = _build(flat('Bench Press', 4)); // < 5 sessions
      expect(d.trendWarnings, isEmpty);
      expect(d.status, TrainingStatus.gettingStarted);
    });

    test('flat top exercise with enough sessions produces a plateau warning '
        'with evidence, and the possiblePlateau status', () {
      final d = _build(flat('Bench Press', 7));
      expect(d.trendWarnings, hasLength(1));
      final w = d.trendWarnings.single;
      expect(w.exercise, 'Bench Press');
      expect(w.concern, TrendConcern.plateau);
      expect(w.sessionCount, 7);
      expect(d.status, TrainingStatus.possiblePlateau);
    });

    test('declining top exercise produces a regression warning which '
        'outranks plateau in the status', () {
      final declining = [
        for (var i = 0; i < 7; i++)
          _workout(
            DateTime(2026, 6, 29 - i * 3),
            exercise: 'Bench Press',
            weight: 100.0 - (6 - i) * 5, // newer sessions lighter
          ),
      ];
      final d = _build([...declining, ...flat('Squat', 7)]);
      expect(
        d.trendWarnings.map((w) => w.concern),
        contains(TrendConcern.regression),
      );
      expect(d.status, TrainingStatus.possibleRegression);
    });

    test('progressing top exercise yields progressing status and evidence', () {
      final rising = [
        for (var i = 0; i < 8; i++)
          _workout(
            DateTime(2026, 6, 29 - i * 3),
            exercise: 'Bench Press',
            weight: 80.0 - i * 2.5, // ascending toward the present
          ),
      ];
      final d = _build(rising);
      expect(d.progressingExercises, ['Bench Press']);
      expect(d.trendWarnings, isEmpty);
      expect(d.status, TrainingStatus.progressing);
    });

    test('active week when data exists but trends are quiet', () {
      // 5 workouts across 5 different exercises: no exercise reaches the
      // 5-session trend minimum, one workout is in the current week.
      final d = _build([
        _workout(DateTime(2026, 6, 30), exercise: 'A'),
        _workout(DateTime(2026, 6, 20), exercise: 'B'),
        _workout(DateTime(2026, 6, 18), exercise: 'C'),
        _workout(DateTime(2026, 6, 16), exercise: 'D'),
        _workout(DateTime(2026, 6, 14), exercise: 'E'),
      ]);
      expect(d.status, TrainingStatus.activeWeek);
    });

    test('needsMoreData when nothing this week and no trend signal', () {
      final d = _build([
        _workout(DateTime(2026, 6, 20), exercise: 'A'),
        _workout(DateTime(2026, 6, 18), exercise: 'B'),
        _workout(DateTime(2026, 6, 16), exercise: 'C'),
        _workout(DateTime(2026, 6, 14), exercise: 'D'),
        _workout(DateTime(2026, 6, 12), exercise: 'E'),
      ]);
      expect(d.status, TrainingStatus.needsMoreData);
    });
  });

  group('data quality and partial data', () {
    test('quality follows the documented history-size mapping', () {
      expect(_build([]).dataQuality, DataQuality.insufficient);
      expect(
        _build([_workout(DateTime(2026, 6, 30))]).dataQuality,
        DataQuality.limited,
      );
      expect(_build(flatHistory(6)).dataQuality, DataQuality.moderate);
      expect(_build(flatHistory(15)).dataQuality, DataQuality.strong);
    });

    test('skipped records are carried through as a partial-data warning', () {
      final d = _build([_workout(DateTime(2026, 6, 30))], skipped: 2);
      expect(d.skippedRecords, 2);
    });
  });

  test('output ordering is stable for identical input', () {
    final workouts = [
      _workout(DateTime(2026, 6, 20), exercise: 'B'),
      _workout(DateTime(2026, 6, 20), exercise: 'A'),
      _workout(DateTime(2026, 6, 21), exercise: 'A'),
      _workout(DateTime(2026, 6, 21), exercise: 'B'),
    ];
    final a = _build(workouts);
    final b = _build(List.of(workouts.reversed));
    expect(
      a.topExercises.map((t) => t.name).toList(),
      b.topExercises.map((t) => t.name).toList(),
    );
    expect(a.topExercises.first.name, 'A'); // tie broken by name
  });
}

List<WorkoutModel> flatHistory(int n) => [
  for (var i = 0; i < n; i++)
    _workout(DateTime(2026, 5, 1 + i), exercise: 'Ex$i'),
];
