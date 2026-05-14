import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/entry.dart';

class RankingEngine extends ChangeNotifier {
  List<ContestEntry> _entries = [];
  final Map<String, List<DateTime>> _voteHistory = {};
  Timer? _refreshTimer;

  List<ContestEntry> get entries => List.unmodifiable(_entries);

  RankingEngine() {
    _startHeartbeat();
    _startSimulation();
  }

  void _startSimulation() {
    // Simulate random votes from "other users" every few seconds
    Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (_entries.isNotEmpty) {
        final randomEntry = (_entries.toList()..shuffle()).first;
        addVote(randomEntry.id);
      }
    });
  }

  void setEntries(List<ContestEntry> initialEntries) {
    _entries = initialEntries;
    notifyListeners();
  }

  void addMockUserEntry() {
    final newId = 'user_entry_${DateTime.now().millisecondsSinceEpoch}';
    final newEntry = ContestEntry(
      id: newId,
      userId: 'my_user',
      userName: 'You (Player) 🎤',
      userAvatar: 'https://i.pravatar.cc/150?u=99',
      contentUrl: 'https://images.unsplash.com/photo-1516280440614-37939bbacd81',
      type: 'image',
      caption: 'My awesome entry! 🎉',
      totalVotes: 50,
      windowVotes: 50,
    );
    
    // Inject 50 instant votes into the engine so the user shoots to #1 rank
    final now = DateTime.now();
    _voteHistory[newId] = List.generate(50, (_) => now);
    
    _entries = List.from(_entries)..insert(0, newEntry);
    _calculateWindowVotes(); // Force immediate re-sort
  }

  void _startHeartbeat() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _calculateWindowVotes();
    });
  }

  void addVote(String entryId) {
    final now = DateTime.now();
    _voteHistory.putIfAbsent(entryId, () => []).add(now);
    
    // Increment total votes instantly
    final index = _entries.indexWhere((e) => e.id == entryId);
    if (index != -1) {
      _entries[index] = _entries[index].copyWith(
        totalVotes: _entries[index].totalVotes + 1,
      );
      _calculateWindowVotes(); // Trigger re-rank immediately on vote
    }
  }

  void _calculateWindowVotes() {
    final now = DateTime.now();
    final windowStart = now.subtract(const Duration(seconds: 10));

    bool changed = false;

    for (int i = 0; i < _entries.length; i++) {
      final entryId = _entries[i].id;
      final votes = _voteHistory[entryId] ?? [];
      
      // Clean up old votes
      votes.removeWhere((v) => v.isBefore(windowStart));
      
      final currentWindowCount = votes.length;
      if (_entries[i].windowVotes != currentWindowCount) {
        _entries[i] = _entries[i].copyWith(windowVotes: currentWindowCount);
        changed = true;
      }
    }

    if (changed) {
      // Sort by windowVotes (Momentum), then totalVotes as tie-breaker
      _entries.sort((a, b) {
        int cmp = b.windowVotes.compareTo(a.windowVotes);
        if (cmp == 0) return b.totalVotes.compareTo(a.totalVotes);
        return cmp;
      });
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
