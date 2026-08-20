import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';
import '../models/entry.dart';
import '../theme/app_theme.dart';
import 'avatar_helper.dart';
import 'video_player_widget.dart';
import 'video_manager.dart';

/// Guess media type from a URL or file path when no explicit type is stored.
String inferMediaTypeFromUrl(String url) {
  if (url.isEmpty || url == 'processing') return 'image';
  final lower = url.toLowerCase().split('?').first;
  if (lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.avi') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.m4v') ||
      lower.contains('.mp4') ||
      lower.contains('.webm') ||
      lower.contains('recordings') ||
      lower.contains('recording') ||
      lower.contains('video')) {
    return 'video';
  }
  return 'image';
}

/// Normalize stored type and infer from URL when needed.
String resolveMediaType(String type, String contentUrl) {
  final normalized = type.toLowerCase().trim();
  if (normalized == 'video' || normalized == 'image' || normalized == 'text') {
    if (normalized == 'text') return 'text';
    if (normalized == 'video') return 'video';
    // type says image but URL is clearly video
    if (inferMediaTypeFromUrl(contentUrl) == 'video') return 'video';
    return 'image';
  }
  return inferMediaTypeFromUrl(contentUrl);
}

bool isNetworkMediaUrl(String url) =>
    url.startsWith('http://') || url.startsWith('https://') || url.startsWith('blob:');

bool isLocalMediaPath(String url) {
  if (url.isEmpty || url == 'processing') return false;
  if (isNetworkMediaUrl(url)) return false;
  if (kIsWeb) return false;
  return true;
}

/// Resolve contest cover type from stored field or URL extension.
String contestCoverType(ContestModel contest) {
  if (contest.coverType == 'video') return 'video';
  if (contest.coverType == 'image') return 'image';
  return inferMediaTypeFromUrl(contest.image);
}

/// Renders image, video, or text post content consistently across the app.
class MediaContentPreview extends StatelessWidget {
  final String type;
  final String contentUrl;
  final double height;
  final double? width;
  final bool autoPlayVideo;
  final bool videoThumbnailMode;
  final BoxFit fit;
  final String? localVideoPath;
  final VoidCallback? onVideoTap;
  final bool forceAutoPlay; // Force immediate auto-play for single video contexts

  const MediaContentPreview({
    super.key,
    required this.type,
    required this.contentUrl,
    this.height = 140,
    this.width,
    this.autoPlayVideo = false,
    this.videoThumbnailMode = false,
    this.fit = BoxFit.cover,
    this.localVideoPath,
    this.onVideoTap,
    this.forceAutoPlay = false,
  });

  bool get _isLocalUrl => isLocalMediaPath(contentUrl);

  @override
  Widget build(BuildContext context) {
    final w = width ?? double.infinity;
    final effectiveType = resolveMediaType(type, contentUrl);

    if (effectiveType == 'text') {
      return Container(
        height: height,
        width: w,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E1E22), Color(0xFF121214)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          contentUrl,
          maxLines: height <= 90 ? 3 : 5,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: height <= 90 ? 10 : 14,
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    if (effectiveType == 'video') {
      if (contentUrl == 'processing' && localVideoPath == null) {
        return Container(
          height: height,
          width: w,
          color: Colors.black,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primary,
                ),
              ),
              if (height > 60) ...[
                const SizedBox(height: 8),
                Text(
                  'Uploading...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: height <= 90 ? 9 : 11,
                  ),
                ),
              ],
            ],
          ),
        );
      }

      final videoUrl = localVideoPath ?? contentUrl;
      final isLocal = localVideoPath != null || _isLocalUrl;
      final useThumbnail = videoThumbnailMode || !autoPlayVideo;

      return SizedBox(
        height: height,
        width: w,
        child: useThumbnail
            ? VideoThumbnailPreview(
                videoUrl: videoUrl,
                isLocal: isLocal,
                height: height,
                width: w,
                fit: fit,
                onTap: onVideoTap,
              )
            : VideoPlayerWidget(
                videoUrl: videoUrl,
                isLocal: isLocal,
                autoPlay: autoPlayVideo,
                height: height,
                onTap: onVideoTap,
                forceAutoPlay: forceAutoPlay,
              ),
      );
    }

    return SizedBox(
      height: height,
      width: w,
      child: AvatarHelper.getSafePostImage(
        contentUrl,
        width: w == double.infinity ? null : w,
        height: height,
        fit: fit,
      ),
    );
  }
}

/// Loads and shows the first frame of a video — for pickers/lists where
/// [VideoPlayerWidget] visibility logic would leave a black box.
class VideoThumbnailPreview extends StatefulWidget {
  final String videoUrl;
  final bool isLocal;
  final double height;
  final double? width;
  final BoxFit fit;
  final bool showLoadingIndicator;
  final VoidCallback? onTap;

  const VideoThumbnailPreview({
    super.key,
    required this.videoUrl,
    required this.isLocal,
    required this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.showLoadingIndicator = true,
    this.onTap,
  });

  @override
  State<VideoThumbnailPreview> createState() => _VideoThumbnailPreviewState();
}

class _VideoThumbnailPreviewState extends State<VideoThumbnailPreview> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.videoUrl.isEmpty || widget.videoUrl == 'processing') {
      if (mounted) setState(() => _error = true);
      return;
    }

    try {
      final isLocal = widget.isLocal && isLocalMediaPath(widget.videoUrl);
      final controller = await VideoManager()
          .getController(widget.videoUrl, isLocal: isLocal);
      await VideoManager().initializeController(widget.videoUrl, controller);
      await controller.setLooping(false);
      await controller.pause();

      if (!mounted) {
        VideoManager().releaseController(widget.videoUrl);
        return;
      }

      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (e) {
      debugPrint('VideoThumbnailPreview failed for ${widget.videoUrl}: $e');
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    if (_controller != null) {
      VideoManager().releaseController(widget.videoUrl);
      _controller = null;
    }
    super.dispose();
  }

  Widget _buildFallback() {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2A2A2E), Color(0xFF121214)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.play, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 10),
            const Text(
              'VIDEO',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error) return _buildFallback();

    if (!_ready || _controller == null) {
      return Container(
        height: widget.height,
        width: widget.width,
        color: const Color(0xFF1A1A1A),
        child: Center(
          child: widget.showLoadingIndicator
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                )
              : Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.play, color: Colors.white, size: 30),
                ),
        ),
      );
    }

    final size = _controller!.value.size;
    final videoW = size.width > 0 ? size.width : 16.0;
    final videoH = size.height > 0 ? size.height : 9.0;

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        height: widget.height,
        width: widget.width,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: FittedBox(
                fit: widget.fit,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: videoW,
                  height: videoH,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
            Container(
              color: Colors.black.withValues(alpha: 0.15),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.play, color: Colors.white, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact badge showing media type on post cards.
class MediaTypeBadge extends StatelessWidget {
  final String type;

  const MediaTypeBadge({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    if (type == 'text') return const SizedBox.shrink();

    final isVideo = type == 'video';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVideo ? LucideIcons.video : LucideIcons.image,
            color: Colors.white,
            size: 10,
          ),
          const SizedBox(width: 3),
          Text(
            isVideo ? 'VIDEO' : 'IMAGE',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
