import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class _CachedController {
  final VideoPlayerController controller;
  int refCount;

  _CachedController({required this.controller, this.refCount = 1});
}

/// Global video manager to handle video lifecycle across the app,
/// featuring reference-counting and an LRU cache for inactive controllers
/// to prevent OutOfMemory (OOM) errors and codec starvation.
class VideoManager {
  static final VideoManager _instance = VideoManager._internal();
  factory VideoManager() => _instance;
  VideoManager._internal();

  // Active controllers currently being used by at least one widget
  final Map<String, _CachedController> _activeControllers = {};

  // Single source of truth for the active video URL to prevent concurrent controller/codec allocation
  final ValueNotifier<String?> activeVideoUrl = ValueNotifier<String?>(null);

  // Inactive controllers queue (LRU)
  final List<String> _inactiveKeys = [];
  final Map<String, VideoPlayerController> _inactiveControllers = {};

  // Map to track ongoing initialization futures to avoid duplicate calls on the same controller instance
  final Map<VideoPlayerController, Future<void>> _initializationFutures = {};

  // Map to track ongoing getController futures to avoid duplicate parallel requests
  final Map<String, Future<VideoPlayerController>> _getControllerFutures = {};

  // Track ongoing pre-cache download tasks to avoid duplicate parallel downloads
  final Set<String> _preCachingUrls = {};

  // Map to store resolved local file paths of cached remote videos for O(1) instant synchronous check
  final Map<String, String> _cachedFilePaths = {};

  // Cache limit for inactive controllers (keep at most 0 in memory to immediately release hardware codecs)
  static const int _maxInactiveCacheSize = 0;

  String? _currentPlayingVideo;

  // Track visible fraction of each video in feeds to auto-play the one with highest visibility percentage
  final Map<String, double> _visibleFractions = {};

  void setVisibleFraction(String url, double fraction) {
    if (fraction <= 0.05) {
      _visibleFractions.remove(url);
    } else {
      _visibleFractions[url] = fraction;
    }
    _updateActiveVideoFromFractions();
  }

  void removeVisibleFraction(String url) {
    _visibleFractions.remove(url);
    _updateActiveVideoFromFractions();
  }

  void _updateActiveVideoFromFractions() {
    if (_visibleFractions.isEmpty) {
      if (activeVideoUrl.value != null) {
        activeVideoUrl.value = null;
      }
      return;
    }

    String? maxUrl;
    double maxFraction = -1.0;

    _visibleFractions.forEach((url, fraction) {
      if (fraction > maxFraction) {
        maxFraction = fraction;
        maxUrl = url;
      }
    });

    if (maxUrl != null && maxFraction > 0.15) {
      if (activeVideoUrl.value != maxUrl) {
        activeVideoUrl.value = maxUrl;
      }
    } else {
      if (activeVideoUrl.value != null) {
        activeVideoUrl.value = null;
      }
    }
  }

  void _printStats() {
    debugPrint('=== VIDEOMANAGER STATS ===');
    debugPrint('Active controllers count: ${_activeControllers.length}');
    _activeControllers.forEach((url, cached) {
      debugPrint('  - Active: $url (refCount: ${cached.refCount}, initialized: ${cached.controller.value.isInitialized}, hasError: ${cached.controller.value.hasError})');
    });
    debugPrint('Inactive controllers count: ${_inactiveControllers.length}');
    _inactiveControllers.forEach((url, controller) {
      debugPrint('  - Inactive: $url (initialized: ${controller.value.isInitialized}, hasError: ${controller.value.hasError})');
    });
    debugPrint('Ongoing getController futures: ${_getControllerFutures.keys.join(', ')}');
    debugPrint('==========================');
  }

  /// Get or create a video controller for the given URL
  Future<VideoPlayerController> getController(String videoUrl, {bool isLocal = false}) async {
    debugPrint('VideoManager.getController: url=$videoUrl, isLocal=$isLocal');

    // Case 1: Already active
    if (_activeControllers.containsKey(videoUrl)) {
      _activeControllers[videoUrl]!.refCount++;
      debugPrint('VideoManager.getController: url=$videoUrl already active. refCount=${_activeControllers[videoUrl]!.refCount}');
      _printStats();
      return _activeControllers[videoUrl]!.controller;
    }

    // Case 2: In inactive cache
    if (_inactiveControllers.containsKey(videoUrl)) {
      final controller = _inactiveControllers.remove(videoUrl)!;
      _inactiveKeys.remove(videoUrl);
      _activeControllers[videoUrl] = _CachedController(controller: controller, refCount: 1);
      debugPrint('VideoManager.getController: url=$videoUrl moved from inactive to active. refCount=1');
      _printStats();
      return controller;
    }

    // Case 3: Ongoing future check (deduplicate concurrent requests)
    if (_getControllerFutures.containsKey(videoUrl)) {
      debugPrint('VideoManager.getController: url=$videoUrl has ongoing future. Awaiting...');
      await _getControllerFutures[videoUrl];
      if (_activeControllers.containsKey(videoUrl)) {
        _activeControllers[videoUrl]!.refCount++;
        debugPrint('VideoManager.getController: url=$videoUrl active after ongoing future completed. refCount=${_activeControllers[videoUrl]!.refCount}');
      } else {
        debugPrint('VideoManager.getController: url=$videoUrl not active after future completed. Retrying...');
        return getController(videoUrl, isLocal: isLocal);
      }
      _printStats();
      return _activeControllers[videoUrl]!.controller;
    }

    // Case 4: Create new
    final future = _createControllerActual(videoUrl, isLocal: isLocal);
    _getControllerFutures[videoUrl] = future;

    try {
      final controller = await future;
      _getControllerFutures.remove(videoUrl);
      _printStats();
      return controller;
    } catch (e) {
      _getControllerFutures.remove(videoUrl);
      _printStats();
      rethrow;
    }
  }

  Future<File> _getPlayableFile(File cachedFile) async {
    if (cachedFile.path.endsWith('.mp4') || cachedFile.path.endsWith('.mkv')) {
      return cachedFile;
    }

    final tempDir = Directory.systemTemp;
    final cacheDir = Directory('${tempDir.path}/playable_videos');
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    final symlinkName = '${cachedFile.path.hashCode}.mp4';
    final symlinkPath = '${cacheDir.path}/$symlinkName';
    final symlinkFile = File(symlinkPath);

    if (!symlinkFile.existsSync()) {
      try {
        final link = Link(symlinkPath);
        await link.create(cachedFile.path);
        debugPrint('VideoManager: Created symlink for video: $symlinkPath -> ${cachedFile.path}');
      } catch (e) {
        debugPrint('VideoManager: Symlink creation failed, copying instead: $e');
        try {
          await cachedFile.copy(symlinkPath);
        } catch (copyErr) {
          debugPrint('VideoManager: Copy failed, returning original: $copyErr');
          return cachedFile;
        }
      }
    }

    return symlinkFile;
  }

  Future<VideoPlayerController> _createControllerActual(String videoUrl, {required bool isLocal}) async {
    VideoPlayerController controller;
    if (isLocal) {
      final playableFile = await _getPlayableFile(File(videoUrl));
      controller = VideoPlayerController.file(playableFile);
    } else {
      // Check memory cache of resolved cached paths synchronously
      if (_cachedFilePaths.containsKey(videoUrl)) {
        final path = _cachedFilePaths[videoUrl]!;
        if (File(path).existsSync()) {
          final playableFile = await _getPlayableFile(File(path));
          controller = VideoPlayerController.file(playableFile);
          _activeControllers[videoUrl] = _CachedController(controller: controller, refCount: 1);
          return controller;
        } else {
          _cachedFilePaths.remove(videoUrl);
        }
      }

      try {
        final fileInfo = await DefaultCacheManager().getFileFromCache(videoUrl);
        if (fileInfo != null && fileInfo.file.existsSync()) {
          _cachedFilePaths[videoUrl] = fileInfo.file.path;
          final playableFile = await _getPlayableFile(fileInfo.file);
          controller = VideoPlayerController.file(playableFile);
        } else {
          controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
          // Start background download with deduplication
          preCacheVideo(videoUrl);
        }
      } catch (e) {
        controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      }
    }

    _activeControllers[videoUrl] = _CachedController(controller: controller, refCount: 1);
    return controller;
  }

  /// Pre-caches a video URL asynchronously using DefaultCacheManager with deduplication
  void preCacheVideo(String videoUrl) {
    if (!videoUrl.startsWith('http')) return;
    if (_cachedFilePaths.containsKey(videoUrl)) return; // Already resolved in memory cache!
    if (_preCachingUrls.contains(videoUrl)) return; // Already downloading or checking!

    _preCachingUrls.add(videoUrl);

    DefaultCacheManager().getFileFromCache(videoUrl).then((fileInfo) {
      if (fileInfo != null && fileInfo.file.existsSync()) {
        _cachedFilePaths[videoUrl] = fileInfo.file.path;
        _preCachingUrls.remove(videoUrl);
        return;
      }

      debugPrint('Pre-caching video: $videoUrl');
      DefaultCacheManager().downloadFile(videoUrl).then((file) {
        if (file.file.existsSync()) {
          _cachedFilePaths[videoUrl] = file.file.path;
        }
        _preCachingUrls.remove(videoUrl);
        debugPrint('Pre-caching video completed: $videoUrl');
      }).catchError((e) {
        _preCachingUrls.remove(videoUrl);
        debugPrint('Failed to pre-cache video: $e');
      });
    }).catchError((e) {
      _preCachingUrls.remove(videoUrl);
    });
  }

  /// Safely initialize a controller, avoiding parallel double-initializations
  Future<void> initializeController(String videoUrl, VideoPlayerController controller) {
    if (controller.value.isInitialized) {
      return Future.value();
    }
    if (_initializationFutures.containsKey(controller)) {
      return _initializationFutures[controller]!;
    }
    final future = controller.initialize().then((_) {
      _initializationFutures.remove(controller);
    }).catchError((e) {
      _initializationFutures.remove(controller);
      throw e;
    });
    _initializationFutures[controller] = future;
    return future;
  }

  /// Release a video controller. When the reference count drops to 0,
  /// it is paused and moved to the inactive cache (evicting the oldest if limit exceeded).
  void releaseController(String videoUrl) {
    debugPrint('VideoManager.releaseController: url=$videoUrl');
    if (!_activeControllers.containsKey(videoUrl)) {
      debugPrint('VideoManager.releaseController: url=$videoUrl not in active controllers list!');
      _printStats();
      return;
    }

    final cached = _activeControllers[videoUrl]!;
    cached.refCount--;
    debugPrint('VideoManager.releaseController: url=$videoUrl refCount decremented to ${cached.refCount}');

    if (cached.refCount <= 0) {
      _activeControllers.remove(videoUrl);

      // Only add to inactive cache if it is initialized and has no errors
      if (cached.controller.value.isInitialized && !cached.controller.value.hasError) {
        cached.controller.pause();
        _inactiveControllers[videoUrl] = cached.controller;
        _inactiveKeys.remove(videoUrl);
        _inactiveKeys.add(videoUrl);
        debugPrint('VideoManager.releaseController: url=$videoUrl moved to inactive cache');

        // Evict if cache size exceeded
        if (_inactiveKeys.length > _maxInactiveCacheSize) {
          final oldestUrl = _inactiveKeys.removeAt(0);
          final oldestController = _inactiveControllers.remove(oldestUrl);
          if (oldestController != null) {
            debugPrint('VideoManager.releaseController: evicting and disposing oldest inactive url=$oldestUrl');
            _initializationFutures.remove(oldestController);
            oldestController.dispose();
          }
        }
      } else {
        debugPrint('VideoManager.releaseController: url=$videoUrl is uninitialized or broken, disposing immediately');
        _initializationFutures.remove(cached.controller);
        cached.controller.dispose();
      }
    }
    _printStats();
  }

  /// Pause all videos except the specified one
  void pauseAllExcept(String? exceptUrl) {
    _activeControllers.forEach((url, cached) {
      if (url != exceptUrl && cached.controller.value.isPlaying) {
        cached.controller.pause();
      }
    });
    _currentPlayingVideo = exceptUrl;
  }

  /// Pause all videos
  void pauseAll() {
    _activeControllers.forEach((url, cached) {
      if (cached.controller.value.isPlaying) {
        cached.controller.pause();
      }
    });
    _currentPlayingVideo = null;
  }

  /// Dispose a specific controller immediately (active or inactive)
  void disposeController(String videoUrl) {
    debugPrint('VideoManager.disposeController: url=$videoUrl');
    _getControllerFutures.remove(videoUrl);
    if (_activeControllers.containsKey(videoUrl)) {
      final cached = _activeControllers.remove(videoUrl)!;
      _initializationFutures.remove(cached.controller);
      cached.controller.dispose();
    } else if (_inactiveControllers.containsKey(videoUrl)) {
      final controller = _inactiveControllers.remove(videoUrl)!;
      _inactiveKeys.remove(videoUrl);
      _initializationFutures.remove(controller);
      controller.dispose();
    }
    if (_currentPlayingVideo == videoUrl) {
      _currentPlayingVideo = null;
    }
    _printStats();
  }

  /// Dispose all controllers (active and inactive)
  void disposeAll() {
    debugPrint('VideoManager.disposeAll');
    _initializationFutures.clear();
    _getControllerFutures.clear();
    _activeControllers.forEach((url, cached) {
      cached.controller.dispose();
    });
    _activeControllers.clear();

    _inactiveControllers.forEach((url, controller) {
      controller.dispose();
    });
    _inactiveControllers.clear();
    _inactiveKeys.clear();
    _currentPlayingVideo = null;
    _printStats();
  }

  /// Get currently playing video URL
  String? get currentPlayingVideo => _currentPlayingVideo;
}
