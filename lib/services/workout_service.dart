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
}
