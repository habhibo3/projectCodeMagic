import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import '../engine/ranking_engine.dart';
import '../models/post.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_helper.dart';
import 'post_detail_screen.dart';
import 'edit_post_screen.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final bool isLocal;

  const VideoPlayerWidget({super.key, required this.videoUrl, required this.isLocal});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      if (widget.isLocal) {
        _controller = VideoPlayerController.file(File(widget.videoUrl));
      } else {
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      }
      await _controller.initialize();
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('Error initializing video: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Container(
        height: 240,
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          if (_controller.value.isPlaying) {
            _controller.pause();
          } else {
            _controller.play();
          }
        });
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          ),
          if (!_controller.value.isPlaying)
            const CircleAvatar(
              radius: 28,
              backgroundColor: Colors.black54,
              child: Icon(LucideIcons.play, color: Colors.white, size: 28),
            ),
        ],
      ),
    );
  }
}

class PublicProfileScreen extends StatefulWidget {
  final String userId;

  const PublicProfileScreen({super.key, required this.userId});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
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
    if (videoUrl.startsWith('/data/user/')) {
      // Local file
      return VideoPlayerWidget(videoUrl: videoUrl, isLocal: true);
    } else {
      // Network URL
      return VideoPlayerWidget(videoUrl: videoUrl, isLocal: false);
    }
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
            GestureDetector(
              onTap: () {
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
                child: post.contentUrl.isNotEmpty
                    ? _buildVideoPlayer(post.contentUrl)
                    : const Center(
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.black54,
                          child: Icon(LucideIcons.play, color: Colors.white, size: 24),
                        ),
                      ),
              ),
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

  @override
  Widget build(BuildContext context) {
    final engine = Provider.of<RankingEngine>(context, listen: false);

    // If it's the current user, we can just show a indicator or allow visiting themselves
    final isMe = widget.userId == engine.currentUserId;

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
          'USER PROFILE',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: StreamBuilder<UserModel?>(
        stream: engine.watchUserProfile(widget.userId),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          final user = userSnapshot.data;
          if (user == null) {
            return const Center(
              child: Text(
                'User not found.',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            );
          }

          final isPremium = user.subscriptionLevel == 'premium';

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Elegent Profile Header Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: isPremium
                              ? const LinearGradient(colors: [Colors.amber, Colors.purpleAccent])
                              : LinearGradient(colors: [AppTheme.primary, Colors.blueAccent.shade400]),
                        ),
                        child: CircleAvatar(
                          radius: 46,
                          backgroundImage: user.photoURL.isNotEmpty
                              ? AvatarHelper.getSafeAvatarProvider(user.photoURL)
                              : null,
                          backgroundColor: Colors.grey.shade900,
                          child: user.photoURL.isEmpty
                              ? const Icon(LucideIcons.user, size: 40, color: Colors.white60)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${user.displayName} ${user.countryFlag}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.mapPin, color: Colors.white38, size: 13),
                          const SizedBox(width: 4),
                          Text(
                            user.location.isNotEmpty ? user.location : '${user.city}, ${user.country}',
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                      if (user.bio.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            user.bio,
                            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: isPremium
                                  ? Colors.amber.withOpacity(0.12)
                                  : AppTheme.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: isPremium
                                    ? Colors.amber.withOpacity(0.3)
                                    : AppTheme.primary.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              isPremium ? 'PREMIUM MEMBER' : user.role.toUpperCase(),
                              style: TextStyle(
                                color: isPremium ? Colors.amber : AppTheme.primary,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: const Text(
                                'YOU',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Stats Section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.checkSquare, size: 24, color: Colors.greenAccent),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'LIFETIME VOTES CAST',
                              style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${user.totalVotesCast}',
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Uploaded Posts Feed
                Text(
                  isMe ? 'MY POSTS' : '${user.displayName.toUpperCase()}\'S POSTS',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 12),

                StreamBuilder<List<PostModel>>(
                  stream: engine.getUserPosts(widget.userId),
                  builder: (context, postsSnapshot) {
                    final posts = postsSnapshot.data ?? [];
                    if (posts.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141416),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: const Column(
                          children: [
                            Icon(LucideIcons.image, color: Colors.white24, size: 36),
                            SizedBox(height: 10),
                            Text('No posts uploaded yet.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: posts.length,
                      itemBuilder: (context, index) {
                        final post = posts[index];
                        return _buildPostCard(context, post, engine);
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
