import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/utils/units.dart';

void main() {
  group('conversion', () {
    test('kg to lbs uses the compatibility factor', () {
      expect(kgToLbs(100), closeTo(220.462, 1e-9));
      expect(kgToLbs(1), closeTo(2.20462, 1e-9));
    });

    test('lbs to kg is the inverse', () {
      expect(lbsToKg(220.462), closeTo(100, 1e-9));
    });

    test('round trip is stable within tolerance', () {
      for (final v in [0.0, 2.5, 60.0, 62.5, 100.0, 142.7, 305.0]) {
        expect(lbsToKg(kgToLbs(v)), closeTo(v, 1e-9));
        expect(kgToLbs(lbsToKg(v)), closeTo(v, 1e-9));
      }
    });

    test('zero converts to zero', () {
      expect(kgToLbs(0), 0);
      expect(lbsToKg(0), 0);
    });

    test('fractional values convert linearly', () {
      expect(kgToLbs(2.5), closeTo(5.511549999999999, 1e-9));
    });

    test('negative input converts mathematically (gated by callers)', () {
      expect(kgToLbs(-10), closeTo(-22.0462, 1e-9));
    });

    test('display-unit helpers respect the unit string', () {
      expect(kgToDisplayUnit(100, 'kg'), 100);
      expect(kgToDisplayUnit(100, 'lbs'), closeTo(220.462, 1e-9));
      expect(displayUnitToKg(220.462, 'lbs'), closeTo(100, 1e-9));
      expect(displayUnitToKg(100, 'kg'), 100);
    });

    test('display round trip (enter in lbs, store kg, redisplay lbs)', () {
      const entered = 135.0; // lbs
      final storedKg = displayUnitToKg(entered, 'lbs');
      expect(kgToDisplayUnit(storedKg, 'lbs'), closeTo(entered, 1e-9));
    });
  });

  group('labels', () {
    test('lbs and kg labels', () {
      expect(weightUnitLabel('lbs'), 'lbs');
      expect(weightUnitLabel('kg'), 'kg');
      // Anything unrecognised falls back to kg (the stored unit).
      expect(weightUnitLabel(''), 'kg');
    });
  });

  group('formatWeight', () {
    test('trims a trailing .0', () {
      expect(formatWeight(60.0), '60');
      expect(formatWeight(0), '0');
    });

    test('keeps one decimal for fractional values', () {
      expect(formatWeight(62.5), '62.5');
      expect(formatWeight(220.462), '220.5'); // rounded to 1 dp
    });

    test('negative values format with sign', () {
      expect(formatWeight(-60.0), '-60');
      expect(formatWeight(-62.5), '-62.5');
    });

    test('non-finite values render as an em dash, never NaN/Infinity', () {
      expect(formatWeight(double.nan), '—');
      expect(formatWeight(double.infinity), '—');
      expect(formatWeight(double.negativeInfinity), '—');
    });
  });

  group('formatCompactWeight', () {
    test('below 1000 has no decimals', () {
      expect(formatCompactWeight(0), '0');
      expect(formatCompactWeight(850.4), '850');
    });

    test('thousands tier uses k with one decimal', () {
      expect(formatCompactWeight(1000), '1.0k');
      expect(formatCompactWeight(1234), '1.2k');
      expect(formatCompactWeight(999999), '1000.0k');
    });

    test('millions tier uses M with two decimals', () {
      expect(formatCompactWeight(1000000), '1.00M');
      expect(formatCompactWeight(1234567), '1.23M');
    });

    test('non-finite values render as an em dash', () {
      expect(formatCompactWeight(double.nan), '—');
      expect(formatCompactWeight(double.infinity), '—');
    });
  });
}
