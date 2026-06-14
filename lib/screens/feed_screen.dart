import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../engine/ranking_engine.dart';
import '../models/post.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_helper.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/video_manager.dart';
import 'post_detail_screen.dart';
import 'public_profile_screen.dart';
import 'edit_post_screen.dart';
import 'create_post_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      Provider.of<RankingEngine>(context, listen: false).fetchNextFeedPage();
    }
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

  Widget _buildVideoPlayer(String videoUrl) {
    final isLocal = !videoUrl.startsWith('http');
    return VideoPlayerWidget(videoUrl: videoUrl, isLocal: isLocal);
  }

  Widget _buildProcessingIndicator(String postUserId) {
    final isOwner = postUserId == Provider.of<RankingEngine>(context, listen: false).currentUserId;
    if (!isOwner) {
      return const SizedBox.shrink(); // Hide from other users
    }
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 12),
            Text(
              'Video processing...',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadOverlay(double progress) {
    return Container(
      color: Colors.black.withOpacity(0.4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 4,
                      color: AppTheme.primary,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Uploading video...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09090B),
        elevation: 0,
        title: const Text(
          'FEED',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: Consumer<RankingEngine>(
        builder: (context, rankingEngine, _) {
          final posts = rankingEngine.feedPosts.where((p) {
            return !(p.contentUrl == 'processing' && p.userId != rankingEngine.currentUserId);
          }).toList();

          if (posts.isEmpty && rankingEngine.isLoadingFeed) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }

          // Pre-cache top 5 video posts in background to speed up loading
          int preCacheCount = 0;
          for (final post in posts) {
            if (post.type == 'video' && post.contentUrl.isNotEmpty && post.contentUrl != 'processing') {
              VideoManager().preCacheVideo(post.contentUrl);
              preCacheCount++;
              if (preCacheCount >= 5) break;
            }
          }

          if (posts.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => rankingEngine.refreshFeed(),
              color: AppTheme.primary,
              backgroundColor: const Color(0xFF141416),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                  const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.newspaper, color: Colors.white24, size: 48),
                        SizedBox(height: 12),
                        Text(
                          'No posts yet. Be the first to share!',
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => rankingEngine.refreshFeed(),
            color: AppTheme.primary,
            backgroundColor: const Color(0xFF141416),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: posts.length + (rankingEngine.hasMoreFeed ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == posts.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    ),
                  );
                }
                final post = posts[index];
                return _buildPostCard(context, post, rankingEngine);
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(LucideIcons.plus, size: 24),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreatePostScreen()),
          );
        },
      ),
    );
  }

  Widget _buildPostCard(BuildContext context, PostModel post, RankingEngine engine) {
    final viewer = engine.currentUserProfile;
    final isLiked = viewer != null && post.likes.contains(viewer.uid);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
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
                    radius: 18,
                    backgroundImage: post.userAvatar.isNotEmpty
                        ? AvatarHelper.getSafeAvatarProvider(post.userAvatar)
                        : null,
                    backgroundColor: Colors.grey.shade900,
                    child: post.userAvatar.isEmpty
                        ? const Icon(LucideIcons.user, size: 18, color: Colors.white60)
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
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
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            _formatTimeAgo(post.createdAt),
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                          ),
                          const SizedBox(width: 4),
                          const Icon(LucideIcons.dot, color: Colors.white38, size: 8),
                          const SizedBox(width: 4),
                          const Icon(LucideIcons.mapPin, size: 8, color: Colors.white38),
                          const SizedBox(width: 2),
                          Text(
                            post.location.isNotEmpty ? post.location : 'Unknown',
                            style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.moreHorizontal, color: Colors.white38, size: 16),
                  onPressed: () {
                    final isOwner = post.userId == engine.currentUserId;
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: const Color(0xFF141416),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (context) => Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isOwner) ...[
                              ListTile(
                                leading: const Icon(LucideIcons.pencil, color: Colors.white),
                                title: const Text('Edit post', style: TextStyle(color: Colors.white)),
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EditPostScreen(post: post),
                                    ),
                                  );
                                },
                              ),
                              ListTile(
                                leading: const Icon(LucideIcons.trash2, color: Colors.red),
                                title: const Text('Delete post', style: TextStyle(color: Colors.red)),
                                onTap: () async {
                                  Navigator.pop(context);
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      backgroundColor: const Color(0xFF141416),
                                      title: const Text('Delete Post', style: TextStyle(color: Colors.white)),
                                      content: const Text('Are you sure you want to delete this post?', style: TextStyle(color: Colors.white70)),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    await engine.deletePost(post.id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Post deleted'), behavior: SnackBarBehavior.floating, backgroundColor: Colors.green),
                                      );
                                    }
                                  }
                                },
                              ),
                              const Divider(color: Colors.white12),
                            ],
                            ListTile(
                              leading: const Icon(LucideIcons.bookmark, color: Colors.white),
                              title: const Text('Save post', style: TextStyle(color: Colors.white)),
                              onTap: () {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Post saved!'), behavior: SnackBarBehavior.floating),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(LucideIcons.flag, color: Colors.white),
                              title: const Text('Report post', style: TextStyle(color: Colors.white)),
                              onTap: () {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Post reported'), behavior: SnackBarBehavior.floating),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(LucideIcons.link, color: Colors.white),
                              title: const Text('Copy link', style: TextStyle(color: Colors.white)),
                              onTap: () {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Link copied to clipboard!'), behavior: SnackBarBehavior.floating),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Caption
          if (post.caption.isNotEmpty && post.type != 'text')
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
              child: Text(
                post.caption,
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
              ),
            ),

          // Post Media / Content
          if (post.type == 'text')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              margin: const EdgeInsets.symmetric(horizontal: 12),
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
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            )
          else if (post.type == 'image')
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PostDetailScreen(postId: post.id),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(0),
                child: AvatarHelper.getSafePostImage(
                  post.contentUrl,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            )
          else if (post.type == 'video')
            Consumer<RankingEngine>(
              builder: (context, currentEngine, _) {
                final localPath = currentEngine.localVideoPaths[post.id];
                final progress = currentEngine.uploadProgressMap[post.id] ?? 0.0;
                final isProcessing = post.contentUrl == 'processing';

                return GestureDetector(
                  onTap: () {
                    if (isProcessing && localPath == null) return; // Don't navigate if processing and no local path
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PostDetailScreen(postId: post.id),
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    height: 240,
                    color: Colors.black,
                    child: isProcessing
                        ? (localPath != null
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  _buildVideoPlayer(localPath),
                                  _buildUploadOverlay(progress),
                                ],
                              )
                            : _buildProcessingIndicator(post.userId))
                        : post.contentUrl.isNotEmpty
                            ? _buildVideoPlayer(post.contentUrl)
                            : const Center(
                                child: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Colors.black54,
                                  child: Icon(LucideIcons.play, color: Colors.white, size: 24),
                                ),
                              ),
                  ),
                );
              },
            ),

          // Like & Comment Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Like
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => engine.toggleLikePost(post.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          color: isLiked ? AppTheme.primary : Colors.white60,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${post.likes.length}',
                          style: TextStyle(
                            color: isLiked ? Colors.white : Colors.white60,
                            fontWeight: isLiked ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Comment
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PostDetailScreen(postId: post.id),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.messageCircle, color: Colors.white60, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          '${post.commentsCount}',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                // Share
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: const Color(0xFF141416),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (context) => Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(LucideIcons.share2, color: Colors.white),
                              title: const Text('Share to...', style: TextStyle(color: Colors.white)),
                              onTap: () {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Share menu opened'), behavior: SnackBarBehavior.floating),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(LucideIcons.messageCircle, color: Colors.white),
                              title: const Text('Send in message', style: TextStyle(color: Colors.white)),
                              onTap: () {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Message feature coming soon'), behavior: SnackBarBehavior.floating),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(LucideIcons.copy, color: Colors.white),
                              title: const Text('Copy post', style: TextStyle(color: Colors.white)),
                              onTap: () {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Post copied to clipboard'), behavior: SnackBarBehavior.floating),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Icon(LucideIcons.share2, color: Colors.white60, size: 18),
                  ),
                ),
              ],
            ),
          ),

          // Divider
          const Divider(color: Colors.white12, height: 1),
        ],
      ),
    );
  }
}
