import '../models/workout_model.dart';
import '../utils/fitness_formulas.dart';
import 'data_result.dart';
import 'firestore_adapter.dart';

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

/// Gym leaderboard data access. Collection path:
/// gyms/{gymId}/leaderboard/{uid} (one document per user, unordered read;
/// ranking is computed client-side per selected exercise).
class LeaderboardService {
  /// The display value stored on anonymous entries. Security rules cannot
  /// redact fields from a readable document, so the readable leaderboard
  /// document itself must never contain the real display name while the
  /// user is anonymous (Phase 10; docs/FIRESTORE_SECURITY.md). Entries
  /// written before Phase 10 may still hold a real name until the owner's
  /// next write - documented historical limitation, migrated in Phase 12.
  static const String anonymousDisplayName = 'Anonymous';

  final FirestoreAdapter _adapter;

  LeaderboardService({FirestoreAdapter? adapter})
    : _adapter = adapter ?? FirebaseFirestoreAdapter();

  List<String> _leaderboardPath(String gymId) => ['gyms', gymId, 'leaderboard'];

  // Pure calculator (Phase 3): best eligible e1RM per exercise in one
  // workout, using the canonical capped formula. Warm-up and malformed sets
  // are excluded via the shared eligibility rule; an exercise with no
  // eligible sets produces no entry. Duplicate same-named entries all
  // contribute (best wins). Also used by WorkoutService for PR detection so
  // leaderboard and personal records always agree.
  static Map<String, double> bestEligibleE1RmPerExercise(WorkoutModel workout) {
    final bests = <String, double>{};
    for (final exercise in workout.exercises) {
      for (final set in exercise.sets) {
        if (!isEligibleForStrengthAnalytics(set)) continue;
        final e1rm = estimatedOneRepMax(set.weight, set.reps);
        final current = bests[exercise.name];
        if (current == null || e1rm > current) {
          bests[exercise.name] = e1rm;
        }
      }
    }
    return bests;
  }

  // updates the leaderboard with the best e1RM per exercise, only where
  // improved. Read-then-merge on the user's OWN document only; concurrent
  // writes from the same user's devices are last-write-wins (documented).
  Future<void> updateUserBestLifts(
    String uid,
    String gymId,
    String displayName,
    bool isAnonymous,
    WorkoutModel workout,
  ) async {
    final newBests = bestEligibleE1RmPerExercise(workout);

    if (newBests.isEmpty) return;

    final path = [..._leaderboardPath(gymId), uid];
    final existing = await _adapter.getDocument(path);

    // build a map of only the exercises where the new value beats the stored one
    final updates = <String, double>{};
    final storedLifts =
        existing?.data['bestLifts'] as Map<String, dynamic>? ??
        <String, dynamic>{};

    for (final entry in newBests.entries) {
      final stored = storedLifts[entry.key];
      final storedValue = stored != null ? (stored as num).toDouble() : null;
      if (storedValue == null || entry.value > storedValue) {
        updates[entry.key] = entry.value;
      }
    }

    // always write displayName and isAnonymous so they stay up to date,
    // even if no lift improved this session. Anonymous users store the
    // safe display value - never the real name (Phase 10).
    await _adapter.setDocument(path, {
      'displayName': isAnonymous ? anonymousDisplayName : displayName,
      'isAnonymous': isAnonymous,
      if (updates.isNotEmpty)
        'bestLifts': {
          ...storedLifts.map((k, v) => MapEntry(k, (v as num).toDouble())),
          ...updates,
        },
    }, merge: true);
  }

  /// Fetches all leaderboard entries for the given gym. Malformed entries
  /// are skipped and reported via [DataSuccess.skipped].
  Future<DataResult<List<LeaderboardEntry>>> loadLeaderboard(
    String gymId,
  ) async {
    try {
      final docs = await _adapter.getCollection(_leaderboardPath(gymId));
      final entries = <LeaderboardEntry>[];
      final skipped = <SkippedDocument>[];
      for (final doc in docs) {
        try {
          entries.add(LeaderboardEntry.fromMap(doc.id, doc.data));
        } catch (e) {
          skipped.add(SkippedDocument(doc.id, e));
        }
      }
      return DataSuccess(entries, skipped: skipped);
    } catch (e) {
      return DataFailure(failureKindFor(e), e);
    }
  }

  // Toggles the anonymity flag on the user's leaderboard document AND
  // keeps the stored display value consistent with it (Phase 10): turning
  // anonymity on overwrites the readable name with the safe value; turning
  // it off restores [displayName] (the profile's name, which the caller
  // legitimately has). set(merge) rather than update() so toggling before
  // ever saving a workout doesn't throw (Phase 4 fix); a flag-only
  // document stays invisible in rankings because it has no bestLifts.
  Future<void> setAnonymous(
    String uid,
    String gymId,
    bool isAnonymous, {
    required String displayName,
  }) async {
    await _adapter.setDocument(
      [..._leaderboardPath(gymId), uid],
      {
        'isAnonymous': isAnonymous,
        'displayName': isAnonymous ? anonymousDisplayName : displayName,
      },
      merge: true,
    );
  }

  // updates the display name on any existing leaderboard entry for the user.
  // called when the user saves a new display name in their profile.
  // no-ops silently if the document doesn't exist yet (user has never saved
  // a workout) - and also while the entry is anonymous, so a profile rename
  // can never leak a real name into the readable document (Phase 10).
  Future<void> updateDisplayName(
    String uid,
    String gymId,
    String displayName,
  ) async {
    final path = [..._leaderboardPath(gymId), uid];
    final existing = await _adapter.getDocument(path);
    if (existing == null) return;
    if (existing.data['isAnonymous'] == true) return;
    await _adapter.updateDocument(path, {'displayName': displayName});
  }
}
