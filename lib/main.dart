import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'firebase_options.dart';
import 'data/firebase_seeder.dart';
import 'theme/app_theme.dart';
import 'engine/ranking_engine.dart';
import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/live_stream_screen.dart';
import 'screens/contest_list_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'models/cohost_invite.dart';
import 'models/entry.dart';
import 'data/admin_service.dart';

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
  bool _isAdmin = false;
  final AdminService _adminService = AdminService();

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      body: Row(
        children: [
          // Sidebar for web
          Container(
            width: 280,
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0C),
              border: Border(right: BorderSide(color: Colors.white.withOpacity(0.08))),
            ),
            child: Column(
              children: [
                const SizedBox(height: 40),
                // Logo
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [AppTheme.primary, Colors.purpleAccent]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(LucideIcons.trophy, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Mlivecast',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                // Navigation items
                _WebNavItem(
                  icon: LucideIcons.home,
                  label: 'Home',
                  onTap: () => _navigateTo(0),
                  isActive: _selectedIndex == 0,
                ),
                _WebNavItem(
                  icon: LucideIcons.map,
                  label: 'Map',
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
                  icon: LucideIcons.bell,
                  label: 'Activity',
                  onTap: () => _navigateTo(3),
                  isActive: _selectedIndex == 3,
                ),
                _WebNavItem(
                  icon: LucideIcons.user,
                  label: 'Profile',
                  onTap: () => _navigateTo(4),
                  isActive: _selectedIndex == 4,
                ),
                if (_isAdmin)
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
                const Spacer(),
                // User section
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () => _navigateTo(4),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141416),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: AppTheme.primary.withOpacity(0.2),
                                child: const Icon(LucideIcons.user, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'My Account',
                                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          await FirebaseAuth.instance.signOut();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.logOut, color: Colors.red, size: 16),
                              const SizedBox(width: 8),
                              const Text(
                                'Logout',
                                style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateTo(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _navChangeNotifier.value = index;
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
        title: Row(
          children: [
            const Icon(LucideIcons.radio, color: Color(0xFFC9A227), size: 24),
            const SizedBox(width: 12),
            const Expanded(
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
              engine.loadContestEntries(contest.id);
              final ok = await engine.acceptCoHostInvite(invite);
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              _isDialogShowing.value = false;
              if (ok) {
                final navContext = ContestListScreen.homeNavKey.currentContext ?? MlivecastApp.navigatorKey.currentContext;
                if (navContext != null) {
                  Navigator.push(
                    navContext,
                    MaterialPageRoute(
                      builder: (_) => LiveStreamScreen(
                        contest: contest,
                        entryId: invite.entryId,
                        isHost: false,
                        isCoHost: true,
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
