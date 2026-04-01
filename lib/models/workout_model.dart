import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutSet {
  final double weight;
  final int reps;

  WorkoutSet({required this.weight, required this.reps});

  Map<String, dynamic> toMap() => {'weight': weight, 'reps': reps};

  factory WorkoutSet.fromMap(Map<String, dynamic> map) => WorkoutSet(
        weight: (map['weight'] as num).toDouble(),
        reps: map['reps'] as int,
      );
}

class ExerciseEntry {
  final String name;
  final List<WorkoutSet> sets;

  ExerciseEntry({required this.name, required this.sets});

  Map<String, dynamic> toMap() => {
        'name': name,
        'sets': sets.map((s) => s.toMap()).toList(),
      };

  factory ExerciseEntry.fromMap(Map<String, dynamic> map) => ExerciseEntry(
        name: map['name'] as String,
        sets: (map['sets'] as List)
            .map((s) => WorkoutSet.fromMap(s as Map<String, dynamic>))
            .toList(),
      );
}

class WorkoutModel {
  final String id;
  final Timestamp date;
  final List<ExerciseEntry> exercises;

  WorkoutModel({required this.id, required this.date, required this.exercises});

  Map<String, dynamic> toMap() => {
        'date': date,
        'exercises': exercises.map((e) => e.toMap()).toList(),
      };

  factory WorkoutModel.fromMap(String id, Map<String, dynamic> map) =>
      WorkoutModel(
        id: id,
        date: map['date'] as Timestamp,
        exercises: (map['exercises'] as List)
            .map((e) => ExerciseEntry.fromMap(e as Map<String, dynamic>))
            .toList(),
      );
}
