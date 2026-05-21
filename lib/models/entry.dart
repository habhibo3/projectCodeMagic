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
  });

  ContestEntry copyWith({
    int? totalVotes,
    int? windowVotes,
    double? averageRating,
    int? reviewCount,
    int? ratingStars,
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
  });
}
