import 'entry.dart';

class StationModel {
  /// Ensures a single `station_` prefix even if legacy data duplicated it.
  static String normalizeId(String id) {
    var normalized = id.trim();
    while (normalized.startsWith('station_station_')) {
      normalized = normalized.substring('station_'.length);
    }
    return normalized;
  }

  final String id;
  final String title;
  final String description;
  final String image;
  final String coverType; // 'image' or 'video'
  final String category;
  final int viewerCount;
  final int totalVotes; // Total votes received
  final double rating;
  final int reviewCount;
  final String creatorId;
  final String creatorName;
  final String creatorAvatar;
  final String city;
  final String country;
  final String countryFlag;
  final double? latitude;
  final double? longitude;
  final String visibilityScope; // 'zip', 'city', 'state', 'country', 'global'
  final DateTime createdAt;
  final bool isLive; // Whether the station is currently live
  final String? currentLiveChannelId; // Agora channel ID if live

  const StationModel({
    required this.id,
    required this.title,
    required this.description,
    required this.image,
    this.coverType = 'image',
    required this.category,
    required this.viewerCount,
    this.totalVotes = 0,
    required this.rating,
    required this.reviewCount,
    required this.creatorId,
    required this.creatorName,
    required this.creatorAvatar,
    required this.city,
    required this.country,
    required this.countryFlag,
    this.latitude,
    this.longitude,
    this.visibilityScope = 'global',
    required this.createdAt,
    this.isLive = false,
    this.currentLiveChannelId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'image': image,
      'coverType': coverType,
      'category': category,
      'viewerCount': viewerCount,
      'totalVotes': totalVotes,
      'rating': rating,
      'reviewCount': reviewCount,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'creatorAvatar': creatorAvatar,
      'city': city,
      'country': country,
      'countryFlag': countryFlag,
      'latitude': latitude,
      'longitude': longitude,
      'visibilityScope': visibilityScope,
      'createdAt': createdAt.toIso8601String(),
      'isLive': isLive,
      'currentLiveChannelId': currentLiveChannelId,
    };
  }

  factory StationModel.fromMap(Map<String, dynamic> map) {
    return StationModel(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      image: map['image'] ?? '',
      coverType: map['coverType'] ?? 'image',
      category: map['category'] ?? '',
      viewerCount: map['viewerCount'] ?? 0,
      totalVotes: map['totalVotes'] ?? 0,
      rating: (map['rating'] ?? 0.0).toDouble(),
      reviewCount: map['reviewCount'] ?? 0,
      creatorId: map['creatorId'] ?? '',
      creatorName: map['creatorName'] ?? '',
      creatorAvatar: map['creatorAvatar'] ?? '',
      city: map['city'] ?? '',
      country: map['country'] ?? '',
      countryFlag: map['countryFlag'] ?? '',
      latitude: map['latitude']?.toDouble(),
      longitude: map['longitude']?.toDouble(),
      visibilityScope: map['visibilityScope'] ?? 'global',
      createdAt: map['createdAt'] != null 
          ? DateTime.parse(map['createdAt']) 
          : DateTime.now(),
      isLive: map['isLive'] ?? false,
      currentLiveChannelId: map['currentLiveChannelId'],
    );
  }

  factory StationModel.fromFirestore(Map<String, dynamic>? data, String id) {
    if (data == null) {
      return StationModel(
        id: id,
        title: '',
        description: '',
        image: '',
        coverType: 'image',
        category: '',
        viewerCount: 0,
        totalVotes: 0,
        rating: 0.0,
        reviewCount: 0,
        creatorId: '',
        creatorName: '',
        creatorAvatar: '',
        city: '',
        country: '',
        countryFlag: '',
        latitude: null,
        longitude: null,
        visibilityScope: 'global',
        createdAt: DateTime.now(),
        isLive: false,
        currentLiveChannelId: null,
      );
    }
    
    return StationModel(
      id: id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      image: data['image'] ?? '',
      coverType: data['coverType'] ?? 'image',
      category: data['category'] ?? '',
      viewerCount: data['viewerCount'] ?? 0,
      totalVotes: data['totalVotes'] ?? 0,
      rating: (data['rating'] ?? 0.0).toDouble(),
      reviewCount: data['reviewCount'] ?? 0,
      creatorId: data['creatorId'] ?? '',
      creatorName: data['creatorName'] ?? '',
      creatorAvatar: data['creatorAvatar'] ?? '',
      city: data['city'] ?? '',
      country: data['country'] ?? '',
      countryFlag: data['countryFlag'] ?? '',
      latitude: data['latitude']?.toDouble(),
      longitude: data['longitude']?.toDouble(),
      visibilityScope: data['visibilityScope'] ?? 'global',
      createdAt: data['createdAt'] is DateTime 
          ? data['createdAt'] 
          : (data['createdAt'] != null ? DateTime.parse(data['createdAt']) : DateTime.now()),
      isLive: data['isLive'] ?? false,
      currentLiveChannelId: data['currentLiveChannelId'],
    );
  }

  ContestModel toContestModel() {
    final normalizedId = StationModel.normalizeId(id);
    return ContestModel(
      id: normalizedId,
      title: title,
      subtitle: description,
      description: description,
      rules: 'Station Broadcast Rules',
      prize: 'N/A',
      prizes: const [],
      schedule: 'Live',
      image: image,
      coverType: coverType,
      category: category,
      type: 'Station',
      participantCount: viewerCount,
      totalVotes: 0,
      rating: rating,
      reviewCount: reviewCount,
      endsIn: 'Live Stream',
      creatorId: creatorId,
      city: city,
      country: country,
      countryFlag: countryFlag,
      latitude: latitude,
      longitude: longitude,
      visibilityScope: visibilityScope,
    );
  }
}

class RecordedLiveModel {
  final String id;
  final String stationId;
  final String title;
  final String videoUrl;
  final String thumbnailUrl;
  final DateTime recordedAt;
  final int duration; // Duration in seconds
  final int viewerCount;
  final int likeCount;
  final int totalVotes;
  final String hostId;
  final String hostName;
  final String hostAvatar;

  const RecordedLiveModel({
    required this.id,
    required this.stationId,
    required this.title,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.recordedAt,
    required this.duration,
    required this.viewerCount,
    this.likeCount = 0,
    this.totalVotes = 0,
    required this.hostId,
    required this.hostName,
    required this.hostAvatar,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'stationId': stationId,
      'title': title,
      'videoUrl': videoUrl,
      'thumbnailUrl': thumbnailUrl,
      'recordedAt': recordedAt.toIso8601String(),
      'duration': duration,
      'viewerCount': viewerCount,
      'likeCount': likeCount,
      'totalVotes': totalVotes,
      'hostId': hostId,
      'hostName': hostName,
      'hostAvatar': hostAvatar,
    };
  }

  factory RecordedLiveModel.fromMap(Map<String, dynamic> map) {
    return RecordedLiveModel(
      id: map['id'] ?? '',
      stationId: map['stationId'] ?? '',
      title: map['title'] ?? '',
      videoUrl: map['videoUrl'] ?? '',
      thumbnailUrl: map['thumbnailUrl'] ?? '',
      recordedAt: map['recordedAt'] is DateTime 
          ? map['recordedAt'] 
          : DateTime.parse(map['recordedAt']),
      duration: map['duration'] ?? 0,
      viewerCount: map['viewerCount'] ?? 0,
      likeCount: map['likeCount'] ?? 0,
      totalVotes: map['totalVotes'] ?? 0,
      hostId: map['hostId'] ?? '',
      hostName: map['hostName'] ?? '',
      hostAvatar: map['hostAvatar'] ?? '',
    );
  }

  factory RecordedLiveModel.fromFirestore(Map<String, dynamic>? data, String id) {
    if (data == null) {
      return RecordedLiveModel(
        id: id,
        stationId: '',
        title: '',
        videoUrl: '',
        thumbnailUrl: '',
        recordedAt: DateTime.now(),
        duration: 0,
        viewerCount: 0,
        likeCount: 0,
        totalVotes: 0,
        hostId: '',
        hostName: '',
        hostAvatar: '',
      );
    }
    
    return RecordedLiveModel(
      id: id,
      stationId: data['stationId'] ?? '',
      title: data['title'] ?? '',
      videoUrl: data['videoUrl'] ?? '',
      thumbnailUrl: data['thumbnailUrl'] ?? '',
      recordedAt: data['recordedAt'] is DateTime 
          ? data['recordedAt'] 
          : (data['recordedAt'] != null ? DateTime.parse(data['recordedAt']) : DateTime.now()),
      duration: data['duration'] ?? 0,
      viewerCount: data['viewerCount'] ?? 0,
      likeCount: data['likeCount'] ?? 0,
      totalVotes: data['totalVotes'] ?? 0,
      hostId: data['hostId'] ?? '',
      hostName: data['hostName'] ?? '',
      hostAvatar: data['hostAvatar'] ?? '',
    );
  }

  String get formattedDuration {
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    final seconds = duration % 60;
    
    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes}:${seconds.toString().padLeft(2, '0')}';
    }
  }
}
