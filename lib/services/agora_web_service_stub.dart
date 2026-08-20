import 'dart:async';
import 'dart:typed_data';

// Stub implementation of AgoraWebService for non-web platforms.
// Returns safe default/fallback values and contains no imports of web-only libraries.

class AgoraWebService {
  static Future<bool> waitForSDK({int maxAttempts = 50, int intervalMs = 100}) async {
    return false;
  }

  static Future<bool> initializeAgora(String appId) async {
    return false;
  }

  static Future<Map<String, dynamic>> joinChannel({
    required String appId,
    required String channel,
    required int userId,
    String? token,
  }) async {
    return {'success': false, 'error': 'Not on web platform'};
  }

  static Future<Map<String, dynamic>> leaveChannel() async {
    return {'success': false, 'error': 'Not on web platform'};
  }

  static void toggleMuteAudio(bool mute) {}

  static void toggleMuteVideo(bool mute) {}

  static Map<String, dynamic> getClientState() {
    return {
      'isConnected': false,
      'hasLocalStream': false,
      'remoteStreamCount': 0,
      'channelName': '',
      'uid': null,
    };
  }

  static void setUserLeftCallback(Function(int) callback) {}

  static void setScreenSharingStateCallback(Function(bool) callback) {}

  // Recording stubs (no-op on non-web platforms)
  static Future<bool> startWebRecording(
    String filename, {
    bool useBrowserCapture = true,
  }) async => false;
  static bool stopWebRecording() => false;
  static bool isWebRecording() => false;
  static Future<Uint8List?> getLatestWebRecordingBytes() async => null;
  static void downloadLatestWebRecording() {}
  static void releaseMediaDevices() {}

  // Screen sharing stubs (no-op on non-web platforms)
  static Future<Map<String, dynamic>> startWebScreenSharing() async {
    return {'success': false, 'error': 'Not on web platform'};
  }
  static Future<Map<String, dynamic>> stopWebScreenSharing() async {
    return {'success': false, 'error': 'Not on web platform'};
  }
  static bool isWebScreenSharing() => false;
}
