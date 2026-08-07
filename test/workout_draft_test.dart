// Unit tests for the log-workout draft model extracted in Phase 11
// (models/workout_draft.dart): validation wording, unit conversion on
// build, the one-warm-up rule and set copying.

import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/models/template_model.dart';
import 'package:gymconnect/models/workout_draft.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/utils/units.dart';

DraftExercise exercise(String name, List<(String, String)> sets) {
  final ex = DraftExercise(name: name);
  for (final (w, r) in sets) {
    ex.sets.add(DraftSet(weight: w, reps: r));
  }
  return ex;
}

void main() {
  group('validateWorkoutDraft', () {
    test('empty draft asks for an exercise', () {
      expect(validateWorkoutDraft([]), 'Add at least one exercise.');
    });

    test('unnamed exercise is rejected', () {
      expect(
        validateWorkoutDraft([
          exercise('  ', [('60', '5')]),
        ]),
        'Every exercise needs a name.',
      );
    });

    test('exercise without sets is rejected', () {
      expect(
        validateWorkoutDraft([DraftExercise(name: 'Bench Press')]),
        'Every exercise needs at least one set.',
      );
    });

    test('non-numeric, negative weight or zero reps are rejected', () {
      for (final (w, r) in [
        ('abc', '5'),
        ('-5', '5'),
        ('60', '0'),
        ('60', ''),
      ]) {
        expect(
          validateWorkoutDraft([
            exercise('Bench Press', [(w, r)]),
          ]),
          'Enter valid weight and reps for all sets.',
          reason: 'weight=$w reps=$r',
        );
      }
    });

    test('a valid draft passes (zero weight allowed, e.g. bodyweight)', () {
      expect(
        validateWorkoutDraft([
          exercise('Bench Press', [('60', '5'), ('0', '12')]),
        ]),
        isNull,
      );
    });
  });

  group('buildExercisesFromDraft', () {
    test('kg input is stored unchanged and names are trimmed', () {
      final entries = buildExercisesFromDraft([
        exercise(' Bench Press ', [('62.5', '5')]),
      ], unit: 'kg');
      expect(entries.single.name, 'Bench Press');
      expect(entries.single.sets.single.weight, 62.5);
      expect(entries.single.sets.single.reps, 5);
    });

    test('lbs input converts to kg exactly once', () {
      final entries = buildExercisesFromDraft([
        exercise('Bench Press', [('100', '5')]),
      ], unit: 'lbs');
      expect(entries.single.sets.single.weight, closeTo(lbsToKg(100), 1e-9));
    });

    test('warm-up flags survive the conversion', () {
      final ex = exercise('Bench Press', [('40', '8'), ('60', '5')]);
      ex.sets.first.isWarmup = true;
      final entries = buildExercisesFromDraft([ex], unit: 'kg');
      expect(entries.single.sets.map((s) => s.isWarmup), [true, false]);
    });
  });

  group('workingVolumeKg', () {
    test('sums weight x reps excluding warm-ups', () {
      final entries = [
        ExerciseEntry(
          name: 'Bench Press',
          sets: [
            WorkoutSet(weight: 40, reps: 8, isWarmup: true),
            WorkoutSet(weight: 60, reps: 5),
            WorkoutSet(weight: 60, reps: 5),
          ],
        ),
      ];
      expect(workingVolumeKg(entries), 600);
    });
  });

  group('DraftExercise', () {
    test('addSet copies the previous set text and starts empty otherwise', () {
      final ex = DraftExercise(name: 'Squat');
      ex.addSet();
      expect(ex.sets.single.weightController.text, '');

      ex.sets.single.weightController.text = '100';
      ex.sets.single.repsController.text = '5';
      ex.addSet();
      expect(ex.sets.last.weightController.text, '100');
      expect(ex.sets.last.repsController.text, '5');
      ex.dispose();
    });

    test('toggleWarmup enforces at most one warm-up per exercise', () {
      final ex = exercise('Squat', [('60', '5'), ('80', '5'), ('100', '3')]);
      ex.toggleWarmup(ex.sets[0]);
      expect(ex.sets.map((s) => s.isWarmup), [true, false, false]);

      // marking another set moves the flag rather than adding a second one
      ex.toggleWarmup(ex.sets[2]);
      expect(ex.sets.map((s) => s.isWarmup), [false, false, true]);

      // tapping the current warm-up clears it
      ex.toggleWarmup(ex.sets[2]);
      expect(ex.sets.map((s) => s.isWarmup), [false, false, false]);
      ex.dispose();
    });
  });

  group('DraftSet factories', () {
    test('fromWorkoutSet converts kg to the display unit and keeps the '
        'warm-up flag', () {
      final set = WorkoutSet(weight: 100, reps: 5, isWarmup: true);
      final kg = DraftSet.fromWorkoutSet(set, unit: 'kg');
      expect(kg.weightController.text, '100');
      expect(kg.isWarmup, isTrue);

      final lbs = DraftSet.fromWorkoutSet(set, unit: 'lbs');
      expect(lbs.weightController.text, formatWeight(kgToLbs(100)));
      kg.dispose();
      lbs.dispose();
    });

    test('fromTemplateSet leaves the weight blank when the template has '
        'none', () {
      final blank = DraftSet.fromTemplateSet(
        TemplateSet(weight: null, reps: 8),
        unit: 'kg',
      );
      expect(blank.weightController.text, '');
      expect(blank.repsController.text, '8');
      expect(blank.isWarmup, isFalse);
      blank.dispose();
    });
  });
}
