// Single source of truth for weight-unit conversion and formatting
// (Phase 3). Invariants (docs/ANALYTICS_DEFINITIONS.md):
//
// 1. Stored value: ALWAYS kilograms, full double precision, in Firestore.
// 2. Calculation value: unrounded kg; analytics never convert to lbs.
// 3. Display value: converted once at the UI boundary and formatted per
//    screen; user input in lbs is converted back to kg once for storage.
//
// The unit preference is the existing 'kg' / 'lbs' string used across the
// app (weightUnitNotifier, UserModel.weightUnit).

/// Compatibility baseline conversion factor (pre-Phase 3 value).
const double lbsPerKg = 2.20462;

double kgToLbs(double kg) => kg * lbsPerKg;

double lbsToKg(double lbs) => lbs / lbsPerKg;

/// Converts a stored kg value into the user's display unit.
double kgToDisplayUnit(double kg, String unit) =>
    unit == 'lbs' ? kgToLbs(kg) : kg;

/// Converts a user-entered display-unit value back to kg for storage.
double displayUnitToKg(double value, String unit) =>
    unit == 'lbs' ? lbsToKg(value) : value;

/// The display label for a unit preference ('lbs' or 'kg').
String weightUnitLabel(String unit) => unit == 'lbs' ? 'lbs' : 'kg';

/// Formats a display-unit weight with at most one decimal place, trimming a
/// trailing ".0": 60.0 -> "60", 62.5 -> "62.5". Non-finite values render as
/// an em dash rather than "NaN"/"Infinity".
String formatWeight(double value) {
  if (!value.isFinite) return '—';
  return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
}

/// Compact formatting for large weight totals (volume, lifetime stats):
/// >= 1,000,000 -> "1.23M"; >= 1,000 -> "1.2k"; otherwise no decimals.
/// Non-finite values render as an em dash.
String formatCompactWeight(double value) {
  if (!value.isFinite) return '—';
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return value.toStringAsFixed(0);
}
