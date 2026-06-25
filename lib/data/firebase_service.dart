import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/entry.dart';
import '../models/comment.dart';
import '../models/review.dart';
import '../models/user.dart';
import '../models/post.dart';
import '../models/notification.dart';
import 'mock_data.dart';
import '../utils/web_blob_reader.dart';
import 'cache_service.dart';


class FirebaseService {
  FirebaseFirestore? _db;
  bool _isInitialized = false;
  final CacheService _cache = CacheService();

  static UserModel? _mockUserProfile;
  static final StreamController<UserModel?> _mockUserStreamController = StreamController<UserModel?>.broadcast();
  static final List<PostModel> _mockPosts = [];
  static final StreamController<List<PostModel>> _mockPostsStreamController = StreamController<List<PostModel>>.broadcast();
  static final Map<String, List<CommentModel>> _mockPostComments = {};
  static final StreamController<Map<String, List<CommentModel>>> _mockPostCommentsStreamController = StreamController<Map<String, List<CommentModel>>>.broadcast();

  FirebaseService() {
    try {
      _db = FirebaseFirestore.instance;
      _isInitialized = true;
    } catch (e) {
      debugPrint('Firebase not initialized. Falling back to mock data: $e');
      _isInitialized = false;
    }
    
    // Clear expired cache entries periodically
    Timer.periodic(const Duration(minutes: 30), (_) {
      _cache.clearExpired();
    });
  }

  // -------------------------------------------------------------------------
  // CONTESTS
  // -------------------------------------------------------------------------
  Stream<List<ContestModel>> getContests() {
    if (!_isInitialized || _db == null) {
      return Stream.value(MockData.getContests());
    }

    final cacheKey = 'contests';
    final cached = _cache.get<List<ContestModel>>(cacheKey);
    
    return _db!.collection('contests').snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) return MockData.getContests();
      
      final contests = snapshot.docs.map((doc) {
        final data = doc.data();
        return ContestModel(
          id: doc.id,
          title: data['title'] ?? '',
          subtitle: data['subtitle'] ?? '',
          description: data['description'] ?? '',
          rules: data['rules'] ?? '',
          prize: data['prize'] ?? '',
          schedule: data['schedule'] ?? '',
          image: data['image'] ?? '',
          category: data['category'] ?? '',
          type: data['type'] ?? '',
          participantCount: data['participantCount'] ?? 0,
          totalVotes: data['totalVotes'] ?? 0,
          rating: (data['rating'] ?? 0.0).toDouble(),
          reviewCount: data['reviewCount'] ?? 0,
          endsIn: data['endsIn'] ?? '',
          endDate: data['endDate'] != null ? DateTime.parse(data['endDate']) : null,
          creatorId: data['creatorId'] ?? '',
          city: data['city'] ?? '',
          country: data['country'] ?? '',
          latitude: data['latitude']?.toDouble(),
          longitude: data['longitude']?.toDouble(),
          visibilityScope: data['visibilityScope'] ?? 'global',
        );
      }).toList();
      
      // Cache with 5-minute TTL
      _cache.set(cacheKey, contests, ttl: const Duration(minutes: 5));
      return contests;
    });
  }

  // -------------------------------------------------------------------------
  // ENTRIES
  // -------------------------------------------------------------------------
  Stream<List<ContestEntry>> getEntries(String contestId) {
    if (!_isInitialized || _db == null) {
      return Stream.value([]);
    }

    final cacheKey = 'entries_$contestId';

    return _db!
        .collection('contests')
        .doc(contestId)
        .collection('entries')
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return [];

      final entries = snapshot.docs.map((doc) {
        final data = doc.data();

        // Provide fallback URLs to prevent NetworkImage crash
        final avatar = data['userAvatar']?.toString() ?? '';
        final content = data['contentUrl']?.toString() ?? '';

        final reviewCount = (data['reviewCount'] ?? 0) as int;
        final totalStars = (data['totalStars'] ?? 0) as int;
        double averageRating = 0;
        if (reviewCount > 0) {
          averageRating = totalStars / reviewCount;
        } else {
          averageRating =
              ((data['averageRating'] ?? data['rating'] ?? 0) as num).toDouble();
        }

        return ContestEntry(
          id: doc.id,
          userId: data['userId'] ?? '',
          userName: data['userName'] ?? 'Anonymous',
          userAvatar: avatar.isEmpty ? 'https://i.pravatar.cc/150?u=99' : avatar,
          countryFlag: data['countryFlag'] ?? '🏠',
          contentUrl: content.isEmpty ? 'https://images.unsplash.com/photo-1516280440614-37939bbacd81' : content,
          type: data['type'] ?? 'image',
          caption: data['caption'] ?? '',
          totalVotes: data['totalVotes'] ?? 0,
          windowVotes: data['windowVotes'] ?? 0,
          ratingStars: averageRating.round().clamp(0, 5),
          averageRating: averageRating,
          reviewCount: reviewCount,
          visibilityScope: data['visibilityScope'] ?? 'global',
          zip: data['zip'] ?? '75001',
          city: data['city'] ?? 'Tunis',
          state: data['state'] ?? 'Tunis State',
          country: data['country'] ?? 'Tunisia',
          contestType: data['contestType'] ?? 'Official',
          contestId: data['contestId'] ?? contestId,
        );
      }).toList();
      
      // Sort locally to avoid Firebase composite index requirement
      entries.sort((a, b) {
        int cmp = b.windowVotes.compareTo(a.windowVotes);
        if (cmp == 0) return b.totalVotes.compareTo(a.totalVotes);
        return cmp;
      });
      
      // Cache with 2-minute TTL for entries (more frequent updates)
      _cache.set(cacheKey, entries, ttl: const Duration(minutes: 2));
      return entries;
    });
  }

  // -------------------------------------------------------------------------
  // VOTING WITH RELATIONAL CONSTRAINTS & LOGIC
  // -------------------------------------------------------------------------
  Future<bool> addVote(String contestId, String entryId, String voterId) async {
    if (!_isInitialized || _db == null) return true; // Simulation success

    final entryRef = _db!.collection('contests').doc(contestId).collection('entries').doc(entryId);
    final userRef = _db!.collection('users').doc(voterId);
    final voteRef = entryRef.collection('votes').doc(voterId);

    try {
      final voteAttempt = await _db!.runTransaction((transaction) async {
        final voteSnap = await transaction.get(voteRef);
        
        // Relational check: If voter document already exists, they already voted!
        if (voteSnap.exists) {
          return false; // Indicate double-voting limit hit
        }

        final entrySnap = await transaction.get(entryRef);
        final userSnap = await transaction.get(userRef);
        final contestRef = _db!.collection('contests').doc(contestId);
        final contestSnap = await transaction.get(contestRef);

        if (!entrySnap.exists) return false;

        // Prevent contest creator from voting on their own contest
        if (contestSnap.exists) {
          final creatorId = contestSnap.data()?['creatorId'] as String?;
          if (creatorId == voterId) {
            return false; // Creator cannot vote on their own contest
          }
        }

        final currentTotal = entrySnap.data()?['totalVotes'] ?? 0;
        final currentWindow = entrySnap.data()?['windowVotes'] ?? 0;

        // Save vote log with voter geo (audience country, not performer country)
        final voterCountryFlag =
            (userSnap.data()?['countryFlag'] as String?) ?? '🌍';
        final voterCountry =
            (userSnap.data()?['country'] as String?) ?? 'Other';

        transaction.set(voteRef, {
          'votedAt': FieldValue.serverTimestamp(),
          'voterId': voterId,
          'countryFlag': voterCountryFlag,
          'country': voterCountry,
        });

        // Increment entry's public vote count
        transaction.update(entryRef, {
          'totalVotes': currentTotal + 1,
          'windowVotes': currentWindow + 1,
        });

        // Relational sync: Increment contest's total votes count
        if (contestSnap.exists) {
          final currentContestVotes = contestSnap.data()?['totalVotes'] ?? 0;
          transaction.update(contestRef, {
            'totalVotes': currentContestVotes + 1,
          });
        }

        // Relational sync: Increment voter's lifetime votes cast count
        if (userSnap.exists) {
          final currentVotesCast = userSnap.data()?['totalVotesCast'] ?? 0;
          transaction.update(userRef, {
            'totalVotesCast': currentVotesCast + 1,
          });
        }

        return true;
      });

      return voteAttempt;
    } catch (e) {
      debugPrint('Failed relational addVote transaction: $e');
      return false;
    }
  }

  /// Demo contestant ids from seed data — never used for live audience geo.
  static const Set<String> demoUserIds = {'u1', 'u2', 'u3', 'u4', 'u5', 'current_user'};

  /// Reads the latest country from the user's Firestore profile (real data).
  Future<({String country, String countryFlag, String displayName})>
      getUserGeoProfile(String userId) async {
    if (!_isInitialized || _db == null) {
      return (country: 'Other', countryFlag: '🌍', displayName: 'Viewer');
    }
    final snap = await _db!.collection('users').doc(userId).get();
    if (!snap.exists) {
      return (country: 'Other', countryFlag: '🌍', displayName: 'Viewer');
    }
    final data = snap.data()!;
    final country = (data['country'] as String?)?.trim();
    final flag = data['countryFlag'] as String? ?? '🌍';
    return (
      country: (country != null && country.isNotEmpty)
          ? country
          : _countryNameFromFlag(flag),
      countryFlag: flag,
      displayName: (data['displayName'] as String?)?.trim() ?? 'Viewer',
    );
  }

  /// Records who is watching — always writes fresh geo from the user profile doc.
  Future<void> trackAudiencePresence(
    String contestId,
    String entryId,
    String userId,
  ) async {
    if (!_isInitialized || _db == null) return;
    if (demoUserIds.contains(userId)) return;

    try {
      final profile = await getUserGeoProfile(userId);
      await _db!
          .collection('contests')
          .doc(contestId)
          .collection('entries')
          .doc(entryId)
          .collection('audience')
          .doc(userId)
          .set({
        'country': profile.country,
        'countryFlag': profile.countryFlag,
        'displayName': profile.displayName,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to track audience: $e');
    }
  }

  /// Live audience geo for a single entry (who is watching, not performer country).
  Stream<Map<String, int>> watchAudienceByCountry(
      String contestId, String entryId) {
    if (!_isInitialized || _db == null) {
      return Stream.value({});
    }

    return _db!
        .collection('contests')
        .doc(contestId)
        .collection('entries')
        .doc(entryId)
        .collection('audience')
        .snapshots()
        .asyncMap((snapshot) async {
      final counts = <String, int>{};
      for (final doc in snapshot.docs) {
        if (demoUserIds.contains(doc.id)) continue;
        // Always resolve from live user profile — never stale/mock audience rows.
        final profile = await getUserGeoProfile(doc.id);
        counts[profile.country] = (counts[profile.country] ?? 0) + 1;
      }
      return counts;
    });
  }

  String _countryNameFromFlag(String flag) {
    const flagMap = {
      '🇺🇸': 'United States',
      '🇻🇳': 'Vietnam',
      '🇨🇳': 'China',
      '🇫🇷': 'France',
      '🇯🇵': 'Japan',
      '🇹🇳': 'Tunisia',
      '🇬🇧': 'United Kingdom',
      '🇪🇸': 'Spain',
      '🇩🇪': 'Germany',
      '🇮🇹': 'Italy',
      '🇧🇷': 'Brazil',
      '🇮🇳': 'India',
      '🇰🇷': 'South Korea',
      '🇲🇽': 'Mexico',
      '🇷🇺': 'Russia',
      '🇨🇦': 'Canada',
      '🇳🇬': 'Nigeria',
      '🇪🇬': 'Egypt',
      '🇸🇦': 'Saudi Arabia',
      '🇦🇪': 'UAE',
      '🇲🇦': 'Morocco',
      '🇩🇿': 'Algeria',
      '🇹🇷': 'Turkey',
      '🇵🇭': 'Philippines',
      '🇮🇩': 'Indonesia',
      '🇹🇭': 'Thailand',
      '🇿🇦': 'South Africa',
      '🇱🇧': 'Lebanon',
      '🏠': 'Other',
      '🌍': 'Other',
    };
    return flagMap[flag] ?? 'Other';
  }

  // -------------------------------------------------------------------------
  // USERS & RELATIONS
  // -------------------------------------------------------------------------
  /// Creates a Firestore profile for this device uid on first launch.
  Future<void> ensureUserProfile(String uid) async {
    if (!_isInitialized || _db == null) return;

    final ref = _db!.collection('users').doc(uid);
    final snap = await ref.get();
    if (snap.exists) return;

    const defaultCountry = 'Tunisia';
    const defaultFlag = '🇹🇳';

    await ref.set({
      'displayName': 'Mlivecast Player',
      'email': '',
      'photoURL': '',
      'role': 'contestant',
      'country': defaultCountry,
      'countryFlag': defaultFlag,
      'bio': '',
      'createdAt': FieldValue.serverTimestamp(),
      'totalVotesCast': 0,
      'subscriptionLevel': 'free',
      'zip': '75001',
      'city': 'Tunis',
      'state': 'Tunis State',
      'location': 'Tunis, Tunisia',
    });
  }

  Future<String> uploadProfilePhoto(String uid, File file) async {
    if (!_isInitialized || _db == null) {
      final path = file.path;
      if (_mockUserProfile != null) {
        _mockUserProfile = UserModel(
          uid: _mockUserProfile!.uid,
          displayName: _mockUserProfile!.displayName,
          email: _mockUserProfile!.email,
          photoURL: path,
          role: _mockUserProfile!.role,
          country: _mockUserProfile!.country,
          countryFlag: _mockUserProfile!.countryFlag,
          bio: _mockUserProfile!.bio,
          createdAt: _mockUserProfile!.createdAt,
          totalVotesCast: _mockUserProfile!.totalVotesCast,
          subscriptionLevel: _mockUserProfile!.subscriptionLevel,
          zip: _mockUserProfile!.zip,
          city: _mockUserProfile!.city,
          state: _mockUserProfile!.state,
          location: _mockUserProfile!.location,
        );
        _mockUserStreamController.add(_mockUserProfile);
      }
      return path;
    }
    try {
      final ref = firebase_storage.FirebaseStorage.instance
          .ref()
          .child('users')
          .child(uid)
          .child('profile.jpg');
      
      if (kIsWeb) {
        final bytes = await WebBlobReader.readBlobBytes(file.path);
        await ref.putData(bytes, firebase_storage.SettableMetadata(contentType: 'image/jpeg'));
      } else {
        await ref.putFile(file);
      }
      final downloadUrl = await ref.getDownloadURL();
      
      // Update user doc
      await _db!.collection('users').doc(uid).set({
        'photoURL': downloadUrl,
      }, SetOptions(merge: true));
      
      return downloadUrl;
    } catch (e) {
      debugPrint('Failed to upload profile photo to Firebase Storage: $e');
      debugPrint('Falling back to local file path');
      // Fallback: use local file path if Firebase Storage fails
      final localPath = file.path;
      await _db!.collection('users').doc(uid).set({
        'photoURL': localPath,
      }, SetOptions(merge: true));
      return localPath;
    }
  }

  Future<String> uploadPostMedia(
    String userId, 
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    if (!_isInitialized || _db == null) {
      if (onProgress != null) {
        for (int i = 0; i <= 10; i++) {
          await Future.delayed(const Duration(milliseconds: 150));
          onProgress(i / 10.0);
        }
      }
      return file.path;
    }
    try {
      final isVideo = file.path.endsWith('.mp4') || file.path.endsWith('.mov') || file.path.endsWith('.avi');
      final extension = isVideo ? 'mp4' : 'jpg';
      final fileName = 'post_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final ref = firebase_storage.FirebaseStorage.instance
          .ref()
          .child('users')
          .child(userId)
          .child('posts')
          .child(fileName);
      
      final firebase_storage.UploadTask uploadTask;
      if (kIsWeb) {
        final bytes = await WebBlobReader.readBlobBytes(file.path);
        final mimeType = isVideo ? 'video/mp4' : 'image/jpeg';
        uploadTask = ref.putData(bytes, firebase_storage.SettableMetadata(contentType: mimeType));
      } else {
        uploadTask = ref.putFile(file);
      }
      
      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((event) {
          if (event.totalBytes > 0) {
            final progress = event.bytesTransferred / event.totalBytes;
            onProgress(progress);
          }
        });
      }
      
      await uploadTask;
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Failed to upload post media to Firebase Storage: $e');
      debugPrint('Falling back to local file path');
      if (onProgress != null) {
        onProgress(1.0);
      }
      return file.path;
    }
  }

  Future<void> updateUserCountry(
      String uid, String country, String countryFlag) async {
    if (!_isInitialized || _db == null) {
      if (_mockUserProfile != null) {
        _mockUserProfile = UserModel(
          uid: _mockUserProfile!.uid,
          displayName: _mockUserProfile!.displayName,
          email: _mockUserProfile!.email,
          photoURL: _mockUserProfile!.photoURL,
          role: _mockUserProfile!.role,
          country: country,
          countryFlag: countryFlag,
          bio: _mockUserProfile!.bio,
          createdAt: _mockUserProfile!.createdAt,
          totalVotesCast: _mockUserProfile!.totalVotesCast,
          subscriptionLevel: _mockUserProfile!.subscriptionLevel,
          zip: _mockUserProfile!.zip,
          city: _mockUserProfile!.city,
          state: _mockUserProfile!.state,
          location: _mockUserProfile!.location,
        );
        _mockUserStreamController.add(_mockUserProfile);
      }
      return;
    }
    await _db!.collection('users').doc(uid).set({
      'country': country,
      'countryFlag': countryFlag,
    }, SetOptions(merge: true));
  }

  Future<void> updateUserLocation({
    required String uid,
    required String zip,
    required String city,
    required String state,
    required String country,
    required String countryFlag,
  }) async {
    if (!_isInitialized || _db == null) {
      if (_mockUserProfile != null) {
        _mockUserProfile = UserModel(
          uid: _mockUserProfile!.uid,
          displayName: _mockUserProfile!.displayName,
          email: _mockUserProfile!.email,
          photoURL: _mockUserProfile!.photoURL,
          role: _mockUserProfile!.role,
          country: country,
          countryFlag: countryFlag,
          bio: _mockUserProfile!.bio,
          createdAt: _mockUserProfile!.createdAt,
          totalVotesCast: _mockUserProfile!.totalVotesCast,
          subscriptionLevel: _mockUserProfile!.subscriptionLevel,
          zip: zip,
          city: city,
          state: state,
          location: '$city, $country',
        );
        _mockUserStreamController.add(_mockUserProfile);
      }
      return;
    }
    await _db!.collection('users').doc(uid).set({
      'zip': zip.trim(),
      'city': city.trim(),
      'state': state.trim(),
      'country': country.trim(),
      'countryFlag': countryFlag,
      'location': '${city.trim()}, ${country.trim()}',
    }, SetOptions(merge: true));
  }

  Future<void> updateUserDisplayName(String uid, String displayName) async {
    if (!_isInitialized || _db == null) {
      if (_mockUserProfile != null) {
        _mockUserProfile = UserModel(
          uid: _mockUserProfile!.uid,
          displayName: displayName,
          email: _mockUserProfile!.email,
          photoURL: _mockUserProfile!.photoURL,
          role: _mockUserProfile!.role,
          country: _mockUserProfile!.country,
          countryFlag: _mockUserProfile!.countryFlag,
          bio: _mockUserProfile!.bio,
          createdAt: _mockUserProfile!.createdAt,
          totalVotesCast: _mockUserProfile!.totalVotesCast,
          subscriptionLevel: _mockUserProfile!.subscriptionLevel,
          zip: _mockUserProfile!.zip,
          city: _mockUserProfile!.city,
          state: _mockUserProfile!.state,
          location: _mockUserProfile!.location,
        );
        _mockUserStreamController.add(_mockUserProfile);
      }
      return;
    }
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return;
    await _db!.collection('users').doc(uid).set({
      'displayName': trimmed,
    }, SetOptions(merge: true));
  }

  /// Keeps contest entry cards in sync with the user's real profile details.
  Future<void> syncEntryUserProfile(
    String contestId,
    String userId, {
    required String displayName,
    required String photoURL,
    required String countryFlag,
    required String zip,
    required String city,
    required String state,
    required String country,
  }) async {
    if (!_isInitialized || _db == null) return;
    final snap = await _db!
        .collection('contests')
        .doc(contestId)
        .collection('entries')
        .where('userId', isEqualTo: userId)
        .get();
    for (final doc in snap.docs) {
      await doc.reference.update({
        'userName': displayName,
        'userAvatar': photoURL,
        'countryFlag': countryFlag,
        'zip': zip,
        'city': city,
        'state': state,
        'country': country,
      });
    }
  }

  Future<void> syncPostUserProfile(
    String userId, {
    required String displayName,
    required String photoURL,
  }) async {
    if (!_isInitialized || _db == null) {
      for (int i = 0; i < _mockPosts.length; i++) {
        if (_mockPosts[i].userId == userId) {
          _mockPosts[i] = PostModel(
            id: _mockPosts[i].id,
            userId: _mockPosts[i].userId,
            userName: displayName,
            userAvatar: photoURL,
            type: _mockPosts[i].type,
            contentUrl: _mockPosts[i].contentUrl,
            caption: _mockPosts[i].caption,
            visibilityScope: _mockPosts[i].visibilityScope,
            location: _mockPosts[i].location,
            createdAt: _mockPosts[i].createdAt,
            contestId: _mockPosts[i].contestId,
            likes: _mockPosts[i].likes,
            commentsCount: _mockPosts[i].commentsCount,
          );
        }
      }
      _mockPostsStreamController.add(List.from(_mockPosts));
      return;
    }
    try {
      final snap = await _db!
          .collection('posts')
          .where('userId', isEqualTo: userId)
          .get();
      for (final doc in snap.docs) {
        await doc.reference.update({
          'userName': displayName,
          'userAvatar': photoURL,
        });
      }
    } catch (e) {
      debugPrint('Failed to sync post user profile: $e');
    }
  }

  Stream<UserModel?> getUserProfile(String userId) async* {
    if (!_isInitialized || _db == null) {
      if (_mockUserProfile == null) {
        _mockUserProfile = UserModel(
          uid: userId,
          displayName: 'James USA',
          email: 'james@mlivecast.com',
          photoURL: '',
          role: 'contestant',
          country: 'United States',
          countryFlag: '🇺🇸',
          bio: 'Mlivecast regular performer.',
          createdAt: DateTime.now(),
          totalVotesCast: 120,
        );
      }
      yield _mockUserProfile;
      yield* _mockUserStreamController.stream;
      return;
    }

    final cacheKey = 'user_$userId';
    final cached = _cache.get<UserModel>(cacheKey);
    if (cached != null) {
      yield cached;
    }

    yield* _db!.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      final user = UserModel.fromFirestore(doc);
      // Cache user profiles with 10-minute TTL
      _cache.set(cacheKey, user, ttl: const Duration(minutes: 10));
      return user;
    });
  }

  // -------------------------------------------------------------------------
  // ADD ENTRY
  // -------------------------------------------------------------------------
  Future<void> addEntry(String contestId, ContestEntry entry) async {
    if (!_isInitialized || _db == null) return;

    final entryRef = _db!.collection('contests').doc(contestId).collection('entries').doc(entry.id);
    try {
      await _db!.runTransaction((transaction) async {
        final contestRef = _db!.collection('contests').doc(contestId);
        final contestSnap = await transaction.get(contestRef);

        transaction.set(entryRef, {
          'userId': entry.userId,
          'userName': entry.userName,
          'userAvatar': entry.userAvatar,
          'countryFlag': entry.countryFlag,
          'contentUrl': entry.contentUrl,
          'type': entry.type,
          'caption': entry.caption,
          'totalVotes': entry.totalVotes,
          'windowVotes': entry.windowVotes,
          'ratingStars': entry.ratingStars,
          'averageRating': entry.averageRating,
          'reviewCount': entry.reviewCount,
          'totalStars': 0,
        });

        // Update contest participant count
        if (contestSnap.exists) {
          final currentParticipants = contestSnap.data()?['participantCount'] ?? 0;
          transaction.update(contestRef, {
            'participantCount': currentParticipants + 1,
          });
        }
      });
    } catch (e) {
      debugPrint('Failed to add entry: $e');
    }
  }

  // -------------------------------------------------------------------------
  // FOLLOW SYSTEM
  // -------------------------------------------------------------------------
  Future<bool> toggleFollowContest(String contestId, String userId) async {
    if (!_isInitialized || _db == null) return true;

    final followRef = _db!.collection('users').doc(userId).collection('following').doc(contestId);
    
    try {
      final snap = await followRef.get();
      if (snap.exists) {
        await followRef.delete();
        return false; // Now unfollowed
      } else {
        await followRef.set({'followedAt': FieldValue.serverTimestamp()});
        return true; // Now followed
      }
    } catch (e) {
      debugPrint('Failed to toggle follow: $e');
      return false;
    }
  }

  Stream<bool> isFollowingContest(String contestId, String userId) {
    if (!_isInitialized || _db == null) return Stream.value(false);

    return _db!.collection('users').doc(userId).collection('following').doc(contestId).snapshots().map((doc) {
      return doc.exists;
    });
  }

  Stream<List<String>> getFollowedContests(String userId) {
    if (!_isInitialized || _db == null) return Stream.value([]);

    return _db!.collection('users').doc(userId).collection('following').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => doc.id).toList();
    });
  }

  // -------------------------------------------------------------------------
  // COMMENTS
  // -------------------------------------------------------------------------
  Stream<List<CommentModel>> getComments(String contestId, String entryId) {
    if (!_isInitialized || _db == null) {
      return Stream.value([
        CommentModel(
          id: 'mock_c1',
          userId: 'user1',
          userName: 'Sara K.',
          userAvatar: 'https://i.pravatar.cc/150?u=1',
          text: 'Incredible performance!',
          timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        CommentModel(
          id: 'mock_c2',
          userId: 'user2',
          userName: 'Mike D.',
          userAvatar: 'https://i.pravatar.cc/150?u=2',
          text: 'You have my vote! 🌟',
          timestamp: DateTime.now().subtract(const Duration(hours: 5)),
        ),
      ]);
    }

    return _db!
        .collection('contests')
        .doc(contestId)
        .collection('entries')
        .doc(entryId)
        .collection('comments')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => CommentModel.fromFirestore(doc)).toList();
    });
  }

  Future<void> addComment(String contestId, String entryId, CommentModel comment) async {
    if (!_isInitialized || _db == null) return;

    try {
      await _db!
          .collection('contests')
          .doc(contestId)
          .collection('entries')
          .doc(entryId)
          .collection('comments')
          .add(comment.toMap());
    } catch (e) {
      debugPrint('Failed to add comment: $e');
    }
  }

  // -------------------------------------------------------------------------
  // REVIEWS & RATINGS (Atomic Transactions)
  // -------------------------------------------------------------------------
  Stream<List<ReviewModel>> getReviews(String contestId, String entryId) {
    if (!_isInitialized || _db == null) {
      return Stream.value([]);
    }

    return _db!
        .collection('contests')
        .doc(contestId)
        .collection('entries')
        .doc(entryId)
        .collection('reviews')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => ReviewModel.fromFirestore(doc)).toList();
    });
  }

  Future<bool> addReview(String contestId, String entryId, ReviewModel review) async {
    if (!_isInitialized || _db == null) return true; // Simulation success

    final entryRef = _db!.collection('contests').doc(contestId).collection('entries').doc(entryId);
    final reviewRef = entryRef.collection('reviews').doc(review.userId);

    try {
      final success = await _db!.runTransaction((transaction) async {
        final reviewSnap = await transaction.get(reviewRef);
        if (reviewSnap.exists) {
          return false; // User already reviewed
        }

        final entrySnap = await transaction.get(entryRef);
        if (!entrySnap.exists) return false;
        
        final contestRef = _db!.collection('contests').doc(contestId);
        final contestSnap = await transaction.get(contestRef);

        final currentTotalStars = (entrySnap.data()?['totalStars'] ?? 0) as int;
        final currentReviewCount = (entrySnap.data()?['reviewCount'] ?? 0) as int;

        final newTotalStars = currentTotalStars + review.ratingStars;
        final newReviewCount = currentReviewCount + 1;
        final newAvgRating = newTotalStars / newReviewCount;

        // Save review doc inside transaction
        transaction.set(reviewRef, review.toMap());

        // Update parent entry doc with recalculated average rating
        transaction.update(entryRef, {
          'totalStars': newTotalStars,
          'reviewCount': newReviewCount,
          'averageRating': newAvgRating,
          'ratingStars': newAvgRating.round().clamp(1, 5),
        });
        
        // Update contest review count and rating
        if (contestSnap.exists) {
          final cTotalStars = (contestSnap.data()?['totalStars'] ?? 0) as num;
          final cReviewCount = (contestSnap.data()?['reviewCount'] ?? 0) as num;
          final newCTotalStars = cTotalStars + review.ratingStars;
          final newCReviewCount = cReviewCount + 1;
          
          transaction.update(contestRef, {
            'totalStars': newCTotalStars,
            'reviewCount': newCReviewCount,
            'rating': (newCTotalStars / newCReviewCount).toDouble(),
          });
        }
        
        return true;
      });
      
      return success;
    } catch (e) {
      debugPrint('Failed to add review transaction: $e');
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // DECREMENT WINDOW VOTE (10-Second Sliding Window)
  // -------------------------------------------------------------------------
  Future<void> decrementWindowVote(String contestId, String entryId) async {
    if (!_isInitialized || _db == null) return;
    final entryRef = _db!.collection('contests').doc(contestId).collection('entries').doc(entryId);
    try {
      await _db!.runTransaction((transaction) async {
        final snap = await transaction.get(entryRef);
        if (!snap.exists) return;
        final currentWindow = snap.data()?['windowVotes'] ?? 0;
        if (currentWindow > 0) {
          transaction.update(entryRef, {
            'windowVotes': currentWindow - 1,
          });
        }
      });
    } catch (e) {
      debugPrint('Failed to decrement window vote: $e');
    }
  }

  // -------------------------------------------------------------------------
  // POSTS & CONTEST JOINING WORKFLOW
  // -------------------------------------------------------------------------
  Future<void> createPost(PostModel post) async {
    if (!_isInitialized || _db == null) {
      _mockPosts.add(post);
      _mockPostsStreamController.add(List.from(_mockPosts));
      return;
    }
    try {
      final postRef = _db!.collection('posts').doc(post.id);
      await postRef.set(post.toMap());
    } catch (e) {
      debugPrint('Error creating post: $e');
      rethrow;
    }
  }

  Future<void> createPostAndJoinContest(PostModel post, String? contestId) async {
    if (!_isInitialized || _db == null) {
      _mockPosts.add(post);
      _mockPostsStreamController.add(List.from(_mockPosts));
      return;
    }
    try {
      final postRef = _db!.collection('posts').doc(post.id);

      await _db!.runTransaction((transaction) async {
        transaction.set(postRef, post.toMap());

        if (contestId != null && contestId.isNotEmpty) {
          final contestRef = _db!.collection('contests').doc(contestId);
          final entryRef = contestRef.collection('entries').doc(post.id);
          final userRef = _db!.collection('users').doc(post.userId);
          
          final contestSnap = await transaction.get(contestRef);
          final userSnap = await transaction.get(userRef);
          
          // Prevent contest creator from joining their own contest
          if (contestSnap.exists) {
            final creatorId = contestSnap.data()?['creatorId'] as String?;
            if (creatorId == post.userId) {
              return; // Creator cannot join their own contest
            }
          }
          
          final userFlag = userSnap.exists ? (userSnap.data()?['countryFlag'] ?? '🌍') : '🌍';
          final userZip = userSnap.exists ? (userSnap.data()?['zip'] ?? '75001') : '75001';
          final userCity = userSnap.exists ? (userSnap.data()?['city'] ?? 'Tunis') : 'Tunis';
          final userState = userSnap.exists ? (userSnap.data()?['state'] ?? 'Tunis State') : 'Tunis State';
          final userCountry = userSnap.exists ? (userSnap.data()?['country'] ?? 'Tunisia') : 'Tunisia';
          final contestType = contestSnap.exists ? (contestSnap.data()?['type'] ?? 'Official') : 'Official';
          
          transaction.set(entryRef, {
            'userId': post.userId,
            'userName': post.userName,
            'userAvatar': post.userAvatar,
            'countryFlag': userFlag,
            'contentUrl': post.contentUrl,
            'type': post.type,
            'caption': post.caption,
            'totalVotes': 0,
            'windowVotes': 0,
            'ratingStars': 0,
            'totalStars': 0,
            'reviewCount': 0,
            'averageRating': 0.0,
            'postId': post.id,
            'visibilityScope': post.visibilityScope,
            'zip': userZip,
            'city': userCity,
            'state': userState,
            'country': userCountry,
            'contestType': contestType,
            'contestId': contestId,
          });
          
          if (contestSnap.exists) {
            final currentParticipants = contestSnap.data()?['participantCount'] ?? 0;
            transaction.update(contestRef, {
              'participantCount': currentParticipants + 1,
            });
          }
        }
      });
    } catch (e) {
      debugPrint('Failed to create post and join contest: $e');
    }
  }

  Future<void> deletePost(String postId) async {
    if (!_isInitialized || _db == null) {
      _mockPosts.removeWhere((p) => p.id == postId);
      _mockPostComments.remove(postId);
      _mockPostsStreamController.add(List.from(_mockPosts));
      _mockPostCommentsStreamController.add(Map.from(_mockPostComments));
      return;
    }
    try {
      final postRef = _db!.collection('posts').doc(postId);
      await postRef.delete();
      // Also delete comments for this post
      final commentsRef = _db!.collection('posts').doc(postId).collection('comments');
      final commentsSnapshot = await commentsRef.get();
      for (var doc in commentsSnapshot.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('Error deleting post: $e');
      rethrow;
    }
  }

  Future<void> updatePost(String postId, Map<String, dynamic> updates) async {
    if (!_isInitialized || _db == null) {
      final index = _mockPosts.indexWhere((p) => p.id == postId);
      if (index != -1) {
        final post = _mockPosts[index];
        _mockPosts[index] = PostModel(
          id: post.id,
          userId: post.userId,
          userName: post.userName,
          userAvatar: post.userAvatar,
          type: updates['type'] ?? post.type,
          contentUrl: updates['contentUrl'] ?? post.contentUrl,
          caption: updates['caption'] ?? post.caption,
          visibilityScope: updates['visibilityScope'] ?? post.visibilityScope,
          location: updates['location'] ?? post.location,
          createdAt: post.createdAt,
          contestId: post.contestId,
          likes: post.likes,
          commentsCount: post.commentsCount,
        );
        _mockPostsStreamController.add(List.from(_mockPosts));
      }
      return;
    }
    try {
      final postRef = _db!.collection('posts').doc(postId);
      await postRef.update(updates);
    } catch (e) {
      debugPrint('Error updating post: $e');
      rethrow;
    }
  }

  Future<void> createContest(ContestModel contest) async {
    if (!_isInitialized || _db == null) {
      debugPrint('Mock contest creation not implemented');
      return;
    }
    try {
      final contestRef = _db!.collection('contests').doc(contest.id);
      await contestRef.set(contest.toMap());
    } catch (e) {
      debugPrint('Error creating contest: $e');
      rethrow;
    }
  }

  Future<bool> assignPostToContest(String postId, String contestId) async {
    if (!_isInitialized || _db == null) return true;
    try {
      final postRef = _db!.collection('posts').doc(postId);
      final contestRef = _db!.collection('contests').doc(contestId);
      final entryRef = contestRef.collection('entries').doc(postId);

      final result = await _db!.runTransaction((transaction) async {
        final postSnap = await transaction.get(postRef);
        if (!postSnap.exists) return false;

        final postData = postSnap.data()!;
        final existingContestId = postData['contestId'] as String?;

        if (existingContestId != null && existingContestId.isNotEmpty) {
          return false; // 1 post = 1 contest only enforcement!
        }

        final contestSnap = await transaction.get(contestRef);
        if (!contestSnap.exists) return false;

        final userRef = _db!.collection('users').doc(postData['userId']);
        final userSnap = await transaction.get(userRef);
        
        final userFlag = userSnap.exists ? (userSnap.data()?['countryFlag'] ?? '🌍') : '🌍';
        final userZip = userSnap.exists ? (userSnap.data()?['zip'] ?? '75001') : '75001';
        final userCity = userSnap.exists ? (userSnap.data()?['city'] ?? 'Tunis') : 'Tunis';
        final userState = userSnap.exists ? (userSnap.data()?['state'] ?? 'Tunis State') : 'Tunis State';
        final userCountry = userSnap.exists ? (userSnap.data()?['country'] ?? 'Tunisia') : 'Tunisia';
        final contestType = contestSnap.data()?['type'] ?? 'Official';
        
        transaction.update(postRef, {'contestId': contestId});
        
        transaction.set(entryRef, {
          'userId': postData['userId'],
          'userName': postData['userName'] ?? 'Anonymous',
          'userAvatar': postData['userAvatar'] ?? 'https://i.pravatar.cc/150?u=99',
          'countryFlag': userFlag,
          'contentUrl': postData['contentUrl'] ?? '',
          'type': postData['type'] ?? 'image',
          'caption': postData['caption'] ?? '',
          'totalVotes': 0,
          'windowVotes': 0,
          'ratingStars': 0,
          'totalStars': 0,
          'reviewCount': 0,
          'averageRating': 0.0,
          'postId': postId,
          'visibilityScope': postData['visibilityScope'] ?? 'global',
          'zip': userZip,
          'city': userCity,
          'state': userState,
          'country': userCountry,
          'contestType': contestType,
          'contestId': contestId,
        });
        
        final currentParticipants = contestSnap.data()?['participantCount'] ?? 0;
        transaction.update(contestRef, {
          'participantCount': currentParticipants + 1,
        });
        
        return true;
      });
      return result;
    } catch (e) {
      debugPrint('Failed to assign post to contest: $e');
      return false;
    }
  }

  Stream<List<PostModel>> getUserPosts(String userId) async* {
    if (!_isInitialized || _db == null) {
      final list = _mockPosts.where((p) => p.userId == userId).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      yield list;
      yield* _mockPostsStreamController.stream.map((posts) {
        final filtered = posts.where((p) => p.userId == userId).toList();
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return filtered;
      });
      return;
    }
    yield* _db!
        .collection('posts')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final posts = snapshot.docs.map((doc) => PostModel.fromFirestore(doc)).toList();
      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return posts;
    });
  }

  // -------------------------------------------------------------------------
  // GLOBAL REAL-TIME SLIDING FEED
  // -------------------------------------------------------------------------
  Stream<List<ContestEntry>> watchGlobalFeedEntries() {
    if (!_isInitialized || _db == null) {
      return Stream.value([]);
    }

    return _db!.collectionGroup('entries').snapshots().map((snapshot) {
      final entries = snapshot.docs.map((doc) {
        final data = doc.data();
        final avatar = data['userAvatar']?.toString() ?? '';
        final content = data['contentUrl']?.toString() ?? '';
        final reviewCount = (data['reviewCount'] ?? 0) as int;
        final totalStars = (data['totalStars'] ?? 0) as int;
        double averageRating = 0;
        if (reviewCount > 0) {
          averageRating = totalStars / reviewCount;
        } else {
          averageRating = ((data['averageRating'] ?? data['rating'] ?? 0) as num).toDouble();
        }
        return ContestEntry(
          id: doc.id,
          userId: data['userId'] ?? '',
          userName: data['userName'] ?? 'Anonymous',
          userAvatar: avatar.isEmpty ? 'https://i.pravatar.cc/150?u=99' : avatar,
          countryFlag: data['countryFlag'] ?? '🌍',
          contentUrl: content.isEmpty ? 'https://images.unsplash.com/photo-1516280440614-37939bbacd81' : content,
          type: data['type'] ?? 'image',
          caption: data['caption'] ?? '',
          totalVotes: data['totalVotes'] ?? 0,
          windowVotes: data['windowVotes'] ?? 0,
          ratingStars: averageRating.round().clamp(0, 5),
          averageRating: averageRating,
          reviewCount: reviewCount,
          visibilityScope: data['visibilityScope'] ?? 'global',
          zip: data['zip'] ?? '75001',
          city: data['city'] ?? 'Tunis',
          state: data['state'] ?? 'Tunis State',
          country: data['country'] ?? 'Tunisia',
          contestType: data['contestType'] ?? 'Official',
          contestId: data['contestId'] ?? '',
        );
      }).toList();

      entries.sort((a, b) {
        int cmp = b.windowVotes.compareTo(a.windowVotes);
        if (cmp == 0) return b.totalVotes.compareTo(a.totalVotes);
        return cmp;
      });

      return entries;
    });
  }

  // -------------------------------------------------------------------------
  // REAL-TIME NOTIFICATIONS
  // -------------------------------------------------------------------------
  Future<void> sendNotification(NotificationModel notification) async {
    if (!_isInitialized || _db == null) return;
    try {
      await _db!.collection('notifications').add(notification.toMap());
    } catch (e) {
      debugPrint('Failed to send notification: $e');
    }
  }

  Stream<List<NotificationModel>> watchNotifications() {
    if (!_isInitialized || _db == null) {
      return Stream.value([
        NotificationModel(
          id: 'mock_n1',
          title: 'Contest Started',
          message: 'Sophie France joined the Live Contest!',
          type: 'join',
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
          senderName: 'Sophie France',
          senderAvatar: 'https://i.pravatar.cc/150?u=4',
        ),
        NotificationModel(
          id: 'mock_n2',
          title: 'High Vote Velocity!',
          message: 'Gordon Ramsey voted for Wei China!',
          type: 'vote',
          timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
          senderName: 'Gordon Ramsey',
          senderAvatar: 'https://i.pravatar.cc/150?u=99',
        ),
      ]);
    }
    return _db!
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(30)
        .snapshots()
        .map((snap) {
      return snap.docs.map((doc) => NotificationModel.fromFirestore(doc)).toList();
    });
  }

  Future<void> toggleLikePost(String postId, String userId) async {
    if (!_isInitialized || _db == null) {
      final index = _mockPosts.indexWhere((p) => p.id == postId);
      if (index != -1) {
        final post = _mockPosts[index];
        final updatedLikes = List<String>.from(post.likes);
        if (updatedLikes.contains(userId)) {
          updatedLikes.remove(userId);
        } else {
          updatedLikes.add(userId);
        }
        _mockPosts[index] = PostModel(
          id: post.id,
          userId: post.userId,
          userName: post.userName,
          userAvatar: post.userAvatar,
          type: post.type,
          contentUrl: post.contentUrl,
          caption: post.caption,
          visibilityScope: post.visibilityScope,
          location: post.location,
          createdAt: post.createdAt,
          contestId: post.contestId,
          likes: updatedLikes,
          commentsCount: post.commentsCount,
        );
        _mockPostsStreamController.add(List.from(_mockPosts));
      }
      return;
    }
    try {
      final postRef = _db!.collection('posts').doc(postId);
      await _db!.runTransaction((transaction) async {
        final snap = await transaction.get(postRef);
        if (!snap.exists) return;
        final data = snap.data() ?? {};
        final likesData = data['likes'];
        final List<String> currentLikes = likesData is List ? List<String>.from(likesData) : [];
        if (currentLikes.contains(userId)) {
          transaction.update(postRef, {
            'likes': FieldValue.arrayRemove([userId])
          });
        } else {
          transaction.update(postRef, {
            'likes': FieldValue.arrayUnion([userId])
          });
        }
      });
    } catch (e) {
      debugPrint('Failed to toggle like: $e');
    }
  }

  Future<void> addPostComment(String postId, CommentModel comment) async {
    if (!_isInitialized || _db == null) {
      if (!_mockPostComments.containsKey(postId)) {
        _mockPostComments[postId] = [];
      }
      final updatedComment = CommentModel(
        id: comment.id.isEmpty ? 'mock_comment_${DateTime.now().millisecondsSinceEpoch}' : comment.id,
        userId: comment.userId,
        userName: comment.userName,
        userAvatar: comment.userAvatar,
        text: comment.text,
        timestamp: comment.timestamp,
      );
      _mockPostComments[postId]!.insert(0, updatedComment);

      // Increment commentsCount in mock posts list
      final index = _mockPosts.indexWhere((p) => p.id == postId);
      if (index != -1) {
        final post = _mockPosts[index];
        _mockPosts[index] = PostModel(
          id: post.id,
          userId: post.userId,
          userName: post.userName,
          userAvatar: post.userAvatar,
          type: post.type,
          contentUrl: post.contentUrl,
          caption: post.caption,
          visibilityScope: post.visibilityScope,
          location: post.location,
          createdAt: post.createdAt,
          contestId: post.contestId,
          likes: post.likes,
          commentsCount: post.commentsCount + 1,
        );
        _mockPostsStreamController.add(List.from(_mockPosts));
      }

      _mockPostCommentsStreamController.add(Map.from(_mockPostComments));
      return;
    }
    try {
      final postRef = _db!.collection('posts').doc(postId);
      final commentRef = postRef.collection('comments').doc();
      await _db!.runTransaction((transaction) async {
        final postSnap = await transaction.get(postRef);
        if (!postSnap.exists) return;
        final currentCount = postSnap.data()?['commentsCount'] ?? 0;
        transaction.set(commentRef, comment.toMap());
        transaction.update(postRef, {
          'commentsCount': currentCount + 1,
        });
      });
    } catch (e) {
      debugPrint('Failed to add post comment: $e');
    }
  }

  Stream<List<CommentModel>> getPostComments(String postId) async* {
    if (!_isInitialized || _db == null) {
      if (!_mockPostComments.containsKey(postId)) {
        _mockPostComments[postId] = [];
      }
      yield _mockPostComments[postId]!;
      yield* _mockPostCommentsStreamController.stream.map((map) => map[postId] ?? []);
      return;
    }
    yield* _db!
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => CommentModel.fromFirestore(doc)).toList();
    });
  }

  Stream<PostModel?> getPostStream(String postId) async* {
    if (!_isInitialized || _db == null) {
      final index = _mockPosts.indexWhere((p) => p.id == postId);
      final fallbackPost = index != -1 ? _mockPosts[index] : PostModel(
        id: postId,
        userId: 'current_user',
        userName: 'Mlivecast Player',
        userAvatar: '',
        type: 'text',
        contentUrl: '',
        caption: 'Placeholder post',
        visibilityScope: 'global',
        location: '',
        createdAt: DateTime.now(),
      );
      yield fallbackPost;
      yield* _mockPostsStreamController.stream.map((posts) {
        final idx = posts.indexWhere((p) => p.id == postId);
        return idx != -1 ? posts[idx] : fallbackPost;
      });
      return;
    }
    yield* _db!.collection('posts').doc(postId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return PostModel.fromFirestore(doc);
    });
  }

  Stream<List<PostModel>> getAllPosts() async* {
    if (!_isInitialized || _db == null) {
      if (_mockPosts.isEmpty) {
        _mockPosts.addAll([
          PostModel(
            id: 'mock_p1',
            userId: 'u1',
            userName: 'Sophie France',
            userAvatar: 'https://i.pravatar.cc/150?u=4',
            type: 'image',
            contentUrl: 'https://images.unsplash.com/photo-1504674900247-0877df9cc836',
            caption: 'Fresh and delicious meal prepared today!',
            visibilityScope: 'global',
            location: 'Paris, France',
            createdAt: DateTime.now().subtract(const Duration(hours: 3)),
            likes: ['u2', 'current_user'],
            commentsCount: 2,
          ),
          PostModel(
            id: 'mock_p2',
            userId: 'u2',
            userName: 'Wei China',
            userAvatar: 'https://i.pravatar.cc/150?u=5',
            type: 'text',
            contentUrl: '',
            caption: 'Excited to participate in the upcoming street food challenge! Who is with me?',
            visibilityScope: 'global',
            location: 'Beijing, China',
            createdAt: DateTime.now().subtract(const Duration(hours: 6)),
            likes: ['u1'],
            commentsCount: 1,
          ),
        ]);
      }
      final sorted = List<PostModel>.from(_mockPosts);
      sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      yield sorted;
      yield* _mockPostsStreamController.stream.map((posts) {
        final sortedPosts = List<PostModel>.from(posts);
        sortedPosts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return sortedPosts;
      });
      return;
    }
    yield* _db!
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => PostModel.fromFirestore(doc)).toList();
    });
  }

  Future<List<dynamic>> getPostsQueryPaginated({
    required int limit,
    dynamic startAfter,
  }) async {
    if (!_isInitialized || _db == null) {
      if (_mockPosts.isEmpty) {
        _mockPosts.addAll([
          PostModel(
            id: 'mock_p1',
            userId: 'u1',
            userName: 'Sophie France',
            userAvatar: 'https://i.pravatar.cc/150?u=4',
            type: 'image',
            contentUrl: 'https://images.unsplash.com/photo-1504674900247-0877df9cc836',
            caption: 'Fresh and delicious meal prepared today!',
            visibilityScope: 'global',
            location: 'Paris, France',
            createdAt: DateTime.now().subtract(const Duration(hours: 3)),
            likes: ['u2', 'current_user'],
            commentsCount: 2,
          ),
          PostModel(
            id: 'mock_p2',
            userId: 'u2',
            userName: 'Wei China',
            userAvatar: 'https://i.pravatar.cc/150?u=5',
            type: 'text',
            contentUrl: '',
            caption: 'Excited to participate in the upcoming street food challenge! Who is with me?',
            visibilityScope: 'global',
            location: 'Beijing, China',
            createdAt: DateTime.now().subtract(const Duration(hours: 6)),
            likes: ['u1'],
            commentsCount: 1,
          ),
        ]);
      }
      final sorted = List<PostModel>.from(_mockPosts);
      sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      int startIndex = 0;
      if (startAfter != null && startAfter is PostModel) {
        final index = sorted.indexWhere((p) => p.id == startAfter.id);
        if (index != -1) {
          startIndex = index + 1;
        }
      }

      if (startIndex >= sorted.length) {
        return [];
      }

      final endIndex = (startIndex + limit).clamp(0, sorted.length);
      return sorted.sublist(startIndex, endIndex);
    }

    Query query = _db!.collection('posts').orderBy('createdAt', descending: true).limit(limit);
    if (startAfter != null && startAfter is DocumentSnapshot) {
      query = query.startAfterDocument(startAfter);
    }
    final snap = await query.get();
    return snap.docs;
  }
}
