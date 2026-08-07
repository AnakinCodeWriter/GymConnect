import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/main.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/screens/progress_screen.dart';
import 'package:gymconnect/services/data_result.dart';
import 'package:gymconnect/services/firestore_service.dart';
import 'package:gymconnect/services/leaderboard_service.dart';
import 'package:gymconnect/services/workout_service.dart';

import 'fake_firestore_adapter.dart';

WorkoutModel _workout(
  DateTime date, {
  String exercise = 'Bench Press',
  double weight = 60,
  int reps = 5,
}) => WorkoutModel(
  id: 'w-${date.millisecondsSinceEpoch}-${exercise.hashCode}',
  date: Timestamp.fromDate(date),
  exercises: [
    ExerciseEntry(
      name: exercise,
      sets: [WorkoutSet(weight: weight, reps: reps)],
    ),
  ],
);

// Rising bench history relative to now: progressing trend.
List<WorkoutModel> _risingHistory() {
  final now = DateTime.now();
  return [
    for (var i = 0; i < 6; i++)
      _workout(now.subtract(Duration(days: i * 3)), weight: 75 - i * 2.5),
  ];
}

// Flat bench history: plateau (with rep-monotony explanation).
List<WorkoutModel> _flatHistory() {
  final now = DateTime.now();
  return [
    for (var i = 0; i < 7; i++)
      _workout(now.subtract(Duration(days: i * 3)), weight: 100),
  ];
}

class _FakeLoader {
  final List<ProgressLoadResult> responses;
  int calls = 0;

  _FakeLoader(this.responses);

  Future<ProgressLoadResult> call() async {
    final r =
        responses[calls < responses.length ? calls : responses.length - 1];
    calls++;
    return r;
  }
}

Widget _app(ProgressLoader loader) =>
    MaterialApp(home: ProgressScreen(loader: loader));

ProgressLoadResult _ok(
  List<WorkoutModel> workouts, {
  List<SkippedDocument> skipped = const [],
}) => ProgressLoadResult(workouts: DataSuccess(workouts, skipped: skipped));

Future<void> _scrollTo(WidgetTester tester, Finder finder) => tester
    .scrollUntilVisible(finder, 150, scrollable: find.byType(Scrollable).first);

void main() {
  setUp(() {
    workoutDataVersion.value = 0;
    progressExerciseRequest.value = null;
  });

  testWidgets('shows the loading state while pending', (tester) async {
    await tester.pumpWidget(
      _app(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return _ok([]);
      }),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('empty history shows the empty state', (tester) async {
    await tester.pumpWidget(_app(() async => _ok([])));
    await tester.pumpAndSettle();
    expect(find.textContaining('No workouts logged yet'), findsOneWidget);
  });

  testWidgets('failed load shows Retry and recovers', (tester) async {
    final loader = _FakeLoader([
      const ProgressLoadResult(
        workouts: DataFailure(DataFailureKind.unavailable),
      ),
      _ok(_risingHistory()),
    ]);
    await tester.pumpWidget(_app(loader.call));
    await tester.pumpAndSettle();
    expect(find.text('Couldn\'t load your workouts'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(loader.calls, 2);
    expect(find.byType(FilterChip), findsWidgets);
  });

  testWidgets('skipped records surface as a notice', (tester) async {
    await tester.pumpWidget(
      _app(
        () async =>
            _ok(_risingHistory(), skipped: const [SkippedDocument('bad', 'x')]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('couldn\'t be read'), findsOneWidget);
  });

  testWidgets('exercise chips render from history', (tester) async {
    await tester.pumpWidget(_app(() async => _ok(_risingHistory())));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, 'Bench Press'), findsOneWidget);
  });

  testWidgets('selecting an exercise shows status, metrics and evidence '
      'sections', (tester) async {
    await tester.pumpWidget(_app(() async => _ok(_risingHistory())));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Bench Press'));
    await tester.pumpAndSettle();

    expect(find.text('Strength Trend'), findsOneWidget);
    expect(find.text('Progressing'), findsOneWidget);
    expect(find.text('Recent best (est. 1RM)'), findsOneWidget);
    expect(find.text('Frequency'), findsOneWidget);
    await _scrollTo(tester, find.text('Why am I seeing this?'));
    expect(find.text('Why am I seeing this?'), findsOneWidget);
  });

  testWidgets('substring exercises do not pollute the selected analytics', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      _app(
        () async => _ok([
          _workout(now.subtract(const Duration(days: 2)), weight: 60),
          _workout(
            now.subtract(const Duration(days: 1)),
            exercise: 'Incline Bench Press',
            weight: 200,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Bench Press'));
    await tester.pumpAndSettle();

    // Bench Press 60x5 -> e1RM 70; the 200 kg incline must not appear as
    // the recent best.
    expect(find.text('70 kg'), findsOneWidget);
    expect(find.textContaining('233'), findsNothing);
  });

  testWidgets('plateau shows "Possible plateau" and a possible explanation, '
      'never certainty wording', (tester) async {
    await tester.pumpWidget(_app(() async => _ok(_flatHistory())));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Bench Press'));
    await tester.pumpAndSettle();

    expect(find.text('Possible plateau'), findsOneWidget);
    await _scrollTo(tester, find.text('Possible explanation'));
    expect(find.text('Possible explanation'), findsOneWidget);
    expect(find.textContaining('Likely Cause'), findsNothing);
  });

  testWidgets('insufficient data is stated, not hidden', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      _app(
        () async => _ok([
          _workout(now, weight: 60),
          _workout(now.subtract(const Duration(days: 3)), weight: 60),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Bench Press'));
    await tester.pumpAndSettle();

    expect(find.text('Not enough data yet'), findsOneWidget);
    // change metrics render unavailable, not fabricated values
    expect(find.text('—'), findsWidgets);
    expect(find.text('not enough data'), findsWidgets);
  });

  testWidgets('evidence panel expands to show the analysis basis', (
    tester,
  ) async {
    await tester.pumpWidget(_app(() async => _ok(_risingHistory())));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Bench Press'));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.text('Why am I seeing this?'));
    await tester.ensureVisible(find.text('Why am I seeing this?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Why am I seeing this?'));
    await tester.pumpAndSettle();

    expect(find.textContaining('valid sessions analysed'), findsOneWidget);
    expect(find.textContaining('plateau band'), findsOneWidget);
    expect(find.textContaining('Data quality:'), findsOneWidget);
  });

  testWidgets('history stays visible below the analytics', (tester) async {
    await tester.pumpWidget(_app(() async => _ok(_risingHistory())));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Bench Press'));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.textContaining('History: Bench Press'));
    expect(find.textContaining('History: Bench Press'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsWidgets);
  });

  testWidgets('pull-to-refresh reloads', (tester) async {
    final loader = _FakeLoader([_ok(_risingHistory())]);
    await tester.pumpWidget(_app(loader.call));
    await tester.pumpAndSettle();
    expect(loader.calls, 1);

    await tester.fling(find.byType(ListView).first, const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(loader.calls, 2);
  });

  testWidgets('workoutDataVersion bump reloads the screen', (tester) async {
    final loader = _FakeLoader([_ok(_risingHistory())]);
    await tester.pumpWidget(_app(loader.call));
    await tester.pumpAndSettle();
    expect(loader.calls, 1);

    workoutDataVersion.value++;
    await tester.pumpAndSettle();
    expect(loader.calls, 2);
  });

  testWidgets('dashboard preselection request selects the exercise', (
    tester,
  ) async {
    await tester.pumpWidget(_app(() async => _ok(_risingHistory())));
    await tester.pumpAndSettle();

    progressExerciseRequest.value = 'Bench Press';
    await tester.pumpAndSettle();

    expect(find.text('Strength Trend'), findsOneWidget);
    expect(progressExerciseRequest.value, isNull); // consumed
  });

  testWidgets('selected exercise vanishing after refresh does not crash', (
    tester,
  ) async {
    final loader = _FakeLoader([_ok(_risingHistory()), _ok([])]);
    await tester.pumpWidget(_app(loader.call));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Bench Press'));
    await tester.pumpAndSettle();
    expect(find.text('Strength Trend'), findsOneWidget);

    workoutDataVersion.value++;
    await tester.pumpAndSettle();
    // empty state takes over; no analytics, no exception
    expect(find.textContaining('No workouts logged yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow width renders without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(() async => _ok(_risingHistory())));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Bench Press'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('2x text scale and no Weekly Review UI', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: ProgressScreen(loader: () async => _ok(_risingHistory())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Weekly Review'), findsNothing);
  });

  testWidgets('dark mode renders without exceptions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
        ),
        home: ProgressScreen(loader: () async => _ok(_risingHistory())),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('warm-up-only exercise stays out of the chips and analytics', (
    tester,
  ) async {
    final now = DateTime.now();
    final workout = WorkoutModel(
      id: 'w1',
      date: Timestamp.fromDate(now.subtract(const Duration(days: 1))),
      exercises: [
        ExerciseEntry(
          name: 'Face Pull',
          sets: [WorkoutSet(weight: 20, reps: 15, isWarmup: true)],
        ),
        ExerciseEntry(
          name: 'Bench Press',
          sets: [WorkoutSet(weight: 60, reps: 5)],
        ),
      ],
    );
    await tester.pumpWidget(_app(() async => _ok([workout])));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilterChip, 'Bench Press'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Face Pull'), findsNothing);
  });

  // -----------------------------------------------------------------------
  // Delete-set flow, testable since Phase 11 via injected service/loaders.
  // -----------------------------------------------------------------------

  group('delete-set flow', () {
    late FakeFirestoreAdapter fake;
    late WorkoutService service;

    setUp(() {
      fake = FakeFirestoreAdapter();
      service = WorkoutService(
        adapter: fake,
        currentUidProvider: () => 'u1',
        profileService: FirestoreService(adapter: fake),
        leaderboardService: LeaderboardService(adapter: fake),
      );
      final day = DateTime.now().subtract(const Duration(days: 1));
      fake.docs['users/u1/workouts/w1'] = {
        'date': Timestamp.fromDate(day),
        'exercises': [
          {
            'name': 'Bench Press',
            'sets': [
              {'weight': 100.0, 'reps': 5},
            ],
          },
        ],
      };
    });

    Widget appWithService() => MaterialApp(
      home: ProgressScreen(
        loader: () async =>
            ProgressLoadResult(workouts: await service.loadWorkouts()),
        workoutService: service,
        profileLoader: () async => null,
      ),
    );

    Future<void> openDeleteDialog(WidgetTester tester) async {
      await tester.pumpWidget(appWithService());
      await tester.pumpAndSettle();
      // expand the session card, then request deletion of its only set
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete entry'));
      await tester.pumpAndSettle();
      expect(find.text('Delete entry?'), findsOneWidget);
    }

    testWidgets('confirmed deletion removes the set, refreshes the screen '
        'and notifies other tabs', (tester) async {
      await openDeleteDialog(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // last set of the last exercise: the whole document is gone
      expect(fake.docs.containsKey('users/u1/workouts/w1'), isFalse);
      expect(find.textContaining('No workouts logged yet'), findsOneWidget);
      expect(workoutDataVersion.value, 1);
      expect(find.text('Failed to delete entry.'), findsNothing);
    });

    testWidgets('cancelled confirmation changes nothing', (tester) async {
      await openDeleteDialog(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(fake.docs.containsKey('users/u1/workouts/w1'), isTrue);
      expect(workoutDataVersion.value, 0);
    });

    testWidgets('failed deletion shows a snackbar and keeps the data', (
      tester,
    ) async {
      await openDeleteDialog(tester);
      fake.throwOnNextCall = Exception('offline');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Failed to delete entry.'), findsOneWidget);
      expect(fake.docs.containsKey('users/u1/workouts/w1'), isTrue);
      expect(workoutDataVersion.value, 0);
    });
  });
}
