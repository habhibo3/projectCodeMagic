import Flutter
import UIKit
import ReplayKit
import Photos
import AVFoundation

public class SwiftFlutterScreenRecordingPlugin: NSObject, FlutterPlugin {
    
    let recorder = RPScreenRecorder.shared()
    
    var videoOutputURL: URL?
    var videoWriter: AVAssetWriter?
    
    var audioInput: AVAssetWriterInput?
    var videoWriterInput: AVAssetWriterInput?
    var nameVideo: String = ""
    var recordAudio: Bool = false
    var isSessionStarted: Bool = false
    var sessionStartTime: CMTime = .zero
    var lastVideoTimestamp: CMTime = .zero
    var activeAudioType: RPSampleBufferType? = nil
    var videoFramesCount: Int = 0
    var audioSamplesCount: Int = 0
    var audioAppCount: Int = 0
    var audioMicCount: Int = 0
    var myResult: FlutterResult?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_screen_recording", binaryMessenger: registrar.messenger())
        let instance = SwiftFlutterScreenRecordingPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "startRecordScreen" {
            self.myResult = result
            let args = call.arguments as? Dictionary<String, Any>
            
            self.recordAudio = (args?["audio"] as? Bool) ?? false
            self.nameVideo = ((args?["name"] as? String) ?? "recording") + ".mp4"
            self.isSessionStarted = false
            self.sessionStartTime = .zero
            self.lastVideoTimestamp = .zero
            self.activeAudioType = nil
            self.videoFramesCount = 0
            self.audioSamplesCount = 0
            self.audioAppCount = 0
            self.audioMicCount = 0
            startRecording()
        } else if call.method == "stopRecordScreen" {
            if self.videoWriter != nil {
                stopRecording { filePath in
                    result(filePath)
                }
            } else {
                result("")
            }
        }
    }
    
    @objc func startRecording() {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
        self.videoOutputURL = URL(fileURLWithPath: documentsPath.appendingPathComponent(nameVideo))
        
        if let outputURL = self.videoOutputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        guard let outputURL = self.videoOutputURL else {
            self.myResult?(false)
            return
        }
        
        do {
            self.videoWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            self.videoWriter?.shouldOptimizeForNetworkUse = true
        } catch let writerError {
            print("[ScreenRecord] Error opening video writer: \(writerError)")
            self.videoWriter = nil
            self.myResult?(false)
            return
        }
        
        let nativeBounds = UIScreen.main.nativeBounds
        // Ensure even pixel dimensions for H.264 VideoToolbox hardware encoder
        let width = (Int(nativeBounds.width) / 2) * 2
        let height = (Int(nativeBounds.height) / 2) * 2
        
        let videoCompressionProps: [String: Any] = [
            AVVideoAverageBitRateKey: 6_000_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalKey: 30
        ]
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: videoCompressionProps
        ]
        
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        self.videoWriterInput = videoInput
        
        if let writer = self.videoWriter, writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        
        if self.recordAudio {
            var channelLayout = AudioChannelLayout()
            memset(&channelLayout, 0, MemoryLayout<AudioChannelLayout>.size)
            channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
            
            let audioOutputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100.0,
                AVEncoderBitRateKey: 128000,
                AVChannelLayoutKey: NSData(bytes: &channelLayout, length: MemoryLayout<AudioChannelLayout>.size)
            ]
            
            let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
            audioIn.expectsMediaDataInRealTime = true
            self.audioInput = audioIn
            
            if let writer = self.videoWriter, writer.canAdd(audioIn) {
                writer.add(audioIn)
            }
        }
        
        if #available(iOS 11.0, *) {
            self.recorder.isMicrophoneEnabled = self.recordAudio
            
            self.recorder.startCapture(handler: { cmSampleBuffer, rpSampleType, error in
                guard error == nil else {
                    print("[ScreenRecord] Capture error: \(error?.localizedDescription ?? "")")
                    return
                }
                
                guard CMSampleBufferDataIsReady(cmSampleBuffer) else { return }
                let timestamp = CMSampleBufferGetPresentationTimeStamp(cmSampleBuffer)
                
                switch rpSampleType {
                case .video:
                    if !self.isSessionStarted {
                        if self.videoWriter?.status == .unknown {
                            self.videoWriter?.startWriting()
                            self.videoWriter?.startSession(atSourceTime: timestamp)
                            self.isSessionStarted = true
                            self.sessionStartTime = timestamp
                            self.lastVideoTimestamp = timestamp
                            print("[ScreenRecord] Started session at timestamp: \(timestamp.seconds)")
                            self.myResult?(true)
                            self.myResult = nil
                        }
                    }
                    
                    if self.isSessionStarted && self.videoWriter?.status == .writing {
                        if let vInput = self.videoWriterInput, vInput.isReadyForMoreMediaData {
                            if vInput.append(cmSampleBuffer) {
                                self.videoFramesCount += 1
                                self.lastVideoTimestamp = timestamp
                            }
                        }
                    }
                    
                case .audioApp, .audioMic:
                    if rpSampleType == .audioApp {
                        self.audioAppCount += 1
                    } else if rpSampleType == .audioMic {
                        self.audioMicCount += 1
                    }
                    
                    guard self.recordAudio, self.isSessionStarted, self.videoWriter?.status == .writing else { break }
                    
                    // Lock onto whichever audio stream arrives first (.audioApp or .audioMic)
                    if self.activeAudioType == nil {
                        self.activeAudioType = rpSampleType
                        print("[ScreenRecord] Locked active audio stream to: \(rpSampleType == .audioApp ? "audioApp" : "audioMic")")
                    }
                    
                    if self.activeAudioType == rpSampleType {
                        if timestamp >= self.sessionStartTime {
                            if let aInput = self.audioInput, aInput.isReadyForMoreMediaData {
                                if aInput.append(cmSampleBuffer) {
                                    self.audioSamplesCount += 1
                                }
                            }
                        }
                    }
                    
                @unknown default:
                    break
                }
            }) { startError in
                if let err = startError {
                    print("[ScreenRecord] startCapture error: \(err.localizedDescription)")
                    self.myResult?(false)
                    self.myResult = nil
                }
            }
        } else {
            self.myResult?(false)
            self.myResult = nil
        }
    }
    
    @objc func stopRecording(completion: @escaping (String) -> Void) {
        self.isSessionStarted = false
        
        if #available(iOS 11.0, *) {
            self.recorder.stopCapture { error in
                if let error = error {
                    print("[ScreenRecord] stopCapture error: \(error.localizedDescription)")
                }
                
                self.videoWriterInput?.markAsFinished()
                self.audioInput?.markAsFinished()
                
                self.videoWriter?.finishWriting {
                    let status = self.videoWriter?.status
                    let errorDesc = self.videoWriter?.error?.localizedDescription
                    print("[ScreenRecord] finishWriting completed. Status: \(String(describing: status)), Error: \(String(describing: errorDesc)), Frames: \(self.videoFramesCount), AudioSamples: \(self.audioSamplesCount), AudioAppCount: \(self.audioAppCount), AudioMicCount: \(self.audioMicCount)")
                    
                    let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
                    let filePath = String(documentsPath.appendingPathComponent(self.nameVideo))
                    var fileSizeBytes: UInt64 = 0
                    
                    if let url = self.videoOutputURL, FileManager.default.fileExists(atPath: url.path) {
                        do {
                            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                            fileSizeBytes = attrs[.size] as? UInt64 ?? 0
                            print("[ScreenRecord] Recorded file size: \(fileSizeBytes) bytes at: \(filePath)")
                        } catch {
                            print("[ScreenRecord] Could not read file size: \(error)")
                        }
                    }
                    
                    // Write diagnostic sidecar JSON file
                    let activeTypeStr = self.activeAudioType == .audioApp ? "audioApp" : (self.activeAudioType == .audioMic ? "audioMic" : "none")
                    let diagDict: [String: Any] = [
                        "videoFrames": self.videoFramesCount,
                        "audioSamples": self.audioSamplesCount,
                        "audioAppCount": self.audioAppCount,
                        "audioMicCount": self.audioMicCount,
                        "activeAudioType": activeTypeStr,
                        "writerStatus": "\(String(describing: status))",
                        "writerError": errorDesc ?? "",
                        "fileSizeBytes": fileSizeBytes
                    ]
                    
                    if let diagData = try? JSONSerialization.data(withJSONObject: diagDict, options: .prettyPrinted) {
                        let diagPath = filePath + ".diag.json"
                        try? diagData.write(to: URL(fileURLWithPath: diagPath))
                    }
                    
                    DispatchQueue.main.async {
                        completion(filePath)
                    }
                }
            }
        } else {
            completion("")
        }
    }
}
