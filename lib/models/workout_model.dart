import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutSet {
  final double weight;
  final int reps;
  final bool isWarmup;

  WorkoutSet({required this.weight, required this.reps, this.isWarmup = false});

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{'weight': weight, 'reps': reps};
    if (isWarmup) m['isWarmup'] = true;
    return m;
  }

  factory WorkoutSet.fromMap(Map<String, dynamic> map) => WorkoutSet(
        weight: (map['weight'] as num).toDouble(),
        reps: map['reps'] as int,
        isWarmup: map['isWarmup'] as bool? ?? false,
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
  final String name;
  final Timestamp date;
  final List<ExerciseEntry> exercises;
  final int? feelRating; // 1–5, null if the user did not rate this session

  WorkoutModel({
    required this.id,
    this.name = '',
    required this.date,
    required this.exercises,
    this.feelRating,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'date': date,
      'exercises': exercises.map((e) => e.toMap()).toList(),
    };
    if (name.isNotEmpty) map['name'] = name;
    if (feelRating != null) map['feelRating'] = feelRating;
    return map;
  }

  factory WorkoutModel.fromMap(String id, Map<String, dynamic> map) =>
      WorkoutModel(
        id: id,
        name: map['name'] as String? ?? '',
        date: map['date'] as Timestamp,
        exercises: (map['exercises'] as List)
            .map((e) => ExerciseEntry.fromMap(e as Map<String, dynamic>))
            .toList(),
        feelRating: map['feelRating'] as int?,
      );
}
