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
import 'models/cohost_invite.dart';
import 'models/entry.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseSeeder.seedIfEmpty();
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  runApp(const FeastVoteApp());
}

class FeastVoteApp extends StatelessWidget {
  const FeastVoteApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FeastVote',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      navigatorKey: navigatorKey,
      home: const SplashScreen(),
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
          child: _GlobalInviteWrapper(child: const ContestListScreen()),
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

    final navigatorContext = FeastVoteApp.navigatorKey.currentContext;
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
                final navContext = ContestListScreen.homeNavKey.currentContext ?? FeastVoteApp.navigatorKey.currentContext;
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
                final navContext = ContestListScreen.homeNavKey.currentContext ?? FeastVoteApp.navigatorKey.currentContext;
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
