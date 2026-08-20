import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class WebVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final VoidCallback onClose;

  const WebVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.onClose,
  });

  @override
  State<WebVideoPlayer> createState() => _WebVideoPlayerState();
}

class _WebVideoPlayerState extends State<WebVideoPlayer> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    // A view type can only be registered once. Give each opened recording its
    // own type so reopening a recording cannot leave a blank player.
    _viewType = 'video-player-${identityHashCode(this)}';
    _registerWebVideoElement();
  }

  void _registerWebVideoElement() {
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) {
        final videoElement = html.VideoElement()
          ..src = widget.videoUrl
          ..autoplay = true
          ..controls = true
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'contain';
        
        return videoElement;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // HTML5 Video Element
          HtmlElementView(viewType: _viewType),
          
          // Close button
          Positioned(
            top: 16,
            left: 16,
            child: IconButton(
              icon: const Icon(LucideIcons.chevronDown, color: Colors.white, size: 28),
              onPressed: widget.onClose,
            ),
          ),
        ],
      ),
    );
  }
}
