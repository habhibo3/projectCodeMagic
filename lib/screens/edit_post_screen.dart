import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../engine/ranking_engine.dart';
import '../models/post.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_helper.dart';

class EditPostScreen extends StatefulWidget {
  final PostModel post;

  const EditPostScreen({super.key, required this.post});

  @override
  State<EditPostScreen> createState() => _EditPostScreenState();
}

class _EditPostScreenState extends State<EditPostScreen> {
  late TextEditingController _textController;
  late String _selectedType;
  late String _selectedScope;
  File? _mediaFile;
  bool _isUploading = false;
  bool _mediaChanged = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.post.type == 'text' ? widget.post.contentUrl : widget.post.caption);
    _selectedType = widget.post.type;
    _selectedScope = widget.post.visibilityScope;
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
          _mediaChanged = true;
        });
      }
    } else if (_selectedType == 'video') {
      final picked = await picker.pickVideo(source: ImageSource.gallery);
      if (picked != null) {
        setState(() {
          _mediaFile = File(picked.path);
          _mediaChanged = true;
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
    final engine = Provider.of<RankingEngine>(context, listen: false);
    final profile = engine.currentUserProfile;
    if (profile == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    final isPremium = profile.subscriptionLevel == 'premium';

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
          'EDIT POST',
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
                if (_selectedType != 'text' && _mediaFile == null && !_mediaChanged) {
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
                  String mediaUrl = widget.post.contentUrl;
                  if (_mediaChanged && _mediaFile != null) {
                    mediaUrl = await engine.uploadPostMedia(_mediaFile!);
                  }

                  await engine.updatePost(
                    widget.post.id,
                    type: _selectedType,
                    contentUrl: _selectedType == 'text' ? _textController.text.trim() : mediaUrl,
                    caption: _selectedType == 'text' ? 'A text performance' : _textController.text.trim(),
                    visibilityScope: _selectedScope,
                  );

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Post successfully updated!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to update post: $e'), backgroundColor: Colors.redAccent),
                    );
                  }
                } finally {
                  setState(() => _isUploading = false);
                }
              },
              child: const Text(
                'SAVE',
                style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Post Type Selector
            const Text(
              'POST TYPE',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildTypeChip('text', LucideIcons.fileText),
                const SizedBox(width: 8),
                _buildTypeChip('image', LucideIcons.image),
                const SizedBox(width: 8),
                _buildTypeChip('video', LucideIcons.video),
              ],
            ),
            const SizedBox(height: 20),

            // Visibility Scope Selector
            const Text(
              'VISIBILITY SCOPE',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildScopeChip('zip', isPremium),
                _buildScopeChip('city', isPremium),
                _buildScopeChip('state', isPremium),
                _buildScopeChip('country', isPremium),
                _buildScopeChip('global', isPremium),
              ],
            ),
            const SizedBox(height: 20),

            // Media Picker / Text Input
            if (_selectedType == 'text')
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'YOUR TEXT',
                    style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _textController,
                    maxLines: 6,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'What\'s on your mind?',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MEDIA',
                    style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _pickMedia,
                    child: Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: _mediaFile != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _selectedType == 'video'
                                  ? const Center(
                                      child: Icon(LucideIcons.video, color: AppTheme.primary, size: 48),
                                    )
                                  : Image.file(_mediaFile!, fit: BoxFit.cover),
                            )
                          : widget.post.contentUrl.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: _selectedType == 'video'
                                      ? const Center(
                                          child: Icon(LucideIcons.video, color: AppTheme.primary, size: 48),
                                        )
                                      : AvatarHelper.getSafePostImage(widget.post.contentUrl, fit: BoxFit.cover),
                                )
                              : Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(LucideIcons.plus, color: Colors.white30, size: 32),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Tap to add ${_selectedType == 'image' ? 'image' : 'video'}',
                                        style: const TextStyle(color: Colors.white30, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _textController,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Add a caption...',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String type, IconData icon) {
    final isSelected = _selectedType == type;
    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.white54),
            const SizedBox(width: 6),
            Text(
              type.toUpperCase(),
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeChip(String scope, bool isPremium) {
    final isSelected = _selectedScope == scope;
    final isGlobal = scope == 'global';
    return GestureDetector(
      onTap: () {
        if (isGlobal && !isPremium) {
          _showUpgradeDialog();
          return;
        }
        setState(() => _selectedScope = scope);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(100),
          border: isGlobal && !isPremium
              ? Border.all(color: const Color(0xFFC9A227), width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              scope == 'global' ? LucideIcons.globe : LucideIcons.mapPin,
              size: 14,
              color: isGlobal && !isPremium
                  ? const Color(0xFFC9A227)
                  : isSelected
                      ? Colors.white
                      : Colors.white54,
            ),
            const SizedBox(width: 6),
            Text(
              scope.toUpperCase(),
              style: TextStyle(
                color: isGlobal && !isPremium
                    ? const Color(0xFFC9A227)
                    : isSelected
                        ? Colors.white
                        : Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isGlobal && !isPremium) ...[
              const SizedBox(width: 4),
              const Icon(LucideIcons.crown, size: 10, color: Color(0xFFC9A227)),
            ],
          ],
        ),
      ),
    );
  }
}
