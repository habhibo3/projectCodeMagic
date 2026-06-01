import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Authentication service supporting Email & Password auth with Firestore user profiles.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  /// Signs up a new user with Email, Password, Display Name, and Location details.
  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String displayName,
    required String zip,
    required String city,
    required String state,
    required String country,
    required String countryFlag,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      
      final uid = credential.user?.uid;
      if (uid != null) {
        // Initialize Firestore profile doc
        final ref = FirebaseFirestore.instance.collection('users').doc(uid);
        await ref.set({
          'displayName': displayName.trim(),
          'email': email.trim(),
          'photoURL': '',
          'role': 'contestant',
          'country': country,
          'countryFlag': countryFlag,
          'bio': 'Regular performer.',
          'createdAt': FieldValue.serverTimestamp(),
          'totalVotesCast': 0,
          'subscriptionLevel': 'free',
          'zip': zip.trim(),
          'city': city.trim(),
          'state': state.trim(),
          'location': '${city.trim()}, ${country.trim()}',
        });
      }
      return credential;
    } catch (e) {
      debugPrint('AuthService signUp error: $e');
      rethrow;
    }
  }

  /// Signs in an existing user with Email and Password.
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } catch (e) {
      debugPrint('AuthService signIn error: $e');
      rethrow;
    }
  }

  /// Signs out the current user.
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Sends a password reset link to the user's email.
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } catch (e) {
      debugPrint('AuthService sendPasswordReset error: $e');
      rethrow;
    }
  }

  /// Fallback anonymous sign in if needed (returns uid).
  Future<String> ensureSignedIn() async {
    if (_auth.currentUser != null) {
      return _auth.currentUser!.uid;
    }
    try {
      final credential = await _auth.signInAnonymously();
      final uid = credential.user?.uid;
      if (uid == null) {
        throw StateError('Anonymous sign-in returned no uid');
      }
      return uid;
    } catch (e) {
      debugPrint('AuthService: anonymous sign-in failed: $e');
      rethrow;
    }
  }
}
