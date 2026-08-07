import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import 'firestore_adapter.dart';

/// User-profile data access. Document path: users/{uid}.
///
/// Profile documents are auth-flow critical, so unlike collection loads the
/// operations here fail outright on malformed required data (callers such
/// as ProfileGate present a typed error state) rather than skipping.
class FirestoreService {
  final FirestoreAdapter _adapter;

  FirestoreService({FirestoreAdapter? adapter})
    : _adapter = adapter ?? FirebaseFirestoreAdapter();

  List<String> _userPath(String uid) => ['users', uid];

  Future<bool> userProfileExists(String uid) async {
    return await _adapter.getDocument(_userPath(uid)) != null;
  }

  Future<void> createUserProfile(UserModel user) async {
    await _adapter.setDocument(_userPath(user.uid), user.toMap());
  }

  Future<UserModel?> getUserProfile(String uid) async {
    final doc = await _adapter.getDocument(_userPath(uid));
    if (doc == null) return null;
    return UserModel.fromMap(uid, doc.data);
  }

  // updates only the isAnonymous field on the user's profile document.
  // used when the user toggles their leaderboard visibility preference.
  Future<void> updateAnonymous(String uid, bool isAnonymous) async {
    await _adapter.updateDocument(_userPath(uid), {'isAnonymous': isAnonymous});
  }

  // updates display name, experience level, fitness goal, and weight unit.
  Future<void> updateProfileDetails(
    String uid, {
    required String displayName,
    required String experienceLevel,
    required String fitnessGoal,
    required String weightUnit,
  }) async {
    await _adapter.updateDocument(_userPath(uid), {
      'displayName': displayName,
      'experienceLevel': experienceLevel,
      'fitnessGoal': fitnessGoal,
      'weightUnit': weightUnit,
    });
  }

  // saves or replaces the user's single training goal.
  Future<void> updateGoal(
    String uid, {
    required String exercise,
    required double targetWeight,
  }) async {
    await _adapter.updateDocument(_userPath(uid), {
      'goalExercise': exercise,
      'goalTargetWeight': targetWeight,
    });
  }

  // clears the user's training goal.
  Future<void> clearGoal(String uid) async {
    await _adapter.updateDocument(_userPath(uid), {
      'goalExercise': '',
      'goalTargetWeight': 0,
    });
  }

  // merges new personal records into the stored map. Callers pass only the
  // entries to write (e.g. improved values, or a recalculated value after a
  // set deletion); other exercises' records are preserved by the merge.
  //
  // Uses set(merge: true) instead of update() with dot-notation paths:
  // update() interprets '.' in a key as a nested-field separator, so an
  // exercise name like "B. Press" would corrupt the document. set() treats
  // map keys literally, making any exercise name safe without renaming it.
  // See docs/DECISIONS.md (2026-07-02, personal-record field paths).
  Future<void> updatePersonalRecords(
    String uid,
    Map<String, double> newRecords,
  ) async {
    if (newRecords.isEmpty) return;
    await _adapter.setDocument(
      _userPath(uid),
      personalRecordsMergeData(newRecords),
      merge: true,
    );
  }

  // Builds the merge payload for updatePersonalRecords. Exercise names are
  // used exactly as given - no encoding or renaming.
  @visibleForTesting
  static Map<String, Object> personalRecordsMergeData(
    Map<String, double> records,
  ) => {'personalRecords': Map<String, double>.of(records)};
}
