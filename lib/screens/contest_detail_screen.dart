import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../engine/ranking_engine.dart';
import '../models/entry.dart';
import '../screens/entry_post_screen.dart';
import '../screens/live_stream_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/cohost_invite_banner.dart';

class ContestDetailScreen extends StatefulWidget {
  final ContestModel contest;

  const ContestDetailScreen({super.key, required this.contest});

  @override
  State<ContestDetailScreen> createState() => _ContestDetailScreenState();
}

class _ContestDetailScreenState extends State<ContestDetailScreen>
    with SingleTickerProviderStateMixin {
  bool _hasJoined = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<RankingEngine>(context, listen: false)
          .loadContestEntries(widget.contest.id);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildAppBar(context),
          _buildTabBar(),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildRankingsTab(),
            _buildDetailsTab(),
            _buildPrizeTab(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomAction(),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      backgroundColor: const Color(0xFF0A0A0A),
      leading: IconButton(
        icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.share2, color: Colors.white),
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Link copied!')),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LiveStreamScreen(isHost: false, contest: widget.contest),
              ),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(widget.contest.image, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade900)),
              Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.4), const Color(0xFF0A0A0A)],
                ),
              ),
            ),
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                        child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      const Icon(LucideIcons.users, color: Colors.white70, size: 13),
                      const SizedBox(width: 4),
                      Text('${widget.contest.participantCount} Participants', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(widget.contest.title,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, height: 1.3)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ...List.generate(5, (i) => Icon(
                        LucideIcons.star,
                        color: i < widget.contest.rating.floor() ? Colors.amber : Colors.white38,
                        size: 14,
                      )),
                      const SizedBox(width: 6),
                      Text('${widget.contest.rating.toStringAsFixed(1)} (${widget.contest.reviewCount} reviews)',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ), // Close GestureDetector
      ), // Close FlexibleSpaceBar
    ); // Close SliverAppBar
  }

  Widget _buildTabBar() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _SliverTabBarDelegate(
        TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 3,
          dividerColor: Colors.white12,
          tabs: const [
            Tab(text: 'RANKINGS'),
            Tab(text: 'DETAILS'),
            Tab(text: 'PRIZE'),
          ],
        ),
      ),
    );
  }

  Widget _buildRankingsTab() {
    return Consumer<RankingEngine>(
      builder: (context, engine, _) {
        final liveContest = engine.contests.firstWhere(
          (c) => c.id == widget.contest.id,
          orElse: () => widget.contest,
        );
        
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            CoHostInviteBanner(contest: widget.contest),
            _buildTimerAndFollow(engine),
            _buildStatsRow(liveContest),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('LIVE RANKINGS',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5)),
            ),
            const SizedBox(height: 8),
            ...List.generate(engine.entries.length, (index) {
              final entry = engine.entries[index];
              return _buildEntryRow(context, entry, index + 1, engine);
            }),
            const SizedBox(height: 100),
          ],
        );
      },
    );
  }

  Widget _buildTimerAndFollow(RankingEngine engine) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ENDS IN', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
              Text(widget.contest.endsIn,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ],
          ),
          const Spacer(),
          StreamBuilder<bool>(
            stream: Provider.of<RankingEngine>(context, listen: false).isFollowingContest(),
            builder: (context, snapshot) {
              final isFollowing = snapshot.data ?? false;
              return GestureDetector(
                onTap: () async {
                  await Provider.of<RankingEngine>(context, listen: false).toggleFollowContest();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: isFollowing ? AppTheme.primary : Colors.transparent,
                    border: Border.all(color: AppTheme.primary),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isFollowing ? 'FOLLOWING' : 'FOLLOW',
                    style: TextStyle(
                        color: isFollowing ? Colors.white : AppTheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
              );
            }
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(ContestModel contest) {
    int totalVotes = contest.totalVotes;
    int participants = contest.participantCount;
    double avgRating = contest.rating;

    String votesStr = totalVotes >= 1000 
      ? '${(totalVotes / 1000).toStringAsFixed(1)}K'
      : totalVotes.toString();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(LucideIcons.barChart2, votesStr, 'Total Votes', AppTheme.primary),
          Container(width: 1, height: 36, color: Colors.white12),
          _buildStatItem(LucideIcons.star, avgRating.toStringAsFixed(1), 'Avg Rating', Colors.orange),
          Container(width: 1, height: 36, color: Colors.white12),
          _buildStatItem(LucideIcons.users, '$participants', 'Participants', Colors.blue),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
      ],
    );
  }

  Widget _buildEntryRow(BuildContext context, ContestEntry entry, int rank, RankingEngine engine) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EntryPostScreen(
            initialEntry: entry,
            initialRank: rank,
            onVote: () => engine.addVote(entry.id),
            contest: widget.contest,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: rank == 1 ? AppTheme.primary.withValues(alpha: 0.5) : Colors.white12),
        ),
        child: Column(
          children: [
            // Video Preview
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Stack(
                children: [
                  Image.network(
                    entry.contentUrl,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(height: 140, color: Colors.grey.shade900),
                  ),
                  Container(
                    height: 140,
                    color: Colors.black.withValues(alpha: 0.3),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.play, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(12)),
                      child: Text('RANK #$rank', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Text(entry.countryFlag, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(entry.caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${entry.totalVotes}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.accent)),
                      const Text('VOTES', style: TextStyle(fontSize: 9, letterSpacing: 1, color: Colors.white54)),
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

  Widget _buildDetailsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildDetailCard('📖 About this Contest', widget.contest.description),
        const SizedBox(height: 16),
        _buildDetailCard('📋 Rules', widget.contest.rules),
        const SizedBox(height: 16),
        _buildDetailCard('📅 Schedule', widget.contest.schedule),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildPrizeTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildDetailCard('🏆 Prizes', widget.contest.prize),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildDetailCard(String title, String content) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Text(content, style: const TextStyle(color: Colors.white70, height: 1.6, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildBottomAction() {
    final engine = Provider.of<RankingEngine>(context);
    final hasJoined = _hasJoined || engine.entries.any((e) => e.userId == engine.currentUserId);

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (hasJoined) return;
          showModalBottomSheet(
            context: context,
            backgroundColor: const Color(0xFF151515),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (sheetCtx) => Container(
              padding: const EdgeInsets.all(24),
              height: 260,
              child: Column(
                children: [
                  const Icon(LucideIcons.checkCircle, color: Colors.green, size: 48),
                  const SizedBox(height: 12),
                  const Text('Join & Start Voting!',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Your entry will go live and you can vote for others!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70)),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
                      onPressed: () {
                        setState(() => _hasJoined = true);
                        final engine = Provider.of<RankingEngine>(context, listen: false);
                        engine.addMockUserEntry();
                        Navigator.pop(sheetCtx);
                      },
                      child: const Text("Let's Go! 🔥", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            gradient: hasJoined ? null : AppTheme.pinkPurpleGradient,
            color: hasJoined ? Colors.white12 : null,
            borderRadius: BorderRadius.circular(27),
          ),
          child: Center(
            child: hasJoined 
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('You are participating! 🎤', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        ),
                        onPressed: () {
                          final engine = Provider.of<RankingEngine>(context, listen: false);
                          final myEntryIndex = engine.entries.indexWhere((e) => e.userId == engine.currentUserId);
                          if (myEntryIndex != -1) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LiveStreamScreen(
                                  isHost: true,
                                  contest: widget.contest,
                                  entryId: engine.entries[myEntryIndex].id,
                                ),
                              ),
                            );
                          }
                        },
                        child: const Text('GO LIVE'),
                      ),
                    ],
                  )
                : const Text(
                    'Join Live & Vote',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _SliverTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: const Color(0xFF0A0A0A), child: tabBar);
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) => false;
}
