import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// One anonymous Firebase user per install — each phone gets its own uid.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  /// Signs in anonymously if needed. Returns the device-unique uid.
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
      debugPrint('AuthService: signed in anonymously as $uid');
      return uid;
    } catch (e) {
      debugPrint('AuthService: anonymous sign-in failed: $e');
      rethrow;
    }
  }
}
