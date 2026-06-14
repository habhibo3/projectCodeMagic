import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_core/firebase_core.dart';
import '../theme/app_theme.dart';
import '../main.dart';
import '../firebase_options.dart';
import '../data/firebase_seeder.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await FirebaseSeeder.seedIfEmpty();
    } catch (e) {
      // Silently handle Firebase initialization errors
    }

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });

      // Navigate after initialization and minimum splash time
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const AuthWrapper(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: AppTheme.pinkPurpleGradient,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated Logo Icon
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(
                LucideIcons.flame,
                size: 64,
                color: AppTheme.primary,
              ),
            )
            .animate()
            .scale(duration: 800.ms, curve: Curves.easeOutBack)
            .then()
            .shimmer(duration: 1200.ms, color: AppTheme.accent.withValues(alpha: 0.5))
            .shake(hz: 2, duration: 500.ms),

            const SizedBox(height: 32),

            // App Name
            const Text(
              'FeastVote',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2,
              ),
            )
            .animate()
            .fadeIn(delay: 400.ms, duration: 800.ms)
            .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),

            const SizedBox(height: 16),

            // Tagline
            const Text(
              'The Live Ranking Arena',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white70,
                letterSpacing: 3,
              ),
            )
            .animate()
            .fadeIn(delay: 800.ms, duration: 800.ms),

            const SizedBox(height: 64),

            // Loading indicator
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              strokeWidth: 3,
            )
            .animate()
            .fadeIn(delay: 1200.ms),
          ],
        ),
      ),
    );
  }
}
