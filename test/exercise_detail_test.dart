import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/models/analytics.dart';
import 'package:gymconnect/models/exercise_detail.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/services/exercise_analytics_service.dart';
import 'package:gymconnect/services/plateau_detector.dart';
import 'package:gymconnect/services/plateau_diagnosis_service.dart';
import 'package:gymconnect/utils/fitness_formulas.dart';

// Reference: Wed 1 Jul 2026. Recent window: 4 Jun - 1 Jul (28 days).
// Baseline window: 7 May - 3 Jun.
final ref = DateTime(2026, 7, 1, 12);

WorkoutModel _workout(
  DateTime date, {
  String exercise = 'Bench Press',
  double weight = 60,
  int reps = 5,
  bool warmup = false,
}) => WorkoutModel(
  id: 'w-${date.millisecondsSinceEpoch}-${exercise.hashCode}-$weight',
  date: Timestamp.fromDate(date),
  exercises: [
    ExerciseEntry(
      name: exercise,
      sets: [WorkoutSet(weight: weight, reps: reps, isWarmup: warmup)],
    ),
  ],
);

ExerciseDetail _analyse(
  List<WorkoutModel> workouts, [
  String name = 'Bench Press',
]) => ExerciseAnalyticsService.analyseExercise(
  workouts,
  name,
  referenceDate: ref,
);

void main() {
  group('availability and matching', () {
    test('no workout history: empty series, insufficient everything', () {
      final d = _analyse([]);
      expect(d.series.isEmpty, isTrue);
      expect(d.totalSessions, 0);
      expect(d.strengthStatus, PlateauStatus.insufficientData);
      expect(d.dataQuality, DataQuality.insufficient);
      expect(d.recentBest, isA<MetricUnavailable<RecentBest>>());
      expect(d.possibleExplanation, isNull);
    });

    test('no matching exercise behaves like no data', () {
      final d = _analyse([_workout(ref, exercise: 'Squat')]);
      expect(d.totalSessions, 0);
      expect(d.dataQuality, DataQuality.insufficient);
    });

    test('matching is exact: substring names do not pollute the analysis', () {
      final d = _analyse([
        _workout(DateTime(2026, 6, 20), weight: 60),
        _workout(
          DateTime(2026, 6, 22),
          exercise: 'Incline Bench Press',
          weight: 200,
        ),
      ]);
      expect(d.totalSessions, 1);
      expect(
        d.recentBest.valueOrNull!.e1RmKg,
        closeTo(estimatedOneRepMax(60, 5), 1e-9),
      );
    });

    test('warm-up-only history yields an empty analysis', () {
      final d = _analyse([_workout(DateTime(2026, 6, 20), warmup: true)]);
      expect(d.totalSessions, 0);
      expect(d.recentBest, isA<MetricUnavailable<RecentBest>>());
    });

    test('malformed sets are skipped via the shared eligibility rule', () {
      final d = _analyse([
        _workout(DateTime(2026, 6, 20), weight: -50), // malformed
        _workout(DateTime(2026, 6, 22), weight: 60),
      ]);
      expect(d.totalSessions, 1);
    });
  });

  group('recent best', () {
    test('one valid session: recent best with its day, but no trend', () {
      final d = _analyse([_workout(DateTime(2026, 6, 20), weight: 80)]);
      final best = d.recentBest.valueOrNull!;
      expect(best.e1RmKg, closeTo(estimatedOneRepMax(80, 5), 1e-9));
      expect(best.day, DateTime(2026, 6, 20));
      expect(d.strengthStatus, PlateauStatus.insufficientData);
    });

    test('sessions outside the 28-day window are not the recent best', () {
      final d = _analyse([
        _workout(DateTime(2026, 5, 1), weight: 100), // heavier but old
        _workout(DateTime(2026, 6, 20), weight: 80),
      ]);
      expect(
        d.recentBest.valueOrNull!.e1RmKg,
        closeTo(estimatedOneRepMax(80, 5), 1e-9),
      );
    });

    test('only-old history: recent best unavailable, not zero', () {
      final d = _analyse([_workout(DateTime(2026, 4, 1), weight: 100)]);
      expect(d.recentBest, isA<MetricUnavailable<RecentBest>>());
    });

    test('equal bests keep the LATEST day', () {
      final d = _analyse([
        _workout(DateTime(2026, 6, 10), weight: 80),
        _workout(DateTime(2026, 6, 24), weight: 80),
      ]);
      expect(d.recentBest.valueOrNull!.day, DateTime(2026, 6, 24));
    });
  });

  group('frequency', () {
    test('sessions per week over the recent 28 days', () {
      final d = _analyse([
        for (var i = 0; i < 8; i++)
          _workout(DateTime(2026, 6, 28 - i * 3), weight: 60),
      ]);
      // all 8 sessions inside 4 Jun-1 Jul -> 8 / 4 weeks = 2.0
      expect(d.sessionsPerWeek.valueOrNull, closeTo(2.0, 1e-9));
      expect(d.sessionsInWindow, 8);
    });

    test('history exists but none recent: frequency is a genuine zero', () {
      final d = _analyse([_workout(DateTime(2026, 4, 1))]);
      expect(d.sessionsPerWeek.valueOrNull, 0);
    });
  });

  group('changes between windows', () {
    test('strength increase between baseline and recent windows', () {
      final d = _analyse([
        _workout(DateTime(2026, 5, 20), weight: 60), // baseline
        _workout(DateTime(2026, 6, 20), weight: 66), // recent (+10%)
      ]);
      expect(d.strengthChange.valueOrNull!.percent, closeTo(10, 1e-9));
      expect(d.strengthChange.valueOrNull!.direction, ChangeDirection.increase);
    });

    test('volume decrease between windows', () {
      final d = _analyse([
        _workout(DateTime(2026, 5, 20), weight: 100), // 500 kg baseline
        _workout(DateTime(2026, 6, 20), weight: 50), // 250 kg recent
      ]);
      expect(d.volumeChange.valueOrNull!.percent, closeTo(-50, 1e-9));
    });

    test('unchanged values report 0% with direction unchanged', () {
      final d = _analyse([
        _workout(DateTime(2026, 5, 20), weight: 60),
        _workout(DateTime(2026, 6, 20), weight: 60),
      ]);
      expect(d.strengthChange.valueOrNull!.percent, 0);
      expect(
        d.strengthChange.valueOrNull!.direction,
        ChangeDirection.unchanged,
      );
    });

    test('no baseline sessions: change unavailable(noData)', () {
      final d = _analyse([_workout(DateTime(2026, 6, 20))]);
      expect(
        (d.strengthChange as MetricUnavailable).reason,
        InsufficiencyReason.noData,
      );
    });

    test('zero baseline volume: unavailable(zeroBaseline), never infinity', () {
      final d = _analyse([
        _workout(DateTime(2026, 5, 20), weight: 0, reps: 10), // 0 volume
        _workout(DateTime(2026, 6, 20), weight: 60),
      ]);
      expect(
        (d.volumeChange as MetricUnavailable).reason,
        InsufficiencyReason.zeroBaseline,
      );
    });
  });

  group('trend statuses', () {
    List<WorkoutModel> series(
      double Function(int i) weightAt, {
      int n = 7,
      int reps = 5,
    }) => [
      for (var i = 0; i < n; i++)
        _workout(
          DateTime(2026, 6, 28 - i * 3),
          weight: weightAt(i),
          reps: reps,
        ),
    ];

    test('progressing status with no explanation attached', () {
      final d = _analyse(series((i) => 80.0 - i * 2.5, n: 8));
      expect(d.strengthStatus, PlateauStatus.progressing);
      expect(d.volumeProgressionSuppressed, isFalse);
      expect(d.possibleExplanation, isNull);
    });

    test('plateau status carries an explanation when the diagnosis rules '
        'fire', () {
      // flat weight, constant reps -> plateau + rep-monotony diagnosis
      final d = _analyse(series((_) => 100));
      expect(d.strengthStatus, PlateauStatus.plateau);
      expect(d.possibleExplanation, isNotNull);
      expect(d.possibleExplanation!.type, DiagnosisType.repMonotony);
    });

    test('regression status', () {
      final d = _analyse(series((i) => 70.0 + i * 5, n: 7));
      expect(d.strengthStatus, PlateauStatus.regressing);
    });

    test('volume-progressing suppression: flat e1RM with rising volume '
        'suppresses the concern and the explanation', () {
      final workouts = [
        for (var i = 0; i < 7; i++)
          WorkoutModel(
            id: 'w$i',
            date: Timestamp.fromDate(DateTime(2026, 6, 28 - i * 3)),
            exercises: [
              ExerciseEntry(
                name: 'Bench Press',
                sets: [
                  // newest sessions have more sets -> rising volume
                  for (var j = 0; j < 7 - i; j++)
                    WorkoutSet(weight: 100, reps: 3),
                ],
              ),
            ],
          ),
      ];
      final d = _analyse(workouts);
      expect(d.strengthStatus, PlateauStatus.plateau);
      expect(d.volumeStatus, PlateauStatus.progressing);
      expect(d.volumeProgressionSuppressed, isTrue);
      expect(d.possibleExplanation, isNull);
    });

    test('insufficient sessions: no status concern and no explanation', () {
      final d = _analyse(series((_) => 100, n: 4));
      expect(d.strengthStatus, PlateauStatus.insufficientData);
      expect(d.possibleExplanation, isNull);
    });
  });

  group('data quality and evidence', () {
    test('quality categories follow the documented per-exercise rules', () {
      expect(_analyse([]).dataQuality, DataQuality.insufficient);
      expect(
        _analyse([_workout(DateTime(2026, 6, 20))]).dataQuality,
        DataQuality.limited,
      );
      expect(
        _analyse([
          for (var i = 0; i < 6; i++)
            _workout(DateTime(2026, 6, 25 - i * 2), weight: 60.0 + i),
        ]).dataQuality,
        DataQuality.moderate,
      );
      expect(
        _analyse([
          for (var i = 0; i < 10; i++)
            _workout(DateTime(2026, 6, 27 - i * 2), weight: 60.0 + i),
        ]).dataQuality,
        DataQuality.strong,
      );
    });

    test('evidence carries session count vs the trend minimum, and change '
        'observations with periods', () {
      final d = _analyse([
        _workout(DateTime(2026, 5, 20), weight: 60),
        _workout(DateTime(2026, 6, 20), weight: 66),
      ]);
      final countEvidence = d.evidence.singleWhere(
        (e) => e.metric == MetricType.workoutCount,
      );
      expect(countEvidence.observedValue, 2);
      expect(
        countEvidence.comparisonValue,
        PlateauDetector.minSessions.toDouble(),
      );
      expect(countEvidence.dataSufficient, isFalse);

      final strengthEvidence = d.evidence.singleWhere(
        (e) => e.metric == MetricType.estimatedOneRepMax,
      );
      expect(
        strengthEvidence.observedValue,
        closeTo(estimatedOneRepMax(66, 5), 1e-9),
      );
      expect(
        strengthEvidence.comparisonValue,
        closeTo(estimatedOneRepMax(60, 5), 1e-9),
      );
      expect(strengthEvidence.period, isNotNull);
    });

    test('unavailable changes contribute no change evidence (absence is '
        'explicit, not zero)', () {
      final d = _analyse([_workout(DateTime(2026, 6, 20))]);
      expect(
        d.evidence.where((e) => e.metric == MetricType.estimatedOneRepMax),
        isEmpty,
      );
    });
  });

  test('injected reference date shifts every window deterministically', () {
    final workouts = [_workout(DateTime(2026, 6, 20), weight: 80)];
    final now = ExerciseAnalyticsService.analyseExercise(
      workouts,
      'Bench Press',
      referenceDate: ref,
    );
    final later = ExerciseAnalyticsService.analyseExercise(
      workouts,
      'Bench Press',
      referenceDate: DateTime(2026, 9, 1),
    );
    expect(now.recentBest.isAvailable, isTrue);
    expect(later.recentBest.isAvailable, isFalse); // outside the new window
    expect(later.sessionsPerWeek.valueOrNull, 0);
  });
}
