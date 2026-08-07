import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/models/workout_model.dart';
import 'package:gymconnect/services/data_result.dart';
import 'package:gymconnect/services/leaderboard_service.dart';
import 'package:gymconnect/utils/fitness_formulas.dart';

import 'fake_firestore_adapter.dart';

void main() {
  late FakeFirestoreAdapter fake;
  late LeaderboardService service;

  setUp(() {
    fake = FakeFirestoreAdapter();
    service = LeaderboardService(adapter: fake);
  });

  WorkoutModel workout(double weight, int reps) => WorkoutModel(
    id: 'w',
    date: Timestamp.fromDate(DateTime(2026, 6, 1)),
    exercises: [
      ExerciseEntry(
        name: 'Bench Press',
        sets: [WorkoutSet(weight: weight, reps: reps)],
      ),
    ],
  );

  group('loadLeaderboard', () {
    test('empty gym is a successful empty result', () async {
      final result = await service.loadLeaderboard('gym-1');
      expect(result, isA<DataSuccess<List<LeaderboardEntry>>>());
      expect(result.dataOrNull, isEmpty);
    });

    test(
      'parses entries and skips malformed ones with a typed warning',
      () async {
        fake.docs['gyms/gym-1/leaderboard/u1'] = {
          'displayName': 'Alfie',
          'isAnonymous': false,
          'bestLifts': {'Bench Press': 116.7},
        };
        fake.docs['gyms/gym-1/leaderboard/u2'] = {
          'displayName': 'Bob',
          'bestLifts': {'Bench Press': 'strong'}, // malformed value
        };
        // legacy entry without bestLifts parses as an empty map
        fake.docs['gyms/gym-1/leaderboard/u3'] = {'displayName': 'Cara'};

        final result =
            await service.loadLeaderboard('gym-1')
                as DataSuccess<List<LeaderboardEntry>>;
        expect(result.data.map((e) => e.uid).toSet(), {'u1', 'u3'});
        expect(result.skipped.single.documentId, 'u2');
      },
    );

    test('a failed read maps to a typed failure', () async {
      fake.throwOnNextCall = FirebaseException(
        plugin: 'fake',
        code: 'permission-denied',
      );
      final result = await service.loadLeaderboard('gym-1');
      expect((result as DataFailure).kind, DataFailureKind.permissionDenied);
    });
  });

  group('setAnonymous', () {
    test('no longer throws when the user has no leaderboard entry yet '
        '(Phase 4 fix: set-merge instead of update)', () async {
      await service.setAnonymous('u1', 'gym-1', true, displayName: 'Alfie');
      expect(fake.docs['gyms/gym-1/leaderboard/u1'], {
        'isAnonymous': true,
        'displayName': LeaderboardService.anonymousDisplayName,
      });
    });

    test('turning anonymity ON sanitises the readable display value and '
        'preserves lifts via merge (Phase 10)', () async {
      fake.docs['gyms/gym-1/leaderboard/u1'] = {
        'displayName': 'Alfie',
        'isAnonymous': false,
        'bestLifts': {'Bench Press': 116.7},
      };
      await service.setAnonymous('u1', 'gym-1', true, displayName: 'Alfie');
      final doc = fake.docs['gyms/gym-1/leaderboard/u1']!;
      expect(doc['isAnonymous'], isTrue);
      expect(doc['displayName'], LeaderboardService.anonymousDisplayName);
      expect(doc['bestLifts'], {'Bench Press': 116.7});
    });

    test('turning anonymity OFF restores the profile display name '
        '(Phase 10)', () async {
      fake.docs['gyms/gym-1/leaderboard/u1'] = {
        'displayName': LeaderboardService.anonymousDisplayName,
        'isAnonymous': true,
        'bestLifts': {'Bench Press': 116.7},
      };
      await service.setAnonymous('u1', 'gym-1', false, displayName: 'Alfie');
      final doc = fake.docs['gyms/gym-1/leaderboard/u1']!;
      expect(doc['isAnonymous'], isFalse);
      expect(doc['displayName'], 'Alfie');
      expect(doc['bestLifts'], {'Bench Press': 116.7});
    });
  });

  group('updateUserBestLifts', () {
    test('creates an entry with the best eligible e1RM', () async {
      await service.updateUserBestLifts(
        'u1',
        'gym-1',
        'Alfie',
        false,
        workout(100, 5),
      );
      final doc = fake.docs['gyms/gym-1/leaderboard/u1']!;
      expect(
        doc['bestLifts']['Bench Press'],
        closeTo(estimatedOneRepMax(100, 5), 1e-9),
      );
    });

    test('only improves stored values, never lowers them', () async {
      fake.docs['gyms/gym-1/leaderboard/u1'] = {
        'displayName': 'Old Name',
        'isAnonymous': false,
        'bestLifts': {'Bench Press': 500.0},
      };
      await service.updateUserBestLifts(
        'u1',
        'gym-1',
        'New Name',
        false,
        workout(100, 5),
      );
      final doc = fake.docs['gyms/gym-1/leaderboard/u1']!;
      // lift unchanged, but identity fields refreshed
      expect(doc['bestLifts']['Bench Press'], 500.0);
      expect(doc['displayName'], 'New Name');
      expect(doc['isAnonymous'], isFalse);
    });

    test('an anonymous save stores the safe display value, never the real '
        'name (Phase 10)', () async {
      await service.updateUserBestLifts(
        'u1',
        'gym-1',
        'Alfie',
        true,
        workout(100, 5),
      );
      final doc = fake.docs['gyms/gym-1/leaderboard/u1']!;
      expect(doc['displayName'], LeaderboardService.anonymousDisplayName);
      expect(doc['isAnonymous'], isTrue);
      expect(doc.toString().contains('Alfie'), isFalse);
    });

    test('a non-anonymous save stores the real display name', () async {
      await service.updateUserBestLifts(
        'u1',
        'gym-1',
        'Alfie',
        false,
        workout(100, 5),
      );
      expect(fake.docs['gyms/gym-1/leaderboard/u1']!['displayName'], 'Alfie');
    });

    test('a workout with no eligible sets writes nothing', () async {
      final warmupOnly = WorkoutModel(
        id: 'w',
        date: Timestamp.fromDate(DateTime(2026, 6, 1)),
        exercises: [
          ExerciseEntry(
            name: 'Bench Press',
            sets: [WorkoutSet(weight: 40, reps: 10, isWarmup: true)],
          ),
        ],
      );
      await service.updateUserBestLifts(
        'u1',
        'gym-1',
        'Alfie',
        false,
        warmupOnly,
      );
      expect(fake.docs, isEmpty);
    });
  });

  group('updateDisplayName', () {
    test('no-ops when the entry does not exist', () async {
      await service.updateDisplayName('u1', 'gym-1', 'Alfie');
      expect(fake.docs, isEmpty);
    });

    test('updates the name on an existing entry', () async {
      fake.docs['gyms/gym-1/leaderboard/u1'] = {'displayName': 'Old'};
      await service.updateDisplayName('u1', 'gym-1', 'New');
      expect(fake.docs['gyms/gym-1/leaderboard/u1']!['displayName'], 'New');
    });

    test('a profile rename cannot leak a real name onto an anonymous entry '
        '(Phase 10)', () async {
      fake.docs['gyms/gym-1/leaderboard/u1'] = {
        'displayName': LeaderboardService.anonymousDisplayName,
        'isAnonymous': true,
      };
      await service.updateDisplayName('u1', 'gym-1', 'Real Name');
      expect(
        fake.docs['gyms/gym-1/leaderboard/u1']!['displayName'],
        LeaderboardService.anonymousDisplayName,
      );
    });
  });
}
