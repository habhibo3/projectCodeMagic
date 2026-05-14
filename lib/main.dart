import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'engine/ranking_engine.dart';
import 'data/mock_data.dart';
import 'screens/contest_list_screen.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => RankingEngine()..setEntries(MockData.getEntries()),
        ),
      ],
      child: const ContestLiveApp(),
    ),
  );
}

class ContestLiveApp extends StatelessWidget {
  const ContestLiveApp({super.key});

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
