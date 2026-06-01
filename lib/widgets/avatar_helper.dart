import 'dart:io';
import 'package:flutter/material.dart';

class AvatarHelper {
  static ImageProvider getSafeAvatarProvider(String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return const NetworkImage('https://i.pravatar.cc/150?u=anonymous');
    }
    if (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://') || avatarUrl.startsWith('content://')) {
      return NetworkImage(avatarUrl);
    }
    return FileImage(File(avatarUrl));
  }

  static Widget getSafePostImage(String? contentUrl, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    if (contentUrl == null || contentUrl.isEmpty) {
      return Container(color: Colors.grey.shade900);
    }
    if (contentUrl.startsWith('http://') || contentUrl.startsWith('https://')) {
      return Image.network(
        contentUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade900),
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
