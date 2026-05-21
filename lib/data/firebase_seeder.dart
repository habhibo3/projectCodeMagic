import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import 'mock_data.dart';
import '../models/user.dart';

class FirebaseSeeder {
  static Future<void> seedIfEmpty() async {
    final db = FirebaseFirestore.instance;
    
    // Check if contests exist
    final snapshot = await db.collection('contests').limit(1).get();
    
    // Always seed users if we don't have them to establish robust relations
    final usersSnapshot = await db.collection('users').limit(1).get();
    if (usersSnapshot.docs.isEmpty) {
      developer.log('Seeding Firebase with professional user database relations...');
      
      final usersToSeed = [
        UserModel(
          uid: 'u1',
          displayName: 'James USA',
          email: 'james@feastvote.com',
          photoURL: 'https://i.pravatar.cc/150?u=1',
          role: 'contestant',
          country: 'United States',
          countryFlag: '🇺🇸',
          bio: 'Singer and songwriter who loves performing acoustic sets in New York.',
          createdAt: DateTime.now(),
          totalVotesCast: 142,
        ),
        UserModel(
          uid: 'u2',
          displayName: 'Lan Vietnam',
          email: 'lan@feastvote.com',
          photoURL: 'https://i.pravatar.cc/150?u=2',
          role: 'contestant',
          country: 'Vietnam',
          countryFlag: '🇻🇳',
          bio: 'Traditional and modern crossover dancer from Hanoi.',
          createdAt: DateTime.now(),
          totalVotesCast: 95,
        ),
        UserModel(
          uid: 'u3',
          displayName: 'Wei China',
          email: 'wei@feastvote.com',
          photoURL: 'https://i.pravatar.cc/150?u=3',
          role: 'contestant',
          country: 'China',
          countryFlag: '🇨🇳',
          bio: 'Street dance choreographer competing worldwide.',
          createdAt: DateTime.now(),
          totalVotesCast: 64,
        ),
        UserModel(
          uid: 'u4',
          displayName: 'Sophie France',
          email: 'sophie@feastvote.com',
          photoURL: 'https://i.pravatar.cc/150?u=4',
          role: 'contestant',
          country: 'France',
          countryFlag: '🇫🇷',
          bio: 'Violinist combining classical melodies with electronic EDM drops.',
          createdAt: DateTime.now(),
          totalVotesCast: 121,
        ),
        UserModel(
          uid: 'u5',
          displayName: 'Yuki Japan',
          email: 'yuki@feastvote.com',
          photoURL: 'https://i.pravatar.cc/150?u=5',
          role: 'contestant',
          country: 'Japan',
          countryFlag: '🇯🇵',
          bio: 'Stand-up comedian showcasing Japanese culture with jokes.',
          createdAt: DateTime.now(),
          totalVotesCast: 78,
        ),
        UserModel(
          uid: 'current_user',
          displayName: 'Gordon Ramsey',
          email: 'gordon@feastvote.com',
          photoURL: 'https://i.pravatar.cc/150?u=99',
          role: 'judge',
          country: 'United Kingdom',
          countryFlag: '🇬🇧',
          bio: 'Official FeastVote Judge. Rating content with critical and objective standards.',
          createdAt: DateTime.now(),
          totalVotesCast: 32,
        ),
      ];

      for (var user in usersToSeed) {
        await db.collection('users').doc(user.uid).set(user.toMap());
      }
      developer.log('Seeded users collection successfully!');
    }

    if (snapshot.docs.isEmpty) {
      developer.log('Seeding Firebase with contests & entries mock data...');
      
      final contests = MockData.getContests();
      final entries = MockData.getEntries();
      
      for (var contest in contests) {
        // Upload contest
        await db.collection('contests').doc(contest.id).set({
          'title': contest.title,
          'subtitle': contest.subtitle,
          'description': contest.description,
          'rules': contest.rules,
          'prize': contest.prize,
          'schedule': contest.schedule,
          'image': contest.image,
          'category': contest.category,
          'type': contest.type,
          'participantCount': 0,
          'totalVotes': 0,
          'rating': 0.0,
          'reviewCount': 0,
          'totalStars': 0,
          'endsIn': contest.endsIn,
        });

        // For each contest, upload the entries
        for (var entry in entries) {
          await db.collection('contests').doc(contest.id).collection('entries').doc(entry.id).set({
            'userId': entry.userId, // FOREIGN KEY relation to users collection!
            'userName': entry.userName,
            'userAvatar': entry.userAvatar,
            'countryFlag': entry.countryFlag,
            'contentUrl': entry.contentUrl,
            'type': entry.type,
            'caption': entry.caption,
            'totalVotes': 0,
            'windowVotes': 0,
            'ratingStars': 0,
            'totalStars': 0,
            'reviewCount': 0,
          });

        }
      }
      
      developer.log('Firebase seeded successfully!');
    } else {
      developer.log('Firebase already has data. Skipping seed.');
      await _resetSeededEntryVotes(db);
      await _syncEntryRatingsFromReviews(db);
    }
  }

  /// Repairs entries where reviews exist but averageRating on the parent was never set.
  static Future<void> _syncEntryRatingsFromReviews(FirebaseFirestore db) async {
    final contestsSnap = await db.collection('contests').get();
    for (final contestDoc in contestsSnap.docs) {
      final entriesSnap =
          await contestDoc.reference.collection('entries').get();
      for (final entryDoc in entriesSnap.docs) {
        final reviewsSnap =
            await entryDoc.reference.collection('reviews').get();
        if (reviewsSnap.docs.isEmpty) continue;

        var totalStars = 0;
        for (final reviewDoc in reviewsSnap.docs) {
          totalStars += (reviewDoc.data()['ratingStars'] ?? 0) as int;
        }
        final count = reviewsSnap.docs.length;
        final avg = totalStars / count;

        await entryDoc.reference.set({
          'totalStars': totalStars,
          'reviewCount': count,
          'averageRating': avg,
          'ratingStars': avg.round().clamp(1, 5),
        }, SetOptions(merge: true));
      }
    }
  }

  /// Resets totalVotes on seeded entries (IDs 1-5) to 0 so only real votes count.
  static Future<void> _resetSeededEntryVotes(FirebaseFirestore db) async {
    final seededEntryIds = ['1', '2', '3', '4', '5'];
    final contestsSnap = await db.collection('contests').get();
    for (var contestDoc in contestsSnap.docs) {
      for (var entryId in seededEntryIds) {
        final entryRef = contestDoc.reference.collection('entries').doc(entryId);
        final entrySnap = await entryRef.get();
        if (entrySnap.exists) {
          final data = entrySnap.data()!;
          if ((data['totalVotes'] ?? 0) > 0) {
            await entryRef.update({'totalVotes': 0, 'windowVotes': 0});
            developer.log('Reset votes for seeded entry $entryId in contest ${contestDoc.id}');
          }
        }
      }
    }
  }
}
