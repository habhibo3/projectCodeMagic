import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewModel {
  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final int ratingStars; // 1 to 5
  final String reviewText;
  final DateTime timestamp;

  ReviewModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.ratingStars,
    required this.reviewText,
    required this.timestamp,
  });

  factory ReviewModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final timestampData = data['timestamp'];
    
    return ReviewModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'Anonymous',
      userAvatar: data['userAvatar'] ?? 'https://i.pravatar.cc/150?u=99',
      ratingStars: data['ratingStars'] ?? 5,
      reviewText: data['reviewText'] ?? '',
      timestamp: timestampData is Timestamp 
          ? timestampData.toDate() 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userAvatar': userAvatar,
      'ratingStars': ratingStars,
      'reviewText': reviewText,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}
