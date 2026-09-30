import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

  // These are public connection details. The signing secret stays in Cloud Functions.
  static String serverUrl = 'wss://mlivecast-kutdj3il.livekit.cloud';

  Future<LiveKitRoomCredentials> getRoomCredentials({
    required String contestId,
    String? entryId,
    bool isHost = false,
    bool isCoHost = false,
    bool isStation = false,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final idToken = currentUser == null ? null : await currentUser.getIdToken();
    final projectId = Firebase.app().options.projectId;
    final uri = Uri.parse(
      'https://us-central1-$projectId.cloudfunctions.net/issueLiveKitToken',
    );
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (idToken != null) 'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({
            'roomKind': isStation ? 'station' : (entryId != null ? 'entry' : 'organizer'),
            'contestId': contestId,
            if (isStation) 'stationId': contestId,
            if (entryId != null) 'entryId': entryId,
            'isHost': isHost,
            'isCoHost': isCoHost,
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('LiveKit token request failed (${response.statusCode}).');
    }
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    final token = result['participantToken'] as String? ?? '';
    if (token.isEmpty) throw Exception('LiveKit returned an empty participant token.');
    serverUrl = result['serverUrl'] as String? ?? serverUrl;

    return LiveKitRoomCredentials(
      serverUrl: serverUrl,
      participantToken: token,
      canPublish: result['canPublish'] as bool? ?? false,
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
