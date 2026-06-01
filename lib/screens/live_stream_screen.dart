import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/entry.dart';
import '../models/comment.dart';
import '../data/firebase_service.dart';
import '../data/live_session_service.dart';
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
  // Static counter: tracks how many LiveStreamScreen instances are alive.
  // Prevents dispose from destroying the Agora singleton when a new screen
  // is about to re-use it (e.g. co-host re-invite).
  static int _activeScreenCount = 0;

  int? _remoteUid;
  bool _engineInitialized = false;
  late RtcEngine _engine;
  late ConfettiController _confettiController;
  late AnimationController _pulseController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  int? _previousTotalVotes;
  final List<_VoteParticle> _particles = [];

  final _liveSessionService = LiveSessionService();
  final TextEditingController _liveCommentController = TextEditingController();

  // Media controls (local states for Host)
  bool _isMicOn = true;
  bool _isCameraOn = true;
  bool _isFrontCamera = true;

  // Layout states
  CameraView _cameraView = CameraView.hostOnly;
  bool _isSplitScreen = true; // false = Fullscreen camera feed on screen
  bool _isCoHostConnected = false;
  bool _showChatInRightPanel = true;

  // Stream entries & details
  ContestEntry? _selectedEntry;
  ContestEntry? _coHostEntry;
  List<ContestEntry> _allEntries = [];

  String get _channelId => widget.entryId ?? widget.contest.id;
  String? get _entryId => widget.entryId;
  bool get _isBroadcaster => widget.isHost || widget.isCoHost;

  StreamSubscription? _sessionSub;
  String? _activeInviteId;

  // Guards against stale Firestore 'idle' snapshot on co-host re-invite.
  // When a co-host accepts a re-invite, the listener initially returns the
  // cached 'idle' status from before the 'live' update arrives.
  bool _hasEverBeenLive = false;
  late final DateTime _screenCreatedAt;

  @override
  void initState() {
    super.initState();
    _activeScreenCount++;
    _screenCreatedAt = DateTime.now();
    debugPrint('[LiveStream] initState — role=${widget.isHost ? "HOST" : widget.isCoHost ? "COHOST" : "VIEWER"}, activeScreens=$_activeScreenCount, entryId=${widget.entryId}');

    if (widget.isCoHost) {
      _cameraView = CameraView.splitBoth;
      _isCoHostConnected = true;
    }

    // Force Landscape Orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

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
    debugPrint('[LiveStream] _listenLiveSession started for entryId=$_entryId');
    _sessionSub = engine.watchLiveSession(_entryId!).listen((session) {
      if (!mounted) {
        debugPrint('[LiveStream] _listenLiveSession callback — NOT MOUNTED, ignoring');
        return;
      }
      if (session == null) {
        debugPrint('[LiveStream] _listenLiveSession — session is null');
        return;
      }
      final status = session['status'] as String? ?? 'idle';
      final coHostName = session['coHostName'] as String?;
      final coHostAvatar = session['coHostAvatar'] as String?;
      final coHostUserId = session['coHostUserId'] as String?;
      debugPrint('[LiveStream] _listenLiveSession — status=$status, coHostUserId=$coHostUserId, isHost=${widget.isHost}, isCoHost=${widget.isCoHost}');

      if (status == 'live' && coHostUserId != null) {
        _hasEverBeenLive = true;
        debugPrint('[LiveStream] Session LIVE — _hasEverBeenLive=true');
        setState(() {
          _isCoHostConnected = true;
          _remoteUid = widget.isHost ? kCoHostAgoraUid : (widget.isCoHost ? kHostAgoraUid : null);
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
          if (_cameraView == CameraView.hostOnly && (widget.isHost || widget.isCoHost)) {
            _cameraView = CameraView.splitBoth;
          }
        });
      } else if (status == 'idle') {
        debugPrint('[LiveStream] Session IDLE — resetting cohost state. isCoHost=${widget.isCoHost}, _hasEverBeenLive=$_hasEverBeenLive');
        setState(() {
          _isCoHostConnected = false;
          _remoteUid = null;
          _coHostEntry = null;
          _cameraView = CameraView.hostOnly;
        });
        // Kick cohost to HOME — but ONLY if they've actually been in a live
        // session before. On re-invite, Firestore's snapshot initially returns
        // the stale 'idle' value from the previous kick. We skip that stale
        // snapshot by checking _hasEverBeenLive or a 5-second grace period.
        if (widget.isCoHost) {
          final elapsed = DateTime.now().difference(_screenCreatedAt);
          if (_hasEverBeenLive || elapsed.inSeconds > 5) {
            debugPrint('[LiveStream] Co-host being kicked to HOME screen (hasEverBeenLive=$_hasEverBeenLive, elapsed=${elapsed.inMilliseconds}ms)');
            Navigator.of(context).popUntil((route) => route.isFirst);
          } else {
            debugPrint('[LiveStream] IGNORING stale idle (co-host just arrived ${elapsed.inMilliseconds}ms ago, waiting for live status)');
          }
        }
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
    debugPrint('[LiveStream] initAgora START — role=${widget.isHost ? "HOST" : widget.isCoHost ? "COHOST" : "VIEWER"}, channel=$_channelId');
    await [Permission.microphone, Permission.camera].request();

    // ── STEP 1: Clean up any previous Agora singleton state ──
    // The Agora engine is a SINGLETON. If a previous LiveStreamScreen
    // was disposed, its engine may still be in a joined/active state.
    // We MUST leave + release before re-initializing.
    _engine = createAgoraRtcEngine();
    try {
      debugPrint('[LiveStream] initAgora — cleaning up previous channel...');
      await _engine.leaveChannel();
      debugPrint('[LiveStream] initAgora — leaveChannel OK');
    } catch (e) {
      debugPrint('[LiveStream] initAgora — leaveChannel cleanup (expected if first time): $e');
    }
    try {
      debugPrint('[LiveStream] initAgora — releasing previous engine...');
      await _engine.release();
      debugPrint('[LiveStream] initAgora — release OK');
    } catch (e) {
      debugPrint('[LiveStream] initAgora — release cleanup (expected if first time): $e');
    }

    // ── STEP 2: Create fresh engine ──
    debugPrint('[LiveStream] initAgora — creating fresh engine...');
    _engine = createAgoraRtcEngine();
    await _engine.initialize(const RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    ));
    debugPrint('[LiveStream] initAgora — engine initialized');

    if (!mounted) {
      debugPrint('[LiveStream] initAgora — widget disposed during init, aborting');
      return;
    }
    setState(() => _engineInitialized = true);

    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          debugPrint('[LiveStream] Agora onJoinChannelSuccess — uid=${connection.localUid}, channel=${connection.channelId}, elapsed=$elapsed');
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint('[LiveStream] Agora onUserJoined — remoteUid=$remoteUid');
          if (!mounted) return;
          setState(() {
            if (remoteUid == kCoHostAgoraUid) {
              _remoteUid = kCoHostAgoraUid;
              _isCoHostConnected = true;
              if (widget.isHost && _cameraView == CameraView.hostOnly) {
                _cameraView = CameraView.splitBoth;
              }
            } else if (remoteUid == kHostAgoraUid && widget.isCoHost) {
              _remoteUid = kHostAgoraUid;
              if (_cameraView == CameraView.hostOnly) {
                _cameraView = CameraView.splitBoth;
              }
            }
          });
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          debugPrint('[LiveStream] Agora onUserOffline — remoteUid=$remoteUid, reason=$reason');
          if (!mounted) return;
          setState(() {
            if (remoteUid == _remoteUid) {
              _remoteUid = null;
              _isCoHostConnected = false;
              _cameraView = CameraView.hostOnly;
            }
          });
          // Kick cohost out if host goes offline → go to HOME
          if (widget.isCoHost && remoteUid == kHostAgoraUid) {
            debugPrint('[LiveStream] Host went offline — co-host navigating to HOME');
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        },
        onConnectionStateChanged: (RtcConnection connection, ConnectionStateType state, ConnectionChangedReasonType reason) {
          debugPrint('[LiveStream] Agora onConnectionStateChanged — state=$state, reason=$reason, localUid=${connection.localUid}, channelId=${connection.channelId}');
        },
        onRemoteVideoStateChanged: (RtcConnection connection, int remoteUid, RemoteVideoState state, RemoteVideoStateReason reason, int elapsed) {
          debugPrint('[LiveStream] Agora onRemoteVideoStateChanged — remoteUid=$remoteUid, state=$state, reason=$reason, elapsed=$elapsed');
        },
        onLocalVideoStateChanged: (VideoSourceType source, LocalVideoStreamState state, LocalVideoStreamReason error) {
          debugPrint('[LiveStream] Agora onLocalVideoStateChanged — source=$source, state=$state, error=$error');
        },
        onFirstRemoteVideoDecoded: (RtcConnection connection, int remoteUid, int width, int height, int elapsed) {
          debugPrint('[LiveStream] Agora onFirstRemoteVideoDecoded — remoteUid=$remoteUid, size=${width}x$height, elapsed=$elapsed');
        },
        onFirstLocalVideoFrame: (VideoSourceType source, int width, int height, int elapsed) {
          debugPrint('[LiveStream] Agora onFirstLocalVideoFrame — size=${width}x$height, elapsed=$elapsed');
        },
        onLeaveChannel: (RtcConnection connection, RtcStats stats) {
          debugPrint('[LiveStream] Agora onLeaveChannel — stats=$stats');
        },
        onError: (ErrorCodeType err, String msg) {
          debugPrint('[LiveStream] Agora onError — $err: $msg');
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

    debugPrint('[LiveStream] initAgora — joining channel=$_channelId as uid=$joinUid');
    try {
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
      debugPrint('[LiveStream] initAgora — joinChannel call succeeded');
    } catch (e) {
      debugPrint('[LiveStream] initAgora — joinChannel FAILED: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to join channel: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _activeScreenCount--;
    debugPrint('[LiveStream] dispose — role=${widget.isHost ? "HOST" : widget.isCoHost ? "COHOST" : "VIEWER"}, activeScreens=$_activeScreenCount');

    _sessionSub?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // If Host is leaving, reset the Firestore session to 'idle'
    // so the co-host's listener sees it and gets kicked to home.
    // Use LiveSessionService directly with widget.contest.id to avoid
    // _currentContestId being null in RankingEngine.
    if (widget.isHost && _entryId != null) {
      debugPrint('[LiveStream] dispose — HOST cleaning up Firestore session and comments for entry=$_entryId, contest=${widget.contest.id}');
      try {
        final liveService = LiveSessionService();
        liveService.endCoHostSession(
          contestId: widget.contest.id,
          entryId: _entryId!,
          inviteId: _activeInviteId,
        );
        liveService.clearLiveComments(widget.contest.id, _channelId);
      } catch (e) {
        debugPrint('[LiveStream] dispose — Error resetting live session: $e');
      }
    }

    // ── Agora engine cleanup ──
    // Only touch the engine if NO other LiveStreamScreen is about to use it.
    // If _activeScreenCount > 0, a new screen's initAgora() will handle cleanup.
    if (_activeScreenCount == 0 && _engineInitialized) {
      debugPrint('[LiveStream] dispose — Last screen, cleaning up Agora engine');
      try {
        _engine.leaveChannel();
      } catch (e) {
        debugPrint('[LiveStream] dispose — leaveChannel error: $e');
      }
      try {
        _engine.release();
      } catch (e) {
        debugPrint('[LiveStream] dispose — release error: $e');
      }
    } else {
      debugPrint('[LiveStream] dispose — Skipping Agora cleanup (activeScreens=$_activeScreenCount or engineInit=$_engineInitialized). initAgora of next screen will handle it.');
    }

    _liveCommentController.dispose();
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
    debugPrint('[LiveStream] _disconnectCoHost — kicking cohost, entryId=$_entryId');
    final engine = Provider.of<RankingEngine>(context, listen: false);
    await engine.endCoHostSession(_entryId!, inviteId: _activeInviteId);
    debugPrint('[LiveStream] _disconnectCoHost — Firestore session set to idle');
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

        // Check for new votes to trigger professional effects & sound
        final totalVotes = _allEntries.fold(0, (sum, entry) => sum + entry.totalVotes);
        if (_previousTotalVotes == null) {
          _previousTotalVotes = totalVotes;
        } else if (totalVotes > _previousTotalVotes!) {
          final diff = totalVotes - _previousTotalVotes!;
          _previousTotalVotes = totalVotes;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _onVoteReceived(diff);
          });
        }

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
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SafeArea(
              child: Stack(
                children: [
                // Main Grid Layout (Flat Row of active columns)
                Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Host Video panel
                          if (showHostCam)
                            Expanded(
                              flex: showAnalytics ? 3 : 5,
                              child: _buildHostVideoPanel(hostEntry, _coHostEntry, engine),
                            ),
  
                          // Divider line
                          Container(width: 2, color: Colors.black),
  
                          // 2. Co-Host Video panel OR Selected Entry Card
                          Expanded(
                            flex: showAnalytics ? 3 : 5,
                            child: showCoHostCam
                                ? _buildCoHostVideoPanel(_coHostEntry)
                                : _buildSelectedEntryScreen(engine),
                          ),
  
                          // Divider line
                          if (showAnalytics)
                            Container(width: 2, color: Colors.black),
  
                          // 3. Right Analytics Panel (split screen stats & chat)
                          if (showAnalytics)
                            Expanded(
                              flex: 4,
                              child: _buildStudioAnalytics(engine),
                            ),
                        ],
                      ),
                    ),
                     // Controls bar - always visible and padded away from system UI
                    _buildLiveControlsBar(),
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

                // Floating vote particles overlay
                ..._particles.map((p) => _buildParticleWidget(p)),
  
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
          ),
        ),
      );
      },
    );
  }

  void _onVoteReceived(int count) {
    debugPrint('[LiveStream] _onVoteReceived: $count new votes!');

    // 1. Play sound
    try {
      _audioPlayer.stop().then((_) {
        _audioPlayer.play(AssetSource('audio/vote_sound.wav'), volume: 0.85);
      });
    } catch (e) {
      debugPrint('[LiveStream] Error playing vote sound: $e');
    }

    // 2. Pulse the vote counter
    _pulseController.forward().then((_) => _pulseController.reverse());

    // 3. Play confetti!
    _confettiController.play();

    // 4. Generate particles
    final random = DateTime.now().millisecondsSinceEpoch;
    final icons = [
      LucideIcons.heart,
      LucideIcons.star,
      LucideIcons.flame,
      LucideIcons.sparkles,
      LucideIcons.thumbsUp,
    ];
    final colors = [
      Colors.pinkAccent,
      Colors.amber,
      Colors.cyanAccent,
      Colors.purpleAccent,
      Colors.redAccent,
      Colors.orangeAccent,
      Colors.greenAccent,
    ];

    // Spawn multiple particles
    setState(() {
      for (int i = 0; i < count * 4 + 4; i++) {
        if (_particles.length > 30) break; // performance cap

        final particleId = 'particle_${random}_${i}_${_particles.length}';
        final icon = icons[(random + i) % icons.length];
        final color = colors[(random + i * 2) % colors.length];
        final size = 20.0 + ((random + i * 3) % 16);

        // Randomize the starting horizontal position (mostly centered/right safe areas)
        final double leftOffsetRatio = 0.35 + (((random + i * 7) % 40) / 100.0);

        _particles.add(_VoteParticle(
          id: particleId,
          icon: icon,
          color: color,
          size: size,
          leftOffsetRatio: leftOffsetRatio,
          bottomOffset: 50.0 + ((random + i) % 30),
        ));
      }
    });
  }

  Widget _buildParticleWidget(_VoteParticle particle) {
    return Positioned(
      key: ValueKey(particle.id),
      bottom: particle.bottomOffset,
      left: MediaQuery.of(context).size.width * particle.leftOffsetRatio,
      child: Icon(
        particle.icon,
        color: particle.color,
        size: particle.size,
      )
      .animate(
        onComplete: (_) {
          setState(() {
            _particles.removeWhere((pt) => pt.id == particle.id);
          });
        },
      )
      .moveY(
        begin: 0,
        end: -280 - ((particle.leftOffsetRatio * 100) % 50),
        duration: 1600.ms,
        curve: Curves.easeOutCubic,
      )
      .moveX(
        begin: 0,
        end: ((particle.leftOffsetRatio * 1000) % 60) - 30,
        duration: 1600.ms,
        curve: Curves.easeInOutSine,
      )
      .fadeIn(duration: 150.ms)
      .scale(
        begin: const Offset(0.4, 0.4),
        end: const Offset(1.4, 1.4),
        duration: 600.ms,
        curve: Curves.easeOutBack,
      )
      .fadeOut(
        delay: 900.ms,
        duration: 700.ms,
      ),
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
            bottom: 8,
            child: BroadcastNameplate(
              name: hostName,
              role: 'Organizer',
              compact: _isCoHostConnected && _isSplitScreen,
            ),
          ),
      ],
    );
  }

  Widget _buildCoHostVideoPanel(ContestEntry? coHostEntry) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildCameraFeed(isHost: false, entry: coHostEntry),
        Positioned(top: 18, left: 60, child: _liveBadge()),
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
    if (!_engineInitialized) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    final name = entry?.userName ?? (isHost ? 'Host' : 'Co-Host');
    final subtitle = isHost ? 'Organizer' : 'Guest';
    final avatar = entry?.userAvatar;

    // Co-host device: local feed on co-host slot, remote host on host slot
    if (widget.isCoHost) {
      if (isHost) {
        // Co-host sees the host's remote feed in the host panel
        return AgoraVideoView(
          key: ValueKey('cohost_host_feed_${_channelId}_$kHostAgoraUid'),
          controller: VideoViewController.remote(
            rtcEngine: _engine,
            canvas: const VideoCanvas(uid: kHostAgoraUid),
            connection: RtcConnection(channelId: _channelId),
            useAndroidSurfaceView: true,
          ),
        );
      } else {
        // Co-host sees their own local feed in the co-host panel
        if (!_isCameraOn) {
          return _buildCameraOffFallback(name: name, subtitle: 'Co-Host', avatar: avatar);
        }
        return AgoraVideoView(
          key: ValueKey('cohost_local_feed_$_channelId'),
          controller: VideoViewController(
            rtcEngine: _engine,
            canvas: const VideoCanvas(uid: 0),
            useAndroidSurfaceView: true,
          ),
        );
      }
    }

    // Host device
    if (widget.isHost) {
      if (isHost) {
        if (!_isCameraOn) {
          return _buildCameraOffFallback(name: name, subtitle: subtitle, avatar: avatar);
        }
        return AgoraVideoView(
          key: ValueKey('host_local_feed_$_channelId'),
          controller: VideoViewController(
            rtcEngine: _engine,
            canvas: const VideoCanvas(uid: 0),
            useAndroidSurfaceView: true,
          ),
        );
      }
      if (!_isCoHostConnected) {
        return _buildNoCoHostFallback(waiting: _coHostEntry != null);
      }
      return AgoraVideoView(
        key: ValueKey('host_cohost_feed_${_channelId}_$kCoHostAgoraUid'),
        controller: VideoViewController.remote(
          rtcEngine: _engine,
          canvas: const VideoCanvas(uid: kCoHostAgoraUid),
          connection: RtcConnection(channelId: _channelId),
          useAndroidSurfaceView: true,
        ),
      );
    }

    // Audience / viewer
    if (isHost) {
      return AgoraVideoView(
        key: ValueKey('audience_host_feed_${_channelId}_$kHostAgoraUid'),
        controller: VideoViewController.remote(
          rtcEngine: _engine,
          canvas: const VideoCanvas(uid: kHostAgoraUid),
          connection: RtcConnection(channelId: _channelId),
          useAndroidSurfaceView: true,
        ),
      );
    }
    if (!_isCoHostConnected) {
      return _buildNoCoHostFallback(waiting: false);
    }
    return AgoraVideoView(
      key: ValueKey('audience_cohost_feed_${_channelId}_$kCoHostAgoraUid'),
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
          if (widget.isHost || widget.isCoHost)
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                'VIEWING MODE',
                style: TextStyle(
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
              if (widget.isHost || widget.isCoHost)
                _buildViewBtn(
                  view: CameraView.hostOnly,
                  label: 'Host',
                  icon: LucideIcons.user,
                ),
              if (widget.isHost || widget.isCoHost)
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
              const SizedBox(width: 6),
              // Toggle Chat / Selected Entry
              GestureDetector(
                onTap: () => setState(() => _showChatInRightPanel = !_showChatInRightPanel),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: !_showChatInRightPanel ? AppTheme.primary.withValues(alpha: 0.25) : Colors.transparent,
                    border: Border.all(
                        color: !_showChatInRightPanel ? AppTheme.primary : Colors.white24),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _showChatInRightPanel ? LucideIcons.image : LucideIcons.messageSquare,
                        color: !_showChatInRightPanel ? AppTheme.primary : Colors.white54,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _showChatInRightPanel ? 'SHOW ENTRY' : 'SHOW CHAT',
                        style: TextStyle(
                          color: !_showChatInRightPanel ? AppTheme.primary : Colors.white54,
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
                    SizedBox(width: 5),
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
    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    final hasCoHostSlot =
        _isCoHostConnected || (widget.isHost && _coHostEntry != null);
    final showCoHostCam = hasCoHostSlot &&
        (_cameraView == CameraView.coHostOnly ||
            _cameraView == CameraView.splitBoth);

    // If cohost is NOT active, the middle column shows the Selected Entry Card.
    // In that case, we ALWAYS show the chat feed on the right to prevent dual cards.
    final showChat = _showChatInRightPanel || !showCoHostCam;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F13),
        border: Border(left: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isKeyboardOpen)
            Expanded(
              flex: 4,
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Colors.white10)),
                ),
                child: _buildAudienceCountryList(engine),
              ),
            ),
          Expanded(
            flex: 6,
            child: showChat
                ? Column(
                    children: [
                      if (!isKeyboardOpen)
                        _buildLiveHeaderBlock(engine),
                      Expanded(
                        child: _buildLiveChatFeed(engine),
                      ),
                    ],
                  )
                : _buildSelectedEntryScreen(engine),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedEntryScreen(RankingEngine engine) {
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
              ],
            ),
          ),
          // BOTTOM DETAILS
          Positioned(
            bottom: 8,
            left: 10,
            right: 10,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
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
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
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
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            const Icon(LucideIcons.flame, color: Colors.amber, size: 11),
                            const SizedBox(width: 3),
                            Text('${_selectedEntry!.totalVotes} Votes',
                                style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 10),
                            const Icon(LucideIcons.eye, color: Colors.amber, size: 11),
                            const SizedBox(width: 3),
                            Text('${_selectedEntry!.totalVotes + 1} Views',
                                style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    final success = await engine.addVote(_selectedEntry!.id);
                    if (success) {
                      debugPrint('[LiveStream] Voted successfully for entry: ${_selectedEntry!.id}');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.4),
                          blurRadius: 6,
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.heart, color: Colors.white, size: 11),
                        const SizedBox(width: 4),
                        const Text(
                          'VOTE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      "AUDIENCE BY COUNTRY".toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 8,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    "LIVE",
                    style: TextStyle(color: Colors.white38, fontSize: 7),
                  ),
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
    return StreamBuilder<List<CommentModel>>(
      stream: _liveSessionService.watchLiveComments(widget.contest.id, _channelId),
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
                  const Expanded(
                    child: Text("LIVE STREAM CHAT",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _liveCommentController,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                      decoration: InputDecoration(
                        hintText: _isBroadcaster ? 'Answer comment...' : 'Comment live...',
                        hintStyle: const TextStyle(color: Colors.white24, fontSize: 10),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        filled: true,
                        fillColor: Colors.white12,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendLiveComment(engine),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(LucideIcons.send, color: AppTheme.primary, size: 14),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _sendLiveComment(engine),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _sendLiveComment(RankingEngine engine) {
    final text = _liveCommentController.text.trim();
    if (text.isEmpty) return;

    final profile = engine.currentUserProfile;
    final comment = CommentModel(
      id: '',
      userId: engine.currentUserId,
      userName: profile?.displayName ?? 'You',
      userAvatar: profile?.photoURL ?? 'https://i.pravatar.cc/150?u=99',
      text: text,
      timestamp: DateTime.now(),
    );

    _liveSessionService.addLiveComment(
      widget.contest.id,
      _channelId,
      comment,
    );
    _liveCommentController.clear();
    FocusScope.of(context).unfocus();
  }
}

class _VoteParticle {
  final String id;
  final IconData icon;
  final Color color;
  final double size;
  final double leftOffsetRatio;
  final double bottomOffset;

  _VoteParticle({
    required this.id,
    required this.icon,
    required this.color,
    required this.size,
    required this.leftOffsetRatio,
    this.bottomOffset = 60,
  });
}
