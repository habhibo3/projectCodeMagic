import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../theme/app_theme.dart';
import '../models/entry.dart';
import '../models/comment.dart';
import '../models/user.dart';
import '../models/station.dart';
import '../data/firebase_service.dart';
import '../data/live_session_service.dart';
import '../engine/ranking_engine.dart';
import '../widgets/live_broadcast_widgets.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:livekit_client/livekit_client.dart' hide ConnectionState;
import 'package:flutter_background/flutter_background.dart';
import '../services/station_upload_progress_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper, RTCVideoViewObjectFit;
import '../services/livekit_token_service.dart';
import '../services/agora_web_service.dart';
import '../widgets/agora_web_video_player.dart';
import '../widgets/media_content_preview.dart';

// Legacy values are retained while the old Agora implementation remains in
// this large screen. LiveKit is the active connection started in initState.
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
  final String? recordingName;

  const LiveStreamScreen({
    super.key,
    required this.contest,
    this.isHost = false,
    this.isCoHost = false,
    this.entryId,
    this.recordingName,
  });

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Retained solely so the dormant Agora cleanup block continues to compile.
  static int _activeScreenCount = 1;
  int? _remoteUid;
  bool _engineInitialized = false;
  late RtcEngine _engine;
  Room? _liveKitRoom;
  bool _liveKitInitialized = false;
  bool _webAgoraInitialized = false;
  late ConfettiController _confettiController;
  late AnimationController _pulseController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  int? _previousTotalVotes;

  final _liveSessionService = LiveSessionService();
  final TextEditingController _liveCommentController = TextEditingController();
  int _viewerCount = 0;

  // Media controls (local states for Host)
  bool _isMicOn = true;
  bool _isCameraOn = true;
  bool _isFrontCamera = true;
  bool _isScreenSharing = false;

  // Layout states
  CameraView _cameraView = CameraView.hostOnly;
  bool _isSplitScreen = true; // false = Fullscreen camera feed on screen
  bool _isCoHostConnected = false;
  bool _showChatInRightPanel = true;
  bool _isScreenShareFullScreen = false;

  // Dynamic session role tracking (updated based on actual session state)
  bool _isSessionCoHost = false; // True if current user is cohost in the session
  bool _isSessionHost = false; // True if current user is host in the session

  // Stream entries & details
  ContestEntry? _selectedEntry;
  ContestEntry? _coHostEntry;
  List<ContestEntry> _allEntries = [];
  String? _hostUserId;
  StreamSubscription? _stationVotesSub;
  int _stationTotalVotes = 0;

  String get _channelId => widget.entryId ?? (_isStationLive ? _stationId : widget.contest.id);
  String? get _entryId => widget.entryId;
  bool get _isBroadcaster => widget.isHost || widget.isCoHost;
  bool get _isStationLive => widget.contest.type == 'Station';
  String get _stationId => StationModel.normalizeId(widget.contest.id);

  // Dynamic role check based on session state (not static widget parameters)
  bool get _amIActuallyCoHost => _isSessionCoHost || widget.isCoHost;
  bool get _amIActuallyHost => _isSessionHost || widget.isHost;

  StreamSubscription? _sessionSub;
  StreamSubscription? _organizerProfileSub;
  String _organizerName = 'Organizer';
  String? _organizerAvatar;
  String? _activeInviteId;

  // Recording state
  bool _isRecording = false;
  bool _serverStationRecordingActive = false;
  DateTime? _recordingStartTime;
  Timer? _recordingTimer;
  String _recordingDuration = '00:00';
  String? _currentUserId;

  // Countdown & Celebration state
  bool _showCountdown = false;
  int _countdownValue = 10;
  Timer? _countdownTimer;
  bool _showCelebration = false;
  bool _showVoteResults = false; // Start as false - video shows first
  StreamSubscription? _countdownSub;

  // Guards against stale Firestore 'idle' snapshot on co-host re-invite.
  bool _hasEverBeenLive = false;
  late final DateTime _screenCreatedAt;

  // Set to true once the listener has seen coHostUserId != null at least once.
  bool _coHostSessionConfirmed = false;

  // Prevents double-navigation when both the button handler and Firestore
  // listener fire a pop() at the same time.
  bool _isLeaving = false;
  bool _stationEndRequested = false;

  // Timer to force host-only view if cohost disconnects but Firestore doesn't update
  Timer? _cohostDisconnectTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stationTotalVotes = widget.contest.totalVotes;
    _screenCreatedAt = DateTime.now();
    debugPrint('[LiveStream] initState — role=${widget.isHost ? "HOST" : widget.isCoHost ? "COHOST" : "VIEWER"}, activeScreens=$_activeScreenCount, entryId=${widget.entryId}');

    if (widget.isCoHost) {
      _cameraView = CameraView.splitBoth;
      _isCoHostConnected = true;
    }

    // Force Landscape Orientation (only on mobile)
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      lowerBound: 1.0,
      upperBound: 1.2,
    );

    _connectLiveKit();
    if (_isStationLive) {
      _listenStationVotes();
    }

    // Track viewer count
    if (_entryId != null) {
      _liveSessionService.incrementViewerCount(widget.contest.id, _entryId!);
      _liveSessionService.watchViewerCount(widget.contest.id, _entryId!).listen((count) {
        if (mounted) {
          setState(() => _viewerCount = count);
        }
      });
    } else if (_isStationLive) {
      if (!widget.isHost) {
        _liveSessionService.incrementStationLiveViewerCount(_stationId);
      }
      _liveSessionService.watchStationLiveViewerCount(_stationId).listen((count) {
        if (mounted) {
          setState(() => _viewerCount = count);
        }
      });
    } else {
      // Contest organizer mode - track viewer count for organizer session
      if (!widget.isHost) {
        _liveSessionService.incrementOrganizerViewerCount(widget.contest.id);
      }
      _liveSessionService.watchOrganizerViewerCount(widget.contest.id).listen((count) {
        if (mounted) {
          setState(() => _viewerCount = count);
        }
      });
    }

    // Fetch entries and make sure current contest is loaded in the engine
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final engine = Provider.of<RankingEngine>(context, listen: false);
      engine.setCurrentContest(widget.contest.id);
      _currentUserId = engine.currentUserId;

      // Fetch organizer profile name
      _organizerProfileSub = engine.watchUserProfile(widget.contest.creatorId).listen((profile) {
        if (mounted && profile != null) {
          setState(() {
            _organizerName = profile.displayName;
            _organizerAvatar = profile.photoURL;
          });
        }
      });

      if (!_isStationLive) {
        engine.loadContestEntries(widget.contest.id);
        _allEntries = engine.entries;
      }

      if (_entryId != null) {
        // Contestant mode
        try {
          _selectedEntry = _allEntries.firstWhere((e) => e.id == _entryId);
        } catch (_) {
          if (_allEntries.isNotEmpty) _selectedEntry = _allEntries.first;
        }
        engine.trackEntryView(_selectedEntry?.id ?? _entryId!);
        _listenLiveSession(engine);
        _listenCountdownControl();

        if (widget.isHost) {
          final profile = engine.currentUserProfile;
          engine.startHostSession(
            entryId: _entryId!,
            hostUserId: engine.currentUserId,
            hostName: profile?.displayName ?? 'Organizer',
            hostAvatar: profile?.photoURL ?? '',
            channelId: _entryId!,
          );
        }
      } else if (_isStationLive) {
        _selectedEntry = ContestEntry(
          id: _stationId,
          userId: widget.contest.creatorId,
          userName: widget.contest.title,
          userAvatar: _organizerAvatar ?? widget.contest.image,
          contentUrl: widget.contest.image,
          type: widget.contest.coverType,
          caption: widget.contest.title,
          totalVotes: _stationTotalVotes,
          averageRating: widget.contest.rating,
          reviewCount: widget.contest.reviewCount,
        );
        _listenOrganizerLiveSession(engine, isStation: true);

        if (widget.isHost) {
          final profile = engine.currentUserProfile;
          _liveSessionService.startStationSession(
            stationId: _stationId,
            hostUserId: engine.currentUserId,
            hostName: profile?.displayName ?? 'Organizer',
            hostAvatar: profile?.photoURL ?? '',
            channelId: _stationId,
          );
        }
      } else {
        // Contest organizer mode - default to the contest's own image & details
        _selectedEntry = ContestEntry(
          id: 'contest_${widget.contest.id}',
          userId: widget.contest.creatorId,
          userName: widget.contest.title,
          userAvatar: _organizerAvatar ?? widget.contest.image,
          contentUrl: widget.contest.image,
          type: widget.contest.coverType,
          caption: widget.contest.title,
          totalVotes: widget.contest.totalVotes,
          averageRating: widget.contest.rating,
          reviewCount: widget.contest.reviewCount,
        );
        _listenOrganizerLiveSession(engine);

        if (widget.isHost) {
          final profile = engine.currentUserProfile;
          _liveSessionService.startOrganizerSession(
            contestId: widget.contest.id,
            hostUserId: engine.currentUserId,
            hostName: profile?.displayName ?? 'Organizer',
            hostAvatar: profile?.photoURL ?? '',
            channelId: widget.contest.id,
          );
        }
      }
      if (mounted) setState(() {});
    });
  }

  void _listenStationVotes() {
    _stationVotesSub?.cancel();
    _stationVotesSub = FirebaseFirestore.instance
        .collection('stations')
        .doc(_stationId)
        .collection('live')
        .doc('session')
        .snapshots()
        .listen((snapshot) {
      if (!mounted || !snapshot.exists) return;
      final totalVotes = (snapshot.data()?['totalVotes'] as num?)?.toInt() ?? 0;
      final previous = _previousTotalVotes;

      setState(() {
        _previousTotalVotes = totalVotes;
        _stationTotalVotes = totalVotes;
        if (_selectedEntry != null) {
          _selectedEntry = _selectedEntry!.copyWith(totalVotes: totalVotes);
        }
      });

      if (previous != null && totalVotes > previous) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onVoteReceived(totalVotes - previous);
        });
      }
    });
  }

  Future<void> _castLiveVote(RankingEngine engine) async {
    final voteTargetId = _isStationLive ? _stationId : _selectedEntry?.id;
    if (voteTargetId == null) return;
    debugPrint('[LiveStream] Vote button tapped: station=$_isStationLive, target=$voteTargetId');
    final success = _isStationLive
        ? await FirebaseService().addStationVote(voteTargetId, engine.currentUserId)
        : await engine.addVote(voteTargetId);
    if (success) {
      debugPrint('[LiveStream] Voted successfully for ${_isStationLive ? 'station' : 'entry'}: $voteTargetId');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isStationLive
              ? 'Your station vote could not be registered.'
              : 'Your vote could not be registered.'),
        ),
      );
    }
  }

  void _listenOrganizerLiveSession(RankingEngine engine, {bool isStation = false}) {
    _sessionSub?.cancel();
    final sessionId = isStation ? _stationId : widget.contest.id;
    debugPrint('[LiveStream] _listenOrganizerLiveSession started for contestId=$sessionId');
    final sessionStream = isStation
        ? _liveSessionService.watchStationLiveSession(_stationId)
        : _liveSessionService.watchOrganizerLiveSession(widget.contest.id);
    _sessionSub = sessionStream.listen((session) {
      if (!mounted) return;
      if (session == null) return;

      final status = session['status'] as String?;
      final hostUserId = session['hostUserId'] as String?;
      final coHostUserId = session['coHostUserId'] as String?;
      final coHostName = session['coHostName'] as String?;
      final coHostAvatar = session['coHostAvatar'] as String?;
      debugPrint('[LiveStream] _listenOrganizerLiveSession — status=$status, coHostUserId=$coHostUserId, isHost=${widget.isHost}, isCoHost=${widget.isCoHost}, _amIActuallyCoHost=$_amIActuallyCoHost, _currentUserId=$_currentUserId');

      if (hostUserId != null) _hostUserId = hostUserId;
      if (status == 'live' && !_hasEverBeenLive) {
        setState(() => _hasEverBeenLive = true);
      }

      // Update dynamic role tracking
      if (_currentUserId != null) {
        final wasCoHost = _isSessionCoHost;
        final wasHost = _isSessionHost;
        _isSessionHost = (hostUserId == _currentUserId);
        _isSessionCoHost = (coHostUserId == _currentUserId);

        if (wasCoHost != _isSessionCoHost || wasHost != _isSessionHost) {
          debugPrint('[LiveStream] Role changed: wasHost=$wasHost -> $_isSessionHost, wasCoHost=$wasCoHost -> $_isSessionCoHost');
        }
      }

      // ── Co-host state management ──────────────────────────────────────────
      if (status == 'live' && coHostUserId != null) {
        _hasEverBeenLive = true;
        _coHostSessionConfirmed = true;
        debugPrint('[LiveStream] Session LIVE with cohost — _hasEverBeenLive=true');
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
          if (_cameraView == CameraView.hostOnly) {
            _cameraView = CameraView.splitBoth;
          }
        });
      } else if (status == 'live' && coHostUserId == null && _isCoHostConnected) {
        // Co-host left — revert to single host view for everyone
        debugPrint('[LiveStream] Organizer: cohost left, forcing host-only view for ALL users');
        setState(() {
          _isCoHostConnected = false;
          _remoteUid = null;
          _coHostEntry = null;
          _cameraView = CameraView.hostOnly;
          _coHostSessionConfirmed = false;
        });
        if (widget.isHost) {
          _updateSessionLayout();
        }
        if (_amIActuallyCoHost && !_isLeaving) {
          _isLeaving = true;
          debugPrint('[LiveStream] Organizer: cohost leaving - navigating home');
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
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

      // ── IDLE: host ended the live — kick ALL non-host users to home ────────
      // NOTE: This block MUST be independent (not inside any if/else branch)
      // so that viewers AND co-hosts are correctly redirected when the host leaves.
      if (status == 'idle') {
        setState(() {
          _isCoHostConnected = false;
          _remoteUid = null;
          _coHostEntry = null;
          _cameraView = CameraView.hostOnly;
        });

        // Only redirect after the session has actually been live (prevents stale idle on join)
        final elapsed = DateTime.now().difference(_screenCreatedAt);
        if (_hasEverBeenLive || elapsed.inSeconds > 5) {
          if (!widget.isHost && !_isLeaving) {
            // Both viewers AND co-hosts navigate home when host ends the station live
            debugPrint('[LiveStream] Station ended — non-host user navigating to HOME (isCoHost=${widget.isCoHost}, _amIActuallyCoHost=$_amIActuallyCoHost)');
            _isLeaving = true;
            Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
          }
        }
      }

      // ── Layout sync for non-hosts ─────────────────────────────────────────
      if (!widget.isHost && status != 'idle') {
        final isSplit = session['isSplitScreen'] as bool?;
        final camViewStr = session['cameraView'] as String?;
        final showChat = session['showChatInRightPanel'] as bool?;
        final screenShareFullScreen = session['isScreenShareFullScreen'] as bool?;

        setState(() {
          if (isSplit != null) {
            _isSplitScreen = isSplit;
          }
          if (camViewStr != null) {
            try {
              final synced = CameraView.values.firstWhere((e) => e.name == camViewStr);
              if (_isCoHostConnected && synced == CameraView.hostOnly) {
                _cameraView = CameraView.splitBoth;
              } else {
                _cameraView = synced;
              }
            } catch (_) {}
          }
          if (showChat != null) {
            _showChatInRightPanel = showChat;
          }
          if (screenShareFullScreen != null) {
            _isScreenShareFullScreen = screenShareFullScreen;
          }
          if (session.containsKey('selectedEntryId')) {
            final selEntryId = session['selectedEntryId'] as String?;
            if (selEntryId == null) {
              _selectedEntry = null;
            } else if (_isStationLive) {
              _selectedEntry = ContestEntry(
                id: _stationId,
                userId: widget.contest.creatorId,
                userName: widget.contest.title,
                userAvatar: _organizerAvatar ?? widget.contest.image,
                contentUrl: widget.contest.image,
                type: widget.contest.coverType,
                caption: widget.contest.title,
                totalVotes: _stationTotalVotes,
                averageRating: widget.contest.rating,
                reviewCount: widget.contest.reviewCount,
              );
            } else if (_allEntries.isNotEmpty) {
              try {
                _selectedEntry = _allEntries.firstWhere((e) => e.id == selEntryId);
              } catch (_) {}
            }
          }
        });
      }

      final startCountdown = session['startCountdown'] as bool? ?? false;
      final showVoteResults = session['showVoteResults'] as bool? ?? false;
      if (startCountdown && !_showCountdown) {
        _startCountdown();
      }
      if (showVoteResults != _showVoteResults) {
        setState(() {
          _showVoteResults = showVoteResults;
        });
      }
    });
  }

  void _listenLiveSession(RankingEngine engine) {
    if (_entryId == null) return;
    _sessionSub?.cancel();
    debugPrint('[LiveStream] _listenLiveSession started for entryId=$_entryId');
    _sessionSub = engine.watchLiveSession(_entryId!).listen((session) {
      if (!mounted) {
        return;
      }

      if (session == null) return;

      final status = session['status'] as String?;
      final hostUserId = session['hostUserId'] as String?;
      final coHostName = session['coHostName'] as String?;
      final coHostAvatar = session['coHostAvatar'] as String?;
      final coHostUserId = session['coHostUserId'] as String?;
      if (hostUserId != null) _hostUserId = hostUserId;
      debugPrint('[LiveStream] _listenLiveSession — status=$status, coHostUserId=$coHostUserId, isHost=${widget.isHost}, isCoHost=${widget.isCoHost}, _amIActuallyCoHost=$_amIActuallyCoHost, _currentUserId=$_currentUserId');

      if (status == 'live' && !_hasEverBeenLive) {
        setState(() => _hasEverBeenLive = true);
      }

      // Update dynamic role tracking
      if (_currentUserId != null) {
        final wasCoHost = _isSessionCoHost;
        final wasHost = _isSessionHost;
        _isSessionHost = (hostUserId == _currentUserId);
        _isSessionCoHost = (coHostUserId == _currentUserId);

        if (wasCoHost != _isSessionCoHost || wasHost != _isSessionHost) {
          debugPrint('[LiveStream] Role changed: wasHost=$wasHost -> $_isSessionHost, wasCoHost=$wasCoHost -> $_isSessionCoHost');
        }
      }

      if (status == 'idle') {
        // Kick cohost and viewers to HOME immediately when session goes idle
        if (_amIActuallyCoHost && !_isLeaving) {
          debugPrint('[LiveStream] Co-host kicked immediately in _listenLiveSession (amIActuallyCoHost=$_amIActuallyCoHost)');
          _isLeaving = true;
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        } else if (!widget.isHost && !widget.isCoHost && !_isLeaving) {
          debugPrint('[LiveStream] Session idle in _listenLiveSession - viewer navigating to HOME');
          _isLeaving = true;
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        } else {
          debugPrint('[LiveStream] Session idle in _listenLiveSession - not kicking (isHost=${widget.isHost}, isCoHost=${widget.isCoHost}, _isLeaving=$_isLeaving)');
        }
      }

      // Sync layout states in real-time for non-hosts
      if (!widget.isHost) {
        final isSplit = session['isSplitScreen'] as bool?;
        final camViewStr = session['cameraView'] as String?;
        final showChat = session['showChatInRightPanel'] as bool?;
        final screenShareFullScreen = session['isScreenShareFullScreen'] as bool?;
        final selEntryId = session['selectedEntryId'] as String?;

        setState(() {
          if (isSplit != null) {
            _isSplitScreen = isSplit;
          }
          if (camViewStr != null) {
            try {
              final synced = CameraView.values.firstWhere((e) => e.name == camViewStr);
              // Override to splitBoth if cohost is actually connected (for both cohost and viewers)
              if (_isCoHostConnected && synced == CameraView.hostOnly) {
                _cameraView = CameraView.splitBoth;
              } else {
                _cameraView = synced;
              }
            } catch (_) {}
          }
          if (showChat != null) {
            _showChatInRightPanel = showChat;
          }
          if (screenShareFullScreen != null) {
            _isScreenShareFullScreen = screenShareFullScreen;
          }
          if (session.containsKey('selectedEntryId')) {
            final selEntryId = session['selectedEntryId'] as String?;
            if (selEntryId == null) {
              _selectedEntry = null;
            } else if (_isStationLive) {
              _selectedEntry = ContestEntry(
                id: _stationId,
                userId: widget.contest.creatorId,
                userName: widget.contest.title,
                userAvatar: _organizerAvatar ?? widget.contest.image,
                contentUrl: widget.contest.image,
                type: widget.contest.coverType,
                caption: widget.contest.title,
                totalVotes: _stationTotalVotes,
                averageRating: widget.contest.rating,
                reviewCount: widget.contest.reviewCount,
              );
            } else if (_allEntries.isNotEmpty) {
              try {
                _selectedEntry = _allEntries.firstWhere((e) => e.id == selEntryId);
              } catch (_) {}
            }
          }
        });
      }

      final startCountdown = session['startCountdown'] as bool? ?? false;
      final showVoteResults = session['showVoteResults'] as bool? ?? false;
      if (startCountdown && !_showCountdown) {
        _startCountdown();
      }
      if (showVoteResults != _showVoteResults) {
        setState(() {
          _showVoteResults = showVoteResults;
        });
      }

      if (status == 'live' && coHostUserId != null) {
        _hasEverBeenLive = true;
        _coHostSessionConfirmed = true; // confirmed: session has a real cohost
        debugPrint('[LiveStream] Session LIVE with cohost — _hasEverBeenLive=true, forcing split screen for ALL users including viewers');
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
          // Force split screen for ALL users when cohost is present
          if (_cameraView == CameraView.hostOnly) {
            _cameraView = CameraView.splitBoth;
          }
        });
      } else if (status == 'live' && coHostUserId == null && _isCoHostConnected) {
        // Co-host left — force host-only view immediately for ALL users
        debugPrint('[LiveStream] Contestant: cohost left (coHostUserId is null), forcing host-only view for ALL users');
        setState(() {
          _isCoHostConnected = false;
          _remoteUid = null;
          _coHostEntry = null;
          _cameraView = CameraView.hostOnly;
          _coHostSessionConfirmed = false; // Reset confirmation state
        });
        // Force session layout update to sync to all viewers
        if (widget.isHost) {
          _updateSessionLayout();
        }
        // Co-host navigation: navigate to home immediately
        if (_amIActuallyCoHost && !_isLeaving) {
          _isLeaving = true;
          debugPrint('[LiveStream] Contestant: cohost leaving - navigating to home (amIActuallyCoHost=$_amIActuallyCoHost)');
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
        // Viewers and host- should see host-only view immediately
        debugPrint('[LiveStream] Contestant: forcing host-only view for all users');
      } else if (status == 'idle') {
        debugPrint('[LiveStream] Session IDLE — resetting cohost state. isCoHost=${widget.isCoHost}, _amIActuallyCoHost=$_amIActuallyCoHost, _hasEverBeenLive=$_hasEverBeenLive, isStation=$_isStationLive');
        setState(() {
          _isCoHostConnected = false;
          _remoteUid = null;
          _coHostEntry = null;
          _cameraView = CameraView.hostOnly;
        });
        // Kick cohost to HOME immediately when session goes idle
        // This handles both host ending live and cohost being dropped
        if (_amIActuallyCoHost && !_isLeaving) {
          debugPrint('[LiveStream] Co-host kicked immediately (amIActuallyCoHost=$_amIActuallyCoHost)');
          _isLeaving = true;
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        } else if (!widget.isHost && !widget.isCoHost && !_isLeaving) {
          // Viewers should also navigate to home when session goes idle
          debugPrint('[LiveStream] Session idle - viewer navigating to HOME');
          _isLeaving = true;
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        } else {
          debugPrint('[LiveStream] Session idle - not kicking (isHost=${widget.isHost}, isCoHost=${widget.isCoHost}, _isLeaving=$_isLeaving)');
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

  void _updateSessionLayout() {
    if (widget.isHost) {
      if (_isStationLive) {
        _liveSessionService.updateStationSessionLayout(
          stationId: _stationId,
          isSplitScreen: _isSplitScreen,
          cameraView: _cameraView.name,
          showChatInRightPanel: _showChatInRightPanel,
          isScreenShareFullScreen: _isScreenShareFullScreen,
        );
      } else {
        final engine = Provider.of<RankingEngine>(context, listen: false);
        engine.updateSessionLayout(
          entryId: _entryId,
          isSplitScreen: _isSplitScreen,
          cameraView: _cameraView.name,
          showChatInRightPanel: _showChatInRightPanel,
          isScreenShareFullScreen: _isScreenShareFullScreen,
          selectedEntryId: _selectedEntry?.id,
        );
      }
      final room = _liveKitRoom;
      if (room != null) {
        final state = jsonEncode({
          'type': 'recording_layout',
          'cameraView': _cameraView.name,
          'showChat': _showChatInRightPanel,
          'isSplitScreen': _isSplitScreen,
          'screenFull': _isScreenShareFullScreen,
          'entryUrl': _selectedEntry?.contentUrl,
          'entryType': _selectedEntry?.type,
        });
        room.localParticipant?.publishData(
          Uint8List.fromList(utf8.encode(state)),
          reliable: true,
        );
      }
    }
  }

  void _listenCountdownControl() {
    if (_entryId == null) return;
    _countdownSub?.cancel();

    final db = FirebaseFirestore.instance;
    _countdownSub = db
        .collection('contests')
        .doc(widget.contest.id)
        .collection('live_sessions')
        .doc(_entryId!)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      final data = snapshot.data();
      if (data == null) return;

      final startCountdown = data['startCountdown'] as bool? ?? false;
      final showVoteResults = data['showVoteResults'] as bool? ?? false;

      if (startCountdown && !_showCountdown) {
        _startCountdown();
      }

      if (showVoteResults && !_showVoteResults) {
        setState(() {
          _showVoteResults = true;
        });
      } else if (!showVoteResults && _showVoteResults) {
        setState(() {
          _showVoteResults = false;
        });
      }
    });
  }

  void _startCountdown() {
    if (_showCountdown) return;

    setState(() {
      _showCountdown = true;
      _countdownValue = 10;
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _countdownValue--;
      });

      if (_countdownValue <= 0) {
        timer.cancel();
        _triggerCelebration();
      }
    });
  }

  void _triggerCelebration() {
    setState(() {
      _showCountdown = false;
      _showCelebration = true;
    });

    // Play celebration sound
    try {
      _audioPlayer.stop().then((_) {
        _audioPlayer.play(AssetSource('audio/Cheering SFX (Download).mp3'), volume: 1.0);
      });
    } catch (e) {
      debugPrint('[LiveStream] Error playing celebration sound: $e');
    }

    // Play confetti for 10 seconds
    _confettiController.play();

    // End celebration after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _showCelebration = false;
        });
      }
    });
  }

  Future<void> _triggerCountdownForAll() async {
    if (!widget.isHost) return;

    await _liveSessionService.setCountdownState(widget.contest.id, _entryId, true);

    // Reset after countdown completes
    Future.delayed(const Duration(seconds: 12), () {
      _liveSessionService.setCountdownState(widget.contest.id, _entryId, false);
    });
  }

  Future<void> _toggleVoteResults() async {
    if (!widget.isHost) return;

    final currentShow = _showVoteResults;
    await _liveSessionService.setVoteResultsState(widget.contest.id, _entryId, !currentShow);
  }

  void _openResultsPage() {
    // Construct full URL based on platform
    String fullUrl;

    if (kIsWeb) {
      // On web, use current origin + relative path
      fullUrl = '${Uri.base}/results.html?contestId=${widget.contest.id}';
      launchUrl(Uri.parse(fullUrl), mode: LaunchMode.externalApplication);
    } else {
      // On mobile, use your production URL (replace with your actual domain)
      // For now, construct a full URL that would work in production
      fullUrl = 'https://contest-app-94050.firebaseapp.com/results.html?contestId=${widget.contest.id}';

      // Try to open directly on mobile
      launchUrl(Uri.parse(fullUrl), mode: LaunchMode.externalApplication).then((success) {
        if (!success) {
          // If opening fails, copy to clipboard
          Clipboard.setData(ClipboardData(text: fullUrl)).then((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('URL copied to clipboard'),
                duration: const Duration(seconds: 3),
                action: SnackBarAction(
                  label: 'Open',
                  textColor: Colors.white,
                  onPressed: () {
                    launchUrl(Uri.parse(fullUrl), mode: LaunchMode.externalApplication);
                  },
                ),
              ),
            );
          });
        }
      });
    }
  }

  Future<void> _connectLiveKit({int attempt = 1}) async {
    try {
      if (_isBroadcaster) {
        await [Permission.microphone, Permission.camera].request();
      }

      final credentials = await LiveKitTokenService().getRoomCredentials(
        contestId: widget.contest.id,
        entryId: _entryId,
        userId: _currentUserId,
        isHost: widget.isHost,
        isCoHost: widget.isCoHost,
      );

      if (credentials.participantToken.isEmpty) {
        debugPrint('[LiveKit] Warning: LiveKit participantToken is empty.');
      }

      debugPrint('[LiveKit] Connecting to ${credentials.serverUrl} (attempt $attempt)...');

      final room = Room();
      room.addListener(_onLiveKitRoomChanged);
      
      // Auto-start audio and trigger UI rebuilds on remote participant & track state changes
      room.events.listen((event) async {
        debugPrint('[LiveKit] Room event received: ${event.runtimeType}');
        if (event is TrackSubscribedEvent) {
          if (event.track is AudioTrack) {
            debugPrint('[LiveKit] Remote audio track subscribed from ${event.participant.identity}');
            try { event.track.start(); } catch (e) {}
          }
          if (mounted) setState(() {});
        } else if (event is DataReceivedEvent) {
          // Handle force disconnect signal from host
          try {
            final data = utf8.decode(event.data);
            final signal = jsonDecode(data) as Map<String, dynamic>;
            if (signal['type'] == 'force_disconnect') {
              debugPrint('[LiveKit] Received force disconnect signal from host: ${signal['reason']}');
              if (signal['reason'] == 'host_ended_live' && !_isLeaving) {
                debugPrint('[LiveKit] Host ended live, disconnecting immediately');
                _isLeaving = true;
                await room.disconnect();
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              } else if (signal['reason'] == 'dropped_by_host' && _amIActuallyCoHost && !_isLeaving) {
                debugPrint('[LiveKit] Cohost dropped by host, disconnecting immediately');
                _isLeaving = true;
                await room.disconnect();
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              }
            }
          } catch (e) {
            debugPrint('[LiveKit] Error processing data signal: $e');
          }
        } else if (event is ParticipantDisconnectedEvent) {
          final participantIdentity = event.participant.identity;
          debugPrint('[LiveKit] Participant disconnected: $participantIdentity, amIActuallyHost=$_amIActuallyHost, _isCoHostConnected=$_isCoHostConnected');
          
          // Check if this is the cohost disconnecting (cohost_ prefix)
          final isCohostDisconnect = participantIdentity.startsWith('cohost_');
          // Check if this is the host disconnecting (host_ prefix)
          final isHostDisconnect = participantIdentity.startsWith('host_');
          
          // If host and cohost disconnects, force host-only view immediately
          if (_amIActuallyHost && isCohostDisconnect && _isCoHostConnected) {
            debugPrint('[LiveKit] Host detected cohost disconnect, forcing host-only view');
            setState(() {
              _isCoHostConnected = false;
              _remoteUid = null;
              _coHostEntry = null;
              _cameraView = CameraView.hostOnly;
              _coHostSessionConfirmed = false;
            });
            _updateSessionLayout();
            // Also update Firestore to remove cohost
            _disconnectCoHost();
          }
          // If cohost and host disconnects, navigate away
          if (_amIActuallyCoHost && isHostDisconnect) {
            debugPrint('[LiveKit] Cohost detected host disconnect, navigating away');
            if (!_isLeaving) {
              _isLeaving = true;
              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
            }
          }
          // If viewer and host disconnects, navigate away
          if (!widget.isHost && !widget.isCoHost && isHostDisconnect) {
            debugPrint('[LiveKit] Viewer detected host disconnect, navigating away');
            if (!_isLeaving) {
              _isLeaving = true;
              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
            }
          }
          // Viewers disconnecting should not affect the live session
          if (participantIdentity.startsWith('viewer_')) {
            debugPrint('[LiveKit] Viewer disconnected, no action needed');
          }
          if (mounted) setState(() {});
        } else if (event is ParticipantConnectedEvent) {
          final participantIdentity = event.participant.identity;
          debugPrint('[LiveKit] Participant connected: $participantIdentity');
          
          // If cohost connects, ensure all users detect and update UI
          if (participantIdentity.startsWith('cohost_')) {
            debugPrint('[LiveKit] Cohost connected, ensuring split screen for ALL users');
            // Force UI update to show split screen for ALL users
            if (mounted) {
              setState(() {
                _isCoHostConnected = true;
                _coHostSessionConfirmed = true;
                // Force split screen regardless of user role
                if (_cameraView == CameraView.hostOnly) {
                  _cameraView = CameraView.splitBoth;
                }
              });
            }
          }
        } else if (event is TrackPublishedEvent ||
                   event is TrackUnsubscribedEvent ||
                   event is TrackMutedEvent ||
                   event is TrackUnmutedEvent) {
          if (mounted) setState(() {});
        }
      });

      await room.connect(
        credentials.serverUrl,
        credentials.participantToken,
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      ).timeout(const Duration(seconds: 45));

      // Start any existing remote audio tracks
      for (final participant in room.remoteParticipants.values) {
        for (final pub in participant.audioTrackPublications) {
          if (pub.subscribed && pub.track is AudioTrack) {
            try { pub.track?.start(); } catch(e) {}
          }
        }
      }

      final localParticipant = room.localParticipant;
      if (_isBroadcaster && credentials.canPublish && localParticipant != null) {
        await localParticipant.setCameraEnabled(true);
        await localParticipant.setMicrophoneEnabled(true);
      }

      if (!mounted) {
        room.removeListener(_onLiveKitRoomChanged);
        await room.disconnect();
        return;
      }
      setState(() {
        _liveKitRoom = room;
        _liveKitInitialized = true;
      });

      if (_isStationLive && widget.isHost) {
        unawaited(_startStationServerRecording());
        FirebaseService().setStationLiveStatus(
          widget.contest.id,
          true,
          channelId: widget.contest.id,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[LiveKit] Failed to join LiveKit room $_channelId (attempt $attempt): $error');
      if (attempt < 2 && mounted) {
        debugPrint('[LiveKit] Retrying LiveKit connection in 1.5 seconds...');
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          return _connectLiveKit(attempt: attempt + 1);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('LiveKit Connection Error: $error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _onLiveKitRoomChanged() {
    if (!mounted) return;
    setState(() {});
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

    // Web-specific initialization using Agora web SDK
    if (kIsWeb) {
      debugPrint('[LiveStream] initAgora — using web SDK');

      // Set up callback for web user-left events
      AgoraWebService.setUserLeftCallback((remoteUid) {
        debugPrint('[LiveStream] Web user-left event — remoteUid=$remoteUid');
        if (!mounted) return;

        setState(() {
          if (remoteUid == _remoteUid) {
            _remoteUid = null;
            _isCoHostConnected = false;
            _coHostEntry = null;
            _cameraView = CameraView.hostOnly;
          }
        });

        if (widget.isHost) {
          _updateSessionLayout();
          // If cohost left via Agora, also update Firestore session to idle
          if (remoteUid == kCoHostAgoraUid) {
            debugPrint('[LiveStream] Web: Co-host left via Agora, removing co-host from session');
            _disconnectCoHost();
          }
        }

        // Note: Co-host navigation is handled by Firestore listener only
        // to avoid race conditions and double-navigation
        // Kick viewers out if host goes offline
        if (!widget.isHost && !widget.isCoHost && remoteUid == kHostAgoraUid) {
          debugPrint('[LiveStream] Web: Host went offline — viewer navigating to HOME');
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      });

      final initialized = await AgoraWebService.initializeAgora(appId);
      if (!initialized) {
        debugPrint('[LiveStream] initAgora — web SDK initialization failed');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to initialize Agora web SDK. Please refresh the page.'),
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      final result = await AgoraWebService.joinChannel(
        appId: appId,
        channel: _channelId,
        userId: widget.isHost ? kHostAgoraUid : (widget.isCoHost ? kCoHostAgoraUid : 0),
        token: token,
      );

      if (result['success'] == true) {
        debugPrint('[LiveStream] initAgora — web channel joined successfully (uid=${result['uid']})');
        setState(() => _webAgoraInitialized = true);
      } else {
        debugPrint('[LiveStream] initAgora — web channel join failed: ${result['error']}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to join channel: ${result['error']}'),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
      return;
    }

    // Mobile initialization using Agora Flutter SDK
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
          if (widget.isHost) {
            _updateSessionLayout();
          }
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          debugPrint('[LiveStream] Agora onUserOffline — remoteUid=$remoteUid, reason=$reason');
          if (!mounted) return;
          setState(() {
            if (remoteUid == _remoteUid) {
              _remoteUid = null;
              _isCoHostConnected = false;
              _coHostEntry = null;
              _cameraView = CameraView.hostOnly;
            }
          });
          if (widget.isHost) {
            _updateSessionLayout();
            // If cohost left via Agora, also update Firestore session to 'idle'
            if (remoteUid == kCoHostAgoraUid) {
              debugPrint('[LiveStream] Mobile: Co-host left via Agora, removing co-host from session');
              _disconnectCoHost();
            }
          }
          // Note: Co-host navigation is handled by Firestore listener only
          // to avoid race conditions and double-navigation
          // Kick viewers out if host goes offline
          if (!widget.isHost && !widget.isCoHost && remoteUid == kHostAgoraUid) {
            debugPrint('[LiveStream] Mobile: Host went offline — viewer navigating to HOME');
            Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
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

    // Add retry logic for mobile join channel
    int joinAttempts = 0;
    const maxJoinAttempts = 3;
    bool joined = false;

    while (!joined && joinAttempts < maxJoinAttempts) {
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
        joined = true;
        debugPrint('[LiveStream] initAgora — joinChannel call succeeded');
      } catch (e) {
        joinAttempts++;
        debugPrint('[LiveStream] initAgora — joinChannel attempt $joinAttempts FAILED: $e');

        if (joinAttempts < maxJoinAttempts) {
          debugPrint('[LiveStream] Retrying join in 2 seconds...');
          await Future.delayed(const Duration(seconds: 2));
        } else {
          debugPrint('[LiveStream] initAgora — all join attempts failed');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to join channel after $maxJoinAttempts attempts: $e'),
                backgroundColor: Colors.redAccent,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    debugPrint('[LiveStream] dispose — widgetRole=${widget.isHost ? "HOST" : widget.isCoHost ? "COHOST" : "VIEWER"}, sessionRole=${_amIActuallyHost ? "HOST" : _amIActuallyCoHost ? "COHOST" : "VIEWER"}, activeScreens=$_activeScreenCount');

    _sessionSub?.cancel();
    _stationVotesSub?.cancel();
    _organizerProfileSub?.cancel();
    _countdownSub?.cancel();
    _recordingTimer?.cancel();
    _countdownTimer?.cancel();
    _cohostDisconnectTimer?.cancel();

    // 1. For station live hosts, send force disconnect signal to all users immediately
    // This ensures users are kicked immediately regardless of recording upload
    if (_amIActuallyHost && _isStationLive && _liveKitRoom != null) {
      debugPrint('[LiveStream] dispose — Station live host sending force disconnect signal to all users');
      try {
        final signal = jsonEncode({
          'type': 'force_disconnect',
          'reason': 'host_ended_live',
        });
        _liveKitRoom!.localParticipant?.publishData(
          Uint8List.fromList(utf8.encode(signal)),
          reliable: true,
        );
        debugPrint('[LiveStream] dispose — Sent force disconnect signal to all station live users');
      } catch (e) {
        debugPrint('[LiveStream] dispose — Error sending disconnect signal: $e');
      }
    }

    // 2. For cohosts, disconnect LiveKit FIRST to ensure immediate session cleanup
    if (_amIActuallyCoHost) {
      debugPrint('[LiveStream] dispose — Cohost disconnecting LiveKit first');
      final liveKitRoom = _liveKitRoom;
      if (liveKitRoom != null) {
        try {
          liveKitRoom.removeListener(_onLiveKitRoomChanged);
          final localParticipant = liveKitRoom.localParticipant;
          if (localParticipant != null) {
            unawaited(localParticipant.setCameraEnabled(false));
            unawaited(localParticipant.setMicrophoneEnabled(false));
            unawaited(localParticipant.unpublishAllTracks());
          }
          unawaited(liveKitRoom.disconnect());
          unawaited(liveKitRoom.dispose());
          debugPrint('[LiveStream] dispose — Cohost LiveKit disconnected');
        } catch (e) {
          debugPrint('[LiveStream] dispose — error during cohost LiveKit cleanup: $e');
        }
      }
    }

    // 3. Finalize active station recording if host (this happens AFTER users are kicked)
    final isSavingStationRecording = _isStationLive && widget.isHost;
    if (isSavingStationRecording) {
      debugPrint('[LiveStream] dispose — saving Station Live recording after users kicked');
      _saveStationRecording(widget.contest.id);
    } else if (_isRecording) {
      debugPrint('[LiveStream] dispose — auto-saving active contest recording');
      _stopRecording(isAutoSave: true);
    }

    // 3. Only unpublish & release tracks immediately if NOT saving station recording
    // (If saving station recording, _saveStationRecording will release tracks after reading recorded bytes)
    if (!isSavingStationRecording && !_amIActuallyCoHost) {
      final liveKitRoom = _liveKitRoom;
      if (liveKitRoom != null) {
        try {
          liveKitRoom.removeListener(_onLiveKitRoomChanged);
          final localParticipant = liveKitRoom.localParticipant;
          if (localParticipant != null) {
            unawaited(localParticipant.setCameraEnabled(false));
            unawaited(localParticipant.setMicrophoneEnabled(false));
            unawaited(localParticipant.unpublishAllTracks());
          }
          unawaited(liveKitRoom.disconnect());
          unawaited(liveKitRoom.dispose());
        } catch (e) {
          debugPrint('[LiveStream] dispose — error during LiveKit room cleanup: $e');
        }
      }

      if (kIsWeb) {
        AgoraWebService.releaseMediaDevices();
      }
    }

    // Mobile orientation cleanup
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    // 3. Reset Firestore session state
    if (_amIActuallyHost && (_isStationLive || _liveKitInitialized || _hasEverBeenLive)) {
      debugPrint('[LiveStream] dispose — HOST cleaning up Firestore session for contest=${widget.contest.id}, entryId=$_entryId, amIActuallyHost=$_amIActuallyHost');
      try {
        final liveService = LiveSessionService();
        if (_entryId != null) {
          liveService.endCoHostSession(
            contestId: widget.contest.id,
            entryId: _entryId,
            inviteId: _activeInviteId,
          );
          liveService.clearLiveComments(widget.contest.id, _channelId);
        } else if (_isStationLive) {
          _endStationLive();
          // Use the same organizer session ending as contest live to kick all users
          liveService.endOrganizerSession(widget.contest.id);
        } else {
          liveService.endOrganizerSession(widget.contest.id);
        }
      } catch (e) {
        debugPrint('[LiveStream] dispose — Error resetting live session: $e');
      }
    }

    if (_amIActuallyCoHost) {
      debugPrint('[LiveStream] dispose — COHOST leaving, removing from session (amIActuallyCoHost=$_amIActuallyCoHost)');
      try {
        final liveService = LiveSessionService();
        // Force the session update to happen immediately
        if (_isStationLive) {
          liveService.removeCoHostFromSession(
            contestId: widget.contest.id,
            entryId: _entryId,
            inviteId: _activeInviteId,
          );
        } else {
          // For contests, also remove cohost
          liveService.removeCoHostFromSession(
            contestId: widget.contest.id,
            entryId: _entryId,
            inviteId: _activeInviteId,
          );
        }
      } catch (e) {
        debugPrint('[LiveStream] dispose — Error removing cohost from session: $e');
      }
    }

    if (_entryId != null) {
      _liveSessionService.decrementViewerCount(widget.contest.id, _entryId!);
    } else if (_isStationLive && !widget.isHost) {
      _liveSessionService.decrementStationLiveViewerCount(_stationId);
    } else if (!widget.isHost) {
      // Contest organizer mode - decrement viewer count for non-host users
      _liveSessionService.decrementOrganizerViewerCount(widget.contest.id);
    } else if (_isStationLive && widget.isHost) {
      // Host should also decrement viewer count when leaving station live
      _liveSessionService.decrementStationLiveViewerCount(_stationId);
    } else if (widget.isHost) {
      // Contest organizer host should also decrement viewer count
      _liveSessionService.decrementOrganizerViewerCount(widget.contest.id);
    }

    debugPrint('[LiveStream] dispose — LiveKit room cleanup completed.');

    _liveCommentController.dispose();
    _confettiController.dispose();
    _pulseController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (widget.isHost && _isStationLive && state == AppLifecycleState.detached) {
      _endStationLive();
    }
  }

  void _endStationLive() {
    if (_stationEndRequested) return;
    _stationEndRequested = true;
    // The server observes the durable session status change and stops Egress.
    // Do not send a request from dispose: browsers cancel it while navigating.
    unawaited(_liveSessionService.endStationSession(_stationId));
    unawaited(FirebaseService().setStationLiveStatus(widget.contest.id, false));
  }

  // --- RECORDING ---

  /// Generates a filename like: mlivecast_live_2026-07-05_17-30-00
  String _buildRecordingFilename() {
    String pad(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    return 'mlivecast_live_${now.year}-${pad(now.month)}-${pad(now.day)}_${pad(now.hour)}-${pad(now.minute)}-${pad(now.second)}';
  }

  Future<void> _startStationServerRecording() async {
    debugPrint('[LiveStream] Auto-starting Station Live recording...');
    bool started = false;
    if (kIsWeb) {
      started = await AgoraWebService.startWebRecording(
        _buildRecordingFilename(),
        useBrowserCapture: true, // Capture full live broadcast tab with studio layout
      );
    } else {
      try {
        final title = _buildRecordingFilename();
        started = await FlutterScreenRecording.startRecordScreenAndAudio(
          title,
          titleNotification: "Station Live Recording",
          messageNotification: "Recording live stream...",
        );
      } catch (e) {
        debugPrint('[LiveStream] Mobile screen recording error: $e');
        started = await LiveKitTokenService().startStationLiveRecording(
          stationId: _stationId,
          title: widget.recordingName ?? '${widget.contest.title} - Live Broadcast',
          thumbnailUrl: widget.contest.image,
          hostName: _organizerName,
          hostAvatar: _organizerAvatar ?? widget.contest.image,
        );
      }
    }

    if (!mounted) return;
    if (started) {
      setState(() {
        _serverStationRecordingActive = true;
        _isRecording = true;
        _recordingStartTime = DateTime.now();
        _recordingDuration = '00:00';
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_serverStationRecordingActive || _recordingStartTime == null) return;
        final elapsed = DateTime.now().difference(_recordingStartTime!);
        final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
        final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
        setState(() => _recordingDuration = '$minutes:$seconds');
      });
      debugPrint('[LiveStream] Station Live auto-recording started successfully.');
      if (_stationEndRequested) {
        unawaited(LiveKitTokenService().stopStationLiveRecording(_stationId));
      }
      return;
    }
    debugPrint('[LiveStream] Station live auto-recording could not start.');
  }

  void _startRecording({bool stationAutoSave = false}) async {
    if (_isRecording) return;

    setState(() {
      _isRecording = true;
      _recordingStartTime = DateTime.now();
      _recordingDuration = '00:00';
    });

    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isRecording || _recordingStartTime == null) return;
      final elapsed = DateTime.now().difference(_recordingStartTime!);
      final mins = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
      final secs = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
      setState(() => _recordingDuration = '$mins:$secs');
    });

    bool success = false;
    if (kIsWeb) {
      success = await AgoraWebService.startWebRecording(
        _buildRecordingFilename(),
        useBrowserCapture: true, // Manual contest recording
      );
    } else {
      success = await LiveKitTokenService().startContestLiveRecording(
        contestId: widget.contest.id,
        entryId: widget.entryId ?? 'organizer',
        thumbnailUrl: widget.contest.image,
      );
    }

    if (success) {
      debugPrint('[LiveStream] Contest recording active.');
    } else {
      debugPrint('[LiveStream] Contest recording failed to start.');
      setState(() {
        _isRecording = false;
        _recordingStartTime = null;
      });
      _recordingTimer?.cancel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not start recording. Please try again.'),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _stopRecording({bool isAutoSave = false}) async {
    if (!_isRecording) return;
    debugPrint('[LiveStream] _stopRecording — isAutoSave=$isAutoSave');

    setState(() {
      _isRecording = false;
      _recordingStartTime = null;
      _recordingDuration = '00:00';
    });
    _recordingTimer?.cancel();
    _recordingTimer = null;

    if (kIsWeb) {
      AgoraWebService.stopWebRecording();
      if (!isAutoSave) {
        Future.delayed(const Duration(milliseconds: 600), () {
          _checkAndDownloadContestRecording();
        });
      }
    }

    if (widget.entryId != null) {
      unawaited(LiveKitTokenService().stopContestLiveRecording(widget.contest.id, widget.entryId!));
    }

    if (!isAutoSave && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recording finished! Download starting...'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _checkAndDownloadContestRecording() async {
    if (kIsWeb) {
      AgoraWebService.downloadLatestWebRecording();
      return;
    }
  }





  void _toggleRecording() {
    if (_isStationLive) return;
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  Future<void> _saveStationRecording(String stationId) async {
    // 1. MUST stop Web recording synchronously on entry BEFORE any await calls!
    if (kIsWeb) {
      AgoraWebService.stopWebRecording();
    }

    final firebaseService = FirebaseService();
    var durationSeconds = 0;
    String? videoUrl;
    var recordedVotes = 0;
    String recordingTitle = widget.recordingName ?? '${widget.contest.title} - Live Broadcast';

    if (_recordingStartTime != null) {
      durationSeconds = DateTime.now().difference(_recordingStartTime!).inSeconds;
    }
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _isRecording = false;
    _serverStationRecordingActive = false;
    _recordingStartTime = null;
    _recordingDuration = '00:00';

    try {
      final session = await FirebaseFirestore.instance
          .collection('stations')
          .doc(StationModel.normalizeId(stationId))
          .collection('live')
          .doc('session')
          .get();
      recordedVotes = (session.data()?['totalVotes'] as num?)?.toInt() ?? 0;
    } catch (error) {
      debugPrint('[LiveStream] Failed to read station live votes: $error');
    }

    if (kIsWeb) {
      try {
        Uint8List? webBytes;
        // The final MediaRecorder chunk arrives after stop(). Retry for
        // a few seconds while media stream tracks are still alive.
        for (var attempt = 0; attempt < 12; attempt++) {
          webBytes = await AgoraWebService.getLatestWebRecordingBytes();
          if (webBytes != null && webBytes.isNotEmpty) break;
          await Future.delayed(const Duration(milliseconds: 400));
        }
        if (webBytes != null && webBytes.isNotEmpty && _currentUserId != null) {
          debugPrint('[LiveStream] Uploading station recording webBytes, length=${webBytes.length} bytes...');
          StationUploadProgressService.instance.startUpload();
          videoUrl = await firebaseService.uploadStationRecordingBytes(
            stationId,
            _currentUserId!,
            webBytes,
            extension: 'webm',
            onProgress: (p) => StationUploadProgressService.instance.updateProgress(p),
          );
        } else {
          debugPrint('[LiveStream] Station recording webBytes was null or empty after retries.');
        }
      } catch (e) {
        debugPrint('[LiveStream] Failed to upload web recording bytes: $e');
      }

      // Now release media stream tracks after recorded bytes are safely extracted
      AgoraWebService.releaseMediaDevices();
    } else {
      try {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

        final savedPath = await FlutterScreenRecording.stopRecordScreen;
        debugPrint('[LiveStream] station recording saved to: $savedPath');

        // IMMEDIATELY teardown LiveKit room & release camera/mic/GPU before starting upload
        final liveKitRoom = _liveKitRoom;
        if (liveKitRoom != null) {
          try {
            liveKitRoom.removeListener(_onLiveKitRoomChanged);
            final localParticipant = liveKitRoom.localParticipant;
            if (localParticipant != null) {
              unawaited(localParticipant.setCameraEnabled(false));
              unawaited(localParticipant.setMicrophoneEnabled(false));
              unawaited(localParticipant.unpublishAllTracks());
            }
            unawaited(liveKitRoom.disconnect());
            unawaited(liveKitRoom.dispose());
            _liveKitRoom = null;
          } catch (e) {
            debugPrint('[LiveStream] Error cleaning up LiveKit room in _saveStationRecording: $e');
          }
        }

        try {
          await firebaseService.setStationLiveStatus(stationId, false);
        } catch (e) {
          debugPrint('[LiveStream] Failed to reset station live status: $e');
        }

        if (savedPath.isNotEmpty && _currentUserId != null) {
          final file = File(savedPath);
          if (await file.exists()) {
            final fileSize = await file.length();
            final fileSizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);
            debugPrint('[LiveStream] Recording file verified: $savedPath, size: $fileSizeMB MB ($fileSize bytes)');

            Map<String, dynamic> diagnostics = {};
            final diagFile = File('$savedPath.diag.json');
            if (await diagFile.exists()) {
              try {
                diagnostics = jsonDecode(await diagFile.readAsString());
                debugPrint('[LiveStream] Native Recording Diagnostics: $diagnostics');
              } catch (diagErr) {
                debugPrint('[LiveStream] Error reading diag file: $diagErr');
              }
            }

            if (fileSize > 1000) {
              StationUploadProgressService.instance.startUpload();
              videoUrl = await firebaseService.uploadStationRecording(
                stationId,
                _currentUserId!,
                file,
                onProgress: (p) => StationUploadProgressService.instance.updateProgress(p),
              );
              debugPrint('[LiveStream] Recording uploaded successfully: $videoUrl');

              // Log complete recording telemetry to Firestore
              try {
                await FirebaseFirestore.instance.collection('recording_debug_logs').add({
                  'stationId': stationId,
                  'userId': _currentUserId,
                  'timestamp': FieldValue.serverTimestamp(),
                  'videoUrl': videoUrl,
                  'fileSizeBytes': fileSize,
                  'fileSizeMB': fileSizeMB,
                  'platform': Platform.operatingSystem,
                  'diagnostics': diagnostics,
                });
              } catch (logErr) {
                debugPrint('[LiveStream] Failed to write telemetry to Firestore: $logErr');
              }
            } else {
              debugPrint('[LiveStream] Recording file too small ($fileSize bytes), aborting upload.');
            }
          } else {
            debugPrint('[LiveStream] Recording file does not exist at path: $savedPath');
          }
        }
      } catch (e) {
        debugPrint('[LiveStream] Failed to finalize station recording: $e');
      }
    }

    final validVideoUrl = (videoUrl != null && videoUrl.trim().isNotEmpty) ? videoUrl.trim() : null;

    if (validVideoUrl != null) {
      final recordedLive = RecordedLiveModel(
        id: 'recorded_${DateTime.now().millisecondsSinceEpoch}',
        stationId: stationId,
        title: recordingTitle,
        videoUrl: validVideoUrl,
        thumbnailUrl: widget.contest.image,
        recordedAt: DateTime.now(),
        duration: durationSeconds > 0 ? durationSeconds : 1,
        viewerCount: _viewerCount > 0 ? _viewerCount : 1,
        totalVotes: recordedVotes,
        hostId: widget.contest.creatorId,
        hostName: _organizerName,
        hostAvatar: _organizerAvatar ?? widget.contest.image,
      );
      try {
        await firebaseService.createRecordedLive(recordedLive);
        StationUploadProgressService.instance.completeUpload(validVideoUrl);
        debugPrint('[LiveStream] Recorded live saved to Firestore successfully with videoUrl: $validVideoUrl');
      } catch (e) {
        StationUploadProgressService.instance.failUpload(e.toString());
        debugPrint('[LiveStream] Failed to save recorded live metadata: $e');
      }
    } else {
      StationUploadProgressService.instance.failUpload('Upload completed without video file');
      debugPrint('[LiveStream] WARNING: Station recording videoUrl was empty or upload failed. Skipped creating recorded live.');
    }
  }

  void _toggleMic() async {
    setState(() => _isMicOn = !_isMicOn);
    final room = _liveKitRoom;
    if (room != null) {
      await room.localParticipant?.setMicrophoneEnabled(_isMicOn);
      return;
    }
    if (kIsWeb) {
      AgoraWebService.toggleMuteAudio(!_isMicOn);
    } else {
      await _engine.muteLocalAudioStream(!_isMicOn);
    }
  }

  void _toggleCamera() async {
    setState(() => _isCameraOn = !_isCameraOn);
    final room = _liveKitRoom;
    if (room != null) {
      await room.localParticipant?.setCameraEnabled(_isCameraOn);
      return;
    }
    if (kIsWeb) {
      AgoraWebService.toggleMuteVideo(!_isCameraOn);
    } else {
      await _engine.muteLocalVideoStream(!_isCameraOn);
    }
  }

  void _toggleScreenSharing() async {
    final room = _liveKitRoom;
    if (room != null) {
      final nextValue = !_isScreenSharing;
      try {
        if (nextValue && !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          final configured = await FlutterBackground.initialize(
            androidConfig: const FlutterBackgroundAndroidConfig(
              notificationTitle: 'Mlivecast is sharing your screen',
              notificationText: 'Screen sharing is active',
              notificationImportance: AndroidNotificationImportance.normal,
              enableWifiLock: true,
            ),
          );
          if (!configured || !await Helper.requestCapturePermission()) {
            return;
          }
          if (!FlutterBackground.isBackgroundExecutionEnabled) {
            await FlutterBackground.enableBackgroundExecution();
          }
        }
        // LiveKit publishes screen video and screen audio as separate tracks.
        // Request both so viewers hear a shared browser tab / supported device
        // playback as well as seeing it.
        await room.localParticipant?.setScreenShareEnabled(
          nextValue,
          captureScreenAudio: nextValue,
          screenShareCaptureOptions: nextValue
              ? const ScreenShareCaptureOptions(captureScreenAudio: true)
              : null,
        );
        if (mounted) setState(() => _isScreenSharing = nextValue);
        if (!nextValue &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android &&
            FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.disableBackgroundExecution();
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Screen sharing could not start: $error')),
          );
        }
      }
      return;
    }
    if (!kIsWeb) return;

    setState(() => _isScreenSharing = !_isScreenSharing);

    if (_isScreenSharing) {
      final result = await AgoraWebService.startWebScreenSharing();
      if (!result['success']) {
        setState(() => _isScreenSharing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to start screen sharing: ${result['error']}'), backgroundColor: Colors.red),
          );
        }
      }
    } else {
      final result = await AgoraWebService.stopWebScreenSharing();
      if (!result['success']) {
        setState(() => _isScreenSharing = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to stop screen sharing: ${result['error']}'), backgroundColor: Colors.red),
          );
        }
      }
      // Reset full screen when screen sharing stops
      setState(() => _isScreenShareFullScreen = false);
    }
  }

  void _toggleScreenShareFullScreen() async {
    setState(() => _isScreenShareFullScreen = !_isScreenShareFullScreen);
    _updateSessionLayout();
  }

  void _switchCamera() async {
    if (_liveKitRoom != null) {
      setState(() => _isFrontCamera = !_isFrontCamera);
      final publication = _liveKitRoom!.localParticipant
          ?.getTrackPublicationBySource(TrackSource.camera);
      final track = publication?.track;
      if (track is LocalVideoTrack) {
        await track.setCameraPosition(
          _isFrontCamera ? CameraPosition.front : CameraPosition.back,
        );
      }
      return;
    }
    if (kIsWeb) {
      debugPrint('Camera switching not supported on web.');
      return;
    }
    setState(() => _isFrontCamera = !_isFrontCamera);
    await _engine.switchCamera();
  }

  Future<void> _disconnectCoHost() async {
    // Works in both Contestant Mode (_entryId set) and Organizer Mode (_entryId null)
    debugPrint('[LiveStream] _disconnectCoHost — kicking cohost, entryId=$_entryId, inviteId=$_activeInviteId');
    
    // Force cohost to disconnect from LiveKit by sending them a signal
    if (_liveKitRoom != null) {
      try {
        // Send a data message to the cohost to force them to disconnect
        final signal = jsonEncode({
          'type': 'force_disconnect',
          'reason': 'dropped_by_host',
        });
        _liveKitRoom!.localParticipant?.publishData(
          Uint8List.fromList(utf8.encode(signal)),
          reliable: true,
        );
        debugPrint('[LiveStream] _disconnectCoHost — Sent force disconnect signal to cohost');
      } catch (e) {
        debugPrint('[LiveStream] _disconnectCoHost — Error sending disconnect signal: $e');
      }
    }
    
    // Update Firestore session
    final engine = Provider.of<RankingEngine>(context, listen: false);
    await engine.removeCoHostFromSession(_entryId, inviteId: _activeInviteId);
    debugPrint('[LiveStream] _disconnectCoHost — Firestore cohost removed, session status kept live');
    
    setState(() {
      _isCoHostConnected = false;
      _remoteUid = null;
      _coHostEntry = null;
      _cameraView = CameraView.hostOnly;
      _activeInviteId = null;
      _coHostSessionConfirmed = false;
    });
    
    // Force session layout update to sync to all viewers
    _updateSessionLayout();
    
    debugPrint('[LiveStream] _disconnectCoHost — completed, cohost should be kicked and viewers should see host-only');
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
    if (entry == null) {
      // Organizer mode - get organizer's name (loaded from creator profile stream)
      return _organizerName;
    }
    if (entry.userId == engine.currentUserId) {
      return engine.currentUserProfile?.displayName ?? entry.userName;
    }
    return entry.userName;
  }

  Future<List<UserModel>> _searchAllUsers(String query, String currentUserId) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isGreaterThanOrEqualTo: cleanQuery)
        .where('username', isLessThanOrEqualTo: '$cleanQuery\uf8ff')
        .limit(15)
        .get();

    final list = snapshot.docs
        .map((doc) => UserModel.fromFirestore(doc))
        .where((u) => u.uid != currentUserId) // Exclude current user
        .toList();
    return list;
  }

  void _showParticipantsSheet() {
    final engine = Provider.of<RankingEngine>(context, listen: false);
    final myId = engine.currentUserId;
    final invitees = _inviteableParticipants(myId);
    final searchController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151515),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final screenH = MediaQuery.of(context).size.height;
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            final isLandscape = screenH < 550 || MediaQuery.of(context).orientation == Orientation.landscape;
            final availableH = (screenH - bottomInset - 16).clamp(140.0, screenH * (isLandscape ? 0.92 : 0.75));

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SizedBox(
                height: availableH,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: isLandscape ? 10 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isLandscape) ...[
                        Row(
                          children: [
                            const Text('Invite Co-Host',
                                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 34,
                                child: TextField(
                                  controller: searchController,
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: 'Search username...',
                                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                                    prefixIcon: const Icon(LucideIcons.search, color: Colors.white38, size: 14),
                                    filled: true,
                                    fillColor: const Color(0xFF252525),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                  ),
                                  onChanged: (value) => setModalState(() {}),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(LucideIcons.x, color: Colors.white70, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ] else ...[
                        const Text('Invite Co-Host',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text(
                            'Search and invite any player by username to join your live broadcast.',
                            style: TextStyle(color: Colors.white38, fontSize: 12)),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF252525),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextField(
                            controller: searchController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Search by username...',
                              hintStyle: TextStyle(color: Colors.white38),
                              prefixIcon: Icon(LucideIcons.search, color: Colors.white38),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            onChanged: (value) => setModalState(() {}),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final searchQuery = searchController.text.trim().toLowerCase();
                        if (searchQuery.isEmpty) {
                          return invitees.isEmpty
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
                                );
                        } else {
                          return FutureBuilder<List<UserModel>>(
                            future: _searchAllUsers(searchQuery, myId),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(color: AppTheme.primary),
                                );
                              }
                              final users = snapshot.data ?? [];
                              if (users.isEmpty) {
                                return Center(
                                  child: Text(
                                    'No users found matching "@$searchQuery"',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                                  ),
                                );
                              }
                              return ListView.builder(
                                itemCount: users.length,
                                itemBuilder: (context, index) {
                                  final user = users[index];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundImage: user.photoURL.isNotEmpty
                                          ? NetworkImage(user.photoURL)
                                          : null,
                                      child: user.photoURL.isEmpty
                                          ? Text(user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?')
                                          : null,
                                    ),
                                    title: Text(user.displayName,
                                        style: const TextStyle(color: Colors.white)),
                                    subtitle: Text(
                                        '@${user.username}  ·  ${user.countryFlag} ${user.country}'),
                                    trailing: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(20)),
                                      ),
                                      onPressed: () {
                                        Navigator.pop(context);
                                        final entry = ContestEntry(
                                          id: 'invite_${user.uid}',
                                          userId: user.uid,
                                          userName: user.displayName,
                                          userAvatar: user.photoURL,
                                          countryFlag: user.countryFlag,
                                          city: user.city,
                                          country: user.country,
                                          contentUrl: '',
                                          type: 'image',
                                          caption: '',
                                        );
                                        _inviteUser(entry);
                                      },
                                      child: const Text('Invite',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              ),
              ),
            );

          },
        );
      },
    );
  }

  Future<void> _inviteUser(ContestEntry entry) async {
    final engine = Provider.of<RankingEngine>(context, listen: false);

    // In Organizer Mode (_entryId == null) we pass entryId: null so the co-host
    // joins the organizer stream (no entry), and the token service won't try to
    // look up a non-existent entry document in Firestore.
    final sent = await engine.sendCoHostInvite(
      entryId: _entryId, // null in Organizer Mode — intentional
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

  bool get _isAnyScreenSharing =>
      _isScreenSharing ||
      (_liveKitRoom != null && _liveKitScreenShareTrack() != null);

  // --- BUILD METHOD ---

  @override
  Widget build(BuildContext context) {
    return Consumer<RankingEngine>(
      builder: (context, engine, child) {
        // Keep active entries synced in real time
        _allEntries = engine.entries;

        // Check for new votes to trigger professional effects & sound
        if (!_isStationLive) {
          final totalVotes =
              _allEntries.fold(0, (sum, entry) => sum + entry.totalVotes);
          if (_previousTotalVotes == null) {
            _previousTotalVotes = totalVotes;
          } else if (totalVotes > _previousTotalVotes!) {
            final diff = totalVotes - _previousTotalVotes!;
            _previousTotalVotes = totalVotes;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _onVoteReceived(diff);
            });
          }
        }

        ContestEntry? hostEntry;
        if (widget.entryId != null) {
          if (_allEntries.isNotEmpty) {
            try {
              hostEntry = _allEntries.firstWhere((e) => e.id == widget.entryId);
            } catch (_) {
              hostEntry = _allEntries.first;
            }
          }
          if (_selectedEntry == null || !_allEntries.any((e) => e.id == _selectedEntry!.id)) {
            if (_allEntries.isNotEmpty) {
              _selectedEntry = _allEntries.firstWhere((e) => e.id == widget.entryId, orElse: () => _allEntries.first);
            }
          } else {
            _selectedEntry = _allEntries.firstWhere((e) => e.id == _selectedEntry!.id);
          }
        } else {
          // Organizer mode: host is the organizer (contest creator)
          hostEntry = null;
          // In Organizer mode, if no specific contestant entry is chosen, show the contest's own image
          if (_selectedEntry == null || _selectedEntry!.id.startsWith('contest_')) {
            _selectedEntry = ContestEntry(
              id: 'contest_${widget.contest.id}',
              userId: widget.contest.creatorId,
              userName: widget.contest.title,
              userAvatar: _organizerAvatar ?? widget.contest.image,
              contentUrl: widget.contest.image,
              type: widget.contest.coverType,
              caption: widget.contest.title,
              totalVotes: widget.contest.totalVotes,
              averageRating: widget.contest.rating,
              reviewCount: widget.contest.reviewCount,
            );
          } else if (_allEntries.any((e) => e.id == _selectedEntry!.id)) {
            _selectedEntry = _allEntries.firstWhere((e) => e.id == _selectedEntry!.id);
          }
        }

        final showHostCam = !_isCoHostConnected ||
            _cameraView == CameraView.hostOnly ||
            _cameraView == CameraView.splitBoth;
        final hasCoHostSlot =
            _isCoHostConnected && _coHostEntry != null;
        final showCoHostCam = hasCoHostSlot &&
            (_cameraView == CameraView.coHostOnly ||
                _cameraView == CameraView.splitBoth);

        // Screen share full screen mode overrides layout
        final showScreenShareFullScreen = _isAnyScreenSharing && _isScreenShareFullScreen;
        // final showAnalytics = _isSplitScreen;
        // final bannerTitle = widget.contest.title;
        // final bannerSubtitle = _isCoHostConnected
        //     ? '${_nameForEntry(hostEntry, engine)} · Organizer | ${_coHostEntry?.userName ?? "Co-Host"} · Co-Host'
        //     : '${_nameForEntry(hostEntry, engine)} · Organizer';

        return Scaffold(
          backgroundColor: const Color(0xFF070707),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SafeArea(
              child: Stack(
                children: [
                // Screen share full screen mode
                if (showScreenShareFullScreen)
                  _buildScreenShareVideo()
                else
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
                              // Keep the live-video area to one third of the
                              // studio. When both cameras are shown, they
                              // share that third equally.
                              flex: showCoHostCam ? 1 : 25,
                              child: _buildHostVideoPanel(hostEntry, _coHostEntry, engine),
                            ),

                          // Divider line 1 (only if Column 2 or Column 3 is shown)
                          if (showHostCam && (showCoHostCam || _isSplitScreen))
                            Container(width: 2, color: Colors.black),

                          // 2. Co-Host Video panel
                          if (showCoHostCam)
                            Expanded(
                              // Co-host-only already occupies one third.
                              // With the host visible, it uses half of the
                              // shared one-third video area.
                              flex: showHostCam ? 1 : 25,
                              child: _buildCoHostVideoPanel(_coHostEntry),
                            ),

                          // Divider line 2 (only if Column 3 is shown and Column 2 was shown)
                          if (_isSplitScreen && showCoHostCam)
                            Container(width: 2, color: Colors.black),

                          // 3. Right Analytics Panel (representing the rest of the screen)
                          if (_isSplitScreen)
                            Expanded(
                              // With both cameras visible, analytics takes
                              // the remaining two thirds of the screen.
                              flex: showHostCam && showCoHostCam ? 4 : 50,
                              child: _buildStudioAnalytics(engine),
                            ),
                        ],
                      ),
                    ),
                     // Controls bar - always visible and padded away from system UI
                    _buildLiveControlsBar(),
                  ],
                ),

                // Hiding the big banner to avoid overlap with video nameplates (preserved logic in comments below)
                /*
                if (!showAnalytics && (showHostCam || showCoHostCam) && !_isCoHostConnected)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 56,
                    child: BroadcastBottomBanner(
                      title: bannerTitle,
                      subtitle: bannerSubtitle,
                    ),
                  ),
                */

                // Floating REC button moved to header logic handled via _buildLiveControlsBar or equivalent

                // Countdown overlay
                if (_showCountdown)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.7),
                      child: Center(
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppTheme.primary.withValues(alpha: 0.3),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '$_countdownValue',
                              style: TextStyle(
                                fontSize: 120,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: AppTheme.primary,
                                    blurRadius: 30,
                                    offset: const Offset(0, 0),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Vote results overlay
                if (_showVoteResults)
                  Positioned.fill(
                    child: Container(
                      color: const Color(0xFF0A0A0A),
                      child: _buildVoteResultsOverlay(engine),
                    ),
                  ),

                Align(
                  alignment: Alignment.centerRight,
                  child: ConfettiWidget(
                    confettiController: _confettiController,
                    blastDirectionality: BlastDirectionality.explosive,
                    shouldLoop: false,
                    emissionFrequency: 0.05,
                    minimumSize: const Size(10, 10),
                    maximumSize: const Size(20, 20),
                    numberOfParticles: 100,
                    gravity: 0.3,
                    colors: const [
                      Color(0xFFFFD700), // Gold
                      Color(0xFFFF6B6B), // Red
                      Color(0xFF4ECDC4), // Teal
                      Color(0xFFA855F7), // Purple
                      Color(0xFFF97316), // Orange
                      Color(0xFF3B82F6), // Blue
                      Color(0xFF10B981), // Emerald
                      Color(0xFFEC4899), // Pink
                    ],
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

    // 1. Play sound (using cheering/clapping audio)
    try {
      _audioPlayer.stop().then((_) {
        _audioPlayer.play(AssetSource('audio/Cheering SFX (Download).mp3'), volume: 0.9);
      });
    } catch (e) {
      debugPrint('[LiveStream] Error playing vote sound: $e');
    }

    // 2. Pulse the vote counter
    _pulseController.forward().then((_) => _pulseController.reverse());

    // 3. Create fireworks using confetti package
    _createFireworks();
  }

  void _createFireworks() {
    // Use the confetti controller with proper configuration
    _confettiController.play();
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
            onPressed: () async {
              debugPrint('[LiveStream] Back button pressed - amIActuallyCoHost=$_amIActuallyCoHost, widget.isCoHost=${widget.isCoHost}, _isLeaving=$_isLeaving');
              if (_amIActuallyCoHost && !_isLeaving) {
                _isLeaving = true;
                debugPrint('[LiveStream] Back button pressed - cohost leaving, forcing Firestore update and navigation');
                // Force immediate Firestore update to remove cohost
                try {
                  final liveService = LiveSessionService();
                  liveService.removeCoHostFromSession(
                    contestId: widget.contest.id,
                    entryId: _entryId,
                    inviteId: _activeInviteId,
                  );
                  debugPrint('[LiveStream] Back button - Firestore cohost removal completed');
                } catch (e) {
                  debugPrint('[LiveStream] Back button - Error removing cohost from Firestore: $e');
                }
                // Disconnect from LiveKit immediately
                final room = _liveKitRoom;
                if (room != null) {
                  try {
                    await room.disconnect();
                    debugPrint('[LiveStream] Back button - LiveKit disconnected');
                  } catch (e) {
                    debugPrint('[LiveStream] Back button - Error disconnecting LiveKit: $e');
                  }
                }
                // Direct navigation to home screen without pop
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              } else {
                Navigator.pop(context);
              }
            },
          ),
        ),

        Positioned(top: 18, left: 60, child: _liveBadge()),

        Positioned(
          top: 18,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.eye, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Text(
                  _viewerCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),

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
          top: 18,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.eye, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Text(
                  _viewerCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
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
    final name = entry?.userName ?? (isHost ? _organizerName : 'Co-Host');
    final subtitle = isHost ? 'Organizer' : 'Guest';
    final avatar = entry?.userAvatar ?? (isHost ? _organizerAvatar : null);

    if (_liveKitInitialized) {
      final track = _liveKitCameraTrack(isHost: isHost);
      if (track != null) {
        return VideoTrackRenderer(
          track,
          fit: VideoViewFit.cover,
        );
      }
      if (!isHost && !_isCoHostConnected) {
        return _buildNoCoHostFallback(waiting: _coHostEntry != null);
      }
      if ((widget.isHost && isHost) || (widget.isCoHost && !isHost)) {
        if (!_isCameraOn) {
          return _buildCameraOffFallback(name: name, subtitle: subtitle, avatar: avatar);
        }
      }
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }

    // Web-specific video player
    if (kIsWeb) {
      // Co-host device: local feed on co-host slot, remote host on host slot
      if (widget.isCoHost) {
        if (isHost) {
          // Co-host sees the host's remote feed in the host panel
          if (!_webAgoraInitialized) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          return AgoraWebVideoPlayer(
            key: ValueKey('cohost_host_feed_${_channelId}_$kHostAgoraUid'),
            videoId: 'remote-video-$kHostAgoraUid',
          );
        } else {
          // Co-host sees their own local feed in the co-host panel
          if (!_isCameraOn) {
            return _buildCameraOffFallback(name: name, subtitle: 'Co-Host', avatar: avatar);
          }
          if (!_webAgoraInitialized) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          return AgoraWebVideoPlayer(
            key: ValueKey('cohost_local_feed_$_channelId'),
            videoId: 'local-video',
          );
        }
      }

      // Host device
      if (widget.isHost) {
        if (isHost) {
          if (!_isCameraOn) {
            return _buildCameraOffFallback(name: name, subtitle: subtitle, avatar: avatar);
          }
          if (!_webAgoraInitialized) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          return AgoraWebVideoPlayer(
            key: ValueKey('host_local_feed_$_channelId'),
            videoId: 'local-video',
          );
        }
        if (!_isCoHostConnected) {
          return _buildNoCoHostFallback(waiting: _coHostEntry != null);
        }
        if (!_webAgoraInitialized) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        return AgoraWebVideoPlayer(
          key: ValueKey('host_cohost_feed_${_channelId}_$kCoHostAgoraUid'),
          videoId: 'remote-video-$kCoHostAgoraUid',
        );
      }

      // Audience / viewer
      if (isHost) {
        if (!_webAgoraInitialized) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        return AgoraWebVideoPlayer(
          key: ValueKey('audience_host_feed_${_channelId}_$kHostAgoraUid'),
          videoId: 'remote-video-$kHostAgoraUid',
        );
      }
      if (!_isCoHostConnected) {
        return _buildNoCoHostFallback(waiting: false);
      }
      if (!_webAgoraInitialized) {
        return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
      }
      return AgoraWebVideoPlayer(
        key: ValueKey('audience_cohost_feed_${_channelId}_$kCoHostAgoraUid'),
        videoId: 'remote-video-$kCoHostAgoraUid',
      );
    }

    // 3. Mobile Agora Fallback
    if (!_engineInitialized) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }

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

  VideoTrack? _liveKitCameraTrack({required bool isHost}) {
    final room = _liveKitRoom;
    if (room == null) return null;

    final isLocal = (widget.isHost && isHost) || (widget.isCoHost && !isHost);
    final Participant? participant = isLocal
        ? room.localParticipant
        : _findLiveKitParticipant(isHost: isHost, room: room);
    if (participant == null) return null;
    final publications = participant.videoTrackPublications.where(
      (publication) => !publication.isScreenShare && !publication.muted,
    );
    if (publications.isEmpty) return null;
    final track = publications.first.track;
    return track is VideoTrack ? track : null;
  }

  Participant? _findLiveKitParticipant({required bool isHost, required Room room}) {
    final hostId = _hostUserId ?? widget.contest.creatorId;
    final coHostId = _coHostEntry?.userId;

    if (isHost) {
      // Look for participant with host_ prefix or hostId
      for (final participant in room.remoteParticipants.values) {
        if (participant.identity.startsWith('host_') ||
            (hostId.isNotEmpty && participant.identity.contains(hostId))) {
          return participant;
        }
      }
      // Fallback: return participant that is not cohost or viewer
      for (final participant in room.remoteParticipants.values) {
        if (!participant.identity.startsWith('cohost_') && !participant.identity.startsWith('viewer_')) {
          return participant;
        }
      }
      return null;
    } else {
      // Look for participant with cohost_ prefix or coHostId — NEVER return the Host!
      for (final participant in room.remoteParticipants.values) {
        if (participant.identity.startsWith('cohost_') ||
            (coHostId != null && coHostId.isNotEmpty && participant.identity.contains(coHostId))) {
          return participant;
        }
      }
      return null;
    }
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

  Widget _buildVoteResultsOverlay(RankingEngine engine) {
    final sortedEntries = List.from(engine.entries)..sort((a, b) => b.totalVotes.compareTo(a.totalVotes));
    final maxVotes = sortedEntries.isNotEmpty ? sortedEntries.first.totalVotes : 1;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF1A1A1A),
                Colors.black.withValues(alpha: 0.5),
              ],
            ),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.trophy, color: AppTheme.primary, size: 32),
              const SizedBox(width: 12),
              const Text(
                'FINAL RESULTS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              if (widget.isHost)
                IconButton(
                  icon: const Icon(LucideIcons.x, color: Colors.white),
                  onPressed: _toggleVoteResults,
                ),
            ],
          ),
        ),
        // Chart
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: sortedEntries.isEmpty
                ? const Center(
                    child: Text(
                      'No entries yet',
                      style: TextStyle(color: Colors.white54, fontSize: 18),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      children: sortedEntries.asMap().entries.map((entry) {
                        final index = entry.key;
                        final contestEntry = entry.value;
                        final rank = index + 1;
                        final heightPercent = maxVotes > 0 ? (contestEntry.totalVotes / maxVotes) * 100 : 0;

                        Color barColor;
                        IconData rankIcon;

                        if (rank == 1) {
                          barColor = const Color(0xFFFFD700);
                          rankIcon = LucideIcons.crown;
                        } else if (rank == 2) {
                          barColor = const Color(0xFFC0C0C0);
                          rankIcon = LucideIcons.medal;
                        } else if (rank == 3) {
                          barColor = const Color(0xFFCD7F32);
                          rankIcon = LucideIcons.medal;
                        } else {
                          barColor = AppTheme.primary;
                          rankIcon = LucideIcons.hash;
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              // Rank
                              SizedBox(
                                width: 40,
                                child: Icon(
                                  rankIcon,
                                  color: barColor,
                                  size: 24,
                                ),
                              ),
                              // Name
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      contestEntry.userName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: barColor.withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: FractionallySizedBox(
                                        widthFactor: heightPercent / 100,
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: barColor,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Votes
                              SizedBox(
                                width: 80,
                                child: Text(
                                  '${contestEntry.totalVotes}',
                                  style: TextStyle(
                                    color: barColor,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ),
      ],
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
    // Viewers see no controls bar — they have the floating REC button instead
    if (!_isBroadcaster) {
      return const SizedBox.shrink();
    }

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
            // 3 media buttons on the left (visible for both Host and Co-Host)
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
                if (kIsWeb && widget.isHost) ...[
                  const SizedBox(width: 6),
                  _buildRoundBtn(
                      icon: _isScreenSharing ? LucideIcons.monitor : LucideIcons.monitor,
                      isActive: _isScreenSharing,
                      onPressed: _toggleScreenSharing),
                ],
              ],
            ),

            // ── REC Button (visible to both Host and Co-Host) ──
            const SizedBox(width: 8),
            _buildRecordingButton(),

            if (widget.isHost) ...[
              const SizedBox(width: 24),
              // Layout Selectors (visible only for Host)
              _buildViewBtn(
                view: CameraView.hostOnly,
                label: 'Host',
                icon: LucideIcons.user,
              ),
              const SizedBox(width: 4),
              if (_isCoHostConnected) ...[
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
                onTap: () {
                  setState(() {
                    _isSplitScreen = !_isSplitScreen;
                  });
                  _updateSessionLayout();
                },
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
                onTap: () {
                  setState(() {
                    _showChatInRightPanel = !_showChatInRightPanel;
                  });
                  _updateSessionLayout();
                },
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

            const SizedBox(width: 12),

            // Live Show Controls (Countdown & Vote Results) - Host only
            if (widget.isHost) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _triggerCountdownForAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.timer, color: Colors.orange, size: 14),
                      const SizedBox(width: 5),
                      const Text(
                        "Countdown",
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _openResultsPage,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.trophy, color: Colors.amber, size: 14),
                      const SizedBox(width: 5),
                      const Text(
                        "Final Results",
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],

            const SizedBox(width: 12),

            // Action button (Invite/Drop for Host, Leave Co-Host for Co-host)
            if (_amIActuallyHost)
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
            else if (_amIActuallyCoHost)
              GestureDetector(
                onTap: () async {
                  final engine = Provider.of<RankingEngine>(context, listen: false);
                  final navigator = Navigator.of(context);
                  if (_isLeaving) return; // prevent double-tap
                  _isLeaving = true;
                  debugPrint('[LiveStream] Manual leave button pressed - amIActuallyCoHost=$_amIActuallyCoHost');
                  // Auto-save recording before leaving
                  if (_isRecording) {
                    _stopRecording(isAutoSave: false);
                    await Future.delayed(const Duration(milliseconds: 500));
                  }
                  // Force immediate Firestore update to remove cohost
                  try {
                    await engine.removeCoHostFromSession(_entryId, inviteId: _activeInviteId);
                    debugPrint('[LiveStream] Manual leave - Firestore cohost removal completed');
                  } catch (e) {
                    debugPrint('[LiveStream] Manual leave - Error removing cohost from Firestore: $e');
                  }
                  // Disconnect from LiveKit immediately
                  final room = _liveKitRoom;
                  if (room != null) {
                    try {
                      await room.disconnect();
                      debugPrint('[LiveStream] Manual leave - LiveKit disconnected');
                    } catch (e) {
                      debugPrint('[LiveStream] Manual leave - Error disconnecting LiveKit: $e');
                    }
                  }
                  // Leave the AV channel (mobile only)
                  if (!kIsWeb) {
                    try { await _engine.leaveChannel(); } catch (_) {}
                  }
                  if (mounted) {
                    debugPrint('[LiveStream] Manual leave - popping to station list');
                    navigator.popUntil((route) => route.isFirst);
                  }
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
              ),
          ],
        ),
      ),
    );
  }

  /// Animated REC button — pulsing red dot when recording, grey when idle.
  Widget _buildRecordingButton() {
    return GestureDetector(
      onTap: _toggleRecording,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _isRecording
              ? Colors.red.withValues(alpha: 0.18)
              : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isRecording ? Colors.red : Colors.white24,
            width: _isRecording ? 1.5 : 1.0,
          ),
          boxShadow: _isRecording
              ? [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.35),
                    blurRadius: 8,
                    spreadRadius: 1,
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing red dot
            if (_isRecording)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 5),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              )
              .animate(onPlay: (c) => c.repeat())
              .fadeOut(duration: 700.ms)
              .then()
              .fadeIn(duration: 700.ms)
            else
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  color: Colors.white38,
                  shape: BoxShape.circle,
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isRecording ? 'STOP REC' : 'REC',
                  style: TextStyle(
                    color: _isRecording ? Colors.red : Colors.white54,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                if (_isRecording)
                  Text(
                    _recordingDuration,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 7,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
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
      onTap: () {
        setState(() => _cameraView = view);
        _updateSessionLayout();
      },
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
    final showChat = _showChatInRightPanel;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F13),
        border: Border(left: BorderSide(color: Colors.white12)),
      ),
      child: _isAnyScreenSharing
          ? _buildScreenShareVideo() // Show screen shared video
          : showChat
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isKeyboardOpen)
                      Expanded(
                        flex: 3, // Countries take 30% of the rest of the screen
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(right: BorderSide(color: Colors.white10)),
                          ),
                          child: _buildAudienceCountryList(engine),
                        ),
                      ),
                    Expanded(
                      flex: 7, // Chat takes 70% of the rest of the screen
                      child: Column(
                        children: [
                          if (!isKeyboardOpen)
                            _buildLiveHeaderBlock(engine),
                          Expanded(
                            child: _buildLiveChatFeed(engine),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : _buildSelectedEntryScreen(engine), // Show Entry is ON, contest image takes 100% of the rest of the screen
    );
  }

  Widget _buildScreenShareVideo() {
    final liveKitScreenShare = _liveKitScreenShareTrack();
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Screen shared video
          if (liveKitScreenShare != null)
            VideoTrackRenderer(liveKitScreenShare)
          else if (kIsWeb && _webAgoraInitialized)
            AgoraWebVideoPlayer(
              key: const ValueKey('screen-share'),
              videoId: 'screen-share-video',
            ),
          // LIVE badge
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('SCREEN SHARE',
                  style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
            ),
          ),
          // Full screen button (host only)
          if (widget.isHost)
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: _toggleScreenShareFullScreen,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _isScreenShareFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  VideoTrack? _liveKitScreenShareTrack() {
    final room = _liveKitRoom;
    if (room == null) return null;
    final participants = <Participant>[
      if (room.localParticipant != null) room.localParticipant!,
      ...room.remoteParticipants.values,
    ];
    for (final participant in participants) {
      for (final publication in participant.videoTrackPublications) {
        if (publication.isScreenShare && !publication.muted) {
          final track = publication.track;
          if (track is VideoTrack) return track;
        }
      }
    }
    return null;
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
          MediaContentPreview(
            type: _selectedEntry!.type,
            contentUrl: _selectedEntry!.contentUrl,
            height: double.infinity,
            videoThumbnailMode: _selectedEntry!.type == 'video',
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
                            fontSize: 24,
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
                                size: 24,
                              )),
                            ),
                            const SizedBox(width: 12),
                            Text('${_selectedEntry!.averageRating.toStringAsFixed(1)} (${_selectedEntry!.reviewCount} reviews)',
                                style: const TextStyle(color: Colors.white70, fontSize: 18)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            const Icon(LucideIcons.flame, color: Colors.amber, size: 22),
                            const SizedBox(width: 6),
                            Text('${_selectedEntry!.totalVotes} Votes',
                                style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 20),
                            const Icon(LucideIcons.eye, color: Colors.amber, size: 22),
                            const SizedBox(width: 6),
                            Text('${_selectedEntry!.totalVotes + 1} Views',
                                style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    await _castLiveVote(engine);
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
    // Show votes for the selected entry, not total contest votes
    final entryVotes = _selectedEntry?.totalVotes ?? 0;

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
              const Text('ENTRY VOTES',
                  style: TextStyle(
                      color: Colors.white54, fontSize: 8, letterSpacing: 1)),
            ],
          ),
          Row(
            children: [
              ScaleTransition(
                scale: _pulseController,
                child: Row(
                  children: [
                    const Icon(LucideIcons.flame, color: Colors.amber, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      entryVotes.toString(),
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
              // Vote button for viewers only
              if (!widget.isHost && !widget.isCoHost) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () async {
                    await _castLiveVote(engine);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.pinkAccent, Colors.purpleAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.pinkAccent.withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.heart, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        const Text(
                          'VOTE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              // REC button for viewers — viewer-only, sits right next to Vote
              if (!widget.isHost && !widget.isCoHost) ...[
                const SizedBox(width: 8),
                _buildRecordingButton(),
              ],
            ],
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
                            style: TextStyle(color: Colors.white24, fontSize: 15)),
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
                                              color: Colors.white70, fontSize: 14)),
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
    // The recording page is a LiveKit participant, so relay new messages to
    // it. This keeps the replay conversation in sync without exposing
    // Firestore credentials in the recording page.
    final room = _liveKitRoom;
    if (room != null) {
      final message = jsonEncode({
        'type': 'recording_chat_message',
        'name': comment.userName,
        'text': comment.text,
      });
      room.localParticipant?.publishData(
        Uint8List.fromList(utf8.encode(message)),
        reliable: true,
      );
    }
    _liveCommentController.clear();
    FocusScope.of(context).unfocus();
  }
}
