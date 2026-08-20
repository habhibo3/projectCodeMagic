import 'package:flutter/material.dart';

// Stub implementation for mobile platforms
class WebVideoPlayer extends StatelessWidget {
  final String videoUrl;
  final VoidCallback onClose;

  const WebVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // This should never be called on mobile
    return const SizedBox.shrink();
  }
}
