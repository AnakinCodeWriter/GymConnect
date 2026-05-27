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

  // Synchronous version of getRecentExerciseNames - takes an already-loaded
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

  // Returns a map of exercise name -> the last WORKING set logged for that
  // exercise. Warm-up sets are excluded so the prefill value and overload
  // hint always reflect the user's actual working load, not a warm-up weight.
  // workouts must already be sorted newest first (as returned by getWorkouts).
  Map<String, WorkoutSet> getLastSetsByExercise(List<WorkoutModel> workouts) {
    final result = <String, WorkoutSet>{};
    for (final workout in workouts) {
      for (final exercise in workout.exercises) {
        final name = exercise.name.trim();
        if (name.isNotEmpty && !result.containsKey(name)) {
          final working =
              exercise.sets.where((s) => !s.isWarmup).toList();
          if (working.isNotEmpty) result[name] = working.last;
        }
      }
    }
    return result;
  }

  // Removes one set from a stored workout document.
  // If the exercise has no sets remaining it is dropped from the workout.
  // If the workout has no exercises remaining the document is deleted entirely.
  Future<void> deleteSet(
      String uid, String workoutId, String exerciseName, int setIndex) async {
    final docRef = _workoutsRef(uid).doc(workoutId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final workout =
        WorkoutModel.fromMap(workoutId, doc.data() as Map<String, dynamic>);

    bool removed = false;
    final updatedExercises = <ExerciseEntry>[];
    for (final ex in workout.exercises) {
      if (ex.name == exerciseName && !removed) {
        final updatedSets = List<WorkoutSet>.from(ex.sets);
        if (setIndex < updatedSets.length) updatedSets.removeAt(setIndex);
        removed = true;
        if (updatedSets.isNotEmpty) {
          updatedExercises.add(ExerciseEntry(name: ex.name, sets: updatedSets));
        }
      } else {
        updatedExercises.add(ex);
      }
    }

    if (updatedExercises.isEmpty) {
      await docRef.delete();
    } else {
      await docRef.update({
        'exercises': updatedExercises.map((e) => e.toMap()).toList(),
      });
    }
  }

  // Sums weight * reps across all working (non-warm-up) sets, in kg.
  double getTotalVolumeLiftedKg(List<WorkoutModel> workouts) {
    double total = 0;
    for (final w in workouts) {
      for (final ex in w.exercises) {
        for (final s in ex.sets) {
          if (!s.isWarmup) total += s.weight * s.reps;
        }
      }
    }
    return total;
  }

  // Returns a map of exercise name -> all WORKING sets from the most recent
  // session in which that exercise appeared. Warm-up sets are excluded so
  // template prefill and the overload hint both reflect actual working loads.
  Map<String, List<WorkoutSet>> getLastSessionSetsByExercise(
      List<WorkoutModel> workouts) {
    final result = <String, List<WorkoutSet>>{};
    for (final workout in workouts) {
      for (final exercise in workout.exercises) {
        final name = exercise.name.trim();
        if (name.isNotEmpty && !result.containsKey(name)) {
          final working =
              exercise.sets.where((s) => !s.isWarmup).toList();
          if (working.isNotEmpty) result[name] = working;
        }
      }
    }
    return result;
  }
}
