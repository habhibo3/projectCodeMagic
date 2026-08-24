import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contest_live/screens/create_contest_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'firebase_options.dart';
import 'data/firebase_seeder.dart';
import 'data/firebase_service.dart';
import 'data/live_session_service.dart';
import 'theme/app_theme.dart';
import 'engine/ranking_engine.dart';
import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/live_stream_screen.dart';
import 'models/station.dart';
import 'screens/contest_list_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'models/cohost_invite.dart';
import 'models/entry.dart';
import 'data/admin_service.dart';
import 'widgets/avatar_helper.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Only lock orientation on mobile
  if (!kIsWeb) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }



  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MlivecastApp());
}

class MlivecastApp extends StatelessWidget {
  const MlivecastApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mlivecast',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      navigatorKey: navigatorKey,
      home: const AuthWrapper(),
    );
  }
}

/// Routes between AuthScreen and ContestListScreen based on user authentication status.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0A0A0A),
            body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
          );
        }
        
        final user = snapshot.data;
        if (user == null) {
          return const AuthScreen();
        }

        return MultiProvider(
          key: ValueKey(user.uid),
          providers: [
            ChangeNotifierProvider(create: (_) => RankingEngine(currentUserId: user.uid)),
          ],
          child: kIsWeb
              ? _WebLayoutWrapper(child: const ContestListScreen())
              : _GlobalInviteWrapper(child: const ContestListScreen()),
        );
      },
    );
  }
}

class _GlobalInviteWrapper extends StatelessWidget {
  final Widget child;

  const _GlobalInviteWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<RankingEngine>(
      builder: (context, engine, _) {
        return Stack(
          children: [
            child,
            // Global cohost invite overlay
            _GlobalInviteOverlay(),
          ],
        );
      },
    );
  }
}

// Web-specific layout wrapper for desktop experience
class _WebLayoutWrapper extends StatefulWidget {
  final Widget child;

  const _WebLayoutWrapper({required this.child});

  @override
  State<_WebLayoutWrapper> createState() => _WebLayoutWrapperState();
}

class _WebLayoutWrapperState extends State<_WebLayoutWrapper> {
  int _selectedIndex = 0;
  final ValueNotifier<int?> _navChangeNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<String> _categoryNotifier = ValueNotifier<String>('All');
  final ValueNotifier<String> _searchNotifier = ValueNotifier<String>('');
  String _selectedCategory = 'All';
  bool _isAdmin = false;
  final AdminService _adminService = AdminService();

  final List<String> _categories = ['All', 'Music', 'Dance', 'Comedy', 'Art', 'Sports', 'Gaming'];

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    _categoryNotifier.addListener(_onCategoryNotifierChange);
  }

  void _onCategoryNotifierChange() {
    if (mounted) {
      setState(() {
        _selectedCategory = _categoryNotifier.value;
      });
    }
  }

  Future<void> _checkAdminStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final isAdmin = await _adminService.isAdmin(user.uid);
      if (mounted) {
        setState(() {
          _isAdmin = isAdmin;
        });
      }
    }
  }

  @override
  void dispose() {
    _navChangeNotifier.dispose();
    _categoryNotifier.dispose();
    _searchNotifier.dispose();
    super.dispose();
  }

  void _navigateTo(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _navChangeNotifier.value = index;
  }

  IconData _getCategoryIcon(String cat) {
    switch (cat.toLowerCase()) {
      case 'all':
        return LucideIcons.layoutGrid;
      case 'music':
        return LucideIcons.music;
      case 'dance':
        return LucideIcons.star;
      case 'comedy':
        return LucideIcons.smile;
      case 'art':
        return LucideIcons.palette;
      case 'sports':
        return LucideIcons.trophy;
      case 'gaming':
        return LucideIcons.gamepad2;
      default:
        return LucideIcons.tag;
    }
  }

  Widget _buildTopHeader(BuildContext context) {
    final engine = Provider.of<RankingEngine>(context);
    final profile = engine.currentUserProfile;
    final photoURL = profile?.photoURL ?? FirebaseAuth.instance.currentUser?.photoURL;
    final hasPhoto = photoURL != null && photoURL.isNotEmpty;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: Row(
        children: [
          // Left: Menu & Logo
          IconButton(
            icon: const Icon(LucideIcons.menu, color: Colors.white),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Colors.redAccent, Colors.purpleAccent]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.flame, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 8),
          const Text(
            'MLIVECAST',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(flex: 3),
          // Center: Search input
          Container(
            width: 480,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    onChanged: (val) {
                      _searchNotifier.value = val.toLowerCase();
                    },
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Search contests, creators...',
                      hintStyle: TextStyle(color: Colors.white30, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.search, color: Colors.white38, size: 16),
                  onPressed: () {},
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          const Spacer(flex: 4),
          // Right: Action buttons & Avatar
          IconButton(
            icon: const Icon(LucideIcons.video, color: Colors.white70, size: 20),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: engine,
                    child: const CreateContestScreen(),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(LucideIcons.bell, color: Colors.white70, size: 20),
            onPressed: () {},
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _navigateTo(5),
            child: CircleAvatar(
              radius: 16,
              backgroundImage: hasPhoto ? AvatarHelper.getSafeAvatarProvider(photoURL) : null,
              backgroundColor: Colors.grey.shade900,
              child: !hasPhoto ? const Icon(LucideIcons.user, size: 16, color: Colors.white60) : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = Provider.of<RankingEngine>(context);
    final profile = engine.currentUserProfile;
    final photoURL = profile?.photoURL ?? FirebaseAuth.instance.currentUser?.photoURL;
    final hasPhoto = photoURL != null && photoURL.isNotEmpty;
    final displayName = profile?.displayName ?? FirebaseAuth.instance.currentUser?.displayName ?? 'My Account';

    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      body: Column(
        children: [
          // Top Header spanning full width
          _buildTopHeader(context),
          // Expanded bottom split layout
          Expanded(
            child: Row(
              children: [
                // Sidebar for web
                Container(
                  width: 240,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F0F),
                    border: Border(right: BorderSide(color: Colors.white.withOpacity(0.08))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      // Navigation items
                      _WebNavItem(
                        icon: LucideIcons.radio,
                        label: 'Stations',
                        onTap: () => _navigateTo(0),
                        isActive: _selectedIndex == 0,
                      ),
                      _WebNavItem(
                        icon: LucideIcons.trophy,
                        label: 'Contests',
                        onTap: () => _navigateTo(1),
                        isActive: _selectedIndex == 1,
                      ),
                      _WebNavItem(
                        icon: LucideIcons.flame,
                        label: 'Explore Feed',
                        onTap: () => _navigateTo(2),
                        isActive: _selectedIndex == 2,
                      ),
                      _WebNavItem(
                        icon: LucideIcons.map,
                        label: 'Contests Map',
                        onTap: () => _navigateTo(3),
                        isActive: _selectedIndex == 3,
                      ),
                      _WebNavItem(
                        icon: LucideIcons.bell,
                        label: 'Activity',
                        onTap: () => _navigateTo(4),
                        isActive: _selectedIndex == 4,
                      ),
                      _WebNavItem(
                        icon: LucideIcons.sparkles,
                        label: 'Subscriptions',
                        onTap: () => _navigateTo(7),
                        isActive: _selectedIndex == 7 && _selectedCategory == 'All',
                      ),
                      _WebNavItem(
                        icon: LucideIcons.bookmark,
                        label: 'Saved Contests',
                        onTap: () => _navigateTo(6),
                        isActive: _selectedIndex == 6,
                      ),
                      if (_isAdmin) ...[
                        const Divider(color: Colors.white12, height: 16),
                        _WebNavItem(
                          icon: LucideIcons.shield,
                          label: 'Admin Panel',
                          onTap: () {
                            Navigator.of(context).push(
                              PageRouteBuilder(
                                pageBuilder: (context, animation, secondaryAnimation) => const AdminDashboardScreen(),
                                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                  return FadeTransition(opacity: animation, child: child);
                                },
                              ),
                            );
                          },
                          isActive: false,
                        ),
                      ],
                      const Divider(color: Colors.white12, height: 16),
                      // Categories header
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        child: Text(
                          'Categories',
                          style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: _categories.map((cat) {
                            final isSelected = _selectedCategory == cat;
                            return _WebNavItem(
                              icon: _getCategoryIcon(cat),
                              label: cat,
                              onTap: () {
                                _categoryNotifier.value = cat;
                                // If we are not in Contests tab, navigate to Contests tab (index 1)
                                if (_selectedIndex != 1) {
                                  _navigateTo(1);
                                }
                              },
                              isActive: isSelected,
                            );
                          }).toList(),
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 16),
                      // User Section at the bottom
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: InkWell(
                          onTap: () => _navigateTo(5),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F1F1F),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundImage: hasPhoto ? AvatarHelper.getSafeAvatarProvider(photoURL) : null,
                                  backgroundColor: Colors.grey.shade900,
                                  child: !hasPhoto ? const Icon(LucideIcons.user, size: 16, color: Colors.white60) : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: InkWell(
                          onTap: () async {
                            await FirebaseAuth.instance.signOut();
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.withOpacity(0.2)),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.logOut, color: Colors.red, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  'Logout',
                                  style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                // Main content area
                Expanded(
                  child: _GlobalInviteWrapper(
                    child: ContestListScreen(
                      onWebNavChange: (index) {
                        setState(() {
                          _selectedIndex = index;
                        });
                      },
                      webNavNotifier: _navChangeNotifier,
                      webCategoryNotifier: _categoryNotifier,
                      webSearchNotifier: _searchNotifier,
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
}

class _WebNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _WebNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primary.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isActive ? AppTheme.primary : Colors.white54,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white54,
                fontSize: 14,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlobalInviteOverlay extends StatefulWidget {
  @override
  State<_GlobalInviteOverlay> createState() => _GlobalInviteOverlayState();
}

class _GlobalInviteOverlayState extends State<_GlobalInviteOverlay> {
  final ValueNotifier<bool> _isDialogShowing = ValueNotifier<bool>(false);
  CoHostInvite? _currentInvite;

  @override
  void dispose() {
    _isDialogShowing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RankingEngine>(
      builder: (context, engine, _) {
        return StreamBuilder<List<CoHostInvite>>(
          stream: engine.watchPendingCoHostInvites(),
          builder: (context, snapshot) {
            final invites = snapshot.data ?? [];
            if (invites.isEmpty) {
              _currentInvite = null;
              _isDialogShowing.value = false;
              return const SizedBox.shrink();
            }

            final invite = invites.first;
            
            // Only show dialog if invite changed and no dialog is currently showing
            if (_currentInvite?.id != invite.id && !_isDialogShowing.value) {
              _currentInvite = invite;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_isDialogShowing.value) {
                  _isDialogShowing.value = true;
                  _showInviteDialog(context, engine, invite);
                }
              });
            }
            
            return const SizedBox.shrink();
          },
        );
      },
    );
  }

  void _showInviteDialog(BuildContext context, RankingEngine engine, CoHostInvite invite) {
    final navigatorContext = MlivecastApp.navigatorKey.currentContext;
    if (navigatorContext == null) return;

    showDialog(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFC9A227), width: 1.2),
        ),
        title: const Row(
          children: [
            Icon(LucideIcons.radio, color: Color(0xFFC9A227), size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Co-Host Invitation',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          '${invite.hostName} invited you to co-host live',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 15,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              engine.declineCoHostInvite(invite.id);
              Navigator.of(dialogContext).pop();
              _isDialogShowing.value = false;
            },
            child: const Text(
              'Decline',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(LucideIcons.video, size: 16),
            label: const Text('Join as Co-Host'),
            onPressed: () async {
              // ── Station co-host invite ──
              if (invite.stationId != null && invite.stationId!.isNotEmpty) {
                final liveService = LiveSessionService();
                final ok = await liveService.acceptStationCoHostInvite(invite);
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                _isDialogShowing.value = false;
                if (ok) {
                  // Fetch the station model to build the ContestModel for navigation
                  StationModel? station;
                  try {
                    station = await FirebaseService().getStationOnce(invite.stationId!);
                  } catch (e) {
                    debugPrint('[InviteDialog] Failed to fetch station: $e');
                  }
                  final navContext = MlivecastApp.navigatorKey.currentContext;
                  if (navContext != null && station != null) {
                    Navigator.of(navContext).popUntil((r) => r.isFirst);
                    await Future.delayed(const Duration(milliseconds: 250));
                    if (!navContext.mounted) return;
                    Navigator.push(
                      navContext,
                      MaterialPageRoute(
                        builder: (_) => ChangeNotifierProvider.value(
                          value: engine,
                          child: LiveStreamScreen(
                            contest: station!.toContestModel(),
                            entryId: null,
                            isHost: false,
                            isCoHost: true,
                          ),
                        ),
                      ),
                    );
                  } else if (navContext != null) {
                    ScaffoldMessenger.of(navContext).showSnackBar(
                      const SnackBar(
                        content: Text('Could not find station — please try again.'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                } else {
                  final navContext = ContestListScreen.homeNavKey.currentContext ?? MlivecastApp.navigatorKey.currentContext;
                  if (navContext != null) {
                    ScaffoldMessenger.of(navContext).showSnackBar(
                      const SnackBar(
                        content: Text('Invite expired or already used'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                }
                return;
              }

              // ── Contest co-host invite ──
              final contests = engine.contests;
              final contest = contests.firstWhere(
                (c) => c.id == invite.contestId,
                orElse: () => contests.isNotEmpty
                    ? contests.first
                    : const ContestModel(
                        id: '',
                        title: '',
                        subtitle: '',
                        description: '',
                        rules: '',
                        prize: '',
                        schedule: '',
                        image: '',
                        category: '',
                        type: '',
                        participantCount: 0,
                        totalVotes: 0,
                        rating: 0,
                        reviewCount: 0,
                        endsIn: '',
                      ),
              );
              engine.loadContestEntries(contest.id);
              final ok = await engine.acceptCoHostInvite(invite);
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              _isDialogShowing.value = false;
              if (ok) {
                final navContext = MlivecastApp.navigatorKey.currentContext;
                if (navContext != null) {
                  Navigator.of(navContext).popUntil((r) => r.isFirst);
                  await Future.delayed(const Duration(milliseconds: 250));
                  if (!navContext.mounted) return;
                  Navigator.push(
                    navContext,
                    MaterialPageRoute(
                      builder: (_) => ChangeNotifierProvider.value(
                        value: engine,
                        child: LiveStreamScreen(
                          contest: contest,
                          entryId: invite.entryId,
                          isHost: false,
                          isCoHost: true,
                        ),
                      ),
                    ),
                  );
                }
              } else {
                final navContext = ContestListScreen.homeNavKey.currentContext ?? MlivecastApp.navigatorKey.currentContext;
                if (navContext != null) {
                  ScaffoldMessenger.of(navContext).showSnackBar(
                    const SnackBar(
                      content: Text('Invite expired or already used'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
