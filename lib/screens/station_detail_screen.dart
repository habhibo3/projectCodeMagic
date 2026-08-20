import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/firebase_service.dart';
import '../data/live_session_service.dart';
import '../data/auth_service.dart';
import '../models/station.dart';
import '../models/review.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_helper.dart';
import '../widgets/media_content_preview.dart';
import 'live_stream_screen.dart';
import 'watch_recorded_live_screen.dart';
import '../engine/ranking_engine.dart';
import 'package:provider/provider.dart';

import '../widgets/station_upload_banner_widget.dart';

class StationDetailScreen extends StatefulWidget {
  final StationModel station;

  const StationDetailScreen({super.key, required this.station});

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseService _firebaseService = FirebaseService();
  late Stream<StationModel?> _stationStream;
  late Stream<List<RecordedLiveModel>> _recordedLivesStream;
  late TabController _tabController;
  String _recordedLivesSearchQuery = '';
  final TextEditingController _recordedLivesSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _stationStream = _firebaseService.getStation(widget.station.id);
    _recordedLivesStream = _firebaseService.getRecordedLives(widget.station.id);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _recordedLivesSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StationModel?>(
      stream: _stationStream,
      builder: (context, stationSnapshot) {
        final station = stationSnapshot.data ?? widget.station;
        final currentUserId = AuthService.instance.currentUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
        final isCreator = currentUserId.isNotEmpty && station.creatorId == currentUserId;
        final coverHeight = kIsWeb ? 320.0 : 250.0;

        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: SafeArea(
            child: Column(
              children: [
                const StationUploadBannerWidget(),
                Expanded(
                  child: NestedScrollView(
                    headerSliverBuilder: (context, innerBoxIsScrolled) => [
                      _buildSliverAppBar(station, isCreator, coverHeight),
                      _buildSliverTabBar(),
                    ],
                    body: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildRecordedLivesTab(station, isCreator),
                        _buildStationDetailsTab(station),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _buildBottomActionBar(station, isCreator),
        );
      },
    );
  }

  Widget _buildSliverAppBar(StationModel station, bool isCreator, double coverHeight) {
    return SliverAppBar(
      expandedHeight: coverHeight,
      pinned: true,
      backgroundColor: const Color(0xFF0A0A0A),
      leading: IconButton(
        icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        if (station.isLive)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.5),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.radio, color: Colors.white, size: 14),
                const SizedBox(width: 6),
                Text(
                  'LIVE (${station.viewerCount})',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
          ),
        IconButton(
          icon: const Icon(LucideIcons.share2, color: Colors.white),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Station link copied to clipboard!')),
            );
          },
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            MediaContentPreview(
              type: station.coverType,
              contentUrl: station.image,
              height: coverHeight,
              autoPlayVideo: true,
            ),
            // Gradient Overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.3),
                      Colors.transparent,
                      Colors.black.withOpacity(0.85),
                    ],
                  ),
                ),
              ),
            ),
            // Content Info Overlay at bottom of cover
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          station.category,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (station.isLive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.circle, size: 6, color: Colors.white),
                              SizedBox(width: 4),
                              Text('LIVE NOW', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    station.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundImage: AvatarHelper.getSafeAvatarProvider(station.creatorAvatar),
                        backgroundColor: Colors.grey.shade900,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Hosted by ${station.creatorName}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      const Icon(LucideIcons.eye, size: 14, color: Colors.white60),
                      const SizedBox(width: 4),
                      Text('${station.viewerCount} Viewers', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverTabBar() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _SliverTabBarDelegate(
        TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(text: 'RECORDED LIVES'),
            Tab(text: 'ABOUT STATION'),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordedLivesTab(StationModel station, bool isCreator) {
    return Column(
      children: [
        // Search bar for recorded lives
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: TextField(
              controller: _recordedLivesSearchController,
              onChanged: (value) {
                setState(() => _recordedLivesSearchQuery = value.toLowerCase());
              },
              decoration: const InputDecoration(
                hintText: 'Search recorded broadcasts...',
                hintStyle: TextStyle(color: Colors.white38),
                prefixIcon: Icon(LucideIcons.search, color: Colors.white38),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<RecordedLiveModel>>(
            stream: _recordedLivesStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
              }

              final recordedLives = snapshot.data ?? [];
              final filteredLives = _recordedLivesSearchQuery.isEmpty
                  ? recordedLives
                  : recordedLives.where((live) =>
                      live.title.toLowerCase().contains(_recordedLivesSearchQuery)).toList();

              if (filteredLives.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _recordedLivesSearchQuery.isEmpty ? LucideIcons.videoOff : LucideIcons.search,
                        size: 64,
                        color: Colors.white12,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _recordedLivesSearchQuery.isEmpty
                            ? 'No recorded broadcasts yet'
                            : 'No broadcasts found',
                        style: const TextStyle(fontSize: 18, color: Colors.white54, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _recordedLivesSearchQuery.isEmpty
                            ? 'Go live to record and save your stream automatically'
                            : 'Try a different search term',
                        style: const TextStyle(fontSize: 13, color: Colors.white30),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filteredLives.length,
                itemBuilder: (context, index) {
                  final recorded = filteredLives[index];
                  return _buildRecordedLiveCard(recorded, station, isCreator);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecordedLiveCard(RecordedLiveModel recorded, StationModel station, bool isCreator) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WatchRecordedLiveScreen(
              recordedLive: recorded,
              station: station,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 160,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MediaContentPreview(
                      type: inferMediaTypeFromUrl(recorded.videoUrl),
                      contentUrl: recorded.videoUrl.isNotEmpty
                          ? recorded.videoUrl
                          : recorded.thumbnailUrl.isNotEmpty
                              ? recorded.thumbnailUrl
                              : station.image,
                      height: 160,
                      autoPlayVideo: false,
                    ),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.play, color: Colors.white, size: 28),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.clock, size: 12, color: AppTheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              recorded.formattedDuration,
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isCreator)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: GestureDetector(
                          onTap: () => _deleteRecordedLive(station.id, recorded.id),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.9),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(LucideIcons.trash2, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recorded.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundImage: AvatarHelper.getSafeAvatarProvider(recorded.hostAvatar),
                        backgroundColor: Colors.grey.shade900,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        recorded.hostName,
                        style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      const Icon(LucideIcons.calendar, size: 13, color: Colors.white38),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(recorded.recordedAt),
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      const SizedBox(width: 12),
                      const Icon(LucideIcons.eye, size: 13, color: Colors.white38),
                      const SizedBox(width: 4),
                      Text(
                        '${recorded.viewerCount}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationDetailsTab(StationModel station) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'STATION DESCRIPTION',
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            station.description,
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          const Text(
            'STATION DETAILS',
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5),
          ),
          const SizedBox(height: 12),
          _buildDetailRow(LucideIcons.tag, 'Category', station.category),
          _buildDetailRow(LucideIcons.mapPin, 'Location', '${station.city}, ${station.country}'),
          _buildDetailRow(LucideIcons.star, 'Rating', '${station.rating.toStringAsFixed(1)} (${station.reviewCount} Reviews)'),
          _buildDetailRow(LucideIcons.eye, 'Total Viewers', '${station.viewerCount} Viewers'),
          _buildDetailRow(LucideIcons.shield, 'Visibility', station.visibilityScope.toUpperCase()),
          const SizedBox(height: 24),
          const Text(
            'HOST CREATOR',
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: AvatarHelper.getSafeAvatarProvider(station.creatorAvatar),
                  backgroundColor: Colors.grey.shade900,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.creatorName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Station Owner & Host',
                        style: const TextStyle(color: AppTheme.primary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildStationReviews(station),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildStationReviews(StationModel station) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'STATION REVIEWS',
              style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            TextButton(
              onPressed: () => _showReviewDialog(station),
              child: const Text(
                'Write Review',
                style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<ReviewModel>>(
          stream: _firebaseService.getStationReviews(station.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
            }

            final reviews = snapshot.data ?? [];
            if (reviews.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(LucideIcons.star, size: 48, color: Colors.white12),
                      SizedBox(height: 12),
                      Text(
                        'No reviews yet',
                        style: TextStyle(fontSize: 14, color: Colors.white54),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Be the first to review this station',
                        style: TextStyle(fontSize: 12, color: Colors.white30),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: reviews.length,
              itemBuilder: (context, index) {
                final review = reviews[index];
                return _buildReviewCard(review);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildReviewCard(ReviewModel review) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundImage: review.userAvatar.isNotEmpty
                    ? NetworkImage(review.userAvatar)
                    : null,
                backgroundColor: Colors.grey.shade900,
                child: review.userAvatar.isEmpty
                    ? const Icon(LucideIcons.user, size: 16, color: Colors.white60)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.userName,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(review.timestamp),
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (index) {
                  return Icon(
                    index < review.ratingStars ? LucideIcons.star : LucideIcons.star,
                    size: 14,
                    color: index < review.ratingStars ? Colors.amber : Colors.white24,
                  );
                }),
              ),
            ],
          ),
          if (review.reviewText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              review.reviewText,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  void _showReviewDialog(StationModel station) {
    final currentUserId = AuthService.instance.currentUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to write a review')),
      );
      return;
    }

    final engine = Provider.of<RankingEngine>(context, listen: false);
    final userProfile = engine.currentUserProfile;
    if (userProfile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile not found')),
      );
      return;
    }

    int selectedRating = 5;
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Rate this Station', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      LucideIcons.star,
                      size: 32,
                      color: index < selectedRating ? Colors.amber : Colors.white24,
                    ),
                    onPressed: () => setState(() => selectedRating = index + 1),
                  );
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: commentController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Write your review (optional)',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.primary),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () async {
                final review = ReviewModel(
                  id: 'review_${userProfile.uid}_${DateTime.now().millisecondsSinceEpoch}',
                  userId: userProfile.uid,
                  userName: userProfile.displayName,
                  userAvatar: userProfile.photoURL,
                  ratingStars: selectedRating,
                  reviewText: commentController.text.trim(),
                  timestamp: DateTime.now(),
                );

                final success = await _firebaseService.addStationReview(station.id, review);
                if (mounted) {
                  Navigator.pop(context);
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Review submitted!'), backgroundColor: Colors.green),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('You have already reviewed this station'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(StationModel station, bool isCreator) {
    if (!isCreator && !station.isLive) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCreator && !station.isLive) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _deleteStation(station),
                  icon: const Icon(LucideIcons.trash2, size: 18),
                  label: const Text('DELETE STATION'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final engine = Provider.of<RankingEngine>(context, listen: false);
                  if (isCreator) {
                    _handleGoLive(station, engine);
                  } else {
                    _handleWatchLive(station, engine);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCreator
                      ? (station.isLive ? Colors.red : AppTheme.primary)
                      : Colors.red,
                  foregroundColor: Colors.white,
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isCreator
                          ? (station.isLive ? LucideIcons.square : LucideIcons.video)
                          : LucideIcons.radio,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isCreator
                          ? (station.isLive ? 'END LIVE STREAM' : 'GO LIVE NOW')
                          : 'JOIN LIVE STREAM',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                  ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleGoLive(StationModel station, RankingEngine engine) async {
    if (station.isLive) {
      await LiveSessionService().endStationSession(station.id);
      await _firebaseService.setStationLiveStatus(station.id, false);
      return;
    }

    // Ask for recording name before starting live
    String recordingName = '${station.title} - Live Broadcast';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Start Live Stream'),
          content: TextField(
            decoration: const InputDecoration(
              labelText: 'Recording Name',
              hintText: 'Enter a name for this live stream',
            ),
            autofocus: true,
            onChanged: (value) => recordingName = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Go Live'),
            ),
          ],
        ),
      ),
    );
    
    if (result != true) return;

    final channelId = 'station_${station.id}_${DateTime.now().millisecondsSinceEpoch}';
    _firebaseService.setStationLiveStatus(station.id, true, channelId: channelId);

    Navigator.push(
      context,
      PageRouteBuilder(
        fullscreenDialog: true,
        pageBuilder: (context, animation, secondaryAnimation) => ChangeNotifierProvider.value(
          value: engine,
          child: LiveStreamScreen(
            contest: station.toContestModel(),
            isHost: true,
            entryId: null,
            recordingName: recordingName.isNotEmpty ? recordingName : '${station.title} - Live Broadcast',
          ),
        ),
      ),
    );
  }

  void _handleWatchLive(StationModel station, RankingEngine engine) {
    Navigator.push(
      context,
      PageRouteBuilder(
        fullscreenDialog: true,
        pageBuilder: (context, animation, secondaryAnimation) => ChangeNotifierProvider.value(
          value: engine,
          child: LiveStreamScreen(
            contest: station.toContestModel(),
            isHost: false,
            entryId: null,
          ),
        ),
      ),
    );
  }

  void _deleteRecordedLive(String stationId, String recordedLiveId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Recording', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to delete this recording?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _firebaseService.deleteRecordedLive(stationId, recordedLiveId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording deleted'), backgroundColor: Colors.green),
        );
      }
    }
  }

  void _deleteStation(StationModel station) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Station', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to delete this station? This action cannot be undone.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _firebaseService.deleteStation(station.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Station deleted'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _SliverTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFF0A0A0A),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return false;
  }
}
