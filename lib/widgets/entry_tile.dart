import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/entry.dart';
import '../theme/app_theme.dart';

class EntryTile extends StatelessWidget {
  final ContestEntry entry;
  final int rank;
  final bool canVote;
  final VoidCallback onVote;

  const EntryTile({
    super.key,
    required this.entry,
    required this.rank,
    required this.canVote,
    required this.onVote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildContent(),
            _buildMomentumBar(),
            _buildInfoRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Stack(
      children: [
        if (entry.type == 'text')
          Container(
            height: 200,
            width: double.infinity,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(40),
            color: AppTheme.primary.withValues(alpha: 0.05),
            child: Text(
              entry.caption,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w400, color: AppTheme.textMain),
            ),
          )
        else
          Image.network(
            entry.contentUrl,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        
        // Rank Badge
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.5), blurRadius: 10)],
            ),
            child: Text(
              'RANK #$rank',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ),

        // Live Momentum Badge
        if (entry.windowVotes > 0)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.emerald.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.trendingUp, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    '+${entry.windowVotes}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
            ).animate(onPlay: (controller) => controller.repeat())
              .shimmer(duration: 1.seconds, color: Colors.white24)
              .scale(duration: 200.ms, curve: Curves.bounceOut),
          ),
      ],
    );
  }

  Widget _buildMomentumBar() {
    // A visual indicator of the 10s window strength
    double momentum = (entry.windowVotes / 10).clamp(0.0, 1.0);
    return Container(
      height: 3,
      width: double.infinity,
      color: Colors.white.withValues(alpha: 0.05),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: momentum,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.accent,
            boxShadow: [BoxShadow(color: AppTheme.accent.withValues(alpha: 0.5), blurRadius: 4)],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            backgroundImage: NetworkImage(entry.userAvatar),
            radius: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.userName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (entry.type != 'text')
                  Text(
                    entry.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.totalVotes}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.accent,
                ),
              ),
              const Text(
                'TOTAL',
                style: TextStyle(fontSize: 8, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(width: 16),
          _VoteButton(onVote: onVote, canVote: canVote),
        ],
      ),
    );
  }
}

class _VoteButton extends StatefulWidget {
  final VoidCallback onVote;
  final bool canVote;
  const _VoteButton({required this.onVote, required this.canVote});

  @override
  State<_VoteButton> createState() => _VoteButtonState();
}

class _VoteButtonState extends State<_VoteButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (widget.canVote) _controller.forward();
      },
      onTapUp: (_) {
        if (widget.canVote) {
          _controller.reverse();
          widget.onVote();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You must Join the Live Arena to vote!')),
          );
        }
      },
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 1.3).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut)),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: widget.canVote ? AppTheme.primary.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: widget.canVote ? AppTheme.primary.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.3)),
          ),
          child: Icon(LucideIcons.heart, color: widget.canVote ? AppTheme.primary : Colors.grey, size: 20),
        ),
      ),
    );
  }
}
