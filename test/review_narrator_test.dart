import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/models/weekly_review.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/services/review_narrator.dart';
import 'package:gymconnect/services/weekly_review_service.dart';

// Same reference frame as the service tests: Wednesday 1 July 2026.
final ref = DateTime(2026, 7, 1, 12);

const narrator = TemplateReviewNarrator();

int _id = 0;

WorkoutModel _workout(
  DateTime date, {
  String exercise = 'Bench Press',
  double weight = 60,
  int reps = 5,
  int? feel,
}) => WorkoutModel(
  id: 'w-${_id++}',
  date: Timestamp.fromDate(date),
  feelRating: feel,
  exercises: [
    ExerciseEntry(
      name: exercise,
      sets: [WorkoutSet(weight: weight, reps: reps)],
    ),
  ],
);

WeeklyReview _review(List<WorkoutModel> workouts, {int skipped = 0}) =>
    WeeklyReviewService.build(
      workouts,
      referenceDate: ref,
      skippedRecords: skipped,
    );

ReviewNarration _narrate(WeeklyReview r) =>
    narrator.narrate(r, weightUnit: 'kg');

/// A rich review: regressing Bench, plateaued Squat, feel ratings, skips.
WeeklyReview _populatedReview() => _review([
  for (var i = 0; i < 6; i++)
    _workout(DateTime(2026, 6, 30 - 4 * (5 - i)), weight: 70 - 2.0 * i),
  for (var i = 0; i < 6; i++)
    _workout(
      DateTime(2026, 6, 30 - 4 * (5 - i)),
      exercise: 'Squat',
      weight: 100,
    ),
  _workout(DateTime(2026, 6, 29), exercise: 'Deadlift', feel: 2),
], skipped: 1);

void main() {
  setUp(() => _id = 0);

  test('empty (no-data) review still narrates a headline and summary with '
      'empty sections', () {
    final n = _narrate(_review([]));
    expect(n.headline, isNotEmpty);
    expect(n.summary, isNotEmpty);
    expect(n.improvements, isEmpty);
    expect(n.stable, isEmpty);
    expect(n.attention, isEmpty);
    expect(n.actions, isEmpty);
  });

  test('populated review: narrated lists stay parallel to the typed lists '
      'and name the exercises involved', () {
    final r = _populatedReview();
    final n = _narrate(r);
    expect(n.improvements.length, r.improvements.length);
    expect(n.stable.length, r.stable.length);
    expect(n.attention.length, r.attention.length);
    expect(n.actions.length, r.actions.length);
    expect(n.attention.join(' '), contains('Bench Press'));
    expect(n.attention.join(' '), contains('Squat'));
  });

  test('insufficient-data review states the observed count and the '
      'requirement instead of judging a trend', () {
    final r = _review([_workout(DateTime(2026, 6, 30))]);
    final n = _narrate(r);
    final all = [...n.attention, ...n.actions].join(' ');
    expect(all, contains('Only 1 workout'));
    expect(all, contains('Log a few more sessions'));
    // no trend judgement anywhere
    expect(all.contains('plateau'), isFalse);
    expect(all.contains('declining'), isFalse);
  });

  test('partial-data warning: skipped records are narrated', () {
    final n = _narrate(_review([_workout(DateTime(2026, 6, 30))], skipped: 3));
    expect(
      n.attention.join(' '),
      contains('3 stored workout records couldn\'t be read'),
    );
  });

  test('concerns keep cautious possible/may wording - never certainty or '
      'proven causes', () {
    final n = _narrate(_populatedReview());
    final concernLines = [...n.attention, ...n.actions].join(' ');
    expect(concernLines, contains('may be declining'));
    expect(concernLines, contains('possible plateau'));
    expect(concernLines.toLowerCase(), isNot(contains('certainly')));
    expect(concernLines.toLowerCase(), isNot(contains('proven')));
    expect(concernLines.toLowerCase(), isNot(contains('caused by')));
    expect(concernLines, contains('not medical advice'));
  });

  test('no invented metric values: an unavailable volume comparison '
      'produces no volume sentence', () {
    // Previous week untrained: the volume change is unavailable(noData).
    final r = _review([
      _workout(DateTime(2026, 6, 29)),
      _workout(DateTime(2026, 6, 30)),
    ]);
    final n = _narrate(r);
    final all = [...n.improvements, ...n.stable, ...n.attention].join(' ');
    expect(all.contains('volume'), isFalse);
    expect(all.contains('%'), isFalse);
  });

  test('no unsupported recommendations: every narrated action maps to a '
      'typed action', () {
    final r = _populatedReview();
    final n = _narrate(r);
    expect(n.actions.length, r.actions.length);
    // The plateau/regression scenario must not narrate "keep it up" advice.
    expect(n.actions.join(' ').contains('appears to be working'), isFalse);
  });

  test('deterministic: identical input narrates identically', () {
    final r = _populatedReview();
    final a = _narrate(r);
    final b = _narrate(r);
    expect(a.headline, b.headline);
    expect(a.summary, b.summary);
    expect(a.improvements, b.improvements);
    expect(a.stable, b.stable);
    expect(a.attention, b.attention);
    expect(a.actions, b.actions);
  });

  test('weight unit parameter converts displayed weights', () {
    // PR scenario: 60 -> 62.5 -> 70 kg; e1RM 81.7 kg -> ~180 lbs.
    final r = _review([
      _workout(DateTime(2026, 6, 10), weight: 60),
      _workout(DateTime(2026, 6, 20), weight: 62.5),
      _workout(DateTime(2026, 6, 30), weight: 70),
    ]);
    final kg = narrator.narrate(r, weightUnit: 'kg').improvements.join(' ');
    final lbs = narrator.narrate(r, weightUnit: 'lbs').improvements.join(' ');
    expect(kg, contains('kg'));
    expect(lbs, contains('lbs'));
    expect(kg, isNot(equals(lbs)));
  });

  test('headline reflects severity: warning beats caution beats positive', () {
    // warning present (regression)
    expect(_narrate(_populatedReview()).headline, 'Worth a closer look');

    // improvements with no concerns at all -> positive: 3 workouts in each
    // week (stable count), rising weights (progressing trend, rising
    // volume), so nothing earns a caution or warning.
    final days = [
      DateTime(2026, 6, 22),
      DateTime(2026, 6, 24),
      DateTime(2026, 6, 26),
      DateTime(2026, 6, 29),
      DateTime(2026, 6, 30),
      DateTime(2026, 7, 1),
    ];
    final progressing = _review([
      for (var i = 0; i < days.length; i++)
        _workout(days[i], weight: 60 + 2.5 * i),
    ]);
    expect(_narrate(progressing).headline, 'A positive week');
  });
}
