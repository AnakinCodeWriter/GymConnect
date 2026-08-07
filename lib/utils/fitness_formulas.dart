import '../models/workout_model.dart';
import 'strength_math.dart';

// The canonical e1RM formula lives in strength_math.dart (pure, importable
// by plain-Dart tooling) and is re-exported here so every existing call
// site keeps working unchanged. There is still exactly one implementation
// (Phase 3, D3); Phase 12 only moved it behind an import that the
// migration CLI can also use.
export 'strength_math.dart' show estimatedOneRepMax;

/// The single eligibility rule for whether a set may contribute to
/// strength-performance analytics (e1RM trends, personal records,
/// leaderboard bests, recommendation strength comparisons, feel-analysis
/// best lifts) and to training-volume analytics.
///
/// Eligible = a working (non-warm-up) set with a finite weight >= 0 and
/// reps >= 1. Zero weight is valid (bodyweight-style logging). Warm-up and
/// malformed sets remain visible in workout-history display and logging
/// prefill - exclusion applies to calculations only.
///
/// Delegates to [isEligibleSetValues] so the migration CLI (which cannot
/// import WorkoutSet) admits exactly the same sets.
bool isEligibleForStrengthAnalytics(WorkoutSet set) => isEligibleSetValues(
  weight: set.weight,
  reps: set.reps,
  isWarmup: set.isWarmup,
);
