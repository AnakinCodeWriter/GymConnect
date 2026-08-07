// Personal-record updates must never build Firestore dot-notation field
// paths from raw exercise names: update('personalRecords.B. Press') would
// write a nested field 'B' -> 'Press'. The fix writes the records map via
// set(merge: true), whose keys are literal. These tests pin the payload
// shape; the merge semantics themselves are verified manually against the
// emulator (see docs/TEST_PLAN.md).

import 'package:flutter_test/flutter_test.dart';
import 'package:gymconnect/services/firestore_service.dart';

void main() {
  group('FirestoreService.personalRecordsMergeData', () {
    test('nests all records under a single personalRecords key', () {
      final data = FirestoreService.personalRecordsMergeData({
        'Bench Press': 100.0,
        'Squat': 140.0,
      });
      expect(data.keys.toList(), ['personalRecords']);
      expect(data['personalRecords'], {'Bench Press': 100.0, 'Squat': 140.0});
    });

    test('exercise names with reserved field-path characters are preserved '
        'exactly, without splitting or renaming', () {
      final names = {
        'B. Press': 101.0, // period - would split under dot-notation
        'Cable [Row]': 102.0, // square brackets
        'Star*Press': 103.0, // asterisk
        'Push/Pull': 104.0, // slash
        ' Padded Name ': 105.0, // leading/trailing whitespace
        'Bench Press': 106.0, // ordinary spaces
      };
      final data = FirestoreService.personalRecordsMergeData(names);
      final records = data['personalRecords'] as Map;

      expect(records.keys.toSet(), names.keys.toSet());
      for (final e in names.entries) {
        expect(records[e.key], e.value);
      }
      // Specifically: no nested map was created from the '.' in the name.
      expect(records.containsKey('B'), isFalse);
      expect(records['B. Press'], isNot(isA<Map<dynamic, dynamic>>()));
    });

    test('payload is a copy - mutating the input later does not alter it', () {
      final input = {'Bench Press': 100.0};
      final data = FirestoreService.personalRecordsMergeData(input);
      input['Bench Press'] = 999.0;
      expect((data['personalRecords'] as Map)['Bench Press'], 100.0);
    });
  });
}
