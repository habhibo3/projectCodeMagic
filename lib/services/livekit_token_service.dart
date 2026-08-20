import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'agora_web_service.dart';

class LiveKitRoomCredentials {
  final String serverUrl;
  final String participantToken;
  final bool canPublish;

  const LiveKitRoomCredentials({
    required this.serverUrl,
    required this.participantToken,
    this.canPublish = true,
  });
}

class LiveKitTokenService {
  static final LiveKitTokenService _instance = LiveKitTokenService._internal();

  factory LiveKitTokenService() => _instance;

  LiveKitTokenService._internal();

  // LiveKit Cloud credentials (configured for wss://mlivecast-kutdj3il.livekit.cloud)
  static String serverUrl = 'wss://mlivecast-kutdj3il.livekit.cloud';
  static String apiKey = 'APImmymJMaxCWrz';
  static String apiSecret = '1erEac9A5BQp9TpyrgwBFwCgbfwCJPxVZDmjz5S81xZ';

  /// Generates a valid LiveKit JWT Token signed with HS256 algorithm.
  static String createToken({
    required String roomName,
    required String participantIdentity,
    String? key,
    String? secret,
  }) {
    final k = key ?? apiKey;
    final s = secret ?? apiSecret;

    if (k.isEmpty || s.isEmpty) {
      return '';
    }

    final header = {
      'alg': 'HS256',
      'typ': 'JWT',
    };

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final payload = {
      'exp': now + 86400, // 24 hours validity
      'iss': k,
      'sub': participantIdentity,
      'nbf': now - 5,
      'video': {
        'room': roomName,
        'roomJoin': true,
        'roomCreate': true,
        'roomAdmin': true,
        'canPublish': true,
        'canSubscribe': true,
        'canPublishData': true,
        'canPublishSources': ['camera', 'microphone', 'screen_share', 'screen_share_audio'],
      },
    };

    String base64UrlEncodeNoPadding(List<int> bytes) {
      return base64Url.encode(bytes).replaceAll('=', '');
    }

    final headerB64 = base64UrlEncodeNoPadding(utf8.encode(jsonEncode(header)));
    final payloadB64 = base64UrlEncodeNoPadding(utf8.encode(jsonEncode(payload)));
    final dataToSign = '$headerB64.$payloadB64';

    final hmac = Hmac(sha256, utf8.encode(s));
    final signature = hmac.convert(utf8.encode(dataToSign));
    final sigB64 = base64UrlEncodeNoPadding(signature.bytes);

    return '$dataToSign.$sigB64';
  }

  Future<LiveKitRoomCredentials> getRoomCredentials({
    required String contestId,
    String? entryId,
  }) async {
    final roomName = entryId != null ? 'contest_${contestId}_$entryId' : 'station_$contestId';
    final identity = 'user_${DateTime.now().millisecondsSinceEpoch}';

    final token = createToken(
      roomName: roomName,
      participantIdentity: identity,
    );

    return LiveKitRoomCredentials(
      serverUrl: serverUrl,
      participantToken: token,
      canPublish: true,
    );
  }

  Future<bool> startStationLiveRecording({
    required String stationId,
    required String title,
    String? thumbnailUrl,
    String? hostName,
    String? hostAvatar,
  }) async {
    debugPrint('[LiveKitTokenService] Starting automatic station live recording for stationId=$stationId');
    if (kIsWeb) {
      return await AgoraWebService.startWebRecording(
        'station_$stationId',
        useBrowserCapture: false,
      );
    }
    return true;
  }

  Future<bool> stopStationLiveRecording(String stationId) async {
    debugPrint('[LiveKitTokenService] Stopping station live recording for stationId=$stationId');
    if (kIsWeb) {
      return AgoraWebService.stopWebRecording();
    }
    return true;
  }

  Future<bool> startContestLiveRecording({
    required String contestId,
    required String entryId,
    String? thumbnailUrl,
  }) async {
    debugPrint('[LiveKitTokenService] Starting contest live recording for contestId=$contestId, entryId=$entryId');
    if (kIsWeb) {
      return await AgoraWebService.startWebRecording(
        'contest_${contestId}_$entryId',
        useBrowserCapture: true,
      );
    }
    return true;
  }

  Future<bool> stopContestLiveRecording(String contestId, String entryId) async {
    debugPrint('[LiveKitTokenService] Stopping contest live recording for contestId=$contestId, entryId=$entryId');
    if (kIsWeb) {
      return AgoraWebService.stopWebRecording();
    }
    return true;
  }
}
