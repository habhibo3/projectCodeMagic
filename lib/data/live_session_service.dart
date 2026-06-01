import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/cohost_invite.dart';
import '../models/comment.dart';

/// Real-time co-host signaling (Firestore) — pairs with Agora uid 100 (host) / 200 (co-host).
class LiveSessionService {
  FirebaseFirestore? _db;
  bool _isInitialized = false;

  LiveSessionService() {
    try {
      _db = FirebaseFirestore.instance;
      _isInitialized = true;
    } catch (e) {
      debugPrint('LiveSessionService: Firebase unavailable — $e');
    }
  }

  CollectionReference<Map<String, dynamic>> get _invites =>
      _db!.collection('cohost_invites');

  /// Pending invites addressed to this user (real-time).
  Stream<List<CoHostInvite>> watchPendingInvitesForUser(String userId) {
    if (!_isInitialized || _db == null) return Stream.value([]);

    return _invites
        .where('inviteeUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => CoHostInvite.fromFirestore(d)).toList());
  }

  /// Active co-host session for a live entry (host + co-host metadata).
  Stream<Map<String, dynamic>?> watchLiveSession(
      String contestId, String entryId) {
    if (!_isInitialized || _db == null) return Stream.value(null);

    return _db!
        .collection('contests')
        .doc(contestId)
        .collection('entries')
        .doc(entryId)
        .collection('live')
        .doc('session')
        .snapshots()
        .map((snap) => snap.exists ? snap.data() : null);
  }

  Future<String?> sendCoHostInvite({
    required String contestId,
    required String entryId,
    required String channelId,
    required String hostUserId,
    required String hostName,
    required String hostAvatar,
    required String inviteeUserId,
    required String inviteeName,
    required String inviteeAvatar,
  }) async {
    if (!_isInitialized || _db == null) return null;

    // Cancel any previous pending invite from this host for this entry
    final existing = await _invites
        .where('entryId', isEqualTo: entryId)
        .where('hostUserId', isEqualTo: hostUserId)
        .where('status', isEqualTo: 'pending')
        .get();
    for (final doc in existing.docs) {
      await doc.reference.update({'status': 'cancelled'});
    }

    final ref = await _invites.add({
      'contestId': contestId,
      'entryId': entryId,
      'channelId': channelId,
      'hostUserId': hostUserId,
      'hostName': hostName,
      'hostAvatar': hostAvatar,
      'inviteeUserId': inviteeUserId,
      'inviteeName': inviteeName,
      'inviteeAvatar': inviteeAvatar,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _sessionRef(contestId, entryId).set({
      'hostUserId': hostUserId,
      'hostName': hostName,
      'hostAvatar': hostAvatar,
      'coHostUserId': inviteeUserId,
      'coHostName': inviteeName,
      'coHostAvatar': inviteeAvatar,
      'status': 'invited',
      'channelId': channelId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return ref.id;
  }

  Future<bool> acceptCoHostInvite(CoHostInvite invite) async {
    if (!_isInitialized || _db == null) return false;

    try {
      await _db!.runTransaction((tx) async {
        final inviteRef = _invites.doc(invite.id);
        final inviteSnap = await tx.get(inviteRef);
        if (!inviteSnap.exists ||
            inviteSnap.data()?['status'] != 'pending') {
          return;
        }

        tx.update(inviteRef, {
          'status': 'accepted',
          'acceptedAt': FieldValue.serverTimestamp(),
        });

        final sessionRef = _sessionRef(invite.contestId, invite.entryId);
        tx.set(sessionRef, {
          'hostUserId': invite.hostUserId,
          'hostName': invite.hostName,
          'hostAvatar': invite.hostAvatar,
          'coHostUserId': invite.inviteeUserId,
          'coHostName': invite.inviteeName,
          'coHostAvatar': invite.inviteeAvatar,
          'status': 'live',
          'channelId': invite.channelId,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      return true;
    } catch (e) {
      debugPrint('acceptCoHostInvite failed: $e');
      return false;
    }
  }

  Future<void> declineCoHostInvite(String inviteId) async {
    if (!_isInitialized || _db == null) return;
    await _invites.doc(inviteId).update({'status': 'declined'});
  }

  Future<void> endCoHostSession({
    required String contestId,
    required String entryId,
    String? inviteId,
  }) async {
    if (!_isInitialized || _db == null) return;

    if (inviteId != null) {
      await _invites.doc(inviteId).update({'status': 'cancelled'});
    }

    final pending = await _invites
        .where('entryId', isEqualTo: entryId)
        .where('status', isEqualTo: 'pending')
        .get();
    for (final doc in pending.docs) {
      await doc.reference.update({'status': 'cancelled'});
    }

    await _sessionRef(contestId, entryId).set({
      'status': 'idle',
      'coHostUserId': FieldValue.delete(),
      'coHostName': FieldValue.delete(),
      'coHostAvatar': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  DocumentReference<Map<String, dynamic>> _sessionRef(
      String contestId, String entryId) {
    return _db!
        .collection('contests')
        .doc(contestId)
        .collection('entries')
        .doc(entryId)
        .collection('live')
        .doc('session');
  }

  // ── LIVE STREAM COMMENTS ──

  CollectionReference<Map<String, dynamic>> _liveCommentsRef(
      String contestId, String entryId) {
    return _sessionRef(contestId, entryId).collection('comments');
  }

  /// Watch live stream comments in real-time.
  Stream<List<CommentModel>> watchLiveComments(String contestId, String entryId) {
    if (!_isInitialized || _db == null) return Stream.value([]);
    return _liveCommentsRef(contestId, entryId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => CommentModel.fromFirestore(doc))
            .toList());
  }

  /// Add a comment to the live stream.
  Future<void> addLiveComment(
      String contestId, String entryId, CommentModel comment) async {
    if (!_isInitialized || _db == null) return;
    try {
      await _liveCommentsRef(contestId, entryId).add(comment.toMap());
    } catch (e) {
      debugPrint('Failed to add live comment: $e');
    }
  }

  /// Clear/delete all comments for this live stream session.
  Future<void> clearLiveComments(String contestId, String entryId) async {
    if (!_isInitialized || _db == null) return;
    try {
      final snap = await _liveCommentsRef(contestId, entryId).get();
      for (final doc in snap.docs) {
        await doc.reference.delete();
      }
      debugPrint('Cleared all live comments for entry $entryId');
    } catch (e) {
      debugPrint('Failed to clear live comments: $e');
    }
  }
}
