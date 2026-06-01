import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../engine/ranking_engine.dart';
import '../models/entry.dart';
import '../models/comment.dart';
import '../models/review.dart';
import '../theme/app_theme.dart';
import 'live_stream_screen.dart';

class EntryPostScreen extends StatefulWidget {
  final ContestEntry initialEntry;
  final int initialRank;
  final Future<bool> Function() onVote;
  final ContestModel contest;

  const EntryPostScreen({
    super.key,
    required this.initialEntry,
    required this.initialRank,
    required this.onVote,
    required this.contest,
  });

  @override
  State<EntryPostScreen> createState() => _EntryPostScreenState();
}

class _EntryPostScreenState extends State<EntryPostScreen> {
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _reviewController = TextEditingController();
  int _userRating = 0;
  int _activeTab = 0; // 0 = Comments, 1 = Reviews

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final engine = Provider.of<RankingEngine>(context, listen: false);
      engine.loadContestEntries(widget.contest.id);
      engine.trackEntryView(widget.initialEntry.id);
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    _reviewController.dispose();
    super.dispose();
  }

  String _formatTimestamp(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RankingEngine>(
      builder: (context, engine, child) {
        final entryIndex = engine.entries.indexWhere((e) => e.id == widget.initialEntry.id);
        final entry = entryIndex != -1 ? engine.entries[entryIndex] : widget.initialEntry;
        final rank = entryIndex != -1 ? entryIndex + 1 : widget.initialRank;

        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0A), // Sleek black
          appBar: AppBar(
            backgroundColor: const Color(0xFF0A0A0A),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(LucideIcons.share2, color: Colors.white),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copied to clipboard!'), behavior: SnackBarBehavior.floating),
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildContent(entry, rank),
                      _buildPostInfo(entry, engine),
                      _buildVoteContainer(entry, engine),
                      _buildRatingSection(entry, engine),
                      const SizedBox(height: 16),
                      _buildTabbarSwitch(),
                      const Divider(height: 1, color: Colors.white24),
                      _activeTab == 0
                          ? _buildCommentsSection(entry, engine)
                          : _buildReviewsSection(entry, engine),
                    ],
                  ),
                ),
              ),
              if (_activeTab == 0) _buildCommentInput(entry, engine),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(ContestEntry entry, int rank) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LiveStreamScreen(
              isHost: false,
              contest: widget.contest,
              entryId: entry.id,
            ),
          ),
        );
      },
      child: Stack(
        children: [
          Image.network(
            entry.contentUrl,
            width: double.infinity,
            height: 240,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 240,
              color: Colors.grey.shade900,
              child: const Icon(LucideIcons.image, size: 60, color: Colors.grey),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                child: const Icon(LucideIcons.play, color: Colors.white, size: 32),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
              child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
          Positioned(
            bottom: 12,
            right: 12,
            child: const Icon(LucideIcons.maximize, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildPostInfo(ContestEntry entry, RankingEngine engine) {
    return StreamBuilder<List<ReviewModel>>(
      stream: engine.getReviews(entry.id),
      builder: (context, reviewSnap) {
        final reviews = reviewSnap.data ?? [];
        double avgRating = entry.averageRating;
        int reviewCount = entry.reviewCount;
        if (reviews.isNotEmpty) {
          reviewCount = reviews.length;
          avgRating = reviews.fold<double>(0, (s, r) => s + r.ratingStars) / reviews.length;
        }
        final filledStars = avgRating.round().clamp(0, 5);

        return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(entry.caption,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, height: 1.3)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ...List.generate(5, (i) => Icon(
                LucideIcons.star,
                color: i < filledStars ? Colors.amber : Colors.white38,
                size: 16,
              )),
              const SizedBox(width: 8),
              Text('${avgRating.toStringAsFixed(1)} Stars ($reviewCount reviews)',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(LucideIcons.thumbsUp, size: 14, color: Colors.amber),
              const SizedBox(width: 4),
              Text('${entry.totalVotes} Votes', style: const TextStyle(fontSize: 12, color: Colors.amber)),
              const SizedBox(width: 16),
              const Icon(LucideIcons.eye, size: 14, color: Colors.amber),
              const SizedBox(width: 4),
              Text('${entry.totalVotes} Views', style: const TextStyle(fontSize: 12, color: Colors.amber)),
            ],
          ),
        ],
      ),
    );
      },
    );
  }

  Widget _buildVoteContainer(ContestEntry entry, RankingEngine engine) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('TOTAL VOTES', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text(
            _formatNumberComma(entry.totalVotes),
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 48,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ).animate(key: ValueKey(entry.totalVotes)).scale(begin: const Offset(1.1, 1.1), end: const Offset(1.0, 1.0), duration: 300.ms),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            icon: const Icon(LucideIcons.heart, size: 20),
            label: const Text('VOTE NOW', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
            onPressed: () async {
              final success = await widget.onVote();
              if (mounted) {
                if (!success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          Icon(LucideIcons.alertTriangle, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Limit reached! Already voted for this entry.', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                      backgroundColor: Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          Icon(LucideIcons.checkCircle, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Vote cast & lifetime count updated!', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 16),
          
          if (entry.totalVotes > 0) ...[
            // Activity Feed
            ...engine.voteActivity.take(4).map((activity) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text(activity.countryFlag, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(activity.userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          const Text('Just voted!', style: TextStyle(color: Colors.white54, fontSize: 10)),
                          const SizedBox(height: 2),
                          Text(activity.comment, style: const TextStyle(color: Colors.white, fontSize: 11)),
                        ],
                      ),
                    ),
                    const Text('Just now', style: TextStyle(color: Colors.white54, fontSize: 10)),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.1, end: 0);
            }),
            
            const SizedBox(height: 12),
            const Text('VIEW ALL VOTES ⌄', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: const Text('No votes yet. Be the first to vote!', style: TextStyle(color: Colors.white54, fontSize: 13)),
              ),
            ),
          ]
        ],
      ),
    );
  }

  // Country stats removed — will be replaced with real geo-tracking
  // in a future milestone via Firebase voter metadata.

  Widget _buildRatingSection(ContestEntry entry, RankingEngine engine) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Audience Rating', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 4),
            const Text('Rate this performance to submit a official review.', style: TextStyle(fontSize: 11, color: Colors.white54)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  icon: Icon(
                    index < _userRating ? LucideIcons.star : LucideIcons.star,
                    color: index < _userRating ? Colors.amber : Colors.white24,
                    size: 36,
                  ),
                  onPressed: () {
                    setState(() => _userRating = index + 1);
                    _showReviewBottomSheet(entry, engine);
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  void _showReviewBottomSheet(ContestEntry entry, RankingEngine engine) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Write a Review', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return Icon(
                    LucideIcons.star,
                    color: index < _userRating ? Colors.amber : Colors.white24,
                    size: 28,
                  );
                }),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: TextField(
                  controller: _reviewController,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Share your feedback about this contestant...',
                    hintStyle: TextStyle(color: Colors.white30, fontSize: 13),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () async {
                    if (_reviewController.text.isNotEmpty) {
                      final success = await engine.addReview(entry.id, _userRating, _reviewController.text);
                      if (context.mounted) {
                        Navigator.pop(context);
                        _reviewController.clear();
                        if (success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Review submitted successfully!'), backgroundColor: Colors.green),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('You have already reviewed this entry!'), backgroundColor: Colors.redAccent),
                          );
                        }
                      }
                    }
                  },
                  child: const Text('Publish Review', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabbarSwitch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildTabButton('Comments', 0),
          const SizedBox(width: 16),
          _buildTabButton('Reviews', 1),
        ],
      ),
    );
  }

  Widget _buildTabButton(String title, int index) {
    final isActive = _activeTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white38,
              fontSize: 15,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 2,
            width: 24,
            color: isActive ? AppTheme.primary : Colors.transparent,
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsSection(ContestEntry entry, RankingEngine engine) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: StreamBuilder<List<CommentModel>>(
        stream: engine.getComments(entry.id),
        builder: (context, snapshot) {
          final comments = snapshot.data ?? [];

          if (comments.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('No comments yet. Start the conversation!', style: TextStyle(color: Colors.white38, fontSize: 13)),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Comments (${comments.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 16),
              ...comments.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundImage: NetworkImage(c.userAvatar),
                          radius: 16,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(c.userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                                  const SizedBox(width: 8),
                                  Text(_formatTimestamp(c.timestamp), style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(c.text, style: const TextStyle(fontSize: 13, color: Colors.white)),
                            ],
                          ),
                        ),
                        const Icon(LucideIcons.heart, size: 14, color: Colors.white54),
                      ],
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReviewsSection(ContestEntry entry, RankingEngine engine) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: StreamBuilder<List<ReviewModel>>(
        stream: engine.getReviews(entry.id),
        builder: (context, snapshot) {
          final reviews = snapshot.data ?? [];
          final avgRating = reviews.isEmpty
              ? 0.0
              : reviews.fold<double>(0, (s, r) => s + r.ratingStars) / reviews.length;

          if (reviews.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('No reviews yet. Be the first to rate!', style: TextStyle(color: Colors.white38, fontSize: 13)),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Audience Reviews (${reviews.length})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(width: 8),
                  ...List.generate(5, (i) => Icon(
                    LucideIcons.star,
                    size: 12,
                    color: i < avgRating.round() ? Colors.amber : Colors.white24,
                  )),
                  const SizedBox(width: 4),
                  Text(avgRating.toStringAsFixed(1),
                      style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              ...reviews.map((r) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151515),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundImage: NetworkImage(r.userAvatar),
                          radius: 16,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(r.userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                                  Text(_formatTimestamp(r.timestamp), style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: List.generate(5, (index) {
                                  return Icon(
                                    LucideIcons.star,
                                    color: index < r.ratingStars ? Colors.amber : Colors.white12,
                                    size: 14,
                                  );
                                }),
                              ),
                              const SizedBox(height: 8),
                              Text(r.reviewText, style: const TextStyle(fontSize: 13, color: Colors.white)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCommentInput(ContestEntry entry, RankingEngine engine) {
    final avatar = engine.currentUserProfile?.photoURL ?? 'https://i.pravatar.cc/150?u=99';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF151515),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            CircleAvatar(
              backgroundImage: NetworkImage(avatar),
              radius: 16,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: _commentController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Add a comment...',
                    hintStyle: TextStyle(color: Colors.white54, fontSize: 13),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(LucideIcons.send, color: AppTheme.primary),
              onPressed: () {
                if (_commentController.text.isNotEmpty) {
                  engine.addComment(entry.id, _commentController.text);
                  _commentController.clear();
                  FocusScope.of(context).unfocus();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumberComma(int n) {
    return n.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }
}
