import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../engine/ranking_engine.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_helper.dart';
import '../widgets/video_manager.dart';
import 'public_profile_screen.dart';
import 'edit_post_screen.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  VideoPlayerController? _videoController;
  String? _loadedVideoUrl;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasError = false;
  double _playbackSpeed = 1.0;
  bool _isMuted = false;
  double _volumeBeforeMute = 1.0;
  bool _showControls = true;
  Timer? _controlsTimer;
  late Stream<PostModel?> _postStream;

  // Double tap heart animation state
  bool _showHeartAnimation = false;

  @override
  void initState() {
    super.initState();
    final engine = Provider.of<RankingEngine>(context, listen: false);
    _postStream = engine.getPostStream(widget.postId);
    // Allow rotation to landscape for immersive viewing
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _startControlsTimer();
  }

  @override
  void didUpdateWidget(covariant PostDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId) {
      final engine = Provider.of<RankingEngine>(context, listen: false);
      _postStream = engine.getPostStream(widget.postId);
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    if (_videoController != null && _loadedVideoUrl != null) {
      _videoController!.removeListener(_videoListener);
      VideoManager().releaseController(_loadedVideoUrl!);
    }
    // Restore orientation lock
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _videoListener() {
    if (!mounted || _videoController == null) return;
    final playing = _videoController!.value.isPlaying;
    if (playing != _isPlaying) {
      setState(() {
        _isPlaying = playing;
      });
    }
  }

  void _initVideoController(String url) async {
    if (_loadedVideoUrl == url) return;
    final oldUrl = _loadedVideoUrl;
    _loadedVideoUrl = url;

    if (_videoController != null) {
      _videoController!.removeListener(_videoListener);
      if (oldUrl != null) {
        VideoManager().releaseController(oldUrl);
      }
      _videoController = null;
    }

    setState(() {
      _isInitialized = false;
      _hasError = false;
    });

    try {
      final isLocal = !url.startsWith('http');
      final controller = await VideoManager().getController(url, isLocal: isLocal);

      _videoController = controller;
      if (!controller.value.isInitialized) {
        await VideoManager().initializeController(url, controller);
      }

      if (!mounted || _loadedVideoUrl != url) {
        return;
      }

      controller.addListener(_videoListener);

      setState(() {
        _isInitialized = true;
        _isPlaying = controller.value.isPlaying;
      });

      controller.setLooping(true);
      controller.play();
      VideoManager().pauseAllExcept(url);
    } catch (e) {
      debugPrint("Error initializing video: $e");
      if (mounted && _loadedVideoUrl == url) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startControlsTimer();
    }
  }

  void _togglePlayPause() {
    if (_videoController == null) return;
    if (_isPlaying) {
      _videoController!.pause();
    } else {
      final pos = _videoController!.value.position;
      final dur = _videoController!.value.duration;
      if (pos >= dur - const Duration(milliseconds: 200)) {
        _videoController!.seekTo(Duration.zero).then((_) {
          if (mounted) {
            _videoController!.play();
            VideoManager().pauseAllExcept(_loadedVideoUrl);
          }
        });
      } else {
        _videoController!.play();
        VideoManager().pauseAllExcept(_loadedVideoUrl);
      }
    }
    _startControlsTimer();
  }

  void _cycleSpeed() {
    if (_videoController == null) return;
    double newSpeed;
    if (_playbackSpeed == 1.0) {
      newSpeed = 1.5;
    } else if (_playbackSpeed == 1.5) {
      newSpeed = 2.0;
    } else {
      newSpeed = 1.0;
    }
    _videoController!.setPlaybackSpeed(newSpeed);
    setState(() {
      _playbackSpeed = newSpeed;
    });
    _startControlsTimer();
  }

  void _toggleMute() {
    if (_videoController == null) return;
    if (_isMuted) {
      _videoController!.setVolume(_volumeBeforeMute);
      setState(() {
        _isMuted = false;
      });
    } else {
      _volumeBeforeMute = _videoController!.value.volume > 0 ? _videoController!.value.volume : 1.0;
      _videoController!.setVolume(0.0);
      setState(() {
        _isMuted = true;
      });
    }
    _startControlsTimer();
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

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatRemainingDuration(Duration position, Duration duration) {
    final remaining = duration - position;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '-$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _showCommentsBottomSheet(BuildContext context, RankingEngine engine) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _CommentsBottomSheet(
          postId: widget.postId,
          engine: engine,
          formatTimeAgo: _formatTimeAgo,
        );
      },
    );
  }

  void _triggerDoubleTapLike(RankingEngine engine, PostModel post) {
    final viewer = engine.currentUserProfile;
    final isLiked = viewer != null && post.likes.contains(viewer.uid);
    if (!isLiked) {
      engine.toggleLikePost(post.id);
    }
    setState(() {
      _showHeartAnimation = true;
    });
    Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showHeartAnimation = false;
        });
      }
    });
  }

  void _navigateToPost(String postId) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: postId),
      ),
    );
  }

  void _showOptionsBottomSheet(BuildContext context, PostModel post, RankingEngine engine) {
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
                      Navigator.pop(context);
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
  }

  @override
  Widget build(BuildContext context) {
    final engine = Provider.of<RankingEngine>(context, listen: false);

    return StreamBuilder<PostModel?>(
      stream: _postStream,
      builder: (context, postSnapshot) {
        if (postSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
          );
        }
        final post = postSnapshot.data;
        if (post == null) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Text(
                'Post not found or deleted.',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ),
          );
        }

        // Initialize video controller if video post type
        if (post.type == 'video' && _loadedVideoUrl != post.contentUrl) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _initVideoController(post.contentUrl);
          });
        }

        return OrientationBuilder(
          builder: (context, orientation) {
            final isLandscape = orientation == Orientation.landscape && post.type == 'video';

            if (isLandscape) {
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
            } else {
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
            }

            return Scaffold(
              backgroundColor: Colors.black,
              body: isLandscape
                  ? _buildLandscapeLayout(context, post, engine)
                  : _buildPortraitLayout(context, post, engine),
            );
          },
        );
      },
    );
  }

  Widget _buildPortraitLayout(BuildContext context, PostModel post, RankingEngine engine) {
    final isLiked = engine.currentUserProfile != null && post.likes.contains(engine.currentUserProfile!.uid);
    final handle = '@${post.userName.replaceAll(' ', '').toLowerCase()}';
    final isVerified = post.userId == 'current_user' || 
                       post.userName.contains('Ramsey') || 
                       post.userName.contains('James') ||
                       post.userName.contains('Yuki') ||
                       post.userName.contains('News');

    return Stack(
      children: [
        // 1. Media Area
        GestureDetector(
          onTap: _togglePlayPause,
          onDoubleTap: () => _triggerDoubleTapLike(engine, post),
          child: Container(
            color: Colors.black,
            width: double.infinity,
            height: double.infinity,
            child: _buildMediaContent(post),
          ),
        ),

        // Heart animation for double tap like
        if (_showHeartAnimation)
          IgnorePointer(
            child: Center(
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 300),
                tween: Tween(begin: 0.0, end: 1.2),
                curve: Curves.elasticOut,
                builder: (context, scale, child) {
                  return Transform.scale(
                    scale: scale.clamp(0.0, 1.0),
                    child: const Icon(
                      Icons.favorite,
                      color: AppTheme.primary,
                      size: 110,
                    ),
                  );
                },
              ),
            ),
          ),

        // Play/Pause brief indicator on center tap
        if (!_isPlaying && post.type == 'video' && _isInitialized && !_showHeartAnimation)
          IgnorePointer(
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(16),
                child: const Icon(LucideIcons.play, color: Colors.white, size: 36),
              ),
            ),
          ),

        // 2. Top transparent nav overlay
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black54, Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back button
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                      ),
                    ),
                    // Options button
                    GestureDetector(
                      onTap: () => _showOptionsBottomSheet(context, post, engine),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.more_horiz, color: Colors.white, size: 22),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 3. Bottom Gradient, User Details Card, and Actions row
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.6),
                  Colors.black.withOpacity(0.9),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User detail card row
                  Row(
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
                            Text(
                              handle,
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Follow Button
                      GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Followed user!'), behavior: SnackBarBehavior.floating),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white24, width: 1),
                          ),
                          child: const Text(
                            'Follow',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Post Caption
                  if (post.caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        post.caption,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                  // Timeline / progress bar for video
                  if (post.type == 'video' && _videoController != null && _isInitialized) ...[
                    _buildTimelineScrubber(false),
                    const SizedBox(height: 8),
                  ],

                  // 5 Icon Action Bar (X Style)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Comment Action
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showCommentsBottomSheet(context, engine),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.messageCircle, color: Colors.white, size: 20),
                            const SizedBox(width: 6),
                            Text(
                              '${post.commentsCount}',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      // Repost Action
                      Row(
                        children: [
                          const Icon(LucideIcons.repeat, color: Colors.white, size: 20),
                          const SizedBox(width: 6),
                          Text(
                            '${(post.likes.length * 0.4).round()}',
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                      // Like Action
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => engine.toggleLikePost(post.id),
                        child: Row(
                          children: [
                            Icon(
                              isLiked ? Icons.favorite : Icons.favorite_border,
                              color: isLiked ? AppTheme.primary : Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${post.likes.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      // Bookmark Action
                      GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Post bookmarked!'), behavior: SnackBarBehavior.floating),
                          );
                        },
                        child: const Icon(LucideIcons.bookmark, color: Colors.white, size: 20),
                      ),
                      // Share Action
                      GestureDetector(
                        onTap: () {
                          _showOptionsBottomSheet(context, post, engine);
                        },
                        child: const Icon(LucideIcons.share2, color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(BuildContext context, PostModel post, RankingEngine engine) {
    final isLiked = engine.currentUserProfile != null && post.likes.contains(engine.currentUserProfile!.uid);
    final isVerified = post.userId == 'current_user' || 
                       post.userName.contains('Ramsey') || 
                       post.userName.contains('James') ||
                       post.userName.contains('Yuki') ||
                       post.userName.contains('News');
    final handle = '@${post.userName.replaceAll(' ', '').toLowerCase()}';

    // Next/Prev Post indexing
    final currentIndex = engine.feedPosts.indexWhere((p) => p.id == post.id);
    final hasNext = currentIndex != -1 && currentIndex < engine.feedPosts.length - 1;

    return Stack(
      children: [
        // 1. Fullscreen Video Player
        GestureDetector(
          onTap: _toggleControls,
          onDoubleTap: () => _triggerDoubleTapLike(engine, post),
          child: Container(
            color: Colors.black,
            width: double.infinity,
            height: double.infinity,
            child: _videoController != null && _isInitialized
                ? Center(
                    child: AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    ),
                  )
                : const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
          ),
        ),

        // Heart animation for double tap like in landscape
        if (_showHeartAnimation)
          IgnorePointer(
            child: Center(
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 300),
                tween: Tween(begin: 0.0, end: 1.2),
                curve: Curves.elasticOut,
                builder: (context, scale, child) {
                  return Transform.scale(
                    scale: scale.clamp(0.0, 1.0),
                    child: const Icon(
                      Icons.favorite,
                      color: AppTheme.primary,
                      size: 110,
                    ),
                  );
                },
              ),
            ),
          ),

        // Play/Pause center overlay indicator
        if (!_isPlaying && _isInitialized && !_showHeartAnimation)
          Center(
            child: GestureDetector(
              onTap: _togglePlayPause,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(16),
                child: const Icon(LucideIcons.play, color: Colors.white, size: 36),
              ),
            ),
          ),

        // Swiping/Swipe next/prev navigation chevrons
        if (_showControls) ...[
          if (hasNext)
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => _navigateToPost(engine.feedPosts[currentIndex + 1].id),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.chevronRight, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ),
        ],

        // 2. Control overlays (shows when toggled)
        if (_showControls) ...[
          // Top overlay bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black54, Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  // Speed setting toggle
                  TextButton(
                    onPressed: _cycleSpeed,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.black45,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: Text(
                      '${_playbackSpeed}x',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Volume mute toggle
                  IconButton(
                    icon: Icon(
                      _isMuted ? LucideIcons.volumeX : LucideIcons.volume2,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: _toggleMute,
                  ),
                  const SizedBox(width: 8),
                  // Double rectangles (PIP mode mock)
                  IconButton(
                    icon: const Icon(LucideIcons.copy, color: Colors.white, size: 20),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Picture in Picture activated'), behavior: SnackBarBehavior.floating),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  // Options menu
                  IconButton(
                    icon: const Icon(Icons.more_horiz, color: Colors.white, size: 24),
                    onPressed: () => _showOptionsBottomSheet(context, post, engine),
                  ),
                ],
              ),
            ),
          ),

          // User details and Floating Actions overlay card at the lower left and right
          Positioned(
            bottom: 60,
            left: 24,
            right: 24,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // User Details & Subtitle (Left side)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundImage: post.userAvatar.isNotEmpty
                                  ? AvatarHelper.getSafeAvatarProvider(post.userAvatar)
                                  : null,
                              backgroundColor: Colors.grey.shade900,
                              child: post.userAvatar.isEmpty
                                  ? const Icon(LucideIcons.user, size: 16, color: Colors.white60)
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      post.userName,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isVerified) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.verified, color: Colors.blueAccent, size: 12),
                                  ],
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      handle,
                                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Followed user!'), behavior: SnackBarBehavior.floating),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: const Text(
                                  'Follow',
                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (post.caption.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            post.caption,
                            style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),

                // Floating Action pill (Right side)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLandscapeHorizontalButton(
                        icon: LucideIcons.messageCircle,
                        label: '${post.commentsCount}',
                        onTap: () => _showCommentsBottomSheet(context, engine),
                      ),
                      const SizedBox(width: 16),
                      _buildLandscapeHorizontalButton(
                        icon: LucideIcons.repeat,
                        label: '${(post.likes.length * 0.4).round()}',
                        onTap: () {},
                      ),
                      const SizedBox(width: 16),
                      _buildLandscapeHorizontalButton(
                        icon: isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? AppTheme.primary : Colors.white,
                        label: '${post.likes.length}',
                        onTap: () => engine.toggleLikePost(post.id),
                      ),
                      const SizedBox(width: 16),
                      _buildLandscapeHorizontalButton(
                        icon: LucideIcons.bookmark,
                        label: '',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Post bookmarked!'), behavior: SnackBarBehavior.floating),
                          );
                        },
                      ),
                      const SizedBox(width: 16),
                      _buildLandscapeHorizontalButton(
                        icon: LucideIcons.share2,
                        label: '',
                        onTap: () => _showOptionsBottomSheet(context, post, engine),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom overlay progress scrubber bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black87],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _isPlaying ? LucideIcons.pause : LucideIcons.play,
                        color: Colors.white,
                        size: 26,
                      ),
                      onPressed: _togglePlayPause,
                    ),
                    if (post.userAvatar.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      CircleAvatar(
                        radius: 12,
                        backgroundImage: AvatarHelper.getSafeAvatarProvider(post.userAvatar),
                      ),
                    ],
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTimelineScrubber(true),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMediaContent(PostModel post) {
    if (post.type == 'image') {
      return Center(
        child: AvatarHelper.getSafePostImage(
          post.contentUrl,
          width: double.infinity,
          fit: BoxFit.contain,
        ),
      );
    } else if (post.type == 'video') {
      if (_hasError) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.alertTriangle, color: Colors.white38, size: 28),
              SizedBox(height: 8),
              Text(
                'Unable to load video',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        );
      } else if (_videoController != null && _isInitialized) {
        return Center(
          child: AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          ),
        );
      } else {
        return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        );
      }
    }

    return const Center(
      child: Text(
        'Unknown post type',
        style: TextStyle(color: Colors.white),
      ),
    );
  }

  Widget _buildTimelineScrubber(bool isLandscape) {
    if (_videoController == null) return const SizedBox.shrink();
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _videoController!,
      builder: (context, value, _) {
        final position = value.position;
        final duration = value.duration;
        final progress = duration.inMilliseconds > 0
            ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;

        return Row(
          children: [
            Text(
              _formatDuration(position),
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: AppTheme.primary,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: AppTheme.primary,
                ),
                child: Slider(
                  value: progress,
                  onChanged: (val) {
                    final targetMs = (val * duration.inMilliseconds).toInt();
                    _videoController!.seekTo(Duration(milliseconds: targetMs));
                  },
                ),
              ),
            ),
            Text(
              isLandscape 
                  ? _formatRemainingDuration(position, duration)
                  : _formatDuration(duration),
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLandscapeHorizontalButton({
    required IconData icon,
    Color color = Colors.white,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentsBottomSheet extends StatefulWidget {
  final String postId;
  final RankingEngine engine;
  final String Function(DateTime) formatTimeAgo;

  const _CommentsBottomSheet({
    required this.postId,
    required this.engine,
    required this.formatTimeAgo,
  });

  @override
  State<_CommentsBottomSheet> createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends State<_CommentsBottomSheet> {
  final _commentController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    _commentController.clear();
    await widget.engine.addPostComment(widget.postId, text);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF141416),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Comments',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // Comments List
          Expanded(
            child: StreamBuilder<List<CommentModel>>(
              stream: widget.engine.getPostComments(widget.postId),
              builder: (context, commentSnapshot) {
                final comments = commentSnapshot.data ?? [];
                if (comments.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.messageCircle, color: Colors.white24, size: 36),
                        SizedBox(height: 8),
                        Text(
                          'No comments yet. Be the first to comment!',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: comments.length,
                  itemBuilder: (context, i) {
                    final comment = comments[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundImage: comment.userAvatar.isNotEmpty
                                ? AvatarHelper.getSafeAvatarProvider(comment.userAvatar)
                                : null,
                            backgroundColor: Colors.grey.shade900,
                            child: comment.userAvatar.isEmpty
                                ? const Icon(LucideIcons.user, size: 16, color: Colors.white60)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      comment.userName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      widget.formatTimeAgo(comment.timestamp),
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
                );
              },
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // Send comment input field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF141416),
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
                      onSubmitted: (_) => _sendComment(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendComment,
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
      ),
    );
  }
}
