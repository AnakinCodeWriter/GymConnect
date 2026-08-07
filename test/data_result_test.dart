import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/services/data_result.dart';

void main() {
  group('DataResult', () {
    test('success with data exposes it', () {
      const r = DataSuccess<List<int>>([1, 2]);
      expect(r.isSuccess, isTrue);
      expect(r.dataOrNull, [1, 2]);
      expect(r.skipped, isEmpty);
    });

    test('success with an empty list is still success, not failure', () {
      const r = DataSuccess<List<int>>([]);
      expect(r.isSuccess, isTrue);
      expect(r.dataOrNull, isEmpty);
    });

    test('failure carries a typed kind and never data', () {
      const r = DataFailure<List<int>>(DataFailureKind.permissionDenied);
      expect(r.isSuccess, isFalse);
      expect(r.dataOrNull, isNull);
      expect(r.kind, DataFailureKind.permissionDenied);
    });

    test('skipped documents are typed, not strings to parse', () {
      final r = DataSuccess<List<int>>(
        const [1],
        skipped: [const SkippedDocument('doc-1', FormatException('bad'))],
      );
      expect(r.skipped.single.documentId, 'doc-1');
    });
  });

  group('failureKindFor', () {
    FirebaseException fb(String code) =>
        FirebaseException(plugin: 'test', code: code);

    test('maps Firebase error codes to stable categories', () {
      expect(
        failureKindFor(fb('permission-denied')),
        DataFailureKind.permissionDenied,
      );
      expect(
        failureKindFor(fb('unauthenticated')),
        DataFailureKind.unauthenticated,
      );
      expect(failureKindFor(fb('unavailable')), DataFailureKind.unavailable);
      expect(
        failureKindFor(fb('network-request-failed')),
        DataFailureKind.unavailable,
      );
      expect(failureKindFor(fb('deadline-exceeded')), DataFailureKind.timeout);
      expect(failureKindFor(fb('not-found')), DataFailureKind.notFound);
      expect(
        failureKindFor(fb('invalid-argument')),
        DataFailureKind.invalidData,
      );
    });

    test('unrecognised Firebase codes fall back to unknown', () {
      expect(failureKindFor(fb('some-new-code')), DataFailureKind.unknown);
    });

    test('parse errors map to invalidData', () {
      expect(
        failureKindFor(const FormatException('bad')),
        DataFailureKind.invalidData,
      );
      Object? typeError;
      try {
        // ignore: unnecessary_cast
        (('a' as dynamic) as int).isEven;
      } catch (e) {
        typeError = e;
      }
      expect(failureKindFor(typeError!), DataFailureKind.invalidData);
    });

    test('arbitrary errors fall back to unknown', () {
      expect(failureKindFor(StateError('boom')), DataFailureKind.unknown);
    });
  });
}
