import '../models/workout_model.dart';

/// Typed result of the progressive-overload hint shown above an exercise
/// card while logging (extracted from the log workout screen in Phase 11 so
/// the rule is unit-testable). All weights are stored kg; the UI converts
/// for display.
class OverloadHint {
  /// Highest working weight from the last session of this exercise.
  final double topWeightKg;

  /// Reps of the first and last working set from that session.
  final int firstReps;
  final int lastReps;

  /// True when the last session held up (single set, or last-set reps at
  /// least 75% of first-set reps, floored) - suggest adding load.
  final bool strong;

  const OverloadHint({
    required this.topWeightKg,
    required this.firstReps,
    required this.lastReps,
    required this.strong,
  });

  /// The suggested next working weight when [strong]: top weight + 2.5 kg.
  double get suggestedWeightKg => topWeightKg + 2.5;
}

/// Computes the hint from the working sets of the user's most recent session
/// of an exercise, or null when there is no history to base one on.
/// Rule (unchanged since the dissertation build): a multi-set session is
/// "strong" when the final set kept at least 75% (floored) of the first
/// set's reps; a single-set session always counts as strong.
OverloadHint? computeOverloadHint(List<WorkoutSet>? lastSessionSets) {
  if (lastSessionSets == null || lastSessionSets.isEmpty) return null;

  final topWeight = lastSessionSets
      .map((s) => s.weight)
      .reduce((a, b) => a > b ? a : b);
  final firstReps = lastSessionSets.first.reps;
  final lastReps = lastSessionSets.last.reps;
  final strong = lastSessionSets.length == 1
      ? true
      : lastReps >= (firstReps * 0.75).floor();

  return OverloadHint(
    topWeightKg: topWeight,
    firstReps: firstReps,
    lastReps: lastReps,
    strong: strong,
  );
}
