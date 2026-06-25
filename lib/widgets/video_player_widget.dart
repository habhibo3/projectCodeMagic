import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../theme/app_theme.dart';
import 'video_manager.dart';
import 'full_screen_video_player.dart';

/// Shared video player widget used across the entire app.
/// Supports auto-play on scroll-into-view, auto-pause on scroll-out,
/// dynamic lazy-loading/releasing of controller based on visibility to prevent OOM.
class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final bool isLocal;
  final bool autoPlay;
  final String? thumbnailUrl;
  final VoidCallback? onTap;

  const VideoPlayerWidget({
    super.key,
    required this.videoUrl,
    required this.isLocal,
    this.autoPlay = true, // Default to true for auto-play in feeds
    this.thumbnailUrl,
    this.onTap,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isVisible = false;
  bool _hasError = false;
  VoidCallback? _controllerListener;
  int _sessionCounter = 0;
  ModalRoute<dynamic>? _route;
  bool _isInitializing = false;
  double _lastVisibleFraction = 0.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final isCurrent = _route?.isCurrent ?? true;
    if (!isCurrent) {
      VideoManager().removeVisibleFraction(widget.videoUrl);
      _deinitializeVideo();
    } else {
      if (_isVisible) {
        VideoManager().setVisibleFraction(widget.videoUrl, _lastVisibleFraction);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // Reduce visibility detector update interval for instant FB-style pausing
    VisibilityDetectorController.instance.updateInterval =
        const Duration(milliseconds: 50);
    VideoManager().activeVideoUrl.addListener(_onActiveVideoChanged);
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      if (VideoManager().activeVideoUrl.value == oldWidget.videoUrl) {
        VideoManager().activeVideoUrl.value = null;
      }
      _deinitializeVideo();
      if (_isVisible) {
        if (_lastVisibleFraction > 0.5) {
          VideoManager().activeVideoUrl.value = widget.videoUrl;
        } else if (VideoManager().activeVideoUrl.value == null) {
          VideoManager().activeVideoUrl.value = widget.videoUrl;
        }
      }
    }
  }

  void _onActiveVideoChanged() {
    if (!mounted) return;
    final activeUrl = VideoManager().activeVideoUrl.value;
    final isActive = activeUrl == widget.videoUrl;

    if (_isVisible) {
      if (_isInitialized && _controller != null) {
        if (isActive && widget.autoPlay) {
          _controller!.play();
          VideoManager().pauseAllExcept(widget.videoUrl);
        } else {
          _controller!.pause();
        }
      } else {
        _initializeVideo();
      }
    } else {
      _deinitializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;

    final currentSession = ++_sessionCounter;

    try {
      final controller = await VideoManager()
          .getController(widget.videoUrl, isLocal: widget.isLocal);
      
      if (currentSession != _sessionCounter) {
        VideoManager().releaseController(widget.videoUrl);
        return;
      }

      if (!mounted || !_isVisible) {
        // Scrolled out of view or disposed during fetch; release resources immediately
        VideoManager().releaseController(widget.videoUrl);
        return;
      }
      
      _controller = controller;

      if (!controller.value.isInitialized) {
        await VideoManager().initializeController(widget.videoUrl, controller);
      }

      if (currentSession != _sessionCounter) {
        _releaseControllerOnly();
        return;
      }

      if (!mounted || !_isVisible) {
        // Scrolled out of view or disposed during initialization; release resources immediately
        _releaseControllerOnly();
        return;
      }

      _controllerListener = () {
        if (mounted && currentSession == _sessionCounter) {
          final playing = controller.value.isPlaying;
          if (playing != _isPlaying) {
            setState(() {
              _isPlaying = playing;
            });
          }
        }
      };
      controller.addListener(_controllerListener!);

      setState(() {
        _isInitialized = true;
        _hasError = false;
      });

      controller.setLooping(true);

      final activeUrl = VideoManager().activeVideoUrl.value;
      final isActive = activeUrl == widget.videoUrl;
      if (widget.autoPlay && _isVisible && isActive) {
        controller.play();
        VideoManager().pauseAllExcept(widget.videoUrl);
      } else {
        controller.pause();
      }
    } catch (e) {
      if (mounted && currentSession == _sessionCounter) {
        setState(() {
          _hasError = true;
        });
      }
    } finally {
      _isInitializing = false;
    }
  }

  void _deinitializeVideo() {
    _sessionCounter++; // Invalidate any active initializations
    _isInitializing = false;
    if (_controller == null) return;

    if (_controllerListener != null) {
      _controller!.removeListener(_controllerListener!);
      _controllerListener = null;
    }

    // Release controller back to VideoManager's cache to free up decoding cycles and prevent crash
    _controller?.pause();
    _releaseControllerOnly();

    if (mounted) {
      setState(() {
        _isInitialized = false;
        _isPlaying = false;
      });
    }
  }

  void _releaseControllerOnly() {
    if (_controller != null) {
      VideoManager().releaseController(widget.videoUrl);
      _controller = null;
    }
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (!mounted) return;
    _lastVisibleFraction = info.visibleFraction;
    final visible = _lastVisibleFraction > 0.15;

    final isCurrent = _route?.isCurrent ?? true;
    if (isCurrent) {
      VideoManager().setVisibleFraction(widget.videoUrl, _lastVisibleFraction);
    } else {
      VideoManager().removeVisibleFraction(widget.videoUrl);
    }

    if (visible == _isVisible) {
      return;
    }

    _isVisible = visible;

    if (!isCurrent) {
      _deinitializeVideo();
      return;
    }

    if (visible) {
      _initializeVideo();
    } else {
      _deinitializeVideo();
    }
  }

  @override
  void dispose() {
    _sessionCounter++; // Invalidate active initializations
    _isVisible = false;
    VideoManager().removeVisibleFraction(widget.videoUrl);
    VideoManager().activeVideoUrl.removeListener(_onActiveVideoChanged);
    if (_controllerListener != null && _controller != null) {
      _controller!.removeListener(_controllerListener!);
    }
    _releaseControllerOnly();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        height: 240,
        color: Colors.black,
        child: const Center(
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
        ),
      );
    }

    return VisibilityDetector(
      key: Key('vpw_${widget.videoUrl}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: ValueListenableBuilder<String?>(
        valueListenable: VideoManager().activeVideoUrl,
        builder: (context, activeUrl, _) {
          final isActive = activeUrl == widget.videoUrl;
          final showLoader = _isVisible && isActive && (!_isInitialized || _isInitializing);

          return Container(
            height: 240,
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Render the thumbnail/placeholder only if explicitly provided
                if ((_controller == null || !_isInitialized || showLoader) && widget.thumbnailUrl != null)
                  Image.network(
                    widget.thumbnailUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: Colors.black),
                  ),
                
                // Show loader or video controller or play overlay
                if (showLoader)
                  Container(
                    color: Colors.black38,
                    child: const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    ),
                  )
                else if (_controller != null && _isInitialized)
                  GestureDetector(
                    onTap: () {
                      if (widget.onTap != null) {
                        widget.onTap!();
                        return;
                      }
                      if (VideoManager().activeVideoUrl.value != widget.videoUrl) {
                        VideoManager().activeVideoUrl.value = widget.videoUrl;
                        return;
                      }
                      
                      // Pause before navigating to full-screen
                      _controller?.pause();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FullScreenVideoPlayer(
                            videoUrl: widget.videoUrl,
                            isLocal: widget.isLocal,
                          ),
                        ),
                      ).then((_) {
                        // When returning from full-screen, re-evaluate visibility
                        if (mounted && _isVisible && _isInitialized) {
                          if (widget.autoPlay) {
                            _controller?.play();
                            VideoManager().pauseAllExcept(widget.videoUrl);
                          }
                        }
                      });
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: AspectRatio(
                            aspectRatio: _controller!.value.aspectRatio > 0
                                ? _controller!.value.aspectRatio
                                : 16 / 9,
                            child: VideoPlayer(_controller!),
                          ),
                        ),
                        // Play button overlay when paused
                        if (!_isPlaying)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(14),
                            child: const Icon(LucideIcons.play,
                                color: Colors.white, size: 28),
                          ),
                      ],
                    ),
                  )
                else
                  GestureDetector(
                    onTap: widget.onTap ?? () {
                      VideoManager().activeVideoUrl.value = widget.videoUrl;
                    },
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.25),
                      alignment: Alignment.center,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(14),
                        child: const Icon(LucideIcons.play,
                            color: Colors.white, size: 28),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
