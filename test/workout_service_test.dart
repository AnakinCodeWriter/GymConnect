import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/services/data_result.dart';
import 'package:gymconnect/services/firestore_service.dart';
import 'package:gymconnect/services/leaderboard_service.dart';
import 'package:gymconnect/services/workout_service.dart';
import 'package:gymconnect/utils/fitness_formulas.dart';

import 'fake_firestore_adapter.dart';

void main() {
  late FakeFirestoreAdapter fake;
  late WorkoutService service;

  const uid = 'u1';

  WorkoutService buildService({String? currentUid = uid}) => WorkoutService(
    adapter: fake,
    currentUidProvider: () => currentUid,
    profileService: FirestoreService(adapter: fake),
    leaderboardService: LeaderboardService(adapter: fake),
  );

  setUp(() {
    fake = FakeFirestoreAdapter();
    service = buildService();
  });

  Map<String, dynamic> workoutDoc(
    DateTime date, {
    double weight = 60,
    int reps = 5,
  }) => {
    'date': Timestamp.fromDate(date),
    'exercises': [
      {
        'name': 'Bench Press',
        'sets': [
          {'weight': weight, 'reps': reps},
        ],
      },
    ],
  };

  group('loadWorkouts', () {
    test('empty history is a successful empty result', () async {
      final result = await service.loadWorkouts();
      expect(result, isA<DataSuccess<List<WorkoutModel>>>());
      expect(result.dataOrNull, isEmpty);
    });

    test('reads from users/{uid}/workouts', () async {
      fake.docs['users/u1/workouts/w1'] = workoutDoc(DateTime(2026, 6, 1));
      fake.docs['users/other/workouts/w9'] = workoutDoc(DateTime(2026, 6, 2));
      final result = await service.loadWorkouts();
      expect(result.dataOrNull, hasLength(1));
      expect(result.dataOrNull!.single.id, 'w1');
    });

    test('orders newest first with deterministic id tie-breaking', () async {
      final sameDay = DateTime(2026, 6, 5, 10);
      fake.docs['users/u1/workouts/b'] = workoutDoc(sameDay);
      fake.docs['users/u1/workouts/a'] = workoutDoc(sameDay);
      fake.docs['users/u1/workouts/old'] = workoutDoc(DateTime(2026, 6, 1));
      fake.docs['users/u1/workouts/new'] = workoutDoc(DateTime(2026, 6, 9));

      final ids = (await service.loadWorkouts()).dataOrNull!
          .map((w) => w.id)
          .toList();
      expect(ids, ['new', 'a', 'b', 'old']);
    });

    test('parses documents missing optional fields (legacy format)', () async {
      // no name, no feelRating, no isWarmup - the original document shape
      fake.docs['users/u1/workouts/w1'] = workoutDoc(DateTime(2026, 6, 1));
      final w = (await service.loadWorkouts()).dataOrNull!.single;
      expect(w.name, '');
      expect(w.feelRating, isNull);
      expect(w.exercises.single.sets.single.isWarmup, isFalse);
    });

    test('coerces int weights and double reps (tolerant numerics)', () async {
      fake.docs['users/u1/workouts/w1'] = {
        'date': Timestamp.fromDate(DateTime(2026, 6, 1)),
        'exercises': [
          {
            'name': 'Bench Press',
            'sets': [
              {'weight': 60, 'reps': 5.0}, // int weight, double reps
            ],
          },
        ],
      };
      final set = (await service.loadWorkouts())
          .dataOrNull!
          .single
          .exercises
          .single
          .sets
          .single;
      expect(set.weight, 60.0);
      expect(set.reps, 5);
    });

    test(
      'skips malformed documents with a typed warning, keeps valid ones',
      () async {
        fake.docs['users/u1/workouts/good'] = workoutDoc(DateTime(2026, 6, 1));
        fake.docs['users/u1/workouts/bad'] = {
          'date': Timestamp.fromDate(DateTime(2026, 6, 2)),
          'exercises': [
            {
              'name': 'Bench Press',
              'sets': [
                {'weight': 'heavy', 'reps': 5}, // unusable weight
              ],
            },
          ],
        };
        final result =
            await service.loadWorkouts() as DataSuccess<List<WorkoutModel>>;
        expect(result.data.single.id, 'good');
        expect(result.skipped.single.documentId, 'bad');
      },
    );

    test('no signed-in user is a typed unauthenticated failure', () async {
      final result = await buildService(currentUid: null).loadWorkouts();
      expect(result, isA<DataFailure<List<WorkoutModel>>>());
      expect((result as DataFailure).kind, DataFailureKind.unauthenticated);
    });

    test('a failed read maps the Firebase code to a typed failure', () async {
      fake.throwOnNextCall = FirebaseException(
        plugin: 'fake',
        code: 'unavailable',
      );
      final result = await service.loadWorkouts();
      expect((result as DataFailure).kind, DataFailureKind.unavailable);
    });
  });

  group('saveWorkoutAndUpdateRecords', () {
    WorkoutModel workout({double weight = 100, int reps = 5}) => WorkoutModel(
      id: '',
      date: Timestamp.fromDate(DateTime(2026, 6, 10, 9)),
      exercises: [
        ExerciseEntry(
          name: 'Bench Press',
          sets: [WorkoutSet(weight: weight, reps: reps)],
        ),
      ],
    );

    test('writes the exact document format to users/{uid}/workouts', () async {
      final w = workout();
      await service.saveWorkoutAndUpdateRecords(w);
      final stored = fake.docs.entries.singleWhere(
        (e) => e.key.startsWith('users/u1/workouts/'),
      );
      expect(stored.value, w.toMap());
      // optional fields stay absent when unset (format preserved)
      expect(stored.value.containsKey('name'), isFalse);
      expect(stored.value.containsKey('feelRating'), isFalse);
    });

    test('reports and stores a new personal record when improved', () async {
      fake.docs['users/u1'] = {
        'displayName': 'Alfie',
        'gymId': '',
        'personalRecords': {'Bench Press': 100.0},
      };
      final result = await service.saveWorkoutAndUpdateRecords(workout());
      expect(result.dataOrNull!.newPersonalRecords, ['Bench Press']);
      expect(
        fake.docs['users/u1']!['personalRecords']['Bench Press'],
        closeTo(estimatedOneRepMax(100, 5), 1e-9),
      );
    });

    test('does not lower an existing higher record', () async {
      fake.docs['users/u1'] = {
        'displayName': 'Alfie',
        'gymId': '',
        'personalRecords': {'Bench Press': 500.0},
      };
      final result = await service.saveWorkoutAndUpdateRecords(workout());
      expect(result.dataOrNull!.newPersonalRecords, isEmpty);
      expect(fake.docs['users/u1']!['personalRecords']['Bench Press'], 500.0);
    });

    test('updates the gym leaderboard when the profile has a gym', () async {
      fake.docs['users/u1'] = {
        'displayName': 'Alfie',
        'gymId': 'gym-1',
        'isAnonymous': false,
      };
      await service.saveWorkoutAndUpdateRecords(workout());
      // leaderboard write is intentionally unawaited - pump the microtask
      // queue so the fake receives it.
      await Future<void>.delayed(Duration.zero);
      final entry = fake.docs['gyms/gym-1/leaderboard/u1'];
      expect(entry, isNotNull);
      expect(entry!['displayName'], 'Alfie');
      expect(
        entry['bestLifts']['Bench Press'],
        closeTo(estimatedOneRepMax(100, 5), 1e-9),
      );
    });

    test(
      'a failed workout write is a typed failure and nothing is stored',
      () async {
        fake.throwOnNextCall = FirebaseException(
          plugin: 'fake',
          code: 'permission-denied',
        );
        final result = await service.saveWorkoutAndUpdateRecords(workout());
        expect((result as DataFailure).kind, DataFailureKind.permissionDenied);
        expect(fake.docs, isEmpty);
      },
    );

    test('a PR/profile failure never blocks a successful save', () async {
      // A malformed profile document makes the PR step throw internally;
      // the save must still succeed with no PRs reported.
      fake.docs['users/u1'] = {'displayName': 42};
      final result = await service.saveWorkoutAndUpdateRecords(workout());
      expect(result, isA<DataSuccess<WorkoutSaveOutcome>>());
      expect(result.dataOrNull!.newPersonalRecords, isEmpty);
      // the workout itself was stored despite the profile failure
      expect(
        fake.docs.keys.where((k) => k.startsWith('users/u1/workouts/')),
        hasLength(1),
      );
    });

    test('unauthenticated save is a typed failure', () async {
      final result = await buildService(
        currentUid: null,
      ).saveWorkoutAndUpdateRecords(workout());
      expect((result as DataFailure).kind, DataFailureKind.unauthenticated);
    });
  });

  group('deleteSetAndRecalculateRecord', () {
    setUp(() {
      fake.docs['users/u1'] = {
        'displayName': 'Alfie',
        'gymId': '',
        'personalRecords': {'Bench Press': 999.0},
      };
      fake.docs['users/u1/workouts/w1'] = {
        'date': Timestamp.fromDate(DateTime(2026, 6, 1)),
        'exercises': [
          {
            'name': 'Bench Press',
            'sets': [
              {'weight': 100.0, 'reps': 5},
              {'weight': 60.0, 'reps': 5},
            ],
          },
        ],
      };
    });

    test(
      'removes one set and recalculates the PR from remaining history',
      () async {
        final result = await service.deleteSetAndRecalculateRecord(
          workoutId: 'w1',
          exerciseName: 'Bench Press',
          setIndex: 0, // remove the 100 kg set
        );
        final workouts = result.dataOrNull!;
        expect(workouts.single.exercises.single.sets, hasLength(1));
        expect(workouts.single.exercises.single.sets.single.weight, 60.0);
        // PR recalculated from what remains (not the stale stored 999)
        expect(
          fake.docs['users/u1']!['personalRecords']['Bench Press'],
          closeTo(estimatedOneRepMax(60, 5), 1e-9),
        );
      },
    );

    test('deleting the last set removes the whole workout document', () async {
      fake.docs['users/u1/workouts/w1'] = {
        'date': Timestamp.fromDate(DateTime(2026, 6, 1)),
        'exercises': [
          {
            'name': 'Bench Press',
            'sets': [
              {'weight': 100.0, 'reps': 5},
            ],
          },
        ],
      };
      final result = await service.deleteSetAndRecalculateRecord(
        workoutId: 'w1',
        exerciseName: 'Bench Press',
        setIndex: 0,
      );
      expect(result.dataOrNull, isEmpty);
      expect(fake.docs.containsKey('users/u1/workouts/w1'), isFalse);
      // PR recalculated to zero - no history remains
      expect(fake.docs['users/u1']!['personalRecords']['Bench Press'], 0);
    });

    test('a failed delete maps to a typed failure', () async {
      fake.throwOnNextCall = FirebaseException(
        plugin: 'fake',
        code: 'unavailable',
      );
      final result = await service.deleteSetAndRecalculateRecord(
        workoutId: 'w1',
        exerciseName: 'Bench Press',
        setIndex: 0,
      );
      expect((result as DataFailure).kind, DataFailureKind.unavailable);
    });

    test('unauthenticated delete is a typed failure', () async {
      final result = await buildService(currentUid: null)
          .deleteSetAndRecalculateRecord(
            workoutId: 'w1',
            exerciseName: 'Bench Press',
            setIndex: 0,
          );
      expect((result as DataFailure).kind, DataFailureKind.unauthenticated);
    });
  });
}
