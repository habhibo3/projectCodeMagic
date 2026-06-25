import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/subscription.dart';
import '../models/user.dart';

class SubscriptionService {
  FirebaseFirestore? _db;
  bool _isInitialized = false;

  SubscriptionService() {
    try {
      _db = FirebaseFirestore.instance;
      _isInitialized = true;
    } catch (e) {
      debugPrint('Firebase not initialized for SubscriptionService: $e');
      _isInitialized = false;
    }
  }

  // -------------------------------------------------------------------------
  // PLAN MANAGEMENT
  // -------------------------------------------------------------------------
  Future<List<SubscriptionPlan>> getPlans() async {
    if (!_isInitialized || _db == null) return _getDefaultPlans();

    try {
      final snapshot = await _db!.collection('subscription_plans').get();
      if (snapshot.docs.isEmpty) {
        // Initialize default plans if none exist
        await _initializeDefaultPlans();
        return _getDefaultPlans();
      }
      return snapshot.docs.map((doc) => SubscriptionPlan.fromMap(doc.data())).toList();
    } catch (e) {
      debugPrint('Error getting plans: $e');
      return _getDefaultPlans();
    }
  }

  Future<void> createPlan(SubscriptionPlan plan) async {
    if (!_isInitialized || _db == null) return;

    try {
      await _db!.collection('subscription_plans').doc(plan.id).set(plan.toMap());
    } catch (e) {
      debugPrint('Error creating plan: $e');
    }
  }

  Future<void> updatePlan(String planId, Map<String, dynamic> updates) async {
    if (!_isInitialized || _db == null) return;

    try {
      await _db!.collection('subscription_plans').doc(planId).update(updates);
    } catch (e) {
      debugPrint('Error updating plan: $e');
    }
  }

  Future<void> deletePlan(String planId) async {
    if (!_isInitialized || _db == null) return;

    try {
      await _db!.collection('subscription_plans').doc(planId).delete();
    } catch (e) {
      debugPrint('Error deleting plan: $e');
    }
  }

  // -------------------------------------------------------------------------
  // USER SUBSCRIPTION MANAGEMENT
  // -------------------------------------------------------------------------
  Future<UserSubscription?> getUserSubscription(String userId) async {
    if (!_isInitialized || _db == null) return null;

    try {
      final doc = await _db!.collection('user_subscriptions').doc(userId).get();
      if (!doc.exists) return null;
      return UserSubscription.fromMap(doc.data()!);
    } catch (e) {
      debugPrint('Error getting user subscription: $e');
      return null;
    }
  }

  Stream<UserSubscription?> getUserSubscriptionStream(String userId) {
    if (!_isInitialized || _db == null) return Stream.value(null);

    return _db!.collection('user_subscriptions').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserSubscription.fromMap(doc.data()!);
    });
  }

  Future<void> createSubscription({
    required String userId,
    required String planId,
    required String stripeSubscriptionId,
    required String stripeCustomerId,
  }) async {
    if (!_isInitialized || _db == null) return;

    try {
      final plan = await _getPlanById(planId);
      if (plan == null) return;

      final now = DateTime.now();
      final endDate = plan.interval == 'yearly'
          ? now.add(const Duration(days: 365))
          : now.add(const Duration(days: 30));

      await _db!.collection('user_subscriptions').doc(userId).set({
        'userId': userId,
        'planId': planId,
        'status': 'active',
        'startDate': now.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'autoRenew': true,
        'stripeSubscriptionId': stripeSubscriptionId,
        'stripeCustomerId': stripeCustomerId,
      });

      // Update user's subscription level
      await _db!.collection('users').doc(userId).set({
        'subscriptionLevel': plan.id,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error creating subscription: $e');
    }
  }

  Future<void> updateSubscription(String userId, String newPlanId) async {
    if (!_isInitialized || _db == null) return;

    try {
      final plan = await _getPlanById(newPlanId);
      if (plan == null) return;

      final now = DateTime.now();
      final endDate = plan.interval == 'yearly'
          ? now.add(const Duration(days: 365))
          : now.add(const Duration(days: 30));

      await _db!.collection('user_subscriptions').doc(userId).update({
        'planId': newPlanId,
        'endDate': endDate.toIso8601String(),
        'status': 'active',
      });

      // Update user's subscription level
      await _db!.collection('users').doc(userId).set({
        'subscriptionLevel': newPlanId,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating subscription: $e');
    }
  }

  Future<void> cancelSubscription(String userId) async {
    if (!_isInitialized || _db == null) return;

    try {
      await _db!.collection('user_subscriptions').doc(userId).update({
        'status': 'canceled',
        'autoRenew': false,
      });

      // Update user's subscription level to free
      await _db!.collection('users').doc(userId).set({
        'subscriptionLevel': 'free',
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error canceling subscription: $e');
    }
  }

  Future<void> renewSubscription(String userId) async {
    if (!_isInitialized || _db == null) return;

    try {
      final subscription = await getUserSubscription(userId);
      if (subscription == null) return;

      final plan = await _getPlanById(subscription.planId);
      if (plan == null) return;

      final now = DateTime.now();
      final newEndDate = plan.interval == 'yearly'
          ? now.add(const Duration(days: 365))
          : now.add(const Duration(days: 30));

      await _db!.collection('user_subscriptions').doc(userId).update({
        'status': 'active',
        'endDate': newEndDate.toIso8601String(),
        'autoRenew': true,
      });

      await _db!.collection('users').doc(userId).set({
        'subscriptionLevel': subscription.planId,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error renewing subscription: $e');
    }
  }

  // -------------------------------------------------------------------------
  // ADMIN FUNCTIONS
  // -------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getAllSubscriptions() async {
    if (!_isInitialized || _db == null) return [];

    try {
      final snapshot = await _db!.collection('user_subscriptions').get();
      final subscriptions = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final subData = doc.data();
        final userId = subData['userId'] as String;

        // Get user details
        final userDoc = await _db!.collection('users').doc(userId).get();
        final userData = userDoc.data();

        // Get plan details
        final plan = await _getPlanById(subData['planId'] as String);

        subscriptions.add({
          'subscriptionId': doc.id,
          'userId': userId,
          'userName': userData?['displayName'] ?? 'Unknown',
          'userEmail': userData?['email'] ?? '',
          'planName': plan?.name ?? subData['planId'],
          'status': subData['status'],
          'startDate': subData['startDate'],
          'endDate': subData['endDate'],
          'autoRenew': subData['autoRenew'],
        });
      }

      return subscriptions;
    } catch (e) {
      debugPrint('Error getting all subscriptions: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getSubscriptionStats() async {
    if (!_isInitialized || _db == null) {
      return {
        'totalSubscribers': 0,
        'activeSubscribers': 0,
        'canceledSubscribers': 0,
        'monthlyRevenue': 0.0,
      };
    }

    try {
      final snapshot = await _db!.collection('user_subscriptions').get();
      final plans = await getPlans();

      int total = snapshot.docs.length;
      int active = 0;
      int canceled = 0;
      double monthlyRevenue = 0.0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final status = data['status'] as String;
        final planId = data['planId'] as String;

        if (status == 'active' || status == 'trialing') {
          active++;
          final plan = plans.firstWhere((p) => p.id == planId, orElse: () => plans[0]);
          if (plan.interval == 'monthly') {
            monthlyRevenue += plan.price;
          } else if (plan.interval == 'yearly') {
            monthlyRevenue += plan.price / 12;
          }
        } else if (status == 'canceled') {
          canceled++;
        }
      }

      return {
        'totalSubscribers': total,
        'activeSubscribers': active,
        'canceledSubscribers': canceled,
        'monthlyRevenue': monthlyRevenue,
      };
    } catch (e) {
      debugPrint('Error getting subscription stats: $e');
      return {
        'totalSubscribers': 0,
        'activeSubscribers': 0,
        'canceledSubscribers': 0,
        'monthlyRevenue': 0.0,
      };
    }
  }

  // -------------------------------------------------------------------------
  // HELPER FUNCTIONS
  // -------------------------------------------------------------------------
  Future<SubscriptionPlan?> _getPlanById(String planId) async {
    final plans = await getPlans();
    try {
      return plans.firstWhere((plan) => plan.id == planId);
    } catch (e) {
      return null;
    }
  }

  Future<void> _initializeDefaultPlans() async {
    if (!_isInitialized || _db == null) return;

    final plans = _getDefaultPlans();
    for (final plan in plans) {
      await _db!.collection('subscription_plans').doc(plan.id).set(plan.toMap());
    }
  }

  List<SubscriptionPlan> _getDefaultPlans() {
    return [
      SubscriptionPlan(
        id: 'free',
        name: 'Free',
        description: 'Basic access to contests',
        price: 0,
        currency: 'USD',
        interval: 'monthly',
        features: [
          'View all contests',
          'Vote in contests',
          'Basic profile',
          'Standard support',
        ],
        maxVotesPerDay: 50,
        maxContestsPerMonth: 5,
        prioritySupport: false,
        adFree: false,
        customProfile: false,
      ),
      SubscriptionPlan(
        id: 'premium',
        name: 'Premium',
        description: 'Enhanced features for power users',
        price: 9.99,
        currency: 'USD',
        interval: 'monthly',
        features: [
          'Everything in Free',
          'Unlimited voting',
          'Unlimited contests',
          'Priority support',
          'Ad-free experience',
          'Custom profile themes',
          'Early access to new features',
        ],
        maxVotesPerDay: -1, // Unlimited
        maxContestsPerMonth: -1, // Unlimited
        prioritySupport: true,
        adFree: true,
        customProfile: true,
      ),
      SubscriptionPlan(
        id: 'premium_yearly',
        name: 'Premium Yearly',
        description: 'Save 20% with annual billing',
        price: 95.88,
        currency: 'USD',
        interval: 'yearly',
        features: [
          'Everything in Premium',
          '2 months free',
          'Priority support',
          'Ad-free experience',
          'Custom profile themes',
          'Early access to new features',
          'Exclusive contests',
        ],
        maxVotesPerDay: -1,
        maxContestsPerMonth: -1,
        prioritySupport: true,
        adFree: true,
        customProfile: true,
      ),
    ];
  }
}
