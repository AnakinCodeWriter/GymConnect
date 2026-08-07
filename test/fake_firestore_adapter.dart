// Handwritten in-memory FirestoreAdapter fake (Phase 4).
//
// Approximations, documented in docs/TEST_PLAN.md: set(merge) performs a
// recursive map merge and update() merges top-level keys - close enough for
// service-logic tests, but real Firestore merge/offline/security semantics
// remain emulator-verified (Phase 10). getCollection with orderBy mimics
// Firestore by OMITTING documents that lack the order field.

import 'package:firebase_core/firebase_core.dart';
import 'package:gymconnect/services/firestore_adapter.dart';

class FakeFirestoreAdapter implements FirestoreAdapter {
  /// Full document path ('users/u1/workouts/w1') -> document data.
  final Map<String, Map<String, dynamic>> docs = {};

  /// When set, the next adapter call throws this and clears the field.
  Object? throwOnNextCall;

  int _autoId = 0;

  void _maybeThrow() {
    final e = throwOnNextCall;
    if (e != null) {
      throwOnNextCall = null;
      throw e;
    }
  }

  static String _key(List<String> path) => path.join('/');

  @override
  Future<List<RawDocument>> getCollection(
    List<String> path, {
    String? orderBy,
    bool descending = false,
  }) async {
    _maybeThrow();
    final prefix = '${_key(path)}/';
    final results = <RawDocument>[];
    for (final entry in docs.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final rest = entry.key.substring(prefix.length);
      if (rest.contains('/')) continue; // sub-collection document
      if (orderBy != null && !entry.value.containsKey(orderBy)) continue;
      results.add(RawDocument(rest, Map<String, dynamic>.of(entry.value)));
    }
    if (orderBy != null) {
      results.sort((a, b) {
        final av = a.data[orderBy] as Comparable<Object?>;
        final bv = b.data[orderBy] as Comparable<Object?>;
        final cmp = av.compareTo(bv);
        return descending ? -cmp : cmp;
      });
    }
    return results;
  }

  @override
  Future<RawDocument?> getDocument(List<String> path) async {
    _maybeThrow();
    final data = docs[_key(path)];
    if (data == null) return null;
    return RawDocument(path.last, Map<String, dynamic>.of(data));
  }

  @override
  Future<String> addDocument(
    List<String> collectionPath,
    Map<String, dynamic> data,
  ) async {
    _maybeThrow();
    final id = 'auto-${_autoId++}';
    docs['${_key(collectionPath)}/$id'] = Map<String, dynamic>.of(data);
    return id;
  }

  @override
  Future<void> setDocument(
    List<String> path,
    Map<String, dynamic> data, {
    bool merge = false,
  }) async {
    _maybeThrow();
    final key = _key(path);
    if (!merge || docs[key] == null) {
      docs[key] = _deepCopy(data);
      return;
    }
    docs[key] = _deepMerge(docs[key]!, data);
  }

  @override
  Future<void> updateDocument(
    List<String> path,
    Map<String, dynamic> data,
  ) async {
    _maybeThrow();
    final key = _key(path);
    final existing = docs[key];
    if (existing == null) {
      throw FirebaseException(plugin: 'fake', code: 'not-found');
    }
    existing.addAll(_deepCopy(data));
  }

  @override
  Future<void> deleteDocument(List<String> path) async {
    _maybeThrow();
    docs.remove(_key(path));
  }

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> map) => {
    for (final e in map.entries)
      e.key: e.value is Map<String, dynamic>
          ? _deepCopy(e.value as Map<String, dynamic>)
          : e.value,
  };

  static Map<String, dynamic> _deepMerge(
    Map<String, dynamic> base,
    Map<String, dynamic> updates,
  ) {
    final result = _deepCopy(base);
    for (final e in updates.entries) {
      final existing = result[e.key];
      if (existing is Map<String, dynamic> && e.value is Map<String, dynamic>) {
        result[e.key] = _deepMerge(existing, e.value as Map<String, dynamic>);
      } else {
        result[e.key] = e.value is Map<String, dynamic>
            ? _deepCopy(e.value as Map<String, dynamic>)
            : e.value;
      }
    }
    return result;
  }
}
