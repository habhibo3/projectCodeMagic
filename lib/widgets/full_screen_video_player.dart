import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';
import 'video_manager.dart';

// Conditional import for web video player
import 'full_screen_video_player_web.dart' if (dart.library.io) 'full_screen_video_player_stub.dart';

class FullScreenVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool isLocal;
  final VoidCallback? onClose;

  const FullScreenVideoPlayer({
    super.key,
    required this.videoUrl,
    this.isLocal = false,
    this.onClose,
  });

  @override
  State<FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<FullScreenVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isMuted = false;
  bool _isLandscapeLocked = false;
  bool _isZoomFilled = false;
  VoidCallback? _controllerListener;
  int _sessionCounter = 0;

  @override
  void initState() {
    super.initState();

    // Start in portrait, allow sensor-based rotation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Hide system UI for immersive experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Web uses the native HTML5 player below. Do not also initialize the
    // mobile file/cache based controller there.
    if (!kIsWeb) {
      _initializeVideo();
      _startHideControlsTimer();
    }
  }

  Future<void> _initializeVideo() async {
    final currentSession = ++_sessionCounter;
    try {
      final controller = await VideoManager().getController(widget.videoUrl, isLocal: widget.isLocal);

      if (currentSession != _sessionCounter) {
        VideoManager().releaseController(widget.videoUrl);
        return;
      }
      if (!mounted) {
        VideoManager().releaseController(widget.videoUrl);
        return;
      }
      _controller = controller;

      if (!_controller!.value.isInitialized) {
        await VideoManager().initializeController(widget.videoUrl, _controller!);
      }

      if (currentSession != _sessionCounter) {
        VideoManager().releaseController(widget.videoUrl);
        _controller = null;
        return;
      }
      if (!mounted) {
        VideoManager().releaseController(widget.videoUrl);
        _controller = null;
        return;
      }

      setState(() {
        _isInitialized = true;
      });

      _controllerListener = () {
        if (mounted && currentSession == _sessionCounter) {
          setState(() {
            _isPlaying = _controller!.value.isPlaying;
          });
        }
      };
      _controller!.addListener(_controllerListener!);

      // Auto-play and set volume to 1.0 when initialized
      _controller!.setVolume(1.0);
      _controller!.play();
      VideoManager().pauseAllExcept(widget.videoUrl);
    } catch (e) {
      debugPrint('Error initializing video: $e');
    }
  }

  void _startHideControlsTimer() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      setState(() {
        _showControls = true;
      });
    } else {
      final pos = _controller!.value.position;
      final dur = _controller!.value.duration;
      if (pos >= dur - const Duration(milliseconds: 200)) {
        _controller!.seekTo(Duration.zero).then((_) {
          if (mounted) {
            _controller!.play();
            _startHideControlsTimer();
          }
        });
      } else {
        _controller!.play();
        _startHideControlsTimer();
      }
    }
  }

  void _toggleMute() {
    if (_controller == null) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls && _isPlaying) {
        _startHideControlsTimer();
      }
    });
  }

  void _toggleFullscreenOrientation() {
    setState(() {
      _isLandscapeLocked = !_isLandscapeLocked;
    });
    if (_isLandscapeLocked) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _closePlayer() {
    widget.onClose?.call();
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _sessionCounter++; // Invalidate active initializations
    if (_controllerListener != null && _controller != null) {
      _controller!.removeListener(_controllerListener!);
    }
    if (_controller != null) {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      }
      VideoManager().releaseController(widget.videoUrl);
    }
    // Restore portrait orientation and system UI
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use HTML5 video player for web to avoid WebM metadata issues
    if (kIsWeb) {
      return WebVideoPlayer(
        videoUrl: widget.videoUrl,
        onClose: _closePlayer,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isInitialized && _controller != null
            ? _buildVideoPlayer()
            : _buildLoadingIndicator(),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    return OrientationBuilder(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape;
        final videoRatio = _controller!.value.aspectRatio;
        final isPortraitVideo = videoRatio < 1.0;

        BoxFit effectiveFit;
        if (_isZoomFilled) {
          effectiveFit = BoxFit.cover;
        } else if (!isLandscape) {
          effectiveFit = isPortraitVideo ? BoxFit.fitWidth : BoxFit.contain;
        } else {
          effectiveFit = BoxFit.contain;
        }

        return GestureDetector(
          onTap: _toggleControls,
          onDoubleTap: () {
            setState(() {
              _isZoomFilled = !_isZoomFilled;
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video
              Center(
                child: _controller!.value.isInitialized
                    ? SizedBox.expand(
                        child: FittedBox(
                          fit: effectiveFit,
                          child: SizedBox(
                            width: _controller!.value.size.width,
                            height: _controller!.value.size.height,
                            child: VideoPlayer(_controller!),
                          ),
                        ),
                      )
                    : const CircularProgressIndicator(color: AppTheme.primary),
              ),

              // Controls overlay
              if (_isInitialized && _controller != null)
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: Container(
                      color: Colors.black.withOpacity(0.35),
                      child: Column(
                        children: [
                          // Top bar — close button & zoom toggle
                          SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(LucideIcons.chevronDown, color: Colors.white, size: 28),
                                    onPressed: _closePlayer,
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: Icon(
                                      _isZoomFilled ? LucideIcons.minimize2 : LucideIcons.maximize2,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _isZoomFilled = !_isZoomFilled;
                                      });
                                    },
                                    tooltip: _isZoomFilled ? 'Fit to screen' : 'Fill screen',
                                  ),
                                ],
                              ),
                            ),
                          ),

                      // Center play/pause big button
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Rewind 10s
                          IconButton(
                            icon: const Icon(LucideIcons.skipBack, color: Colors.white70, size: 28),
                            onPressed: () {
                              if (_controller == null) return;
                              final pos = _controller!.value.position;
                              _controller!.seekTo(pos - const Duration(seconds: 10));
                            },
                          ),
                          const SizedBox(width: 32),
                          // Play / Pause
                          GestureDetector(
                            onTap: _togglePlayPause,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Icon(
                                _isPlaying ? LucideIcons.pause : LucideIcons.play,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ),
                          const SizedBox(width: 32),
                          // Forward 10s
                          IconButton(
                            icon: const Icon(LucideIcons.skipForward, color: Colors.white70, size: 28),
                            onPressed: () {
                              if (_controller == null) return;
                              final pos = _controller!.value.position;
                              _controller!.seekTo(pos + const Duration(seconds: 10));
                            },
                          ),
                        ],
                      ),
                      const Spacer(),

                      // Bottom controls bar
                      SafeArea(
                        top: false,
                        child: Container(
                          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Progress bar
                              SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                  activeTrackColor: AppTheme.primary,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: AppTheme.primary,
                                  overlayColor: AppTheme.primary.withOpacity(0.2),
                                ),
                                child: Slider(
                                  value: _controller!.value.duration.inMilliseconds > 0
                                      ? _controller!.value.position.inMilliseconds
                                          .clamp(0, _controller!.value.duration.inMilliseconds)
                                          .toDouble()
                                      : 0.0,
                                  min: 0.0,
                                  max: _controller!.value.duration.inMilliseconds > 0
                                      ? _controller!.value.duration.inMilliseconds.toDouble()
                                      : 1.0,
                                  onChanged: (value) {
                                    _controller!.seekTo(Duration(milliseconds: value.toInt()));
                                  },
                                ),
                              ),

                              // Bottom row: time + controls
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Row(
                                  children: [
                                    // Play/Pause small icon
                                    GestureDetector(
                                      onTap: _togglePlayPause,
                                      child: Icon(
                                        _isPlaying ? LucideIcons.pause : LucideIcons.play,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Time display
                                    Text(
                                      _formatDuration(_controller!.value.position),
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                    ),
                                    const Text(
                                      ' / ',
                                      style: TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                    Text(
                                      _formatDuration(_controller!.value.duration),
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                    const Spacer(),
                                    // Mute/Unmute
                                    GestureDetector(
                                      onTap: _toggleMute,
                                      child: Icon(
                                        _isMuted ? LucideIcons.volumeX : LucideIcons.volume2,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 20),
                                    // Fullscreen toggle (landscape lock)
                                    GestureDetector(
                                      onTap: _toggleFullscreenOrientation,
                                      child: Icon(
                                        _isLandscapeLocked ? LucideIcons.minimize : LucideIcons.maximize,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          ),
        );
      },
    );
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      child: CircularProgressIndicator(color: AppTheme.primary),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }
}
