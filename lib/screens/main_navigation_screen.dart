import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../engine/ranking_engine.dart';
import '../theme/app_theme.dart';
import 'station_list_screen.dart';
import 'contest_list_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final List<GlobalKey<NavigatorState>> _navKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        final navState = _navKeys[_currentIndex].currentState;
        if (navState != null && navState.canPop()) {
          navState.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: IndexedStack(
          index: _currentIndex,
          children: [
            Navigator(
              key: _navKeys[0],
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (_) => const StationListScreen(),
              ),
            ),
            Navigator(
              key: _navKeys[1],
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (_) => const ContestListScreen(),
              ),
            ),
          ],
        ),
        bottomNavigationBar: Theme(
          data: ThemeData(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              backgroundColor: const Color(0xFF0A0A0A),
              type: BottomNavigationBarType.fixed,
              selectedItemColor: AppTheme.primary,
              unselectedItemColor: Colors.white38,
              showSelectedLabels: true,
              showUnselectedLabels: true,
              selectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, height: 1.5),
              unselectedLabelStyle: const TextStyle(fontSize: 10, height: 1.5),
              onTap: (index) {
                if (index == _currentIndex) {
                  _navKeys[index].currentState?.popUntil((r) => r.isFirst);
                }
                setState(() => _currentIndex = index);
              },
              items: const [
                BottomNavigationBarItem(icon: Icon(LucideIcons.radio), label: 'Stations'),
                BottomNavigationBarItem(icon: Icon(LucideIcons.trophy), label: 'Contests'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
