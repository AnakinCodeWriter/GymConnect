import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/models/analytics.dart';

void main() {
  group('DatePeriod', () {
    test('normalises inputs to date-only and is inclusive of both ends', () {
      final p = DatePeriod(
        DateTime(2026, 6, 1, 23, 59),
        DateTime(2026, 6, 7, 0, 1),
      );
      expect(p.start, DateTime(2026, 6, 1));
      expect(p.end, DateTime(2026, 6, 7));
      expect(p.dayCount, 7);
      expect(p.contains(DateTime(2026, 6, 1, 6)), isTrue);
      expect(p.contains(DateTime(2026, 6, 7, 23)), isTrue);
      expect(p.contains(DateTime(2026, 5, 31)), isFalse);
      expect(p.contains(DateTime(2026, 6, 8)), isFalse);
    });

    test('single-day period has dayCount 1 and contains only that day', () {
      final p = DatePeriod(DateTime(2026, 6, 15), DateTime(2026, 6, 15));
      expect(p.dayCount, 1);
      expect(p.contains(DateTime(2026, 6, 15, 12)), isTrue);
      expect(p.contains(DateTime(2026, 6, 16)), isFalse);
    });

    test('end before start throws', () {
      expect(
        () => DatePeriod(DateTime(2026, 6, 10), DateTime(2026, 6, 9)),
        throwsArgumentError,
      );
    });

    test('lastDays(7) covers the reference day and the 6 before it', () {
      final p = DatePeriod.lastDays(7, endingOn: DateTime(2026, 6, 30, 15));
      expect(p.start, DateTime(2026, 6, 24));
      expect(p.end, DateTime(2026, 6, 30));
      expect(p.dayCount, 7);
    });

    test('lastDays(1) is just the reference day', () {
      final p = DatePeriod.lastDays(1, endingOn: DateTime(2026, 6, 30));
      expect(p.start, p.end);
      expect(p.dayCount, 1);
    });

    test('lastDays rejects non-positive day counts', () {
      expect(
        () => DatePeriod.lastDays(0, endingOn: DateTime(2026, 6, 30)),
        throwsArgumentError,
      );
    });
  });

  group('MetricResult', () {
    test('available carries its value, including a genuine zero', () {
      const zero = MetricAvailable<double>(0);
      expect(zero.isAvailable, isTrue);
      expect(zero.valueOrNull, 0);
    });

    test('unavailable exposes reason and optional counts', () {
      const r = MetricUnavailable<double>(
        InsufficiencyReason.tooFewSessions,
        observedCount: 3,
        requiredCount: 5,
      );
      expect(r.isAvailable, isFalse);
      expect(r.valueOrNull, isNull);
      expect(r.reason, InsufficiencyReason.tooFewSessions);
      expect(r.observedCount, 3);
      expect(r.requiredCount, 5);
    });
  });

  group('PercentageChange.direction', () {
    PercentageChange change(double percent) => PercentageChange(
      percent: percent,
      baselineValue: 100,
      currentValue: 100 + percent,
      baselinePeriod: DatePeriod(DateTime(2026, 6, 1), DateTime(2026, 6, 7)),
      currentPeriod: DatePeriod(DateTime(2026, 6, 8), DateTime(2026, 6, 14)),
    );

    test('positive percent is an increase', () {
      expect(change(5).direction, ChangeDirection.increase);
    });
    test('negative percent is a decrease', () {
      expect(change(-5).direction, ChangeDirection.decrease);
    });
    test('zero percent is unchanged', () {
      expect(change(0).direction, ChangeDirection.unchanged);
    });
  });

  group('EvidenceItem', () {
    test(
      'captures metric, observation, comparison, period and sufficiency',
      () {
        final e = EvidenceItem(
          metric: MetricType.sessionVolume,
          observedValue: 1200,
          comparisonValue: 1000,
          period: DatePeriod(DateTime(2026, 6, 1), DateTime(2026, 6, 7)),
          dataSufficient: true,
        );
        expect(e.metric, MetricType.sessionVolume);
        expect(e.observedValue, 1200);
        expect(e.comparisonValue, 1000);
        expect(e.period!.dayCount, 7);
        expect(e.dataSufficient, isTrue);
      },
    );
  });
}
