// TemplateSet, TemplateExercise, and TemplateModel follow the same
// toMap/fromMap pattern as workout_model.dart.

class TemplateSet {
  final int reps;
  final double? weight; // optional - templates can be defined without weights

  TemplateSet({required this.reps, this.weight});

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{'reps': reps};
    // only write the weight key if a value was provided
    if (weight != null) map['weight'] = weight;
    return map;
  }

  factory TemplateSet.fromMap(Map<String, dynamic> map) => TemplateSet(
    reps: map['reps'] as int,
    weight: map['weight'] != null ? (map['weight'] as num).toDouble() : null,
  );
}

class TemplateExercise {
  final String name;
  final List<TemplateSet> sets;

  TemplateExercise({required this.name, required this.sets});

  Map<String, dynamic> toMap() => {
    'name': name,
    'sets': sets.map((s) => s.toMap()).toList(),
  };

  factory TemplateExercise.fromMap(Map<String, dynamic> map) =>
      TemplateExercise(
        name: map['name'] as String,
        sets: (map['sets'] as List)
            .map((s) => TemplateSet.fromMap(s as Map<String, dynamic>))
            .toList(),
      );
}

class TemplateModel {
  final String id; // Firestore document ID - not stored inside the document
  final String name;
  final List<TemplateExercise> exercises;

  TemplateModel({
    required this.id,
    required this.name,
    required this.exercises,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'exercises': exercises.map((e) => e.toMap()).toList(),
  };

  factory TemplateModel.fromMap(String id, Map<String, dynamic> map) =>
      TemplateModel(
        id: id,
        name: map['name'] as String,
        exercises: (map['exercises'] as List)
            .map((e) => TemplateExercise.fromMap(e as Map<String, dynamic>))
            .toList(),
      );
}
