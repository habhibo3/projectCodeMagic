import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../data/auth_service.dart';
import '../data/locale_country.dart';
import '../engine/ranking_engine.dart';
import '../models/entry.dart';
import '../models/post.dart';
import '../models/user.dart';
import '../models/notification.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_helper.dart';
import '../widgets/video_player_widget.dart';
import 'contest_detail_screen.dart';
import 'create_post_screen.dart';
import 'create_contest_screen.dart';
import 'entry_post_screen.dart';
import 'post_detail_screen.dart';
import 'public_profile_screen.dart';
import 'feed_screen.dart';
import 'edit_post_screen.dart';
import 'subscription_upgrade_screen.dart';

// ---------------------------------------------------------------------------
// ROOT SHELL — holds the persistent BottomNavigationBar + nested Navigator
// ---------------------------------------------------------------------------
class ContestListScreen extends StatefulWidget {
  const ContestListScreen({super.key, this.onWebNavChange, this.webNavNotifier});

  static final GlobalKey<NavigatorState> homeNavKey = GlobalKey<NavigatorState>();
  final Function(int)? onWebNavChange;
  final ValueNotifier<int?>? webNavNotifier;

  @override
  State<ContestListScreen> createState() => _ContestListScreenState();
}

class _ContestListScreenState extends State<ContestListScreen> {
  int _bottomNavIndex = 0;

  late final List<GlobalKey<NavigatorState>> _navKeys = [
    ContestListScreen.homeNavKey,
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  @override
  void initState() {
    super.initState();
    widget.webNavNotifier?.addListener(_onWebNavChange);
  }

  @override
  void dispose() {
    widget.webNavNotifier?.removeListener(_onWebNavChange);
    super.dispose();
  }

  void _onWebNavChange() {
    final index = widget.webNavNotifier?.value;
    if (index != null) {
      navigateToTab(index);
    }
  }

  void navigateToTab(int index) {
    if (index == _bottomNavIndex) {
      _navKeys[index].currentState?.popUntil((r) => r.isFirst);
    }
    setState(() => _bottomNavIndex = index);
    widget.onWebNavChange?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        final navState = _navKeys[_bottomNavIndex].currentState;
        if (navState != null && navState.canPop()) {
          navState.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: IndexedStack(
          index: _bottomNavIndex,
          children: [
            Navigator(
              key: _navKeys[0],
              onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const _HomeTab()),
            ),
            Navigator(
              key: _navKeys[1],
              onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const _MapTab()),
            ),
            Navigator(
              key: _navKeys[2],
              onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const FeedScreen()),
            ),
            Navigator(
              key: _navKeys[3],
              onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const _ActivityTab()),
            ),
            Navigator(
              key: _navKeys[4],
              onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const _UserProfileTab()),
            ),
          ],
        ),
        bottomNavigationBar: kIsWeb
            ? null
            : Theme(
          data: ThemeData(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: BottomNavigationBar(
              currentIndex: _bottomNavIndex,
              backgroundColor: const Color(0xFF0A0A0A),
              type: BottomNavigationBarType.fixed,
              selectedItemColor: AppTheme.primary,
              unselectedItemColor: Colors.white38,
              showSelectedLabels: true,
              showUnselectedLabels: true,
              selectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, height: 1.5),
              unselectedLabelStyle: const TextStyle(fontSize: 10, height: 1.5),
              onTap: (index) {
                if (index == _bottomNavIndex) {
                  _navKeys[index].currentState?.popUntil((r) => r.isFirst);
                }
                setState(() => _bottomNavIndex = index);
                widget.onWebNavChange?.call(index);
              },
              items: const [
                BottomNavigationBarItem(icon: Icon(LucideIcons.home), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(LucideIcons.map), label: 'Map'),
                BottomNavigationBarItem(icon: Icon(LucideIcons.flame), label: 'Explore Feed'),
                BottomNavigationBarItem(icon: Icon(LucideIcons.bell), label: 'Activity'),
                BottomNavigationBarItem(icon: Icon(LucideIcons.user), label: 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HOME TAB — feed with search, categories, grid/list toggle
// ---------------------------------------------------------------------------
class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  int _selectedTabIndex = 0;
  bool _isGridView = false;
  bool _isSearching = false;
  String _searchQuery = '';
  String _selectedCategory = 'All';
  final TextEditingController _searchController = TextEditingController();
  final List<String> _categories = ['All', 'Music', 'Dance', 'Comedy', 'Art', 'Sports'];

  List<ContestModel> _getFilteredContests(List<ContestModel> allContests, RankingEngine engine) {
    return allContests.where((c) {
      final matchesQuery = c.title.toLowerCase().contains(_searchQuery) ||
          c.subtitle.toLowerCase().contains(_searchQuery);
      final matchesCategory =
          _selectedCategory == 'All' || c.category == _selectedCategory;
          
      bool matchesTab = true;
      if (_selectedTabIndex == 1) { // Following
        matchesTab = engine.followedContestIds.contains(c.id);
      }
      
      return matchesQuery && matchesCategory && matchesTab;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RankingEngine>(
      builder: (context, engine, child) {
        final filteredContests = _getFilteredContests(engine.contests, engine);
        
        final profile = engine.currentUserProfile;
        final hasPhoto = profile != null && profile.photoURL.isNotEmpty;

        return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundImage: hasPhoto ? AvatarHelper.getSafeAvatarProvider(profile.photoURL) : null,
            backgroundColor: Colors.grey.shade900,
            child: !hasPhoto 
                ? const Icon(LucideIcons.user, size: 16, color: Colors.white60) 
                : null,
          ),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                decoration: const InputDecoration(
                  hintText: 'Search contests...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.white54),
                ),
                style: const TextStyle(color: Colors.white),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.flame, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  const Text('MLIVECAST', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1)),
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top tabs
          _buildTopTabs(),
          // Category chips
          _buildCategoryChips(),
          // Trending banner
          _buildTrendingBar(),
          // Contest list / grid
          Expanded(child: _buildContestFeed(filteredContests)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(LucideIcons.trophy, size: 24),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateContestScreen()),
          );
        },
      ),
    );
      },
    );
  }

  Widget _buildTopTabs() {
    final tabs = ['For you', 'Following', 'Subscribed', 'Trending'];
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
                    Text(tabs[i],
                        style: TextStyle(
                          fontWeight: active ? FontWeight.bold : FontWeight.w500,
                          color: active ? Colors.white : Colors.white54,
                          fontSize: 14,
                        )),
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
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 12),
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: selected ? AppTheme.pinkPurpleGradient : null,
                  color: selected ? null : const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: selected ? Colors.transparent : Colors.white12),
                ),
                child: Text(cat,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    )),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTrendingBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(LucideIcons.flame, color: AppTheme.primary, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text('Trending Now: The Next Star Talent Contest',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Icon(LucideIcons.chevronRight, color: Colors.white54, size: 16),
        ],
      ),
    );
  }

  Widget _buildContestFeed(List<ContestModel> contests) {
    if (contests.isEmpty) {
      String emptyMessage = 'No contests found';
      String emptySubtitle = 'Try a different search or category';
      if (_selectedTabIndex == 1) {
        emptyMessage = 'No followed contests yet';
        emptySubtitle = 'Open a contest and tap FOLLOW to see it here';
      } else if (_selectedTabIndex == 2) {
        emptyMessage = 'No subscribed contests';
        emptySubtitle = 'Subscribe to contests to see them here';
      } else if (_selectedTabIndex == 3) {
        emptyMessage = 'Nothing trending right now';
        emptySubtitle = 'Check back soon!';
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.inbox, size: 64, color: Colors.white12),
            const SizedBox(height: 16),
            Text(emptyMessage, style: const TextStyle(fontSize: 18, color: Colors.white54)),
            const SizedBox(height: 8),
            Text(emptySubtitle, style: const TextStyle(fontSize: 13, color: Colors.white30), textAlign: TextAlign.center),
          ],
        ),
      );
    }

    if (_isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.75,
        ),
        itemCount: contests.length,
        itemBuilder: (ctx, i) => _buildGridCard(ctx, contests[i]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      itemCount: contests.length,
      itemBuilder: (ctx, i) => _buildListCard(ctx, contests[i]),
    );
  }

  void _openContest(BuildContext context, ContestModel contest) {
    final engine = Provider.of<RankingEngine>(context, listen: false);
    engine.loadContestEntries(contest.id);

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ContestDetailScreen(contest: contest)),
    );
  }

  Widget _buildListCard(BuildContext context, ContestModel contest) {
    return GestureDetector(
      onTap: () => _openContest(context, contest),
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image header
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Stack(
                children: [
                  Image.network(contest.image,
                      height: 220, width: double.infinity, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(height: 220, color: Colors.grey.shade900)),
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, const Color(0xFF121212).withValues(alpha: 0.9)],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(contest.category,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (contest.type == 'Official')
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.checkCircle, size: 12, color: Colors.black),
                            SizedBox(width: 4),
                            Text('OFFICIAL', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contest.title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20, height: 1.2)),
                  const SizedBox(height: 6),
                  StreamBuilder<UserModel?>(
                    stream: Provider.of<RankingEngine>(context, listen: false).watchUserProfile(contest.creatorId),
                    builder: (context, snapshot) {
                      final name = snapshot.data?.displayName ?? 'Organizer';
                      return Row(
                        children: [
                          const Icon(LucideIcons.user, size: 12, color: Colors.white54),
                          const SizedBox(width: 4),
                          Text(
                            'Organized by $name',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(contest.subtitle,
                      style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(LucideIcons.clock, size: 14, color: Colors.white54),
                      const SizedBox(width: 6),
                      Text('Ends in ${contest.calculatedEndsIn}',
                          style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      const SizedBox(width: 20),
                      const Icon(LucideIcons.users, size: 14, color: Colors.white54),
                      const SizedBox(width: 6),
                      Text('${contest.participantCount} Participants',
                          style: const TextStyle(fontSize: 12, color: Colors.white54)),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(height: 1, color: Colors.white12),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStat(
                        LucideIcons.barChart2,
                        contest.totalVotes >= 1000
                            ? '${(contest.totalVotes / 1000).toStringAsFixed(1)}K'
                            : '${contest.totalVotes}',
                        'Total Votes',
                        color: AppTheme.primary,
                      ),
                      Container(width: 1, height: 40, color: Colors.white12),
                      _buildStat(
                        LucideIcons.star,
                        contest.rating.toStringAsFixed(1),
                        '${contest.reviewCount} Reviews',
                        color: Colors.orange,
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

  Widget _buildGridCard(BuildContext context, ContestModel contest) {
    return GestureDetector(
      onTap: () => _openContest(context, contest),
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
              Image.network(contest.image, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade900)),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)],
                  ),
                ),
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
                  child: Text(contest.category,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contest.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, height: 1.2)),
                    const SizedBox(height: 4),
                    StreamBuilder<UserModel?>(
                      stream: Provider.of<RankingEngine>(context, listen: false).watchUserProfile(contest.creatorId),
                      builder: (context, snapshot) {
                        final name = snapshot.data?.displayName ?? 'Organizer';
                        return Text(
                          'by $name',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(LucideIcons.heart, size: 12, color: AppTheme.primary),
                        const SizedBox(width: 4),
                        Text(contest.totalVotes >= 1000 ? '${(contest.totalVotes / 1000).toStringAsFixed(1)}K' : '${contest.totalVotes}',
                            style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        const Spacer(),
                        const Icon(LucideIcons.users, size: 12, color: Colors.white54),
                        const SizedBox(width: 4),
                        Text('${contest.participantCount}',
                            style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStat(IconData icon, String value, String label, {required Color color}) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ],
    );
  }
}

class _UserProfileTab extends StatefulWidget {
  const _UserProfileTab();

  @override
  State<_UserProfileTab> createState() => _UserProfileTabState();
}

class _UserProfileTabState extends State<_UserProfileTab> {
  final _nameController = TextEditingController();
  final _zipController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  String? _loadedForUid;

  String _formatTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inDays >= 7) {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } else if (difference.inDays >= 1) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Widget _buildVideoPlayer(String videoUrl) {
    final isLocal = !videoUrl.startsWith('http');
    return VideoPlayerWidget(videoUrl: videoUrl, isLocal: isLocal);
  }

  Widget _buildPostCard(BuildContext context, PostModel post, RankingEngine engine) {
    final viewer = engine.currentUserProfile;
    final isLiked = viewer != null && post.likes.contains(viewer.uid);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PublicProfileScreen(userId: post.userId),
                      ),
                    );
                  },
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage: post.userAvatar.isNotEmpty
                        ? AvatarHelper.getSafeAvatarProvider(post.userAvatar)
                        : null,
                    backgroundColor: Colors.grey.shade900,
                    child: post.userAvatar.isEmpty
                        ? const Icon(LucideIcons.user, size: 18, color: Colors.white60)
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PublicProfileScreen(userId: post.userId),
                            ),
                          );
                        },
                        child: Text(
                          post.userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            _formatTimeAgo(post.createdAt),
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                          ),
                          const SizedBox(width: 4),
                          const Icon(LucideIcons.dot, color: Colors.white38, size: 8),
                          const SizedBox(width: 4),
                          const Icon(LucideIcons.mapPin, size: 8, color: Colors.white38),
                          const SizedBox(width: 2),
                          Text(
                            post.location.isNotEmpty ? post.location : 'Unknown',
                            style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.moreHorizontal, color: Colors.white38, size: 16),
                  onPressed: () {
                    final isOwner = post.userId == engine.currentUserId;
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: const Color(0xFF141416),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (context) => Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isOwner) ...[
                              ListTile(
                                leading: const Icon(LucideIcons.pencil, color: Colors.white),
                                title: const Text('Edit post', style: TextStyle(color: Colors.white)),
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EditPostScreen(post: post),
                                    ),
                                  );
                                },
                              ),
                              ListTile(
                                leading: const Icon(LucideIcons.trash2, color: Colors.red),
                                title: const Text('Delete post', style: TextStyle(color: Colors.red)),
                                onTap: () async {
                                  Navigator.pop(context);
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      backgroundColor: const Color(0xFF141416),
                                      title: const Text('Delete Post', style: TextStyle(color: Colors.white)),
                                      content: const Text('Are you sure you want to delete this post?', style: TextStyle(color: Colors.white70)),
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
                                    await engine.deletePost(post.id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Post deleted'), behavior: SnackBarBehavior.floating, backgroundColor: Colors.green),
                                      );
                                    }
                                  }
                                },
                              ),
                              const Divider(color: Colors.white12),
                            ],
                            ListTile(
                              leading: const Icon(LucideIcons.bookmark, color: Colors.white),
                              title: const Text('Save post', style: TextStyle(color: Colors.white)),
                              onTap: () {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Post saved!'), behavior: SnackBarBehavior.floating),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(LucideIcons.flag, color: Colors.white),
                              title: const Text('Report post', style: TextStyle(color: Colors.white)),
                              onTap: () {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Post reported'), behavior: SnackBarBehavior.floating),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(LucideIcons.link, color: Colors.white),
                              title: const Text('Copy link', style: TextStyle(color: Colors.white)),
                              onTap: () {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Link copied to clipboard!'), behavior: SnackBarBehavior.floating),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Caption
          if (post.caption.isNotEmpty && post.type != 'text')
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
              child: Text(
                post.caption,
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
              ),
            ),

          // Post Media / Content
          if (post.type == 'text')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF1C1C1E), const Color(0xFF121214)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                post.contentUrl,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            )
          else if (post.type == 'image')
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PostDetailScreen(postId: post.id),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(0),
                child: AvatarHelper.getSafePostImage(
                  post.contentUrl,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            )
          else if (post.type == 'video')
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PostDetailScreen(postId: post.id),
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                height: 240,
                color: Colors.black,
                child: post.contentUrl.isNotEmpty
                    ? _buildVideoPlayer(post.contentUrl)
                    : const Center(
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.black54,
                          child: Icon(LucideIcons.play, color: Colors.white, size: 24),
                        ),
                      ),
              ),
            ),

          // Like & Comment Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Like
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => engine.toggleLikePost(post.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          color: isLiked ? AppTheme.primary : Colors.white60,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${post.likes.length}',
                          style: TextStyle(
                            color: isLiked ? Colors.white : Colors.white60,
                            fontWeight: isLiked ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Comment
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PostDetailScreen(postId: post.id),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.messageCircle, color: Colors.white60, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          '${post.commentsCount}',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                // Share
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: const Color(0xFF141416),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (context) => Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(LucideIcons.share2, color: Colors.white),
                              title: const Text('Share to...', style: TextStyle(color: Colors.white)),
                              onTap: () {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Share menu opened'), behavior: SnackBarBehavior.floating),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(LucideIcons.messageCircle, color: Colors.white),
                              title: const Text('Send in message', style: TextStyle(color: Colors.white)),
                              onTap: () {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Message feature coming soon'), behavior: SnackBarBehavior.floating),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(LucideIcons.copy, color: Colors.white),
                              title: const Text('Copy post', style: TextStyle(color: Colors.white)),
                              onTap: () {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Post copied to clipboard'), behavior: SnackBarBehavior.floating),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Icon(LucideIcons.share2, color: Colors.white60, size: 18),
                  ),
                ),
              ],
            ),
          ),

          // Divider
          const Divider(color: Colors.white12, height: 1),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _zipController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  void _showCreateContestDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final subtitleCtrl = TextEditingController();
    final prizeCtrl = TextEditingController();
    String selectedCat = 'Music';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF151515),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppTheme.primary, width: 1.2),
              ),
              title: const Row(
                children: [
                  Icon(LucideIcons.trophy, color: AppTheme.primary, size: 24),
                  SizedBox(width: 12),
                  Text('Create Test Contest', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CONTEST TITLE', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'e.g. Rock Vocal Challenge',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    const Text('SUBTITLE', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: subtitleCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'e.g. Battle of the best singers',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text('PRIZE', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: prizeCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'e.g. \$500 Cash prize',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text('CATEGORY', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          dropdownColor: const Color(0xFF1E1E1E),
                          value: selectedCat,
                          isExpanded: true,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          items: ['Music', 'Dance', 'Comedy', 'Art', 'Sports'].map((cat) {
                            return DropdownMenuItem<String>(
                              value: cat,
                              child: Text(cat),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => selectedCat = val);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    final subtitle = subtitleCtrl.text.trim();
                    final prize = prizeCtrl.text.trim();

                    if (title.isEmpty || subtitle.isEmpty || prize.isEmpty) return;

                    final imageMap = {
                      'Music': 'https://images.unsplash.com/photo-1516280440614-37939bbacd81',
                      'Dance': 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad',
                      'Comedy': 'https://images.unsplash.com/photo-1527224857830-43a7acc85260',
                      'Art': 'https://images.unsplash.com/photo-1465847899084-d164df4dedc6',
                      'Sports': 'https://images.unsplash.com/photo-1508098682722-e99c43a406b2',
                    };

                    final img = imageMap[selectedCat] ?? imageMap['Music']!;
                    final contestId = 'c_custom_${DateTime.now().millisecondsSinceEpoch}';

                    await FirebaseFirestore.instance.collection('contests').doc(contestId).set({
                      'title': title,
                      'subtitle': subtitle,
                      'description': 'A custom user-created contest arena. Show your best performance to win!',
                      'rules': 'Submit a post within the scope rules. Highest votes in the last 10s wins.',
                      'prize': prize,
                      'schedule': 'Starts now, live updates.',
                      'image': img,
                      'category': selectedCat,
                      'type': 'Public',
                      'participantCount': 0,
                      'totalVotes': 0,
                      'rating': 5.0,
                      'reviewCount': 0,
                      'totalStars': 0,
                      'endsIn': '24 Hours',
                    });

                    if (dialogCtx.mounted) {
                      Navigator.pop(dialogCtx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Custom contest successfully created! 🏆'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
                      );
                    }
                  },
                  child: const Text('Create', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09090B),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'MY PROFILE',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: Consumer<RankingEngine>(
        builder: (context, engine, child) {
          final user = engine.currentUserProfile;
          if (user == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          }

          if (_loadedForUid != user.uid) {
            _loadedForUid = user.uid;
            _nameController.text = user.displayName;
            _zipController.text = user.zip;
            _cityController.text = user.city;
            _stateController.text = user.state;
          }

          final isPremium = user.subscriptionLevel == 'premium';

          // Web-specific layout with max width constraint
          final content = SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: kIsWeb ? 1200 : double.infinity,
              ),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. ELEGANT PROFILE HEADER CARD
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      // Avatar with colorful active indicator & glowing ring
                      GestureDetector(
                        onTap: () async {
                          final picker = ImagePicker();
                          final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
                          if (picked != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Uploading profile photo...'), behavior: SnackBarBehavior.floating),
                            );
                            await engine.uploadMyProfilePhoto(File(picked.path));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Profile photo updated successfully!'), behavior: SnackBarBehavior.floating, backgroundColor: Colors.green),
                              );
                            }
                          }
                        },
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: isPremium 
                                    ? const LinearGradient(colors: [Colors.amber, Colors.purpleAccent]) 
                                    : LinearGradient(colors: [AppTheme.primary, Colors.blueAccent.shade400]),
                              ),
                              child: CircleAvatar(
                                radius: 46,
                                backgroundImage: user.photoURL.isNotEmpty ? AvatarHelper.getSafeAvatarProvider(user.photoURL) : null,
                                backgroundColor: Colors.grey.shade900,
                                child: user.photoURL.isEmpty 
                                    ? const Icon(LucideIcons.user, size: 40, color: Colors.white60) 
                                    : null,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: AppTheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(LucideIcons.camera, size: 14, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${user.displayName} ${user.countryFlag}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.mapPin, color: Colors.white38, size: 13),
                          const SizedBox(width: 4),
                          Text(
                            '${user.city}, ${user.country} (${user.zip})',
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: isPremium
                              ? Colors.amber.withOpacity(0.12)
                              : AppTheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: isPremium 
                                ? Colors.amber.withOpacity(0.3) 
                                : AppTheme.primary.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          user.role.toUpperCase(),
                          style: TextStyle(
                            color: isPremium ? Colors.amber : AppTheme.primary,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 2. PREMIUM MEMBERSHIP BANNER CARD
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: isPremium
                        ? LinearGradient(
                            colors: [
                              const Color(0xFFD4AF37).withOpacity(0.15),
                              Colors.purple.withOpacity(0.12),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : LinearGradient(
                            colors: [
                              const Color(0xFF1E1E22),
                              const Color(0xFF141416),
                            ],
                          ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isPremium
                          ? const Color(0xFFD4AF37).withOpacity(0.35)
                          : Colors.white.withOpacity(0.08),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isPremium 
                              ? const Color(0xFFD4AF37).withOpacity(0.2) 
                              : Colors.white.withOpacity(0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPremium ? LucideIcons.crown : LucideIcons.unlock,
                          color: isPremium ? const Color(0xFFD4AF37) : Colors.white54,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isPremium ? 'PREMIUM MEMBER 👑' : 'FREE PLAN ACTIVE',
                              style: TextStyle(
                                color: isPremium ? const Color(0xFFD4AF37) : Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isPremium
                                  ? 'Unlimited Global Scope active!'
                                  : 'Visibility scope locked at local zip & country.',
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        activeColor: const Color(0xFFD4AF37),
                        value: isPremium,
                        onChanged: (val) async {
                          final newLevel = val ? 'premium' : 'free';
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(user.uid)
                              .update({'subscriptionLevel': newLevel});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Membership upgraded to [${newLevel.toUpperCase()}]!'),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: val ? Colors.purple : Colors.grey.shade900,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 3. PROFILE SETTINGS UNIFIED CARD
                const Text(
                  'ACCOUNT DETAILS',
                  style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Display Name Input
                      const Text(
                        'DISPLAY NAME',
                        style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Your Display Name',
                                hintStyle: const TextStyle(color: Colors.white24),
                                filled: true,
                                fillColor: const Color(0xFF1C1C1E),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            onPressed: () async {
                              final name = _nameController.text.trim();
                              if (name.isEmpty) return;
                              await engine.updateMyDisplayName(name);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Display name updated successfully!'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                            child: const Text('Save', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Location Scope Details
                      const Text(
                        'LOCATION LIMITS (ZIP / CITY / STATE)',
                        style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _zipController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Zip Code',
                                hintStyle: const TextStyle(color: Colors.white24),
                                filled: true,
                                fillColor: const Color(0xFF1C1C1E),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 4,
                            child: TextField(
                              controller: _cityController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'City',
                                hintStyle: const TextStyle(color: Colors.white24),
                                filled: true,
                                fillColor: const Color(0xFF1C1C1E),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 4,
                            child: TextField(
                              controller: _stateController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'State',
                                hintStyle: const TextStyle(color: Colors.white24),
                                filled: true,
                                fillColor: const Color(0xFF1C1C1E),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1C1C1E),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.white.withOpacity(0.08)),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () async {
                            await engine.updateMyLocation(
                              zip: _zipController.text.trim(),
                              city: _cityController.text.trim(),
                              state: _stateController.text.trim(),
                              country: user.country,
                              countryFlag: user.countryFlag,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Location details saved successfully! Scope locked.'), behavior: SnackBarBehavior.floating),
                              );
                            }
                          },
                          child: const Text('Update Location Scope', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Country Picker section
                      const Text(
                        'MY AUDIENCE COUNTRY',
                        style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Updates your physical country limits (critical for two-phone testing).',
                        style: TextStyle(color: Colors.white24, fontSize: 10),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: LocaleCountry.pickableCountries.map((c) {
                          final selected = user.country == c.name;
                          return FilterChip(
                            label: Text('${c.flag} ${c.name}'),
                            selected: selected,
                            onSelected: (_) => engine.updateMyCountry(c.name, c.flag),
                            backgroundColor: const Color(0xFF1C1C1E),
                            selectedColor: AppTheme.primary.withOpacity(0.25),
                            checkmarkColor: Colors.white,
                            side: BorderSide(
                              color: selected ? AppTheme.primary : Colors.white.withOpacity(0.08),
                              width: 1,
                            ),
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : Colors.white70,
                              fontSize: 11,
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 4. SUBSCRIPTION CARD
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'SUBSCRIPTION',
                            style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: user.subscriptionLevel == 'premium' 
                                  ? AppTheme.primary.withOpacity(0.2)
                                  : Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  user.subscriptionLevel == 'premium' ? LucideIcons.crown : LucideIcons.user,
                                  size: 12,
                                  color: user.subscriptionLevel == 'premium' ? AppTheme.primary : Colors.white54,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  user.subscriptionLevel.toUpperCase(),
                                  style: TextStyle(
                                    color: user.subscriptionLevel == 'premium' ? AppTheme.primary : Colors.white54,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        user.subscriptionLevel == 'premium'
                            ? 'Unlimited voting, global contests, ad-free experience'
                            : 'Limited voting, local contests, basic features',
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      if (user.subscriptionLevel != 'premium')
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SubscriptionUpgradeScreen(),
                                ),
                              );
                            },
                            icon: const Icon(LucideIcons.crown, size: 16),
                            label: const Text('Upgrade to Premium', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white54,
                              side: BorderSide(color: Colors.white.withOpacity(0.2)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SubscriptionUpgradeScreen(),
                                ),
                              );
                            },
                            icon: const Icon(LucideIcons.settings, size: 16),
                            label: const Text('Manage Subscription', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 5. STATS SUMMARY CARD
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.checkSquare, size: 24, color: Colors.greenAccent),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'LIFETIME VOTES CAST',
                              style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${user.totalVotesCast}',
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 5. TEST CONTROLLER ACTIONS
                const Text(
                  'DEVELOPER TOOLS',
                  style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.primary.withOpacity(0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(LucideIcons.plusCircle, size: 16, color: AppTheme.primary),
                    label: const Text(
                      'CREATE CONTEST 🏆',
                      style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CreateContestScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                // 6. UPLOADED POSTS FEED
                const Text(
                  'MY POSTS',
                  style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<PostModel>>(
                  stream: engine.getMyPosts(),
                  builder: (context, snapshot) {
                    final myPosts = snapshot.data ?? [];
                    if (myPosts.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141416),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: const Column(
                          children: [
                            Icon(LucideIcons.image, color: Colors.white24, size: 36),
                            SizedBox(height: 10),
                            Text('You haven\'t posted anything yet.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                          ],
                        ),
                      );
                    }

                    // Web: Show all posts with pagination, Mobile: Show all
                    final postsToShow = kIsWeb ? myPosts : myPosts;
                    final pageSize = kIsWeb ? 5 : myPosts.length;
                    final currentPage = 0; // Can be made stateful for full pagination

                    return Column(
                      children: [
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: postsToShow.length,
                          itemBuilder: (context, index) {
                            final post = postsToShow[index];
                            return _buildPostCard(context, post, engine);
                          },
                        ),
                        // Web pagination indicator
                        if (kIsWeb && myPosts.length > pageSize) ...[
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Showing ${myPosts.length} posts',
                                style: const TextStyle(color: Colors.white38, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),

                // 7. LOG OUT BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.redAccent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Colors.redAccent, width: 1.2),
                      ),
                    ),
                    icon: const Icon(LucideIcons.logOut, size: 16),
                    label: const Text(
                      'LOG OUT ACCOUNT',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    onPressed: () async {
                      await AuthService.instance.signOut();
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
            ),
          );

          // Center content on web
          if (kIsWeb) {
            return Center(child: content);
          }
          return content;
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// MAP TAB — Simulated Interactive Location Map
// ---------------------------------------------------------------------------
class _MapTab extends StatefulWidget {
  const _MapTab();

  @override
  State<_MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<_MapTab> {
  ContestModel? _selectedContest;
  final MapController _mapController = MapController();

  // Helper method to check if contest is visible to user based on subscription and location
  bool _isContestVisible(ContestModel contest, UserModel? user) {
    if (user == null) return true; // Show all if no user (for testing)
    
    // Premium users can see all contests
    if (user.subscriptionLevel == 'premium') return true;
    
    // Free users: check visibility scope
    switch (contest.visibilityScope) {
      case 'global':
        return true;
      case 'country':
        return contest.country.isEmpty || contest.country.toLowerCase() == user.country.toLowerCase();
      case 'state':
        // For simplicity, check country if state data not available
        return contest.country.isEmpty || contest.country.toLowerCase() == user.country.toLowerCase();
      case 'city':
        return contest.city.isEmpty || contest.city.toLowerCase() == user.city.toLowerCase();
      case 'zip':
        // For simplicity, check city if zip data not available
        return contest.city.isEmpty || contest.city.toLowerCase() == user.city.toLowerCase();
      default:
        return true;
    }
  }

  // Get LatLng for contest, with fallback to default coordinates
  LatLng _getContestLatLng(ContestModel contest) {
    if (contest.latitude != null && contest.longitude != null) {
      return LatLng(contest.latitude!, contest.longitude!);
    }
    
    // Fallback coordinates based on city with slight offset to prevent overlap
    final cityCoordinates = {
      'London': LatLng(51.5074, -0.1278),
      'Tokyo': LatLng(35.6762, 139.6503),
      'Tunis': LatLng(36.8065, 10.1815),
      'Paris': LatLng(48.8566, 2.3522),
      'New York': LatLng(40.7128, -74.0060),
    };
    
    // Add small random offset based on contest ID hash to prevent overlapping markers
    final baseCoords = cityCoordinates[contest.city] ?? LatLng(34.0522, -118.2437);
    final offset = contest.id.hashCode % 1000 / 10000; // Small offset between 0 and 0.1
    return LatLng(baseCoords.latitude + offset, baseCoords.longitude + offset);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RankingEngine>(
      builder: (context, engine, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0A0A0A),
            elevation: 0,
            title: const Text('CONTEST LOCATION MAP', 
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1)),
          ),
          body: Stack(
            children: [
              // 1. Real Interactive Map
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LatLng(34.0522, -118.2437), // Default center
                  initialZoom: 2.0,
                  minZoom: 1.0,
                  maxZoom: 18.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.contest_live',
                  ),
                  // 2. Contest Markers
                  MarkerLayer(
                    markers: engine.contests.map((contest) {
                      final latLng = _getContestLatLng(contest);
                      final isSelected = _selectedContest?.id == contest.id;
                      return Marker(
                        point: latLng,
                        width: 60,
                        height: 60,
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _selectedContest = contest);
                            _mapController.move(latLng, 10.0);
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppTheme.primary : const Color(0xFF151515),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: isSelected ? Colors.white : AppTheme.primary, width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primary.withValues(alpha: isSelected ? 0.6 : 0.2),
                                      blurRadius: isSelected ? 12 : 6,
                                    )
                                  ],
                                ),
                                child: Icon(
                                  LucideIcons.mapPin,
                                  color: isSelected ? Colors.white : AppTheme.primary,
                                  size: isSelected ? 22 : 16,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  contest.city.isNotEmpty ? contest.city : contest.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),

              // 3. Floating Overlay Instructions
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.info, color: AppTheme.primary, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Contests by location. ${engine.currentUserProfile?.subscriptionLevel == 'premium' ? 'Premium: Global view' : 'Free: Local view'}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 4. Contest Detail Bottom Card
              if (_selectedContest != null)
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121212),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4), width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 20,
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _selectedContest!.category.toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(LucideIcons.x, color: Colors.white54, size: 18),
                              onPressed: () => setState(() => _selectedContest = null),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedContest!.title,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedContest!.subtitle,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(LucideIcons.gift, color: Colors.amber, size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('Prize: ${_selectedContest!.prize}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 8),
                            const Icon(LucideIcons.users, color: Colors.white54, size: 14),
                            const SizedBox(width: 6),
                            Text('${_selectedContest!.participantCount} Joined',
                                style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              final contest = _selectedContest!;
                              setState(() => _selectedContest = null);
                              engine.loadContestEntries(contest.id);
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => ContestDetailScreen(contest: contest)),
                              );
                            },
                            child: const Text(
                              'OPEN CONTEST ARENA',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MapCanvasPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw grid matrix
    const int lines = 12;
    for (int i = 0; i <= lines; i++) {
      final double x = (size.width / lines) * i;
      final double y = (size.height / lines) * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Draw dynamic concentric target circular waves
    final paintWave = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.08)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    
    canvas.drawCircle(Offset(size.width * 0.45, size.height * 0.45), size.width * 0.2, paintWave);
    canvas.drawCircle(Offset(size.width * 0.45, size.height * 0.45), size.width * 0.4, paintWave);
    canvas.drawCircle(Offset(size.width * 0.45, size.height * 0.45), size.width * 0.6, paintWave);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Removed _MapCanvasPainter as we now use flutter_map

// ---------------------------------------------------------------------------
// EXPLORE TAB — Live Sliding Feed Sorted by 10-Second Ranking Engine
// ---------------------------------------------------------------------------
class _ExploreTab extends StatefulWidget {
  const _ExploreTab();

  @override
  State<_ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<_ExploreTab> {
  String _selectedTypeFilter = 'All'; // 'All', 'image', 'video', 'text'
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      Provider.of<RankingEngine>(context, listen: false).fetchNextFeedPage();
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inDays >= 7) {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } else if (difference.inDays >= 1) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RankingEngine>(
      builder: (context, engine, _) {
        final viewer = engine.currentUserProfile;
        if (viewer == null) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }

        final posts = engine.feedPosts;

        // Filter by type if selected
        final filtered = posts.where((post) {
          if (_selectedTypeFilter == 'All') return true;
          return post.type == _selectedTypeFilter;
        }).toList();

        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0A0A0A),
            elevation: 0,
            title: const Text(
              'GLOBAL FEED',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 1.5,
              ),
            ),
          ),
          body: Column(
            children: [
              _buildTypeFilters(),
              Expanded(
                child: filtered.isEmpty && engine.isLoadingFeed
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : RefreshIndicator(
                        onRefresh: () => engine.refreshFeed(),
                        color: AppTheme.primary,
                        backgroundColor: const Color(0xFF141416),
                        child: filtered.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                                  const Center(
                                    child: Text(
                                      'No posts found.',
                                      style: TextStyle(color: Colors.white38, fontSize: 13),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                itemCount: filtered.length + (engine.hasMoreFeed ? 1 : 0),
                                itemBuilder: (ctx, i) {
                                  if (i == filtered.length) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 16),
                                      child: Center(
                                        child: CircularProgressIndicator(color: AppTheme.primary),
                                      ),
                                    );
                                  }
                                  final post = filtered[i];
                                  return _buildPostCard(ctx, post, engine);
                                },
                              ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTypeFilters() {
    final filters = [
      {'value': 'All', 'label': 'All Feed'},
      {'value': 'image', 'label': 'Photos'},
      {'value': 'video', 'label': 'Videos'},
      {'value': 'text', 'label': 'Text'},
    ];
    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        itemBuilder: (_, i) {
          final filter = filters[i];
          final val = filter['value']!;
          final label = filter['label']!;
          final selected = _selectedTypeFilter == val;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) => setState(() => _selectedTypeFilter = val),
              selectedColor: AppTheme.primary.withOpacity(0.25),
              checkmarkColor: Colors.white,
              backgroundColor: const Color(0xFF1C1C1E),
              labelStyle: TextStyle(
                color: selected ? Colors.white : Colors.white60,
                fontSize: 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
              side: BorderSide(
                color: selected ? AppTheme.primary : Colors.white.withOpacity(0.08),
                width: 1,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPostCard(BuildContext context, PostModel post, RankingEngine engine) {
    final viewer = engine.currentUserProfile;
    final isLiked = viewer != null && post.likes.contains(viewer.uid);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PublicProfileScreen(userId: post.userId),
                      ),
                    );
                  },
                  child: CircleAvatar(
                    radius: 20,
                    backgroundImage: post.userAvatar.isNotEmpty
                        ? AvatarHelper.getSafeAvatarProvider(post.userAvatar)
                        : null,
                    backgroundColor: Colors.grey.shade900,
                    child: post.userAvatar.isEmpty
                        ? const Icon(LucideIcons.user, size: 20, color: Colors.white60)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PublicProfileScreen(userId: post.userId),
                            ),
                          );
                        },
                        child: Text(
                          post.userName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            _formatTimeAgo(post.createdAt),
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                          ),
                          const SizedBox(width: 6),
                          const Icon(LucideIcons.dot, color: Colors.white38, size: 10),
                          const SizedBox(width: 4),
                          Icon(
                            post.visibilityScope == 'global' ? LucideIcons.globe : LucideIcons.mapPin,
                            size: 10,
                            color: Colors.white38,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            post.visibilityScope.toUpperCase(),
                            style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (post.contestId != null && post.contestId!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.primary.withOpacity(0.25)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.trophy, color: AppTheme.primary, size: 10),
                        SizedBox(width: 4),
                        Text(
                          'ARENA',
                          style: TextStyle(color: AppTheme.primary, fontSize: 8, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (post.caption.isNotEmpty && post.type != 'text')
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 14, bottom: 10),
              child: Text(
                post.caption,
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
            ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PostDetailScreen(postId: post.id),
                ),
              );
            },
            child: post.type == 'text'
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [const Color(0xFF1E1E22), const Color(0xFF121214)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      post.contentUrl,
                      style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : post.type == 'image'
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 16 / 10,
                          child: AvatarHelper.getSafePostImage(
                            post.contentUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                    : Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(12),
                          image: post.contentUrl.isNotEmpty && !post.contentUrl.startsWith('/data/user/')
                              ? DecorationImage(
                                  image: AvatarHelper.getSafeAvatarProvider(post.contentUrl),
                                  fit: BoxFit.cover,
                                  colorFilter: ColorFilter.mode(
                                    Colors.black.withOpacity(0.4),
                                    BlendMode.darken,
                                  ),
                                )
                              : null,
                        ),
                        child: const Center(
                          child: CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.black54,
                            child: Icon(LucideIcons.play, color: Colors.white, size: 24),
                          ),
                        ),
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => engine.toggleLikePost(post.id),
                  child: Row(
                    children: [
                      Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? AppTheme.primary : Colors.white60,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${post.likes.length}',
                        style: TextStyle(
                          color: isLiked ? Colors.white : Colors.white60,
                          fontWeight: isLiked ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PostDetailScreen(postId: post.id),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      const Icon(LucideIcons.messageSquare, color: Colors.white60, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        '${post.commentsCount}',
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ACTIVITY TAB — Real-Time Event Log Notifications
// ---------------------------------------------------------------------------
class _ActivityTab extends StatelessWidget {
  const _ActivityTab();

  Color _getColorForType(String type) {
    switch (type) {
      case 'vote':
        return AppTheme.primary;
      case 'join':
        return Colors.green;
      case 'live':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RankingEngine>(
      builder: (context, engine, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0A0A0A),
            elevation: 0,
            title: const Text('REAL-TIME ACTIVITY LOG', 
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1)),
          ),
          body: StreamBuilder<List<NotificationModel>>(
            stream: engine.watchNotifications(),
            builder: (context, snapshot) {
              final notifications = snapshot.data ?? [];
              if (notifications.isEmpty) {
                return const Center(
                  child: Text('No real-time logs reported.', style: TextStyle(color: Colors.white38)),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: notifications.length,
                itemBuilder: (ctx, i) {
                  final notif = notifications[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121212),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundImage: AvatarHelper.getSafeAvatarProvider(notif.senderAvatar),
                          radius: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    notif.title.toUpperCase(),
                                    style: TextStyle(
                                      color: _getColorForType(notif.type),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const Spacer(),
                                  const Icon(LucideIcons.activity, color: Colors.white24, size: 10),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                notif.message,
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
