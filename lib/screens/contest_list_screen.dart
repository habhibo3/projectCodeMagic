import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_theme.dart';
import 'contest_detail_screen.dart';

class ContestListScreen extends StatefulWidget {
  const ContestListScreen({super.key});

  @override
  State<ContestListScreen> createState() => _ContestListScreenState();
}

class _ContestListScreenState extends State<ContestListScreen> {
  int _selectedTabIndex = 0;
  int _bottomNavIndex = 0;
  final Set<int> _joinedContests = {};
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<Map<String, String>> _allContests = [
    {
      'title': 'The Next Star Talent Contest',
      'subtitle': 'Show us your talent and be the next star!',
      'image': 'https://images.unsplash.com/photo-1516280440614-37939bbacd81',
      'type': 'Official',
    },
    {
      'title': 'Global Dance Off',
      'subtitle': 'Bring your best moves to the dance floor.',
      'image': 'https://images.unsplash.com/photo-1533174072545-7a4b6ad7a6c3',
      'type': 'Public Contest',
    },
    {
      'title': 'Comedy Night Live',
      'subtitle': 'Make us laugh and win the grand prize!',
      'image': 'https://images.unsplash.com/photo-1585699324551-f6c309eedeca',
      'type': 'Official',
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.green.shade800,
            child: const Text('t', style: TextStyle(color: Colors.white)),
          ),
        ),
        title: _isSearching 
          ? TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
              decoration: const InputDecoration(
                hintText: 'Search contests...',
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.grey),
              ),
              style: const TextStyle(color: AppTheme.textMain),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.trophy, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text('CONTEST', style: Theme.of(context).appBarTheme.titleTextStyle),
              ],
            ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? LucideIcons.x : LucideIcons.search), 
            onPressed: () {
              developer.log('DEBUG: App bar Search icon pressed. Current state _isSearching=$_isSearching');
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            }
          ),
          IconButton(
            icon: const Icon(LucideIcons.bell), 
            onPressed: () {
              developer.log('DEBUG: App bar Bell icon pressed.');
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No new notifications')));
            }
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _bottomNavIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: AppTheme.textSecondary,
        onTap: (index) {
          developer.log('DEBUG: BottomNavigationBar item tapped. Index=$index');
          setState(() {
            _bottomNavIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(LucideIcons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.compass), label: 'Explore'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.bell), label: 'Activity'),
          BottomNavigationBarItem(icon: Icon(LucideIcons.user), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_bottomNavIndex) {
      case 0:
        return _buildHomeContent();
      case 1:
        return _buildPlaceholderScreen('Search', LucideIcons.search);
      case 2:
        return _buildPlaceholderScreen('Explore', LucideIcons.compass);
      case 3:
        return _buildPlaceholderScreen('Activity & Notifications', LucideIcons.bell);
      case 4:
        return _buildPlaceholderScreen('Profile', LucideIcons.user);
      default:
        return _buildHomeContent();
    }
  }

  Widget _buildPlaceholderScreen(String title, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textMain),
          ),
          const SizedBox(height: 8),
          const Text(
            'Coming soon in future milestones',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeContent() {
    final filteredContests = _allContests.where((contest) {
      return contest['title']!.toLowerCase().contains(_searchQuery) ||
             contest['subtitle']!.toLowerCase().contains(_searchQuery);
    }).toList();

    return Column(
      children: [
        _buildTopTabs(),
        const Divider(height: 1),
        _buildTrendingBar(),
        Expanded(
          child: _selectedTabIndex == 0 
            ? filteredContests.isEmpty 
              ? _buildPlaceholderScreen('No matches found', LucideIcons.search)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filteredContests.length,
                  itemBuilder: (context, index) => _buildContestCard(context, index, filteredContests[index]),
                )
            : _buildPlaceholderScreen('No active contests here', LucideIcons.inbox),
        ),
      ],
    );
  }

  Widget _buildTopTabs() {
    final tabs = ['For you', 'Following', 'Subscribed', 'Trending'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: List.generate(tabs.length, (index) {
          return _buildTab(tabs[index], index, isActive: _selectedTabIndex == index);
        }),
      ),
    );
  }

  Widget _buildTab(String label, int index, {bool isActive = false}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        print('DEBUG: Top Tab tapped. Label=$label, Index=$index');
        setState(() {
          _selectedTabIndex = index;
        });
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 24),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? AppTheme.textMain : AppTheme.textSecondary,
              ),
            ),
            if (isActive)
              Container(
                margin: const EdgeInsets.only(top: 4),
                height: 2,
                width: 20,
                color: AppTheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendingBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: AppTheme.pinkPurpleGradient,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 14,
            backgroundImage: NetworkImage('https://i.pravatar.cc/150?u=9'),
          ),
          const SizedBox(width: 8),
          const Icon(LucideIcons.flame, color: Colors.orange, size: 16),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Trending: Contest Now',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const Icon(LucideIcons.chevronRight, color: Colors.white, size: 16),
        ],
      ),
    );
  }

  Widget _buildContestCard(BuildContext context, int index, Map<String, String> contestData) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ContestDetailScreen()),
              );
            },
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Image.network(
                contestData['image']!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          contestData['title']!,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                      if (contestData['type'] == 'Official')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(LucideIcons.checkCircle, size: 12, color: Colors.orange),
                              SizedBox(width: 4),
                              Text('Official', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    contestData['subtitle']!,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(LucideIcons.calendar, size: 14, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      const Text('Ends in 7 days', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      const SizedBox(width: 16),
                      const Icon(LucideIcons.users, size: 14, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      const Text('Public Contest', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStat(LucideIcons.barChart2, '3.6K', 'Total Votes', color: AppTheme.primary),
                      Container(width: 1, height: 40, color: Colors.grey.shade200),
                      _buildStat(LucideIcons.star, '4.7', '(239 Reviews)', color: Colors.orange),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Interaction Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildInteractionIcon(LucideIcons.messageCircle, '239'),
                      _buildInteractionIcon(LucideIcons.repeat, '41'),
                      _buildInteractionIcon(LucideIcons.heart, '3.6K'),
                      _buildInteractionIcon(LucideIcons.barChart2, '4.7M'),
                      const Icon(LucideIcons.bookmark, size: 20, color: AppTheme.textSecondary),
                      const Icon(LucideIcons.share, size: 20, color: AppTheme.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      print('DEBUG: ContestCard Join Contest tapped. Index=$index, CurrentlyJoined=${_joinedContests.contains(index)}');
                      setState(() {
                        if (_joinedContests.contains(index)) {
                          _joinedContests.remove(index);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Left contest')));
                        } else {
                          _joinedContests.add(index);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Successfully joined contest!')));
                        }
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: _joinedContests.contains(index) ? null : AppTheme.pinkPurpleGradient,
                        color: _joinedContests.contains(index) ? Colors.grey.shade300 : null,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _joinedContests.contains(index) ? LucideIcons.check : LucideIcons.trophy, 
                            color: _joinedContests.contains(index) ? AppTheme.textMain : Colors.white, 
                            size: 18
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _joinedContests.contains(index) ? 'Joined' : 'Join Contest',
                            style: TextStyle(
                              color: _joinedContests.contains(index) ? AppTheme.textMain : Colors.white, 
                              fontWeight: FontWeight.bold, 
                              fontSize: 16
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  Widget _buildStat(IconData icon, String value, String label, {required Color color}) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
      ],
    );
  }

  Widget _buildInteractionIcon(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
      ],
    );
  }
}
