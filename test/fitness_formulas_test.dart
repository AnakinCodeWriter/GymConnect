import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/utils/fitness_formulas.dart';

void main() {
  group('estimatedOneRepMax', () {
    test('basic Epley calculation is correct', () {
      // 100 * (1 + 5/30) = 116.67
      expect(estimatedOneRepMax(100, 5), closeTo(116.67, 0.01));
    });

    test('single rep returns weight plus one-thirtieth', () {
      // 100 * (1 + 1/30) = 103.33
      expect(estimatedOneRepMax(100, 1), closeTo(103.33, 0.01));
    });

    test('rep cap: 11 reps produces the same result as 10 reps', () {
      expect(estimatedOneRepMax(100, 11), equals(estimatedOneRepMax(100, 10)));
    });

    test('rep cap: 20 reps produces the same result as 10 reps', () {
      expect(estimatedOneRepMax(100, 20), equals(estimatedOneRepMax(100, 10)));
    });

    test('rep cap is applied at exactly 10 reps', () {
      // 100 * (1 + 10/30) = 133.33
      expect(estimatedOneRepMax(100, 10), closeTo(133.33, 0.01));
    });

    test(
      '9 reps and 10 reps produce different results - cap does not apply early',
      () {
        expect(
          estimatedOneRepMax(100, 9),
          isNot(equals(estimatedOneRepMax(100, 10))),
        );
      },
    );

    test('result scales linearly with weight', () {
      expect(
        estimatedOneRepMax(200, 5),
        closeTo(estimatedOneRepMax(100, 5) * 2, 0.01),
      );
    });

    // Characterisation: edge-case behaviour relied upon by callers.
    test('zero weight returns zero', () {
      expect(estimatedOneRepMax(0, 5), 0);
    });

    test('reps below 1 are clamped up to 1', () {
      expect(estimatedOneRepMax(100, 0), equals(estimatedOneRepMax(100, 1)));
      expect(estimatedOneRepMax(100, -3), equals(estimatedOneRepMax(100, 1)));
    });

    test('fractional weights are supported and unrounded', () {
      // 62.5 * (1 + 5/30) = 72.9166...
      expect(estimatedOneRepMax(62.5, 5), closeTo(62.5 * (1 + 5 / 30), 1e-12));
    });

    test(
      'negative weight propagates mathematically (gated by eligibility)',
      () {
        expect(estimatedOneRepMax(-100, 5), closeTo(-100 * (1 + 5 / 30), 1e-9));
      },
    );

    test('non-finite weight propagates (gated by eligibility)', () {
      expect(estimatedOneRepMax(double.nan, 5).isNaN, isTrue);
      expect(estimatedOneRepMax(double.infinity, 5).isInfinite, isTrue);
    });
  });

  group('isEligibleForStrengthAnalytics', () {
    WorkoutSet set(double weight, int reps, {bool warmup = false}) =>
        WorkoutSet(weight: weight, reps: reps, isWarmup: warmup);

    test('a valid working set is eligible', () {
      expect(isEligibleForStrengthAnalytics(set(60, 5)), isTrue);
    });

    test('zero weight is a valid value (bodyweight-style logging)', () {
      expect(isEligibleForStrengthAnalytics(set(0, 12)), isTrue);
    });

    test('warm-up sets are not eligible', () {
      expect(isEligibleForStrengthAnalytics(set(60, 5, warmup: true)), isFalse);
    });

    test('negative weight is not eligible', () {
      expect(isEligibleForStrengthAnalytics(set(-60, 5)), isFalse);
    });

    test('reps below 1 are not eligible', () {
      expect(isEligibleForStrengthAnalytics(set(60, 0)), isFalse);
      expect(isEligibleForStrengthAnalytics(set(60, -2)), isFalse);
    });

    test('non-finite weight is not eligible', () {
      expect(isEligibleForStrengthAnalytics(set(double.nan, 5)), isFalse);
      expect(isEligibleForStrengthAnalytics(set(double.infinity, 5)), isFalse);
    });
  });
}
