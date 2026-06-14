import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_theme.dart';

class AvatarHelper {
  static ImageProvider getSafeAvatarProvider(String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return const CachedNetworkImageProvider('https://i.pravatar.cc/150?u=anonymous');
    }
    if (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://') || avatarUrl.startsWith('content://')) {
      return CachedNetworkImageProvider(avatarUrl);
    }
    // On web, FileImage is not supported, return network placeholder
    if (kIsWeb) {
      return const CachedNetworkImageProvider('https://i.pravatar.cc/150?u=anonymous');
    }
    return FileImage(File(avatarUrl));
  }

  static Widget getSafePostImage(String? contentUrl, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    if (contentUrl == null || contentUrl.isEmpty) {
      return Container(color: Colors.grey.shade900);
    }
    if (contentUrl.startsWith('http://') || contentUrl.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: contentUrl,
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, url) => Container(
          color: const Color(0xFF141416),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(color: Colors.grey.shade900),
      );
    }
    // On web, Image.file is not supported
    if (kIsWeb) {
      return Container(
        width: width,
        height: height,
        color: Colors.grey.shade900,
        child: const Center(
          child: Icon(LucideIcons.image, color: Colors.white30, size: 32),
        ),
      );
    }
    return Image.file(
      File(contentUrl),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade900),
    );
  }
}
