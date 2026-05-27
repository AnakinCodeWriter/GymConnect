import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/services/plateau_detector.dart';

// Builds a list of (date, e1RM) pairs spaced evenly apart.
// Index 0 = oldest session.
List<(DateTime, double)> makeSessions(
  List<double> e1rms, {
  int daysBetween = 3,
}) {
  final base = DateTime(2024, 1, 1);
  return List.generate(
    e1rms.length,
    (i) => (base.add(Duration(days: i * daysBetween)), e1rms[i]),
  );
}

void main() {
  group('PlateauDetector.analyse', () {
    group('Minimum session requirement', () {
      test('fewer than 5 sessions returns insufficientData', () {
        final result = PlateauDetector.analyse(makeSessions([100, 105, 110, 115]));
        expect(result.status, PlateauStatus.insufficientData);
        expect(result.slope, 0);
      });

      test('exactly 5 sessions does not return insufficientData', () {
        final result = PlateauDetector.analyse(makeSessions([100, 102, 104, 106, 108]));
        expect(result.status, isNot(PlateauStatus.insufficientData));
      });
    });

    group('Trend classification', () {
      test('strong upward trend returns progressing', () {
        // +2 kg every 3 days on ~100 kg base, ~0.67%/day, well above 0.1% threshold
        final result = PlateauDetector.analyse(
          makeSessions([100, 102, 104, 106, 108, 110]),
        );
        expect(result.status, PlateauStatus.progressing);
      });

      test('strong downward trend returns regressing', () {
        final result = PlateauDetector.analyse(
          makeSessions([110, 108, 106, 104, 102, 100]),
        );
        expect(result.status, PlateauStatus.regressing);
      });

      test('flat trend returns plateau', () {
        final result = PlateauDetector.analyse(
          makeSessions([100, 100, 100, 100, 100, 100]),
        );
        expect(result.status, PlateauStatus.plateau);
      });

      test('very small upward drift returns plateau, not progressing', () {
        // +0.05 kg every 3 days, ~0.017%/day, below the 0.1% threshold
        final result = PlateauDetector.analyse(
          makeSessions([100.00, 100.05, 100.10, 100.15, 100.20, 100.25]),
        );
        expect(result.status, PlateauStatus.plateau);
      });
    });

    group('Slope direction', () {
      test('progressing result has a positive slope', () {
        final result = PlateauDetector.analyse(
          makeSessions([100, 102, 104, 106, 108]),
        );
        expect(result.slope, greaterThan(0));
      });

      test('regressing result has a negative slope', () {
        final result = PlateauDetector.analyse(
          makeSessions([108, 106, 104, 102, 100]),
        );
        expect(result.slope, lessThan(0));
      });

      test('plateau result has a slope near zero', () {
        final result = PlateauDetector.analyse(
          makeSessions([100, 100, 100, 100, 100]),
        );
        expect(result.slope.abs(), lessThan(0.001));
      });
    });

    group('Edge cases', () {
      test('all sessions on the same day returns plateau without error', () {
        final day = DateTime(2024, 1, 1);
        final sessions = List.generate(5, (_) => (day, 100.0));
        final result = PlateauDetector.analyse(sessions);
        expect(result.status, PlateauStatus.plateau);
        expect(result.slope, 0);
      });

      test('unsorted input is sorted and classified correctly', () {
        final base = DateTime(2024, 1, 1);
        // Provide sessions deliberately out of chronological order
        final sessions = [
          (base.add(const Duration(days: 12)), 108.0),
          (base, 100.0),
          (base.add(const Duration(days: 6)), 104.0),
          (base.add(const Duration(days: 9)), 106.0),
          (base.add(const Duration(days: 3)), 102.0),
        ];
        final result = PlateauDetector.analyse(sessions);
        expect(result.status, PlateauStatus.progressing);
      });

      test('large training gap reduces apparent rate of progress', () {
        final base = DateTime(2024, 1, 1);
        // 5 improving sessions close together, then a 180-day gap at the same weight.
        // The long gap with no change should reduce the slope substantially.
        final tightSessions = makeSessions([100, 102, 104, 106, 108]);
        final withGap = [
          ...tightSessions,
          (base.add(const Duration(days: 180)), 108.0),
        ];
        final withGapResult = PlateauDetector.analyse(withGap);
        final withoutGapResult = PlateauDetector.analyse(tightSessions);
        // The gap session carries full weight (most recent = 1.0) and shows
        // zero progress over 180 days, so the slope should be lower.
        expect(withGapResult.slope, lessThan(withoutGapResult.slope));
      });
    });
  });
}
