import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  final db = FirebaseFirestore.instance;
  
  debugPrint('Starting Firestore stats reset...');
  
  final contests = await db.collection('contests').get();
  
  for (var contest in contests.docs) {
    debugPrint('Resetting contest: ${contest.id}');
    await contest.reference.update({
      'participantCount': 0,
      'totalVotes': 0,
      'rating': 0.0,
      'reviewCount': 0,
      'totalStars': 0,
    });
    
    final entries = await contest.reference.collection('entries').get();
    for (var entry in entries.docs) {
      debugPrint('  Resetting entry: ${entry.id}');
      await entry.reference.update({
        'totalVotes': 0,
        'windowVotes': 0,
        'ratingStars': 0,
        'totalStars': 0,
        'reviewCount': 0,
      });
    }
  }
  
  debugPrint('Done!');
}
