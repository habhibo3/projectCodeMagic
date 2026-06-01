class ContestEntry {
  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final String countryFlag;
  final String contentUrl;
  final String type; // 'video', 'image', 'text'
  final String caption;
  int totalVotes;
  int windowVotes; // Votes in the last 10 seconds
  int ratingStars; // Rounded star display (1-5)
  double averageRating; // Live average from reviews (0.0–5.0)
  int reviewCount;
  final String visibilityScope; // 'zip', 'city', 'state', 'country', 'global'
  final String zip;
  final String city;
  final String state;
  final String country;
  final String contestType; // 'Official', 'Public'
  final String contestId;

  ContestEntry({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    this.countryFlag = '🌍',
    required this.contentUrl,
    required this.type,
    this.caption = '',
    this.totalVotes = 0,
    this.windowVotes = 0,
    this.ratingStars = 0,
    this.averageRating = 0,
    this.reviewCount = 0,
    this.visibilityScope = 'global',
    this.zip = '75001',
    this.city = 'Tunis',
    this.state = 'Tunis State',
    this.country = 'Tunisia',
    this.contestType = 'Official',
    this.contestId = '',
  });

  ContestEntry copyWith({
    int? totalVotes,
    int? windowVotes,
    double? averageRating,
    int? reviewCount,
    int? ratingStars,
    String? visibilityScope,
    String? zip,
    String? city,
    String? state,
    String? country,
    String? contestType,
    String? contestId,
  }) {
    return ContestEntry(
      id: id,
      userId: userId,
      userName: userName,
      userAvatar: userAvatar,
      countryFlag: countryFlag,
      contentUrl: contentUrl,
      type: type,
      caption: caption,
      totalVotes: totalVotes ?? this.totalVotes,
      windowVotes: windowVotes ?? this.windowVotes,
      ratingStars: ratingStars ?? this.ratingStars,
      averageRating: averageRating ?? this.averageRating,
      reviewCount: reviewCount ?? this.reviewCount,
      visibilityScope: visibilityScope ?? this.visibilityScope,
      zip: zip ?? this.zip,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      contestType: contestType ?? this.contestType,
      contestId: contestId ?? this.contestId,
    );
  }
}

class ContestModel {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final String rules;
  final String prize;
  final String schedule;
  final String image;
  final String category;
  final String type; // 'Official', 'Public'
  final int participantCount;
  final int totalVotes;
  final double rating;
  final int reviewCount;
  final String endsIn;
  final DateTime? endDate;

  const ContestModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.rules,
    required this.prize,
    required this.schedule,
    required this.image,
    required this.category,
    required this.type,
    required this.participantCount,
    required this.totalVotes,
    required this.rating,
    required this.reviewCount,
    required this.endsIn,
    this.endDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'description': description,
      'rules': rules,
      'prize': prize,
      'schedule': schedule,
      'image': image,
      'category': category,
      'type': type,
      'participantCount': participantCount,
      'totalVotes': totalVotes,
      'rating': rating,
      'reviewCount': reviewCount,
      'endsIn': endsIn,
      'endDate': endDate?.toIso8601String(),
    };
  }

  factory ContestModel.fromMap(Map<String, dynamic> map) {
    return ContestModel(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      subtitle: map['subtitle'] ?? '',
      description: map['description'] ?? '',
      rules: map['rules'] ?? '',
      prize: map['prize'] ?? '',
      schedule: map['schedule'] ?? '',
      image: map['image'] ?? '',
      category: map['category'] ?? '',
      type: map['type'] ?? 'Public',
      participantCount: map['participantCount'] ?? 0,
      totalVotes: map['totalVotes'] ?? 0,
      rating: (map['rating'] ?? 0.0).toDouble(),
      reviewCount: map['reviewCount'] ?? 0,
      endsIn: map['endsIn'] ?? '30 days',
      endDate: map['endDate'] != null ? DateTime.parse(map['endDate']) : null,
    );
  }

  String get calculatedEndsIn {
    if (endDate == null) return endsIn;
    final now = DateTime.now();
    final difference = endDate!.difference(now);
    if (difference.isNegative) return 'Ended';
    if (difference.inDays >= 7) {
      return '${difference.inDays} days';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ${difference.inHours % 24}h';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours}h ${difference.inMinutes % 60}m';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}m';
    } else {
      return 'Ending soon';
    }
  }
}
