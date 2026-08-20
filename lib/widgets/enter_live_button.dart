import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/entry.dart';
import '../screens/live_stream_screen.dart';
import '../theme/app_theme.dart';

/// Dedicated button to enter the live arena — keeps video taps for playback only.
class EnterLiveButton extends StatelessWidget {
  final ContestModel contest;
  final String? entryId;
  final bool compact;
  final bool isHost;

  const EnterLiveButton({
    super.key,
    required this.contest,
    this.entryId,
    this.compact = false,
    this.isHost = false,
  });

  void _openLive(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveStreamScreen(
          isHost: isHost,
          contest: contest,
          entryId: entryId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openLive(context),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isHost ? 'GO LIVE' : 'ENTER LIVE',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: isHost ? Colors.red : AppTheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        icon: Icon(
          isHost ? LucideIcons.radio : LucideIcons.tv2,
          size: 18,
        ),
        label: Text(
          isHost ? 'GO LIVE' : 'ENTER LIVE ARENA',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            letterSpacing: 0.5,
          ),
        ),
        onPressed: () => _openLive(context),
      ),
    );
  }
}
