import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../engine/ranking_engine.dart';
import '../models/post.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_helper.dart';
import '../widgets/video_player_widget.dart';
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

  @override
  Widget build(BuildContext context) {
    final engine = Provider.of<RankingEngine>(context, listen: false);

    // Automatically trigger initial load if feed is empty
    if (engine.feedPosts.isEmpty && !engine.isLoadingFeed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        engine.refreshFeed();
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09090B),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'MLIVECAST',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreatePostScreen()),
              );
            },
          ),
        ],
      ),
      body: Consumer<RankingEngine>(
        builder: (context, currentEngine, child) {
          final posts = currentEngine.feedPosts;

          if (posts.isEmpty && currentEngine.isLoadingFeed) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          }

          if (posts.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => currentEngine.refreshFeed(),
              color: AppTheme.primary,
              child: const Center(
                child: SingleChildScrollView(
                  physics: AlwaysScrollableScrollPhysics(),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.rss, color: Colors.white38, size: 48),
                      SizedBox(height: 16),
                      Text(
                        'No posts yet. Pull to refresh!',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => currentEngine.refreshFeed(),
            color: AppTheme.primary,
            child: ListView.builder(
              controller: _scrollController,
              itemCount: posts.length + (currentEngine.hasMoreFeed ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == posts.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    ),
                  );
                }
                return _buildPostCard(context, posts[index], currentEngine);
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primary,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreatePostScreen()),
          );
        },
        child: const Icon(LucideIcons.plus, color: Colors.white),
      ),
    );
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

  Widget _buildVideoPlayer(String videoUrl, PostModel post) {
    final isLocal = !videoUrl.startsWith('http');
    return VideoPlayerWidget(
      videoUrl: videoUrl,
      isLocal: isLocal,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(postId: post.id),
          ),
        );
      },
    );
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

  Widget _buildPostCard(BuildContext context, PostModel post, RankingEngine engine) {
    final viewer = engine.currentUserProfile;
    final isLiked = viewer != null && post.likes.contains(viewer.uid);
    final handle = '@${post.userName.replaceAll(' ', '').toLowerCase()}';
    
    // Gordon Ramsey (Judge) or specific mock users get a verified badge
    final isVerified = post.userId == 'current_user' || 
                       post.userName.contains('Ramsey') || 
                       post.userName.contains('James') ||
                       post.userName.contains('Yuki') ||
                       post.userName.contains('News');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left side - User Avatar
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
                  radius: 22,
                  backgroundImage: post.userAvatar.isNotEmpty
                      ? AvatarHelper.getSafeAvatarProvider(post.userAvatar)
                      : null,
                  backgroundColor: Colors.grey.shade900,
                  child: post.userAvatar.isEmpty
                      ? const Icon(LucideIcons.user, size: 22, color: Colors.white60)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              
              // Right side - Username, Handle, Timestamp, Caption, Media, Actions
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top user details bar
                    Row(
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PublicProfileScreen(userId: post.userId),
                                ),
                              );
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    post.userName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified, color: Colors.blueAccent, size: 14),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            handle,
                            style: const TextStyle(color: Colors.white38, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Text(
                          ' · ',
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                        Text(
                          _formatTimeAgo(post.createdAt),
                          style: const TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
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
                          child: const Icon(LucideIcons.moreHorizontal, color: Colors.white38, size: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    
                    // Post Description Caption text
                    if (post.caption.isNotEmpty && post.type != 'text')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          post.caption,
                          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                        ),
                      ),
                      
                    // Post Media / Content Card
                    if (post.type == 'text')
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [const Color(0xFF1C1C1E), const Color(0xFF121214)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
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
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: AvatarHelper.getSafePostImage(
                              post.contentUrl,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
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
                              if (isProcessing && localPath == null) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PostDetailScreen(postId: post.id),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                width: double.infinity,
                                height: 240,
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: isProcessing
                                    ? (localPath != null
                                        ? Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              _buildVideoPlayer(localPath, post),
                                              _buildUploadOverlay(progress),
                                            ],
                                          )
                                        : _buildProcessingIndicator(post.userId))
                                    : post.contentUrl.isNotEmpty
                                        ? _buildVideoPlayer(post.contentUrl, post)
                                        : const Center(
                                            child: CircleAvatar(
                                              radius: 24,
                                              backgroundColor: Colors.black54,
                                              child: Icon(LucideIcons.play, color: Colors.white, size: 24),
                                            ),
                                          ),
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 12),
                    
                    // Social Action Row (X Style)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
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
                          child: Row(
                            children: [
                              const Icon(LucideIcons.messageCircle, color: Colors.white38, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '${post.commentsCount}',
                                style: const TextStyle(color: Colors.white38, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        // Repost
                        Row(
                          children: [
                            const Icon(LucideIcons.repeat, color: Colors.white38, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${(post.likes.length * 0.4).round()}',
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),
                        // Like
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => engine.toggleLikePost(post.id),
                          child: Row(
                            children: [
                              Icon(
                                isLiked ? Icons.favorite : Icons.favorite_border,
                                color: isLiked ? AppTheme.primary : Colors.white38,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${post.likes.length}',
                                style: TextStyle(
                                  color: isLiked ? Colors.white : Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Views (Mock)
                        Row(
                          children: [
                            const Icon(LucideIcons.barChart2, color: Colors.white38, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${(post.likes.length * 12 + 45)}K',
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),
                        // Bookmark
                        const Icon(LucideIcons.bookmark, color: Colors.white38, size: 16),
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
                          child: const Icon(LucideIcons.share2, color: Colors.white38, size: 16),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),
        ],
      ),
    );
  }
}
