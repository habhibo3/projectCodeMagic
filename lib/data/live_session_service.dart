import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/cohost_invite.dart';
import '../models/comment.dart';
import '../models/station.dart';

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

  /// Active organizer live session (organizer goes live without an entry).
  Stream<Map<String, dynamic>?> watchOrganizerLiveSession(
      String contestId) {
    if (!_isInitialized || _db == null) return Stream.value(null);

    return _db!
        .collection('contests')
        .doc(contestId)
        .collection('organizer_live')
        .doc('session')
        .snapshots()
        .map((snap) => snap.exists ? snap.data() : null);
  }

  DocumentReference<Map<String, dynamic>> _stationSessionRef(String stationId) {
    return _db!
        .collection('stations')
        .doc(StationModel.normalizeId(stationId))
        .collection('live')
        .doc('session');
  }

  /// Active station live session (station host goes live).
  Stream<Map<String, dynamic>?> watchStationLiveSession(String stationId) {
    if (!_isInitialized || _db == null) return Stream.value(null);

    return _stationSessionRef(stationId)
        .snapshots()
        .map((snap) => snap.exists ? snap.data() : null);
  }

  Future<void> startStationSession({
    required String stationId,
    required String hostUserId,
    required String hostName,
    required String hostAvatar,
    required String channelId,
  }) async {
    if (!_isInitialized || _db == null) return;
    try {
      await _stationSessionRef(stationId).set({
        'hostUserId': hostUserId,
        'hostName': hostName,
        'hostAvatar': hostAvatar,
        'status': 'live',
        'channelId': channelId,
        'viewerCount': 0,
        // Every new broadcast has its own vote total.
        'totalVotes': 0,
        'isSplitScreen': true,
        'cameraView': 'hostOnly',
        'showChatInRightPanel': true,
        'isScreenShareFullScreen': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to start station session: $e');
    }
  }

  Future<void> endStationSession(String stationId) async {
    if (!_isInitialized || _db == null) return;
    try {
      await _stationSessionRef(stationId).set({
        'status': 'idle',
        'coHostUserId': FieldValue.delete(),
        'coHostName': FieldValue.delete(),
        'coHostAvatar': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to end station session: $e');
    }
  }

  Future<void> updateStationSessionLayout({
    required String stationId,
    bool? isSplitScreen,
    String? cameraView,
    bool? showChatInRightPanel,
    bool? isScreenShareFullScreen,
  }) async {
    if (!_isInitialized || _db == null) return;
    try {
      final updates = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
      if (isSplitScreen != null) updates['isSplitScreen'] = isSplitScreen;
      if (cameraView != null) updates['cameraView'] = cameraView;
      if (showChatInRightPanel != null) updates['showChatInRightPanel'] = showChatInRightPanel;
      if (isScreenShareFullScreen != null) updates['isScreenShareFullScreen'] = isScreenShareFullScreen;
      
      await _stationSessionRef(stationId).set(updates, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to update station session layout: $e');
    }
  }

  Future<String?> sendStationCoHostInvite({
    required String stationId,
    required String channelId,
    required String hostUserId,
    required String hostName,
    required String hostAvatar,
    required String inviteeUserId,
    required String inviteeName,
    required String inviteeAvatar,
  }) async {
    if (!_isInitialized || _db == null) return null;

    // Cancel any previous pending invite from this host for this station
    final existing = await _invites
        .where('stationId', isEqualTo: stationId)
        .where('hostUserId', isEqualTo: hostUserId)
        .where('status', isEqualTo: 'pending')
        .get();
    for (final doc in existing.docs) {
      await doc.reference.update({'status': 'cancelled'});
    }

    final ref = await _invites.add({
      'stationId': stationId,
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

    // Update station session with cohost info
    await _stationSessionRef(stationId).set({
      'coHostUserId': inviteeUserId,
      'coHostName': inviteeName,
      'coHostAvatar': inviteeAvatar,
      'status': 'invited',
      'channelId': channelId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return ref.id;
  }

  Future<bool> acceptStationCoHostInvite(CoHostInvite invite) async {
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

        final sessionRef = _stationSessionRef(invite.stationId!);
        tx.set(sessionRef, {
          'hostUserId': invite.hostUserId,
          'hostName': invite.hostName,
          'hostAvatar': invite.hostAvatar,
          'coHostUserId': invite.inviteeUserId,
          'coHostName': invite.inviteeName,
          'coHostAvatar': invite.inviteeAvatar,
          'status': 'live',
          'channelId': invite.channelId,
          'cameraView': 'splitBoth',
          'isSplitScreen': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      return true;
    } catch (e) {
      debugPrint('acceptStationCoHostInvite failed: $e');
      return false;
    }
  }

  Future<void> endStationCoHostSession({
    required String stationId,
    String? inviteId,
  }) async {
    if (!_isInitialized || _db == null) return;

    if (inviteId != null) {
      await _invites.doc(inviteId).update({'status': 'cancelled'});
    }

    // Cancel any pending invites for this station
    final pending = await _invites
        .where('stationId', isEqualTo: stationId)
        .where('status', isEqualTo: 'pending')
        .get();
    for (final doc in pending.docs) {
      await doc.reference.update({'status': 'cancelled'});
    }

    // Clear co-host fields on station session
    await _stationSessionRef(stationId).set({
      'status': 'live',
      'coHostUserId': FieldValue.delete(),
      'coHostName': FieldValue.delete(),
      'coHostAvatar': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> incrementStationLiveViewerCount(String stationId) async {
    if (!_isInitialized || _db == null) return;
    try {
      await _stationSessionRef(stationId).set({
        'viewerCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to increment station live viewer count: $e');
    }
  }

  Future<void> decrementStationLiveViewerCount(String stationId) async {
    if (!_isInitialized || _db == null) return;
    try {
      await _stationSessionRef(stationId).update({
        'viewerCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to decrement station live viewer count: $e');
    }
  }

  Stream<int> watchStationLiveViewerCount(String stationId) {
    if (!_isInitialized || _db == null) return Stream.value(0);
    return _stationSessionRef(stationId).snapshots().map((snap) {
      if (!snap.exists) return 0;
      final data = snap.data();
      return (data?['viewerCount'] as int?) ?? 0;
    });
  }

  Future<String?> sendCoHostInvite({
    required String contestId,
    required String? entryId, // null for Organizer Mode
    required String channelId,
    required String hostUserId,
    required String hostName,
    required String hostAvatar,
    required String inviteeUserId,
    required String inviteeName,
    required String inviteeAvatar,
  }) async {
    if (!_isInitialized || _db == null) return null;

    // Cancel any previous pending invite from this host
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
      if (entryId != null) 'entryId': entryId, // omit for Organizer Mode
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

    // Write the session document to the appropriate path
    await _resolvedSessionRef(contestId, entryId).set({
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

        // Route to the organizer session path when entryId is null (Organizer Mode)
        final sessionRef = _resolvedSessionRef(
            invite.contestId,
            (invite.entryId == null || invite.entryId!.isEmpty) ? null : invite.entryId);
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
    required String? entryId, // null for Organizer Mode
    String? inviteId,
  }) async {
    if (!_isInitialized || _db == null) return;

    if (inviteId != null) {
      await _invites.doc(inviteId).update({'status': 'cancelled'});
    }

    // Cancel any pending invites for this entry (or all organizer invites if null)
    final query = entryId != null
        ? _invites.where('entryId', isEqualTo: entryId).where('status', isEqualTo: 'pending')
        : _invites.where('entryId', isNull: true).where('status', isEqualTo: 'pending');
    final pending = await query.get();
    for (final doc in pending.docs) {
      await doc.reference.update({'status': 'cancelled'});
    }

    // Clear co-host fields on the correct session document
    await _resolvedSessionRef(contestId, entryId).set({
      'status': 'idle',
      'coHostUserId': FieldValue.delete(),
      'coHostName': FieldValue.delete(),
      'coHostAvatar': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Marks the organizer session as ended (idle) when the host leaves.
  Future<void> endOrganizerSession(String contestId) async {
    if (!_isInitialized || _db == null) return;
    try {
      await _db!
          .collection('contests')
          .doc(contestId)
          .collection('organizer_live')
          .doc('session')
          .set({
        'status': 'idle',
        'coHostUserId': FieldValue.delete(),
        'coHostName': FieldValue.delete(),
        'coHostAvatar': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to end organizer session: $e');
    }
  }

  /// Co-host voluntarily leaves — keeps status 'live' so the host continues
  /// streaming solo. Does NOT set status to 'idle' (that would kick everyone).
  Future<void> removeCoHostFromSession({
    required String contestId,
    required String? entryId, // null for Organizer Mode
    String? inviteId,
  }) async {
    if (!_isInitialized || _db == null) return;

    if (inviteId != null) {
      await _invites.doc(inviteId).update({'status': 'cancelled'});
    }

    // Keep status 'live' — host stays streaming; just remove co-host fields
    await _resolvedSessionRef(contestId, entryId).set({
      'status': 'live',
      'coHostUserId': FieldValue.delete(),
      'coHostName': FieldValue.delete(),
      'coHostAvatar': FieldValue.delete(),
      'cameraView': 'hostOnly',
      'isSplitScreen': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> startHostSession({
    required String contestId,
    required String entryId,
    required String hostUserId,
    required String hostName,
    required String hostAvatar,
    required String channelId,
  }) async {
    if (!_isInitialized || _db == null) return;
    try {
      await _sessionRef(contestId, entryId).set({
        'hostUserId': hostUserId,
        'hostName': hostName,
        'hostAvatar': hostAvatar,
        'status': 'live',
        'channelId': channelId,
        'isSplitScreen': true,
        'cameraView': 'hostOnly',
        'showChatInRightPanel': true,
        'viewerCount': 0, // Reset viewer count when starting new session
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to start host session: $e');
    }
  }

  Future<void> startOrganizerSession({
    required String contestId,
    required String hostUserId,
    required String hostName,
    required String hostAvatar,
    required String channelId,
  }) async {
    if (!_isInitialized || _db == null) return;
    try {
      // Use set() without merge so stale coHost fields from a previous session
      // are fully cleared — prevents false split-screen on startup.
      await _db!
          .collection('contests')
          .doc(contestId)
          .collection('organizer_live')
          .doc('session')
          .set({
        'hostUserId': hostUserId,
        'hostName': hostName,
        'hostAvatar': hostAvatar,
        'status': 'live',
        'channelId': channelId,
        'viewerCount': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      }); // no merge — clears any leftover coHostUserId/coHostName/etc
    } catch (e) {
      debugPrint('Failed to start organizer session: $e');
    }
  }

  Future<void> updateSessionLayout({
    required String contestId,
    required String? entryId, // null for Organizer Mode
    required bool isSplitScreen,
    required String cameraView,
    required bool showChatInRightPanel,
    bool isScreenShareFullScreen = false,
    String? selectedEntryId,
  }) async {
    if (!_isInitialized || _db == null) return;
    try {
      await _resolvedSessionRef(contestId, entryId).set({
        'isSplitScreen': isSplitScreen,
        'cameraView': cameraView,
        'showChatInRightPanel': showChatInRightPanel,
        'isScreenShareFullScreen': isScreenShareFullScreen,
        if (selectedEntryId != null) 'selectedEntryId': selectedEntryId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to update session layout: $e');
    }
  }

  Future<void> setCountdownState(String contestId, String? entryId, bool startCountdown) async {
    if (!_isInitialized || _db == null) return;
    try {
      await _resolvedSessionRef(contestId, entryId).set({
        'startCountdown': startCountdown,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to set countdown state: $e');
    }
  }

  Future<void> setVoteResultsState(String contestId, String? entryId, bool showVoteResults) async {
    if (!_isInitialized || _db == null) return;
    try {
      await _resolvedSessionRef(contestId, entryId).set({
        'showVoteResults': showVoteResults,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to set vote results state: $e');
    }
  }

  Future<void> setStationVoteResultsState(String stationId, bool showVoteResults) async {
    if (!_isInitialized || _db == null) return;
    try {
      await _db!
          .collection('stations')
          .doc(stationId)
          .collection('live')
          .doc('session')
          .set({
        'showVoteResults': showVoteResults,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to set station vote results state: $e');
    }
  }

  /// Resolves to organizer_live/session when entryId is null, otherwise entries/{entryId}/live/session.
  DocumentReference<Map<String, dynamic>> _resolvedSessionRef(
      String contestId, String? entryId) {
    if (entryId == null || entryId.isEmpty) {
      return _db!
          .collection('contests')
          .doc(contestId)
          .collection('organizer_live')
          .doc('session');
    }
    return _sessionRef(contestId, entryId);
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

  // ── VIEWER COUNT TRACKING ──

  /// Increment viewer count when a user joins the live stream
  Future<void> incrementViewerCount(String contestId, String entryId) async {
    if (!_isInitialized || _db == null) return;
    try {
      await _sessionRef(contestId, entryId).update({
        'viewerCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to increment viewer count: $e');
    }
  }

  /// Decrement viewer count when a user leaves the live stream
  Future<void> decrementViewerCount(String contestId, String entryId) async {
    if (!_isInitialized || _db == null) return;
    try {
      await _sessionRef(contestId, entryId).update({
        'viewerCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to decrement viewer count: $e');
    }
  }

  /// Watch viewer count in real-time
  Stream<int> watchViewerCount(String contestId, String entryId) {
    if (!_isInitialized || _db == null) return Stream.value(0);
    return _sessionRef(contestId, entryId).snapshots().map((snap) {
      if (!snap.exists) return 0;
      final data = snap.data();
      return (data?['viewerCount'] as int?) ?? 0;
    });
  }

  /// Increment organizer viewer count
  Future<void> incrementOrganizerViewerCount(String contestId) async {
    if (!_isInitialized || _db == null) return;
    try {
      await _db!
          .collection('contests')
          .doc(contestId)
          .collection('organizer_live')
          .doc('session')
          .update({
        'viewerCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to increment organizer viewer count: $e');
    }
  }

  /// Decrement organizer viewer count
  Future<void> decrementOrganizerViewerCount(String contestId) async {
    if (!_isInitialized || _db == null) return;
    try {
      await _db!
          .collection('contests')
          .doc(contestId)
          .collection('organizer_live')
          .doc('session')
          .update({
        'viewerCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to decrement organizer viewer count: $e');
    }
  }

  /// Watch organizer viewer count changes
  Stream<int> watchOrganizerViewerCount(String contestId) {
    if (!_isInitialized || _db == null) return Stream.value(0);
    return _db!
        .collection('contests')
        .doc(contestId)
        .collection('organizer_live')
        .doc('session')
        .snapshots()
        .map((snap) {
      if (!snap.exists) return 0;
      final data = snap.data();
      return (data?['viewerCount'] as int?) ?? 0;
    });
  }
}

