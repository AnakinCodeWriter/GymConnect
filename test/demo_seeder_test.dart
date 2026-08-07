import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/demo/demo_fixtures.dart';
import 'package:gymconnect/demo/demo_plan.dart';
import 'package:gymconnect/demo/demo_seeder.dart';
import 'package:gymconnect/models/workout_model.dart';

import 'fake_firestore_adapter.dart';

final ref = DateTime(2026, 7, 3, 18);
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
  late DemoSeeder seeder;

  setUp(() {
    fake = FakeFirestoreAdapter();
    seeder = DemoSeeder(adapter: fake, uid: uid);
  });

  Iterable<MapEntry<String, Map<String, dynamic>>> workoutDocs() => fake
      .docs
      .entries
      .where((e) => e.key.startsWith('users/$uid/workouts/'))
      .map((e) => MapEntry(e.key.split('/').last, e.value));

  group('selectDemoDocuments', () {
    test('selects only strictly-tagged demo documents', () {
      final selection = selectDemoDocuments([
        ('demo-1', {demoFieldIsDemo: true, demoFieldBatchId: 'a'}),
        ('normal-1', _normalWorkoutMap()),
        ('weird-1', {demoFieldIsDemo: 'yes'}), // truthy string is NOT demo
        ('weird-2', {demoFieldIsDemo: false}),
      ]);
      expect(selection.selectedIds, ['demo-1']);
      expect(selection.normalDocuments, 3);
      expect(selection.otherDemoDocuments, 0);
    });

    test('batch filter keeps other demo batches', () {
      final selection = selectDemoDocuments([
        ('a-1', {demoFieldIsDemo: true, demoFieldBatchId: 'a'}),
        ('b-1', {demoFieldIsDemo: true, demoFieldBatchId: 'b'}),
        ('n-1', _normalWorkoutMap()),
      ], batchId: 'a');
      expect(selection.selectedIds, ['a-1']);
      expect(selection.otherDemoDocuments, 1);
      expect(selection.normalDocuments, 1);
    });

    test('a demo document with a missing batch tag is only selected by an '
        'all-batches cleanup', () {
      final docs = [
        ('orphan', <String, dynamic>{demoFieldIsDemo: true}),
      ];
      expect(selectDemoDocuments(docs, batchId: 'a').selectedIds, isEmpty);
      expect(selectDemoDocuments(docs).selectedIds, ['orphan']);
    });
  });

  group('seeding', () {
    test('writes tagged, parseable documents at deterministic ids', () async {
      final result = await seeder.seedScenario(
        DemoScenario.insufficientData,
        referenceDate: ref,
      );
      expect(result.written, 2);
      expect(result.replacedExisting, 0);

      final docs = workoutDocs().toList();
      expect(docs.length, 2);
      for (final doc in docs) {
        expect(doc.key, startsWith('demo-insufficient-data-'));
        expect(isDemoDocument(doc.value), isTrue);
        expect(doc.value[demoFieldScenario], 'insufficient-data');
        expect(doc.value[demoFieldBatchId], 'insufficient-data');
        expect(doc.value[demoFieldGeneratedAt], isA<String>());
        // stored payload parses exactly like a normal workout document
        final model = WorkoutModel.fromMap(doc.key, doc.value);
        expect(model.exercises, isNotEmpty);
      }
    });

    test(
      'is idempotent: seeding the same batch twice never duplicates',
      () async {
        await seeder.seedScenario(DemoScenario.progressing, referenceDate: ref);
        final countAfterFirst = workoutDocs().length;

        final second = await seeder.seedScenario(
          DemoScenario.progressing,
          referenceDate: ref,
        );
        expect(workoutDocs().length, countAfterFirst);
        expect(second.replacedExisting, countAfterFirst);
        expect(second.written, countAfterFirst);
      },
    );

    test('never touches normal workouts or other demo batches', () async {
      fake.docs['users/$uid/workouts/real-1'] = _normalWorkoutMap();
      await seeder.seedScenario(DemoScenario.plateau, referenceDate: ref);
      await seeder.seedScenario(
        DemoScenario.insufficientData,
        referenceDate: ref,
      );

      // reseed one batch - the normal doc and the other batch survive
      await seeder.seedScenario(DemoScenario.plateau, referenceDate: ref);
      expect(fake.docs.containsKey('users/$uid/workouts/real-1'), isTrue);
      expect(
        workoutDocs().where(
          (d) => d.value[demoFieldBatchId] == 'insufficient-data',
        ),
        hasLength(2),
      );
    });
  });

  group('cleanup', () {
    test('removes one batch, keeps others and all normal workouts', () async {
      fake.docs['users/$uid/workouts/real-1'] = _normalWorkoutMap();
      await seeder.seedScenario(DemoScenario.plateau, referenceDate: ref);
      await seeder.seedScenario(
        DemoScenario.insufficientData,
        referenceDate: ref,
      );

      final result = await seeder.cleanup(batchId: 'plateau');
      expect(result.deleted, 14);
      expect(result.otherDemoDocuments, 2);
      expect(result.normalDocumentsIgnored, 1);
      expect(result.dryRun, isFalse);

      expect(fake.docs.containsKey('users/$uid/workouts/real-1'), isTrue);
      expect(
        workoutDocs().any((d) => d.value[demoFieldBatchId] == 'plateau'),
        isFalse,
      );
      expect(workoutDocs().where((d) => isDemoDocument(d.value)), hasLength(2));
    });

    test(
      'cleanup with no batch removes ALL demo data but nothing else',
      () async {
        fake.docs['users/$uid/workouts/real-1'] = _normalWorkoutMap();
        fake.docs['users/$uid/workouts/real-2'] = _normalWorkoutMap();
        await seeder.seedScenario(DemoScenario.regression, referenceDate: ref);
        await seeder.seedScenario(
          DemoScenario.volumeProgressing,
          referenceDate: ref,
        );

        final result = await seeder.cleanup();
        expect(result.deleted, 28);
        expect(result.normalDocumentsIgnored, 2);
        expect(workoutDocs().where((d) => isDemoDocument(d.value)), isEmpty);
        expect(workoutDocs(), hasLength(2)); // the normal docs
      },
    );

    test('dry run reports the selection without mutating anything', () async {
      fake.docs['users/$uid/workouts/real-1'] = _normalWorkoutMap();
      await seeder.seedScenario(DemoScenario.plateau, referenceDate: ref);
      final before = Map.of(fake.docs);

      final result = await seeder.cleanup(dryRun: true);
      expect(result.dryRun, isTrue);
      expect(result.deleted, 14);
      expect(result.normalDocumentsIgnored, 1);
      expect(fake.docs.keys.toSet(), before.keys.toSet());
    });

    test(
      'documents without demo tags are never deleted, even by --all',
      () async {
        fake.docs['users/$uid/workouts/real-1'] = _normalWorkoutMap();
        fake.docs['users/$uid/workouts/odd-1'] = {
          ..._normalWorkoutMap(),
          demoFieldIsDemo: 'true', // string, not bool - not demo data
        };
        final result = await seeder.cleanup();
        expect(result.deleted, 0);
        expect(result.normalDocumentsIgnored, 2);
        expect(fake.docs.length, 2);
      },
    );
  });
}
