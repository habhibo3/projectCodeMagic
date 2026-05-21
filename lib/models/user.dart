import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String displayName;
  final String email;
  final String photoURL;
  final String role; // 'voter', 'contestant', 'judge', 'admin'
  final String country;
  final String countryFlag;
  final String bio;
  final DateTime createdAt;
  final int totalVotesCast;

  UserModel({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.photoURL,
    required this.role,
    required this.country,
    required this.countryFlag,
    required this.bio,
    required this.createdAt,
    required this.totalVotesCast,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final createdAtData = data['createdAt'];

    return UserModel(
      uid: doc.id,
      displayName: data['displayName'] ?? 'Anonymous User',
      email: data['email'] ?? '',
      photoURL: data['photoURL'] ?? 'https://i.pravatar.cc/150?u=anonymous',
      role: data['role'] ?? 'voter',
      country: data['country'] ?? 'Global',
      countryFlag: data['countryFlag'] ?? '🌍',
      bio: data['bio'] ?? '',
      createdAt: createdAtData is Timestamp 
          ? createdAtData.toDate() 
          : DateTime.now(),
      totalVotesCast: data['totalVotesCast'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'email': email,
      'photoURL': photoURL,
      'role': role,
      'country': country,
      'countryFlag': countryFlag,
      'bio': bio,
      'createdAt': FieldValue.serverTimestamp(),
      'totalVotesCast': totalVotesCast,
    };
  }
}
