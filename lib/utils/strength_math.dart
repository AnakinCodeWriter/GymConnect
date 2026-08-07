// Pure strength maths with NO imports (Phase 12).
//
// Split out of fitness_formulas.dart so plain-Dart tooling (the migration
// CLI, which cannot import Flutter plugins) uses the SAME canonical formula
// and eligibility rule as the app. fitness_formulas.dart re-exports
// [estimatedOneRepMax] and adapts the eligibility rule to WorkoutSet, so
// there is still exactly one implementation of each (Phase 3, D3).

/// Canonical estimated one-rep max: the ONLY e1RM implementation in the
/// repository. Definition: docs/ANALYTICS_DEFINITIONS.md.
///
/// Epley formula with reps clamped to [1, 10]; the cap prevents high-rep
/// sets producing inflated maxima. Returns an UNROUNDED value in the same
/// unit as [weight] (kg everywhere in this app); rounding happens only at
/// display boundaries, and comparisons (e.g. personal records) use the
/// unrounded value.
///
/// Zero weight yields 0. The formula itself does not gate inputs - negative
/// or non-finite weights propagate mathematically. Callers must admit sets
/// via the eligibility rule, which rejects them.
double estimatedOneRepMax(double weight, int reps) {
  final r = reps.clamp(1, 10);
  return weight * (1 + r / 30);
}

/// The single eligibility rule, expressed over raw values so both the app
/// (via `isEligibleForStrengthAnalytics`) and the migration CLI apply
/// identical admission criteria.
///
/// Eligible = a working (non-warm-up) set with a finite weight >= 0 and
/// reps >= 1. Zero weight is valid (bodyweight-style logging).
bool isEligibleSetValues({
  required double weight,
  required int reps,
  required bool isWarmup,
}) => !isWarmup && weight.isFinite && weight >= 0 && reps >= 1;
