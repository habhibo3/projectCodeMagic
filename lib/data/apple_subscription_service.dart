import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Sends StoreKit's signed transaction to the trusted backend for verification.
/// Firestore entitlements are written by the backend only after Apple's JWS is
/// verified; the client never grants premium access from a local callback.
class AppleSubscriptionService {
  static const Map<String, String> productToPlan = {
    'com.mlivecast.premium.monthly': 'premium',
    'com.mlivecast.premium.yearly': 'premium_yearly',
  };

  Future<void> verifyAndActivate(String signedTransaction) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in before buying a subscription.');
    if (signedTransaction.isEmpty) {
      throw StateError('The App Store did not provide a signed transaction.');
    }

    final projectId = FirebaseAuth.instance.app.options.projectId;
    if (projectId == null || projectId.isEmpty) {
      throw StateError('Firebase project is not configured.');
    }

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Could not authenticate with Firebase. Sign in again and retry.');
    }
    final response = await http.post(
      Uri.parse(
        'https://us-central1-$projectId.cloudfunctions.net/verifyAppleSubscription',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'signedTransaction': signedTransaction}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Could not verify the App Store purchase.';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['error'] is String) message = body['error'] as String;
      } catch (_) {
        // Keep the generic user-facing message if the response is not JSON.
      }
      debugPrint('Apple purchase verification failed: ${response.statusCode}');
      throw StateError(message);
    }
  }
}
