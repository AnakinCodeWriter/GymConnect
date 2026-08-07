import 'package:flutter/widgets.dart';

import '../models/template_model.dart';
import '../models/workout_model.dart';
import '../utils/units.dart';

// In-progress workout form state for the log workout screen, extracted in
// Phase 11 so validation, unit conversion and the warm-up rule are unit
// testable. Weights are stored in kg; the draft holds display-unit text and
// converts exactly once on [buildExercises].

/// One editable set: weight/reps text plus the warm-up flag. Text is in the
/// user's display unit.
class DraftSet {
  final TextEditingController weightController;
  final TextEditingController repsController;
  bool isWarmup;

  DraftSet({String weight = '', String reps = '', this.isWarmup = false})
    : weightController = TextEditingController(text: weight),
      repsController = TextEditingController(text: reps);

  /// Pre-fills from a previously logged set. Converts kg -> [unit];
  /// preserves the warm-up flag.
  factory DraftSet.fromWorkoutSet(WorkoutSet set, {required String unit}) {
    return DraftSet(
      weight: formatWeight(kgToDisplayUnit(set.weight, unit)),
      reps: set.reps.toString(),
      isWarmup: set.isWarmup,
    );
  }

  /// Pre-fills from a template set (templates have no warm-up flag and may
  /// omit the weight).
  factory DraftSet.fromTemplateSet(TemplateSet set, {required String unit}) {
    final w = set.weight;
    return DraftSet(
      weight: w == null ? '' : formatWeight(kgToDisplayUnit(w, unit)),
      reps: set.reps.toString(),
    );
  }

  void dispose() {
    weightController.dispose();
    repsController.dispose();
  }
}

/// One exercise being logged: a free-text name kept in sync by the UI and
/// its list of draft sets.
class DraftExercise {
  String name;
  final List<DraftSet> sets = [];

  DraftExercise({this.name = ''});

  /// Appends a set, copying the previous set's current text so consecutive
  /// sets start from the same weight/reps (pre-existing behaviour).
  void addSet() {
    if (sets.isNotEmpty) {
      final prev = sets.last;
      sets.add(
        DraftSet(
          weight: prev.weightController.text,
          reps: prev.repsController.text,
        ),
      );
    } else {
      sets.add(DraftSet());
    }
  }

  /// Toggles the warm-up flag on [set]. At most one warm-up per exercise:
  /// marking a set clears any other warm-up first.
  void toggleWarmup(DraftSet set) {
    if (!set.isWarmup) {
      for (final other in sets) {
        other.isWarmup = false;
      }
      set.isWarmup = true;
    } else {
      set.isWarmup = false;
    }
  }

  void dispose() {
    for (final s in sets) {
      s.dispose();
    }
  }
}

/// Validates a draft before saving. Returns the user-facing error message
/// (unchanged wording from the original screen) or null when valid.
String? validateWorkoutDraft(List<DraftExercise> exercises) {
  if (exercises.isEmpty) return 'Add at least one exercise.';
  for (final ex in exercises) {
    if (ex.name.trim().isEmpty) return 'Every exercise needs a name.';
    if (ex.sets.isEmpty) return 'Every exercise needs at least one set.';
    for (final s in ex.sets) {
      final weight = double.tryParse(s.weightController.text.trim());
      final reps = int.tryParse(s.repsController.text.trim());
      if (weight == null || reps == null || weight < 0 || reps <= 0) {
        return 'Enter valid weight and reps for all sets.';
      }
    }
  }
  return null;
}

/// Converts a validated draft to storable exercise entries. Weights are
/// parsed as display-unit values and converted to kg exactly once.
/// Call only after [validateWorkoutDraft] returned null.
List<ExerciseEntry> buildExercisesFromDraft(
  List<DraftExercise> exercises, {
  required String unit,
}) {
  return exercises.map((ex) {
    final sets = ex.sets.map((s) {
      final rawWeight = double.parse(s.weightController.text.trim());
      return WorkoutSet(
        weight: displayUnitToKg(rawWeight, unit),
        reps: int.parse(s.repsController.text.trim()),
        isWarmup: s.isWarmup,
      );
    }).toList();
    return ExerciseEntry(name: ex.name.trim(), sets: sets);
  }).toList();
}

/// Total working volume (weight x reps, warm-ups excluded) in kg - the value
/// shown in the post-save summary dialog.
double workingVolumeKg(List<ExerciseEntry> exercises) {
  double total = 0;
  for (final ex in exercises) {
    for (final s in ex.sets) {
      if (!s.isWarmup) total += s.weight * s.reps;
    }
  }
  return total;
}
