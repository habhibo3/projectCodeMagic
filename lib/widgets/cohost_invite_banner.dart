import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../engine/ranking_engine.dart';
import '../models/cohost_invite.dart';
import '../models/entry.dart';
import '../screens/live_stream_screen.dart';
import '../theme/app_theme.dart';

/// Shows real pending co-host invites as a modal dialog that blocks interaction.
class CoHostInviteBanner extends StatelessWidget {
  final ContestModel contest;

  const CoHostInviteBanner({super.key, required this.contest});

  @override
  Widget build(BuildContext context) {
    return Consumer<RankingEngine>(
      builder: (context, engine, _) {
        return StreamBuilder<List<CoHostInvite>>(
          stream: engine.watchPendingCoHostInvites(),
          builder: (context, snapshot) {
            final invites = snapshot.data ?? [];
            final forContest =
                invites.where((i) => i.contestId == contest.id).toList();
            if (forContest.isEmpty) return const SizedBox.shrink();

            final invite = forContest.first;
            
            // Show as modal dialog that blocks interaction
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showInviteDialog(context, engine, invite);
            });
            
            return const SizedBox.shrink();
          },
        );
      },
    );
  }

  void _showInviteDialog(BuildContext context, RankingEngine engine, CoHostInvite invite) {
    showDialog(
      context: context,
      barrierDismissible: false, // Cannot dismiss by tapping outside
      builder: (context) => AlertDialog(
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
              Navigator.of(context).pop();
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
              if (!context.mounted) return;
              Navigator.of(context).pop();
              if (ok) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LiveStreamScreen(
                      contest: contest,
                      entryId: invite.entryId,
                      isHost: false,
                      isCoHost: true,
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invite expired or already used'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
