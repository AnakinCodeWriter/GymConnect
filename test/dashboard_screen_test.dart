import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/main.dart';
import 'package:gymconnect/models/user_model.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/screens/home_screen.dart';
import 'package:gymconnect/services/data_result.dart';

WorkoutModel _workout(DateTime date, {double weight = 60}) => WorkoutModel(
  id: 'w-${date.millisecondsSinceEpoch}',
  date: Timestamp.fromDate(date),
  exercises: [
    ExerciseEntry(
      name: 'Bench Press',
      sets: [WorkoutSet(weight: weight, reps: 5)],
    ),
  ],
);

List<WorkoutModel> _history() {
  final now = DateTime.now();
  return [
    for (var i = 0; i < 6; i++)
      _workout(now.subtract(Duration(days: i * 3)), weight: 60 + i * 2.5),
  ];
}

UserModel _profileWithGoal() => UserModel(
  uid: 'u1',
  displayName: 'Alfie',
  gymId: 'g',
  createdAt: Timestamp.now(),
  goalExercise: 'Bench Press',
  goalTargetWeight: 100,
  personalRecords: const {'Bench Press': 80},
);

/// Scripted loader: returns queued results in order, repeating the last.
class _FakeLoader {
  final List<DashboardLoadResult> responses;
  int calls = 0;

  _FakeLoader(this.responses);

  Future<DashboardLoadResult> call() async {
    final r =
        responses[calls < responses.length ? calls : responses.length - 1];
    calls++;
    return r;
  }
}

Widget _app(DashboardLoader loader) =>
    MaterialApp(home: HomeScreen(loader: loader));

void main() {
  setUp(() {
    workoutDataVersion.value = 0;
    progressExerciseRequest.value = null;
  });

  testWidgets('tapping a Most trained row requests progress preselection', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(() async => DashboardLoadResult(workouts: DataSuccess(_history()))),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.textContaining('Most trained'), 150);
    await tester.tap(find.text('Bench Press').first);
    await tester.pump();
    // no shell in this test, so only the request notifier changes
    expect(progressExerciseRequest.value, 'Bench Press');
  });

  testWidgets('shows the loading state while the loader is pending', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return const DashboardLoadResult(workouts: DataSuccess([]));
      }),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('empty success encourages the first workout and keeps '
      'Log Workout visible', (tester) async {
    await tester.pumpWidget(
      _app(() async => const DashboardLoadResult(workouts: DataSuccess([]))),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No workouts yet'), findsOneWidget);
    expect(find.text('Log Workout'), findsOneWidget);
  });

  testWidgets('populated dashboard shows metrics, status, goal and actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        () async => DashboardLoadResult(
          workouts: DataSuccess(_history()),
          profile: _profileWithGoal(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome back, Alfie!'), findsOneWidget);
    expect(find.textContaining('Week of'), findsOneWidget);
    expect(find.text('Workouts this week'), findsOneWidget);
    expect(find.text('Volume this week'), findsOneWidget);
    expect(find.text('Log Workout'), findsOneWidget);
    expect(find.text('Training Status'), findsOneWidget);
    expect(find.textContaining('Weekly Review'), findsNothing);

    // lower sections are built lazily by the ListView - scroll to them.
    await tester.scrollUntilVisible(find.text('Training Goal'), 150);
    expect(find.text('Training Goal'), findsOneWidget); // goal card
    await tester.scrollUntilVisible(find.textContaining('Most trained'), 150);
    expect(find.textContaining('Most trained'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('View detailed progress'), 150);
    expect(find.text('View detailed progress'), findsOneWidget);
    expect(find.textContaining('Weekly Review'), findsNothing);
  });

  testWidgets('failed initial load shows Retry, and retrying recovers', (
    tester,
  ) async {
    final loader = _FakeLoader([
      const DashboardLoadResult(
        workouts: DataFailure(DataFailureKind.unavailable),
      ),
      DashboardLoadResult(workouts: DataSuccess(_history())),
    ]);
    await tester.pumpWidget(_app(loader.call));
    await tester.pumpAndSettle();

    expect(find.text('Couldn\'t load your dashboard'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(loader.calls, 2);
    expect(find.text('Workouts this week'), findsOneWidget);
  });

  testWidgets('failed refresh keeps last-known data behind a warning banner', (
    tester,
  ) async {
    final loader = _FakeLoader([
      DashboardLoadResult(workouts: DataSuccess(_history())),
      const DashboardLoadResult(
        workouts: DataFailure(DataFailureKind.unavailable),
      ),
    ]);
    await tester.pumpWidget(_app(loader.call));
    await tester.pumpAndSettle();
    expect(find.text('Workouts this week'), findsOneWidget);

    // another screen bumps the data version; the refresh fails.
    workoutDataVersion.value++;
    await tester.pumpAndSettle();

    expect(find.text('Couldn\'t refresh your training data'), findsOneWidget);
    // last-known data still visible
    expect(find.text('Workouts this week'), findsOneWidget);
  });

  testWidgets('skipped malformed records surface as a visible notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        () async => DashboardLoadResult(
          workouts: DataSuccess(
            _history(),
            skipped: const [SkippedDocument('bad-1', 'unparseable')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('couldn\'t be read'), findsOneWidget);
  });

  testWidgets('no horizontal overflow at a narrow width', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        () async => DashboardLoadResult(
          workouts: DataSuccess(_history()),
          profile: _profileWithGoal(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('2x text scale renders without exceptions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: HomeScreen(
            loader: () async =>
                DashboardLoadResult(workouts: DataSuccess(_history())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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
        home: HomeScreen(
          loader: () async =>
              DashboardLoadResult(workouts: DataSuccess(_history())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
