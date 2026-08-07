// Unit tests for the progressive-overload hint rule extracted in Phase 11
// (utils/overload_hint.dart). The rule itself is unchanged from the
// dissertation build: single-set or reps-held-up sessions suggest +2.5 kg,
// dropped-reps sessions suggest consolidating first.

import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/utils/dates.dart';
import 'package:gymconnect/utils/overload_hint.dart';

WorkoutSet set(double weight, int reps) =>
    WorkoutSet(weight: weight, reps: reps);

void main() {
  group('computeOverloadHint', () {
    test('no history means no hint', () {
      expect(computeOverloadHint(null), isNull);
      expect(computeOverloadHint([]), isNull);
    });

    test('a single-set session is always strong and suggests +2.5 kg', () {
      final hint = computeOverloadHint([set(100, 5)])!;
      expect(hint.strong, isTrue);
      expect(hint.topWeightKg, 100);
      expect(hint.suggestedWeightKg, 102.5);
    });

    test('reps held up (last >= 75% of first, floored) counts as strong', () {
      // first 8 reps -> floor(6.0) = 6; last set 6 reps holds up
      final hint = computeOverloadHint([set(80, 8), set(80, 6)])!;
      expect(hint.strong, isTrue);
      expect(hint.firstReps, 8);
      expect(hint.lastReps, 6);
    });

    test('dropped reps below the threshold suggest consolidating', () {
      final hint = computeOverloadHint([set(80, 8), set(80, 5)])!;
      expect(hint.strong, isFalse);
    });

    test('top weight is the session maximum, not the first set', () {
      final hint = computeOverloadHint([set(60, 5), set(80, 5), set(70, 5)])!;
      expect(hint.topWeightKg, 80);
    });
  });

  group('date formatting helpers', () {
    test('formatDayMonth and formatDayMonthYear', () {
      final d = DateTime(2026, 7, 4);
      expect(formatDayMonth(d), '4 Jul');
      expect(formatDayMonthYear(d), '4 Jul 2026');
      expect(monthAbbreviation(1), 'Jan');
      expect(monthAbbreviation(12), 'Dec');
    });
  });
}
