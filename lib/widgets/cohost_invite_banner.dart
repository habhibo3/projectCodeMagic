import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../engine/ranking_engine.dart';
import '../models/cohost_invite.dart';
import '../models/entry.dart';
import '../screens/live_stream_screen.dart';
import '../theme/app_theme.dart';

/// Shows real pending co-host invites and lets the user join live on Agora.
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
            return Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF051937),
                    AppTheme.primary.withValues(alpha: 0.35),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFC9A227), width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.radio, color: Color(0xFFC9A227), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${invite.hostName} invited you to co-host live',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => engine.declineCoHostInvite(invite.id),
                        child: const Text('Decline', style: TextStyle(color: Colors.white54)),
                      ),
                      const SizedBox(width: 8),
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
                ],
              ),
            );
          },
        );
      },
    );
  }
}
