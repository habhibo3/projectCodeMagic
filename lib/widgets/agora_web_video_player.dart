// Conditional export for AgoraWebVideoPlayer.
// Selects the appropriate implementation depending on whether JS libraries are available (Web vs Native).

export 'agora_web_video_player_stub.dart'
    if (dart.library.js_util) 'agora_web_video_player_web.dart';
