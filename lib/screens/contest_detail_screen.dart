import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../engine/ranking_engine.dart';
import '../models/entry.dart';
import '../models/post.dart';
import '../data/live_session_service.dart';
import '../screens/entry_post_screen.dart';
import '../screens/create_post_screen.dart';
import '../screens/live_stream_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_helper.dart';
import '../widgets/media_content_preview.dart';

class ContestDetailScreen extends StatefulWidget {
  final ContestModel contest;

  const ContestDetailScreen({super.key, required this.contest});

  @override
  State<ContestDetailScreen> createState() => _ContestDetailScreenState();
}

class _ContestDetailScreenState extends State<ContestDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Debug logging
    debugPrint('ContestDetailScreen: Contest prizes: ${widget.contest.prizes}');
    debugPrint('ContestDetailScreen: Contest prize (legacy): ${widget.contest.prize}');
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final engine = Provider.of<RankingEngine>(context, listen: false);
      engine.setCurrentContest(widget.contest.id);
      engine.loadContestEntries(widget.contest.id);
    });
    
    // Start timer to update countdown every second
    _startTimer();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
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
    final engine = Provider.of<RankingEngine>(context, listen: false);
    final isCreator = widget.contest.creatorId == engine.currentUserId;
    final coverHeight = kIsWeb ? 338.0 : 260.0;

    return SliverAppBar(
      expandedHeight: coverHeight,
      pinned: true,
      backgroundColor: const Color(0xFF0A0A0A),
      leading: IconButton(
        icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        if (isCreator)
          IconButton(
            icon: const Icon(LucideIcons.barChart2, color: AppTheme.primary),
            tooltip: 'Live Standings',
            onPressed: () => _openLiveStandings(),
          ),
        if (isCreator)
          IconButton(
            icon: const Icon(LucideIcons.trash2, color: Colors.red),
            onPressed: () => _showDeleteContestDialog(),
          ),
        StreamBuilder<Map<String, dynamic>?>(
          stream: LiveSessionService().watchOrganizerLiveSession(widget.contest.id),
          builder: (context, snapshot) {
            final isOrganizerLive = snapshot.data != null && snapshot.data!['status'] == 'live';
            if (!isOrganizerLive || isCreator) return const SizedBox.shrink();
            
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.5),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LiveStreamScreen(
                          isHost: false,
                          contest: widget.contest,
                          entryId: null,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.radio, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            MediaContentPreview(
              type: contestCoverType(widget.contest),
              contentUrl: widget.contest.image,
              height: coverHeight,
              autoPlayVideo: true,
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
      ),
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

  Widget _buildWebEntryCard(BuildContext context, ContestEntry entry, int rank, RankingEngine engine) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image / video preview
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MediaContentPreview(
                    type: entry.type,
                    contentUrl: entry.contentUrl,
                    height: double.infinity,
                    fit: BoxFit.contain,
                    autoPlayVideo: false,
                    videoThumbnailMode: true,
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: rank == 1 ? AppTheme.primary : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: rank == 1 ? Colors.transparent : Colors.white12),
                      ),
                      child: Text(
                        'RANK #$rank',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: MediaTypeBadge(type: entry.type),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Details row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: entry.userAvatar.isNotEmpty
                    ? AvatarHelper.getSafeAvatarProvider(entry.userAvatar)
                    : null,
                backgroundColor: Colors.grey.shade900,
                child: entry.userAvatar.isEmpty
                    ? const Icon(LucideIcons.user, size: 16, color: Colors.white60)
                    : null,
              ),
              const SizedBox(width: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(entry.countryFlag, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entry.userName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.caption,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '${entry.totalVotes} Votes',
                          style: const TextStyle(
                            color: AppTheme.accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        // A quick vote action button
                        GestureDetector(
                          onTap: () {
                            engine.addVote(entry.id);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.thumbsUp, size: 10, color: AppTheme.primary),
                                SizedBox(width: 4),
                                Text('VOTE', style: TextStyle(color: AppTheme.primary, fontSize: 9, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
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
        
        if (kIsWeb) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildTimerAndFollow(engine),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 3,
                    child: _buildStatsRow(liveContest),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'LIVE RANKINGS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              if (engine.entries.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text('No entries yet', style: TextStyle(color: Colors.white38)),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = (constraints.maxWidth - (3 * 24)) / 4;
                    final cardHeight = (width * 9 / 16) + 125;
                    final ratio = width / cardHeight;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 24,
                        mainAxisSpacing: 16,
                        childAspectRatio: ratio,
                      ),
                      itemCount: engine.entries.length,
                      itemBuilder: (ctx, index) {
                        final entry = engine.entries[index];
                        return _buildWebEntryCard(ctx, entry, index + 1, engine);
                      },
                    );
                  },
                ),
              const SizedBox(height: 100),
            ],
          );
        }
        
        return ListView(
          padding: EdgeInsets.zero,
          children: [
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
      margin: kIsWeb ? EdgeInsets.zero : const EdgeInsets.all(16),
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
              Text(widget.contest.calculatedEndsIn,
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
      margin: kIsWeb ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16),
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
                  MediaContentPreview(
                    type: entry.type,
                    contentUrl: entry.contentUrl,
                    height: 160,
                    fit: BoxFit.contain,
                    autoPlayVideo: false,
                    videoThumbnailMode: true,
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
                  Positioned(
                    bottom: 8,
                    left: 10,
                    child: MediaTypeBadge(type: entry.type),
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
    return Consumer<RankingEngine>(
      builder: (context, engine, _) {
        final liveContest = engine.contests.firstWhere(
          (c) => c.id == widget.contest.id,
          orElse: () => widget.contest,
        );
        
        debugPrint('_buildPrizeTab: liveContest prizes: ${liveContest.prizes}');
        
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (liveContest.prizes.isEmpty)
              _buildDetailCard('🏆 Prizes', liveContest.prize)
            else
              ...liveContest.prizes.asMap().entries.map((entry) {
                final prize = entry.value;
                final rank = prize['rank'] as int? ?? entry.key + 1;
                final amount = prize['amount'] as String? ?? '';
                final type = prize['type'] as String? ?? '';
                final description = prize['description'] as String? ?? '';
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _getPrizeColor(type),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '#$rank',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              amount,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            const SizedBox(height: 100),
          ],
        );
      },
    );
  }

  Color _getPrizeColor(String type) {
    switch (type.toLowerCase()) {
      case 'gold':
        return Colors.amber;
      case 'silver':
        return Colors.grey;
      case 'bronze':
        return const Color(0xFFCD7F32);
      default:
        return AppTheme.primary;
    }
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

  void _showJoinOptions(BuildContext context, RankingEngine engine) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      backgroundColor: const Color(0xFF151515),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        final screenWidth = MediaQuery.of(sheetCtx).size.width;
        final sheetHeight = MediaQuery.of(sheetCtx).size.height * 0.82;
        final cardWidth = (screenWidth * 0.82).clamp(280.0, 360.0);

        return SizedBox(
          height: sheetHeight,
          child: StreamBuilder<List<PostModel>>(
            stream: engine.getMyPosts(),
            builder: (context, snapshot) {
              final posts = (snapshot.data ?? [])
                  .where((p) => p.type == 'image' || p.type == 'video')
                  .toList();
              final isLoading = snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'JOIN CONTEST ARENA',
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                posts.isEmpty
                                    ? 'Create a photo or video post first, then pick it to join.'
                                    : 'Swipe left or right to browse your posts.',
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetCtx),
                          icon: const Icon(LucideIcons.x, color: Colors.white54, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (isLoading)
                    const Expanded(
                      child: Center(
                        child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
                      ),
                    )
                  else if (posts.isEmpty)
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(LucideIcons.imagePlus, color: Colors.white24, size: 36),
                              ),
                              const SizedBox(height: 12),
                                  const Text(
                                    'No photo or video posts yet',
                                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Text posts cannot be used to join a contest.\nCreate a photo or video post first.',
                                style: TextStyle(color: Colors.white54, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(LucideIcons.plus, size: 16, color: Colors.white),
                                label: const Text('Create New Post', style: TextStyle(color: Colors.white)),
                                onPressed: () {
                                  Navigator.pop(sheetCtx);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const CreatePostScreen()),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final previewHeight = (constraints.maxHeight - 132).clamp(240.0, 340.0);

                          return ScrollConfiguration(
                            behavior: ScrollConfiguration.of(sheetCtx).copyWith(
                              dragDevices: {
                                PointerDeviceKind.touch,
                                PointerDeviceKind.mouse,
                                PointerDeviceKind.trackpad,
                                PointerDeviceKind.stylus,
                              },
                            ),
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                              clipBehavior: Clip.none,
                              itemCount: posts.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 16),
                              itemBuilder: (ctx, idx) => _buildJoinPostCard(
                                sheetCtx: sheetCtx,
                                context: context,
                                engine: engine,
                                post: posts[idx],
                                cardWidth: cardWidth,
                                previewHeight: previewHeight,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (posts.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.moveHorizontal, color: Colors.white38, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            '${posts.length} post${posts.length == 1 ? '' : 's'} — swipe to browse',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(LucideIcons.plus, size: 16, color: AppTheme.primary),
                          label: const Text('Create New Post Instead', style: TextStyle(color: AppTheme.primary)),
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const CreatePostScreen()),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildJoinPostCard({
    required BuildContext sheetCtx,
    required BuildContext context,
    required RankingEngine engine,
    required PostModel post,
    required double cardWidth,
    required double previewHeight,
  }) {
    final isAssigned = post.contestId != null && post.contestId!.isNotEmpty;

    return SizedBox(
      width: cardWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isAssigned ? Colors.white24 : AppTheme.primary.withValues(alpha: 0.5),
            width: isAssigned ? 1 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
              child: SizedBox(
                height: previewHeight,
                width: cardWidth,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MediaContentPreview(
                      type: post.type,
                      contentUrl: post.contentUrl,
                      height: previewHeight,
                      width: cardWidth,
                      videoThumbnailMode: false,
                      autoPlayVideo: true,
                      forceAutoPlay: true,
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: MediaTypeBadge(type: post.type),
                    ),
                    if (isAssigned)
                      Container(
                        color: Colors.black.withValues(alpha: 0.65),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.lock, color: Colors.white54, size: 28),
                            const SizedBox(height: 8),
                            const Text(
                              'ALREADY IN A CONTEST',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Text(
                post.caption.isNotEmpty ? post.caption : 'Untitled post',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, height: 1.3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              child: Text(
                post.userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                height: 44,
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAssigned ? Colors.white12 : AppTheme.primary,
                    disabledBackgroundColor: Colors.white12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: isAssigned
                      ? null
                      : () async {
                          Navigator.pop(sheetCtx);
                          final ok = await engine.assignPostToContest(post.id, widget.contest.id);
                          if (!context.mounted) return;
                          if (ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Successfully joined the contest! 🔥'),
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to join. Remember: 1 post = 1 contest only!'),
                                backgroundColor: Colors.redAccent,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                  child: Text(
                    isAssigned ? 'Already assigned' : 'Select this post',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isAssigned ? Colors.white38 : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomAction() {
    final engine = Provider.of<RankingEngine>(context);
    final isOrganizer = widget.contest.creatorId == engine.currentUserId;
    final hasJoined = engine.entries.any((e) => e.userId == engine.currentUserId);
    final myEntry = hasJoined
        ? engine.entries.firstWhere((e) => e.userId == engine.currentUserId)
        : null;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: isOrganizer
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(LucideIcons.crown, color: Colors.amber, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'You are the organizer!',
                              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              'Go live to host this contest',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(LucideIcons.radio, size: 16),
                    label: const Text('GO LIVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LiveStreamScreen(
                            isHost: true,
                            contest: widget.contest,
                            entryId: null, // Organizer goes live without an entry
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            )
          : hasJoined
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (myEntry != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151515),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(LucideIcons.mic, color: AppTheme.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'You are participating!',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                myEntry.caption.isNotEmpty ? myEntry.caption : 'Your contest entry',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white54, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(LucideIcons.radio, size: 16),
                    label: const Text('GO LIVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () {
                      if (myEntry == null) {
                        debugPrint('[ContestDetail] No entry found for contestant');
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LiveStreamScreen(
                            isHost: true,
                            contest: widget.contest,
                            entryId: myEntry.id,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            )
          : GestureDetector(
              onTap: () => _showJoinOptions(context, engine),
              child: Container(
                height: 52,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: AppTheme.pinkPurpleGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text(
                    'Join Contest',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  void _openLiveStandings() {
    // Construct full URL based on platform
    String fullUrl;
    
    if (kIsWeb) {
      // On web, use current origin + relative path
      fullUrl = '${Uri.base}/standings.html?contestId=${widget.contest.id}';
      launchUrl(Uri.parse(fullUrl), mode: LaunchMode.externalApplication);
    } else {
      // On mobile, use your production URL (replace with your actual domain)
      // For now, construct a full URL that would work in production
      fullUrl = 'https://contest-app-94050.firebaseapp.com/standings.html?contestId=${widget.contest.id}';
      
      // Try to open directly on mobile
      launchUrl(Uri.parse(fullUrl), mode: LaunchMode.externalApplication).then((success) {
        if (!success) {
          // If opening fails, copy to clipboard
          Clipboard.setData(ClipboardData(text: fullUrl)).then((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('URL copied to clipboard'),
                duration: const Duration(seconds: 3),
                action: SnackBarAction(
                  label: 'Open',
                  textColor: Colors.white,
                  onPressed: () {
                    launchUrl(Uri.parse(fullUrl), mode: LaunchMode.externalApplication);
                  },
                ),
              ),
            );
          });
        }
      });
    }
  }

  void _showDeleteContestDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: Colors.red),
            SizedBox(width: 12),
            Text(
              'Delete Contest',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "${widget.contest.title}"?',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: const Text(
                '⚠️ This will delete all entries and votes associated with this contest. This action cannot be undone.',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                // Delete all entries
                final entriesSnapshot = await FirebaseFirestore.instance
                    .collection('contests')
                    .doc(widget.contest.id)
                    .collection('entries')
                    .get();
                
                for (final doc in entriesSnapshot.docs) {
                  await doc.reference.delete();
                }
                
                // Delete contest
                await FirebaseFirestore.instance
                    .collection('contests')
                    .doc(widget.contest.id)
                    .delete();
                
                if (mounted) {
                  Navigator.pop(context); // Close dialog
                  // Show snackbar before navigation
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Contest deleted successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  // Navigate to home after a short delay
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted) {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  });
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete contest: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete Contest'),
          ),
        ],
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
