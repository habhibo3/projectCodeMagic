import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/admin_service.dart';
import '../theme/app_theme.dart';

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  final AdminService _adminService = AdminService();
  Map<String, dynamic>? _dashboardStats;
  List<Map<String, dynamic>> _voteTrends = [];
  List<Map<String, dynamic>> _topContests = [];
  List<Map<String, dynamic>> _topUsers = [];

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    final stats = await _adminService.getDashboardStats();
    final trends = await _adminService.getVoteTrends(days: 7);
    final topContests = await _adminService.getTopContests(limit: 10);
    final topUsers = await _adminService.getTopUsers(limit: 10);

    if (mounted) {
      setState(() {
        _dashboardStats = stats;
        _voteTrends = trends;
        _topContests = topContests;
        _topUsers = topUsers;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Analytics Dashboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text('Refresh'),
                  onPressed: _loadAnalytics,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Platform performance metrics and engagement analytics',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            if (_dashboardStats != null) ...[
              _buildOverviewStats(),
              const SizedBox(height: 32),
              _buildVoteTrendsChart(),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(child: _buildTopContests()),
                  const SizedBox(width: 24),
                  Expanded(child: _buildTopUsers()),
                ],
              ),
            ] else
              const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Platform Overview',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 2.5,
          children: [
            _buildStatCard(
              'Total Users',
              _dashboardStats?['totalUsers']?.toString() ?? '0',
              LucideIcons.users,
              Colors.blue,
              '',
            ),
            _buildStatCard(
              'Total Contests',
              _dashboardStats?['totalContests']?.toString() ?? '0',
              LucideIcons.trophy,
              Colors.orange,
              '',
            ),
            _buildStatCard(
              'Total Posts',
              _dashboardStats?['totalPosts']?.toString() ?? '0',
              LucideIcons.image,
              Colors.green,
              '',
            ),
            _buildStatCard(
              'Total Votes',
              _dashboardStats?['totalVotes']?.toString() ?? '0',
              LucideIcons.heart,
              Colors.red,
              '',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, String change) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              if (change.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    change,
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoteTrendsChart() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Vote Trends (Last 7 Days)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Weekly',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            child: _voteTrends.isEmpty
                ? Center(
                    child: Text(
                      'No vote data available',
                      style: TextStyle(color: Colors.white.withOpacity(0.5)),
                    ),
                  )
                : _buildSimpleChart(_voteTrends),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleChart(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return const SizedBox.shrink();

    final maxVotes = data.map((e) => e['votes'] as int).reduce((a, b) => a > b ? a : b);
    final maxVotesDisplay = maxVotes > 0 ? maxVotes : 1;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: data.map((item) {
        final votes = item['votes'] as int;
        final height = (votes / maxVotesDisplay) * 140;
        final date = item['date'] as String;
        final dayName = date.split('-').last;

        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 28,
              height: height > 0 ? height.toDouble() : 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    AppTheme.primary.withOpacity(0.3),
                    AppTheme.primary,
                  ],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              dayName,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 9,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              votes.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildTopContests() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top Contests',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          if (_topContests.isEmpty)
            Center(
              child: Text(
                'No contests data',
                style: TextStyle(color: Colors.white.withOpacity(0.5)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _topContests.take(5).length,
              separatorBuilder: (_, __) => const Divider(
                color: Colors.white10,
                height: 16,
              ),
              itemBuilder: (context, index) {
                final contest = _topContests[index];
                return _buildContestRow(contest, index + 1);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildContestRow(Map<String, dynamic> contest, int rank) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: rank <= 3
                ? [Colors.amber, Colors.grey, Colors.brown][rank - 1].withOpacity(0.3)
                : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              rank.toString(),
              style: TextStyle(
                color: rank <= 3
                    ? [Colors.amber, Colors.grey, Colors.brown][rank - 1]
                    : Colors.white54,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                contest['title'] as String,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(LucideIcons.users, size: 10, color: Colors.white38),
                  const SizedBox(width: 4),
                  Text(
                    '${contest['participantCount']} participants',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${contest['totalVotes']}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'votes',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopUsers() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top Voters',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          if (_topUsers.isEmpty)
            Center(
              child: Text(
                'No users data',
                style: TextStyle(color: Colors.white.withOpacity(0.5)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _topUsers.take(5).length,
              separatorBuilder: (_, __) => const Divider(
                color: Colors.white10,
                height: 16,
              ),
              itemBuilder: (context, index) {
                final user = _topUsers[index];
                return _buildUserRow(user, index + 1);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildUserRow(Map<String, dynamic> user, int rank) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: rank <= 3
                ? [Colors.amber, Colors.grey, Colors.brown][rank - 1].withOpacity(0.3)
                : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              rank.toString(),
              style: TextStyle(
                color: rank <= 3
                    ? [Colors.amber, Colors.grey, Colors.brown][rank - 1]
                    : Colors.white54,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user['displayName'] as String,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(LucideIcons.mapPin, size: 10, color: Colors.white38),
                  const SizedBox(width: 4),
                  Text(
                    user['country'] as String,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (user['subscriptionLevel'] == 'premium'
                          ? Colors.amber.withOpacity(0.2)
                          : Colors.white.withOpacity(0.1)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      user['subscriptionLevel'] as String,
                      style: TextStyle(
                        color: user['subscriptionLevel'] == 'premium'
                            ? Colors.amber
                            : Colors.white54,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${user['totalVotesCast']}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'votes',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
