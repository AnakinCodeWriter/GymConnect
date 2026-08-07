import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/models/analytics.dart';
import 'package:gymconnect/models/weekly_review.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/services/weekly_review_service.dart';
import 'package:gymconnect/utils/fitness_formulas.dart';

// Reference date: Wednesday 1 July 2026.
// Review week: Mon 29 Jun - Sun 5 Jul. Previous: Mon 22 - Sun 28 Jun.
final ref = DateTime(2026, 7, 1, 12);

int _id = 0;

WorkoutModel _workout(
  DateTime date, {
  String exercise = 'Bench Press',
  double weight = 60,
  int reps = 5,
  int? feel,
  List<ExerciseEntry>? exercises,
}) => WorkoutModel(
  id: 'w-${_id++}',
  date: Timestamp.fromDate(date),
  feelRating: feel,
  exercises:
      exercises ??
      [
        ExerciseEntry(
          name: exercise,
          sets: [WorkoutSet(weight: weight, reps: reps)],
        ),
      ],
);

/// Six sessions every 4 days ending 30 Jun (all inside the 28-day
/// top-exercise window), with the given max weights oldest -> newest.
List<WorkoutModel> _trendHistory(
  List<double> weights, {
  String exercise = 'Bench Press',
}) => [
  for (var i = 0; i < weights.length; i++)
    _workout(
      DateTime(2026, 6, 30 - 4 * (weights.length - 1 - i)),
      exercise: exercise,
      weight: weights[i],
    ),
];

WeeklyReview _build(List<WorkoutModel> workouts, {int skipped = 0}) =>
    WeeklyReviewService.build(
      workouts,
      referenceDate: ref,
      skippedRecords: skipped,
    );

bool _has(List<ReviewFinding> findings, ReviewFindingKind kind) =>
    findings.any((f) => f.kind == kind);

ReviewFinding _find(List<ReviewFinding> findings, ReviewFindingKind kind) =>
    findings.firstWhere((f) => f.kind == kind);

bool _hasAction(WeeklyReview r, SuggestedActionKind kind) =>
    r.actions.any((a) => a.kind == kind);

void main() {
  setUp(() => _id = 0);

  group('availability and history size', () {
    test(
      'no workout history: noData, empty sections, insufficient quality',
      () {
        final r = _build([]);
        expect(r.availability, ReviewAvailability.noData);
        expect(r.improvements, isEmpty);
        expect(r.stable, isEmpty);
        expect(r.attention, isEmpty);
        expect(r.actions, isEmpty);
        expect(r.dataQuality, DataQuality.insufficient);
        expect(r.totalWorkouts, 0);
      },
    );

    test('one workout this week: available, insufficient-history finding '
        'and log-more-sessions action', () {
      final r = _build([_workout(DateTime(2026, 6, 30))]);
      expect(r.availability, ReviewAvailability.available);
      expect(r.workoutsThisWeek, 1);
      expect(_has(r.attention, ReviewFindingKind.insufficientHistory), isTrue);
      final f = _find(r.attention, ReviewFindingKind.insufficientHistory);
      expect(f.observedValue, 1);
      expect(
        f.comparisonValue,
        WeeklyReviewService.minHistoryForConclusions.toDouble(),
      );
      expect(f.evidence.single.dataSufficient, isFalse);
      expect(_hasAction(r, SuggestedActionKind.logMoreSessions), isTrue);
    });

    test('multiple workouts this week are all counted', () {
      final r = _build([
        _workout(DateTime(2026, 6, 29)),
        _workout(DateTime(2026, 6, 30)),
        _workout(DateTime(2026, 7, 1)),
      ]);
      expect(r.workoutsThisWeek, 3);
      expect(r.workoutsPreviousWeek, 0);
    });

    test('data quality follows the shared dashboard mapping', () {
      List<WorkoutModel> history(int n) => [
        for (var i = 0; i < n; i++) _workout(DateTime(2026, 6, 30 - i)),
      ];
      expect(_build([]).dataQuality, DataQuality.insufficient);
      expect(_build(history(3)).dataQuality, DataQuality.limited);
      expect(_build(history(10)).dataQuality, DataQuality.moderate);
      expect(_build(history(20)).dataQuality, DataQuality.strong);
    });
  });

  group('week boundaries and reference date', () {
    test('Monday-Sunday boundary: Sunday belongs to the previous week', () {
      final r = _build([
        _workout(DateTime(2026, 6, 28, 23)), // Sunday previous week
        _workout(DateTime(2026, 6, 29, 0, 30)), // Monday review week
      ]);
      expect(r.week.start, DateTime(2026, 6, 29));
      expect(r.week.end, DateTime(2026, 7, 5));
      expect(r.workoutsThisWeek, 1);
      expect(r.workoutsPreviousWeek, 1);
    });

    test('injected reference date moves the review week', () {
      final workouts = [_workout(DateTime(2026, 6, 24))];
      final thatWeek = WeeklyReviewService.build(
        workouts,
        referenceDate: DateTime(2026, 6, 24),
      );
      final nextWeek = _build(workouts);
      expect(thatWeek.workoutsThisWeek, 1);
      expect(nextWeek.workoutsThisWeek, 0);
      expect(nextWeek.workoutsPreviousWeek, 1);
    });
  });

  group('workout count comparisons', () {
    test('increased count is an improvement with evidence', () {
      final r = _build([
        _workout(DateTime(2026, 6, 29)),
        _workout(DateTime(2026, 6, 30)),
        _workout(DateTime(2026, 7, 1)),
        _workout(DateTime(2026, 6, 23)),
        _workout(DateTime(2026, 6, 25)),
      ]);
      final f = _find(r.improvements, ReviewFindingKind.workoutCountIncreased);
      expect(f.observedValue, 3);
      expect(f.comparisonValue, 2);
      expect(f.evidence, isNotEmpty);
      expect(
        _has(r.attention, ReviewFindingKind.workoutCountDecreased),
        isFalse,
      );
    });

    test('a first-ever training week is not reported as "up" against an '
        'empty previous week', () {
      final r = _build([
        _workout(DateTime(2026, 6, 29)),
        _workout(DateTime(2026, 6, 30)),
      ]);
      expect(
        _has(r.improvements, ReviewFindingKind.workoutCountIncreased),
        isFalse,
      );
    });

    test('decreased count needs attention', () {
      final r = _build([
        _workout(DateTime(2026, 6, 30)),
        _workout(DateTime(2026, 6, 22)),
        _workout(DateTime(2026, 6, 24)),
        _workout(DateTime(2026, 6, 26)),
      ]);
      final f = _find(r.attention, ReviewFindingKind.workoutCountDecreased);
      expect(f.observedValue, 1);
      expect(f.comparisonValue, 3);
      expect(f.severity, Severity.caution);
    });

    test('unchanged count is stable', () {
      final r = _build([
        _workout(DateTime(2026, 6, 29)),
        _workout(DateTime(2026, 6, 30)),
        _workout(DateTime(2026, 6, 23)),
        _workout(DateTime(2026, 6, 25)),
      ]);
      expect(_has(r.stable, ReviewFindingKind.workoutCountStable), isTrue);
    });

    test('zero workouts this week reports only noTrainingThisWeek, never '
        'also "decreased"', () {
      final r = _build([
        _workout(DateTime(2026, 6, 23)),
        _workout(DateTime(2026, 6, 25)),
        _workout(DateTime(2026, 6, 27)),
      ]);
      expect(_has(r.attention, ReviewFindingKind.noTrainingThisWeek), isTrue);
      expect(
        _has(r.attention, ReviewFindingKind.workoutCountDecreased),
        isFalse,
      );
    });
  });

  group('weekly volume comparisons', () {
    test('increase beyond the band is an improvement', () {
      final r = _build([
        _workout(DateTime(2026, 6, 24)), // 60x5 = 300 kg
        _workout(
          DateTime(2026, 6, 30),
          exercises: [
            ExerciseEntry(
              name: 'Bench Press',
              sets: [
                WorkoutSet(weight: 60, reps: 5),
                WorkoutSet(weight: 60, reps: 5),
              ],
            ),
          ],
        ), // 600 kg: +100%
      ]);
      final f = _find(r.improvements, ReviewFindingKind.volumeIncreased);
      expect(f.observedValue, 600);
      expect(f.comparisonValue, 300);
      expect(_has(r.stable, ReviewFindingKind.volumeStable), isFalse);
    });

    test('decrease beyond the band needs attention', () {
      final r = _build([
        _workout(DateTime(2026, 6, 24), weight: 100, reps: 5), // 500 kg
        _workout(DateTime(2026, 6, 30), weight: 40, reps: 5), // 200 kg
      ]);
      final f = _find(r.attention, ReviewFindingKind.volumeDecreased);
      expect(f.observedValue, 200);
      expect(f.comparisonValue, 500);
    });

    test('change inside the band is stable', () {
      final r = _build([
        _workout(DateTime(2026, 6, 24), weight: 100, reps: 5), // 500 kg
        _workout(DateTime(2026, 6, 30), weight: 102, reps: 5), // 510 kg: +2%
      ]);
      expect(_has(r.stable, ReviewFindingKind.volumeStable), isTrue);
      expect(_has(r.improvements, ReviewFindingKind.volumeIncreased), isFalse);
      expect(_has(r.attention, ReviewFindingKind.volumeDecreased), isFalse);
    });

    test('zero previous-week volume: comparison unavailable, no volume '
        'finding is fabricated', () {
      final r = _build([
        // previous week: one workout of only warm-up sets (volume 0)
        _workout(
          DateTime(2026, 6, 24),
          exercises: [
            ExerciseEntry(
              name: 'Bench Press',
              sets: [WorkoutSet(weight: 60, reps: 5, isWarmup: true)],
            ),
          ],
        ),
        _workout(DateTime(2026, 6, 30)),
      ]);
      expect(r.volumeChange.isAvailable, isFalse);
      expect(
        (r.volumeChange as MetricUnavailable).reason,
        InsufficiencyReason.zeroBaseline,
      );
      expect(_has(r.improvements, ReviewFindingKind.volumeIncreased), isFalse);
      expect(_has(r.stable, ReviewFindingKind.volumeStable), isFalse);
      expect(_has(r.attention, ReviewFindingKind.volumeDecreased), isFalse);
    });
  });

  group('personal records', () {
    test('a PR inside the review week is an improvement', () {
      final r = _build([
        _workout(DateTime(2026, 6, 10), weight: 60),
        _workout(DateTime(2026, 6, 20), weight: 62.5),
        _workout(DateTime(2026, 6, 30), weight: 70),
      ]);
      final f = _find(r.improvements, ReviewFindingKind.newPersonalRecord);
      expect(f.exercise, 'Bench Press');
      expect(f.observedValue, closeTo(estimatedOneRepMax(70, 5), 0.001));
      expect(f.evidence, isNotEmpty);
    });

    test('a first-ever session is never a record', () {
      final r = _build([_workout(DateTime(2026, 6, 30), weight: 100)]);
      expect(
        _has(r.improvements, ReviewFindingKind.newPersonalRecord),
        isFalse,
      );
    });

    test('warm-up sets cannot create a record', () {
      final r = _build([
        _workout(DateTime(2026, 6, 10), weight: 60),
        _workout(DateTime(2026, 6, 20), weight: 60),
        _workout(
          DateTime(2026, 6, 30),
          exercises: [
            ExerciseEntry(
              name: 'Bench Press',
              sets: [
                WorkoutSet(weight: 100, reps: 5, isWarmup: true),
                WorkoutSet(weight: 50, reps: 5),
              ],
            ),
          ],
        ),
      ]);
      expect(
        _has(r.improvements, ReviewFindingKind.newPersonalRecord),
        isFalse,
      );
    });
  });

  group('exercise trends', () {
    test('progressing trend: improvement finding plus maintain action', () {
      final r = _build(_trendHistory([60, 62.5, 65, 67.5, 70, 72.5]));
      final f = _find(r.improvements, ReviewFindingKind.exerciseProgressing);
      expect(f.exercise, 'Bench Press');
      expect(f.evidence.single.observedValue, 6); // sessions backing it
      expect(
        _hasAction(r, SuggestedActionKind.maintainCurrentStructure),
        isTrue,
      );
      expect(_hasAction(r, SuggestedActionKind.considerVolumeReview), isFalse);
      expect(
        _hasAction(r, SuggestedActionKind.reviewRecoveryAndTechnique),
        isFalse,
      );
    });

    test('plateau: caution finding plus volume-review action, no maintain '
        'action', () {
      final r = _build(_trendHistory([60, 60, 60, 60, 60, 60]));
      final f = _find(r.attention, ReviewFindingKind.possiblePlateau);
      expect(f.exercise, 'Bench Press');
      expect(f.severity, Severity.caution);
      final action = r.actions.firstWhere(
        (a) => a.kind == SuggestedActionKind.considerVolumeReview,
      );
      expect(action.exercise, 'Bench Press');
      expect(action.evidence, isNotEmpty);
      expect(
        _hasAction(r, SuggestedActionKind.maintainCurrentStructure),
        isFalse,
      );
    });

    test('regression: warning finding plus recovery/technique action', () {
      final r = _build(_trendHistory([70, 68, 66, 64, 62, 60]));
      final f = _find(r.attention, ReviewFindingKind.possibleRegression);
      expect(f.severity, Severity.warning);
      final action = r.actions.firstWhere(
        (a) => a.kind == SuggestedActionKind.reviewRecoveryAndTechnique,
      );
      expect(action.exercise, 'Bench Press');
      expect(action.evidence, isNotEmpty);
    });

    test('flat e1RM with rising volume is reported stable, not a concern '
        '(suppression rule)', () {
      final workouts = [
        for (var i = 0; i < 6; i++)
          _workout(
            DateTime(2026, 6, 30 - 4 * (5 - i)),
            exercises: [
              ExerciseEntry(
                name: 'Bench Press',
                sets: [
                  WorkoutSet(weight: 100, reps: 5),
                  // volume grows every session; e1RM stays 100-based
                  for (var s = 0; s < i * 2; s++)
                    WorkoutSet(weight: 60, reps: 10),
                ],
              ),
            ],
          ),
      ];
      final r = _build(workouts);
      final f = _find(r.stable, ReviewFindingKind.exerciseVolumeRising);
      expect(f.exercise, 'Bench Press');
      expect(_has(r.attention, ReviewFindingKind.possiblePlateau), isFalse);
      expect(_has(r.attention, ReviewFindingKind.possibleRegression), isFalse);
      expect(_hasAction(r, SuggestedActionKind.considerVolumeReview), isFalse);
    });

    test('too few sessions: no trend finding of any kind', () {
      final r = _build(_trendHistory([60, 62.5, 65, 67.5])); // 4 < minimum
      expect(
        _has(r.improvements, ReviewFindingKind.exerciseProgressing),
        isFalse,
      );
      expect(_has(r.attention, ReviewFindingKind.possiblePlateau), isFalse);
      expect(_has(r.attention, ReviewFindingKind.possibleRegression), isFalse);
    });
  });

  group('repeated exercises', () {
    test('exercises trained in both weeks are a stable finding '
        '(case-insensitive match)', () {
      final r = _build([
        _workout(DateTime(2026, 6, 24), exercise: 'bench press'),
        _workout(DateTime(2026, 6, 30), exercise: 'Bench Press'),
        _workout(DateTime(2026, 6, 30), exercise: 'Squat'), // this week only
      ]);
      final f = _find(r.stable, ReviewFindingKind.repeatedExercises);
      expect(f.exercises, ['Bench Press']);
      expect(f.observedValue, 1);
    });

    test('no repeated finding when the weeks share no exercise', () {
      final r = _build([
        _workout(DateTime(2026, 6, 24), exercise: 'Squat'),
        _workout(DateTime(2026, 6, 30), exercise: 'Bench Press'),
      ]);
      expect(_has(r.stable, ReviewFindingKind.repeatedExercises), isFalse);
    });
  });

  group('session feel', () {
    test('absent feel data: averages unavailable, keep-logging-feel action '
        'when the week was trained', () {
      final r = _build([
        _workout(DateTime(2026, 6, 29)),
        _workout(DateTime(2026, 6, 30)),
      ]);
      expect(r.feel.averageThisWeek.isAvailable, isFalse);
      expect(
        (r.feel.averageThisWeek as MetricUnavailable).reason,
        InsufficiencyReason.noData,
      );
      expect(_hasAction(r, SuggestedActionKind.keepLoggingFeel), isTrue);
      expect(_has(r.improvements, ReviewFindingKind.feelImproved), isFalse);
      expect(_has(r.attention, ReviewFindingKind.feelDeclined), isFalse);
    });

    test('sparse feel data (one rating) stays unavailable rather than '
        'becoming an invented trend', () {
      final r = _build([
        _workout(DateTime(2026, 6, 29), feel: 2),
        _workout(DateTime(2026, 6, 30)),
      ]);
      final unavailable = r.feel.averageThisWeek as MetricUnavailable;
      expect(unavailable.reason, InsufficiencyReason.tooFewSessions);
      expect(unavailable.observedCount, 1);
      expect(_hasAction(r, SuggestedActionKind.keepLoggingFeel), isTrue);
      expect(_has(r.attention, ReviewFindingKind.lowFeelWeek), isFalse);
    });

    test('declining feel is an attention finding (and suppresses the '
        'separate low-feel finding)', () {
      final r = _build([
        _workout(DateTime(2026, 6, 23), feel: 4),
        _workout(DateTime(2026, 6, 25), feel: 4),
        _workout(DateTime(2026, 6, 29), feel: 2),
        _workout(DateTime(2026, 6, 30), feel: 2),
      ]);
      final f = _find(r.attention, ReviewFindingKind.feelDeclined);
      expect(f.observedValue, 2);
      expect(f.comparisonValue, 4);
      expect(_has(r.attention, ReviewFindingKind.lowFeelWeek), isFalse);
      expect(_hasAction(r, SuggestedActionKind.keepLoggingFeel), isFalse);
    });

    test('improving feel is an improvement finding', () {
      final r = _build([
        _workout(DateTime(2026, 6, 23), feel: 2),
        _workout(DateTime(2026, 6, 25), feel: 3),
        _workout(DateTime(2026, 6, 29), feel: 4),
        _workout(DateTime(2026, 6, 30), feel: 5),
      ]);
      final f = _find(r.improvements, ReviewFindingKind.feelImproved);
      expect(f.observedValue, 4.5);
      expect(f.comparisonValue, 2.5);
    });

    test('a low-feel week without a decline is flagged on its own', () {
      final r = _build([
        _workout(DateTime(2026, 6, 29), feel: 2),
        _workout(DateTime(2026, 6, 30), feel: 2),
      ]);
      final f = _find(r.attention, ReviewFindingKind.lowFeelWeek);
      expect(f.observedValue, 2);
      expect(f.severity, Severity.caution);
    });

    test('similar feel across both weeks is stable', () {
      final r = _build([
        _workout(DateTime(2026, 6, 23), feel: 4),
        _workout(DateTime(2026, 6, 25), feel: 4),
        _workout(DateTime(2026, 6, 29), feel: 4),
        _workout(DateTime(2026, 6, 30), feel: 4),
      ]);
      expect(_has(r.stable, ReviewFindingKind.feelStable), isTrue);
    });
  });

  group('partial data', () {
    test(
      'skipped records surface as an attention finding and on the review',
      () {
        final r = _build([_workout(DateTime(2026, 6, 30))], skipped: 2);
        expect(r.skippedRecords, 2);
        final f = _find(r.attention, ReviewFindingKind.skippedRecords);
        expect(f.observedValue, 2);
        expect(f.evidence.single.dataSufficient, isFalse);
      },
    );
  });

  group('evidence and determinism', () {
    test('every finding and action carries evidence', () {
      final r = _build([
        ..._trendHistory([70, 68, 66, 64, 62, 60]),
        ..._trendHistory([60, 60, 60, 60, 60, 60], exercise: 'Squat'),
        _workout(DateTime(2026, 6, 29), feel: 2),
        _workout(DateTime(2026, 6, 30), feel: 2),
      ], skipped: 1);
      for (final f in [...r.improvements, ...r.stable, ...r.attention]) {
        expect(f.evidence, isNotEmpty, reason: '${f.kind} lacks evidence');
      }
      for (final a in r.actions) {
        expect(a.evidence, isNotEmpty, reason: '${a.kind} lacks evidence');
      }
    });

    test('no unsupported suggested action is ever produced', () {
      // A plateau-only scenario must not suggest recovery review or claim
      // progress; a progress-only scenario must not suggest volume review.
      final plateau = _build(_trendHistory([60, 60, 60, 60, 60, 60]));
      expect(
        _hasAction(plateau, SuggestedActionKind.reviewRecoveryAndTechnique),
        isFalse,
      );
      expect(
        _hasAction(plateau, SuggestedActionKind.maintainCurrentStructure),
        isFalse,
      );
      expect(_hasAction(plateau, SuggestedActionKind.logMoreSessions), isFalse);

      final progressing = _build(_trendHistory([60, 62.5, 65, 67.5, 70, 72.5]));
      expect(
        _hasAction(progressing, SuggestedActionKind.considerVolumeReview),
        isFalse,
      );
      expect(
        _hasAction(progressing, SuggestedActionKind.reviewRecoveryAndTechnique),
        isFalse,
      );
    });

    test('regressions are ordered before plateaus; output is stable across '
        'identical builds', () {
      final workouts = [
        ..._trendHistory([70, 68, 66, 64, 62, 60]), // Bench: regressing
        ..._trendHistory([60, 60, 60, 60, 60, 60], exercise: 'Squat'),
        _workout(DateTime(2026, 6, 29), feel: 2),
      ];
      final a = _build(workouts);
      final b = _build(workouts);

      expect(a.attention.first.kind, ReviewFindingKind.possibleRegression);
      expect(a.attention[1].kind, ReviewFindingKind.possiblePlateau);

      List<(ReviewFindingKind, String?)> kinds(List<ReviewFinding> l) => [
        for (final f in l) (f.kind, f.exercise),
      ];
      expect(kinds(a.improvements), kinds(b.improvements));
      expect(kinds(a.stable), kinds(b.stable));
      expect(kinds(a.attention), kinds(b.attention));
      expect(
        [for (final x in a.actions) (x.kind, x.exercise)],
        [for (final x in b.actions) (x.kind, x.exercise)],
      );
    });
  });
}
