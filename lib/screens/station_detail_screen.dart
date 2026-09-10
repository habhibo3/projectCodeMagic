import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
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
  int _selectedFilterIndex = 0; // 0: All, 1: Popular, 2: Recent
  bool _isGridView = false;
  bool _isUploadingBanner = false;
  double _bannerUploadProgress = 0.0;

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
        final coverHeight = kIsWeb ? 442.0 : 338.0;

        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: SafeArea(
            child: Column(
              children: [
                const StationUploadBannerWidget(),
                if (_isUploadingBanner)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: const Color(0xFF1E1E22),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Updating station banner... (${(_bannerUploadProgress * 100).toInt()}%)',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
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

  // ---------------------------------------------------------------------------
  // TOP BANNER (HERO MEDIA WITH OWNER EDIT OPTION)
  // ---------------------------------------------------------------------------
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
          tooltip: 'Share Station',
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
            // Banner Media (Image / Video)
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
                      Colors.black.withOpacity(0.4),
                      Colors.transparent,
                      Colors.black.withOpacity(0.9),
                    ],
                  ),
                ),
              ),
            ),

            // Station Information Overlay at bottom of banner
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
                      const Spacer(),
                      // Owner Banner Edit Button
                      if (isCreator)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black.withOpacity(0.65),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: const BorderSide(color: Colors.white24, width: 1),
                            ),
                          ),
                          icon: const Icon(LucideIcons.camera, size: 14, color: Colors.white),
                          label: const Text(
                            'Edit Banner',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () => _showEditBannerSheet(station),
                        ),
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
                      const SizedBox(width: 12),
                      const Icon(LucideIcons.star, size: 14, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(station.rating.toStringAsFixed(1), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
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

  // ---------------------------------------------------------------------------
  // OWNER BANNER EDIT MODAL (IMAGE / VIDEO)
  // ---------------------------------------------------------------------------
  void _showEditBannerSheet(StationModel station) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141416),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(LucideIcons.image, color: AppTheme.primary, size: 20),
                    SizedBox(width: 10),
                    Text(
                      'Change Station Banner',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Upload an image or video to display at the top of your station.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 20),

                // Option 1: Upload Image
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  tileColor: const Color(0xFF1E1E22),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.image, color: AppTheme.primary, size: 20),
                  ),
                  title: const Text('Upload Photo / Image Banner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Supports JPG, PNG, WEBP', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  trailing: const Icon(LucideIcons.chevronRight, color: Colors.white38, size: 18),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUploadBanner(station, isVideo: false);
                  },
                ),
                const SizedBox(height: 10),

                // Option 2: Upload Video
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  tileColor: const Color(0xFF1E1E22),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.video, color: Colors.purpleAccent, size: 20),
                  ),
                  title: const Text('Upload Video Banner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Supports MP4, MOV videos', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  trailing: const Icon(LucideIcons.chevronRight, color: Colors.white38, size: 18),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUploadBanner(station, isVideo: true);
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadBanner(StationModel station, {required bool isVideo}) async {
    final picker = ImagePicker();
    XFile? picked;
    if (isVideo) {
      picked = await picker.pickVideo(source: ImageSource.gallery);
    } else {
      picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    }

    if (picked == null) return;

    setState(() {
      _isUploadingBanner = true;
      _bannerUploadProgress = 0.05;
    });

    try {
      final file = File(picked.path);
      final downloadUrl = await _firebaseService.uploadPostMedia(
        station.creatorId,
        file,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _bannerUploadProgress = progress);
          }
        },
      );

      await _firebaseService.updateStation(station.id, {
        'image': downloadUrl,
        'coverType': isVideo ? 'video' : 'image',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Station banner updated successfully! ✓'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update banner: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingBanner = false;
          _bannerUploadProgress = 0.0;
        });
      }
    }
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
            Tab(text: 'BROADCASTS'),
            Tab(text: 'ABOUT STATION'),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // RECORDED BROADCASTS TAB (SIMILAR TO STATION HOME PAGE FEED)
  // ---------------------------------------------------------------------------
  Widget _buildRecordedLivesTab(StationModel station, bool isCreator) {
    return StreamBuilder<List<RecordedLiveModel>>(
      stream: _recordedLivesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }

        final recordedLives = snapshot.data ?? [];
        final filteredLives = _getFilteredRecordedLives(recordedLives);

        return CustomScrollView(
          slivers: [
            // Top Controls Bar (Search + Filter Chips + Grid/List Toggle)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF141416),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: TextField(
                        controller: _recordedLivesSearchController,
                        onChanged: (value) {
                          setState(() => _recordedLivesSearchQuery = value.toLowerCase());
                        },
                        decoration: InputDecoration(
                          hintText: 'Search station broadcasts...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(LucideIcons.search, color: Colors.white38, size: 18),
                          suffixIcon: _recordedLivesSearchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(LucideIcons.x, color: Colors.white38, size: 16),
                                  onPressed: () {
                                    _recordedLivesSearchController.clear();
                                    setState(() => _recordedLivesSearchQuery = '');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),

                  // Filter Chips & View Mode Toggle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        _buildFilterChip('All', 0),
                        const SizedBox(width: 8),
                        _buildFilterChip('Most Popular', 1),
                        const SizedBox(width: 8),
                        _buildFilterChip('Recent', 2),
                        const Spacer(),
                        IconButton(
                          icon: Icon(_isGridView ? LucideIcons.list : LucideIcons.layoutGrid, color: Colors.white70, size: 18),
                          tooltip: _isGridView ? 'List View' : 'Grid View',
                          onPressed: () => setState(() => _isGridView = !_isGridView),
                        ),
                      ],
                    ),
                  ),

                  // Header with Count
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.radio, color: AppTheme.primary, size: 16),
                        const SizedBox(width: 6),
                        const Text(
                          'Station Broadcasts',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text(
                          '${filteredLives.length} available',
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),

            // Empty State
            if (filteredLives.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
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
                            ? 'No broadcasts yet'
                            : 'No matching broadcasts found',
                        style: const TextStyle(fontSize: 18, color: Colors.white54, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _recordedLivesSearchQuery.isEmpty
                            ? 'Go live to record and save your broadcast to this list automatically'
                            : 'Try searching with a different keyword',
                        style: const TextStyle(fontSize: 13, color: Colors.white30),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else if (kIsWeb)
              // Web Responsive Grid
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.crossAxisExtent > 1200
                        ? 4
                        : (constraints.crossAxisExtent > 800 ? 3 : 2);
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.88,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _buildGridRecordedLiveCard(filteredLives[i], station, isCreator),
                        childCount: filteredLives.length,
                      ),
                    );
                  },
                ),
              )
            else if (_isGridView)
              // Mobile Grid View
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.78,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _buildGridRecordedLiveCard(filteredLives[i], station, isCreator),
                    childCount: filteredLives.length,
                  ),
                ),
              )
            else
              // Mobile / Default List View (Matching Station Home Page List Cards)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _buildListRecordedLiveCard(filteredLives[i], station, isCreator),
                    childCount: filteredLives.length,
                  ),
                ),
              ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 80),
            ),
          ],
        );
      },
    );
  }

  List<RecordedLiveModel> _getFilteredRecordedLives(List<RecordedLiveModel> all) {
    var list = all.where((live) {
      if (_recordedLivesSearchQuery.isEmpty) return true;
      return live.title.toLowerCase().contains(_recordedLivesSearchQuery) ||
          live.hostName.toLowerCase().contains(_recordedLivesSearchQuery);
    }).toList();

    if (_selectedFilterIndex == 1) {
      // Popular (by viewerCount or votes)
      list.sort((a, b) => b.viewerCount.compareTo(a.viewerCount));
    } else if (_selectedFilterIndex == 2) {
      // Recent (by recordedAt)
      list.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    }

    return list;
  }

  Widget _buildFilterChip(String label, int index) {
    final selected = _selectedFilterIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilterIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? Colors.transparent : Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LIST CARD FOR RECORDED LIVES (MATCHING STATION HOME PAGE LIST CARD FORMAT)
  // ---------------------------------------------------------------------------
  Widget _buildListRecordedLiveCard(RecordedLiveModel recorded, StationModel station, bool isCreator) {
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
            // Top Media Preview
            SizedBox(
              height: 180,
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
                          : (recorded.thumbnailUrl.isNotEmpty ? recorded.thumbnailUrl : station.image),
                      height: 180,
                      autoPlayVideo: false,
                    ),
                    // Center Play Button
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
                    // Category Badge (Top Left)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          station.category,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    // Duration Badge (Bottom Right)
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.85),
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
                    // Creator Delete Action (Top Right)
                    if (isCreator)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: GestureDetector(
                          onTap: () => _deleteRecordedLive(station.id, recorded.id),
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.85),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(LucideIcons.trash2, color: Colors.white, size: 15),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Card Body Info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recorded.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17, height: 1.2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundImage: AvatarHelper.getSafeAvatarProvider(recorded.hostAvatar.isNotEmpty ? recorded.hostAvatar : station.creatorAvatar),
                        backgroundColor: Colors.grey.shade900,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Hosted by ${recorded.hostName.isNotEmpty ? recorded.hostName : station.creatorName}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      Text(
                        _formatDate(recorded.recordedAt),
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(LucideIcons.eye, size: 13, color: AppTheme.primary),
                      const SizedBox(width: 4),
                      Text('${recorded.viewerCount} Views', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(width: 14),
                      const Icon(LucideIcons.heart, size: 13, color: Colors.redAccent),
                      const SizedBox(width: 4),
                      Text('${recorded.likeCount} Likes', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      const Spacer(),
                      const Icon(LucideIcons.star, size: 13, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(station.rating.toStringAsFixed(1), style: const TextStyle(color: Colors.white70, fontSize: 11)),
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

  // ---------------------------------------------------------------------------
  // GRID CARD FOR RECORDED LIVES (MATCHING STATION HOME PAGE GRID CARD FORMAT)
  // ---------------------------------------------------------------------------
  Widget _buildGridRecordedLiveCard(RecordedLiveModel recorded, StationModel station, bool isCreator) {
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              MediaContentPreview(
                type: inferMediaTypeFromUrl(recorded.videoUrl),
                contentUrl: recorded.videoUrl.isNotEmpty
                    ? recorded.videoUrl
                    : (recorded.thumbnailUrl.isNotEmpty ? recorded.thumbnailUrl : station.image),
                height: double.infinity,
                autoPlayVideo: false,
              ),
              // Category badge
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    station.category,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              // Duration badge
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    recorded.formattedDuration,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              // Play Center Icon
              Center(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.play, color: Colors.white, size: 22),
                ),
              ),
              // Bottom Info Gradient Overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.95)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        recorded.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'by ${recorded.hostName.isNotEmpty ? recorded.hostName : station.creatorName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(LucideIcons.eye, size: 11, color: AppTheme.primary),
                          const SizedBox(width: 3),
                          Text('${recorded.viewerCount}', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                          const Spacer(),
                          Text(_formatDate(recorded.recordedAt), style: const TextStyle(color: Colors.white38, fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Creator delete button
              if (isCreator)
                Positioned(
                  top: 36,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => _deleteRecordedLive(station.id, recorded.id),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.85),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.trash2, color: Colors.white, size: 13),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ABOUT STATION TAB
  // ---------------------------------------------------------------------------
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
                      const Text(
                        'Station Owner & Host',
                        style: TextStyle(color: AppTheme.primary, fontSize: 12),
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
        StreamBuilder<List<ReviewModel>>(
          stream: _firebaseService.getStationReviews(station.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: AppTheme.primary)));
            }

            final reviews = snapshot.data ?? [];
            if (reviews.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Center(
                  child: Text('No reviews yet. Be the first to review!', style: TextStyle(color: Colors.white38, fontSize: 13)),
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: reviews.length,
              itemBuilder: (context, index) {
                final review = reviews[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
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
                            radius: 12,
                            backgroundImage: AvatarHelper.getSafeAvatarProvider(review.userAvatar),
                            backgroundColor: Colors.grey.shade900,
                          ),
                          const SizedBox(width: 8),
                          Text(review.userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          const Spacer(),
                          Row(
                            children: List.generate(5, (starIndex) {
                              return Icon(
                                starIndex < review.ratingStars ? LucideIcons.star : LucideIcons.star,
                                size: 12,
                                color: starIndex < review.ratingStars ? Colors.amber : Colors.white24,
                              );
                            }),
                          ),
                        ],
                      ),
                      if (review.reviewText.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(review.reviewText, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  void _showReviewDialog(StationModel station) {
    final userProfile = Provider.of<RankingEngine>(context, listen: false).currentUserProfile;
    if (userProfile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to submit a review')),
      );
      return;
    }

    int selectedRating = 5;
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Review Station', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      LucideIcons.star,
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
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(dialogContext);
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
                Navigator.pop(dialogContext);
                if (success) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Review submitted!'), backgroundColor: Colors.green),
                  );
                } else {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('You have already reviewed this station'),
                      backgroundColor: Colors.orange,
                    ),
                  );
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

  // ---------------------------------------------------------------------------
  // BOTTOM ACTION BAR (GO LIVE / WATCH LIVE / DELETE STATION)
  // ---------------------------------------------------------------------------
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

    String recordingName = '${station.title} - Live Broadcast';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Start Live Stream', style: TextStyle(color: Colors.white)),
          content: TextField(
            decoration: const InputDecoration(
              labelText: 'Recording Name',
              labelStyle: TextStyle(color: Colors.white70),
              hintText: 'Enter a name for this live stream',
              hintStyle: TextStyle(color: Colors.white30),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary)),
            ),
            style: const TextStyle(color: Colors.white),
            autofocus: true,
            onChanged: (value) => recordingName = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Go Live'),
            ),
          ],
        ),
      ),
    );
    
    if (result != true) return;

    final channelId = 'station_${station.id}_${DateTime.now().millisecondsSinceEpoch}';
    _firebaseService.setStationLiveStatus(station.id, true, channelId: channelId);

    if (mounted) {
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
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
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
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
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
