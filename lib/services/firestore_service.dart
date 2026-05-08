import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<bool> userProfileExists(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.exists;
  }

  Future<void> createUserProfile(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toMap());
  }

  Future<UserModel?> getUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromMap(uid, doc.data()!);
  }

  // updates only the isAnonymous field on the user's profile document.
  // used when the user toggles their leaderboard visibility preference.
  Future<void> updateAnonymous(String uid, bool isAnonymous) async {
    await _db.collection('users').doc(uid).update({'isAnonymous': isAnonymous});
  }

  // updates display name, experience level, fitness goal, and weight unit.
  Future<void> updateProfileDetails(
    String uid, {
    required String displayName,
    required String experienceLevel,
    required String fitnessGoal,
    required String weightUnit,
  }) async {
    await _db.collection('users').doc(uid).update({
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
    await _db.collection('users').doc(uid).update({
      'goalExercise': exercise,
      'goalTargetWeight': targetWeight,
    });
  }

  // clears the user's training goal.
  Future<void> clearGoal(String uid) async {
    await _db.collection('users').doc(uid).update({
      'goalExercise': '',
      'goalTargetWeight': 0,
    });
  }

  // merges new personal records into the stored map.
  // only updates entries where the new value beats the stored value.
  Future<void> updatePersonalRecords(
      String uid, Map<String, double> newRecords) async {
    final updates = {
      for (final e in newRecords.entries)
        'personalRecords.${e.key}': e.value,
    };
    await _db.collection('users').doc(uid).update(updates);
  }
}
