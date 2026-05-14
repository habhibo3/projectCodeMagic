import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../engine/ranking_engine.dart';
import '../widgets/entry_tile.dart';
import '../theme/app_theme.dart';

class ContestDetailScreen extends StatefulWidget {
  const ContestDetailScreen({super.key});

  @override
  State<ContestDetailScreen> createState() => _ContestDetailScreenState();
}

class _ContestDetailScreenState extends State<ContestDetailScreen> {
  bool _isFollowing = false;
  bool _hasJoined = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          _buildLiveIndicator(),
          _buildStatsSection(),
          _buildEntriesHeader(),
          _buildEntriesList(),
        ],
      ),
      bottomNavigationBar: _buildBottomAction(),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 250,
      pinned: true,
      backgroundColor: AppTheme.textMain,
      leading: IconButton(
        icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              'https://images.unsplash.com/photo-1516280440614-37939bbacd81',
              fit: BoxFit.cover,
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      const Icon(LucideIcons.eye, color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      const Text('4.7K', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The Next Star Talent Contest',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 12,
                        backgroundImage: NetworkImage('https://i.pravatar.cc/150?u=12'),
                      ),
                      const SizedBox(width: 8),
                      const Text('Hosted by MusicHub', style: TextStyle(color: Colors.white70, fontSize: 14)),
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

  Widget _buildLiveIndicator() {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.textMain,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TIME LEFT', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
                Text('01 : 23 : 45', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2)),
              ],
            ),
            const Spacer(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _isFollowing = !_isFollowing;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_isFollowing ? 'Following MusicHub' : 'Unfollowed MusicHub')),
                  );
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _isFollowing ? AppTheme.primary : Colors.transparent,
                  border: Border.all(color: AppTheme.primary),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isFollowing ? 'FOLLOWING' : 'FOLLOW', 
                  style: TextStyle(
                    color: _isFollowing ? Colors.white : AppTheme.primary, 
                    fontWeight: FontWeight.bold
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(LucideIcons.barChart2, '3.6K', 'Total Votes', AppTheme.primary),
            _buildStatItem(LucideIcons.star, '4.7', 'Reviews', Colors.orange),
            _buildStatItem(LucideIcons.users, '128', 'Participants', Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
      ],
    );
  }

  Widget _buildEntriesHeader() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Text(
              'LIVE RANKINGS',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 12),
            ),
            const Spacer(),
            const Icon(LucideIcons.zap, color: Colors.orange, size: 14),
            const SizedBox(width: 4),
            const Text('10s MOMENTUM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)),
          ],
        ),
      ),
    );
  }

  Widget _buildEntriesList() {
    return Consumer<RankingEngine>(
      builder: (context, engine, child) {
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = engine.entries[index];
                return EntryTile(
                  key: ValueKey(entry.id),
                  entry: entry,
                  rank: index + 1,
                  canVote: _hasJoined,
                  onVote: () => engine.addVote(entry.id),
                ).animate()
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.05, end: 0);
              },
              childCount: engine.entries.length,
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomAction() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20)],
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_hasJoined) return;
          
          showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (bottomSheetContext) => Container(
              padding: const EdgeInsets.all(24),
              height: 250,
              child: Column(
                children: [
                  const Icon(LucideIcons.checkCircle, color: Colors.green, size: 48),
                  const SizedBox(height: 16),
                  const Text('Joined Successfully!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Your entry is now live in the contest!'),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                      onPressed: () {
                        setState(() {
                          _hasJoined = true;
                        });
                        // Add mock user entry
                        final engine = Provider.of<RankingEngine>(context, listen: false);
                        engine.addMockUserEntry();
                        Navigator.pop(bottomSheetContext);
                      },
                      child: const Text('Let\'s Go!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: _hasJoined ? null : AppTheme.pinkPurpleGradient,
            color: _hasJoined ? Colors.grey.shade200 : null,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Center(
            child: Text(
              _hasJoined ? 'Voting Active - You are participating!' : 'Join Live & Vote',
              style: TextStyle(
                color: _hasJoined ? AppTheme.textMain : Colors.white, 
                fontWeight: FontWeight.bold, 
                fontSize: 18
              ),
            ),
          ),
        ),
      ),
    );
  }
}
