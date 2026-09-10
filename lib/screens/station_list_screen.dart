import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../data/firebase_service.dart';
import '../engine/ranking_engine.dart';
import '../models/station.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_helper.dart';
import '../widgets/media_content_preview.dart';
import 'station_detail_screen.dart';
import 'create_station_screen.dart';

class StationListScreen extends StatefulWidget {
  final ValueNotifier<String>? webSearchNotifier;
  final ValueNotifier<String>? webCategoryNotifier;

  const StationListScreen({
    super.key,
    this.webSearchNotifier,
    this.webCategoryNotifier,
  });

  @override
  State<StationListScreen> createState() => _StationListScreenState();
}

class _StationListScreenState extends State<StationListScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  int _selectedTabIndex = 0;
  bool _isGridView = false;
  bool _isSearching = false;
  String _searchQuery = '';
  String _selectedCategory = 'All';
  final TextEditingController _searchController = TextEditingController();
  final List<String> _categories = ['All', 'Music', 'Dance', 'Comedy', 'Art', 'Sports', 'Gaming', 'Talk', 'News'];

  @override
  void initState() {
    super.initState();
    widget.webCategoryNotifier?.addListener(_onWebCategoryChanged);
    widget.webSearchNotifier?.addListener(_onWebSearchChanged);
    if (widget.webCategoryNotifier != null) {
      _selectedCategory = widget.webCategoryNotifier!.value;
    }
    if (widget.webSearchNotifier != null) {
      _searchQuery = widget.webSearchNotifier!.value.trim().toLowerCase();
    }
  }

  @override
  void dispose() {
    widget.webCategoryNotifier?.removeListener(_onWebCategoryChanged);
    widget.webSearchNotifier?.removeListener(_onWebSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onWebCategoryChanged() {
    if (mounted && widget.webCategoryNotifier != null) {
      setState(() {
        _selectedCategory = widget.webCategoryNotifier!.value;
      });
    }
  }

  void _onWebSearchChanged() {
    if (mounted && widget.webSearchNotifier != null) {
      setState(() {
        _searchQuery = widget.webSearchNotifier!.value.trim().toLowerCase();
      });
    }
  }

  List<StationModel> _getFilteredStations(List<StationModel> allStations) {
    return allStations.where((s) {
      final query = _searchQuery.trim().toLowerCase();
      final matchesQuery = query.isEmpty ||
          s.title.toLowerCase().contains(query) ||
          s.description.toLowerCase().contains(query) ||
          s.creatorName.toLowerCase().contains(query) ||
          s.category.toLowerCase().contains(query) ||
          s.city.toLowerCase().contains(query) ||
          s.country.toLowerCase().contains(query);
      final matchesCategory = _selectedCategory == 'All' ||
          s.category.toLowerCase() == _selectedCategory.toLowerCase();
      
      bool matchesTab = true;
      if (_selectedTabIndex == 1) { // Live only
        matchesTab = s.isLive;
      } else if (_selectedTabIndex == 2) { // Trending
        matchesTab = s.viewerCount > 0 || s.rating >= 4.0;
      }
      
      return matchesQuery && matchesCategory && matchesTab;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Consumer<RankingEngine>(
            builder: (context, engine, _) {
              final profile = engine.currentUserProfile;
              final hasPhoto = profile != null && profile.photoURL.isNotEmpty;
              return CircleAvatar(
                backgroundImage: hasPhoto ? AvatarHelper.getSafeAvatarProvider(profile.photoURL) : null,
                backgroundColor: Colors.grey.shade900,
                child: !hasPhoto 
                    ? const Icon(LucideIcons.user, size: 16, color: Colors.white60) 
                    : null,
              );
            },
          ),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                decoration: const InputDecoration(
                  hintText: 'Search stations...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.white54),
                ),
                style: const TextStyle(color: Colors.white),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.radio, color: AppTheme.primary),
                  SizedBox(width: 8),
                  Text('STATIONS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1)),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? LucideIcons.x : LucideIcons.search, color: Colors.white),
            onPressed: () => setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchController.clear();
                _searchQuery = '';
              }
            }),
          ),
          IconButton(
            icon: Icon(_isGridView ? LucideIcons.list : LucideIcons.layoutGrid, color: Colors.white),
            onPressed: () => setState(() => _isGridView = !_isGridView),
            tooltip: _isGridView ? 'List View' : 'Grid View',
          ),
        ],
      ),
      body: StreamBuilder<List<StationModel>>(
        stream: _firebaseService.getStations(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }

          final allStations = snapshot.data ?? [];
          final filteredStations = _getFilteredStations(allStations);
          final featuredStation = allStations.isNotEmpty
              ? (allStations.firstWhere((s) => s.isLive, orElse: () => allStations.first))
              : null;

          if (kIsWeb) {
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 20),
              children: [
                // Web category chips
                _buildWebCategoryChips(),
                const SizedBox(height: 16),

                // Top Hero Advertisers Banner
                if (allStations.isNotEmpty && _searchQuery.isEmpty)
                  _WebStationAdvertiserBanner(
                    advertisers: allStations,
                    onOpenStation: _openStation,
                  ),

                // Section header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.radio, color: AppTheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _selectedCategory != 'All' ? '$_selectedCategory Stations' : 'All Stations',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${filteredStations.length} available',
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Main Station Grid (Unlimited Continuous Scroll)
                if (filteredStations.isEmpty)
                  _buildEmptyState()
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisCount = constraints.maxWidth > 1200 ? 4 : (constraints.maxWidth > 800 ? 3 : 2);
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 20,
                            childAspectRatio: 1.1,
                          ),
                          itemCount: filteredStations.length,
                          itemBuilder: (ctx, i) => _buildWebStationCard(ctx, filteredStations[i]),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 80),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top tabs
              _buildTopTabs(),
              // Category chips
              _buildCategoryChips(),
              // Featured station banner
              if (featuredStation != null && _searchQuery.isEmpty)
                _buildFeaturedStationBanner(featuredStation),
              // Main station feed
              Expanded(
                child: filteredStations.isEmpty
                    ? _buildEmptyState()
                    : _buildStationFeed(filteredStations),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'station_fab',
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(LucideIcons.plus, size: 24),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateStationScreen()),
          );
        },
      ),
    );
  }

  Widget _buildTopTabs() {
    final tabs = ['For you', 'Live Now', 'Trending', 'Following'];
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: List.generate(tabs.length, (i) {
            final active = _selectedTabIndex == i;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _selectedTabIndex = i),
              child: Padding(
                padding: const EdgeInsets.only(right: 24),
                child: Column(
                  children: [
                    Text(
                      tabs[i],
                      style: TextStyle(
                        fontWeight: active ? FontWeight.bold : FontWeight.w500,
                        color: active ? Colors.white : Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                    if (active)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        height: 3,
                        width: 24,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _categories.length,
        itemBuilder: (_, i) {
          final cat = _categories[i];
          final selected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () => setState(() => _selectedCategory = cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: selected ? AppTheme.pinkPurpleGradient : null,
                  color: selected ? null : const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: selected ? Colors.transparent : Colors.white12),
                ),
                child: Text(
                  cat,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeaturedStationBanner(StationModel station) {
    return GestureDetector(
      onTap: () => _openStation(station),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 70,
                height: 50,
                child: MediaContentPreview(
                  type: station.coverType,
                  contentUrl: station.image,
                  height: 50,
                  autoPlayVideo: false,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: station.isLive ? Colors.red : AppTheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          station.isLive ? 'LIVE NOW' : 'FEATURED',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        station.category,
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    station.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.white54, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(LucideIcons.radio, size: 64, color: Colors.white12),
          const SizedBox(height: 16),
          Text(
            _selectedTabIndex == 1 ? 'No live stations right now' : 'No stations found',
            style: const TextStyle(fontSize: 18, color: Colors.white54, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Create your station to start broadcasting live', style: TextStyle(fontSize: 13, color: Colors.white30)),
        ],
      ),
    );
  }

  Widget _buildStationFeed(List<StationModel> stations) {
    if (_isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.78,
        ),
        itemCount: stations.length,
        itemBuilder: (context, index) => _buildGridCard(stations[index]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: stations.length,
      itemBuilder: (context, index) => _buildListCard(stations[index]),
    );
  }

  Widget _buildGridCard(StationModel station) {
    return GestureDetector(
      onTap: () => _openStation(station),
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
                type: station.coverType,
                contentUrl: station.image,
                height: double.infinity,
                autoPlayVideo: true,
              ),
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
              if (station.isLive)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.circle, size: 6, color: Colors.white),
                        SizedBox(width: 4),
                        Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'by ${station.creatorName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(LucideIcons.eye, size: 12, color: AppTheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            '${station.viewerCount}',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                          const Spacer(),
                          const Icon(LucideIcons.star, size: 12, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            station.rating.toStringAsFixed(1),
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListCard(StationModel station) {
    return GestureDetector(
      onTap: () => _openStation(station),
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
              height: 180,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MediaContentPreview(
                      type: station.coverType,
                      contentUrl: station.image,
                      height: 180,
                      autoPlayVideo: true,
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          station.category,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    if (station.isLive)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.circle, size: 8, color: Colors.white),
                              SizedBox(width: 4),
                              Text('LIVE NOW', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, height: 1.2),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundImage: AvatarHelper.getSafeAvatarProvider(station.creatorAvatar),
                        backgroundColor: Colors.grey.shade900,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Created by ${station.creatorName}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      Text(
                        '${station.city}, ${station.country}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    station.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Divider(height: 1, color: Colors.white12),
                  ),
                  Row(
                    children: [
                      const Icon(LucideIcons.eye, size: 14, color: AppTheme.primary),
                      const SizedBox(width: 6),
                      Text('${station.viewerCount} Viewers', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                      const Spacer(),
                      const Icon(LucideIcons.star, size: 14, color: Colors.amber),
                      const SizedBox(width: 6),
                      Text('${station.rating.toStringAsFixed(1)} (${station.reviewCount} Reviews)', style: const TextStyle(fontSize: 12, color: Colors.white70)),
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

  Widget _buildWebCategoryChips() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (_, i) {
          final cat = _categories[i];
          final selected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedCategory = cat);
                widget.webCategoryNotifier?.value = cat;
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: selected ? AppTheme.pinkPurpleGradient : null,
                  color: selected ? null : const Color(0xFF1E1E22),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: selected ? Colors.transparent : Colors.white12),
                ),
                child: Text(
                  cat,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWebStationCard(BuildContext context, StationModel station) {
    return GestureDetector(
      onTap: () => _openStation(station),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141416),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MediaContentPreview(
                      type: station.coverType,
                      contentUrl: station.image,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      autoPlayVideo: true,
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          station.category,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    if (station.isLive)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.circle, size: 7, color: Colors.white),
                              SizedBox(width: 4),
                              Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    station.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 10,
                        backgroundImage: AvatarHelper.getSafeAvatarProvider(station.creatorAvatar),
                        backgroundColor: Colors.grey.shade900,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          station.creatorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 12, color: Colors.white12),
                  Row(
                    children: [
                      const Icon(LucideIcons.eye, size: 12, color: AppTheme.primary),
                      const SizedBox(width: 4),
                      Text('${station.viewerCount}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                      const Spacer(),
                      const Icon(LucideIcons.star, size: 12, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(station.rating.toStringAsFixed(1), style: const TextStyle(fontSize: 11, color: Colors.white70)),
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

  void _openStation(StationModel station) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StationDetailScreen(station: station),
      ),
    );
  }
}

/// Web Hero Banner section for station advertisers.
/// - Rotates randomly among up to 12 advertisers every 11 seconds.
/// - Videos play muted by default with an on-screen speaker toggle.
/// - Sound & video pause immediately on dispose / navigation.
/// - Clicking banner opens the advertiser station/link.
class _WebStationAdvertiserBanner extends StatefulWidget {
  final List<StationModel> advertisers;
  final Function(StationModel) onOpenStation;

  const _WebStationAdvertiserBanner({
    required this.advertisers,
    required this.onOpenStation,
  });

  @override
  State<_WebStationAdvertiserBanner> createState() => _WebStationAdvertiserBannerState();
}

class _WebStationAdvertiserBannerState extends State<_WebStationAdvertiserBanner> {
  late PageController _pageController;
  Timer? _rotationTimer;
  int _currentIndex = 0;
  bool _isMuted = true;
  List<StationModel> _advertiserList = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _initAdvertisers();
  }

  void _initAdvertisers() {
    _advertiserList = List<StationModel>.from(widget.advertisers)..shuffle();
    if (_advertiserList.length > 12) {
      _advertiserList = _advertiserList.take(12).toList();
    }
    _startRotationTimer();
  }

  @override
  void didUpdateWidget(covariant _WebStationAdvertiserBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.advertisers.length != widget.advertisers.length) {
      _initAdvertisers();
    }
  }

  void _startRotationTimer() {
    _rotationTimer?.cancel();
    if (_advertiserList.length <= 1) return;

    _rotationTimer = Timer.periodic(const Duration(seconds: 11), (timer) {
      if (!mounted || _advertiserList.isEmpty) return;
      final nextIndex = (_currentIndex + 1) % _advertiserList.length;
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_advertiserList.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      height: 494,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF141416),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: _advertiserList.length,
              onPageChanged: (i) {
                setState(() {
                  _currentIndex = i;
                });
              },
              itemBuilder: (context, index) {
                final station = _advertiserList[index];
                return GestureDetector(
                  onTap: () => widget.onOpenStation(station),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Background Image / Video
                      MediaContentPreview(
                        type: station.coverType,
                        contentUrl: station.image,
                        height: 494,
                        fit: BoxFit.cover,
                        autoPlayVideo: true,
                        forceAutoPlay: true,
                      ),

                      // Gradient Overlay (Dark on left for text readability)
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.black.withOpacity(0.85),
                              Colors.black.withOpacity(0.45),
                              Colors.black.withOpacity(0.15),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.4, 0.7, 1.0],
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.9),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.6],
                          ),
                        ),
                      ),

                      // Station Information Overlay (Bottom Left)
                      Positioned(
                        left: 32,
                        bottom: 32,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 420),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (station.isLive) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(LucideIcons.circle, size: 8, color: Colors.white),
                                      SizedBox(width: 4),
                                      Text(
                                        'LIVE NOW',
                                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              Text(
                                station.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
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
                                    'Created by ${station.creatorName}',
                                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                              if (station.description.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  station.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.3),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(LucideIcons.eye, size: 14, color: AppTheme.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${station.viewerCount} Viewers',
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                  const SizedBox(width: 16),
                                  const Icon(LucideIcons.star, size: 14, color: Colors.amber),
                                  const SizedBox(width: 4),
                                  Text(
                                    station.rating.toStringAsFixed(1),
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Top Right: Speaker Mute/Unmute toggle
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: IconButton(
                  icon: Icon(
                    _isMuted ? LucideIcons.volumeX : LucideIcons.volume2,
                    color: Colors.white,
                    size: 20,
                  ),
                  tooltip: _isMuted ? 'Unmute' : 'Mute',
                  onPressed: () {
                    setState(() {
                      _isMuted = !_isMuted;
                    });
                  },
                ),
              ),
            ),

            // Bottom Center: Carousel Indicators / Dots
            if (_advertiserList.length > 1)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_advertiserList.length, (i) {
                    final active = _currentIndex == i;
                    return GestureDetector(
                      onTap: () {
                        _pageController.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active ? AppTheme.primary : Colors.white30,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
