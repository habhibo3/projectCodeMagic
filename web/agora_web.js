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
function bindVideoElement(elementId) {
  console.log('bindVideoElement called for:', elementId);
  
  const tryBind = () => {
    const el = document.getElementById(elementId);
    if (!el) return false;
    
    if (elementId === 'local-video') {
      if (localVideoTrack) {
        console.log('Successfully re-bound local video track to element');
        localVideoTrack.play(el);
        return true;
      }
    } else {
      const match = elementId.match(/^remote-video-(\d+)$/);
      if (match) {
        const uid = parseInt(match[1]);
        const user = remoteUsers[uid];
        if (user && user.videoTrack) {
          console.log('Successfully re-bound remote video track for user', uid, 'to element');
          user.videoTrack.play(el);
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
    await agoraClient.join(appId, channel, token || null, uid);
    console.log('Joined channel:', channel, 'with uid:', uid);
    
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
