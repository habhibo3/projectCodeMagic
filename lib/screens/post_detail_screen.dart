import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../engine/ranking_engine.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_helper.dart';
import '../widgets/video_player_widget.dart';
import 'public_profile_screen.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _commentController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inDays >= 7) {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } else if (difference.inDays >= 1) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  void _sendComment(RankingEngine engine) async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    _commentController.clear();
    await engine.addPostComment(widget.postId, text);
    // Scroll to top of comment list
    _scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = Provider.of<RankingEngine>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09090B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'POST DETAILS',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: StreamBuilder<PostModel?>(
        stream: engine.getPostStream(widget.postId),
        builder: (context, postSnapshot) {
          if (postSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          final post = postSnapshot.data;
          if (post == null) {
            return const Center(
              child: Text(
                'Post not found or deleted.',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            );
          }

          final viewer = engine.currentUserProfile;
          final isLiked = viewer != null && post.likes.contains(viewer.uid);

          return Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    // Post Content Section
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141416),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PublicProfileScreen(userId: post.userId),
                                        ),
                                      );
                                    },
                                    child: CircleAvatar(
                                      radius: 20,
                                      backgroundImage: post.userAvatar.isNotEmpty
                                          ? AvatarHelper.getSafeAvatarProvider(post.userAvatar)
                                          : null,
                                      backgroundColor: Colors.grey.shade900,
                                      child: post.userAvatar.isEmpty
                                          ? const Icon(LucideIcons.user, size: 20, color: Colors.white60)
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        GestureDetector(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => PublicProfileScreen(userId: post.userId),
                                              ),
                                            );
                                          },
                                          child: Text(
                                            post.userName,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Text(
                                              _formatTimeAgo(post.createdAt),
                                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                                            ),
                                            const SizedBox(width: 6),
                                            const Icon(LucideIcons.dot, color: Colors.white38, size: 10),
                                            const SizedBox(width: 4),
                                            Icon(
                                              post.visibilityScope == 'global' ? LucideIcons.globe : LucideIcons.mapPin,
                                              size: 10,
                                              color: Colors.white38,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              post.visibilityScope.toUpperCase(),
                                              style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (post.contestId != null && post.contestId!.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(LucideIcons.trophy, color: AppTheme.primary, size: 11),
                                          SizedBox(width: 4),
                                          Text(
                                            'ARENA',
                                            style: TextStyle(color: AppTheme.primary, fontSize: 9, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            // Caption
                            if (post.caption.isNotEmpty && post.type != 'text')
                              Padding(
                                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                                child: Text(
                                  post.caption,
                                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                                ),
                              ),

                            // Post Media / Content
                            if (post.type == 'text')
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [const Color(0xFF1C1C1E), const Color(0xFF121214)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  post.contentUrl,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    height: 1.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            else if (post.type == 'image')
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AvatarHelper.getSafePostImage(
                                  post.contentUrl,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else if (post.type == 'video')
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: double.infinity,
                                  color: Colors.black,
                                  child: VideoPlayerWidget(
                                    videoUrl: post.contentUrl,
                                    isLocal: !post.contentUrl.startsWith('http'),
                                    autoPlay: true,
                                  ),
                                ),
                              ),

                            // Divider
                            const Divider(color: Colors.white12, height: 1),

                            // Like & Comment Stats bar
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  // Like
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => engine.toggleLikePost(post.id),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isLiked ? Icons.favorite : Icons.favorite_border,
                                          color: isLiked ? AppTheme.primary : Colors.white60,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '${post.likes.length} Likes',
                                          style: TextStyle(
                                            color: isLiked ? Colors.white : Colors.white60,
                                            fontWeight: isLiked ? FontWeight.bold : FontWeight.normal,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 24),
                                  // Comments info
                                  const Icon(LucideIcons.messageSquare, color: Colors.white60, size: 20),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${post.commentsCount} Comments',
                                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Comments Title Section
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          'COMMENTS',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),

                    // Comments Stream List
                    StreamBuilder<List<CommentModel>>(
                      stream: engine.getPostComments(widget.postId),
                      builder: (context, commentSnapshot) {
                        final comments = commentSnapshot.data ?? [];
                        if (comments.isEmpty) {
                          return const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(LucideIcons.messageCircle, color: Colors.white24, size: 36),
                                    SizedBox(height: 8),
                                    Text(
                                      'No comments yet. Start the conversation!',
                                      style: TextStyle(color: Colors.white38, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        return SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final comment = comments[i];
                              final commentUserAvatar = comment.userAvatar;
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF141416),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withOpacity(0.04)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => PublicProfileScreen(userId: comment.userId),
                                          ),
                                        );
                                      },
                                      child: CircleAvatar(
                                        radius: 16,
                                        backgroundImage: commentUserAvatar.isNotEmpty
                                            ? AvatarHelper.getSafeAvatarProvider(commentUserAvatar)
                                            : null,
                                        backgroundColor: Colors.grey.shade900,
                                        child: commentUserAvatar.isEmpty
                                            ? const Icon(LucideIcons.user, size: 16, color: Colors.white60)
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              GestureDetector(
                                                onTap: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => PublicProfileScreen(userId: comment.userId),
                                                    ),
                                                  );
                                                },
                                                child: Text(
                                                  comment.userName,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                _formatTimeAgo(comment.timestamp),
                                                style: const TextStyle(color: Colors.white38, fontSize: 10),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            comment.text,
                                            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            childCount: comments.length,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Bottom Input Bar
              Container(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 10,
                  bottom: MediaQuery.of(context).padding.bottom + 10,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF141416),
                  border: Border(top: BorderSide(color: Colors.white12)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: _commentController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Add a comment...',
                            hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _sendComment(engine),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _sendComment(engine),
                      child: const CircleAvatar(
                        radius: 20,
                        backgroundColor: AppTheme.primary,
                        child: Icon(LucideIcons.send, color: Colors.white, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
