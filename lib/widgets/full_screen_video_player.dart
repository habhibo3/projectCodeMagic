import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_theme.dart';
import 'video_manager.dart';

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
  VoidCallback? _controllerListener;
  int _sessionCounter = 0;

  @override
  void initState() {
    super.initState();
    // Lock to landscape on entry
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initializeVideo();
    _hideControlsTimer();
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

      // Auto-play when initialized
      _controller!.play();
      VideoManager().pauseAllExcept(widget.videoUrl);
    } catch (e) {
      debugPrint('Error initializing video: $e');
    }
  }

  void _hideControlsTimer() {
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
      setState(() {});
    } else {
      final pos = _controller!.value.position;
      final dur = _controller!.value.duration;
      if (pos >= dur - const Duration(milliseconds: 200)) {
        _controller!.seekTo(Duration.zero).then((_) {
          if (mounted) {
            _controller!.play();
            setState(() {
              _showControls = false;
              _hideControlsTimer();
            });
          }
        });
      } else {
        _controller!.play();
        setState(() {
          _showControls = false;
          _hideControlsTimer();
        });
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
        _hideControlsTimer();
      }
    });
  }

  @override
  void dispose() {
    _sessionCounter++; // Invalidate active initializations
    if (_controllerListener != null && _controller != null) {
      _controller!.removeListener(_controllerListener!);
    }
    // Release the controller back to VideoManager for proper caching and resource collection
    if (_controller != null) {
      VideoManager().releaseController(widget.videoUrl);
    }
    // Always restore portrait when leaving full-screen, regardless of how
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video player
          if (_isInitialized && _controller != null)
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),

          // Controls overlay
          if (_showControls && _isInitialized && _controller != null)
            GestureDetector(
              onTap: _toggleControls,
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: Column(
                  children: [
                    // Top bar
                    SafeArea(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(LucideIcons.chevronDown, color: Colors.white),
                              onPressed: () {
                                // dispose() handles orientation reset
                                widget.onClose?.call();
                                Navigator.pop(context);
                              },
                            ),
                            const Spacer(),
                            IconButton(
                              icon: Icon(_isMuted ? LucideIcons.volumeX : LucideIcons.volume2, color: Colors.white),
                              onPressed: _toggleMute,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Bottom controls
                    SafeArea(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Progress bar
                            VideoProgressIndicator(
                              _controller!,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: AppTheme.primary,
                                bufferedColor: Colors.white24,
                                backgroundColor: Colors.white12,
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Play/Pause and time
                            Row(
                              children: [
                                IconButton(
                                  icon: Icon(
                                    _isPlaying ? LucideIcons.pause : LucideIcons.play,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                  onPressed: _togglePlayPause,
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  _formatDuration(_controller!.value.position),
                                  style: const TextStyle(color: Colors.white),
                                ),
                                const Text(' / ', style: TextStyle(color: Colors.white70)),
                                Text(
                                  _formatDuration(_controller!.value.duration),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                const Spacer(),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Tap to show controls
          if (!_showControls)
            GestureDetector(
              onTap: _toggleControls,
              child: Container(color: Colors.transparent),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
