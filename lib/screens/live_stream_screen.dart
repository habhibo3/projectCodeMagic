import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:confetti/confetti.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/entry.dart';
import '../models/comment.dart';
import '../data/firebase_service.dart';
import '../engine/ranking_engine.dart';
import '../widgets/live_broadcast_widgets.dart';
import 'package:audioplayers/audioplayers.dart';

const String appId = "cc891f53a26c43eab01dd4e8009ba100";
const String token = "";
const int kHostAgoraUid = 100;
const int kCoHostAgoraUid = 200;

enum CameraView {
  hostOnly,
  coHostOnly,
  splitBoth,
}

class LiveStreamScreen extends StatefulWidget {
  final bool isHost;
  final bool isCoHost;
  final ContestModel contest;
  final String? entryId;

  const LiveStreamScreen({
    super.key,
    required this.contest,
    this.isHost = false,
    this.isCoHost = false,
    this.entryId,
  });

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen>
    with SingleTickerProviderStateMixin {
  int? _remoteUid;
  bool _localUserJoined = false;
  late RtcEngine _engine;
  late ConfettiController _confettiController;
  late AnimationController _pulseController;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Media controls (local states for Host)
  bool _isMicOn = true;
  bool _isCameraOn = true;
  bool _isFrontCamera = true;

  // Layout states
  CameraView _cameraView = CameraView.hostOnly;
  bool _isSplitScreen = true; // false = Fullscreen camera feed on screen
  bool _isCoHostConnected = false;

  // Stream entries & details
  ContestEntry? _selectedEntry;
  ContestEntry? _coHostEntry;
  List<ContestEntry> _allEntries = [];

  String get _channelId => widget.entryId ?? widget.contest.id;
  String? get _entryId => widget.entryId;
  bool get _isBroadcaster => widget.isHost || widget.isCoHost;

  StreamSubscription? _sessionSub;
  String? _activeInviteId;

  @override
  void initState() {
    super.initState();
    // Force Landscape Orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      lowerBound: 1.0,
      upperBound: 1.2,
    );

    initAgora();

    // Fetch entries and make sure current contest is loaded in the engine
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final engine = Provider.of<RankingEngine>(context, listen: false);
      engine.loadContestEntries(widget.contest.id);
      _allEntries = engine.entries;
      if (_entryId != null) {
        try {
          _selectedEntry = _allEntries.firstWhere((e) => e.id == _entryId);
        } catch (_) {
          if (_allEntries.isNotEmpty) _selectedEntry = _allEntries.first;
        }
        engine.trackEntryView(_selectedEntry?.id ?? _entryId!);
        _listenLiveSession(engine);
      } else if (_allEntries.isNotEmpty) {
        _selectedEntry = _allEntries.first;
        engine.trackEntryView(_selectedEntry!.id);
      }
      if (mounted) setState(() {});
    });
  }

  void _listenLiveSession(RankingEngine engine) {
    if (_entryId == null) return;
    _sessionSub?.cancel();
    _sessionSub = engine.watchLiveSession(_entryId!).listen((session) {
      if (!mounted || session == null) return;
      final status = session['status'] as String? ?? 'idle';
      final coHostName = session['coHostName'] as String?;
      final coHostAvatar = session['coHostAvatar'] as String?;
      final coHostUserId = session['coHostUserId'] as String?;

      if (status == 'live' && coHostUserId != null) {
        setState(() {
          _isCoHostConnected = true;
          _remoteUid = kCoHostAgoraUid;
          _coHostEntry = ContestEntry(
            id: 'cohost_$coHostUserId',
            userId: coHostUserId,
            userName: coHostName ?? 'Co-Host',
            userAvatar: coHostAvatar?.isNotEmpty == true
                ? coHostAvatar!
                : 'https://i.pravatar.cc/150?u=cohost',
            contentUrl: '',
            type: 'video',
            caption: '',
          );
          if (_cameraView == CameraView.hostOnly && widget.isHost) {
            _cameraView = CameraView.splitBoth;
          }
        });
      } else if (status == 'idle') {
        setState(() {
          _isCoHostConnected = false;
          _remoteUid = null;
          _coHostEntry = null;
          _cameraView = CameraView.hostOnly;
        });
      } else if (status == 'invited') {
        setState(() {
          _coHostEntry = ContestEntry(
            id: 'cohost_pending',
            userId: coHostUserId ?? '',
            userName: coHostName ?? 'Co-Host',
            userAvatar: coHostAvatar?.isNotEmpty == true
                ? coHostAvatar!
                : 'https://i.pravatar.cc/150?u=pending',
            contentUrl: '',
            type: 'video',
            caption: 'Invitation sent…',
          );
        });
      }
    });
  }

  Future<void> initAgora() async {
    await [Permission.microphone, Permission.camera].request();

    _engine = createAgoraRtcEngine();
    await _engine.initialize(const RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    ));

    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          debugPrint("Agora: Local user ${connection.localUid} joined");
          if (mounted) setState(() => _localUserJoined = true);
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint("Agora: Remote user $remoteUid joined");
          if (!mounted) return;
          setState(() {
            if (remoteUid == kCoHostAgoraUid) {
              _remoteUid = kCoHostAgoraUid;
              _isCoHostConnected = true;
              if (widget.isHost && _cameraView == CameraView.hostOnly) {
                _cameraView = CameraView.splitBoth;
              }
            }
          });
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          debugPrint("Agora: Remote user $remoteUid left");
          if (mounted) {
            setState(() {
              if (remoteUid == _remoteUid) {
                _remoteUid = null;
                _isCoHostConnected = false;
                _cameraView = CameraView.hostOnly;
              }
            });
          }
        },
        onError: (ErrorCodeType err, String msg) {
          debugPrint("Agora Error: $err - $msg");
        },
      ),
    );

    await _engine.setClientRole(
      role: _isBroadcaster
          ? ClientRoleType.clientRoleBroadcaster
          : ClientRoleType.clientRoleAudience,
    );

    await _engine.enableVideo();
    if (_isBroadcaster) {
      await _engine.startPreview();
    }

    final joinUid = widget.isHost
        ? kHostAgoraUid
        : (widget.isCoHost ? kCoHostAgoraUid : 0);

    await _engine.joinChannel(
      token: token,
      channelId: _channelId,
      uid: joinUid,
      options: ChannelMediaOptions(
        clientRoleType: _isBroadcaster
            ? ClientRoleType.clientRoleBroadcaster
            : ClientRoleType.clientRoleAudience,
        publishCameraTrack: _isBroadcaster,
        publishMicrophoneTrack: _isBroadcaster,
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
      ),
    );
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    _engine.leaveChannel();
    _engine.release();
    _confettiController.dispose();
    _pulseController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- CONTROL ACTIONS ---

  void _toggleMic() async {
    setState(() => _isMicOn = !_isMicOn);
    await _engine.muteLocalAudioStream(!_isMicOn);
  }

  void _toggleCamera() async {
    setState(() => _isCameraOn = !_isCameraOn);
    await _engine.muteLocalVideoStream(!_isCameraOn);
  }

  void _switchCamera() async {
    setState(() => _isFrontCamera = !_isFrontCamera);
    await _engine.switchCamera();
  }

  Future<void> _disconnectCoHost() async {
    if (_entryId == null) return;
    final engine = Provider.of<RankingEngine>(context, listen: false);
    await engine.endCoHostSession(_entryId!, inviteId: _activeInviteId);
    setState(() {
      _isCoHostConnected = false;
      _remoteUid = null;
      _coHostEntry = null;
      _cameraView = CameraView.hostOnly;
      _activeInviteId = null;
    });
  }

  /// Real joined users only — no seed demo accounts, never yourself.
  List<ContestEntry> _inviteableParticipants(String myUserId) {
    final seen = <String>{};
    final list = <ContestEntry>[];
    for (final entry in _allEntries) {
      if (FirebaseService.demoUserIds.contains(entry.userId)) continue;
      if (entry.userId.isEmpty || entry.userId == myUserId) continue;
      if (seen.contains(entry.userId)) continue;
      seen.add(entry.userId);
      list.add(entry);
    }
    return list;
  }

  String _nameForEntry(ContestEntry? entry, RankingEngine engine) {
    if (entry == null) return 'Organizer';
    if (entry.userId == engine.currentUserId) {
      return engine.currentUserProfile?.displayName ?? entry.userName;
    }
    return entry.userName;
  }

  void _showParticipantsSheet() {
    final engine = Provider.of<RankingEngine>(context, listen: false);
    final myId = engine.currentUserId;
    final invitees = _inviteableParticipants(myId);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151515),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Invite Co-Host',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                  'Only other real players who joined this contest (not you, not demo entries).',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 16),
              Expanded(
                child: invitees.isEmpty
                    ? const Center(
                        child: Text(
                          'No other players have joined yet.\nAsk someone to join on another phone first.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        itemCount: invitees.length,
                        itemBuilder: (context, index) {
                          final entry = invitees[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                                backgroundImage:
                                    NetworkImage(entry.userAvatar)),
                            title: Text(entry.userName,
                                style: const TextStyle(color: Colors.white)),
                            subtitle: Text(
                                '${entry.countryFlag}  ·  Player',
                                style: const TextStyle(fontSize: 12)),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20)),
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                _inviteUser(entry);
                              },
                              child: const Text('Invite',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _inviteUser(ContestEntry entry) async {
    if (_entryId == null) return;
    final engine = Provider.of<RankingEngine>(context, listen: false);

    final sent = await engine.sendCoHostInvite(
      entryId: _entryId!,
      inviteeUserId: entry.userId,
      inviteeName: entry.userName,
      inviteeAvatar: entry.userAvatar,
    );

    if (!mounted) return;
    if (sent) {
      setState(() {
        _coHostEntry = entry;
        _activeInviteId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Live invite sent to ${entry.userName}. They must tap Join as Co-Host on their phone.'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send invite. Check connection.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _selectEntry(ContestEntry entry) {
    setState(() => _selectedEntry = entry);
    Provider.of<RankingEngine>(context, listen: false).trackEntryView(entry.id);
  }

  String _formatTimestamp(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // --- BUILD METHOD ---

  @override
  Widget build(BuildContext context) {
    return Consumer<RankingEngine>(
      builder: (context, engine, child) {
        // Keep active entries synced in real time
        _allEntries = engine.entries;
        ContestEntry? hostEntry;
        if (_allEntries.isNotEmpty) {
          if (widget.entryId != null) {
            try {
              hostEntry = _allEntries.firstWhere((e) => e.id == widget.entryId);
            } catch (_) {
              hostEntry = _allEntries.first;
            }
          } else {
            hostEntry = _allEntries.first;
          }

          if (_selectedEntry == null || !_allEntries.any((e) => e.id == _selectedEntry!.id)) {
            _selectedEntry = _allEntries.first;
          } else {
            // keep reference fresh
            _selectedEntry = _allEntries.firstWhere((e) => e.id == _selectedEntry!.id);
          }
        }

        final showHostCam = !_isCoHostConnected ||
            _cameraView == CameraView.hostOnly ||
            _cameraView == CameraView.splitBoth;
        final hasCoHostSlot =
            _isCoHostConnected || (widget.isHost && _coHostEntry != null);
        final showCoHostCam = hasCoHostSlot &&
            (_cameraView == CameraView.coHostOnly ||
                _cameraView == CameraView.splitBoth);
        final showAnalytics = _isSplitScreen;

        final bannerTitle = widget.contest.title;
        final bannerSubtitle = _isCoHostConnected
            ? '${_nameForEntry(hostEntry, engine)} · Organizer | ${_coHostEntry?.userName ?? "Co-Host"} · Co-Host'
            : '${_nameForEntry(hostEntry, engine)} · Organizer';

        return Scaffold(
          backgroundColor: const Color(0xFF070707),
          body: Stack(
            children: [
              // Main Grid Layout (Flat Row of active columns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Host Video panel (overlays span full column width)
                  if (showHostCam)
                    Expanded(
                      flex: showCoHostCam && showAnalytics 
                          ? 3 
                          : (showAnalytics ? 6 : 5),
                      child: _buildHostVideoPanel(hostEntry, _coHostEntry, engine),
                    ),

                  // Black divider line between feeds
                  if (showHostCam && showCoHostCam)
                    Container(width: 2, color: Colors.black),

                  // 2. Co-Host Video panel
                  if (showCoHostCam)
                    Expanded(
                      flex: showHostCam && showAnalytics 
                          ? 3 
                          : (showAnalytics ? 6 : 5),
                      child: _buildCoHostVideoPanel(_coHostEntry),
                    ),

                  // 3. Right Analytics Panel (split screen stats & chat)
                  if (showAnalytics)
                    Expanded(
                      flex: showHostCam && showCoHostCam ? 4 : 4,
                      child: _buildStudioAnalytics(engine),
                    ),
                ],
              ),

              if (!showAnalytics && (showHostCam || showCoHostCam))
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 56,
                  child: BroadcastBottomBanner(
                    title: bannerTitle,
                    subtitle: bannerSubtitle,
                  ),
                ),

              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirectionality: BlastDirectionality.explosive,
                  shouldLoop: false,
                  colors: const [Colors.amber, Colors.pink, Colors.purple, Colors.blue],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- CAMERA WIDGET RENDERING ---

  Widget _buildHostVideoPanel(
      ContestEntry? hostEntry, ContestEntry? coHostEntry, RankingEngine engine) {
    final hostName = _nameForEntry(hostEntry, engine);
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildCameraFeed(isHost: true, entry: hostEntry),

        Positioned(
          top: 12,
          left: 8,
          child: IconButton(
            icon: const Icon(LucideIcons.arrowLeft, color: Colors.white70, size: 24),
            onPressed: () => Navigator.pop(context),
          ),
        ),

        Positioned(top: 18, left: 60, child: _liveBadge()),

        if (_cameraView != CameraView.coHostOnly || !_isCoHostConnected)
          Positioned(
            left: 8,
            right: 8,
            bottom: 52,
            child: BroadcastNameplate(
              name: hostName,
              role: 'Organizer',
              compact: _isCoHostConnected && _isSplitScreen,
            ),
          ),

        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildLiveControlsBar(),
        ),
      ],
    );
  }

  Widget _buildCoHostVideoPanel(ContestEntry? coHostEntry) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildCameraFeed(isHost: false, entry: coHostEntry),
        Positioned(
          top: 12,
          left: 8,
          child: _liveBadge(),
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: BroadcastNameplate(
            name: coHostEntry?.userName ?? 'Co-Host',
            role: _isCoHostConnected ? 'Co-Host' : 'Awaiting join…',
            compact: true,
          ),
        ),
      ],
    );
  }

  Widget _liveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          const Text('LIVE',
              style: TextStyle(
                  color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCameraFeed({required bool isHost, ContestEntry? entry}) {
    final name = entry?.userName ?? (isHost ? 'Host' : 'Co-Host');
    final subtitle = isHost ? 'Organizer' : 'Guest';
    final avatar = entry?.userAvatar;

    // Co-host device: local feed on co-host slot, remote host on host slot
    if (widget.isCoHost) {
      if (isHost) {
        return AgoraVideoView(
          controller: VideoViewController.remote(
            rtcEngine: _engine,
            canvas: const VideoCanvas(uid: kHostAgoraUid),
            connection: RtcConnection(channelId: _channelId),
          ),
        );
      }
      if (!_isCameraOn) {
        return _buildCameraOffFallback(name: name, subtitle: 'Co-Host', avatar: avatar);
      }
      if (_localUserJoined) {
        return AgoraVideoView(
          controller: VideoViewController(
            rtcEngine: _engine,
            canvas: const VideoCanvas(uid: 0),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }

    // Host device
    if (widget.isHost) {
      if (isHost) {
        if (!_isCameraOn) {
          return _buildCameraOffFallback(name: name, subtitle: subtitle, avatar: avatar);
        }
        if (_localUserJoined) {
          return AgoraVideoView(
            controller: VideoViewController(
              rtcEngine: _engine,
              canvas: const VideoCanvas(uid: 0),
            ),
          );
        }
        return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
      }
      if (!_isCoHostConnected) {
        return _buildNoCoHostFallback(waiting: _coHostEntry != null);
      }
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: _engine,
          canvas: const VideoCanvas(uid: kCoHostAgoraUid),
          connection: RtcConnection(channelId: _channelId),
        ),
      );
    }

    // Audience / viewer
    if (isHost) {
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: _engine,
          canvas: const VideoCanvas(uid: kHostAgoraUid),
          connection: RtcConnection(channelId: _channelId),
        ),
      );
    }
    if (!_isCoHostConnected) {
      return _buildNoCoHostFallback(waiting: false);
    }
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine,
        canvas: const VideoCanvas(uid: kCoHostAgoraUid),
        connection: RtcConnection(channelId: _channelId),
        useAndroidSurfaceView: true,
      ),
    );
  }

  Widget _buildCameraOffFallback({required String name, required String subtitle, String? avatar}) {
    return Container(
      color: const Color(0xFF151515),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
              child: avatar == null ? const Icon(LucideIcons.mic, color: AppTheme.primary, size: 36) : null,
            ),
            const SizedBox(height: 10),
            Text(name,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            Text(subtitle,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildNoCoHostFallback({required bool waiting}) {
    return Container(
      color: const Color(0xFF121212),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              waiting ? LucideIcons.userPlus : LucideIcons.userMinus,
              color: Colors.white24,
              size: 36,
            ),
            const SizedBox(height: 8),
            Text(
              waiting
                  ? 'Invite a co-host\n(they join from their phone)'
                  : 'No co-host on stream',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white24, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveControlsBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.88),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isBroadcaster)
            Row(
              children: [
                _buildRoundBtn(
                    icon: _isMicOn ? LucideIcons.mic : LucideIcons.micOff,
                    isActive: _isMicOn,
                    onPressed: _toggleMic),
                const SizedBox(width: 6),
                _buildRoundBtn(
                    icon: _isCameraOn ? LucideIcons.video : LucideIcons.videoOff,
                    isActive: _isCameraOn,
                    onPressed: _toggleCamera),
                const SizedBox(width: 6),
                _buildRoundBtn(
                    icon: LucideIcons.refreshCw,
                    isActive: true,
                    onPressed: _switchCamera),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                widget.isCoHost ? 'CO-HOST LIVE' : 'VIEWING MODE',
                style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1),
              ),
            ),

          const SizedBox(width: 24),
          // Layout Selectors + Fullscreen Switch
          Row(
            children: [
              _buildViewBtn(
                view: CameraView.hostOnly,
                label: 'Host',
                icon: LucideIcons.user,
              ),
              const SizedBox(width: 4),
              if (_isCoHostConnected || widget.isCoHost) ...[
                _buildViewBtn(
                  view: CameraView.coHostOnly,
                  label: 'Co-Host',
                  icon: LucideIcons.users,
                ),
                const SizedBox(width: 4),
                _buildViewBtn(
                  view: CameraView.splitBoth,
                  label: 'Split',
                  icon: LucideIcons.columns,
                ),
              ],
              const SizedBox(width: 8),
              
              // Fullscreen Panel Switch
              GestureDetector(
                onTap: () => setState(() => _isSplitScreen = !_isSplitScreen),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: !_isSplitScreen ? AppTheme.primary.withValues(alpha: 0.25) : Colors.transparent,
                    border: Border.all(
                        color: !_isSplitScreen ? AppTheme.primary : Colors.white24),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isSplitScreen ? LucideIcons.maximize : LucideIcons.minimize,
                        color: !_isSplitScreen ? AppTheme.primary : Colors.white54,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isSplitScreen ? 'FULLSCREEN' : 'SHOW PANEL',
                        style: TextStyle(
                          color: !_isSplitScreen ? AppTheme.primary : Colors.white54,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 12),

          // Co-host Invitation or Leave stream
          if (widget.isHost && !widget.isCoHost)
            GestureDetector(
              onTap: () {
                if (_isCoHostConnected) {
                  _disconnectCoHost();
                } else {
                  _showParticipantsSheet();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _isCoHostConnected
                      ? Colors.red.shade900.withValues(alpha: 0.8)
                      : const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _isCoHostConnected ? Colors.red : Colors.white24),
                ),
                child: Row(
                  children: [
                    Icon(
                        _isCoHostConnected
                            ? LucideIcons.userMinus
                            : LucideIcons.userPlus,
                        color: Colors.white,
                        size: 14),
                    const SizedBox(width: 5),
                    Text(
                      _isCoHostConnected ? "Drop Co-Host" : "Invite",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            )
          else if (widget.isCoHost)
            GestureDetector(
              onTap: () async {
                if (_entryId != null) {
                  await Provider.of<RankingEngine>(context, listen: false)
                      .endCoHostSession(_entryId!);
                }
                await _engine.leaveChannel();
                if (mounted) Navigator.pop(context);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: const Row(
                  children: [
                    Icon(LucideIcons.logOut, color: Colors.white, size: 14),
                    SizedBox(width: 5),
                    Text('Leave Co-Host',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            )
          else
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: const Row(
                  children: [
                    Icon(LucideIcons.logOut, color: Colors.white, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      "Leave",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
        ),
      ),
    );
  }

  Widget _buildRoundBtn(
      {required IconData icon,
      required bool isActive,
      required VoidCallback onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primary : const Color(0xFF1E1E1E),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 15),
      ),
    );
  }

  Widget _buildViewBtn(
      {required CameraView view, required String label, required IconData icon}) {
    final isSelected = _cameraView == view;
    return GestureDetector(
      onTap: () => setState(() => _cameraView = view),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.25) : Colors.transparent,
          border: Border.all(
              color: isSelected ? AppTheme.primary : Colors.white24),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: isSelected ? AppTheme.primary : Colors.white54, size: 12),
            const SizedBox(width: 4),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: isSelected ? AppTheme.primary : Colors.white54,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- STUDIO ANALYTICS AND REAL-TIME DATA ---

  Widget _buildStudioAnalytics(RankingEngine engine) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F13),
        border: Border(left: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Half: Selected Entry video
          Expanded(
            flex: 5,
            child: _buildSelectedEntryScreen(),
          ),
          
          // Bottom Half: Split row
          Expanded(
            flex: 5,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(right: BorderSide(color: Colors.white10)),
                    ),
                    child: _buildAudienceCountryList(engine),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      _buildLiveHeaderBlock(engine),
                      Expanded(
                        child: _buildLiveChatFeed(engine),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedEntryScreen() {
    if (_selectedEntry == null) {
      return Container(
        color: const Color(0xFF101010),
        child: const Center(
          child: Text("Select an entry to view details",
              style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            _selectedEntry!.contentUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: Colors.grey.shade900),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.6),
                  Colors.black.withValues(alpha: 0.0),
                  Colors.black.withValues(alpha: 0.8),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          // TOP LEFT LIVE BADGE
          Positioned(
            top: 8,
            left: 8,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('LIVE',
                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                const Icon(LucideIcons.flame, color: Colors.white, size: 10),
                const SizedBox(width: 4),
                Text('${_selectedEntry!.totalVotes} votes', style: const TextStyle(color: Colors.white, fontSize: 10)),
              ],
            ),
          ),
          // BOTTOM DETAILS
          Positioned(
            bottom: 8,
            left: 10,
            right: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selectedEntry!.caption.isNotEmpty ? _selectedEntry!.caption : 'Entry Details',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Row(
                      children: List.generate(5, (index) => Icon(
                        index < _selectedEntry!.averageRating.round().clamp(0, 5)
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.amber,
                        size: 12,
                      )),
                    ),
                    const SizedBox(width: 6),
                    Text('${_selectedEntry!.averageRating.toStringAsFixed(1)} (${_selectedEntry!.reviewCount} reviews)',
                        style: const TextStyle(color: Colors.white70, fontSize: 9)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveHeaderBlock(RankingEngine engine) {
    // Dynamic real-time sum of votes of all entries in the contest
    final totalVotes = _allEntries.fold(0, (sum, entry) => sum + entry.totalVotes);

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: const BoxDecoration(
        color: Color(0xFF09090C),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.red, borderRadius: BorderRadius.circular(4)),
                child: Row(
                  children: [
                    Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle)),
                    const SizedBox(width: 3),
                    const Text('LIVE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Text('TOTAL VOTES',
                  style: TextStyle(
                      color: Colors.white54, fontSize: 8, letterSpacing: 1)),
            ],
          ),
          ScaleTransition(
            scale: _pulseController,
            child: Row(
              children: [
                const Icon(LucideIcons.flame, color: Colors.amber, size: 20),
                const SizedBox(width: 4),
                Text(
                  totalVotes.toString(),
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildLiveEntrySelectorSlider() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C0E),
        border: Border(
            top: BorderSide(color: Colors.white10),
            bottom: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.0, vertical: 1.0),
            child: Text("ACTIVE ENTRIES — TAP TO SWITCH DETAILS",
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 7,
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _allEntries.length,
              itemBuilder: (context, index) {
                final entry = _allEntries[index];
                final isSelected = _selectedEntry?.id == entry.id;

                return GestureDetector(
                  onTap: () => _selectEntry(entry),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primary.withValues(alpha: 0.15)
                          : const Color(0xFF18181E),
                      border: Border.all(
                          color: isSelected ? AppTheme.primary : Colors.white12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Row(
                        children: [
                          CircleAvatar(
                              backgroundImage: NetworkImage(entry.userAvatar),
                              radius: 8),
                          const SizedBox(width: 5),
                          Text(
                            entry.userName,
                            style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudienceCountryList(RankingEngine engine) {
    final entryId = _selectedEntry?.id;
    if (entryId == null) {
      return const Center(
        child: Text('Select an entry', style: TextStyle(color: Colors.white24, fontSize: 9)),
      );
    }

    return StreamBuilder<Map<String, int>>(
      stream: engine.getAudienceByCountry(entryId),
      builder: (context, snapshot) {
        final audiencePerCountry = snapshot.data ?? {};
        final totalViewers =
            audiencePerCountry.values.fold(0, (sum, count) => sum + count);

        final List<MapEntry<String, double>> countryRatios = [];
        if (totalViewers > 0) {
          audiencePerCountry.forEach((country, viewers) {
            countryRatios.add(MapEntry(country, viewers / totalViewers));
          });
        }
        countryRatios.sort((a, b) => b.value.compareTo(a.value));

        return Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("AUDIENCE BY COUNTRY",
                      style: TextStyle(
                          color: Colors.white54,
                          fontSize: 8,
                          fontWeight: FontWeight.bold)),
                  Text("LIVE", style: TextStyle(color: Colors.white38, fontSize: 7)),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: countryRatios.isEmpty
                    ? const Center(
                        child: Text('No viewers yet',
                            style: TextStyle(color: Colors.white24, fontSize: 9)),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: countryRatios.length,
                        itemBuilder: (context, index) {
                          final item = countryRatios[index];
                          final countryName = item.key;
                          final ratio = item.value;
                          final percentage = (ratio * 100).round();
                          final flag = _flagForCountryName(countryName);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3.5),
                            child: Row(
                              children: [
                                Text(flag, style: const TextStyle(fontSize: 11)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(countryName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 9)),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: ratio,
                                      minHeight: 7,
                                      backgroundColor: Colors.white10,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        countryName == 'Tunisia'
                                            ? Colors.red
                                            : AppTheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 36,
                                  child: Text(
                                    '$percentage%',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _flagForCountryName(String countryName) {
    const nameToFlag = {
      'United States': '🇺🇸', 'Vietnam': '🇻🇳', 'China': '🇨🇳',
      'France': '🇫🇷', 'Japan': '🇯🇵', 'Australia': '🇦🇺',
      'United Kingdom': '🇬🇧', 'Spain': '🇪🇸', 'Tunisia': '🇹🇳',
      'Germany': '🇩🇪', 'Italy': '🇮🇹', 'Brazil': '🇧🇷',
      'India': '🇮🇳', 'South Korea': '🇰🇷', 'Mexico': '🇲🇽',
      'Russia': '🇷🇺', 'Canada': '🇨🇦', 'Nigeria': '🇳🇬',
      'Egypt': '🇪🇬', 'Saudi Arabia': '🇸🇦', 'UAE': '🇦🇪',
      'Morocco': '🇲🇦', 'Algeria': '🇩🇿', 'Turkey': '🇹🇷',
      'Philippines': '🇵🇭', 'Indonesia': '🇮🇩', 'Thailand': '🇹🇭',
      'South Africa': '🇿🇦', 'Lebanon': '🇱🇧', 'Other': '🌍',
    };
    return nameToFlag[countryName] ?? '🌍';
  }

  Widget _buildLiveChatFeed(RankingEngine engine) {
    if (_selectedEntry == null) {
      return const Center(child: Text("No entry selected", style: TextStyle(color: Colors.white38, fontSize: 10)));
    }

    return StreamBuilder<List<CommentModel>>(
      stream: engine.getComments(_selectedEntry!.id),
      builder: (context, snapshot) {
        final comments = snapshot.data ?? [];

        return Container(
          padding: const EdgeInsets.all(10.0),
          decoration: const BoxDecoration(
            color: Color(0xFF09090C),
            border: Border(top: BorderSide(color: Colors.white10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text("AUDIENCE CHAT (${_selectedEntry!.userName})",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 8,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 4),
                  Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: Colors.green, shape: BoxShape.circle)),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: comments.isEmpty
                    ? const Center(
                        child: Text("No messages yet. Chat live!",
                            style: TextStyle(color: Colors.white24, fontSize: 10)),
                      )
                    : ListView.builder(
                        reverse: true,
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          final message = comments[index];
                          final formattedTime = _formatTimestamp(message.timestamp);

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.white10,
                                  backgroundImage: message.userAvatar.isNotEmpty
                                      ? NetworkImage(message.userAvatar)
                                      : null,
                                  child: message.userAvatar.isEmpty
                                      ? Text(
                                          message.userName.isEmpty ? '?' : message.userName.substring(0, 1).toUpperCase(),
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(message.userName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    color: AppTheme.primary,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold)),
                                          ),
                                          Text(formattedTime,
                                              style: const TextStyle(
                                                  color: Colors.white38, fontSize: 7)),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(message.text,
                                          style: const TextStyle(
                                              color: Colors.white70, fontSize: 9)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
