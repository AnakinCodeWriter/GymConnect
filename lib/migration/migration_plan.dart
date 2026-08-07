// Pure planning for the opt-in stored-value migration (Phase 12, executes
// D3). NO Flutter/Firebase imports - `dart run tool/migrate_data.dart`
// cannot load Flutter plugins, and keeping the rules pure makes every
// decision unit-testable without touching a project.
//
// What this corrects, and why it exists:
//   * `users/{uid}.personalRecords` and `gyms/{gymId}/leaderboard/{uid}
//     .bestLifts` written BEFORE Phase 3 used an uncapped Epley formula,
//     and the leaderboard also counted warm-up sets. Those stored values
//     can be higher than the canonical formula produces, and new writes
//     only overwrite a stored value when the corrected number BEATS it -
//     so an inflated record stands until migrated (D3).
//   * Leaderboard entries written BEFORE Phase 10 may hold a real display
//     name while `isAnonymous == true` (the anonymity leak fixed at the
//     write path in Phase 10; historical entries were deliberately not
//     rewritten then).
//
// Safety rules encoded here, not left to the CLI:
//   * Nothing is ever deleted. Only field values are corrected.
//   * A stored record whose exercise has NO eligible history is reported
//     as an orphan and never written - "if uncertainty exists about a
//     stored value, leave it alone".
//   * Corrections are computed against a tolerance so floating-point noise
//     never produces a write, which is what makes the tool idempotent:
//     applying a plan and re-planning yields no changes.

import '../utils/strength_math.dart';

/// Kilogram difference below which a stored value counts as already
/// correct. Well under any real logged increment (2.5 kg / 5 lbs) and far
/// above double-rounding noise.
const double migrationToleranceKg = 1e-6;

// ---------------------------------------------------------------------
// Minimal stored-workout shapes
// ---------------------------------------------------------------------
// The app's WorkoutModel carries a Firestore Timestamp, so it cannot be
// imported here. These plain types mirror only what recomputation needs;
// `test/migration_plan_test.dart` proves they produce identical results to
// the app's own LeaderboardService calculator for the same sets.

class StoredSet {
  final double weight;
  final int reps;
  final bool isWarmup;

  const StoredSet({
    required this.weight,
    required this.reps,
    this.isWarmup = false,
  });
}

class StoredExercise {
  final String name;
  final List<StoredSet> sets;

  const StoredExercise({required this.name, required this.sets});
}

class StoredWorkout {
  final List<StoredExercise> exercises;

  const StoredWorkout({required this.exercises});
}

/// Best eligible capped-Epley e1RM per exercise across the whole history,
/// in kg. Exercise names are used exactly as stored (the app matches names
/// verbatim); an exercise with no eligible sets produces no entry.
Map<String, double> bestE1RmPerExerciseAcross(Iterable<StoredWorkout> history) {
  final bests = <String, double>{};
  for (final workout in history) {
    for (final exercise in workout.exercises) {
      for (final set in exercise.sets) {
        if (!isEligibleSetValues(
          weight: set.weight,
          reps: set.reps,
          isWarmup: set.isWarmup,
        )) {
          continue;
        }
        final e1rm = estimatedOneRepMax(set.weight, set.reps);
        final current = bests[exercise.name];
        if (current == null || e1rm > current) bests[exercise.name] = e1rm;
      }
    }
  }
  return bests;
}

// ---------------------------------------------------------------------
// Plan pieces
// ---------------------------------------------------------------------

/// One stored value that disagrees with the recomputed one.
class ValueCorrection {
  final String exercise;
  final double storedKg;
  final double correctedKg;

  const ValueCorrection({
    required this.exercise,
    required this.storedKg,
    required this.correctedKg,
  });

  /// True when the stored value was inflated (the expected D3 case).
  bool get isLowered => correctedKg < storedKg;
}

/// A stored record for an exercise with no eligible history behind it -
/// reported so it is never silently kept OR silently removed.
class OrphanValue {
  final String exercise;
  final double storedKg;

  const OrphanValue({required this.exercise, required this.storedKg});
}

/// Shared shape of both correction plans.
abstract class ValuePlan {
  List<ValueCorrection> get corrections;
  List<OrphanValue> get orphans;

  /// Stored values that already match the recomputed value.
  int get unchanged;

  int get loweredCount => corrections.where((c) => c.isLowered).length;
  int get raisedCount => corrections.length - loweredCount;
}

/// Correction plan for `users/{uid}.personalRecords`.
class PersonalRecordsPlan extends ValuePlan {
  @override
  final List<ValueCorrection> corrections;
  @override
  final List<OrphanValue> orphans;
  @override
  final int unchanged;

  /// The stored map as it was read, used to build a full replacement map.
  final Map<String, double> stored;

  PersonalRecordsPlan({
    required this.corrections,
    required this.orphans,
    required this.unchanged,
    required this.stored,
  });

  bool get hasChanges => corrections.isNotEmpty;

  /// The COMPLETE personalRecords map to write: stored values with the
  /// corrections applied. Orphans are carried through untouched, and the
  /// whole map is written as one field so exercise names never become
  /// Firestore field paths (the dot-notation hazard fixed in Phase 1).
  Map<String, double> get mergedRecords => {
    ...stored,
    for (final c in corrections) c.exercise: c.correctedKg,
  };
}

/// Correction plan for `gyms/{gymId}/leaderboard/{uid}`.
class LeaderboardPlan extends ValuePlan {
  @override
  final List<ValueCorrection> corrections;
  @override
  final List<OrphanValue> orphans;
  @override
  final int unchanged;
  final Map<String, double> storedLifts;

  /// True when the entry is anonymous but still stores a readable real
  /// name (pre-Phase-10 leak).
  final bool anonymityNameLeak;

  final bool isAnonymous;
  final String storedDisplayName;
  final String safeDisplayName;

  LeaderboardPlan({
    required this.corrections,
    required this.orphans,
    required this.unchanged,
    required this.storedLifts,
    required this.anonymityNameLeak,
    required this.isAnonymous,
    required this.storedDisplayName,
    required this.safeDisplayName,
  });

  bool get hasChanges => corrections.isNotEmpty || anonymityNameLeak;

  Map<String, double> get mergedLifts => {
    ...storedLifts,
    for (final c in corrections) c.exercise: c.correctedKg,
  };

  /// The fields to PATCH. `displayName` is included whenever the entry
  /// leaks a name - and it MUST be, because the Phase 10 rules reject any
  /// write leaving `isAnonymous == true` with a readable real name, so a
  /// lift-only correction on a leaking entry would be denied.
  Map<String, Object> get writeFields => {
    if (corrections.isNotEmpty) 'bestLifts': mergedLifts,
    if (anonymityNameLeak) 'displayName': safeDisplayName,
  };
}

// ---------------------------------------------------------------------
// Planning
// ---------------------------------------------------------------------

(List<ValueCorrection>, List<OrphanValue>, int) _diff(
  Map<String, double> stored,
  Map<String, double> recomputed,
) {
  final corrections = <ValueCorrection>[];
  final orphans = <OrphanValue>[];
  var unchanged = 0;

  // Sorted so plans, output and tests are deterministic.
  final names = stored.keys.toList()..sort();
  for (final exercise in names) {
    final storedValue = stored[exercise]!;
    final correct = recomputed[exercise];
    if (correct == null) {
      orphans.add(OrphanValue(exercise: exercise, storedKg: storedValue));
      continue;
    }
    if ((correct - storedValue).abs() <= migrationToleranceKg) {
      unchanged++;
      continue;
    }
    corrections.add(
      ValueCorrection(
        exercise: exercise,
        storedKg: storedValue,
        correctedKg: correct,
      ),
    );
  }
  return (corrections, orphans, unchanged);
}

/// Plans personal-record corrections. Only exercises ALREADY stored are
/// considered: the migration corrects existing values, it does not invent
/// records the app never wrote (that is normal app behaviour's job).
PersonalRecordsPlan planPersonalRecords({
  required Map<String, double> stored,
  required Map<String, double> recomputed,
}) {
  final (corrections, orphans, unchanged) = _diff(stored, recomputed);
  return PersonalRecordsPlan(
    corrections: corrections,
    orphans: orphans,
    unchanged: unchanged,
    stored: stored,
  );
}

/// Plans leaderboard corrections, including the pre-Phase-10 anonymity
/// name leak. [safeDisplayName] must be the app's
/// `LeaderboardService.anonymousDisplayName`.
LeaderboardPlan planLeaderboard({
  required Map<String, double> storedLifts,
  required Map<String, double> recomputed,
  required bool isAnonymous,
  required String storedDisplayName,
  required String safeDisplayName,
}) {
  final (corrections, orphans, unchanged) = _diff(storedLifts, recomputed);
  return LeaderboardPlan(
    corrections: corrections,
    orphans: orphans,
    unchanged: unchanged,
    storedLifts: storedLifts,
    anonymityNameLeak: isAnonymous && storedDisplayName != safeDisplayName,
    isAnonymous: isAnonymous,
    storedDisplayName: storedDisplayName,
    safeDisplayName: safeDisplayName,
  );
}
