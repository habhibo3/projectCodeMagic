import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/station_upload_progress_service.dart';
import '../theme/app_theme.dart';

class StationUploadBannerWidget extends StatelessWidget {
  const StationUploadBannerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StationUploadState>(
      valueListenable: StationUploadProgressService.instance,
      builder: (context, state, child) {
        if (!state.isUploading && !state.isCompleted && state.error == null) {
          return const SizedBox.shrink();
        }

        final percent = (state.progress * 100).toInt();

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: state.isCompleted
                ? Colors.green.shade900
                : state.error != null
                    ? Colors.red.shade900
                    : const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: state.isCompleted
                  ? Colors.green
                  : state.error != null
                      ? Colors.red
                      : AppTheme.primary,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (state.isUploading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primary,
                      ),
                    )
                  else if (state.isCompleted)
                    const Icon(LucideIcons.checkCircle2, color: Colors.green, size: 20)
                  else
                    const Icon(LucideIcons.alertTriangle, color: Colors.red, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      state.isUploading
                          ? 'Uploading station recording... ($percent%)'
                          : state.isCompleted
                              ? 'Live recording saved to Recorded Lives! ✓'
                              : 'Upload failed: ${state.error ?? "Unknown error"}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              if (state.isUploading) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: state.progress,
                    backgroundColor: Colors.white10,
                    color: AppTheme.primary,
                    minHeight: 4,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
