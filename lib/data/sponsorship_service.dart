import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class SponsorshipService {
  SponsorshipService._();

  static final SponsorshipService instance = SponsorshipService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchTiers({
    required String ownerType,
    required String ownerId,
  }) {
    return _db
        .collection('sponsor_tiers')
        .where('ownerType', isEqualTo: ownerType)
        .where('ownerId', isEqualTo: ownerId)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchSponsors({
    required String ownerType,
    required String ownerId,
  }) {
    return _db
        .collection('sponsorships')
        .where('ownerType', isEqualTo: ownerType)
        .where('ownerId', isEqualTo: ownerId)
        .where('status', isEqualTo: 'ACTIVE')
        .where('artworkStatus', isEqualTo: 'APPROVED')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMySponsorships({
    required String ownerType,
    required String ownerId,
  }) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('sponsorships')
        .where('sponsorUserId', isEqualTo: uid)
        .where('ownerType', isEqualTo: ownerType)
        .where('ownerId', isEqualTo: ownerId)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingReview() {
    return _db
        .collection('sponsorships')
        .where('status', isEqualTo: 'ACTIVE')
        .where('artworkStatus', isEqualTo: 'PENDING_REVIEW')
        .snapshots();
  }

  Future<Map<String, dynamic>> call(String action, [Map<String, dynamic> data = const {}]) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Sign in to manage sponsorships.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) throw Exception('Could not authenticate this request.');
    final projectId = Firebase.app().options.projectId;
    final response = await http
        .post(
          Uri.parse('https://us-central1-$projectId.cloudfunctions.net/sponsorshipApi'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'action': action, ...data}),
        )
        .timeout(const Duration(seconds: 30));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] as String? ?? 'Sponsorship request failed.');
    }
    return body;
  }

  Future<String> createTier(Map<String, dynamic> tier) async {
    final result = await call('create_tier', tier);
    return result['tierId'] as String;
  }

  Future<void> updateTier(String tierId, Map<String, dynamic> updates) async {
    await call('update_tier', {'tierId': tierId, ...updates});
  }

  Future<String> startCheckout(String tierId, int durationMonths) async {
    final result = await call('create_checkout', {
      'tierId': tierId,
      'durationMonths': durationMonths,
    });
    return result['checkoutUrl'] as String;
  }

  Future<String> startPayoutSetup() async {
    final result = await call('connect_onboarding');
    return result['url'] as String;
  }

  Future<void> uploadArtwork(String sponsorshipId, XFile media) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Sign in to submit sponsor artwork.');
    final ext = media.name.split('.').last.toLowerCase();
    const contentTypes = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'mp4': 'video/mp4',
      'webm': 'video/webm',
    };
    final contentType = contentTypes[ext];
    if (contentType == null) {
      throw Exception('Choose a JPG, PNG, WebP, MP4, or WebM file.');
    }
    final bytes = await media.readAsBytes();
    if (bytes.length > 25 * 1024 * 1024) {
      throw Exception('Artwork must be smaller than 25 MB.');
    }
    final uploadId = DateTime.now().microsecondsSinceEpoch;
    final path = 'sponsor_artwork/${user.uid}/$sponsorshipId/artwork_$uploadId.$ext';
    await FirebaseStorage.instance.ref(path).putData(
          bytes,
          SettableMetadata(contentType: contentType),
        );
    await call('submit_artwork', {
      'sponsorshipId': sponsorshipId,
      'storagePath': path,
    });
  }

  Future<void> reviewArtwork(String sponsorshipId, {required bool approve}) async {
    await call(approve ? 'approve_artwork' : 'reject_artwork', {
      'sponsorshipId': sponsorshipId,
    });
  }

  Future<Map<String, dynamic>?> getOwnerConnectAccount() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final snapshot = await _db.collection('users').doc(uid).get();
    return snapshot.data();
  }

}
