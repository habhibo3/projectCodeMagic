import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/admin_service.dart';

/// Utility class to help set up an admin user
/// 
/// IMPORTANT: This should only be used in development or by trusted administrators.
/// In production, users should be created through Firebase Console or secure backend APIs.
class AdminSetup {
  static final AdminService _adminService = AdminService();

  /// Creates a new admin user with the given email and password
  /// 
  /// Returns the user credential if successful, or throws an error if failed.
  /// 
  /// Usage:
  /// ```dart
  /// try {
  ///   final credential = await AdminSetup.createAdminUser(
  ///     email: 'admin@example.com',
  ///     password: 'securePassword123!',
  ///     displayName: 'Admin User',
  ///   );
  ///   print('Admin user created: ${credential.user?.email}');
  /// } catch (e) {
  ///   print('Error creating admin: $e');
  /// }
  /// ```
  static Future<UserCredential> createAdminUser({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      // Create the user in Firebase Auth
      final auth = FirebaseAuth.instance;
      final userCredential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update display name
      await userCredential.user?.updateDisplayName(displayName);

      // Create user document in Firestore with admin role
      final userDoc = FirebaseFirestore.instance.collection('users').doc(userCredential.user?.uid);
      
      await userDoc.set({
        'uid': userCredential.user?.uid,
        'displayName': displayName,
        'email': email,
        'photoURL': '',
        'role': 'admin', // Set admin role
        'country': 'Global',
        'countryFlag': '🌍',
        'bio': 'System Administrator',
        'createdAt': DateTime.now().toIso8601String(),
        'totalVotesCast': 0,
        'subscriptionLevel': 'premium',
        'location': 'Global',
        'zip': '',
        'city': '',
        'state': '',
        'isBanned': false,
        'isSuspended': false,
        'suspiciousActivityCount': 0,
      });

      print('✅ Admin user created successfully');
      print('Email: $email');
      print('UID: ${userCredential.user?.uid}');
      
      return userCredential;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') {
        throw Exception('The password provided is too weak.');
      } else if (e.code == 'email-already-in-use') {
        throw Exception('An account with this email already exists.');
      } else {
        throw Exception('Firebase Auth error: ${e.message}');
      }
    } catch (e) {
      throw Exception('Error creating admin user: $e');
    }
  }

  /// Promotes an existing user to admin role
  /// 
  /// Usage:
  /// ```dart
  /// try {
  ///   await AdminSetup.promoteToAdmin('user-uid-here');
  ///   print('User promoted to admin');
  /// } catch (e) {
  ///   print('Error: $e');
  /// }
  /// ```
  static Future<void> promoteToAdmin(String userId) async {
    try {
      await _adminService.setAdminRole(userId, true);
      print('✅ User promoted to admin successfully');
    } catch (e) {
      throw Exception('Error promoting user to admin: $e');
    }
  }

  /// Demotes an admin user to regular user
  static Future<void> demoteFromAdmin(String userId) async {
    try {
      await _adminService.setAdminRole(userId, false);
      print('✅ User demoted from admin successfully');
    } catch (e) {
      throw Exception('Error demoting user from admin: $e');
    }
  }

  /// Checks if a user has admin role
  static Future<bool> isAdmin(String userId) async {
    return await _adminService.isAdmin(userId);
  }
}
