// Typed analytics domain shared by ExerciseAnalyticsService and the planned
// dashboard / exercise analytics / weekly review features (Phases 6-8).
//
// Pure Dart by design: no Flutter, no Firestore, no presentation strings.
// Human-readable prose is a presentation/narration concern and never lives
// in these types. None of these types are stored, so they deliberately have
// no serialization methods.
//
// Calendar/timezone assumptions: all analytics operate on the device-local
// DateTime derived from stored timestamps; a "day" is the local calendar
// date (see [dateOnly]). Definitions: docs/ANALYTICS_DEFINITIONS.md.

/// Strips the time component, leaving the local calendar date.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// An inclusive range of local calendar days. Times on [start]/[end] inputs
/// are ignored.
class DatePeriod {
  final DateTime start; // first day, inclusive
  final DateTime end; // last day, inclusive

  DatePeriod(DateTime start, DateTime end)
    : start = dateOnly(start),
      end = dateOnly(end) {
    if (this.end.isBefore(this.start)) {
      throw ArgumentError('DatePeriod end ($end) is before start ($start)');
    }
  }

  /// The [days]-day period ending on (and including) [endingOn].
  /// Example: lastDays(7, endingOn: today) = today and the 6 days before it.
  factory DatePeriod.lastDays(int days, {required DateTime endingOn}) {
    if (days < 1) throw ArgumentError('days must be >= 1');
    final end = dateOnly(endingOn);
    return DatePeriod(end.subtract(Duration(days: days - 1)), end);
  }

  /// The Monday-Sunday week of local calendar days containing [date]
  /// (Phase 6 dashboard convention). Uses DateTime component arithmetic so
  /// a DST transition cannot shift the boundaries.
  factory DatePeriod.weekContaining(DateTime date) {
    final d = dateOnly(date);
    final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
    return DatePeriod(
      monday,
      DateTime(monday.year, monday.month, monday.day + 6),
    );
  }

  /// The Monday-Sunday week immediately before this week-period.
  DatePeriod get previousWeek => DatePeriod(
    DateTime(start.year, start.month, start.day - 7),
    DateTime(start.year, start.month, start.day - 1),
  );

  /// Number of calendar days in the period (>= 1). Rounded from hours so a
  /// DST transition inside the period cannot skew the count.
  int get dayCount => (end.difference(start).inHours / 24).round() + 1;

  bool contains(DateTime date) {
    final d = dateOnly(date);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  @override
  String toString() => 'DatePeriod($start..$end)';
}

/// Why a metric could not be produced.
enum InsufficiencyReason {
  /// No usable observations at all.
  noData,

  /// The requested exercise does not appear in the history.
  noMatchingExercise,

  /// Some observations exist, but fewer than the calculation requires.
  tooFewSessions,

  /// A percentage change was requested against a zero baseline; the change
  /// is mathematically undefined (never reported as 0 or infinity).
  zeroBaseline,
}

/// A calculated metric that is either available (including a genuine zero)
/// or explicitly unavailable with a typed reason. Never encodes absence as
/// null or zero.
sealed class MetricResult<T> {
  const MetricResult();

  bool get isAvailable => this is MetricAvailable<T>;

  T? get valueOrNull => switch (this) {
    MetricAvailable<T>(:final value) => value,
    MetricUnavailable<T>() => null,
  };
}

class MetricAvailable<T> extends MetricResult<T> {
  final T value;
  const MetricAvailable(this.value);
}

class MetricUnavailable<T> extends MetricResult<T> {
  final InsufficiencyReason reason;

  /// Optional counts explaining "too few": what was observed vs required.
  final int? observedCount;
  final int? requiredCount;

  const MetricUnavailable(
    this.reason, {
    this.observedCount,
    this.requiredCount,
  });
}

enum ChangeDirection { increase, decrease, unchanged }

/// A defined percentage change between two explicit periods.
/// Undefined changes (zero baseline, missing data) are never represented by
/// this type - they surface as [MetricUnavailable].
class PercentageChange {
  /// Signed percent: +10 means 10% higher than baseline.
  final double percent;
  final double baselineValue;
  final double currentValue;
  final DatePeriod baselinePeriod;
  final DatePeriod currentPeriod;

  const PercentageChange({
    required this.percent,
    required this.baselineValue,
    required this.currentValue,
    required this.baselinePeriod,
    required this.currentPeriod,
  });

  ChangeDirection get direction => percent > 0
      ? ChangeDirection.increase
      : percent < 0
      ? ChangeDirection.decrease
      : ChangeDirection.unchanged;
}

/// What a piece of evidence or a metric refers to.
enum MetricType {
  estimatedOneRepMax,
  sessionVolume,
  trainingFrequency,
  workoutCount,
  feelRating,
}

/// How much usable data backs a conclusion. Categorical on purpose: no
/// fabricated numeric confidence percentages (see docs/DECISIONS.md).
enum DataQuality { insufficient, limited, moderate, strong }

/// How much attention a finding warrants. Distinct from [DataQuality]
/// (amount of data) and [ChangeDirection] (direction of change).
enum Severity { info, caution, warning }

/// One structured observation supporting an insight or recommendation.
/// Answers: which metric, what value, judged against what, over what period,
/// and whether the underlying data was sufficient.
class EvidenceItem {
  final MetricType metric;

  /// The observed value, in the metric's natural unit (kg for e1RM/volume,
  /// sessions-per-week for frequency). Null when the evidence is about
  /// absence of data.
  final double? observedValue;

  /// The threshold or baseline the observation was judged against, if any.
  final double? comparisonValue;

  /// The period the observation relates to, if time-bounded.
  final DatePeriod? period;

  final bool dataSufficient;

  const EvidenceItem({
    required this.metric,
    this.observedValue,
    this.comparisonValue,
    this.period,
    this.dataSufficient = true,
  });
}

/// One exercise's training on one local calendar day. Multiple workouts on
/// the same day merge into one session: best e1RM is the max across them,
/// volume is the sum. Warm-up and malformed sets are already excluded.
class ExerciseSession {
  /// Local calendar date (time component stripped).
  final DateTime day;

  /// Best capped-Epley estimated 1RM among the day's working sets, kg.
  final double bestE1RmKg;

  /// Sum of weight x reps over the day's working sets, kg.
  final double volumeKg;

  final int workingSetCount;

  const ExerciseSession({
    required this.day,
    required this.bestE1RmKg,
    required this.volumeKg,
    required this.workingSetCount,
  });
}

/// All sessions for one exercise, ascending by day, one entry per day.
class ExerciseSeries {
  /// The stored exercise name that was matched (trimmed, original casing).
  final String exerciseName;

  final List<ExerciseSession> sessions;

  const ExerciseSeries({required this.exerciseName, required this.sessions});

  bool get isEmpty => sessions.isEmpty;
}
