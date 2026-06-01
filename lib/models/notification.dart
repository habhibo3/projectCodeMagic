import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String title;
  final String message;
  final String type; // 'vote', 'join', 'live', 'system'
  final DateTime timestamp;
  final String senderName;
  final String senderAvatar;

  NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    required this.senderName,
    required this.senderAvatar,
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final timestampData = data['timestamp'];

    return NotificationModel(
      id: doc.id,
      title: data['title'] ?? '',
      message: data['message'] ?? '',
      type: data['type'] ?? 'system',
      timestamp: timestampData is Timestamp 
          ? timestampData.toDate() 
          : DateTime.now(),
      senderName: data['senderName'] ?? 'FeastVote',
      senderAvatar: data['senderAvatar'] ?? 'https://i.pravatar.cc/150?u=feastvote',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'message': message,
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
      'senderName': senderName,
      'senderAvatar': senderAvatar,
    };
  }
}
