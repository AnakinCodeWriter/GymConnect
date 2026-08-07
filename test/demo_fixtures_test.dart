import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/demo/demo_fixtures.dart';
import 'package:gymconnect/demo/demo_plan.dart';
import 'package:gymconnect/demo/demo_seeder.dart';
import 'package:gymconnect/models/analytics.dart';
import 'package:gymconnect/models/dashboard.dart';
import 'package:gymconnect/models/weekly_review.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/services/dashboard_service.dart';
import 'package:gymconnect/services/exercise_analytics_service.dart';
import 'package:gymconnect/services/plateau_detector.dart';
import 'package:gymconnect/services/plateau_diagnosis_service.dart';
import 'package:gymconnect/services/weekly_review_service.dart';

// Fixed reference date: Friday 3 July 2026 (review week Mon 29 Jun–Sun
// 5 Jul). Scenarios schedule sessions relative to the reference date, and
// the weekly-review assertions here depend on this fixed weekday.
final ref = DateTime(2026, 7, 3, 18);

List<DemoWorkoutSpec> _specs(DemoScenario s) =>
    generateDemoWorkouts(s, referenceDate: ref);

List<WorkoutModel> _models(DemoScenario s) => [
  for (final spec in _specs(s)) DemoSeeder.toWorkoutModel(spec),
];

WeeklyReview _review(DemoScenario s) =>
    WeeklyReviewService.build(_models(s), referenceDate: ref);

PlateauResult _trend(DemoScenario s, String exercise) =>
    ExerciseAnalyticsService.e1RmTrend(
      ExerciseAnalyticsService.buildSeries(_models(s), exercise),
    );

void main() {
  group('generator invariants (all scenarios)', () {
    for (final scenario in DemoScenario.values) {
      test('${scenario.key}: deterministic for the same input', () {
        final a = _specs(scenario);
        final b = _specs(scenario);
        expect(a.length, b.length);
        for (var i = 0; i < a.length; i++) {
          expect(a[i].documentId, b[i].documentId);
          expect(a[i].date, b[i].date);
          expect(a[i].name, b[i].name);
          expect(a[i].feelRating, b[i].feelRating);
          expect(a[i].exercises.length, b[i].exercises.length);
          for (var e = 0; e < a[i].exercises.length; e++) {
            expect(a[i].exercises[e].name, b[i].exercises[e].name);
            expect(
              [
                for (final s in a[i].exercises[e].sets)
                  (s.weight, s.reps, s.isWarmup),
              ],
              [
                for (final s in b[i].exercises[e].sets)
                  (s.weight, s.reps, s.isWarmup),
              ],
            );
          }
        }
      });

      test('${scenario.key}: chronologically valid and before the reference '
          'date', () {
        final specs = _specs(scenario);
        expect(specs, isNotEmpty);
        for (var i = 0; i < specs.length; i++) {
          expect(specs[i].date.isBefore(ref), isTrue);
          if (i > 0) {
            expect(
              specs[i].date.isAfter(specs[i - 1].date),
              isTrue,
              reason: 'dates must ascend (rest-day gaps, no duplicates)',
            );
          }
        }
      });

      test('${scenario.key}: realistic, well-formed workouts', () {
        for (final spec in _specs(scenario)) {
          expect(spec.documentId, startsWith('demo-${scenario.key}-'));
          expect(spec.name, isNotEmpty);
          expect(spec.exercises, isNotEmpty);
          if (spec.feelRating != null) {
            expect(spec.feelRating, inInclusiveRange(1, 5));
          }
          for (final ex in spec.exercises) {
            expect(ex.name.trim(), isNotEmpty);
            expect(ex.sets, isNotEmpty);
            // max one warm-up per exercise (app convention), listed first.
            final warmups = ex.sets.where((s) => s.isWarmup).length;
            expect(warmups, lessThanOrEqualTo(1));
            for (final set in ex.sets) {
              expect(set.weight.isFinite, isTrue);
              expect(set.weight, greaterThan(0));
              expect(set.weight, lessThanOrEqualTo(200));
              expect(set.reps, inInclusiveRange(1, 12));
            }
          }
        }
      });

      test('${scenario.key}: round-trips through the stored WorkoutModel '
          'format', () {
        for (final spec in _specs(scenario)) {
          final model = DemoSeeder.toWorkoutModel(spec);
          final reparsed = WorkoutModel.fromMap(spec.documentId, model.toMap());
          expect(reparsed.exercises.length, spec.exercises.length);
          expect(reparsed.feelRating, spec.feelRating);
          expect(reparsed.date.toDate(), spec.date);
        }
      });
    }

    test('scenarios produce meaningfully different data', () {
      final benchTrends = {
        DemoScenario.progressing: _trend(
          DemoScenario.progressing,
          'Bench Press',
        ).status,
        DemoScenario.plateau: _trend(
          DemoScenario.plateau,
          'Bench Press',
        ).status,
      };
      expect(benchTrends[DemoScenario.progressing], PlateauStatus.progressing);
      expect(benchTrends[DemoScenario.plateau], PlateauStatus.plateau);
      // and the documents don't collide across scenarios
      final ids = <String>{};
      for (final s in DemoScenario.values) {
        for (final spec in _specs(s)) {
          expect(ids.add(spec.documentId), isTrue);
        }
      }
    });

    test(
      'demo tagging: payload carries workout fields plus all tag fields',
      () {
        final spec = _specs(DemoScenario.progressing).first;
        final payload = DemoSeeder.storedPayload(
          spec,
          scenario: DemoScenario.progressing,
          batchId: 'batch-1',
          generatedAt: DateTime.utc(2026, 7, 3, 12),
        );
        expect(isDemoDocument(payload), isTrue);
        expect(payload[demoFieldScenario], 'progressing');
        expect(payload[demoFieldBatchId], 'batch-1');
        expect(payload[demoFieldGeneratedAt], '2026-07-03T12:00:00.000Z');
        expect(payload['date'], isNotNull);
        expect(payload['exercises'], isNotEmpty);
        // tags never break normal parsing (unknown fields are ignored)
        expect(WorkoutModel.fromMap('x', payload).exercises, isNotEmpty);
      },
    );
  });

  group('progressing scenario', () {
    test('triggers progressing analytics, recent PRs and improving feel', () {
      final models = _models(DemoScenario.progressing);

      expect(
        _trend(DemoScenario.progressing, 'Bench Press').status,
        PlateauStatus.progressing,
      );
      expect(
        _trend(DemoScenario.progressing, 'Squat').status,
        PlateauStatus.progressing,
      );

      final dashboard = DashboardService.build(models, referenceDate: ref);
      expect(dashboard.status, TrainingStatus.progressing);
      expect(dashboard.trendWarnings, isEmpty);

      // PRs land inside the review week - but not every session is one.
      final prs = DashboardService.personalRecordsIn(
        models,
        DatePeriod.weekContaining(ref),
      );
      expect(prs, isNotEmpty);

      final review = _review(DemoScenario.progressing);
      expect(
        review.improvements.any(
          (f) => f.kind == ReviewFindingKind.exerciseProgressing,
        ),
        isTrue,
      );
      expect(
        review.improvements.any(
          (f) => f.kind == ReviewFindingKind.feelImproved,
        ),
        isTrue,
      );
      expect(
        review.attention.any((f) => f.severity == Severity.warning),
        isFalse,
      );
    });

    test('includes the substring exercise-name pair', () {
      final names = {
        for (final spec in _specs(DemoScenario.progressing))
          for (final ex in spec.exercises) ex.name,
      };
      expect(names, contains('Bench Press'));
      expect(names, contains('Incline Bench Press'));
    });
  });

  group('plateau scenario', () {
    test('Bench Press plateaus without volume suppression; a possible '
        'explanation is available', () {
      final models = _models(DemoScenario.plateau);
      expect(
        _trend(DemoScenario.plateau, 'Bench Press').status,
        PlateauStatus.plateau,
      );
      expect(
        ExerciseAnalyticsService.volumeTrend(
          ExerciseAnalyticsService.buildSeries(models, 'Bench Press'),
        ).status,
        isNot(PlateauStatus.progressing),
      );

      final review = _review(DemoScenario.plateau);
      final plateauFinding = review.attention.firstWhere(
        (f) => f.kind == ReviewFindingKind.possiblePlateau,
      );
      expect(plateauFinding.exercise, 'Bench Press');

      // diagnosis expects newest-first input (WorkoutService order)
      final diagnosis = PlateauDiagnosisService.analyse(
        models.reversed.toList(),
        'Bench Press',
        referenceDate: ref,
      );
      expect(diagnosis, isNotNull);
      expect(diagnosis!.type, DiagnosisType.repMonotony);
    });

    test('not everything plateaus at once: Squat and Deadlift progress', () {
      expect(
        _trend(DemoScenario.plateau, 'Squat').status,
        PlateauStatus.progressing,
      );
      expect(
        _trend(DemoScenario.plateau, 'Deadlift').status,
        PlateauStatus.progressing,
      );
    });
  });

  group('regression scenario', () {
    test('Overhead Press regresses with declining feel; other lifts still '
        'progress', () {
      expect(
        _trend(DemoScenario.regression, 'Overhead Press').status,
        PlateauStatus.regressing,
      );
      expect(
        _trend(DemoScenario.regression, 'Bench Press').status,
        PlateauStatus.progressing,
      );

      final review = _review(DemoScenario.regression);
      final regression = review.attention.firstWhere(
        (f) => f.kind == ReviewFindingKind.possibleRegression,
      );
      expect(regression.exercise, 'Overhead Press');
      expect(
        review.attention.any((f) => f.kind == ReviewFindingKind.feelDeclined),
        isTrue,
      );
    });
  });

  group('volume-progressing scenario', () {
    test('flat Deadlift e1RM with rising volume suppresses the plateau '
        'concern; sparse feel drives the keep-logging action', () {
      final models = _models(DemoScenario.volumeProgressing);
      final series = ExerciseAnalyticsService.buildSeries(models, 'Deadlift');
      expect(
        ExerciseAnalyticsService.e1RmTrend(series).status,
        PlateauStatus.plateau,
      );
      expect(
        ExerciseAnalyticsService.volumeTrend(series).status,
        PlateauStatus.progressing,
      );

      final review = _review(DemoScenario.volumeProgressing);
      expect(
        review.stable.any(
          (f) =>
              f.kind == ReviewFindingKind.exerciseVolumeRising &&
              f.exercise == 'Deadlift',
        ),
        isTrue,
      );
      expect(
        review.attention.any(
          (f) => f.kind == ReviewFindingKind.possiblePlateau,
        ),
        isFalse,
      );
      // only two rated sessions in the whole block -> feel stays sparse
      expect(review.feel.averageThisWeek.isAvailable, isFalse);
      expect(
        review.actions.any(
          (a) => a.kind == SuggestedActionKind.keepLoggingFeel,
        ),
        isTrue,
      );
    });
  });

  group('insufficient-data scenario', () {
    test('history and chart data exist but no trend is judged', () {
      final models = _models(DemoScenario.insufficientData);
      expect(models.length, 2);

      final dashboard = DashboardService.build(models, referenceDate: ref);
      expect(dashboard.status, TrainingStatus.gettingStarted);
      expect(dashboard.trendWarnings, isEmpty);

      final review = _review(DemoScenario.insufficientData);
      expect(
        review.attention.any(
          (f) => f.kind == ReviewFindingKind.insufficientHistory,
        ),
        isTrue,
      );
      expect(
        review.actions.any(
          (a) => a.kind == SuggestedActionKind.logMoreSessions,
        ),
        isTrue,
      );
      expect(
        review.attention.any(
          (f) =>
              f.kind == ReviewFindingKind.possiblePlateau ||
              f.kind == ReviewFindingKind.possibleRegression,
        ),
        isFalse,
      );
    });
  });
}
