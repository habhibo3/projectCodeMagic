import 'dart:js' as js;
import 'dart:js_util';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:js/js.dart';

// Agora Web Service - JavaScript interop for Agora web SDK
// This service provides a bridge between Flutter and the Agora web JavaScript SDK

@JS('initializeAgora')
external dynamic _jsInitializeAgora(String appId);

@JS('joinChannel')
external dynamic _jsJoinChannel(String appId, String channel, int userId, String token);

@JS('leaveChannel')
external dynamic _jsLeaveChannel();

@JS('toggleMuteAudio')
external void _jsToggleMuteAudio(bool mute);

@JS('toggleMuteVideo')
external void _jsToggleMuteVideo(bool mute);

@JS('getClientState')
external dynamic _jsGetClientState();

@JS('setUserLeftCallback')
external void _jsSetUserLeftCallback(dynamic callback);

@JS('setScreenSharingStateCallback')
external void _jsSetScreenSharingStateCallback(dynamic callback);

@JS('startRecording')
external dynamic _jsStartRecording(String filename, [bool? useBrowserCapture]);

@JS('stopRecording')
external dynamic _jsStopRecording();

@JS('isRecording')
external dynamic _jsIsRecording();

@JS('getLatestRecordingBytes')
external dynamic _jsGetLatestRecordingBytes();

@JS('downloadLatestRecording')
external void _jsDownloadLatestRecording();

@JS('releaseMediaDevices')
external void _jsReleaseMediaDevices();

@JS('startScreenSharing')
external dynamic _jsStartScreenSharing();

@JS('stopScreenSharing')
external dynamic _jsStopScreenSharing();

@JS('getScreenSharingState')
external dynamic _jsGetScreenSharingState();

class AgoraWebService {
  static bool _sdkLoaded = false;
  static Completer<bool>? _sdkLoadCompleter;
  static Function(int)? _onUserLeftCallback;
  static Function(bool)? _onScreenSharingStateChangedCallback;
  
  static void setUserLeftCallback(Function(int) callback) {
    _onUserLeftCallback = callback;
  }

  static void setScreenSharingStateCallback(Function(bool) callback) {
    _onScreenSharingStateChangedCallback = callback;
    _jsSetScreenSharingStateCallback(allowInterop((bool isSharing) {
      debugPrint('AgoraWebService: Screen sharing state changed to: $isSharing');
      _onScreenSharingStateChangedCallback?.call(isSharing);
    }));
  }

  // Wait for SDK to load
  static Future<bool> waitForSDK({int maxAttempts = 50, int intervalMs = 100}) async {
    if (_sdkLoaded) return true;
    
    if (_sdkLoadCompleter == null) {
      _sdkLoadCompleter = Completer<bool>();
      
      int attempts = 0;
      debugPrint('AgoraWebService: Starting to wait for SDK load...');
      
      Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
        attempts++;
        try {
          final isLoaded = js.context.callMethod('eval', ['typeof AgoraRTC !== "undefined"']);
          debugPrint('AgoraWebService: SDK check attempt $attempts: isLoaded=$isLoaded');
          
          if (isLoaded == true) {
            _sdkLoaded = true;
            debugPrint('AgoraWebService: SDK loaded successfully after $attempts attempts');
            _sdkLoadCompleter?.complete(true);
            timer.cancel();
          } else if (attempts >= maxAttempts) {
            debugPrint('AgoraWebService: SDK failed to load after $maxAttempts attempts');
            _sdkLoadCompleter?.complete(false);
            timer.cancel();
          }
        } catch (e) {
          debugPrint('AgoraWebService: Error checking SDK load on attempt $attempts: $e');
          if (attempts >= maxAttempts) {
            debugPrint('AgoraWebService: Max attempts reached with errors');
            _sdkLoadCompleter?.complete(false);
            timer.cancel();
          }
        }
      });
    }
    
    return _sdkLoadCompleter!.future;
  }

  // Initialize Agora client
  static Future<bool> initializeAgora(String appId) async {
    if (!kIsWeb) return false;
    
    debugPrint('AgoraWebService: initializeAgora called with appId: $appId');
    
    // Set up user-left callback
    _jsSetUserLeftCallback(allowInterop((int uid) {
      debugPrint('AgoraWebService: User left callback triggered for uid=$uid');
      _onUserLeftCallback?.call(uid);
    }));
    
    // The JS initializeAgora now handles SDK loading internally
    debugPrint('AgoraWebService: Calling JS initializeAgora (it will load SDK dynamically)...');
    
    try {
      // Call the JS function using @JS annotation
      final jsResult = _jsInitializeAgora(appId);
      debugPrint('AgoraWebService: JS initializeAgora returned object: $jsResult');
      
      // Check if it's a promise before converting
      if (jsResult != null && hasProperty(jsResult, 'then')) {
        final result = await promiseToFuture(jsResult);
        debugPrint('AgoraWebService: Promise resolved with: $result');
        return result as bool? ?? false;
      } else {
        debugPrint('AgoraWebService: JS function did not return a promise, treating as direct result');
        return jsResult as bool? ?? false;
      }
    } catch (e) {
      debugPrint('AgoraWebService: initializeAgora error: $e');
      return false;
    }
  }

  // Join channel
  static Future<Map<String, dynamic>> joinChannel({
    required String appId,
    required String channel,
    required int userId,
    String? token,
  }) async {
    if (!kIsWeb) {
      return {'success': false, 'error': 'Not on web platform'};
    }

    // Wait for SDK to load first
    final sdkReady = await waitForSDK();
    if (!sdkReady) {
      return {'success': false, 'error': 'Agora SDK failed to load'};
    }

    try {
      final result = await promiseToFuture(_jsJoinChannel(appId, channel, userId, token ?? ''));
      // Convert JS object to Map properly
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      } else {
        // If it's already a JS object, convert it
        final map = <String, dynamic>{};
        final keys = objectKeys(result);
        for (final key in keys) {
          map[key as String] = getProperty(result, key);
        }
        return map;
      }
    } catch (e) {
      debugPrint('AgoraWebService: joinChannel error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Leave channel
  static Future<Map<String, dynamic>> leaveChannel() async {
    if (!kIsWeb) {
      return {'success': false, 'error': 'Not on web platform'};
    }

    try {
      final result = await promiseToFuture(_jsLeaveChannel());
      return Map<String, dynamic>.from(result);
    } catch (e) {
      debugPrint('AgoraWebService: leaveChannel error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Toggle microphone
  static void toggleMuteAudio(bool mute) {
    if (!kIsWeb) return;
    
    try {
      _jsToggleMuteAudio(mute);
    } catch (e) {
      debugPrint('AgoraWebService: toggleMuteAudio error: $e');
    }
  }

  // Toggle camera
  static void toggleMuteVideo(bool mute) {
    if (!kIsWeb) return;
    
    try {
      _jsToggleMuteVideo(mute);
    } catch (e) {
      debugPrint('AgoraWebService: toggleMuteVideo error: $e');
    }
  }

  // Get client state
  static Map<String, dynamic> getClientState() {
    if (!kIsWeb) {
      return {
        'isConnected': false,
        'hasLocalStream': false,
        'remoteStreamCount': 0,
        'channelName': '',
        'uid': null,
      };
    }

    try {
      final result = _jsGetClientState();
      return Map<String, dynamic>.from(result);
    } catch (e) {
      debugPrint('AgoraWebService: getClientState error: $e');
      return {
        'isConnected': false,
        'hasLocalStream': false,
        'remoteStreamCount': 0,
        'channelName': '',
        'uid': null,
      };
    }
  }

  // ── Recording ──────────────────────────────────────────────────────────────

  /// Start recording the live video stream.
  /// [filename] is the base filename (without extension) for the saved file.
  /// Returns true if recording started successfully.
  static Future<bool> startWebRecording(
    String filename, {
    bool useBrowserCapture = true,
  }) async {
    if (!kIsWeb) return false;
    try {
      final result = await promiseToFuture(
        _jsStartRecording(filename, useBrowserCapture),
      );
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('AgoraWebService: startWebRecording error: $e');
      return false;
    }
  }

  /// Stop the current recording. Triggers a browser download of the recorded file.
  /// Returns true if recording was stopped successfully.
  static bool stopWebRecording() {
    if (!kIsWeb) return false;
    try {
      final result = _jsStopRecording();
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('AgoraWebService: stopWebRecording error: $e');
      return false;
    }
  }

  /// Returns true if a recording is currently in progress.
  static bool isWebRecording() {
    if (!kIsWeb) return false;
    try {
      final result = _jsIsRecording();
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('AgoraWebService: isWebRecording error: $e');
      return false;
    }
  }

  /// Retrieves the recorded bytes (Uint8List) on Web platform after recording has stopped.
  static Future<Uint8List?> getLatestWebRecordingBytes() async {
    if (!kIsWeb) return null;
    try {
      final jsPromise = _jsGetLatestRecordingBytes();
      if (jsPromise != null) {
        final result = await promiseToFuture(jsPromise);
        debugPrint('AgoraWebService: getLatestWebRecordingBytes result type: ${result.runtimeType}');
        
        if (result != null) {
          // Handle different possible return types from JS
          if (result is Uint8List) {
            debugPrint('Result is direct Uint8List, size: ${result.length}');
            return result;
          } else if (result is List) {
            debugPrint('Result is a List, converting to Uint8List');
            return Uint8List.fromList(List<int>.from(result));
          } else if (result is Map) {
            debugPrint('Result is a Map, trying to extract bytes');
            // Try to extract bytes from Map
            final bytesData = result['bytes'];
            if (bytesData != null) {
              if (bytesData is Uint8List) {
                return bytesData;
              } else if (bytesData is List) {
                return Uint8List.fromList(List<int>.from(bytesData));
              }
            }
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('AgoraWebService: getLatestWebRecordingBytes error: $e');
      return null;
    }
  }

  /// Triggers browser file download of the recorded stream.
  static void downloadLatestWebRecording() {
    if (!kIsWeb) return;
    try {
      _jsDownloadLatestRecording();
    } catch (e) {
      debugPrint('AgoraWebService: downloadLatestWebRecording error: $e');
    }
  }

  /// Releases all camera and microphone media stream tracks in browser.
  static void releaseMediaDevices() {
    if (!kIsWeb) return;
    try {
      _jsReleaseMediaDevices();
    } catch (e) {
      debugPrint('AgoraWebService: releaseMediaDevices error: $e');
    }
  }

  // ── Screen Sharing ─────────────────────────────────────────────────────────

  /// Start screen sharing for the host
  static Future<Map<String, dynamic>> startWebScreenSharing() async {
    if (!kIsWeb) {
      return {'success': false, 'error': 'Not on web platform'};
    }
    try {
      final result = await promiseToFuture(_jsStartScreenSharing());
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      } else {
        final map = <String, dynamic>{};
        final keys = objectKeys(result);
        for (final key in keys) {
          map[key as String] = getProperty(result, key);
        }
        return map;
      }
    } catch (e) {
      debugPrint('AgoraWebService: startWebScreenSharing error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Stop screen sharing and return to camera
  static Future<Map<String, dynamic>> stopWebScreenSharing() async {
    if (!kIsWeb) {
      return {'success': false, 'error': 'Not on web platform'};
    }
    try {
      final result = await promiseToFuture(_jsStopScreenSharing());
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      } else {
        final map = <String, dynamic>{};
        final keys = objectKeys(result);
        for (final key in keys) {
          map[key as String] = getProperty(result, key);
        }
        return map;
      }
    } catch (e) {
      debugPrint('AgoraWebService: stopWebScreenSharing error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Check if screen sharing is currently active
  static bool isWebScreenSharing() {
    if (!kIsWeb) return false;
    try {
      final result = _jsGetScreenSharingState();
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('AgoraWebService: isWebScreenSharing error: $e');
      return false;
    }
  }

  static void debugPrint(String s) {}
}
