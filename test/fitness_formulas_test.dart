import 'package:flutter_test/flutter_test.dart';
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

    test('9 reps and 10 reps produce different results - cap does not apply early', () {
      expect(estimatedOneRepMax(100, 9), isNot(equals(estimatedOneRepMax(100, 10))));
    });

    test('result scales linearly with weight', () {
      expect(
        estimatedOneRepMax(200, 5),
        closeTo(estimatedOneRepMax(100, 5) * 2, 0.01),
      );
    });
  });
}
