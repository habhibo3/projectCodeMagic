import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/entry.dart';
import '../models/comment.dart';
import '../models/review.dart';
import '../models/user.dart';
import 'mock_data.dart';

class FirebaseService {
  FirebaseFirestore? _db;
  bool _isInitialized = false;

  FirebaseService() {
    try {
      _db = FirebaseFirestore.instance;
      _isInitialized = true;
    } catch (e) {
      debugPrint('Firebase not initialized. Falling back to mock data: $e');
      _isInitialized = false;
    }
  }

  // -------------------------------------------------------------------------
  // CONTESTS
  // -------------------------------------------------------------------------
  Stream<List<ContestModel>> getContests() {
    if (!_isInitialized || _db == null) {
      return Stream.value(MockData.getContests());
    }

    return _db!.collection('contests').snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) return MockData.getContests();
      return snapshot.docs.map((doc) {
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
        );
      }).toList();
    });
  }

  // -------------------------------------------------------------------------
  // ENTRIES
  // -------------------------------------------------------------------------
  Stream<List<ContestEntry>> getEntries(String contestId) {
    if (!_isInitialized || _db == null) {
      return Stream.value(MockData.getEntries());
    }

    return _db!
        .collection('contests')
        .doc(contestId)
        .collection('entries')
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return MockData.getEntries();
      
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
        );
      }).toList();
      
      // Sort locally to avoid Firebase composite index requirement
      entries.sort((a, b) {
        int cmp = b.windowVotes.compareTo(a.windowVotes);
        if (cmp == 0) return b.totalVotes.compareTo(a.totalVotes);
        return cmp;
      });
      
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
      'displayName': 'FeastVote Player',
      'email': '',
      'photoURL': 'https://i.pravatar.cc/150?u=$uid',
      'role': 'contestant',
      'country': defaultCountry,
      'countryFlag': defaultFlag,
      'bio': '',
      'createdAt': FieldValue.serverTimestamp(),
      'totalVotesCast': 0,
    });
  }

  Future<void> updateUserCountry(
      String uid, String country, String countryFlag) async {
    if (!_isInitialized || _db == null) return;
    await _db!.collection('users').doc(uid).set({
      'country': country,
      'countryFlag': countryFlag,
    }, SetOptions(merge: true));
  }

  Future<void> updateUserDisplayName(String uid, String displayName) async {
    if (!_isInitialized || _db == null) return;
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return;
    await _db!.collection('users').doc(uid).set({
      'displayName': trimmed,
    }, SetOptions(merge: true));
  }

  /// Keeps contest entry cards in sync with the user's real profile name.
  Future<void> syncEntryUserProfile(
    String contestId,
    String userId, {
    required String displayName,
    required String photoURL,
    required String countryFlag,
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
      });
    }
  }

  Stream<UserModel?> getUserProfile(String userId) {
    if (!_isInitialized || _db == null) {
      return Stream.value(UserModel(
        uid: userId,
        displayName: 'James USA',
        email: 'james@feastvote.com',
        photoURL: 'https://i.pravatar.cc/150?u=1',
        role: 'contestant',
        country: 'United States',
        countryFlag: '🇺🇸',
        bio: 'FeastVote regular performer.',
        createdAt: DateTime.now(),
        totalVotesCast: 120,
      ));
    }

    return _db!.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc);
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
}
