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
}
