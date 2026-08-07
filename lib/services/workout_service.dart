import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../models/workout_model.dart';
import '../utils/fitness_formulas.dart';
import 'data_result.dart';
import 'firestore_adapter.dart';
import 'firestore_service.dart';
import 'leaderboard_service.dart';

/// Result payload of a successful save: which exercises set a new PR.
class WorkoutSaveOutcome {
  final List<String> newPersonalRecords;

  const WorkoutSaveOutcome(this.newPersonalRecords);
}

/// Workout data access + the multi-step save/delete flows that were
/// previously orchestrated inside screens (Phase 4).
///
/// Collection path: users/{uid}/workouts. Ordering rule: newest first by the
/// stored `date` Timestamp, tie-broken by document id ascending (client-side
/// stable sort after the server query). Firestore's orderBy omits documents
/// missing `date` - documented, pre-existing behaviour.
class WorkoutService {
  final FirestoreAdapter _adapter;
  final String? Function() _currentUid;
  final FirestoreService _profileService;
  final LeaderboardService _leaderboardService;

  WorkoutService({
    FirestoreAdapter? adapter,
    String? Function()? currentUidProvider,
    FirestoreService? profileService,
    LeaderboardService? leaderboardService,
  }) : _adapter = adapter ?? FirebaseFirestoreAdapter(),
       _currentUid = currentUidProvider ?? _defaultUid,
       _profileService = profileService ?? FirestoreService(adapter: adapter),
       _leaderboardService =
           leaderboardService ?? LeaderboardService(adapter: adapter);

  static String? _defaultUid() => FirebaseAuth.instance.currentUser?.uid;

  List<String> _workoutsPath(String uid) => ['users', uid, 'workouts'];

  /// Loads the signed-in user's workouts, newest first. Malformed documents
  /// are skipped and reported via [DataSuccess.skipped] - never silently
  /// discarded. An empty history is a successful empty list.
  Future<DataResult<List<WorkoutModel>>> loadWorkouts() async {
    final uid = _currentUid();
    if (uid == null) {
      return const DataFailure(DataFailureKind.unauthenticated);
    }
    try {
      final docs = await _adapter.getCollection(
        _workoutsPath(uid),
        orderBy: 'date',
        descending: true,
      );
      final workouts = <WorkoutModel>[];
      final skipped = <SkippedDocument>[];
      for (final doc in docs) {
        try {
          workouts.add(WorkoutModel.fromMap(doc.id, doc.data));
        } catch (e) {
          skipped.add(SkippedDocument(doc.id, e));
        }
      }
      _sortNewestFirst(workouts);
      return DataSuccess(workouts, skipped: skipped);
    } catch (e) {
      return DataFailure(failureKindFor(e), e);
    }
  }

  // Deterministic ordering: date descending, then document id ascending so
  // same-timestamp workouts always appear in a stable order.
  static void _sortNewestFirst(List<WorkoutModel> workouts) {
    workouts.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
  }

  /// Saves a workout, then best-effort: updates improved personal records
  /// and the gym leaderboard. PR/leaderboard failures never block a
  /// successful save (pre-Phase 4 semantics preserved); the leaderboard
  /// write is intentionally not awaited.
  Future<DataResult<WorkoutSaveOutcome>> saveWorkoutAndUpdateRecords(
    WorkoutModel workout,
  ) async {
    final uid = _currentUid();
    if (uid == null) {
      return const DataFailure(DataFailureKind.unauthenticated);
    }
    try {
      await _adapter.addDocument(_workoutsPath(uid), workout.toMap());
    } catch (e) {
      return DataFailure(failureKindFor(e), e);
    }

    final newPRs = <String>[];
    try {
      final profile = await _profileService.getUserProfile(uid);
      final stored = profile?.personalRecords ?? {};

      // Same calculation the leaderboard uses: best eligible capped e1RM
      // per exercise (warm-ups and malformed sets excluded).
      final bests = LeaderboardService.bestEligibleE1RmPerExercise(workout);
      final improved = <String, double>{
        for (final e in bests.entries)
          if (e.value > (stored[e.key] ?? 0)) e.key: e.value,
      };
      newPRs.addAll(improved.keys);
      if (improved.isNotEmpty) {
        await _profileService.updatePersonalRecords(uid, improved);
      }

      if (profile != null && profile.gymId.isNotEmpty) {
        unawaited(
          _leaderboardService
              .updateUserBestLifts(
                uid,
                profile.gymId,
                profile.displayName,
                profile.isAnonymous,
                workout,
              )
              .catchError((_) {}),
        );
      }
    } catch (_) {
      // best-effort: the workout is saved; PR/leaderboard updates may lag.
    }
    return DataSuccess(WorkoutSaveOutcome(newPRs));
  }

  /// Removes one set from a stored workout, dropping the exercise when it
  /// has no sets left and the whole document when no exercises remain, then
  /// recalculates the personal record for [exerciseName] from the remaining
  /// history. Returns the fresh workout list so callers need no re-fetch.
  Future<DataResult<List<WorkoutModel>>> deleteSetAndRecalculateRecord({
    required String workoutId,
    required String exerciseName,
    required int setIndex,
  }) async {
    final uid = _currentUid();
    if (uid == null) {
      return const DataFailure(DataFailureKind.unauthenticated);
    }
    try {
      final path = [..._workoutsPath(uid), workoutId];
      final doc = await _adapter.getDocument(path);
      if (doc != null) {
        final workout = WorkoutModel.fromMap(doc.id, doc.data);

        bool removed = false;
        final updatedExercises = <ExerciseEntry>[];
        for (final ex in workout.exercises) {
          if (ex.name == exerciseName && !removed) {
            final updatedSets = List<WorkoutSet>.from(ex.sets);
            if (setIndex < updatedSets.length) updatedSets.removeAt(setIndex);
            removed = true;
            if (updatedSets.isNotEmpty) {
              updatedExercises.add(
                ExerciseEntry(name: ex.name, sets: updatedSets),
              );
            }
          } else {
            updatedExercises.add(ex);
          }
        }

        if (updatedExercises.isEmpty) {
          await _adapter.deleteDocument(path);
        } else {
          await _adapter.updateDocument(path, {
            'exercises': updatedExercises.map((e) => e.toMap()).toList(),
          });
        }
      }
    } catch (e) {
      return DataFailure(failureKindFor(e), e);
    }

    final reloaded = await loadWorkouts();
    final workouts = reloaded.dataOrNull;
    if (workouts == null) return reloaded;

    try {
      double best = 0;
      for (final w in workouts) {
        for (final ex in w.exercises) {
          if (ex.name != exerciseName) continue;
          for (final s in ex.sets) {
            if (!isEligibleForStrengthAnalytics(s)) continue;
            final e1rm = estimatedOneRepMax(s.weight, s.reps);
            if (e1rm > best) best = e1rm;
          }
        }
      }
      await _profileService.updatePersonalRecords(uid, {exerciseName: best});
    } catch (e) {
      return DataFailure(failureKindFor(e), e);
    }
    return reloaded;
  }

  // ---------------------------------------------------------------------
  // Pure history-derived helpers (no data access).
  // ---------------------------------------------------------------------

  // Returns unique exercise names ordered by how often each appears
  // (most frequent first), capped at 15 so the chip row stays manageable.
  List<String> extractExerciseNames(List<WorkoutModel> workouts) {
    final counts = <String, int>{};
    for (final workout in workouts) {
      for (final exercise in workout.exercises) {
        final name = exercise.name.trim();
        if (name.isNotEmpty) {
          counts[name] = (counts[name] ?? 0) + 1;
        }
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).take(15).toList();
  }

  // Returns a map of exercise name -> the last WORKING set logged for that
  // exercise. Warm-up sets are excluded so the prefill value and overload
  // hint always reflect the user's actual working load, not a warm-up weight.
  // workouts must already be sorted newest first (as returned by loadWorkouts).
  Map<String, WorkoutSet> getLastSetsByExercise(List<WorkoutModel> workouts) {
    final result = <String, WorkoutSet>{};
    for (final workout in workouts) {
      for (final exercise in workout.exercises) {
        final name = exercise.name.trim();
        if (name.isNotEmpty && !result.containsKey(name)) {
          final working = exercise.sets.where((s) => !s.isWarmup).toList();
          if (working.isNotEmpty) result[name] = working.last;
        }
      }
    }
    return result;
  }

  // Sums weight * reps across all eligible sets, in kg. Warm-ups excluded
  // (pre-existing behaviour); malformed sets also excluded via the shared
  // eligibility rule (Phase 3).
  double getTotalVolumeLiftedKg(List<WorkoutModel> workouts) {
    double total = 0;
    for (final w in workouts) {
      for (final ex in w.exercises) {
        for (final s in ex.sets) {
          if (isEligibleForStrengthAnalytics(s)) total += s.weight * s.reps;
        }
      }
    }
    return total;
  }

  // Returns a map of exercise name -> all WORKING sets from the most recent
  // session in which that exercise appeared. Warm-up sets are excluded so
  // template prefill and the overload hint both reflect actual working loads.
  Map<String, List<WorkoutSet>> getLastSessionSetsByExercise(
    List<WorkoutModel> workouts,
  ) {
    final result = <String, List<WorkoutSet>>{};
    for (final workout in workouts) {
      for (final exercise in workout.exercises) {
        final name = exercise.name.trim();
        if (name.isNotEmpty && !result.containsKey(name)) {
          final working = exercise.sets.where((s) => !s.isWarmup).toList();
          if (working.isNotEmpty) result[name] = working;
        }
      }
    }
    return result;
  }
}
