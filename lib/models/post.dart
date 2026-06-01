import 'package:cloud_firestore/cloud_firestore.dart';

class PostModel {
  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final String type; // 'video', 'image', 'text'
  final String contentUrl;
  final String caption;
  final String visibilityScope; // 'zip', 'city', 'state', 'country', 'global'
  final String location; // Actual location string (e.g., "Paris, France")
  final DateTime createdAt;
  final String? contestId; // The ID of the contest this post belongs to
  final List<String> likes;
  final int commentsCount;

  PostModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.type,
    required this.contentUrl,
    required this.caption,
    required this.visibilityScope,
    required this.location,
    required this.createdAt,
    this.contestId,
    this.likes = const [],
    this.commentsCount = 0,
  });

  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final createdAtData = data['createdAt'];
    final likesData = data['likes'];

    return PostModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'Anonymous',
      userAvatar: data['userAvatar'] ?? '',
      type: data['type'] ?? 'image',
      contentUrl: data['contentUrl'] ?? '',
      caption: data['caption'] ?? '',
      visibilityScope: data['visibilityScope'] ?? 'global',
      location: data['location'] ?? '',
      createdAt: createdAtData is Timestamp
          ? createdAtData.toDate()
          : DateTime.now(),
      contestId: data['contestId'],
      likes: likesData is List ? List<String>.from(likesData) : [],
      commentsCount: data['commentsCount'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userAvatar': userAvatar,
      'type': type,
      'contentUrl': contentUrl,
      'caption': caption,
      'visibilityScope': visibilityScope,
      'location': location,
      'createdAt': FieldValue.serverTimestamp(),
      'contestId': contestId,
      'likes': likes,
      'commentsCount': commentsCount,
    };
  }
}
