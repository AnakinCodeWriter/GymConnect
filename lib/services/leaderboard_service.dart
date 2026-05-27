import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workout_model.dart';

// represents one user's entry on the gym leaderboard.
// bestLifts maps exercise name -> that user's all-time best estimated 1RM.
class LeaderboardEntry {
  final String uid;
  final String displayName;
  final bool isAnonymous;
  final Map<String, double> bestLifts;

  LeaderboardEntry({
    required this.uid,
    required this.displayName,
    required this.isAnonymous,
    required this.bestLifts,
  });

  factory LeaderboardEntry.fromMap(String uid, Map<String, dynamic> map) {
    final rawLifts = map['bestLifts'] as Map<String, dynamic>? ?? {};
    return LeaderboardEntry(
      uid: uid,
      displayName: map['displayName'] as String? ?? 'Unknown',
      isAnonymous: map['isAnonymous'] as bool? ?? false,
      bestLifts: rawLifts.map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }
}

class LeaderboardService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // scoped reference to the leaderboard subcollection for a given gym.
  // each document in this collection represents one user's best lifts.
  CollectionReference _leaderboardRef(String gymId) =>
      _db.collection('gyms').doc(gymId).collection('leaderboard');

  // updates the leaderboard with the best e1RM per exercise, only where improved.
  Future<void> updateUserBestLifts(
    String uid,
    String gymId,
    String displayName,
    bool isAnonymous,
    WorkoutModel workout,
  ) async {
    // compute the best e1RM (Epley: weight * (1 + reps / 30)) for each
    // exercise in this workout, taking the highest set value per exercise.
    final newBests = <String, double>{};
    for (final exercise in workout.exercises) {
      for (final set in exercise.sets) {
        final e1rm = set.weight * (1 + set.reps / 30);
        final current = newBests[exercise.name];
        if (current == null || e1rm > current) {
          newBests[exercise.name] = e1rm;
        }
      }
    }

    if (newBests.isEmpty) return;

    final docRef = _leaderboardRef(gymId).doc(uid);
    final existing = await docRef.get();

    // build a map of only the exercises where the new value beats the stored one
    final updates = <String, double>{};
    final storedLifts = existing.exists
        ? (existing.data() as Map<String, dynamic>)['bestLifts']
              as Map<String, dynamic>? ??
            {}
        : <String, dynamic>{};

    for (final entry in newBests.entries) {
      final stored = storedLifts[entry.key];
      final storedValue = stored != null ? (stored as num).toDouble() : null;
      if (storedValue == null || entry.value > storedValue) {
        updates[entry.key] = entry.value;
      }
    }

    // always write displayName and isAnonymous so they stay up to date,
    // even if no lift improved this session.
    await docRef.set({
      'displayName': displayName,
      'isAnonymous': isAnonymous,
      if (updates.isNotEmpty)
        'bestLifts': {
          ...storedLifts.map((k, v) => MapEntry(k, (v as num).toDouble())),
          ...updates,
        },
    }, SetOptions(merge: true));
  }

  // fetches all leaderboard entries for the given gym.
  Future<List<LeaderboardEntry>> getLeaderboard(String gymId) async {
    final snapshot = await _leaderboardRef(gymId).get();
    return snapshot.docs
        .map((doc) =>
            LeaderboardEntry.fromMap(doc.id, doc.data() as Map<String, dynamic>))
        .toList();
  }

  // updates only the isAnonymous flag on the user's leaderboard document.
  // called when the user toggles their visibility preference on the leaderboard screen.
  Future<void> setAnonymous(String uid, String gymId, bool isAnonymous) async {
    await _leaderboardRef(gymId).doc(uid).update({'isAnonymous': isAnonymous});
  }

  // updates the display name on any existing leaderboard entry for the user.
  // called when the user saves a new display name in their profile.
  // no-ops silently if the document doesn't exist yet (user has never saved a workout).
  Future<void> updateDisplayName(
      String uid, String gymId, String displayName) async {
    final docRef = _leaderboardRef(gymId).doc(uid);
    final snapshot = await docRef.get();
    if (!snapshot.exists) return;
    await docRef.update({'displayName': displayName});
  }
}
