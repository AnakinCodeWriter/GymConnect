import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/demo/demo_fixtures.dart';
import 'package:gymconnect/demo/demo_plan.dart';
import 'package:gymconnect/demo/demo_seeder.dart';
import 'package:gymconnect/main.dart';
import 'package:gymconnect/screens/demo_tools_screen.dart';

import 'fake_firestore_adapter.dart';

const uid = 'u1';

Map<String, dynamic> _normalWorkoutMap() => {
  'date': Timestamp.fromDate(DateTime(2026, 6, 20, 9)),
  'exercises': [
    {
      'name': 'Bench Press',
      'sets': [
        {'weight': 60.0, 'reps': 5},
      ],
    },
  ],
};

void main() {
  late FakeFirestoreAdapter fake;

  setUp(() {
    fake = FakeFirestoreAdapter();
    workoutDataVersion.value = 0;
  });

  Widget app() => MaterialApp(
    home: DemoToolsScreen(
      seeder: DemoSeeder(adapter: fake, uid: uid),
      userLabel: 'demo-user',
      projectLabel: 'demo-project',
    ),
  );

  int demoDocCount() => fake.docs.keys
      .where((k) => k.startsWith('users/$uid/workouts/demo-'))
      .length;

  testWidgets('shows the warning, target context, every scenario and the '
      'cleanup action', (tester) async {
    await tester.pumpWidget(app());

    expect(find.text('Development tool'), findsOneWidget);
    expect(
      find.textContaining('Project: demo-project · User: demo-user'),
      findsOneWidget,
    );
    expect(find.text('Progressing'), findsOneWidget);
    for (final title in ['Plateau', 'Regression', 'Insufficient data']) {
      await tester.scrollUntilVisible(find.text(title), 150);
      expect(find.text(title), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('Remove all demo data'), 150);
    expect(find.text('Remove all demo data'), findsOneWidget);
  });

  testWidgets('seeding requires confirmation - Cancel changes nothing', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Seed').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Seed "Progressing"?'), findsOneWidget);
    expect(find.textContaining('Project: demo-project'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(demoDocCount(), 0);
    expect(workoutDataVersion.value, 0);
  });

  testWidgets('confirming a seed writes tagged documents and bumps the data '
      'version', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Seed').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(demoDocCount(), 24); // progressing scenario
    expect(workoutDataVersion.value, 1);
    expect(find.textContaining('Seeded 24 demo workouts'), findsOneWidget);
    // every written document is tagged
    for (final doc in fake.docs.values) {
      expect(isDemoDocument(doc), isTrue);
    }
  });

  testWidgets('cleanup deletes only tagged demo data and never normal '
      'workouts', (tester) async {
    fake.docs['users/$uid/workouts/real-1'] = _normalWorkoutMap();
    // pre-existing demo batch to remove
    await DemoSeeder(adapter: fake, uid: uid).seedScenario(
      DemoScenario.insufficientData,
      referenceDate: DateTime(2026, 7, 3),
    );

    await tester.pumpWidget(app());
    await tester.scrollUntilVisible(find.text('Remove all demo data'), 150);
    await tester.tap(find.text('Remove all demo data'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Remove ALL demo data?'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(demoDocCount(), 0);
    expect(fake.docs.containsKey('users/$uid/workouts/real-1'), isTrue);
    expect(workoutDataVersion.value, 1);
    expect(find.textContaining('1 normal workouts untouched'), findsOneWidget);
  });
}
