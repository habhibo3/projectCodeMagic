// Conditional export for AgoraWebService.
// Selects the appropriate implementation depending on whether JS libraries are available (Web vs Native).

export 'agora_web_service_stub.dart'
    if (dart.library.js_util) 'agora_web_service_web.dart';
