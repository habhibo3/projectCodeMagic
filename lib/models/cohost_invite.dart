import 'package:cloud_firestore/cloud_firestore.dart';

class CoHostInvite {
  final String id;
  final String contestId;
  final String entryId;
  final String channelId;
  final String hostUserId;
  final String hostName;
  final String hostAvatar;
  final String inviteeUserId;
  final String inviteeName;
  final String inviteeAvatar;
  final String status; // pending, accepted, declined, cancelled
  final DateTime createdAt;

  const CoHostInvite({
    required this.id,
    required this.contestId,
    required this.entryId,
    required this.channelId,
    required this.hostUserId,
    required this.hostName,
    required this.hostAvatar,
    required this.inviteeUserId,
    required this.inviteeName,
    required this.inviteeAvatar,
    required this.status,
    required this.createdAt,
  });

  factory CoHostInvite.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final ts = data['createdAt'];
    return CoHostInvite(
      id: doc.id,
      contestId: data['contestId'] ?? '',
      entryId: data['entryId'] ?? '',
      channelId: data['channelId'] ?? data['entryId'] ?? '',
      hostUserId: data['hostUserId'] ?? '',
      hostName: data['hostName'] ?? 'Host',
      hostAvatar: data['hostAvatar'] ?? '',
      inviteeUserId: data['inviteeUserId'] ?? '',
      inviteeName: data['inviteeName'] ?? 'Guest',
      inviteeAvatar: data['inviteeAvatar'] ?? '',
      status: data['status'] ?? 'pending',
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }

  bool get isPending => status == 'pending';
}
