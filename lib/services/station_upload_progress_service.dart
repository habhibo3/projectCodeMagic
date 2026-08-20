import 'package:flutter/foundation.dart';

class StationUploadState {
  final bool isUploading;
  final double progress; // 0.0 to 1.0
  final bool isCompleted;
  final String? error;
  final String? videoUrl;

  const StationUploadState({
    this.isUploading = false,
    this.progress = 0.0,
    this.isCompleted = false,
    this.error,
    this.videoUrl,
  });
}

class StationUploadProgressService extends ValueNotifier<StationUploadState> {
  static final StationUploadProgressService instance = StationUploadProgressService._();

  StationUploadProgressService._() : super(const StationUploadState());

  void startUpload() {
    value = const StationUploadState(
      isUploading: true,
      progress: 0.05,
      isCompleted: false,
    );
  }

  void updateProgress(double progress) {
    if (!value.isUploading) return;
    value = StationUploadState(
      isUploading: true,
      progress: progress.clamp(0.05, 0.99),
      isCompleted: false,
    );
  }

  void completeUpload(String? videoUrl) {
    value = StationUploadState(
      isUploading: false,
      progress: 1.0,
      isCompleted: true,
      videoUrl: videoUrl,
    );

    Future.delayed(const Duration(seconds: 5), () {
      if (value.isCompleted) {
        value = const StationUploadState();
      }
    });
  }

  void failUpload(String error) {
    value = StationUploadState(
      isUploading: false,
      progress: 0.0,
      isCompleted: false,
      error: error,
    );

    Future.delayed(const Duration(seconds: 5), () {
      if (value.error != null) {
        value = const StationUploadState();
      }
    });
  }
}
