import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'data/auth_service.dart';
import 'data/firebase_seeder.dart';
import 'data/firebase_service.dart';
import 'theme/app_theme.dart';
import 'engine/ranking_engine.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  String? userId;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    userId = await AuthService.instance.ensureSignedIn();
    await FirebaseSeeder.seedIfEmpty();
    await FirebaseService().ensureUserProfile(userId);
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  if (userId == null) {
    runApp(const _AuthErrorApp());
    return;
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RankingEngine(currentUserId: userId!)),
      ],
      child: const FeastVoteApp(),
    ),
  );
}

class _AuthErrorApp extends StatelessWidget {
  const _AuthErrorApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Could not connect. Enable Anonymous sign-in in Firebase Console → Authentication.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class FeastVoteApp extends StatelessWidget {
  const FeastVoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FeastVote',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
