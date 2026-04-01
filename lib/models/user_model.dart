import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String displayName;
  final String gymId;
  final Timestamp createdAt;

  UserModel({
    required this.uid,
    required this.displayName,
    required this.gymId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'gymId': gymId,
      'createdAt': createdAt,
    };
  }

  factory UserModel.fromMap(String uid, Map<String, dynamic> map) {
    return UserModel(
      uid: uid,
      displayName: map['displayName'] ?? '',
      gymId: map['gymId'] ?? '',
      createdAt: map['createdAt'] ?? Timestamp.now(),
    );
  }
}
