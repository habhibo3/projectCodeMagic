import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:js' as js;

// Web-specific video player for Agora live streaming
// Uses HTML video elements to display Agora streams

class AgoraWebVideoPlayer extends StatefulWidget {
  final String videoId;

  const AgoraWebVideoPlayer({
    super.key,
    required this.videoId,
  });

  @override
  State<AgoraWebVideoPlayer> createState() => _AgoraWebVideoPlayerState();
}

class _AgoraWebVideoPlayerState extends State<AgoraWebVideoPlayer> {
  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const Center(
        child: Text('Web video player only works on web'),
      );
    }

    return Container(
      color: Colors.black,
      child: _VideoElementView(elementId: widget.videoId),
    );
  }
}

class _VideoElementView extends StatefulWidget {
  final String elementId;

  const _VideoElementView({required this.elementId});

  @override
  State<_VideoElementView> createState() => _VideoElementViewState();
}

class _VideoElementViewState extends State<_VideoElementView> {
  @override
  void initState() {
    super.initState();
    // Create and register the video element
    ui_web.platformViewRegistry.registerViewFactory(
      widget.elementId,
      (int viewId) {
        final videoElement = html.VideoElement()
          ..id = widget.elementId
          ..autoplay = true
          ..muted = widget.elementId == 'local-video' // Mute local video
          ..setAttribute('playsinline', 'true')
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover';

        try {
          js.context.callMethod('bindVideoElement', [widget.elementId]);
        } catch (e) {
          debugPrint('Error calling bindVideoElement: $e');
        }

        return videoElement;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: widget.elementId);
  }
}
