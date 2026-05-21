import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../data/locale_country.dart';
import '../data/mock_data.dart';
import '../engine/ranking_engine.dart';
import '../models/entry.dart';
import '../theme/app_theme.dart';
import 'contest_detail_screen.dart';

// ---------------------------------------------------------------------------
// ROOT SHELL — holds the persistent BottomNavigationBar + nested Navigator
// ---------------------------------------------------------------------------
class ContestListScreen extends StatefulWidget {
  const ContestListScreen({super.key});

  @override
  State<ContestListScreen> createState() => _ContestListScreenState();
}

class _ContestListScreenState extends State<ContestListScreen> {
  int _bottomNavIndex = 0;
  final GlobalKey<NavigatorState> _homeNavKey = GlobalKey<NavigatorState>();

  late final List<GlobalKey<NavigatorState>> _navKeys = [
    _homeNavKey,
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

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
            _buildPlaceholder('Search', LucideIcons.search),
            _buildPlaceholder('Explore', LucideIcons.compass),
            _buildPlaceholder('Activity & Notifications', LucideIcons.bell),
            Navigator(
              key: _navKeys[4],
              onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const _UserProfileTab()),
            ),
          ],
        ),
        bottomNavigationBar: Theme(
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
              },
              items: const [
                BottomNavigationBarItem(icon: Icon(LucideIcons.home), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(LucideIcons.search), label: 'Search'),
                BottomNavigationBarItem(icon: Icon(LucideIcons.compass), label: 'Explore'),
                BottomNavigationBarItem(icon: Icon(LucideIcons.bell), label: 'Activity'),
                BottomNavigationBarItem(icon: Icon(LucideIcons.user), label: 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(String title, IconData icon) {
    return Navigator(
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0A0A0A),
            elevation: 0,
            title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 64, color: Colors.white12),
                const SizedBox(height: 16),
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                const Text('Coming soon in future milestones', style: TextStyle(color: Colors.white54)),
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
        
        return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundImage: const NetworkImage('https://i.pravatar.cc/150?u=99'),
            backgroundColor: Colors.grey.shade900,
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
                  const Text('FEASTVOTE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1)),
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
                  const SizedBox(height: 8),
                  Text(contest.subtitle,
                      style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(LucideIcons.clock, size: 14, color: Colors.white54),
                      const SizedBox(width: 6),
                      Text('Ends in ${contest.endsIn}',
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
  String? _loadedForUid;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: const Text('MY PROFILE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1)),
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
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundImage: NetworkImage(user.photoURL),
                        backgroundColor: Colors.white10,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${user.displayName} ${user.countryFlag}',
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.country,
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Device ID: ${engine.currentUserId}',
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          user.role.toUpperCase(),
                          style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'YOUR DISPLAY NAME (shown on live stream & invites)',
                  style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Enter your name',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF151515),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        final name = _nameController.text.trim();
                        if (name.isEmpty) return;
                        await engine.updateMyDisplayName(name);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Name saved — visible on live stream'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'YOUR COUNTRY (for live audience stats)',
                  style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Set a different country on each phone when testing with two devices.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
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
                      selectedColor: AppTheme.primary.withValues(alpha: 0.35),
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontSize: 11,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.checkSquare, size: 36, color: Colors.greenAccent),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('LIFETIME VOTES CAST', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(
                              '${user.totalVotesCast}',
                              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
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
        },
      ),
    );
  }
}
