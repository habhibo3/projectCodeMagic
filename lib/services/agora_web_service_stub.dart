import 'dart:async';

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
}
