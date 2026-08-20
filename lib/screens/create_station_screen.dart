import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../data/firebase_service.dart';
import '../engine/ranking_engine.dart';
import '../models/station.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import '../widgets/media_content_preview.dart';

class CreateStationScreen extends StatefulWidget {
  const CreateStationScreen({super.key});

  @override
  State<CreateStationScreen> createState() => _CreateStationScreenState();
}

class _CreateStationScreenState extends State<CreateStationScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _cityController = TextEditingController();
  final _countryController = TextEditingController();

  String _selectedCategory = 'Music';
  String _selectedVisibilityScope = 'global';
  File? _coverFile;
  bool _isCreating = false;

  final List<String> _categories = ['Music', 'Dance', 'Comedy', 'Art', 'Sports', 'Gaming', 'Talk', 'News', 'Other'];
  final List<String> _visibilityScopes = ['global', 'country', 'city', 'zip'];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _pickCoverMedia() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);

    if (picked != null && mounted) {
      setState(() {
        _coverFile = File(picked.path);
      });
    }
  }

  Future<void> _createStation() async {
    // Get current user profile from RankingEngine
    final engine = Provider.of<RankingEngine>(context, listen: false);
    final profile = engine.currentUserProfile;
    
    if (profile == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User profile not found'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    if (_titleController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a station title'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a description'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    if (_coverFile == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a cover photo'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    setState(() => _isCreating = true);

    try {
      // Check if user already has a station and delete it
      final existingStations = await _firebaseService.getStations().first;
      final userStation = existingStations.where((s) => s.creatorId == profile.uid).toList();
      
      if (userStation.isNotEmpty) {
        // Delete existing station
        for (var oldStation in userStation) {
          await _firebaseService.deleteStation(oldStation.id);
          debugPrint('Deleted existing station: ${oldStation.id}');
        }
      }

      String imageUrl = 'https://via.placeholder.com/400x200/1E1E1E/FFFFFF?text=Station';
      if (_coverFile != null) {
        imageUrl = await _firebaseService.uploadPostMedia(engine.currentUserId, _coverFile!);
      }

      final stationId = StationModel.normalizeId(
        'station_${DateTime.now().millisecondsSinceEpoch}',
      );
      
      final station = StationModel(
        id: stationId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        image: imageUrl,
        coverType: 'image',
        category: _selectedCategory,
        viewerCount: 0,
        rating: 0.0,
        reviewCount: 0,
        creatorId: profile.uid,
        creatorName: profile.displayName,
        creatorAvatar: profile.photoURL,
        city: _cityController.text.trim().isEmpty ? (profile.city ?? 'Tunis') : _cityController.text.trim(),
        country: _countryController.text.trim().isEmpty ? (profile.country ?? 'Tunisia') : _countryController.text.trim(),
        countryFlag: profile.countryFlag,
        latitude: null,
        longitude: null,
        visibilityScope: _selectedVisibilityScope,
        createdAt: DateTime.now(),
        isLive: false,
        currentLiveChannelId: null,
      );

      await _firebaseService.createStation(station);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Station created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create station: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          'CREATE STATION',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover media
            const Text(
              'COVER PHOTO',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickCoverMedia,
              child: Container(
                width: double.infinity,
                height: 180,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: _coverFile != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: kIsWeb
                            ? Image.network(
                                _coverFile!.path,
                                width: double.infinity,
                                height: 180,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey.shade900,
                                    child: const Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            LucideIcons.image,
                                            color: Colors.white30,
                                            size: 48,
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            'Failed to load image',
                                            style: TextStyle(color: Colors.white54, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              )
                            : MediaContentPreview(
                                type: 'image',
                                contentUrl: _coverFile!.path,
                                height: 180,
                                autoPlayVideo: true,
                              ),
                      )
                    : const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.imagePlus, color: Colors.white30, size: 40),
                            SizedBox(height: 8),
                            Text(
                              'Tap to add cover photo',
                              style: TextStyle(color: Colors.white30, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            const Text(
              'STATION TITLE',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText: 'e.g. My Music Station',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Description
            const Text(
              'DESCRIPTION',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText: 'Describe your station...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Location Section
            const Text(
              'LOCATION',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cityController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      hintText: 'City',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _countryController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      hintText: 'Country',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Visibility Scope
            const Text(
              'VISIBILITY SCOPE',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _visibilityScopes.map((scope) {
                final isSelected = _selectedVisibilityScope == scope;
                return GestureDetector(
                  onTap: () => setState(() => _selectedVisibilityScope = scope),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primary : const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      scope.toUpperCase(),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Category
            const Text(
              'CATEGORY',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((category) {
                final isSelected = _selectedCategory == category;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = category),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primary : const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      category.toUpperCase(),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),

            // Create Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isCreating ? null : _createStation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isCreating
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'CREATE STATION',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
