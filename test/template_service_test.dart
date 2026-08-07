import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/models/template_model.dart';
import 'package:gymconnect/services/data_result.dart';
import 'package:gymconnect/services/firestore_service.dart';
import 'package:gymconnect/services/template_service.dart';

import 'fake_firestore_adapter.dart';

void main() {
  late FakeFirestoreAdapter fake;

  setUp(() => fake = FakeFirestoreAdapter());

  group('TemplateService', () {
    late TemplateService service;
    setUp(() => service = TemplateService(adapter: fake));

    test('empty collection is a successful empty result', () async {
      final result = await service.loadTemplates('u1');
      expect(result, isA<DataSuccess<List<TemplateModel>>>());
      expect(result.dataOrNull, isEmpty);
    });

    test('round-trips templates through users/{uid}/templates', () async {
      final template = TemplateModel(
        id: '',
        name: 'Push Day',
        exercises: [
          TemplateExercise(
            name: 'Bench Press',
            sets: [TemplateSet(reps: 5, weight: 60)],
          ),
        ],
      );
      await service.createTemplate('u1', template);
      final loaded = (await service.loadTemplates('u1')).dataOrNull!;
      expect(loaded.single.name, 'Push Day');
      expect(loaded.single.exercises.single.sets.single.weight, 60);
    });

    test('skips malformed template documents with a typed warning', () async {
      fake.docs['users/u1/templates/good'] = {
        'name': 'Push Day',
        'exercises': <Map<String, dynamic>>[],
      };
      fake.docs['users/u1/templates/bad'] = {'exercises': 'nope'};
      final result =
          await service.loadTemplates('u1') as DataSuccess<List<TemplateModel>>;
      expect(result.data.single.id, 'good');
      expect(result.skipped.single.documentId, 'bad');
    });

    test('a failed read maps to a typed failure', () async {
      fake.throwOnNextCall = FirebaseException(
        plugin: 'fake',
        code: 'unavailable',
      );
      final result = await service.loadTemplates('u1');
      expect((result as DataFailure).kind, DataFailureKind.unavailable);
    });

    test('deleteTemplate removes the document', () async {
      fake.docs['users/u1/templates/t1'] = {
        'name': 'X',
        'exercises': <Map<String, dynamic>>[],
      };
      await service.deleteTemplate('u1', 't1');
      expect(fake.docs, isEmpty);
    });
  });

  group('FirestoreService (profile)', () {
    late FirestoreService service;
    setUp(() => service = FirestoreService(adapter: fake));

    test('userProfileExists distinguishes missing from present', () async {
      expect(await service.userProfileExists('u1'), isFalse);
      fake.docs['users/u1'] = {'displayName': 'Alfie', 'gymId': 'g'};
      expect(await service.userProfileExists('u1'), isTrue);
    });

    test('getUserProfile returns null for a missing document (genuinely '
        'no profile), and parses a legacy minimal document', () async {
      expect(await service.getUserProfile('u1'), isNull);
      fake.docs['users/u1'] = {'displayName': 'Alfie', 'gymId': 'g'};
      final profile = await service.getUserProfile('u1');
      expect(profile!.displayName, 'Alfie');
      expect(profile.personalRecords, isEmpty);
      expect(profile.weightUnit, 'kg');
    });

    test('getUserProfile fails (throws) on structurally malformed profiles - '
        'auth-critical documents do not degrade silently', () async {
      fake.docs['users/u1'] = {'displayName': 42, 'gymId': 'g'};
      expect(service.getUserProfile('u1'), throwsA(isA<TypeError>()));
    });

    test(
      'updatePersonalRecords merges without touching other exercises',
      () async {
        fake.docs['users/u1'] = {
          'displayName': 'Alfie',
          'personalRecords': {'Squat': 140.0},
        };
        await service.updatePersonalRecords('u1', {'Bench Press': 116.7});
        expect(fake.docs['users/u1']!['personalRecords'], {
          'Squat': 140.0,
          'Bench Press': 116.7,
        });
        expect(fake.docs['users/u1']!['displayName'], 'Alfie');
      },
    );
  });
}
