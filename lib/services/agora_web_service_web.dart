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

class AgoraWebService {
  static bool _sdkLoaded = false;
  static Completer<bool>? _sdkLoadCompleter;

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
}
