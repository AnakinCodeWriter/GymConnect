import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String displayName;
  final String gymId;
  final Timestamp createdAt;
  // whether the user appears as "Anonymous" on the gym leaderboard
  final bool isAnonymous;

  UserModel({
    required this.uid,
    required this.displayName,
    required this.gymId,
    required this.createdAt,
    this.isAnonymous = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'gymId': gymId,
      'createdAt': createdAt,
      'isAnonymous': isAnonymous,
    };
  }

  factory UserModel.fromMap(String uid, Map<String, dynamic> map) {
    return UserModel(
      uid: uid,
      displayName: map['displayName'] ?? '',
      gymId: map['gymId'] ?? '',
      createdAt: map['createdAt'] ?? Timestamp.now(),
      // nullable read with false fallback so existing accounts without this
      // field are treated as non-anonymous by default
      isAnonymous: map['isAnonymous'] as bool? ?? false,
    );
  }
}
