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
  final String prize; // Kept for backward compatibility, but use prizes list
  final List<Map<String, dynamic>> prizes; // New structured prize system
  final String schedule;
  final String image;
  final String coverType; // 'image' or 'video'
  final String category;
  final String type; // 'Official', 'Public'
  final int participantCount;
  final int totalVotes;
  final double rating;
  final int reviewCount;
  final String endsIn;
  final DateTime? endDate;
  final String creatorId;
  // Location fields for map system
  final String city;
  final String country;
  final String countryFlag;
  final double? latitude;
  final double? longitude;
  final String visibilityScope; // 'zip', 'city', 'state', 'country', 'global'

  const ContestModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.rules,
    required this.prize,
    this.prizes = const [], // Default to empty list for new contests
    required this.schedule,
    required this.image,
    this.coverType = 'image',
    required this.category,
    required this.type,
    required this.participantCount,
    required this.totalVotes,
    required this.rating,
    required this.reviewCount,
    required this.endsIn,
    this.endDate,
    this.creatorId = '',
    this.city = '',
    this.country = '',
    this.countryFlag = '',
    this.latitude,
    this.longitude,
    this.visibilityScope = 'global',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'description': description,
      'rules': rules,
      'prize': prize,
      'prizes': prizes,
      'schedule': schedule,
      'image': image,
      'coverType': coverType,
      'category': category,
      'type': type,
      'participantCount': participantCount,
      'totalVotes': totalVotes,
      'rating': rating,
      'reviewCount': reviewCount,
      'endsIn': endsIn,
      'endDate': endDate?.toIso8601String(),
      'creatorId': creatorId,
      'city': city,
      'country': country,
      'countryFlag': countryFlag,
      'latitude': latitude,
      'longitude': longitude,
      'visibilityScope': visibilityScope,
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
      prizes: List<Map<String, dynamic>>.from(map['prizes'] ?? []),
      schedule: map['schedule'] ?? '',
      image: map['image'] ?? '',
      coverType: map['coverType'] ?? 'image',
      category: map['category'] ?? '',
      type: map['type'] ?? 'Public',
      participantCount: map['participantCount'] ?? 0,
      totalVotes: map['totalVotes'] ?? 0,
      rating: (map['rating'] ?? 0.0).toDouble(),
      reviewCount: map['reviewCount'] ?? 0,
      endsIn: map['endsIn'] ?? '30 days',
      endDate: map['endDate'] != null ? DateTime.parse(map['endDate']) : null,
      creatorId: map['creatorId'] ?? '',
      city: map['city'] ?? '',
      country: map['country'] ?? '',
      countryFlag: map['countryFlag'] ?? '',
      latitude: map['latitude']?.toDouble(),
      longitude: map['longitude']?.toDouble(),
      visibilityScope: map['visibilityScope'] ?? 'global',
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
