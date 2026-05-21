import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/firebase_service.dart';
import '../data/live_session_service.dart';
import '../models/cohost_invite.dart';
import '../models/entry.dart';
import '../models/comment.dart';
import '../models/review.dart';
import '../models/user.dart';

class VoteActivity {
  final String userName;
  final String countryFlag;
  final String comment;
  final DateTime time;

  VoteActivity({
    required this.userName,
    required this.countryFlag,
    required this.comment,
    required this.time,
  });
}

class RankingEngine extends ChangeNotifier {
  final FirebaseService _firebaseService = FirebaseService();
  final LiveSessionService _liveSessionService = LiveSessionService();
  final String currentUserId;

  List<ContestModel> _contests = [];
  List<ContestEntry> _entries = [];
  final List<VoteActivity> _voteActivity = [];
  UserModel? _currentUserProfile;

  StreamSubscription? _contestsSub;
  StreamSubscription? _entriesSub;
  StreamSubscription? _userSub;
  StreamSubscription? _followedSub;

  String? _currentContestId;
  String? _lastViewedEntryId;

  RankingEngine({required this.currentUserId}) {
    _listenToContests();
    _listenToCurrentUser();
  }

  UserModel? get currentUserProfile => _currentUserProfile;
  List<ContestModel> get contests => List.unmodifiable(_contests);
  List<ContestEntry> get entries => List.unmodifiable(_entries);
  List<VoteActivity> get voteActivity => List.unmodifiable(_voteActivity);

  List<String> _followedContestIds = [];
  List<String> get followedContestIds => List.unmodifiable(_followedContestIds);

  void _listenToContests() {
    _contestsSub = _firebaseService.getContests().listen((fetchedContests) {
      if (fetchedContests.isNotEmpty) {
        _contests = fetchedContests;
        notifyListeners();
      }
    });
  }

  void loadContestEntries(String contestId) {
    _currentContestId = contestId;
    _entriesSub?.cancel();
    _voteActivity.clear();

    _entriesSub = _firebaseService.getEntries(contestId).listen((fetchedEntries) {
      _entries = fetchedEntries;
      notifyListeners();
    });
  }

  void _listenToCurrentUser() {
    _userSub?.cancel();
    _userSub = _firebaseService.getUserProfile(currentUserId).listen((profile) {
      _currentUserProfile = profile;
      notifyListeners();
      if (profile != null && _currentContestId != null && _lastViewedEntryId != null) {
        trackEntryView(_lastViewedEntryId!);
      }
    });

    _followedSub?.cancel();
    _followedSub = _firebaseService.getFollowedContests(currentUserId).listen((ids) {
      _followedContestIds = ids;
      notifyListeners();
    });
  }

  Future<bool> addVote(String entryId) async {
    if (_currentContestId != null) {
      final success =
          await _firebaseService.addVote(_currentContestId!, entryId, currentUserId);

      if (success) {
        final voterFlag = _currentUserProfile?.countryFlag ?? '🌍';
        _voteActivity.insert(0, VoteActivity(
          userName: 'You',
          countryFlag: voterFlag,
          comment: 'You voted!',
          time: DateTime.now(),
        ));
        if (_voteActivity.length > 20) _voteActivity.removeLast();
        notifyListeners();
      }
      return success;
    }
    return false;
  }

  void addMockUserEntry() {
    if (_currentContestId == null) return;

    final alreadyJoined = _entries.any((e) => e.userId == currentUserId);
    if (alreadyJoined) return;

    final profile = _currentUserProfile;
    final newId = 'user_entry_${DateTime.now().millisecondsSinceEpoch}';
    final newEntry = ContestEntry(
      id: newId,
      userId: currentUserId,
      userName: profile?.displayName ?? 'You (Player) 🎤',
      userAvatar: profile?.photoURL ?? 'https://i.pravatar.cc/150?u=99',
      countryFlag: profile?.countryFlag ?? '🏠',
      contentUrl: 'https://images.unsplash.com/photo-1516280440614-37939bbacd81',
      type: 'image',
      caption: 'My awesome entry! 🎉',
      totalVotes: 0,
      windowVotes: 0,
    );

    _firebaseService.addEntry(_currentContestId!, newEntry);
  }

  Stream<List<CommentModel>> getComments(String entryId) {
    if (_currentContestId == null) {
      return Stream.value([]);
    }
    return _firebaseService.getComments(_currentContestId!, entryId);
  }

  void addComment(String entryId, String text) {
    if (_currentContestId != null) {
      final profile = _currentUserProfile;
      final comment = CommentModel(
        id: '',
        userId: currentUserId,
        userName: profile?.displayName ?? 'You',
        userAvatar: profile?.photoURL ?? 'https://i.pravatar.cc/150?u=99',
        text: text,
        timestamp: DateTime.now(),
      );
      _firebaseService.addComment(_currentContestId!, entryId, comment);
    }
  }

  void trackEntryView(String entryId) {
    if (_currentContestId == null) return;
    _lastViewedEntryId = entryId;
    _firebaseService.trackAudiencePresence(
      _currentContestId!,
      entryId,
      currentUserId,
    );
  }

  Future<void> updateMyDisplayName(String displayName) async {
    await _firebaseService.updateUserDisplayName(currentUserId, displayName);
    final profile = _currentUserProfile;
    if (_currentContestId != null && profile != null) {
      await _firebaseService.syncEntryUserProfile(
        _currentContestId!,
        currentUserId,
        displayName: displayName.trim(),
        photoURL: profile.photoURL,
        countryFlag: profile.countryFlag,
      );
    }
    if (_lastViewedEntryId != null) {
      trackEntryView(_lastViewedEntryId!);
    }
  }

  Future<void> updateMyCountry(String country, String countryFlag) async {
    await _firebaseService.updateUserCountry(currentUserId, country, countryFlag);
    final profile = _currentUserProfile;
    if (_currentContestId != null && profile != null) {
      await _firebaseService.syncEntryUserProfile(
        _currentContestId!,
        currentUserId,
        displayName: profile.displayName,
        photoURL: profile.photoURL,
        countryFlag: countryFlag,
      );
    }
    if (_lastViewedEntryId != null) {
      trackEntryView(_lastViewedEntryId!);
    }
  }

  Stream<Map<String, int>> getAudienceByCountry(String entryId) {
    if (_currentContestId == null) {
      return Stream.value({});
    }
    return _firebaseService.watchAudienceByCountry(_currentContestId!, entryId);
  }

  Stream<List<ReviewModel>> getReviews(String entryId) {
    if (_currentContestId == null) {
      return Stream.value([]);
    }
    return _firebaseService.getReviews(_currentContestId!, entryId);
  }

  Future<bool> addReview(String entryId, int ratingStars, String reviewText) async {
    if (_currentContestId != null) {
      final profile = _currentUserProfile;
      final review = ReviewModel(
        id: '',
        userId: currentUserId,
        userName: profile?.displayName ?? 'You',
        userAvatar: profile?.photoURL ?? 'https://i.pravatar.cc/150?u=99',
        ratingStars: ratingStars,
        reviewText: reviewText,
        timestamp: DateTime.now(),
      );
      return await _firebaseService.addReview(_currentContestId!, entryId, review);
    }
    return false;
  }

  Future<bool> toggleFollowContest() async {
    if (_currentContestId != null) {
      return await _firebaseService.toggleFollowContest(_currentContestId!, currentUserId);
    }
    return false;
  }

  Stream<bool> isFollowingContest() {
    if (_currentContestId == null) return Stream.value(false);
    return _firebaseService.isFollowingContest(_currentContestId!, currentUserId);
  }

  Stream<List<CoHostInvite>> watchPendingCoHostInvites() {
    return _liveSessionService.watchPendingInvitesForUser(currentUserId);
  }

  Stream<Map<String, dynamic>?> watchLiveSession(String entryId) {
    if (_currentContestId == null) return Stream.value(null);
    return _liveSessionService.watchLiveSession(_currentContestId!, entryId);
  }

  Future<bool> sendCoHostInvite({
    required String entryId,
    required String inviteeUserId,
    required String inviteeName,
    required String inviteeAvatar,
  }) async {
    if (_currentContestId == null) return false;
    final host = _currentUserProfile;
    final id = await _liveSessionService.sendCoHostInvite(
      contestId: _currentContestId!,
      entryId: entryId,
      channelId: entryId,
      hostUserId: currentUserId,
      hostName: host?.displayName ?? 'Organizer',
      hostAvatar: host?.photoURL ?? '',
      inviteeUserId: inviteeUserId,
      inviteeName: inviteeName,
      inviteeAvatar: inviteeAvatar,
    );
    return id != null;
  }

  Future<bool> acceptCoHostInvite(CoHostInvite invite) {
    return _liveSessionService.acceptCoHostInvite(invite);
  }

  Future<void> declineCoHostInvite(String inviteId) {
    return _liveSessionService.declineCoHostInvite(inviteId);
  }

  Future<void> endCoHostSession(String entryId, {String? inviteId}) {
    if (_currentContestId == null) return Future.value();
    return _liveSessionService.endCoHostSession(
      contestId: _currentContestId!,
      entryId: entryId,
      inviteId: inviteId,
    );
  }

  @override
  void dispose() {
    _contestsSub?.cancel();
    _entriesSub?.cancel();
    _userSub?.cancel();
    _followedSub?.cancel();
    super.dispose();
  }
}
