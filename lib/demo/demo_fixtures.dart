// Deterministic demo-data fixtures (Phase 9).
//
// Pure Dart by design: no Flutter, Firebase, dart:io, network or randomness
// — the same inputs always generate the same workouts, so screenshots and
// tests are reproducible. The CLI (tool/seed_data.dart) imports this file,
// so it must never gain a Flutter or plugin dependency.
//
// Every scenario is engineered against the app's REAL documented analytics
// rules (docs/ANALYTICS_DEFINITIONS.md): the ±0.1%/day trend thresholds,
// the 5-session trend minimum, the volume-progressing suppression rule, the
// weekly-review feel thresholds and the strictly-beats-all-earlier PR rule.
// Values are deliberately believable: hold-then-jump loading, an occasional
// back-off, warm-up sets, rest-day gaps and multi-exercise sessions — never
// perfectly linear robots (docs/DECISIONS.md, Phase 9).

/// The demo scenarios the tooling can seed. Keys double as the default
/// batch id, so reseeding a scenario replaces it.
enum DemoScenario {
  progressing,
  plateau,
  regression,
  volumeProgressing,
  insufficientData,
}

extension DemoScenarioInfo on DemoScenario {
  String get key => switch (this) {
    DemoScenario.progressing => 'progressing',
    DemoScenario.plateau => 'plateau',
    DemoScenario.regression => 'regression',
    DemoScenario.volumeProgressing => 'volume-progressing',
    DemoScenario.insufficientData => 'insufficient-data',
  };

  String get title => switch (this) {
    DemoScenario.progressing => 'Progressing',
    DemoScenario.plateau => 'Plateau',
    DemoScenario.regression => 'Regression',
    DemoScenario.volumeProgressing => 'Volume progressing',
    DemoScenario.insufficientData => 'Insufficient data',
  };

  String get description => switch (this) {
    DemoScenario.progressing =>
      '8 weeks, 3 sessions/week. Bench Press and Squat climb steadily '
          '(with holds and one back-off), Incline Bench Press demonstrates '
          'exact-name matching, feel improves, and fresh PRs land in the '
          'final week.',
    DemoScenario.plateau =>
      '7 weeks, 2 sessions/week. Bench Press is stuck at the same top '
          'weight (rep monotony triggers a possible explanation) while Squat '
          'and Deadlift keep progressing. Feel is steady.',
    DemoScenario.regression =>
      '7 weeks, 2 sessions/week. Overhead Press declines while Bench '
          'Press and Barbell Row still progress; session feel worsens over '
          'the final weeks.',
    DemoScenario.volumeProgressing =>
      '7 weeks, 2 sessions/week. Deadlift e1RM stays flat but set count '
          'grows every fortnight, so rising volume suppresses the plateau '
          'concern. Feel ratings are sparse.',
    DemoScenario.insufficientData =>
      'Two recent full-body workouts: enough for history and a chart '
          'point, not enough for any trend judgement.',
  };

  static DemoScenario? fromKey(String key) {
    for (final s in DemoScenario.values) {
      if (s.key == key) return s;
    }
    return null;
  }
}

class DemoSet {
  final double weight; // kg, matches the storage convention
  final int reps;
  final bool isWarmup;

  const DemoSet(this.weight, this.reps, {this.isWarmup = false});
}

class DemoExercise {
  final String name;
  final List<DemoSet> sets;

  const DemoExercise(this.name, this.sets);
}

/// One generated workout plus its deterministic document id, so seeding is
/// naturally idempotent (same inputs, same ids, overwrite not duplicate).
class DemoWorkoutSpec {
  final String documentId;
  final DateTime date;
  final String name;
  final int? feelRating;
  final List<DemoExercise> exercises;

  const DemoWorkoutSpec({
    required this.documentId,
    required this.date,
    required this.name,
    required this.feelRating,
    required this.exercises,
  });
}

/// Generates the scenario's workouts, oldest first. All dates derive from
/// [referenceDate] via calendar-component arithmetic (DST-safe), with the
/// newest session 1–3 days before the reference date.
///
/// Note: weekly-review week-over-week comparisons bucket sessions into
/// Monday–Sunday weeks, so which sessions count as "this week" depends on
/// the reference date's weekday; demos read best seeded Wednesday–Sunday.
List<DemoWorkoutSpec> generateDemoWorkouts(
  DemoScenario scenario, {
  required DateTime referenceDate,
}) {
  switch (scenario) {
    case DemoScenario.progressing:
      return _progressing(referenceDate);
    case DemoScenario.plateau:
      return _plateau(referenceDate);
    case DemoScenario.regression:
      return _regression(referenceDate);
    case DemoScenario.volumeProgressing:
      return _volumeProgressing(referenceDate);
    case DemoScenario.insufficientData:
      return _insufficientData(referenceDate);
  }
}

// ---- shared helpers ----

DateTime _onDay(DateTime ref, int daysAgo) =>
    DateTime(ref.year, ref.month, ref.day - daysAgo, 10, 30);

String _docId(DemoScenario s, int index) =>
    'demo-${s.key}-${index.toString().padLeft(2, '0')}';

/// 14 sessions, 2 per week for 7 weeks, at 3 and 1 days before each week's
/// anchor: [45, 43, 38, 36, ..., 3, 1] days ago (oldest first).
List<int> _twicePerWeekDaysAgo() => [
  for (var j = 0; j < 14; j++) (j.isEven ? 3 : 1) + 7 * (6 - j ~/ 2),
];

DemoSet _w(double weight, int reps) => DemoSet(weight, reps, isWarmup: true);
DemoSet _s(double weight, int reps) => DemoSet(weight, reps);

// ---- scenarios ----

List<DemoWorkoutSpec> _progressing(DateTime ref) {
  // Hold-then-jump loading with one deliberate back-off (index 4).
  const benchTop = <double>[
    60, 60, 62.5, 62.5, 60, 65, 65, 67.5, 67.5, 70, 70, 72.5, //
  ];
  const incline = <double>[
    47.5, 47.5, 50, 50, 47.5, 52.5, 52.5, 55, 55, 57.5, 57.5, 60, //
  ];
  const ohp = <double>[
    40, 40, 40, 42.5, 42.5, 42.5, 45, 45, 45, 45, 47.5, 47.5, //
  ];
  const squat = <double>[
    90, 90, 92.5, 95, 95, 97.5, 100, 100, 102.5, 105, 107.5, 110, //
  ];
  const row = <double>[
    60, 60, 62.5, 62.5, 62.5, 65, 65, 65, 67.5, 67.5, 67.5, 70, //
  ];
  // Feel improves across the block (weekly averages rise ~3.0 -> ~4.5+).
  const feel = <int>[
    3, 3, 2, 3, 3, 3, 3, 4, 3, 3, 4, 4, //
    3, 4, 4, 4, 3, 4, 4, 4, 4, 4, 5, 5, //
  ];

  return [
    for (var i = 0; i < 24; i++)
      () {
        final daysAgo = 55 - 7 * (i ~/ 3) - 2 * (i % 3);
        final j = i ~/ 2;
        final isPush = i.isEven;
        return DemoWorkoutSpec(
          documentId: _docId(DemoScenario.progressing, i),
          date: _onDay(ref, daysAgo),
          name: isPush ? 'Push Day' : 'Legs & Pull',
          feelRating: feel[i],
          exercises: isPush
              ? [
                  DemoExercise('Bench Press', [
                    _w(40, 8),
                    _s(benchTop[j], 5),
                    _s(benchTop[j], 5),
                    _s(benchTop[j] - 5, 8),
                  ]),
                  DemoExercise('Incline Bench Press', [
                    _s(incline[j], 8),
                    _s(incline[j], 8),
                    _s(incline[j], 8),
                  ]),
                  DemoExercise('Overhead Press', [
                    _s(ohp[j], 6),
                    _s(ohp[j], 6),
                  ]),
                ]
              : [
                  DemoExercise('Squat', [
                    _w(60, 6),
                    _s(squat[j], 5),
                    _s(squat[j], 5),
                    _s(squat[j], 5),
                  ]),
                  DemoExercise('Barbell Row', [
                    _s(row[j], 8),
                    _s(row[j], 8),
                    _s(row[j], 8),
                  ]),
                ],
        );
      }(),
  ];
}

List<DemoWorkoutSpec> _plateau(DateTime ref) {
  final daysAgo = _twicePerWeekDaysAgo();
  // Bench top weight is stuck; one 82.5x4 attempt keeps it human while the
  // modal 5-rep pattern still triggers the rep-monotony explanation.
  const squat = <double>[100, 100, 102.5, 105, 105, 107.5, 110];
  const deadlift = <double>[130, 132.5, 132.5, 135, 135, 137.5, 140];
  // Steady feel: recent weekly averages sit level (3.5 vs 3.5).
  const feel = <int>[3, 4, 3, 3, 4, 3, 4, 3, 3, 4, 4, 3, 3, 4];

  return [
    for (var j = 0; j < 14; j++)
      DemoWorkoutSpec(
        documentId: _docId(DemoScenario.plateau, j),
        date: _onDay(ref, daysAgo[j]),
        name: j.isEven ? 'Strength A' : 'Strength B',
        feelRating: feel[j],
        exercises: [
          DemoExercise('Bench Press', [
            _w(50, 6),
            if (j == 7) ...[
              _s(82.5, 4),
              _s(82.5, 4),
              _s(82.5, 4),
            ] else ...[
              _s(80, 5),
              _s(80, 5),
              _s(80, 5),
            ],
            _s(72.5, 8),
          ]),
          if (j.isEven)
            DemoExercise('Squat', [
              _w(60, 6),
              _s(squat[j ~/ 2], 5),
              _s(squat[j ~/ 2], 5),
              _s(squat[j ~/ 2], 5),
            ])
          else
            DemoExercise('Deadlift', [
              _w(90, 5),
              _s(deadlift[j ~/ 2], 3),
              _s(deadlift[j ~/ 2], 3),
            ]),
        ],
      ),
  ];
}

List<DemoWorkoutSpec> _regression(DateTime ref) {
  final daysAgo = _twicePerWeekDaysAgo();
  const ohp = <double>[
    55, 55, 52.5, 52.5, 52.5, 50, 52.5, 50, 50, 47.5, 47.5, 47.5, 45, 45, //
  ];
  const bench = <double>[70, 70, 72.5, 72.5, 75, 75, 77.5];
  const row = <double>[62.5, 65, 65, 67.5, 67.5, 70, 70];
  // Feel declines over the block (recent weekly averages 3.0 -> 2.0).
  const feel = <int>[4, 4, 4, 5, 4, 4, 3, 4, 3, 3, 3, 3, 2, 2];

  return [
    for (var j = 0; j < 14; j++)
      DemoWorkoutSpec(
        documentId: _docId(DemoScenario.regression, j),
        date: _onDay(ref, daysAgo[j]),
        name: j.isEven ? 'Press Day A' : 'Press Day B',
        feelRating: feel[j],
        exercises: [
          DemoExercise('Overhead Press', [
            _w(30, 8),
            _s(ohp[j], 6),
            _s(ohp[j], 6),
            _s(ohp[j], 6),
          ]),
          if (j.isEven)
            DemoExercise('Bench Press', [
              _w(45, 8),
              _s(bench[j ~/ 2], 5),
              _s(bench[j ~/ 2], 5),
            ])
          else
            DemoExercise('Barbell Row', [
              _s(row[j ~/ 2], 8),
              _s(row[j ~/ 2], 8),
              _s(row[j ~/ 2], 8),
            ]),
        ],
      ),
  ];
}

List<DemoWorkoutSpec> _volumeProgressing(DateTime ref) {
  final daysAgo = _twicePerWeekDaysAgo();
  const squat = <double>[95, 95, 97.5, 100, 100, 102.5, 105];
  const pullUp = <double>[10, 10, 10, 12.5, 12.5, 15, 15];
  return [
    for (var j = 0; j < 14; j++)
      DemoWorkoutSpec(
        documentId: _docId(DemoScenario.volumeProgressing, j),
        date: _onDay(ref, daysAgo[j]),
        name: j.isEven ? 'Deadlift Day A' : 'Deadlift Day B',
        // Sparse feel: only two rated sessions across the whole block.
        feelRating: j == 2 ? 3 : (j == 9 ? 4 : null),
        exercises: [
          DemoExercise('Deadlift', [
            _w(90, 5),
            // Same top weight throughout; the set count grows instead, so
            // volume trends up while e1RM stays flat (suppression demo).
            for (var s = 0; s < 2 + j ~/ 3; s++) _s(140, 3),
          ]),
          if (j.isEven)
            DemoExercise('Squat', [
              _w(60, 6),
              _s(squat[j ~/ 2], 5),
              _s(squat[j ~/ 2], 5),
            ])
          else
            DemoExercise('Pull Up', [
              _s(pullUp[j ~/ 2], 6),
              _s(pullUp[j ~/ 2], 6),
              _s(pullUp[j ~/ 2], 6),
            ]),
        ],
      ),
  ];
}

List<DemoWorkoutSpec> _insufficientData(DateTime ref) {
  DemoWorkoutSpec fullBody(int index, int daysAgo, int? feel) =>
      DemoWorkoutSpec(
        documentId: _docId(DemoScenario.insufficientData, index),
        date: _onDay(ref, daysAgo),
        name: index == 0 ? 'Full Body A' : 'Full Body B',
        feelRating: feel,
        exercises: [
          DemoExercise('Bench Press', [
            _w(40, 8),
            _s(60, 5),
            _s(60, 5),
            _s(60, 5),
          ]),
          DemoExercise('Squat', [_w(60, 6), _s(90, 5), _s(90, 5), _s(90, 5)]),
          DemoExercise('Barbell Row', [_s(60, 8), _s(60, 8)]),
        ],
      );

  return [fullBody(0, 8, null), fullBody(1, 3, 4)];
}
