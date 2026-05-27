import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String displayName;
  final String gymId;
  final Timestamp createdAt;
  // whether the user appears as "Anonymous" on the gym leaderboard
  final bool isAnonymous;
  // profile extras - stored for future use in recommendations
  final String experienceLevel; // 'Beginner', 'Intermediate', 'Advanced', or ''
  final String fitnessGoal;     // 'Build Muscle', 'Lose Weight', 'Improve Fitness', or ''
  // single training goal
  final String goalExercise;      // exercise name the user is targeting, or ''
  final double goalTargetWeight;  // target weight in kg (0 = no goal set)
  // personal records: exercise name -> best estimated 1RM achieved
  final Map<String, double> personalRecords;
  // preferred weight display unit: 'kg' or 'lbs'
  final String weightUnit;

  UserModel({
    required this.uid,
    required this.displayName,
    required this.gymId,
    required this.createdAt,
    this.isAnonymous = false,
    this.experienceLevel = '',
    this.fitnessGoal = '',
    this.goalExercise = '',
    this.goalTargetWeight = 0,
    this.personalRecords = const {},
    this.weightUnit = 'kg',
  });

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'gymId': gymId,
      'createdAt': createdAt,
      'isAnonymous': isAnonymous,
      'experienceLevel': experienceLevel,
      'fitnessGoal': fitnessGoal,
      'goalExercise': goalExercise,
      'goalTargetWeight': goalTargetWeight,
      'personalRecords': personalRecords,
      'weightUnit': weightUnit,
    };
  }

  factory UserModel.fromMap(String uid, Map<String, dynamic> map) {
    // personalRecords is stored as Map<String, dynamic> in Firestore -
    // cast each value to double, ignoring any entries that aren't numeric.
    final rawRecords = map['personalRecords'] as Map<String, dynamic>? ?? {};
    final records = {
      for (final e in rawRecords.entries)
        if (e.value is num) e.key: (e.value as num).toDouble(),
    };

    return UserModel(
      uid: uid,
      displayName: map['displayName'] ?? '',
      gymId: map['gymId'] ?? '',
      createdAt: map['createdAt'] ?? Timestamp.now(),
      isAnonymous: map['isAnonymous'] as bool? ?? false,
      experienceLevel: map['experienceLevel'] as String? ?? '',
      fitnessGoal: map['fitnessGoal'] as String? ?? '',
      goalExercise: map['goalExercise'] as String? ?? '',
      goalTargetWeight: (map['goalTargetWeight'] as num?)?.toDouble() ?? 0,
      personalRecords: records,
      weightUnit: map['weightUnit'] as String? ?? 'kg',
    );
  }
}
