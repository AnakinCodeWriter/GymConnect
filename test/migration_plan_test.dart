// Unit tests for the opt-in stored-value migration planner (Phase 12).
//
// The planner is pure and CLI-safe, so these tests also pin the two
// properties the tool's safety rests on: it agrees exactly with the app's
// own e1RM calculator, and applying a plan makes the next plan empty
// (idempotency).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/migration/migration_plan.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/services/leaderboard_service.dart';
import 'package:gymconnect/utils/fitness_formulas.dart';

StoredWorkout stored(List<StoredExercise> exercises) =>
    StoredWorkout(exercises: exercises);

StoredExercise ex(String name, List<StoredSet> sets) =>
    StoredExercise(name: name, sets: sets);

void main() {
  group('bestE1RmPerExerciseAcross', () {
    test('takes the best eligible set across the whole history', () {
      final history = [
        stored([
          ex('Bench Press', [
            const StoredSet(weight: 60, reps: 5),
            const StoredSet(weight: 80, reps: 3),
          ]),
        ]),
        stored([
          ex('Bench Press', [const StoredSet(weight: 70, reps: 5)]),
        ]),
      ];
      // best of: 60*(1+5/30)=70, 80*(1+3/30)=88, 70*(1+5/30)=81.67
      expect(
        bestE1RmPerExerciseAcross(history)['Bench Press'],
        closeTo(88, 1e-9),
      );
    });

    test('excludes warm-up sets - the pre-Phase-3 leaderboard bug', () {
      final history = [
        stored([
          ex('Squat', [
            const StoredSet(weight: 200, reps: 5, isWarmup: true),
            const StoredSet(weight: 100, reps: 5),
          ]),
        ]),
      ];
      expect(
        bestE1RmPerExerciseAcross(history)['Squat'],
        closeTo(116.667, 1e-3),
      );
    });

    test('caps reps at 10 so high-rep sets cannot inflate the record', () {
      final capped = bestE1RmPerExerciseAcross([
        stored([
          ex('Deadlift', [const StoredSet(weight: 100, reps: 20)]),
        ]),
      ]);
      // uncapped Epley would give 100*(1+20/30) = 166.7
      expect(capped['Deadlift'], closeTo(100 * (1 + 10 / 30), 1e-9));
    });

    test('malformed and warm-up-only exercises produce no entry', () {
      final result = bestE1RmPerExerciseAcross([
        stored([
          ex('Face Pull', [const StoredSet(weight: 20, reps: 0)]),
          ex('Curl', [const StoredSet(weight: 20, reps: 10, isWarmup: true)]),
          ex('Row', const []),
        ]),
      ]);
      expect(result, isEmpty);
    });

    test('empty history yields no values', () {
      expect(bestE1RmPerExerciseAcross(const []), isEmpty);
    });
  });

  group('agreement with the app', () {
    test('recomputation matches LeaderboardService for the same sets', () {
      // The migration exists to make stored values equal what the APP would
      // now compute; if these two ever diverge the tool would corrupt data.
      final sets = [
        WorkoutSet(weight: 40, reps: 12, isWarmup: true),
        WorkoutSet(weight: 100, reps: 5),
        WorkoutSet(weight: 90, reps: 15),
        WorkoutSet(weight: 0, reps: 20),
      ];
      final workout = WorkoutModel(
        id: 'w1',
        date: Timestamp.fromDate(DateTime(2026, 7, 1)),
        exercises: [ExerciseEntry(name: 'Bench Press', sets: sets)],
      );

      final fromApp = LeaderboardService.bestEligibleE1RmPerExercise(workout);
      final fromMigration = bestE1RmPerExerciseAcross([
        stored([
          ex('Bench Press', [
            for (final s in sets)
              StoredSet(weight: s.weight, reps: s.reps, isWarmup: s.isWarmup),
          ]),
        ]),
      ]);

      expect(fromMigration, fromApp);
    });

    test('the formula re-export keeps one implementation', () {
      // fitness_formulas re-exports strength_math's function; both call
      // sites must be the same function.
      expect(estimatedOneRepMax(100, 5), closeTo(116.667, 1e-3));
    });

    test('the CLI\'s anonymous display constant matches the app', () {
      // tool/migrate_data.dart cannot import LeaderboardService (Firebase),
      // so it holds a literal copy; this pins them together.
      expect(LeaderboardService.anonymousDisplayName, 'Anonymous');
    });
  });

  group('planPersonalRecords', () {
    test('an inflated stored record is planned as a lowering correction', () {
      final plan = planPersonalRecords(
        stored: {'Bench Press': 166.7},
        recomputed: {'Bench Press': 133.3},
      );
      expect(plan.hasChanges, isTrue);
      expect(plan.corrections.single.exercise, 'Bench Press');
      expect(plan.corrections.single.isLowered, isTrue);
      expect(plan.loweredCount, 1);
      expect(plan.raisedCount, 0);
    });

    test('a stored value below the true best is raised', () {
      final plan = planPersonalRecords(
        stored: {'Squat': 100},
        recomputed: {'Squat': 120},
      );
      expect(plan.corrections.single.isLowered, isFalse);
      expect(plan.raisedCount, 1);
    });

    test('matching values are counted unchanged, not rewritten', () {
      final plan = planPersonalRecords(
        stored: {'Squat': 120},
        recomputed: {'Squat': 120},
      );
      expect(plan.hasChanges, isFalse);
      expect(plan.unchanged, 1);
    });

    test('differences within tolerance are treated as already correct', () {
      final plan = planPersonalRecords(
        stored: {'Squat': 120},
        recomputed: {'Squat': 120 + migrationToleranceKg / 2},
      );
      expect(plan.hasChanges, isFalse);
      expect(plan.unchanged, 1);
    });

    test('records with no eligible history are orphans, never written', () {
      final plan = planPersonalRecords(
        stored: {'Bench Press': 120, 'Deleted Exercise': 90},
        recomputed: {'Bench Press': 100},
      );
      expect(plan.orphans.single.exercise, 'Deleted Exercise');
      // the orphan survives untouched in the map that gets written
      expect(plan.mergedRecords['Deleted Exercise'], 90);
      expect(plan.mergedRecords['Bench Press'], 100);
    });

    test('exercises never stored are not invented', () {
      final plan = planPersonalRecords(
        stored: {'Bench Press': 100},
        recomputed: {'Bench Press': 100, 'Overhead Press': 60},
      );
      expect(plan.hasChanges, isFalse);
      expect(plan.mergedRecords.containsKey('Overhead Press'), isFalse);
    });

    test('applying a plan makes the next plan empty (idempotent)', () {
      const recomputed = {'Bench Press': 133.3, 'Squat': 180.0};
      final first = planPersonalRecords(
        stored: {'Bench Press': 166.7, 'Squat': 180.0},
        recomputed: recomputed,
      );
      expect(first.hasChanges, isTrue);

      final second = planPersonalRecords(
        stored: first.mergedRecords,
        recomputed: recomputed,
      );
      expect(second.hasChanges, isFalse);
      expect(second.corrections, isEmpty);
    });

    test('an empty stored map produces no work', () {
      final plan = planPersonalRecords(
        stored: const {},
        recomputed: {'Bench Press': 100},
      );
      expect(plan.hasChanges, isFalse);
      expect(plan.orphans, isEmpty);
    });

    test('corrections are ordered deterministically by exercise name', () {
      final plan = planPersonalRecords(
        stored: {'Squat': 200, 'Bench Press': 200, 'Deadlift': 200},
        recomputed: {'Squat': 100, 'Bench Press': 100, 'Deadlift': 100},
      );
      expect(plan.corrections.map((c) => c.exercise), [
        'Bench Press',
        'Deadlift',
        'Squat',
      ]);
    });
  });

  group('planLeaderboard', () {
    LeaderboardPlan build({
      Map<String, double> storedLifts = const {'Bench Press': 166.7},
      Map<String, double> recomputed = const {'Bench Press': 133.3},
      bool isAnonymous = false,
      String storedDisplayName = 'Alfie',
    }) => planLeaderboard(
      storedLifts: storedLifts,
      recomputed: recomputed,
      isAnonymous: isAnonymous,
      storedDisplayName: storedDisplayName,
      safeDisplayName: 'Anonymous',
    );

    test('stale lifts are corrected like personal records', () {
      final plan = build();
      expect(plan.hasChanges, isTrue);
      expect(plan.mergedLifts['Bench Press'], 133.3);
      expect(plan.writeFields.keys, ['bestLifts']);
    });

    test('a pre-Phase-10 anonymous entry leaking a real name is fixed', () {
      final plan = build(isAnonymous: true, storedDisplayName: 'Alfie');
      expect(plan.anonymityNameLeak, isTrue);
      expect(plan.writeFields['displayName'], 'Anonymous');
    });

    test('an anonymous entry already storing the safe value is left alone', () {
      final plan = build(
        storedLifts: const {'Bench Press': 133.3},
        isAnonymous: true,
        storedDisplayName: 'Anonymous',
      );
      expect(plan.anonymityNameLeak, isFalse);
      expect(plan.hasChanges, isFalse);
      expect(plan.writeFields, isEmpty);
    });

    test('a named non-anonymous entry is never renamed', () {
      final plan = build(
        storedLifts: const {'Bench Press': 133.3},
        storedDisplayName: 'Alfie',
      );
      expect(plan.anonymityNameLeak, isFalse);
      expect(plan.writeFields, isEmpty);
    });

    test('a leaking entry always writes the name alongside lift fixes, '
        'because the rules reject a lift-only write', () {
      final plan = build(isAnonymous: true, storedDisplayName: 'Alfie');
      // Phase 10 rule: isAnonymous == true requires displayName == 'Anonymous'
      // in the POST-write document, so both fields must go in one PATCH.
      expect(plan.writeFields.keys, containsAll(['bestLifts', 'displayName']));
    });

    test('applying a leaderboard plan is idempotent', () {
      const recomputed = {'Bench Press': 133.3};
      final first = build(isAnonymous: true, storedDisplayName: 'Alfie');
      final second = planLeaderboard(
        storedLifts: first.mergedLifts,
        recomputed: recomputed,
        isAnonymous: true,
        storedDisplayName: first.safeDisplayName,
        safeDisplayName: 'Anonymous',
      );
      expect(second.hasChanges, isFalse);
    });

    test('lifts with no history are reported but carried through', () {
      final plan = build(
        storedLifts: const {'Bench Press': 166.7, 'Retired Lift': 50},
        recomputed: const {'Bench Press': 133.3},
      );
      expect(plan.orphans.single.exercise, 'Retired Lift');
      expect(plan.mergedLifts['Retired Lift'], 50);
    });
  });
}
