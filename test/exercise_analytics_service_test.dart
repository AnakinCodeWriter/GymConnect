import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/models/analytics.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/services/exercise_analytics_service.dart';
import 'package:gymconnect/services/plateau_detector.dart';
import 'package:gymconnect/utils/fitness_formulas.dart';

WorkoutModel _workout(DateTime date, List<ExerciseEntry> exercises) =>
    WorkoutModel(
      id: 'w-${date.millisecondsSinceEpoch}-${exercises.length}',
      date: Timestamp.fromDate(date),
      exercises: exercises,
    );

ExerciseEntry _entry(String name, List<WorkoutSet> sets) =>
    ExerciseEntry(name: name, sets: sets);

WorkoutSet _set(double weight, int reps, {bool warmup = false}) =>
    WorkoutSet(weight: weight, reps: reps, isWarmup: warmup);

void main() {
  final base = DateTime(2026, 6, 1, 10);

  group('buildSeries', () {
    test('empty workout history produces an empty series', () {
      final series = ExerciseAnalyticsService.buildSeries([], 'Bench Press');
      expect(series.isEmpty, isTrue);
      expect(series.exerciseName, 'Bench Press');
    });

    test('no matching exercise produces an empty series', () {
      final workouts = [
        _workout(base, [
          _entry('Squat', [_set(100, 5)]),
        ]),
      ];
      final series = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Bench Press',
      );
      expect(series.isEmpty, isTrue);
    });

    test('matching is exact (trim + case-insensitive), not substring - '
        'regression for the pre-extraction chart defect', () {
      final workouts = [
        _workout(base, [
          _entry('Bench Press', [_set(60, 5)]),
          _entry('Incline Bench Press', [_set(200, 5)]),
        ]),
      ];
      final series = ExerciseAnalyticsService.buildSeries(
        workouts,
        '  bench press ',
      );
      expect(series.sessions, hasLength(1));
      // The 200 kg incline set must NOT leak into the Bench Press series.
      expect(
        series.sessions.single.bestE1RmKg,
        closeTo(estimatedOneRepMax(60, 5), 1e-9),
      );
      expect(series.sessions.single.volumeKg, 60 * 5);
    });

    test('warm-up-only sessions produce no series entry', () {
      final workouts = [
        _workout(base, [
          _entry('Bench Press', [_set(40, 10, warmup: true)]),
        ]),
      ];
      final series = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Bench Press',
      );
      expect(series.isEmpty, isTrue);
    });

    test('warm-up sets are excluded from best e1RM, volume and set count', () {
      final workouts = [
        _workout(base, [
          _entry('Bench Press', [
            _set(200, 10, warmup: true), // heavier warm-up must not count
            _set(60, 5),
            _set(60, 5),
          ]),
        ]),
      ];
      final s = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Bench Press',
      ).sessions.single;
      expect(s.bestE1RmKg, closeTo(estimatedOneRepMax(60, 5), 1e-9));
      expect(s.volumeKg, 600);
      expect(s.workingSetCount, 2);
    });

    test('one valid session: best e1RM is the max across its sets', () {
      final workouts = [
        _workout(base, [
          _entry('Bench Press', [_set(60, 5), _set(65, 3), _set(55, 8)]),
        ]),
      ];
      final s = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Bench Press',
      ).sessions.single;
      final expected = [
        estimatedOneRepMax(60, 5),
        estimatedOneRepMax(65, 3),
        estimatedOneRepMax(55, 8),
      ].reduce((a, b) => a > b ? a : b);
      expect(s.bestE1RmKg, closeTo(expected, 1e-9));
      expect(s.volumeKg, 60 * 5 + 65 * 3 + 55 * 8);
      expect(s.workingSetCount, 3);
    });

    test('multiple exercises in one workout: only the target contributes', () {
      final workouts = [
        _workout(base, [
          _entry('Squat', [_set(140, 5)]),
          _entry('Bench Press', [_set(60, 5)]),
        ]),
      ];
      final s = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Bench Press',
      ).sessions.single;
      expect(s.volumeKg, 300);
    });

    test('duplicate same-named entries in one workout are all counted - '
        'regression for the pre-extraction volume break defect', () {
      final workouts = [
        _workout(base, [
          _entry('Bench Press', [_set(60, 5)]),
          _entry('Bench Press', [_set(70, 3)]),
        ]),
      ];
      final s = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Bench Press',
      ).sessions.single;
      expect(s.volumeKg, 60 * 5 + 70 * 3);
      expect(s.bestE1RmKg, closeTo(estimatedOneRepMax(70, 3), 1e-9));
      expect(s.workingSetCount, 2);
    });

    test('two workouts on the same calendar day merge into one session: '
        'best is max, volume is sum', () {
      final workouts = [
        _workout(DateTime(2026, 6, 1, 7), [
          _entry('Bench Press', [_set(60, 5)]),
        ]),
        _workout(DateTime(2026, 6, 1, 19), [
          _entry('Bench Press', [_set(70, 2)]),
        ]),
      ];
      final series = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Bench Press',
      );
      expect(series.sessions, hasLength(1));
      final s = series.sessions.single;
      expect(s.day, DateTime(2026, 6, 1));
      expect(s.bestE1RmKg, closeTo(estimatedOneRepMax(70, 2), 1e-9));
      expect(s.volumeKg, 60 * 5 + 70 * 2);
    });

    test('duplicate identical timestamps also merge into one session', () {
      final t = DateTime(2026, 6, 1, 10);
      final workouts = [
        _workout(t, [
          _entry('Bench Press', [_set(60, 5)]),
        ]),
        _workout(t, [
          _entry('Bench Press', [_set(62.5, 5)]),
        ]),
      ];
      final series = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Bench Press',
      );
      expect(series.sessions, hasLength(1));
      expect(series.sessions.single.volumeKg, 60 * 5 + 62.5 * 5);
    });

    test('sessions are ordered ascending by day regardless of input order', () {
      final workouts = [
        _workout(DateTime(2026, 6, 10), [
          _entry('Bench Press', [_set(65, 5)]),
        ]),
        _workout(DateTime(2026, 6, 1), [
          _entry('Bench Press', [_set(60, 5)]),
        ]),
        _workout(DateTime(2026, 6, 5), [
          _entry('Bench Press', [_set(62.5, 5)]),
        ]),
      ];
      final days = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Bench Press',
      ).sessions.map((s) => s.day).toList();
      expect(days, [
        DateTime(2026, 6, 1),
        DateTime(2026, 6, 5),
        DateTime(2026, 6, 10),
      ]);
    });

    test('high-rep sets use the capped Epley formula (reps capped at 10)', () {
      final workouts = [
        _workout(base, [
          _entry('Bench Press', [_set(100, 15)]),
        ]),
      ];
      final s = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Bench Press',
      ).sessions.single;
      expect(s.bestE1RmKg, closeTo(estimatedOneRepMax(100, 10), 1e-9));
      // Volume still uses the real rep count.
      expect(s.volumeKg, 1500);
    });

    test('zero weight is a valid value: e1RM 0, volume 0, set counted', () {
      final workouts = [
        _workout(base, [
          _entry('Push Up', [_set(0, 12)]),
        ]),
      ];
      final s = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Push Up',
      ).sessions.single;
      expect(s.bestE1RmKg, 0);
      expect(s.volumeKg, 0);
      expect(s.workingSetCount, 1);
    });

    test('malformed sets (negative weight, reps < 1) are ignored and do not '
        'distort valid sets in the same session', () {
      final workouts = [
        _workout(base, [
          _entry('Bench Press', [
            _set(-50, 5), // negative weight - ignored
            _set(60, 0), // zero reps - ignored
            _set(60, -2), // negative reps - ignored
            _set(60, 5), // valid
          ]),
        ]),
      ];
      final s = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Bench Press',
      ).sessions.single;
      expect(s.workingSetCount, 1);
      expect(s.volumeKg, 300);
      expect(s.bestE1RmKg, closeTo(estimatedOneRepMax(60, 5), 1e-9));
    });

    test('a session containing only malformed sets produces no entry', () {
      final workouts = [
        _workout(base, [
          _entry('Bench Press', [_set(-50, 5), _set(60, 0)]),
        ]),
      ];
      expect(
        ExerciseAnalyticsService.buildSeries(workouts, 'Bench Press').isEmpty,
        isTrue,
      );
    });
  });

  group('e1RmTrend / volumeTrend', () {
    List<WorkoutModel> flatBench(int sessionCount) => [
      for (var i = 0; i < sessionCount; i++)
        _workout(base.add(Duration(days: i * 3)), [
          _entry('Bench Press', [_set(100, 5)]),
        ]),
    ];

    test('fewer than 5 sessions is insufficient data', () {
      final series = ExerciseAnalyticsService.buildSeries(
        flatBench(4),
        'Bench Press',
      );
      expect(
        ExerciseAnalyticsService.e1RmTrend(series).status,
        PlateauStatus.insufficientData,
      );
    });

    test('characterisation: flat weights classify as plateau', () {
      final series = ExerciseAnalyticsService.buildSeries(
        flatBench(6),
        'Bench Press',
      );
      expect(
        ExerciseAnalyticsService.e1RmTrend(series).status,
        PlateauStatus.plateau,
      );
    });

    test(
      'characterisation: steadily rising weights classify as progressing',
      () {
        final workouts = [
          for (var i = 0; i < 8; i++)
            _workout(base.add(Duration(days: i * 3)), [
              _entry('Bench Press', [_set(60 + i * 2.5, 5)]),
            ]),
        ];
        final series = ExerciseAnalyticsService.buildSeries(
          workouts,
          'Bench Press',
        );
        expect(
          ExerciseAnalyticsService.e1RmTrend(series).status,
          PlateauStatus.progressing,
        );
      },
    );

    test(
      'characterisation: flat top weight with rising set count is an e1RM '
      'plateau but a progressing volume trend (Volume Progressing state)',
      () {
        final workouts = [
          for (var i = 0; i < 7; i++)
            _workout(base.add(Duration(days: i * 3)), [
              _entry('Deadlift', [for (var j = 0; j <= i; j++) _set(120, 3)]),
            ]),
        ];
        final series = ExerciseAnalyticsService.buildSeries(
          workouts,
          'Deadlift',
        );
        expect(
          ExerciseAnalyticsService.e1RmTrend(series).status,
          PlateauStatus.plateau,
        );
        expect(
          ExerciseAnalyticsService.volumeTrend(series).status,
          PlateauStatus.progressing,
        );
      },
    );

    test('zero-volume sessions are excluded from the volume trend '
        '(preserved legacy behaviour)', () {
      // 4 weighted sessions + 2 bodyweight-only (zero volume) sessions:
      // the volume trend sees only 4 points -> insufficient data.
      final workouts = [
        for (var i = 0; i < 4; i++)
          _workout(base.add(Duration(days: i * 3)), [
            _entry('Bench Press', [_set(60, 5)]),
          ]),
        for (var i = 4; i < 6; i++)
          _workout(base.add(Duration(days: i * 3)), [
            _entry('Bench Press', [_set(0, 12)]),
          ]),
      ];
      final series = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Bench Press',
      );
      expect(series.sessions, hasLength(6));
      expect(
        ExerciseAnalyticsService.volumeTrend(series).status,
        PlateauStatus.insufficientData,
      );
    });
  });

  group('trainingFrequencyPerWeek', () {
    List<WorkoutModel> benchOn(List<int> dayOffsets) => [
      for (final d in dayOffsets)
        _workout(base.add(Duration(days: d)), [
          _entry('Bench Press', [_set(60, 5)]),
        ]),
    ];

    test('empty series is unavailable (noData)', () {
      final series = ExerciseAnalyticsService.buildSeries([], 'Bench Press');
      final r = ExerciseAnalyticsService.trainingFrequencyPerWeek(
        series,
        DatePeriod.lastDays(28, endingOn: DateTime(2026, 6, 30)),
      );
      expect(r, isA<MetricUnavailable<double>>());
      expect(
        (r as MetricUnavailable<double>).reason,
        InsufficiencyReason.noData,
      );
    });

    test('history exists but none in the period is a genuine zero', () {
      final series = ExerciseAnalyticsService.buildSeries(
        benchOn([0, 3]),
        'Bench Press',
      ); // early June only
      final r = ExerciseAnalyticsService.trainingFrequencyPerWeek(
        series,
        DatePeriod(DateTime(2026, 7, 1), DateTime(2026, 7, 28)),
      );
      expect(r.valueOrNull, 0);
    });

    test('8 sessions across a 28-day period is 2 per week, counting only '
        'sessions inside the period (week-boundary behaviour)', () {
      // Period: 3 June .. 30 June inclusive (28 days). Sessions on 1 and
      // 2 June fall outside and must not count; 8 sessions inside.
      final series = ExerciseAnalyticsService.buildSeries(
        benchOn([0, 1, 2, 5, 9, 12, 16, 19, 23, 26]), // 1 June + offsets
        'Bench Press',
      );
      final r = ExerciseAnalyticsService.trainingFrequencyPerWeek(
        series,
        DatePeriod(DateTime(2026, 6, 3), DateTime(2026, 6, 30)),
      );
      expect(r.valueOrNull, closeTo(2.0, 1e-9));
    });

    test('non-multiple-of-7 period lengths scale correctly', () {
      // 2 sessions in a 10-day period -> 2 / (10/7) = 1.4 per week.
      final series = ExerciseAnalyticsService.buildSeries(
        benchOn([0, 4]),
        'Bench Press',
      );
      final r = ExerciseAnalyticsService.trainingFrequencyPerWeek(
        series,
        DatePeriod(DateTime(2026, 6, 1), DateTime(2026, 6, 10)),
      );
      expect(r.valueOrNull, closeTo(1.4, 1e-9));
    });

    test('injected reference date defines the window deterministically', () {
      final series = ExerciseAnalyticsService.buildSeries(
        benchOn([0, 3, 6]),
        'Bench Press',
      ); // 1, 4, 7 June
      // Window ending 7 June includes all 3; window ending 30 June has none
      // in its last 7 days.
      final upTo7th = ExerciseAnalyticsService.trainingFrequencyPerWeek(
        series,
        DatePeriod.lastDays(7, endingOn: DateTime(2026, 6, 7)),
      );
      final upTo30th = ExerciseAnalyticsService.trainingFrequencyPerWeek(
        series,
        DatePeriod.lastDays(7, endingOn: DateTime(2026, 6, 30)),
      );
      expect(upTo7th.valueOrNull, closeTo(3.0, 1e-9));
      expect(upTo30th.valueOrNull, 0);
    });
  });

  group('bestE1RmIn', () {
    test('returns the best session e1RM within the period only', () {
      final workouts = [
        _workout(DateTime(2026, 6, 1), [
          _entry('Bench Press', [_set(80, 5)]), // outside period
        ]),
        _workout(DateTime(2026, 6, 10), [
          _entry('Bench Press', [_set(70, 5)]),
        ]),
        _workout(DateTime(2026, 6, 12), [
          _entry('Bench Press', [_set(75, 5)]),
        ]),
      ];
      final series = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Bench Press',
      );
      final r = ExerciseAnalyticsService.bestE1RmIn(
        series,
        DatePeriod(DateTime(2026, 6, 8), DateTime(2026, 6, 14)),
      );
      expect(r.valueOrNull, closeTo(estimatedOneRepMax(75, 5), 1e-9));
    });

    test('no sessions in the period is unavailable (noData)', () {
      final workouts = [
        _workout(DateTime(2026, 6, 1), [
          _entry('Bench Press', [_set(80, 5)]),
        ]),
      ];
      final series = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Bench Press',
      );
      final r = ExerciseAnalyticsService.bestE1RmIn(
        series,
        DatePeriod(DateTime(2026, 7, 1), DateTime(2026, 7, 7)),
      );
      expect(r, isA<MetricUnavailable<double>>());
    });
  });

  group('percentageChange', () {
    final baselinePeriod = DatePeriod(
      DateTime(2026, 6, 1),
      DateTime(2026, 6, 7),
    );
    final currentPeriod = DatePeriod(
      DateTime(2026, 6, 8),
      DateTime(2026, 6, 14),
    );

    ExerciseSeries seriesWith({
      required double baselineWeight,
      required double currentWeight,
    }) {
      final workouts = [
        _workout(DateTime(2026, 6, 2), [
          _entry('Bench Press', [_set(baselineWeight, 5)]),
        ]),
        _workout(DateTime(2026, 6, 10), [
          _entry('Bench Press', [_set(currentWeight, 5)]),
        ]),
      ];
      return ExerciseAnalyticsService.buildSeries(workouts, 'Bench Press');
    }

    test('increase: best e1RM 60 -> 66 kg is +10%', () {
      final r = ExerciseAnalyticsService.percentageChange(
        seriesWith(baselineWeight: 60, currentWeight: 66),
        metric: SessionMetric.bestE1Rm,
        baseline: baselinePeriod,
        current: currentPeriod,
      );
      final change = r.valueOrNull!;
      expect(change.percent, closeTo(10, 1e-9));
      expect(change.direction, ChangeDirection.increase);
      expect(change.baselinePeriod, baselinePeriod);
      expect(change.currentPeriod, currentPeriod);
    });

    test('decrease: best e1RM 60 -> 54 kg is -10%', () {
      final r = ExerciseAnalyticsService.percentageChange(
        seriesWith(baselineWeight: 60, currentWeight: 54),
        metric: SessionMetric.bestE1Rm,
        baseline: baselinePeriod,
        current: currentPeriod,
      );
      expect(r.valueOrNull!.percent, closeTo(-10, 1e-9));
      expect(r.valueOrNull!.direction, ChangeDirection.decrease);
    });

    test('unchanged values are 0% with direction unchanged', () {
      final r = ExerciseAnalyticsService.percentageChange(
        seriesWith(baselineWeight: 60, currentWeight: 60),
        metric: SessionMetric.bestE1Rm,
        baseline: baselinePeriod,
        current: currentPeriod,
      );
      expect(r.valueOrNull!.percent, 0);
      expect(r.valueOrNull!.direction, ChangeDirection.unchanged);
    });

    test('very small differences near display-rounding boundaries keep '
        'their true direction (rounding is presentation-only)', () {
      // 60 -> 60.001 kg: displays would round to the same value, but the
      // typed result must still report a tiny increase, not "unchanged".
      final r = ExerciseAnalyticsService.percentageChange(
        seriesWith(baselineWeight: 60, currentWeight: 60.001),
        metric: SessionMetric.bestE1Rm,
        baseline: baselinePeriod,
        current: currentPeriod,
      );
      final change = r.valueOrNull!;
      expect(change.percent, greaterThan(0));
      expect(change.percent, lessThan(0.01));
      expect(change.direction, ChangeDirection.increase);
    });

    test(
      'zero baseline is unavailable(zeroBaseline), never 0% or infinity',
      () {
        final r = ExerciseAnalyticsService.percentageChange(
          seriesWith(baselineWeight: 0, currentWeight: 60),
          metric: SessionMetric.bestE1Rm,
          baseline: baselinePeriod,
          current: currentPeriod,
        );
        expect(r, isA<MetricUnavailable<PercentageChange>>());
        expect(
          (r as MetricUnavailable<PercentageChange>).reason,
          InsufficiencyReason.zeroBaseline,
        );
      },
    );

    test('current zero against a positive baseline is a genuine -100%', () {
      final r = ExerciseAnalyticsService.percentageChange(
        seriesWith(baselineWeight: 60, currentWeight: 0),
        metric: SessionMetric.bestE1Rm,
        baseline: baselinePeriod,
        current: currentPeriod,
      );
      expect(r.valueOrNull!.percent, closeTo(-100, 1e-9));
    });

    test('a period without sessions is unavailable (noData)', () {
      final workouts = [
        _workout(DateTime(2026, 6, 2), [
          _entry('Bench Press', [_set(60, 5)]),
        ]),
      ];
      final series = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Bench Press',
      );
      final r = ExerciseAnalyticsService.percentageChange(
        series,
        metric: SessionMetric.bestE1Rm,
        baseline: baselinePeriod,
        current: currentPeriod, // no sessions 8-14 June
      );
      expect(r, isA<MetricUnavailable<PercentageChange>>());
      expect(
        (r as MetricUnavailable<PercentageChange>).reason,
        InsufficiencyReason.noData,
      );
    });

    test('volume change aggregates by sum per period', () {
      // Baseline week: 60x5 + 60x5 = 600. Current week: 60x5 = 300 -> -50%.
      final workouts = [
        _workout(DateTime(2026, 6, 2), [
          _entry('Bench Press', [_set(60, 5), _set(60, 5)]),
        ]),
        _workout(DateTime(2026, 6, 10), [
          _entry('Bench Press', [_set(60, 5)]),
        ]),
      ];
      final series = ExerciseAnalyticsService.buildSeries(
        workouts,
        'Bench Press',
      );
      final r = ExerciseAnalyticsService.percentageChange(
        series,
        metric: SessionMetric.sessionVolume,
        baseline: baselinePeriod,
        current: currentPeriod,
      );
      expect(r.valueOrNull!.percent, closeTo(-50, 1e-9));
      expect(r.valueOrNull!.baselineValue, 600);
      expect(r.valueOrNull!.currentValue, 300);
    });
  });
}
