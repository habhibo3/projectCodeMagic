import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../engine/ranking_engine.dart';
import '../models/entry.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_helper.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _textController = TextEditingController();

  String _selectedType = 'text'; // 'image', 'video', 'text'
  String _selectedScope = 'country'; // 'zip', 'city', 'state', 'country', 'global'

  File? _mediaFile;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final picker = ImagePicker();
    if (_selectedType == 'image') {
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (picked != null) {
        setState(() {
          _mediaFile = File(picked.path);
        });
      }
    } else if (_selectedType == 'video') {
      final picked = await picker.pickVideo(source: ImageSource.gallery);
      if (picked != null) {
        setState(() {
          _mediaFile = File(picked.path);
        });
      }
    }
  }

  void _showUpgradeDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFC9A227), width: 1.2),
        ),
        title: const Row(
          children: [
            Icon(LucideIcons.sparkles, color: Color(0xFFC9A227), size: 24),
            SizedBox(width: 12),
            Text(
              'Premium Scope Required',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Global ranking visibility is exclusively reserved for Premium members. Free users can post in local Zip Code, City, State, or Country scopes.',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Maybe Later', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please go to the Profile tab to toggle Premium subscription instantly!'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('View Profile'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RankingEngine>(
      builder: (context, engine, _) {
        final profile = engine.currentUserProfile;
        if (profile == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF0A0A0A),
            body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
          );
        }
        final isPremium = profile.subscriptionLevel == 'premium';
        final hasAvatar = profile.photoURL.isNotEmpty;

        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0A0A0A),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'CREATE POST',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5),
            ),
            actions: [
              if (_isUploading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                    ),
                  ),
                )
              else
                TextButton(
                  onPressed: () async {
                    if (_selectedType != 'text' && _mediaFile == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please select media to upload!'), backgroundColor: Colors.redAccent),
                      );
                      return;
                    }
                    if (_selectedType == 'text' && _textController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter some text!'), backgroundColor: Colors.redAccent),
                      );
                      return;
                    }

                    setState(() => _isUploading = true);

                    try {
                      String mediaUrl = '';
                      if (_selectedType != 'text' && _mediaFile != null) {
                        mediaUrl = await engine.uploadPostMedia(_mediaFile!);
                      }

                      await engine.createPost(
                        type: _selectedType,
                        contentUrl: _selectedType == 'text' ? _textController.text.trim() : mediaUrl,
                        caption: _selectedType == 'text' ? 'A text performance' : _textController.text.trim(),
                        visibilityScope: _selectedScope,
                      );

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Post successfully published on profile!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        Navigator.pop(context);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to publish post: $e'), backgroundColor: Colors.redAccent),
                        );
                      }
                    } finally {
                      setState(() => _isUploading = false);
                    }
                  },
                  child: const Text(
                    'SHARE',
                    style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                  ),
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. User Header like Facebook
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: hasAvatar ? AvatarHelper.getSafeAvatarProvider(profile.photoURL) : null,
                      backgroundColor: Colors.grey.shade900,
                      child: !hasAvatar ? const Icon(LucideIcons.user, size: 20, color: Colors.white70) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.displayName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          // Scope selector button under name
                          GestureDetector(
                            onTap: () {
                              _showScopeBottomSheet(context, isPremium);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _selectedScope == 'global' ? LucideIcons.globe : LucideIcons.mapPin,
                                    size: 11,
                                    color: Colors.white60,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _selectedScope.toUpperCase(),
                                    style: const TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(LucideIcons.chevronDown, size: 10, color: Colors.white60),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 2. What's on your mind field
                TextField(
                  controller: _textController,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: _selectedType == 'text' 
                      ? "Write something..." 
                      : "Say something about this media...",
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 16),
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 20),

                // 3. Media Preview Box (Only if type is image/video)
                if (_selectedType != 'text') ...[
                  GestureDetector(
                    onTap: _pickMedia,
                    child: Container(
                      width: double.infinity,
                      height: 240,
                      decoration: BoxDecoration(
                        color: const Color(0xFF151515),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: _mediaFile != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _selectedType == 'image'
                                      ? Image.file(_mediaFile!, fit: BoxFit.cover)
                                      : Container(
                                          color: Colors.black,
                                          child: const Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(LucideIcons.video, size: 48, color: Colors.white54),
                                                SizedBox(height: 10),
                                                Text('Video Selected (Tap to change)', style: TextStyle(color: Colors.white54)),
                                              ],
                                            ),
                                          ),
                                        ),
                                  Positioned(
                                    top: 12,
                                    right: 12,
                                    child: CircleAvatar(
                                      backgroundColor: Colors.black54,
                                      child: IconButton(
                                        icon: const Icon(LucideIcons.x, color: Colors.white),
                                        onPressed: () => setState(() => _mediaFile = null),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _selectedType == 'image' ? LucideIcons.image : LucideIcons.video,
                                  size: 48,
                                  color: Colors.white30,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _selectedType == 'image' 
                                      ? 'Tap to select an image from gallery' 
                                      : 'Tap to select a video from gallery',
                                  style: const TextStyle(color: Colors.white30, fontSize: 13),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // 4. Facebook-style Composer Actions Bar
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Row(
                    children: [
                      _buildBottomBarItem(
                        type: 'text',
                        icon: LucideIcons.fileText,
                        label: 'Text',
                        color: Colors.blueAccent,
                      ),
                      _buildBottomBarItem(
                        type: 'image',
                        icon: LucideIcons.image,
                        label: 'Photo',
                        color: Colors.greenAccent,
                      ),
                      _buildBottomBarItem(
                        type: 'video',
                        icon: LucideIcons.video,
                        label: 'Video',
                        color: Colors.redAccent,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBarItem({
    required String type,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final active = _selectedType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedType = type;
            _mediaFile = null;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? Colors.white.withOpacity(0.05) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: active ? color : Colors.white38, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white38,
                  fontSize: 11,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showScopeBottomSheet(BuildContext context, bool isPremium) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151515),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              const Text('SELECT RANKING SCOPE', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              _buildScopeTile('zip', 'Zip Code', false),
              _buildScopeTile('city', 'City', false),
              _buildScopeTile('state', 'State', false),
              _buildScopeTile('country', 'Country', false),
              _buildScopeTile('global', 'Global 👑', !isPremium),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScopeTile(String scope, String label, bool isLocked) {
    final active = _selectedScope == scope;
    return ListTile(
      leading: Icon(
        scope == 'global' ? LucideIcons.globe : LucideIcons.mapPin,
        color: isLocked ? Colors.orange : (active ? AppTheme.primary : Colors.white54),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isLocked ? Colors.orange.shade300 : (active ? AppTheme.primary : Colors.white),
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
          fontSize: 14,
        ),
      ),
      trailing: isLocked 
        ? const Icon(LucideIcons.lock, size: 14, color: Colors.orange)
        : (active ? const Icon(LucideIcons.check, color: AppTheme.primary, size: 18) : null),
      onTap: () {
        Navigator.pop(context);
        if (isLocked) {
          _showUpgradeDialog();
        } else {
          setState(() => _selectedScope = scope);
        }
      },
    );
  }
}
