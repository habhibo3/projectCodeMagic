import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/firebase_service.dart';
import '../data/live_session_service.dart';
import '../models/cohost_invite.dart';
import '../models/entry.dart';
import '../models/comment.dart';
import '../models/review.dart';
import '../models/user.dart';
import '../models/post.dart';
import '../models/notification.dart';

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

  // Maps to track active video uploads for the current user session
  final Map<String, String> _localVideoPaths = {};
  final Map<String, double> _uploadProgressMap = {};

  Map<String, String> get localVideoPaths => _localVideoPaths;
  Map<String, double> get uploadProgressMap => _uploadProgressMap;

  // --- Paginated Feed State ---
  final List<PostModel> _feedPosts = [];
  bool _isLoadingFeed = false;
  bool _hasMoreFeed = true;
  dynamic _lastFeedDocument;

  List<PostModel> get feedPosts => _feedPosts;
  bool get isLoadingFeed => _isLoadingFeed;
  bool get hasMoreFeed => _hasMoreFeed;

  Future<void> fetchNextFeedPage() async {
    if (_isLoadingFeed || !_hasMoreFeed) return;

    _isLoadingFeed = true;
    notifyListeners();

    try {
      const limit = 10;
      final results = await _firebaseService.getPostsQueryPaginated(
        limit: limit,
        startAfter: _lastFeedDocument,
      );

      if (results.isEmpty) {
        _hasMoreFeed = false;
      } else {
        _lastFeedDocument = results.last;
        final List<PostModel> newPosts = results.map((item) {
          if (item is PostModel) {
            return item;
          } else {
            return PostModel.fromFirestore(item as DocumentSnapshot);
          }
        }).toList();

        for (final post in newPosts) {
          if (!_feedPosts.any((p) => p.id == post.id)) {
            _feedPosts.add(post);
          }
        }

        if (results.length < limit) {
          _hasMoreFeed = false;
        }
      }
    } catch (e) {
      debugPrint('Error fetching next feed page: $e');
    } finally {
      _isLoadingFeed = false;
      notifyListeners();
    }
  }

  Future<void> refreshFeed() async {
    _feedPosts.clear();
    _hasMoreFeed = true;
    _lastFeedDocument = null;
    notifyListeners();
    await fetchNextFeedPage();
  }

  void setLocalVideoPath(String postId, String path) {
    _localVideoPaths[postId] = path;
    notifyListeners();
  }

  void setUploadProgress(String postId, double progress) {
    _uploadProgressMap[postId] = progress;
    notifyListeners();
  }

  void clearUploadTask(String postId) {
    _localVideoPaths.remove(postId);
    _uploadProgressMap.remove(postId);
    notifyListeners();
  }

  StreamSubscription? _contestsSub;
  StreamSubscription? _entriesSub;
  StreamSubscription? _userSub;
  StreamSubscription? _followedSub;

  String? _currentContestId;
  String? _lastViewedEntryId;

  bool _isSimulationActive = false;
  Timer? _simulationTimer;
  final List<Timer> _activeTimers = [];

  RankingEngine({required this.currentUserId}) {
    _listenToContests();
    _listenToCurrentUser();
    fetchNextFeedPage();
  }

  bool get isSimulationActive => _isSimulationActive;

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

  void setCurrentContest(String contestId) {
    _currentContestId = contestId;
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
        final voterName = _currentUserProfile?.displayName ?? 'A viewer';
        _voteActivity.insert(0, VoteActivity(
          userName: 'You',
          countryFlag: voterFlag,
          comment: 'You voted!',
          time: DateTime.now(),
        ));
        if (_voteActivity.length > 20) _voteActivity.removeLast();
        notifyListeners();

        // 1. Schedule client-mediated sliding window decrement
        final contestId = _currentContestId!;
        final timer = Timer(const Duration(seconds: 10), () async {
          await _firebaseService.decrementWindowVote(contestId, entryId);
        });
        _activeTimers.add(timer);

        // 2. Add real-time activity alert to Firestore
        final entryIndex = _entries.indexWhere((e) => e.id == entryId);
        final entryName = entryIndex != -1 ? _entries[entryIndex].userName : 'Contestant';
        final notify = NotificationModel(
          id: '',
          title: 'New Vote!',
          message: '$voterName voted for $entryName\'s entry!',
          type: 'vote',
          timestamp: DateTime.now(),
          senderName: voterName,
          senderAvatar: _currentUserProfile?.photoURL ?? 'https://i.pravatar.cc/150?u=99',
        );
        _firebaseService.sendNotification(notify);
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

  Future<void> uploadMyProfilePhoto(File file) async {
    final downloadUrl = await _firebaseService.uploadProfilePhoto(currentUserId, file);
    if (downloadUrl.isNotEmpty) {
      final profile = _currentUserProfile;
      if (profile != null) {
        await _firebaseService.syncPostUserProfile(
          currentUserId,
          displayName: profile.displayName,
          photoURL: downloadUrl,
        );
      }
      if (_currentContestId != null && profile != null) {
        await _firebaseService.syncEntryUserProfile(
          _currentContestId!,
          currentUserId,
          displayName: profile.displayName,
          photoURL: downloadUrl,
          countryFlag: profile.countryFlag,
          zip: profile.zip,
          city: profile.city,
          state: profile.state,
          country: profile.country,
        );
      }
      // Update local profile state
      if (_currentUserProfile != null) {
        _currentUserProfile = UserModel(
          uid: _currentUserProfile!.uid,
          displayName: _currentUserProfile!.displayName,
          email: _currentUserProfile!.email,
          photoURL: downloadUrl,
          role: _currentUserProfile!.role,
          country: _currentUserProfile!.country,
          countryFlag: _currentUserProfile!.countryFlag,
          bio: _currentUserProfile!.bio,
          createdAt: _currentUserProfile!.createdAt,
          totalVotesCast: _currentUserProfile!.totalVotesCast,
          subscriptionLevel: _currentUserProfile!.subscriptionLevel,
          zip: _currentUserProfile!.zip,
          city: _currentUserProfile!.city,
          state: _currentUserProfile!.state,
          location: _currentUserProfile!.location,
        );
        notifyListeners();
      }
    }
  }

  Future<String> uploadPostMedia(File file, {void Function(double progress)? onProgress}) async {
    return await _firebaseService.uploadPostMedia(currentUserId, file, onProgress: onProgress);
  }

  Future<void> updateMyDisplayName(String displayName) async {
    await _firebaseService.updateUserDisplayName(currentUserId, displayName);
    final profile = _currentUserProfile;
    if (profile != null) {
      await _firebaseService.syncPostUserProfile(
        currentUserId,
        displayName: displayName.trim(),
        photoURL: profile.photoURL,
      );
    }
    if (_currentContestId != null && profile != null) {
      await _firebaseService.syncEntryUserProfile(
        _currentContestId!,
        currentUserId,
        displayName: displayName.trim(),
        photoURL: profile.photoURL,
        countryFlag: profile.countryFlag,
        zip: profile.zip,
        city: profile.city,
        state: profile.state,
        country: profile.country,
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
        zip: profile.zip,
        city: profile.city,
        state: profile.state,
        country: country,
      );
    }
    if (_lastViewedEntryId != null) {
      trackEntryView(_lastViewedEntryId!);
    }
  }

  Future<void> updateMyLocation({
    required String zip,
    required String city,
    required String state,
    required String country,
    required String countryFlag,
  }) async {
    await _firebaseService.updateUserLocation(
      uid: currentUserId,
      zip: zip,
      city: city,
      state: state,
      country: country,
      countryFlag: countryFlag,
    );
    final profile = _currentUserProfile;
    if (_currentContestId != null && profile != null) {
      await _firebaseService.syncEntryUserProfile(
        _currentContestId!,
        currentUserId,
        displayName: profile.displayName,
        photoURL: profile.photoURL,
        countryFlag: countryFlag,
        zip: zip.trim(),
        city: city.trim(),
        state: state.trim(),
        country: country.trim(),
      );
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

  Stream<List<PostModel>> getMyPosts() {
    return _firebaseService.getUserPosts(currentUserId);
  }

  Future<bool> assignPostToContest(String postId, String contestId) async {
    final success = await _firebaseService.assignPostToContest(postId, contestId);
    if (success) {
      final profile = _currentUserProfile;
      final notify = NotificationModel(
        id: '',
        title: 'User Joined Contest',
        message: '${profile?.displayName ?? 'A contestant'} joined the contest with an existing post!',
        type: 'join',
        timestamp: DateTime.now(),
        senderName: profile?.displayName ?? 'Contestant',
        senderAvatar: profile?.photoURL ?? 'https://i.pravatar.cc/150?u=99',
      );
      await _firebaseService.sendNotification(notify);
      loadContestEntries(contestId);
    }
    return success;
  }

  Future<String> createPost({
    required String type,
    required String contentUrl,
    required String caption,
    required String visibilityScope,
  }) async {
    final profile = _currentUserProfile;
    final postId = 'post_${DateTime.now().millisecondsSinceEpoch}';
    final location = profile?.location ?? '${profile?.city}, ${profile?.country}';
    final post = PostModel(
      id: postId,
      userId: currentUserId,
      userName: profile?.displayName ?? 'Anonymous',
      userAvatar: profile?.photoURL ?? 'https://i.pravatar.cc/150?u=99',
      type: type,
      contentUrl: contentUrl,
      caption: caption,
      visibilityScope: visibilityScope,
      location: location,
      createdAt: DateTime.now(),
    );

    await _firebaseService.createPost(post);

    if (!_feedPosts.any((p) => p.id == postId)) {
      _feedPosts.insert(0, post);
      notifyListeners();
    }

    return postId;
  }

  Future<void> createPostAndJoinContest({
    required String type,
    required String contentUrl,
    required String caption,
    required String visibilityScope,
    required String? contestId,
  }) async {
    final profile = _currentUserProfile;
    final postId = 'post_${DateTime.now().millisecondsSinceEpoch}';
    final location = profile?.location ?? '${profile?.city}, ${profile?.country}';
    final post = PostModel(
      id: postId,
      userId: currentUserId,
      userName: profile?.displayName ?? 'Anonymous Contestant',
      userAvatar: profile?.photoURL ?? 'https://i.pravatar.cc/150?u=99',
      type: type,
      contentUrl: contentUrl,
      caption: caption,
      visibilityScope: visibilityScope,
      location: location,
      createdAt: DateTime.now(),
      contestId: contestId,
    );

    await _firebaseService.createPostAndJoinContest(post, contestId);

    if (!_feedPosts.any((p) => p.id == postId)) {
      _feedPosts.insert(0, post);
      notifyListeners();
    }

    // Publish join notification
    final notify = NotificationModel(
      id: '',
      title: 'New Entry Joined!',
      message: '${profile?.displayName ?? 'A contestant'} joined the contest with a new $type post!',
      type: 'join',
      timestamp: DateTime.now(),
      senderName: profile?.displayName ?? 'Contestant',
      senderAvatar: profile?.photoURL ?? 'https://i.pravatar.cc/150?u=99',
    );
    await _firebaseService.sendNotification(notify);
  }

  Future<void> deletePost(String postId) async {
    await _firebaseService.deletePost(postId);
    _feedPosts.removeWhere((p) => p.id == postId);
    notifyListeners();
  }

  Future<void> updatePost(String postId, {
    String? type,
    String? contentUrl,
    String? caption,
    String? visibilityScope,
    String? location,
  }) async {
    final updates = <String, dynamic>{};
    if (type != null) updates['type'] = type;
    if (contentUrl != null) updates['contentUrl'] = contentUrl;
    if (caption != null) updates['caption'] = caption;
    if (visibilityScope != null) updates['visibilityScope'] = visibilityScope;
    if (location != null) updates['location'] = location;
    await _firebaseService.updatePost(postId, updates);

    final index = _feedPosts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      _feedPosts[index] = _feedPosts[index].copyWith(
        type: type,
        contentUrl: contentUrl,
        caption: caption,
        visibilityScope: visibilityScope,
        location: location,
      );
      notifyListeners();
    }
  }

  Future<void> createContest(ContestModel contest) async {
    await _firebaseService.createContest(contest);
  }

  Stream<List<ContestEntry>> watchGlobalFeed() {
    return _firebaseService.watchGlobalFeedEntries();
  }

  Stream<List<NotificationModel>> watchNotifications() {
    return _firebaseService.watchNotifications();
  }

  Stream<List<PostModel>> watchAllPosts() {
    return _firebaseService.getAllPosts();
  }

  Future<void> toggleLikePost(String postId) async {
    final index = _feedPosts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      final post = _feedPosts[index];
      final updatedLikes = List<String>.from(post.likes);
      if (updatedLikes.contains(currentUserId)) {
        updatedLikes.remove(currentUserId);
      } else {
        updatedLikes.add(currentUserId);
      }
      _feedPosts[index] = post.copyWith(likes: updatedLikes);
      notifyListeners();
    }
    await _firebaseService.toggleLikePost(postId, currentUserId);
  }

  Stream<List<CommentModel>> getPostComments(String postId) {
    return _firebaseService.getPostComments(postId);
  }

  Future<void> addPostComment(String postId, String text) async {
    final profile = _currentUserProfile;
    final comment = CommentModel(
      id: '',
      userId: currentUserId,
      userName: profile?.displayName ?? 'You',
      userAvatar: profile?.photoURL ?? '',
      text: text,
      timestamp: DateTime.now(),
    );
    await _firebaseService.addPostComment(postId, comment);

    final index = _feedPosts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      _feedPosts[index] = _feedPosts[index].copyWith(
        commentsCount: _feedPosts[index].commentsCount + 1,
      );
      notifyListeners();
    }
  }

  Stream<PostModel?> getPostStream(String postId) {
    return _firebaseService.getPostStream(postId);
  }

  Stream<UserModel?> watchUserProfile(String userId) {
    return _firebaseService.getUserProfile(userId);
  }

  Stream<List<PostModel>> getUserPosts(String userId) {
    return _firebaseService.getUserPosts(userId);
  }

  // -------------------------------------------------------------------------
  // INTERACTIVE BACKGROUND TRAFFIC SIMULATOR
  // -------------------------------------------------------------------------
  void toggleSimulation(bool isActive) {
    _isSimulationActive = isActive;
    _simulationTimer?.cancel();
    notifyListeners();

    if (_isSimulationActive) {
      _simulationTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
        if (_currentContestId == null || _entries.isEmpty) return;

        // Choose a random entry to vote on
        final randomIndex = math.Random().nextInt(_entries.length);
        final entry = _entries[randomIndex];

        // Choose a random seeder user ID
        final mockUserIds = ['u1', 'u2', 'u3', 'u4', 'u5'];
        final randomUserIndex = math.Random().nextInt(mockUserIds.length);
        final mockUserId = mockUserIds[randomUserIndex];

        // Fetch user flag & name
        final profileInfo = await _firebaseService.getUserGeoProfile(mockUserId);

        final success = await _firebaseService.addVote(
          _currentContestId!,
          entry.id,
          mockUserId,
        );

        if (success) {
          final contestId = _currentContestId!;
          final entryId = entry.id;
          final mockTimer = Timer(const Duration(seconds: 10), () async {
            await _firebaseService.decrementWindowVote(contestId, entryId);
          });
          _activeTimers.add(mockTimer);

          // Stream notification
          final notify = NotificationModel(
            id: '',
            title: 'New Vote!',
            message: '${profileInfo.displayName} voted for ${entry.userName}\'s entry!',
            type: 'vote',
            timestamp: DateTime.now(),
            senderName: profileInfo.displayName,
            senderAvatar: 'https://i.pravatar.cc/150?u=$mockUserId',
          );
          await _firebaseService.sendNotification(notify);
        }
      });
    }
  }

  @override
  void dispose() {
    _contestsSub?.cancel();
    _entriesSub?.cancel();
    _userSub?.cancel();
    _followedSub?.cancel();
    _simulationTimer?.cancel();
    for (final timer in _activeTimers) {
      timer.cancel();
    }
    super.dispose();
  }
}
