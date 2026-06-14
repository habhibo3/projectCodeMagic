import 'package:flutter/material.dart';

// Stub implementation of AgoraWebVideoPlayer for non-web platforms.
// Contains no imports of web-only libraries.

class AgoraWebVideoPlayer extends StatelessWidget {
  final String videoId;

  const AgoraWebVideoPlayer({
    super.key,
    required this.videoId,
  });

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Web video player only works on web'),
    );
  }
}
