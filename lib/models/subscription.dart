class SubscriptionPlan {
  final String id;
  final String name;
  final String description;
  final double price;
  final String currency;
  final String interval; // 'monthly', 'yearly'
  final List<String> features;
  final int maxVotesPerDay;
  final int maxContestsPerMonth;
  final bool prioritySupport;
  final bool adFree;
  final bool customProfile;

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.currency,
    required this.interval,
    required this.features,
    required this.maxVotesPerDay,
    required this.maxContestsPerMonth,
    required this.prioritySupport,
    required this.adFree,
    required this.customProfile,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'currency': currency,
      'interval': interval,
      'features': features,
      'maxVotesPerDay': maxVotesPerDay,
      'maxContestsPerMonth': maxContestsPerMonth,
      'prioritySupport': prioritySupport,
      'adFree': adFree,
      'customProfile': customProfile,
    };
  }

  factory SubscriptionPlan.fromMap(Map<String, dynamic> map) {
    return SubscriptionPlan(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      price: (map['price'] as num).toDouble(),
      currency: map['currency'] as String,
      interval: map['interval'] as String,
      features: List<String>.from(map['features'] as List),
      maxVotesPerDay: map['maxVotesPerDay'] as int,
      maxContestsPerMonth: map['maxContestsPerMonth'] as int,
      prioritySupport: map['prioritySupport'] as bool,
      adFree: map['adFree'] as bool,
      customProfile: map['customProfile'] as bool,
    );
  }
}

class UserSubscription {
  final String userId;
  final String planId;
  final String status; // 'active', 'canceled', 'past_due', 'trialing'
  final DateTime? startDate;
  final DateTime? endDate;
  final bool autoRenew;
  final String? stripeSubscriptionId;
  final String? stripeCustomerId;

  UserSubscription({
    required this.userId,
    required this.planId,
    required this.status,
    this.startDate,
    this.endDate,
    required this.autoRenew,
    this.stripeSubscriptionId,
    this.stripeCustomerId,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'planId': planId,
      'status': status,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'autoRenew': autoRenew,
      'stripeSubscriptionId': stripeSubscriptionId,
      'stripeCustomerId': stripeCustomerId,
    };
  }

  factory UserSubscription.fromMap(Map<String, dynamic> map) {
    return UserSubscription(
      userId: map['userId'] as String,
      planId: map['planId'] as String,
      status: map['status'] as String,
      startDate: map['startDate'] != null ? DateTime.parse(map['startDate'] as String) : null,
      endDate: map['endDate'] != null ? DateTime.parse(map['endDate'] as String) : null,
      autoRenew: map['autoRenew'] as bool,
      stripeSubscriptionId: map['stripeSubscriptionId'] as String?,
      stripeCustomerId: map['stripeCustomerId'] as String?,
    );
  }

  bool get isActive => status == 'active' || status == 'trialing';
  bool get isExpired => endDate != null && DateTime.now().isAfter(endDate!);
}
