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
  final String subscriptionLevel; // 'free', 'premium'
  final String location; // City/State/Zip string or description
  final String zip;
  final String city;
  final String state;

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
    this.subscriptionLevel = 'free',
    this.location = 'Tunisia',
    this.zip = '75001',
    this.city = 'Tunis',
    this.state = 'Tunis State',
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final createdAtData = data['createdAt'];

    return UserModel(
      uid: doc.id,
      displayName: data['displayName'] ?? 'Anonymous User',
      email: data['email'] ?? '',
      photoURL: data['photoURL'] ?? '',
      role: data['role'] ?? 'voter',
      country: data['country'] ?? 'Global',
      countryFlag: data['countryFlag'] ?? '🌍',
      bio: data['bio'] ?? '',
      createdAt: createdAtData is Timestamp 
          ? createdAtData.toDate() 
          : DateTime.now(),
      totalVotesCast: data['totalVotesCast'] ?? 0,
      subscriptionLevel: data['subscriptionLevel'] ?? 'free',
      location: data['location'] ?? 'Tunisia',
      zip: data['zip'] ?? '75001',
      city: data['city'] ?? 'Tunis',
      state: data['state'] ?? 'Tunis State',
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
      'subscriptionLevel': subscriptionLevel,
      'location': location,
      'zip': zip,
      'city': city,
      'state': state,
    };
  }
}
