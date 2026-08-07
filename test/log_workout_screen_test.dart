// Widget tests for the log workout screen (Phase 11). The screen takes
// injected services backed by the in-memory FakeFirestoreAdapter, so the
// full log -> validate -> feel rating -> save flow runs without Firebase.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/main.dart';
import 'package:gymconnect/screens/log_workout_screen.dart';
import 'package:gymconnect/services/firestore_service.dart';
import 'package:gymconnect/services/leaderboard_service.dart';
import 'package:gymconnect/services/template_service.dart';
import 'package:gymconnect/services/workout_service.dart';
import 'package:gymconnect/utils/units.dart';

import 'fake_firestore_adapter.dart';

const _uid = 'u1';

void main() {
  late FakeFirestoreAdapter fake;

  setUp(() {
    fake = FakeFirestoreAdapter();
    weightUnitNotifier.value = 'kg';
    workoutDataVersion.value = 0;
  });

  LogWorkoutScreen buildScreen({String? Function()? uidProvider}) {
    final workoutService = WorkoutService(
      adapter: fake,
      currentUidProvider: uidProvider ?? () => _uid,
      profileService: FirestoreService(adapter: fake),
      leaderboardService: LeaderboardService(adapter: fake),
    );
    return LogWorkoutScreen(
      workoutService: workoutService,
      templateService: TemplateService(adapter: fake),
      uidProvider: uidProvider ?? () => _uid,
    );
  }

  // Pushes the screen from a host route so Navigator.pop after a save has
  // somewhere to return to (mirrors production, where the dashboard pushes).
  Future<void> pumpScreen(
    WidgetTester tester, {
    String? Function()? uidProvider,
  }) async {
    final screen = buildScreen(uidProvider: uidProvider);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => screen),
                ),
                child: const Text('open log'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open log'));
    await tester.pumpAndSettle();
  }

  void seedBenchHistory({double weight = 60, int reps = 5}) {
    fake.docs['users/$_uid/workouts/w1'] = {
      'date': Timestamp.fromDate(DateTime(2026, 7, 1, 18)),
      'exercises': [
        {
          'name': 'Bench Press',
          'sets': [
            {'weight': 40.0, 'reps': 8, 'isWarmup': true},
            {'weight': weight, 'reps': reps},
          ],
        },
      ],
    };
  }

  Finder exerciseNameField() => find.widgetWithText(TextField, 'Exercise name');

  // Bounded pumps for the post-save flow: while the volume dialog is up the
  // AppBar save spinner is still animating (pre-existing behaviour), so
  // pumpAndSettle would never settle.
  Future<void> pumpThroughAnimations(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('starts with the empty form state', (tester) async {
    await pumpScreen(tester);
    expect(find.textContaining('No exercises yet'), findsOneWidget);
    expect(find.text('Repeat Last Workout'), findsNothing);
    expect(find.text('Load Template'), findsNothing);
  });

  testWidgets('history load failure shows a banner with retry and manual '
      'logging stays available', (tester) async {
    fake.throwOnNextCall = Exception('network');
    await pumpScreen(tester);

    expect(
      find.textContaining('Couldn\'t load workout history'),
      findsOneWidget,
    );
    // manual logging still works
    await tester.tap(find.text('Add Exercise'));
    await tester.pump();
    expect(exerciseNameField(), findsOneWidget);

    // retry succeeds and clears the banner
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Couldn\'t load workout history'), findsNothing);
  });

  testWidgets('missing signed-in user degrades to the history banner '
      'instead of crashing', (tester) async {
    await pumpScreen(tester, uidProvider: () => null);
    expect(
      find.textContaining('Couldn\'t load workout history'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent exercise chip adds a card prefilled from the last '
      'working set', (tester) async {
    seedBenchHistory();
    await pumpScreen(tester);

    expect(find.text('Recent Exercises'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'Bench Press'));
    await tester.pump();

    // prefilled from the last WORKING set (60x5), not the warm-up (40x8)
    expect(find.widgetWithText(TextField, '60'), findsOneWidget);
    expect(find.widgetWithText(TextField, '5'), findsOneWidget);
  });

  testWidgets('tapping the chip again appends a set to the existing card', (
    tester,
  ) async {
    seedBenchHistory();
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'Bench Press'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionChip, 'Bench Press'));
    await tester.pump();

    expect(exerciseNameField(), findsOneWidget); // still one card
    expect(find.widgetWithText(TextField, '60'), findsNWidgets(2));
  });

  testWidgets('add/remove sets: new sets copy the previous values and the '
      'remove button deletes a row', (tester) async {
    seedBenchHistory();
    await pumpScreen(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'Bench Press'));
    await tester.pump();

    await tester.tap(find.text('Add Set'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '60'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Remove set').last);
    await tester.pump();
    expect(find.widgetWithText(TextField, '60'), findsOneWidget);
  });

  testWidgets('warm-up toggle marks a set W and moves when another set is '
      'marked', (tester) async {
    seedBenchHistory();
    await pumpScreen(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'Bench Press'));
    await tester.pump();
    await tester.tap(find.text('Add Set'));
    await tester.pump();

    await tester.tap(find.byTooltip('Tap to mark as warm-up').first);
    await tester.pump();
    expect(find.text('W'), findsOneWidget);
    expect(find.byTooltip('Warm-up (tap to clear)'), findsOneWidget);

    // marking the other set moves the single warm-up flag
    await tester.tap(find.byTooltip('Tap to mark as warm-up').first);
    await tester.pump();
    expect(find.text('W'), findsOneWidget);
  });

  testWidgets('lbs preference converts the prefill and the stored save back '
      'to kg', (tester) async {
    seedBenchHistory(); // last working set 60 kg x 5
    weightUnitNotifier.value = 'lbs';
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'Bench Press'));
    await tester.pump();

    final lbsText = formatWeight(kgToLbs(60)); // '132.3'
    expect(find.widgetWithText(TextField, lbsText), findsOneWidget);
    expect(find.text('lbs'), findsWidgets);

    // save: converted back to kg (within display-rounding tolerance)
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // dismiss feel sheet = skip
    await pumpThroughAnimations(tester);
    await tester.tap(find.text('Done'));
    await pumpThroughAnimations(tester);

    final saved = fake.docs.entries
        .firstWhere((e) => e.key.startsWith('users/$_uid/workouts/auto-'))
        .value;
    final sets =
        ((saved['exercises'] as List).first as Map<String, dynamic>)['sets']
            as List;
    final weightKg = (sets.first as Map<String, dynamic>)['weight'] as double;
    expect(weightKg, closeTo(60, 0.05));
  });

  testWidgets('validation errors are shown for an empty form and invalid '
      'sets', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Add at least one exercise.'), findsOneWidget);

    await tester.tap(find.text('Add Exercise'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Every exercise needs a name.'), findsOneWidget);

    await tester.enterText(exerciseNameField(), 'Squat');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Every exercise needs at least one set.'), findsOneWidget);

    await tester.tap(find.text('Add Set'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(
      find.text('Enter valid weight and reps for all sets.'),
      findsOneWidget,
    );
  });

  testWidgets('save success stores the workout with the feel rating, bumps '
      'workoutDataVersion and pops back', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Add Exercise'));
    await tester.pump();
    await tester.enterText(exerciseNameField(), 'Squat');
    await tester.tap(find.text('Add Set'));
    await tester.pump();
    final steppers = find.byType(TextField);
    // fields: session name, exercise name, weight, reps
    await tester.enterText(steppers.at(2), '100');
    await tester.enterText(steppers.at(3), '5');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // feel rating sheet appears while interactive; rate 4 of 5
    expect(find.text('How did that feel?'), findsOneWidget);
    await tester.tap(find.byTooltip('Rate 4 of 5'));
    await pumpThroughAnimations(tester);

    // volume dialog: 100 kg x 5 reps = 500 kg
    expect(find.text('Session Complete!'), findsOneWidget);
    expect(find.text('500 kg'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await pumpThroughAnimations(tester);

    // popped back to the host route
    expect(find.text('open log'), findsOneWidget);
    expect(workoutDataVersion.value, 1);

    final saved = fake.docs.entries
        .firstWhere((e) => e.key.startsWith('users/$_uid/workouts/auto-'))
        .value;
    expect(saved['feelRating'], 4);
    final exercise = (saved['exercises'] as List).first as Map<String, dynamic>;
    expect(exercise['name'], 'Squat');
  });

  testWidgets('save failure shows a visible error and stays on the screen', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Add Exercise'));
    await tester.pump();
    await tester.enterText(exerciseNameField(), 'Squat');
    await tester.tap(find.text('Add Set'));
    await tester.pump();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(2), '100');
    await tester.enterText(fields.at(3), '5');

    fake.throwOnNextCall = Exception('offline');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // skip feel rating
    await tester.pumpAndSettle();

    expect(
      find.text('Failed to save workout. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Log Workout'), findsOneWidget); // still here
    expect(workoutDataVersion.value, 0);
  });

  testWidgets('template loads with sets prefilled from the last actual '
      'performance', (tester) async {
    seedBenchHistory(weight: 62.5);
    fake.docs['users/$_uid/templates/t1'] = {
      'name': 'Push Day',
      'exercises': [
        {
          'name': 'Bench Press',
          'sets': [
            {'reps': 8},
            {'reps': 8},
          ],
        },
      ],
    };
    await pumpScreen(tester);

    await tester.tap(find.text('Load Template'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push Day'));
    await tester.pumpAndSettle();

    // history exists: one working set 62.5x5 wins over the two template
    // placeholder sets
    expect(find.widgetWithText(TextField, '62.5'), findsOneWidget);
    expect(find.widgetWithText(TextField, '8'), findsNothing);
  });

  testWidgets('repeat last workout restores its exercises and asks before '
      'replacing entered work', (tester) async {
    seedBenchHistory();
    await pumpScreen(tester);

    await tester.tap(find.text('Repeat Last Workout'));
    await tester.pumpAndSettle();
    // warm-up flag survives the repeat (2 sets: W + set 1)
    expect(find.text('W'), findsOneWidget);
    expect(find.widgetWithText(TextField, '60'), findsOneWidget);

    // repeating again over entered work asks for confirmation
    await tester.tap(find.text('Repeat Last Workout'));
    await tester.pumpAndSettle();
    expect(find.text('Replace current workout?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('overload hint suggests +2.5 kg after a solid session', (
    tester,
  ) async {
    seedBenchHistory(weight: 80, reps: 5);
    await pumpScreen(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'Bench Press'));
    await tester.pump();

    expect(
      find.text('Last: 80kg × 5 reps - solid session, try 82.5kg today'),
      findsOneWidget,
    );
  });

  testWidgets('no horizontal overflow at a narrow width', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    seedBenchHistory();
    await pumpScreen(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'Bench Press'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('2x text scale renders without exceptions', (tester) async {
    seedBenchHistory();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: buildScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark mode renders without exceptions', (tester) async {
    seedBenchHistory();
    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
        ),
        home: buildScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
