import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workout_model.dart';

class WorkoutService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _workoutsRef(String uid) =>
      _db.collection('users').doc(uid).collection('workouts');

  Future<void> saveWorkout(String uid, WorkoutModel workout) async {
    await _workoutsRef(uid).add(workout.toMap());
  }

  Future<List<WorkoutModel>> getWorkouts(String uid) async {
    final snapshot = await _workoutsRef(uid)
        .orderBy('date', descending: true)
        .get();
    return snapshot.docs
        .map((doc) =>
            WorkoutModel.fromMap(doc.id, doc.data() as Map<String, dynamic>))
        .toList();
  }

  // Returns unique exercise names from the user's full workout history,
  // ordered by how often each name appears (most frequent first).
  // Capped at 15 so the chip row stays manageable.
  Future<List<String>> getRecentExerciseNames(String uid) async {
    final workouts = await getWorkouts(uid);
    return extractExerciseNames(workouts);
  }

  // Synchronous version of getRecentExerciseNames — takes an already-loaded
  // workout list so the caller can avoid a second Firestore round-trip.
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

  // Returns a map of exercise name -> the last set logged for that exercise.
  // workouts must already be sorted newest first (as returned by getWorkouts).
  // Because we iterate newest-first, the first time we see a name is its most
  // recent entry — we stop tracking that name after that.
  Map<String, WorkoutSet> getLastSetsByExercise(List<WorkoutModel> workouts) {
    final result = <String, WorkoutSet>{};
    for (final workout in workouts) {
      for (final exercise in workout.exercises) {
        final name = exercise.name.trim();
        if (name.isNotEmpty && !result.containsKey(name) && exercise.sets.isNotEmpty) {
          result[name] = exercise.sets.last;
        }
      }
    }
    return result;
  }
}
