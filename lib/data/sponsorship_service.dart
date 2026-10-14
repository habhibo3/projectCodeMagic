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

  Future<List<Map<String, dynamic>>> getAppleSponsorshipProducts() async {
    final result = await call('get_apple_sponsorship_products');
    return (result['products'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<void> startAppleSponsorship({
    required String tierId,
    required String productId,
    required int durationMonths,
  }) async {
    await call('start_apple_sponsorship', {
      'tierId': tierId,
      'productId': productId,
      'durationMonths': durationMonths,
    });
  }

  Future<void> cancelPendingAppleSponsorship(String productId) async {
    await call('cancel_apple_sponsorship', {'productId': productId});
  }

  Future<void> verifyAppleSponsorship(String signedTransaction) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Sign in to verify this purchase.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Could not authenticate this purchase.');
    }
    final projectId = Firebase.app().options.projectId;
    final response = await http.post(
      Uri.parse(
        'https://us-central1-$projectId.cloudfunctions.net/verifyAppleSponsorship',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'signedTransaction': signedTransaction}),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        body['error'] as String? ?? 'Could not verify this Apple purchase.',
      );
    }
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
    try {
      await FirebaseStorage.instance.ref(path).putData(
            bytes,
            SettableMetadata(contentType: contentType),
          );
    } on FirebaseException catch (error) {
      final code = error.code.toLowerCase();
      if (code == 'unauthorized' || code == 'unauthenticated') {
        throw Exception(
          'Firebase Storage denied this upload. Check that the deployed Storage rules allow signed-in users to write to sponsor_artwork/{their user ID}/{their sponsorship ID}/.',
        );
      }
      if (code == 'bucket-not-found' || code == 'no-default-bucket') {
        throw Exception(
          'The Firebase Storage bucket is unavailable for this app environment. Confirm the staging app and staging Functions use the mlivecast-staging bucket.',
        );
      }
      if (code == 'too-many-requests' || code == 'retry-limit-exceeded' || code == 'quota-exceeded') {
        throw Exception(
          'Firebase Storage temporarily rejected the upload (${error.code}). Wait a minute and try once more. If it continues, check Storage quotas and the upload request in the browser Network panel.',
        );
      }
      throw Exception(
        'Firebase Storage upload failed (${error.code})${error.message == null ? '.' : ': ${error.message}'}.',
      );
    }
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
