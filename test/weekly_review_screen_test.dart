import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/main.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/screens/weekly_review_screen.dart';
import 'package:gymconnect/services/data_result.dart';

WorkoutModel _workout(
  DateTime date, {
  String exercise = 'Bench Press',
  double weight = 60,
  int? feel,
}) => WorkoutModel(
  id: 'w-${date.millisecondsSinceEpoch}-${exercise.hashCode}',
  date: Timestamp.fromDate(date),
  feelRating: feel,
  exercises: [
    ExerciseEntry(
      name: exercise,
      sets: [WorkoutSet(weight: weight, reps: 5)],
    ),
  ],
);

/// Mixed history relative to the real clock (the screen injects
/// DateTime.now()): a regressing exercise plus workouts in both weeks.
List<WorkoutModel> _history() {
  final now = DateTime.now();
  return [
    // i counts BACK in time, so weights fall toward today: regressing.
    for (var i = 0; i < 6; i++)
      _workout(now.subtract(Duration(days: i * 3)), weight: 62 + i * 2.0),
  ];
}

/// Scripted loader: returns queued results in order, repeating the last.
class _FakeLoader {
  final List<DataResult<List<WorkoutModel>>> responses;
  int calls = 0;

  _FakeLoader(this.responses);

  Future<DataResult<List<WorkoutModel>>> call() async {
    final r =
        responses[calls < responses.length ? calls : responses.length - 1];
    calls++;
    return r;
  }
}

Widget _app(WeeklyReviewLoader loader) =>
    MaterialApp(home: WeeklyReviewScreen(loader: loader));

Future<void> _scrollTo(WidgetTester tester, Finder finder) => tester
    .scrollUntilVisible(finder, 150, scrollable: find.byType(Scrollable).first);

void main() {
  setUp(() {
    workoutDataVersion.value = 0;
  });

  testWidgets('shows the loading state while the loader is pending', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return const DataSuccess([]);
      }),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('empty history shows an encouraging empty state', (tester) async {
    await tester.pumpWidget(_app(() async => const DataSuccess([])));
    await tester.pumpAndSettle();

    expect(find.textContaining('No workouts yet'), findsOneWidget);
    expect(find.textContaining('Week of'), findsOneWidget);
    expect(find.text('Weekly Summary'), findsNothing);
  });

  testWidgets('populated review renders summary, sections and data-quality '
      'note', (tester) async {
    await tester.pumpWidget(_app(() async => DataSuccess(_history())));
    await tester.pumpAndSettle();

    expect(find.textContaining('Week of'), findsOneWidget);
    expect(find.text('Weekly Summary'), findsOneWidget);
    expect(find.textContaining('Based on'), findsOneWidget);
    await _scrollTo(tester, find.text('What may need attention'));
    expect(find.text('What may need attention'), findsOneWidget);
    await _scrollTo(tester, find.textContaining('may be declining'));
    expect(find.textContaining('may be declining'), findsWidgets);
    await _scrollTo(tester, find.text('Suggested next steps'));
    expect(find.text('Suggested next steps'), findsOneWidget);
  });

  testWidgets('failed initial load shows Retry, and retrying recovers', (
    tester,
  ) async {
    final loader = _FakeLoader([
      const DataFailure(DataFailureKind.unavailable),
      DataSuccess(_history()),
    ]);
    await tester.pumpWidget(_app(loader.call));
    await tester.pumpAndSettle();

    expect(find.text('Couldn\'t load your weekly review'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(loader.calls, 2);
    expect(find.text('Weekly Summary'), findsOneWidget);
  });

  testWidgets('failed refresh keeps the last-known review behind a warning '
      'banner', (tester) async {
    final loader = _FakeLoader([
      DataSuccess(_history()),
      const DataFailure(DataFailureKind.unavailable),
    ]);
    await tester.pumpWidget(_app(loader.call));
    await tester.pumpAndSettle();
    expect(find.text('Weekly Summary'), findsOneWidget);

    workoutDataVersion.value++;
    await tester.pumpAndSettle();

    expect(find.text('Couldn\'t refresh your weekly review'), findsOneWidget);
    expect(find.text('Weekly Summary'), findsOneWidget); // last-known kept
  });

  testWidgets('skipped malformed records surface as a visible notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        () async => DataSuccess(
          _history(),
          skipped: const [SkippedDocument('bad-1', 'unparseable')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('couldn\'t be read'), findsWidgets);
  });

  testWidgets('evidence panel expands to show the underlying facts', (
    tester,
  ) async {
    await tester.pumpWidget(_app(() async => DataSuccess(_history())));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.text('Why am I seeing this?'));
    await tester.ensureVisible(find.text('Why am I seeing this?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Why am I seeing this?'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Week analysed'), findsOneWidget);
    expect(find.textContaining('Weekly volume'), findsWidgets);
    expect(find.textContaining('Data quality'), findsOneWidget);
  });

  testWidgets('pull-to-refresh reloads through the loader', (tester) async {
    final loader = _FakeLoader([DataSuccess(_history())]);
    await tester.pumpWidget(_app(loader.call));
    await tester.pumpAndSettle();
    expect(loader.calls, 1);

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(loader.calls, 2);
  });

  testWidgets('reloads when workoutDataVersion changes elsewhere', (
    tester,
  ) async {
    final loader = _FakeLoader([
      const DataSuccess([]),
      DataSuccess(_history()),
    ]);
    await tester.pumpWidget(_app(loader.call));
    await tester.pumpAndSettle();
    expect(find.textContaining('No workouts yet'), findsOneWidget);

    workoutDataVersion.value++;
    await tester.pumpAndSettle();

    expect(loader.calls, 2);
    expect(find.text('Weekly Summary'), findsOneWidget);
  });

  testWidgets('no horizontal overflow at a narrow width', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(() async => DataSuccess(_history())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('2x text scale renders without exceptions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: WeeklyReviewScreen(
            loader: () async => DataSuccess(_history()),
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
        home: WeeklyReviewScreen(loader: () async => DataSuccess(_history())),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
