import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/station.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_helper.dart';
import '../widgets/media_content_preview.dart';
import '../widgets/full_screen_video_player.dart';

class WatchRecordedLiveScreen extends StatefulWidget {
  final RecordedLiveModel recordedLive;
  final StationModel station;

  const WatchRecordedLiveScreen({
    super.key,
    required this.recordedLive,
    required this.station,
  });

  @override
  State<WatchRecordedLiveScreen> createState() => _WatchRecordedLiveScreenState();
}

class _WatchRecordedLiveScreenState extends State<WatchRecordedLiveScreen> {
  bool _isLiked = false;
  int _likeCount = 0;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.recordedLive.likeCount;
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final recorded = widget.recordedLive;

    return Scaffold(
      backgroundColor: const Color(0xFF070707),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070707),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          recorded.title.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 13,
            letterSpacing: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              children: [
                // Video Player Container
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: kIsWeb ? MediaQuery.of(context).size.height * 0.55 : double.infinity,
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      color: Colors.black,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MediaContentPreview(
                            type: inferMediaTypeFromUrl(recorded.videoUrl),
                            contentUrl: recorded.videoUrl.isNotEmpty
                                ? recorded.videoUrl
                                : recorded.thumbnailUrl.isNotEmpty
                                    ? recorded.thumbnailUrl
                                    : widget.station.image,
                            height: double.infinity,
                            autoPlayVideo: false,
                            videoThumbnailMode: true,
                            onVideoTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FullScreenVideoPlayer(
                                    videoUrl: recorded.videoUrl.isNotEmpty
                                        ? recorded.videoUrl
                                        : widget.station.image,
                                    isLocal: false,
                                  ),
                                ),
                              );
                            },
                          ),
                          // TOP DURATION BADGE
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.75),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(LucideIcons.clock, size: 12, color: AppTheme.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    recorded.formattedDuration,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Video Meta & Details
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      recorded.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Stats Row
                    Row(
                      children: [
                        const Icon(LucideIcons.calendar, size: 14, color: Colors.white54),
                        const SizedBox(width: 6),
                        Text(
                          _formatDate(recorded.recordedAt),
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(width: 16),
                        const Icon(LucideIcons.eye, size: 14, color: Colors.white54),
                        const SizedBox(width: 6),
                        Text(
                          '${recorded.viewerCount} views',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(color: Colors.white12),
                    ),

                    // Host Info Row
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundImage: AvatarHelper.getSafeAvatarProvider(recorded.hostAvatar),
                          backgroundColor: Colors.grey.shade900,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                recorded.hostName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                widget.station.title,
                                style: const TextStyle(color: AppTheme.primary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        // Like Button
                        InkWell(
                          onTap: () {
                            setState(() {
                              _isLiked = !_isLiked;
                              _likeCount += _isLiked ? 1 : -1;
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: _isLiked ? Colors.red.withOpacity(0.2) : const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _isLiked ? Colors.red : Colors.white12,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.heart,
                                  size: 16,
                                  color: _isLiked ? Colors.red : Colors.white70,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$_likeCount',
                                  style: TextStyle(
                                    color: _isLiked ? Colors.red : Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    const Text(
                      'Recorded Live Broadcast',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'This broadcast was streamed live on ${widget.station.title}. Watch past streams and highlights anytime.',
                      style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);
  }
}
