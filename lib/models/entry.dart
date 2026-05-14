class ContestEntry {
  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final String contentUrl;
  final String type; // 'video', 'image', 'text'
  final String caption;
  int totalVotes;
  int windowVotes; // Votes in the last 10 seconds

  ContestEntry({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.contentUrl,
    required this.type,
    this.caption = '',
    this.totalVotes = 0,
    this.windowVotes = 0,
  });

  ContestEntry copyWith({
    int? totalVotes,
    int? windowVotes,
  }) {
    return ContestEntry(
      id: id,
      userId: userId,
      userName: userName,
      userAvatar: userAvatar,
      contentUrl: contentUrl,
      type: type,
      caption: caption,
      totalVotes: totalVotes ?? this.totalVotes,
      windowVotes: windowVotes ?? this.windowVotes,
    );
  }
}
