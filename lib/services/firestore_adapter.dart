import 'package:cloud_firestore/cloud_firestore.dart';

/// A raw Firestore document: id + data map.
class RawDocument {
  final String id;
  final Map<String, dynamic> data;

  const RawDocument(this.id, this.data);
}

/// The single narrow boundary between services and Firestore (Phase 4).
/// Paths are segment lists alternating collection/document, e.g.
/// ['users', uid, 'workouts'] (a collection) or
/// ['users', uid, 'workouts', workoutId] (a document).
///
/// Services own path construction and (de)serialisation; this interface
/// only moves raw maps. Tests use an in-memory fake; real merge/offline
/// semantics remain emulator-verified (Phase 10).
abstract class FirestoreAdapter {
  /// Loads a collection. When [orderBy] is set, ordering is delegated to
  /// Firestore, which OMITS documents missing that field (documented,
  /// pre-existing behaviour for workout loads).
  Future<List<RawDocument>> getCollection(
    List<String> path, {
    String? orderBy,
    bool descending = false,
  });

  /// Returns null when the document does not exist.
  Future<RawDocument?> getDocument(List<String> path);

  /// Adds a document with an auto-generated id; returns the new id.
  Future<String> addDocument(
    List<String> collectionPath,
    Map<String, dynamic> data,
  );

  Future<void> setDocument(
    List<String> path,
    Map<String, dynamic> data, {
    bool merge = false,
  });

  /// Fails if the document does not exist (Firestore update semantics).
  Future<void> updateDocument(List<String> path, Map<String, dynamic> data);

  Future<void> deleteDocument(List<String> path);
}

/// Production adapter over the live Firestore instance.
class FirebaseFirestoreAdapter implements FirestoreAdapter {
  final FirebaseFirestore _db;

  FirebaseFirestoreAdapter({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _collection(List<String> path) {
    assert(path.length.isOdd, 'collection paths have an odd segment count');
    var col = _db.collection(path.first);
    for (var i = 1; i + 1 < path.length; i += 2) {
      col = col.doc(path[i]).collection(path[i + 1]);
    }
    return col;
  }

  DocumentReference<Map<String, dynamic>> _document(List<String> path) {
    assert(path.length.isEven, 'document paths have an even segment count');
    return _collection(path.sublist(0, path.length - 1)).doc(path.last);
  }

  @override
  Future<List<RawDocument>> getCollection(
    List<String> path, {
    String? orderBy,
    bool descending = false,
  }) async {
    Query<Map<String, dynamic>> query = _collection(path);
    if (orderBy != null) {
      query = query.orderBy(orderBy, descending: descending);
    }
    final snapshot = await query.get();
    return [for (final d in snapshot.docs) RawDocument(d.id, d.data())];
  }

  @override
  Future<RawDocument?> getDocument(List<String> path) async {
    final doc = await _document(path).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    return RawDocument(doc.id, data);
  }

  @override
  Future<String> addDocument(
    List<String> collectionPath,
    Map<String, dynamic> data,
  ) async {
    final ref = await _collection(collectionPath).add(data);
    return ref.id;
  }

  @override
  Future<void> setDocument(
    List<String> path,
    Map<String, dynamic> data, {
    bool merge = false,
  }) {
    return _document(path).set(data, SetOptions(merge: merge));
  }

  @override
  Future<void> updateDocument(List<String> path, Map<String, dynamic> data) {
    return _document(path).update(data);
  }

  @override
  Future<void> deleteDocument(List<String> path) {
    return _document(path).delete();
  }
}
