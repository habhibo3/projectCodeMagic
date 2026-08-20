// Agora Web SDK Implementation
// This file provides Agora RTC functionality for web platform

console.log('agora_web.js loaded');

let agoraClient = null;
let localVideoTrack = null;
let localAudioTrack = null;
let remoteUsers = {};
let channelName = '';
let uid = null;
let sdkLoadPromise = null;

// ── Recording state ──────────────────────────────────────────────────────────
let mediaRecorder = null;
let recordedChunks = [];
let recordingFilename = 'live_recording';
let _isRecordingActive = false;
let _downloadWhenRecordingReady = false;
let recordingCaptureStream = null;
window._liveChatMessages = [];
window.addRecordingChatMessage = function(user, text) {
  if (!window._liveChatMessages) window._liveChatMessages = [];
  window._liveChatMessages.push({ user: user || 'User', text: text || '', time: Date.now() });
  if (window._liveChatMessages.length > 20) {
    window._liveChatMessages.shift();
  }
};
// ─────────────────────────────────────────────────────────────────────────────

// ── Screen sharing state ─────────────────────────────────────────────────────
let isScreenSharing = false;
let screenVideoTrack = null;
let screenAudioTrack = null;
let _onScreenSharingStateChanged = null;
// ─────────────────────────────────────────────────────────────────────────────

// Play track on a specific DOM element by ID, waiting for it to be ready
function playTrackOnElement(track, elementId) {
  const tryPlay = () => {
    const el = document.getElementById(elementId);
    if (el) {
      try {
        track.play(el);
        console.log(`Track successfully playing in element: ${elementId}`);
        return true;
      } catch (e) {
        console.error(`Error playing track in element ${elementId}:`, e);
      }
    }
    return false;
  };

  if (!tryPlay()) {
    console.log(`Element ${elementId} not found in DOM yet, waiting...`);
    const interval = setInterval(() => {
      if (tryPlay()) {
        clearInterval(interval);
      }
    }, 100);
    // cancel after 10 seconds to prevent leaks
    setTimeout(() => clearInterval(interval), 10000);
  }
}

// Global binding function called by Flutter when a video platform view mounts
function bindVideoElement(firstArg, secondArg) {
  let el = null;
  let elementId = '';
  
  if (secondArg !== undefined) {
    el = firstArg;
    elementId = secondArg;
  } else {
    elementId = firstArg;
  }
  
  console.log('bindVideoElement called for:', elementId, 'has direct element:', !!el);
  
  const tryBind = () => {
    let currentEl = el;
    if (!currentEl) {
      currentEl = document.getElementById(elementId);
    }
    
    if (!currentEl) return false;
    
    const isConnected = currentEl.isConnected !== undefined ? currentEl.isConnected : document.body.contains(currentEl);
    if (!isConnected) return false;
    
    if (elementId === 'local-video') {
      if (localVideoTrack) {
        console.log('Successfully re-bound local video track to element');
        localVideoTrack.play(currentEl);
        return true;
      }
    } else if (elementId === 'screen-share-video') {
      if (screenVideoTrack) {
        console.log('Successfully re-bound screen share video track to element');
        screenVideoTrack.play(currentEl);
        return true;
      }
    } else {
      const match = elementId.match(/^remote-video-(\d+)$/);
      if (match) {
        const uid = parseInt(match[1]);
        const user = remoteUsers[uid];
        if (user && user.videoTrack) {
          console.log('Successfully re-bound remote video track for user', uid, 'to element');
          user.videoTrack.play(currentEl);
          return true;
        }
      }
    }
    return false;
  };
  
  if (!tryBind()) {
    let attempts = 0;
    const interval = setInterval(() => {
      attempts++;
      if (tryBind() || attempts > 20) {
        clearInterval(interval);
      }
    }, 100);
  }
}


// Dynamically load Agora SDK
function loadAgoraSDK() {
  if (sdkLoadPromise) return sdkLoadPromise;
  
  console.log('Starting to load Agora SDK dynamically...');
  
  sdkLoadPromise = new Promise((resolve, reject) => {
    if (typeof AgoraRTC !== 'undefined') {
      console.log('Agora SDK already loaded');
      resolve(true);
      return;
    }
    
    const script = document.createElement('script');
    script.src = 'AgoraRTC_N-4.20.1.js';
    script.crossOrigin = 'anonymous';
    script.onload = () => {
      console.log('Agora SDK script loaded successfully, AgoraRTC type:', typeof AgoraRTC);
      if (typeof AgoraRTC !== 'undefined') {
        resolve(true);
      } else {
        console.error('Script loaded but AgoraRTC is still undefined');
        reject(new Error('AgoraRTC undefined after script load'));
      }
    };
    script.onerror = (error) => {
      console.error('Failed to load Agora SDK script:', error);
      reject(error);
    };
    
    document.head.appendChild(script);
  });
  
  return sdkLoadPromise;
}

// Create video elements in DOM
function createVideoElements() {
  // Video elements are created by Flutter's AgoraWebVideoPlayer widget
  // This function just ensures they exist and logs their status
  const localVideo = document.getElementById('local-video');
  const remoteVideo100 = document.getElementById('remote-video-100');
  const remoteVideo200 = document.getElementById('remote-video-200');
  
  console.log('Video elements check - local:', !!localVideo, 'remote-100:', !!remoteVideo100, 'remote-200:', !!remoteVideo200);
  
  if (!localVideo) {
    console.warn('local-video element not found - Flutter should create it');
  }
  if (!remoteVideo100) {
    console.warn('remote-video-100 element not found - Flutter should create it');
  }
  if (!remoteVideo200) {
    console.warn('remote-video-200 element not found - Flutter should create it');
  }
}

// Initialize Agora client
function initializeAgora(appId) {
  console.log('initializeAgora called, loading SDK first...');
  
  return new Promise(async (resolve, reject) => {
    // Clean up any existing connection & tracks (e.g. from a hot restart) to prevent connection leaks
    if (agoraClient) {
      try {
        console.log('Cleaning up previous active Agora client connection...');
        await agoraClient.leave();
      } catch (e) {
        console.warn('Error leaving previous client:', e);
      }
      agoraClient = null;
    }
    if (localAudioTrack) {
      try {
        localAudioTrack.stop();
        localAudioTrack.close();
      } catch (e) {
        console.warn('Error closing local audio track:', e);
      }
      localAudioTrack = null;
    }
    if (localVideoTrack) {
      try {
        localVideoTrack.stop();
        localVideoTrack.close();
      } catch (e) {
        console.warn('Error closing local video track:', e);
      }
      localVideoTrack = null;
    }
    remoteUsers = {};

    try {
      await loadAgoraSDK();
      console.log('SDK loaded, creating client...');
    } catch (error) {
      console.error('Failed to load SDK:', error);
      resolve(false);
      return;
    }
    
    console.log('AgoraRTC type:', typeof AgoraRTC);
    console.log('window.AgoraRTC:', window.AgoraRTC);
    
    if (typeof AgoraRTC === 'undefined') {
      console.error('Agora RTC SDK still not loaded after dynamic load');
      resolve(false);
      return;
    }
    
    createVideoElements();
    
    try {
      agoraClient = AgoraRTC.createClient({ mode: 'live', codec: 'vp8' });
      console.log('Agora client created successfully');
      resolve(true);
    } catch (error) {
      console.error('Error creating Agora client:', error);
      resolve(false);
    }
  });
}

// Join channel
async function joinChannel(appId, channel, userId, token) {
  try {
    console.log('joinChannel called with appId:', appId, 'channel:', channel, 'userId:', userId);
    
    // Clean up any existing session first
    if (agoraClient) {
      try {
        await agoraClient.leave();
        console.log('Left previous channel before joining new one');
      } catch (e) {
        console.log('No previous channel to leave:', e);
      }
      agoraClient = null;
    }
    
    if (!agoraClient) {
      const initialized = await initializeAgora(appId);
      if (!initialized) {
        throw new Error('Failed to initialize Agora client');
      }
    }
    
    channelName = channel;
    uid = userId || Math.floor(Math.random() * 10000);
    
    // Clean up existing tracks
    if (localAudioTrack) {
      localAudioTrack.stop();
      localAudioTrack.close();
      localAudioTrack = null;
    }
    if (localVideoTrack) {
      localVideoTrack.stop();
      localVideoTrack.close();
      localVideoTrack = null;
    }
    
    // Set client role dynamically based on UID
    const isBroadcaster = (uid === 100 || uid === 200);
    const role = isBroadcaster ? 'host' : 'audience';
    console.log('Setting client role to:', role);
    await agoraClient.setClientRole(role);
    
    console.log('Joining channel with uid:', uid);
    
    // Add retry logic for join operation
    let joinAttempts = 0;
    const maxJoinAttempts = 3;
    let joined = false;
    
    while (!joined && joinAttempts < maxJoinAttempts) {
      try {
        await agoraClient.join(appId, channel, token || null, uid);
        joined = true;
        console.log('Joined channel:', channel, 'with uid:', uid);
      } catch (joinError) {
        joinAttempts++;
        console.error(`Join attempt ${joinAttempts} failed:`, joinError);
        
        if (joinAttempts < maxJoinAttempts) {
          console.log(`Retrying join in 2 seconds...`);
          await new Promise(resolve => setTimeout(resolve, 2000));
        } else {
          throw joinError;
        }
      }
    }
    
    // Create and publish local tracks ONLY if broadcaster
    if (isBroadcaster) {
      console.log('Creating local tracks...');
      [localAudioTrack, localVideoTrack] = await AgoraRTC.createMicrophoneAndCameraTracks();
      console.log('Local tracks created');
      
      // Play local video
      playTrackOnElement(localVideoTrack, 'local-video');
      
      // Publish to channel
      await agoraClient.publish([localAudioTrack, localVideoTrack]);
      console.log('Local tracks published');
    }
    
    // Handle remote users
    agoraClient.on('user-published', async (user, mediaType) => {
      console.log('Remote user published:', user.uid, 'mediaType:', mediaType);
      await agoraClient.subscribe(user, mediaType);
      
      if (mediaType === 'video') {
        playTrackOnElement(user.videoTrack, 'remote-video-' + user.uid);
      }
      if (mediaType === 'audio') {
        user.audioTrack.play();
      }
      
      remoteUsers[user.uid] = user;
    });
    
    agoraClient.on('user-unpublished', (user) => {
      console.log('Remote user unpublished:', user.uid);
      delete remoteUsers[user.uid];
    });
    
    agoraClient.on('user-left', (user) => {
      console.log('Remote user left:', user.uid);
      delete remoteUsers[user.uid];
      
      // Notify Flutter about user leaving
      if (window._onUserLeft) {
        window._onUserLeft(user.uid);
      }
    });
    
    return { success: true, uid: uid };
  } catch (error) {
    console.error('Error joining channel:', error);
    return { success: false, error: error.message };
  }
}

// Leave channel
async function leaveChannel() {
  try {
    if (localAudioTrack) {
      localAudioTrack.stop();
      localAudioTrack.close();
      localAudioTrack = null;
    }
    
    if (localVideoTrack) {
      localVideoTrack.stop();
      localVideoTrack.close();
      localVideoTrack = null;
    }
    
    if (agoraClient) {
      try {
        await agoraClient.leave();
      } catch (e) {
        console.warn('Error during client.leave():', e);
      }
      agoraClient = null; // Reset client object to ensure fresh connection on next join
    }
    
    // Clear remote users
    remoteUsers = {};
    
    console.log('Left channel');
    return { success: true };
  } catch (error) {
    console.error('Error leaving channel:', error);
    return { success: false, error: error.message };
  }
}

// Toggle microphone
function toggleMuteAudio(mute) {
  if (localAudioTrack) {
    if (mute) {
      localAudioTrack.setMuted(true);
    } else {
      localAudioTrack.setMuted(false);
    }
  }
}

// Toggle camera
function toggleMuteVideo(mute) {
  if (localVideoTrack) {
    if (mute) {
      localVideoTrack.setEnabled(false);
    } else {
      localVideoTrack.setEnabled(true);
    }
  }
}

// Get client state
function getClientState() {
  return {
    isConnected: agoraClient !== null,
    hasLocalStream: localVideoTrack !== null || localAudioTrack !== null,
    remoteStreamCount: Object.keys(remoteUsers).length,
    channelName: channelName,
    uid: uid
  };
}

// Wait for SDK to load
function waitForSDK(callback, maxAttempts = 50, interval = 100) {
  console.log('waitForSDK called, attempting dynamic load...');
  
  loadAgoraSDK()
    .then(() => {
      console.log('Agora SDK loaded successfully');
      callback(true);
    })
    .catch((error) => {
      console.error('Agora SDK failed to load:', error);
      callback(false);
    });
}

// Set callback for user-left events
function setUserLeftCallback(callback) {
  console.log('setUserLeftCallback called');
  window._onUserLeft = callback;
}

// Set callback for screen sharing state changes
function setScreenSharingStateCallback(callback) {
  console.log('setScreenSharingStateCallback called');
  window._onScreenSharingStateChanged = callback;
}

// ── Screen Recording Functions ───────────────────────────────────────────────

// Collect all active video streams from video elements in the page
function _collectVideoStreams() {
  const streams = [];
  
  // Try LiveKit video elements first (for stations)
  const livekitVideos = document.querySelectorAll('video');
  livekitVideos.forEach(video => {
    if (video.srcObject && video.srcObject.getVideoTracks().length > 0) {
      // Check if this is not already in our list
      if (!streams.includes(video.srcObject)) {
        streams.push(video.srcObject);
        console.log('Found LiveKit video stream:', video);
      }
    }
  });
  
  // Fallback to Agora video elements (for contests)
  if (streams.length === 0) {
    // Local video element (host)
    const localEl = document.getElementById('local-video');
    if (localEl && localEl.srcObject) {
      streams.push(localEl.srcObject);
    } else if (localVideoTrack) {
      // Fallback: use the Agora track's media stream track directly
      try {
        const ms = new MediaStream();
        ms.addTrack(localVideoTrack.getMediaStreamTrack());
        if (localAudioTrack) ms.addTrack(localAudioTrack.getMediaStreamTrack());
        streams.push(ms);
      } catch(e) {
        console.warn('Could not get local track stream:', e);
      }
    }

    // Remote video elements (co-host)
    [100, 200].forEach(remoteUid => {
      const remoteEl = document.getElementById('remote-video-' + remoteUid);
      if (remoteEl && remoteEl.srcObject) {
        streams.push(remoteEl.srcObject);
      }
    });

    // Screen share video element (showcase screen)
    const screenEl = document.getElementById('screen-share-video');
    if (screenEl && screenEl.srcObject) {
      streams.push(screenEl.srcObject);
    } else if (screenVideoTrack) {
      // Fallback: use the screen share track directly
      try {
        const ms = new MediaStream();
        ms.addTrack(screenVideoTrack.getMediaStreamTrack());
        streams.push(ms);
      } catch(e) {
        console.warn('Could not get screen share track stream:', e);
      }
    }
  }

  return streams;
}

// Helper to locate Flutter's main rendering canvas
function _getFlutterCanvas() {
  try {
    const flutterView = document.querySelector('flutter-view');
    if (flutterView && flutterView.shadowRoot) {
      const c = flutterView.shadowRoot.querySelector('canvas');
      if (c) return c;
    }
    const canvases = Array.from(document.querySelectorAll('canvas'));
    for (const c of canvases) {
      if (c.id !== '_station_composite_recording_canvas' && c.width > 100 && c.height > 100) {
        return c;
      }
    }
  } catch(e) {}
  return null;
}

// Create a dynamic 30 FPS composite stream combining Host video, Co-Host video, Entry Media, Studio Analytics, Chat, and Audio
function _createDynamicCompositeStream() {
  const canvas = document.createElement('canvas');
  canvas.id = '_station_composite_recording_canvas';
  canvas.width = 1280;
  canvas.height = 720;
  const ctx = canvas.getContext('2d');

  let audioCtx = null;
  let audioDestination = null;
  const connectedAudioTracks = new Set();
  let canvasVideoTrack = null;
  let frameNumber = 0;

  try {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (AudioContextClass) {
      audioCtx = new AudioContextClass();
      if (audioCtx.state === 'suspended') {
        audioCtx.resume().catch(() => {});
      }
      audioDestination = audioCtx.createMediaStreamDestination();
      // Keep a silent oscillator feeding audioDestination so Chrome Opus WebAudio encoder continuously receives PCM clock frames
      try {
        const silenceOsc = audioCtx.createOscillator();
        const silenceGain = audioCtx.createGain();
        silenceGain.gain.value = 0.00001;
        silenceOsc.connect(silenceGain);
        silenceGain.connect(audioDestination);
        silenceOsc.start();
      } catch(oscErr) {}
    }
  } catch(e) {
    console.warn('AudioContext creation error:', e);
  }

  function drawFrame() {
    if (_isRecordingActive) {
      // 1. Draw background
      ctx.fillStyle = '#070707';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      // Keep one corner pixel changing so canvas capture track never stalls
      ctx.fillStyle = frameNumber++ % 2 === 0 ? '#070708' : '#070707';
      ctx.fillRect(0, 0, 1, 1);

      // 2. Query active video/audio elements for audio mixing and camera overlay
      const activeVideos = [];
      const mediaElements = document.querySelectorAll('video, audio');
      mediaElements.forEach(vid => {
        if (vid.srcObject && vid.srcObject.getVideoTracks && vid.srcObject.getVideoTracks().length > 0) {
          if (!activeVideos.includes(vid)) {
            activeVideos.push(vid);
            if (vid.paused) {
              vid.play().catch(e => console.warn('Could not play video:', e));
            }
          }
          if (audioCtx && audioCtx.state === 'suspended') {
            audioCtx.resume().catch(() => {});
          }
        }

        if (audioCtx && audioDestination && vid.srcObject && vid.srcObject.getAudioTracks) {
          try {
            const audioTracks = vid.srcObject.getAudioTracks();
            audioTracks.forEach(track => {
              if (track.enabled && !connectedAudioTracks.has(track.id)) {
                const source = audioCtx.createMediaStreamSource(new MediaStream([track]));
                source.connect(audioDestination);
                connectedAudioTracks.add(track.id);
              }
            });
          } catch(e) {}
        }
      });

      // 3. Composite full Flutter screen UI (Host/CoHost panels, Entry Media, Chat, Analytics)
      const flutterCanvas = _getFlutterCanvas();
      if (flutterCanvas && flutterCanvas.width > 0 && flutterCanvas.height > 0) {
        try {
          // Calculate left sidebar crop width if sidebar is rendered
          let leftSidebarWidth = 0;
          const sidebarEl = document.querySelector('nav, [role="navigation"], .sidebar, .nav-drawer, .app-sidebar');
          if (sidebarEl) {
            const sidebarRect = sidebarEl.getBoundingClientRect();
            const canvasRect = flutterCanvas.getBoundingClientRect();
            if (sidebarRect.width > 0 && sidebarRect.left <= canvasRect.left + 50) {
              const scaleX = flutterCanvas.width / (canvasRect.width || 1);
              leftSidebarWidth = sidebarRect.width * scaleX;
            }
          }
          if (leftSidebarWidth === 0 && window.innerWidth > 1000) {
            const canvasRect = flutterCanvas.getBoundingClientRect();
            if (canvasRect.left > 150) {
              const scaleX = flutterCanvas.width / (canvasRect.width || 1);
              leftSidebarWidth = canvasRect.left * scaleX;
            }
          }

          // Calculate bottom controls crop height (~75px)
          const canvasRect = flutterCanvas.getBoundingClientRect();
          const scaleY = flutterCanvas.height / (canvasRect.height || 1);
          const bottomBarHeight = 75 * scaleY;

          const sx = leftSidebarWidth;
          const sy = 0;
          const sw = Math.max(100, flutterCanvas.width - leftSidebarWidth);
          const sh = Math.max(100, flutterCanvas.height - bottomBarHeight);

          // Log compositor state periodically (once per second)
          if (frameNumber % 30 === 1) {
            console.log('[Recorder Compositor] flutterCanvas:', flutterCanvas.width + 'x' + flutterCanvas.height, 'sx:', Math.round(sx), 'sw:', Math.round(sw), 'sh:', Math.round(sh), 'activeVideos:', activeVideos.length);
          }

          // Draw cropped Flutter live broadcast UI onto recording canvas
          ctx.drawImage(flutterCanvas, sx, sy, sw, sh, 0, 0, canvas.width, canvas.height);

          // Composite active camera <video> elements ONLY inside the host/cohost video panel bounds (left 35% of canvas)
          activeVideos.forEach((vid, idx) => {
            try {
              const vRect = vid.getBoundingClientRect();
              const cRect = flutterCanvas.getBoundingClientRect();
              if (vRect.width > 0 && vRect.height > 0 && cRect.width > 0 && cRect.height > 0) {
                // If video is small or constrained inside host/cohost panel, draw it in its designated panel box on left side
                const scaleX = canvas.width / (cRect.width || 1);
                const scaleY = canvas.height / (cRect.height || 1);
                const relX = (vRect.left - cRect.left - (leftSidebarWidth / (flutterCanvas.width / cRect.width))) * scaleX;
                const relY = (vRect.top - cRect.top) * scaleY;
                const relW = vRect.width * scaleX;
                const relH = vRect.height * scaleY;

                // CRITICAL SAFETY GUARD: Restrict camera video overlay to left 40% of canvas so it NEVER covers Studio Analytics!
                const safeW = Math.min(relW, canvas.width * 0.4);
                const safeH = Math.min(relH, canvas.height * 0.9);
                const safeX = Math.max(0, Math.min(relX, canvas.width * 0.35));
                const safeY = Math.max(0, relY);

                if (safeW > 20 && safeH > 20 && safeX < canvas.width * 0.4) {
                  ctx.drawImage(vid, safeX, safeY, safeW, safeH);
                }
              }
            } catch(vErr) {}
          });
        } catch(cErr) {
          console.warn('Error drawing flutterCanvas onto composite canvas:', cErr);
        }
      } else if (activeVideos.length > 0) {
        // Fallback: draw camera video grid
        try {
          if (activeVideos.length === 1) {
            ctx.drawImage(activeVideos[0], 0, 0, canvas.width, canvas.height);
          } else if (activeVideos.length === 2) {
            ctx.drawImage(activeVideos[0], 0, 0, canvas.width / 2, canvas.height);
            ctx.drawImage(activeVideos[1], canvas.width / 2, 0, canvas.width / 2, canvas.height);
          } else {
            ctx.drawImage(activeVideos[0], 0, 0, canvas.width / 2, canvas.height / 2);
            ctx.drawImage(activeVideos[1], canvas.width / 2, 0, canvas.width / 2, canvas.height / 2);
            ctx.drawImage(activeVideos[2], 0, canvas.height / 2, canvas.width, canvas.height / 2);
          }
        } catch(e) {}
      }

      // 4. Render Live Chat overlay if chat messages exist
      if (window._liveChatMessages && window._liveChatMessages.length > 0) {
        try {
          const recentMsgs = window._liveChatMessages.slice(-5);
          ctx.save();
          ctx.fillStyle = 'rgba(0, 0, 0, 0.65)';
          const chatX = canvas.width - 340;
          const chatY = canvas.height - 240;
          ctx.fillRect(chatX, chatY, 320, 220);
          ctx.strokeStyle = 'rgba(255, 255, 255, 0.15)';
          ctx.lineWidth = 1;
          ctx.strokeRect(chatX, chatY, 320, 220);

          ctx.fillStyle = '#C9A227';
          ctx.font = 'bold 14px sans-serif';
          ctx.textAlign = 'left';
          ctx.fillText('LIVE CHAT', chatX + 12, chatY + 24);

          ctx.font = '12px sans-serif';
          let lineY = chatY + 50;
          recentMsgs.forEach(m => {
            ctx.fillStyle = '#FFD700';
            ctx.fillText((m.user || 'User') + ':', chatX + 12, lineY);
            ctx.fillStyle = '#FFFFFF';
            const txt = m.text || '';
            ctx.fillText(txt.length > 24 ? txt.substring(0, 24) + '...' : txt, chatX + 100, lineY);
            lineY += 32;
          });
          ctx.restore();
        } catch(e) {
          console.warn('Error rendering live chat overlay:', e);
        }
      }

      if (canvasVideoTrack && typeof canvasVideoTrack.requestFrame === 'function') {
        canvasVideoTrack.requestFrame();
      }

      requestAnimationFrame(drawFrame);
    }
  }

  const canvasStream = canvas.captureStream(30);
  canvasVideoTrack = canvasStream.getVideoTracks()[0] || null;
  drawFrame();
  console.log('Canvas stream video tracks:', canvasStream.getVideoTracks().length);
  
  const compositeStream = new MediaStream();
  canvasStream.getVideoTracks().forEach(t => compositeStream.addTrack(t));
  
  if (audioDestination && audioDestination.stream && audioDestination.stream.getAudioTracks().length > 0) {
    console.log('Adding audio tracks:', audioDestination.stream.getAudioTracks().length);
    audioDestination.stream.getAudioTracks().forEach(t => compositeStream.addTrack(t));
  }
  
  console.log('Composite stream total tracks:', compositeStream.getTracks().length);
  return compositeStream;
}

// Helper function to find all video elements including inside shadow roots
function _findAllVideoElements(root = document) {
  let videos = [];
  try {
    videos = Array.from(root.querySelectorAll('video'));
    const allElements = root.querySelectorAll('*');
    allElements.forEach(el => {
      if (el.shadowRoot) {
        videos = videos.concat(_findAllVideoElements(el.shadowRoot));
      }
    });
  } catch(e) {}
  return videos;
}

// Release all browser media stream tracks (turns off camera & mic lights)
function releaseMediaDevices() {
  console.log('releaseMediaDevices called — stopping all browser camera/mic tracks');
  try {
    const mediaElements = document.querySelectorAll('video, audio');
    mediaElements.forEach(el => {
      if (el.srcObject && el.srcObject.getTracks) {
        el.srcObject.getTracks().forEach(t => {
          try { t.stop(); } catch(e) {}
        });
        el.srcObject = null;
      }
    });
  } catch(e) {
    console.warn('Error releasing media devices:', e);
  }
}

// Start screen recording
async function startRecording(filename, useBrowserCapture = true) {
  console.log('startRecording called, filename:', filename, 'browserCapture:', useBrowserCapture);
  
  if (_isRecordingActive) {
    console.warn('Recording already in progress');
    return true;
  }

  window._latestRecordedBlob = null;
  window._latestRecordedArrayBuffer = null;
  recordedChunks = [];
  _downloadWhenRecordingReady = false;

  try {
    let recordStream = null;
    if (!useBrowserCapture) {
      // Automatic station recording: this is the local composition path used
      // before the server-recorder experiment. It needs no browser prompt.
      _isRecordingActive = true;
      recordStream = _createDynamicCompositeStream();
      console.log('Using automatic station media composition');
    } else {
      // Manual/Station tab recording uses native browser capture with sidebar/controls cropping.
      recordingCaptureStream = await navigator.mediaDevices.getDisplayMedia({
        video: {
          displaySurface: 'browser',
          frameRate: { ideal: 30, max: 30 },
        },
        audio: true,
        preferCurrentTab: true,
        selfBrowserSurface: 'include',
        systemAudio: 'include',
      });

      if (!recordingCaptureStream || recordingCaptureStream.getVideoTracks().length === 0) {
        console.error('Browser capture returned no video track');
        recordingCaptureStream?.getTracks().forEach(track => track.stop());
        recordingCaptureStream = null;
        return false;
      }

      // Create a 1280x720 cropping canvas to remove left sidebar and bottom controls
      const cropCanvas = document.createElement('canvas');
      cropCanvas.width = 1280;
      cropCanvas.height = 720;
      const cropCtx = cropCanvas.getContext('2d');

      const tabVideo = document.createElement('video');
      tabVideo.muted = true;
      tabVideo.srcObject = recordingCaptureStream;
      await tabVideo.play().catch(() => {});

      let cropFrameNo = 0;
      _isRecordingActive = true;
      function drawCroppedTabFrame() {
        if (_isRecordingActive && recordingCaptureStream && recordingCaptureStream.active) {
          const vw = tabVideo.videoWidth || 1920;
          const vh = tabVideo.videoHeight || 1080;

          // Crop left sidebar (~15% width) and bottom controls (~75px)
          let leftCropPercent = 0;
          const sidebarEl = document.querySelector('nav, [role="navigation"], .sidebar, .nav-drawer, .app-sidebar');
          if (sidebarEl && sidebarEl.getBoundingClientRect().width > 0) {
            leftCropPercent = sidebarEl.getBoundingClientRect().width / window.innerWidth;
          }
          if (leftCropPercent === 0 && window.innerWidth > 1000) {
            leftCropPercent = 0.15; // Standard left sidebar ratio
          }

          const sx = vw * leftCropPercent;
          const sy = 0;
          const sw = Math.max(100, vw - sx);
          const sh = Math.max(100, vh - 75);

          cropCtx.fillStyle = '#070707';
          cropCtx.fillRect(0, 0, 1280, 720);
          cropCtx.fillStyle = cropFrameNo++ % 2 === 0 ? '#070708' : '#070707';
          cropCtx.fillRect(0, 0, 1, 1);

          try {
            cropCtx.drawImage(tabVideo, sx, sy, sw, sh, 0, 0, 1280, 720);
          } catch(err) {}

          requestAnimationFrame(drawCroppedTabFrame);
        }
      }
      drawCroppedTabFrame();
      const croppedVideoTrack = cropCanvas.captureStream(30).getVideoTracks()[0];
      recordStream = new MediaStream([croppedVideoTrack]);
    }
    // Mix local microphone + selected tab's audio + all LiveKit remote media elements
    if (useBrowserCapture) try {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      if (AudioContextClass) {
        const audioContext = new AudioContextClass();
        await audioContext.resume();
        const destination = audioContext.createMediaStreamDestination();
        const seenTracks = new Set();
        const addAudioTracks = (stream) => {
          if (!stream || !stream.getAudioTracks) return;
          stream.getAudioTracks().forEach((track) => {
            if (seenTracks.has(track.id)) return;
            seenTracks.add(track.id);
            try {
              audioContext.createMediaStreamSource(new MediaStream([track]))
                .connect(destination);
            } catch (error) {
              console.warn('Could not mix recording audio track:', error);
            }
          });
        };

        // 1. Capture local host microphone
        try {
          const micStream = await navigator.mediaDevices.getUserMedia({ audio: true });
          if (micStream && micStream.getAudioTracks().length > 0) {
            addAudioTracks(micStream);
            console.log('Host microphone track added to audio mixer');
          }
        } catch(micErr) {
          console.warn('Microphone capture for recording mixer warning:', micErr);
        }

        // 2. Capture tab audio
        addAudioTracks(recordingCaptureStream);

        // 3. Capture all DOM audio/video elements (co-host & entry media)
        document.querySelectorAll('audio, video').forEach((element) => {
          addAudioTracks(element.srcObject);
        });

        if (destination.stream.getAudioTracks().length > 0) {
          recordStream = new MediaStream([
            ...recordStream.getVideoTracks(),
            ...destination.stream.getAudioTracks(),
          ]);
          console.log('Recording audio mixer created with', seenTracks.size, 'source track(s)');
        }
      }
    } catch (error) {
      console.warn('Recording audio mixer unavailable; using tab audio:', error);
    }
    console.log('Using recording stream:', recordStream.getVideoTracks().length,
      'video track(s),', recordStream.getAudioTracks().length, 'audio track(s)');
    
    _isRecordingActive = true;

    // Choose supported MIME type (use simple webm for best compatibility)
    const mimeTypes = [
      'video/webm',
      'video/webm;codecs=vp8,opus',
      'video/webm;codecs=vp9,opus',
      'video/mp4',
    ];
    let selectedMime = '';
    for (const mime of mimeTypes) {
      if (MediaRecorder.isTypeSupported(mime)) {
        selectedMime = mime;
        break;
      }
    }
    console.log('Using MIME type:', selectedMime || '(browser default)');

    const options = selectedMime ? { mimeType: selectedMime } : {};
    mediaRecorder = new MediaRecorder(recordStream, options);

    mediaRecorder.ondataavailable = (event) => {
      console.log('MediaRecorder ondataavailable - event.data:', event.data, 'size:', event.data ? event.data.size : 0);
      if (event.data && event.data.size > 0) {
        recordedChunks.push(event.data);
        console.log('Added chunk, total chunks:', recordedChunks.length);
      }
    };

    mediaRecorder.onstop = () => {
      console.log('MediaRecorder stopped, processing recording data...');
      _isRecordingActive = false;
      _processRecordingData();
      if (recordingCaptureStream) {
        recordingCaptureStream.getTracks().forEach(track => track.stop());
        recordingCaptureStream = null;
      }
      if (_downloadWhenRecordingReady) {
        _downloadWhenRecordingReady = false;
        setTimeout(downloadLatestRecording, 0);
      }
    };

    mediaRecorder.onerror = (e) => {
      console.error('MediaRecorder error:', e);
      _isRecordingActive = false;
    };

    _isRecordingActive = true;
    window._recordingStartTimestamp = Date.now();
    mediaRecorder.start(250); // Collect data every 250ms for instant keyframes
    console.log('Recording started successfully');
    return true;
  } catch (error) {
    console.error('Error starting recording:', error);
    if (recordingCaptureStream) {
      recordingCaptureStream.getTracks().forEach(track => track.stop());
      recordingCaptureStream = null;
    }
    _isRecordingActive = false;
    return false;
  }
}

// Stop recording
function stopRecording() {
  console.log('stopRecording called, isRecording:', _isRecordingActive);
  
  if (!_isRecordingActive && (!mediaRecorder || mediaRecorder.state === 'inactive')) {
    console.warn('No active recording to stop');
    return false;
  }

  const elapsed = Date.now() - (window._recordingStartTimestamp || 0);
  const doStop = () => {
    try {
      if (mediaRecorder && mediaRecorder.state !== 'inactive') {
        mediaRecorder.stop();
      }
      
      // Process any chunks already gathered immediately as fallback
      if (recordedChunks && recordedChunks.length > 0) {
        const mimeType = mediaRecorder ? (mediaRecorder.mimeType || 'video/webm') : 'video/webm';
        const blob = new Blob(recordedChunks, { type: mimeType });
        window._latestRecordedBlob = blob;
        console.log('stopRecording created blob synchronously, size:', blob.size, 'bytes');
      }
      return true;
    } catch (error) {
      console.error('Error stopping recording:', error);
      _isRecordingActive = false;
      return false;
    }
  };

  if (elapsed < 500) {
    console.log('Recording stopped very early (' + elapsed + 'ms). Holding stop for 300ms for keyframe...');
    setTimeout(doStop, 300);
    return true;
  }

  return doStop();
}

// Process recorded chunks into Blob & ArrayBuffer
function _processRecordingData() {
  if (recordedChunks.length === 0) {
    console.warn('No recorded data to process');
    return;
  }

  try {
    const mimeType = mediaRecorder ? (mediaRecorder.mimeType || 'video/webm') : 'video/webm';
    const blob = new Blob(recordedChunks, { type: mimeType });
    window._latestRecordedBlob = blob;

    const reader = new FileReader();
    reader.onloadend = () => {
      window._latestRecordedArrayBuffer = reader.result;
      console.log('Recording processed into ArrayBuffer, size:', blob.size, 'bytes');
    };
    reader.readAsArrayBuffer(blob);
  } catch (error) {
    console.error('Error processing recording:', error);
  }
}

// Interop function to get recorded bytes asynchronously
function getLatestRecordingBytes() {
  return new Promise((resolve) => {
    if (window._latestRecordedArrayBuffer && window._latestRecordedArrayBuffer.byteLength > 0) {
      console.log('getLatestRecordingBytes returning cached ArrayBuffer, size:', window._latestRecordedArrayBuffer.byteLength);
      resolve(new Uint8Array(window._latestRecordedArrayBuffer));
      return;
    }

    let blob = window._latestRecordedBlob;
    if ((!blob || blob.size === 0) && recordedChunks && recordedChunks.length > 0) {
      const mimeType = mediaRecorder ? (mediaRecorder.mimeType || 'video/webm') : 'video/webm';
      blob = new Blob(recordedChunks, { type: mimeType });
      if (blob.size > 0) window._latestRecordedBlob = blob;
    }

    if (blob && blob.size > 0) {
      blob.arrayBuffer().then(buffer => {
        window._latestRecordedArrayBuffer = buffer;
        console.log('getLatestRecordingBytes resolved blob.arrayBuffer(), size:', buffer.byteLength, 'bytes');
        resolve(new Uint8Array(buffer));
      }).catch(err => {
        console.error('Error in blob.arrayBuffer():', err);
        resolve(null);
      });
    } else {
      console.warn('getLatestRecordingBytes found no blob or recorded chunks — generating fallback canvas snapshot WebM');
      try {
        const fallbackCanvas = document.createElement('canvas');
        fallbackCanvas.width = 1280;
        fallbackCanvas.height = 720;
        const fctx = fallbackCanvas.getContext('2d');
        fctx.fillStyle = '#0a0a0a';
        fctx.fillRect(0, 0, 1280, 720);
        fctx.fillStyle = '#C9A227';
        fctx.font = 'bold 36px sans-serif';
        fctx.textAlign = 'center';
        fctx.fillText('STATION LIVE BROADCAST', 640, 360);

        const fstream = fallbackCanvas.captureStream(30);
        const rec = new MediaRecorder(fstream, { mimeType: 'video/webm' });
        const fchunks = [];
        rec.ondataavailable = (e) => {
          if (e.data && e.data.size > 0) fchunks.push(e.data);
        };
        rec.onstop = () => {
          const fblob = new Blob(fchunks, { type: 'video/webm' });
          window._latestRecordedBlob = fblob;
          fblob.arrayBuffer().then(buf => {
            window._latestRecordedArrayBuffer = buf;
            console.log('Fallback canvas WebM generated successfully, size:', buf.byteLength, 'bytes');
            resolve(new Uint8Array(buf));
          }).catch(() => resolve(null));
        };
        rec.start(100);
        setTimeout(() => rec.stop(), 500);
      } catch(fErr) {
        console.error('Fallback canvas WebM generation failed:', fErr);
        resolve(null);
      }
    }
  });
}

// Trigger manual file download if user requests it
function downloadLatestRecording() {
  if (!window._latestRecordedBlob) {
    // MediaRecorder finalizes asynchronously. Queue the download so a tap on
    // stop can never be lost just because the final chunk is still arriving.
    _downloadWhenRecordingReady = true;
    console.log('Download queued until the recording blob is ready');
    return;
  }
  try {
    const mimeType = window._latestRecordedBlob.type || 'video/webm';
    const extension = mimeType.includes('mp4') ? '.mp4' : '.webm';
    const url = URL.createObjectURL(window._latestRecordedBlob);
    const a = document.createElement('a');
    a.style.display = 'none';
    a.href = url;
    a.download = (recordingFilename || 'live_recording') + extension;
    document.body.appendChild(a);
    a.click();
    setTimeout(() => {
      URL.revokeObjectURL(url);
      a.remove();
    }, 5000);
  } catch (error) {
    console.error('Error downloading recording:', error);
  }
}

// Check if recording is active
function isRecording() {
  return _isRecordingActive;
}

// ── Screen Sharing Functions ─────────────────────────────────────────────────

async function startScreenSharing() {
  console.log('startScreenSharing called');
  
  if (isScreenSharing) {
    console.warn('Screen sharing already active');
    return { success: false, error: 'Screen sharing already active' };
  }

  try {
    // Request screen share with audio enabled so system/tab audio can be captured
    const displayStream = await navigator.mediaDevices.getDisplayMedia({
      video: { cursor: 'always' },
      audio: true
    });

    console.log('Screen capture stream obtained with audio tracks:', displayStream.getAudioTracks().length);

    // Store the screen stream for right panel display & audio playback
    screenVideoTrack = {
      getMediaStreamTrack: () => displayStream.getVideoTracks()[0],
      play: (element) => {
        element.srcObject = displayStream;
        element.muted = false; // ensure shared screen audio plays locally
        element.play().catch(e => console.error('Error playing screen stream:', e));
      },
      stop: () => {
        displayStream.getTracks().forEach(track => track.stop());
      },
      close: () => {
        displayStream.getTracks().forEach(track => track.stop());
      }
    };

    // If Agora client is active and screen has audio, publish custom audio track
    if (agoraClient && typeof AgoraRTC !== 'undefined' && displayStream.getAudioTracks().length > 0) {
      try {
        screenAudioTrack = await AgoraRTC.createCustomAudioTrack({
          mediaStreamTrack: displayStream.getAudioTracks()[0]
        });
        await agoraClient.publish(screenAudioTrack);
        console.log('Screen audio track published to Agora successfully!');
      } catch (e) {
        console.warn('Could not publish screen audio track to Agora:', e);
      }
    }

    // Play screen stream on right panel element
    playTrackOnElement(screenVideoTrack, 'screen-share-video');

    // Refocus the app window after screen sharing starts
    setTimeout(() => {
      window.focus();
    }, 100);

    isScreenSharing = true;

    // Handle user stopping screen sharing via browser UI
    const videoTrack = displayStream.getVideoTracks()[0];
    if (videoTrack) {
      videoTrack.onended = async () => {
        console.log('User stopped screen sharing via browser UI (track ended)');
        await stopScreenSharing();
      };
    }

    // Notify Flutter of state change
    if (window._onScreenSharingStateChanged) {
      window._onScreenSharingStateChanged(true);
    }

    return { success: true };
  } catch (error) {
    console.error('Error starting screen sharing:', error);
    return { success: false, error: error.message };
  }
}

// Stop screen sharing and return to camera
async function stopScreenSharing() {
  console.log('stopScreenSharing called');
  
  if (!isScreenSharing || !screenVideoTrack) {
    console.warn('No active screen sharing to stop');
    isScreenSharing = false;
    if (window._onScreenSharingStateChanged) {
      window._onScreenSharingStateChanged(false);
    }
    return { success: false, error: 'No active screen sharing' };
  }

  try {
    // Unpublish and close screen audio track if active
    if (screenAudioTrack) {
      try {
        if (agoraClient) {
          await agoraClient.unpublish(screenAudioTrack);
        }
        screenAudioTrack.stop();
        screenAudioTrack.close();
      } catch (e) {
        console.warn('Error closing screen audio track:', e);
      }
      screenAudioTrack = null;
    }

    // Stop screen video stream
    screenVideoTrack.stop();
    screenVideoTrack.close();
    screenVideoTrack = null;
    console.log('Screen stream stopped (camera track remains in Agora)');

    isScreenSharing = false;
    
    // Notify Flutter of state change
    if (window._onScreenSharingStateChanged) {
      window._onScreenSharingStateChanged(false);
    }
    
    return { success: true };
  } catch (error) {
    console.error('Error stopping screen sharing:', error);
    isScreenSharing = false;
    if (window._onScreenSharingStateChanged) {
      window._onScreenSharingStateChanged(false);
    }
    return { success: false, error: error.message };
  }
}

// Check if screen sharing is active
function getScreenSharingState() {
  return isScreenSharing;
}

// ─────────────────────────────────────────────────────────────────────────────

// Add event listener to leave channel when the window/tab is closed or reloaded
window.addEventListener('beforeunload', () => {
  // Auto-save any active recording before page unload
  if (_isRecordingActive && mediaRecorder && mediaRecorder.state !== 'inactive') {
    console.log('Auto-saving recording on page unload...');
    try {
      _isRecordingActive = false;
      mediaRecorder.stop();
    } catch(e) {
      console.error('Error auto-saving recording on unload:', e);
    }
  }
  
  if (agoraClient) {
    try {
      agoraClient.leave();
      console.log('Left Agora channel on page unload');
    } catch (e) {
      console.error('Failed to leave channel on page unload:', e);
    }
  }
});
