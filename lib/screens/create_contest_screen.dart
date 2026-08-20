import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../engine/ranking_engine.dart';
import '../models/entry.dart';
import '../theme/app_theme.dart';
import '../widgets/media_content_preview.dart';
import '../widgets/prize_management_widget.dart';

class CreateContestScreen extends StatefulWidget {
  const CreateContestScreen({super.key});

  @override
  State<CreateContestScreen> createState() => _CreateContestScreenState();
}

class _CreateContestScreenState extends State<CreateContestScreen> {
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _rulesController = TextEditingController();
  final _prizeController = TextEditingController();
  final _scheduleController = TextEditingController();
  final _endsInController = TextEditingController();
  final _cityController = TextEditingController();
  final _countryController = TextEditingController();

  String _selectedCategory = 'Music';
  String _selectedType = 'Public';
  String _selectedVisibilityScope = 'global';
  File? _coverFile;
  bool _isCreating = false;
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  List<Map<String, dynamic>> _prizes = [
    {'id': 'default_1', 'rank': 1, 'amount': '\$200', 'type': 'gold', 'description': 'Cash prize'},
    {'id': 'default_2', 'rank': 2, 'amount': '\$100', 'type': 'silver', 'description': 'Cash prize'},
    {'id': 'default_3', 'rank': 3, 'amount': '\$50', 'type': 'bronze', 'description': 'Cash prize'},
  ];

  final List<String> _categories = ['Music', 'Dance', 'Comedy', 'Art', 'Sports', 'Fashion', 'Photography', 'Gaming', 'Other'];
  final List<String> _types = ['Public', 'Official'];
  final List<String> _visibilityScopes = ['global', 'country', 'city', 'zip'];

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _descriptionController.dispose();
    _rulesController.dispose();
    _prizeController.dispose();
    _scheduleController.dispose();
    _endsInController.dispose();
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

  Future<void> _createContest() async {
    final engine = Provider.of<RankingEngine>(context, listen: false);
    final profile = engine.currentUserProfile;

    // Check if user is premium
    if (profile?.subscriptionLevel != 'premium') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only premium users can create contests'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    // Check if user already has an active contest
    final contests = engine.contests;
    final userContests = contests.where((c) => c.creatorId == profile?.uid).toList();
    if (userContests.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can only create one contest at a time'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a contest title'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (_subtitleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a subtitle'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a description'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (_rulesController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter rules'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (_prizes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one prize'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (_selectedStartDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a start date'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (_selectedEndDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an end date'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (_selectedEndDate!.isBefore(_selectedStartDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date must be after start date'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (_coverFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a cover photo or video'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final engine = Provider.of<RankingEngine>(context, listen: false);

      String imageUrl = 'https://via.placeholder.com/400x200/1E1E1E/FFFFFF?text=Contest';
      if (_coverFile != null) {
        imageUrl = await engine.uploadPostMedia(_coverFile!);
      }

      final contestId = 'contest_${DateTime.now().millisecondsSinceEpoch}';
      
      // Debug logging
      debugPrint('Creating contest with prizes: $_prizes');
      debugPrint('Prizes count: ${_prizes.length}');
      
      final contest = ContestModel(
        id: contestId,
        title: _titleController.text.trim(),
        subtitle: _subtitleController.text.trim(),
        description: _descriptionController.text.trim(),
        rules: _rulesController.text.trim(),
        prize: _prizeController.text.trim(),
        prizes: _prizes,
        schedule: '${_selectedStartDate!.day}/${_selectedStartDate!.month}/${_selectedStartDate!.year}',
        image: imageUrl,
        category: _selectedCategory,
        type: _selectedType,
        participantCount: 0,
        totalVotes: 0,
        rating: 0.0,
        reviewCount: 0,
        endsIn: _endsInController.text.trim().isEmpty ? '30 days' : _endsInController.text.trim(),
        endDate: _selectedEndDate,
        creatorId: profile?.uid ?? '',
        city: _cityController.text.trim().isEmpty ? (profile?.city ?? 'Tunis') : _cityController.text.trim(),
        country: _countryController.text.trim().isEmpty ? (profile?.country ?? 'Tunisia') : _countryController.text.trim(),
        visibilityScope: _selectedVisibilityScope,
      );
      
      debugPrint('Contest toMap prizes: ${contest.toMap()['prizes']}');

      await engine.createContest(contest);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contest created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create contest: $e'), backgroundColor: Colors.redAccent),
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
          'CREATE CONTEST',
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
              'COVER (PHOTO OR VIDEO)',
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
                              'Tap to add cover photo or video',
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
              'CONTEST TITLE',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText: 'e.g. Rock Vocal Challenge',
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

            // Subtitle
            const Text(
              'SUBTITLE',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _subtitleController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText: 'e.g. Battle of the best singers',
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
                hintText: 'Describe your contest...',
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

            // Rules
            const Text(
              'RULES',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _rulesController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText: 'Contest rules and guidelines...',
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

            // Prize Management
            PrizeManagementWidget(
              initialPrizes: _prizes,
              onPrizesChanged: (newPrizes) {
                setState(() {
                  _prizes = newPrizes;
                });
              },
            ),
            const SizedBox(height: 16),

            // Start Date
            const Text(
              'START DATE',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() => _selectedStartDate = picked);
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.calendar, color: Colors.white54, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      _selectedStartDate != null
                          ? '${_selectedStartDate!.day}/${_selectedStartDate!.month}/${_selectedStartDate!.year}'
                          : 'Select start date',
                      style: TextStyle(
                        color: _selectedStartDate != null ? Colors.white : Colors.white30,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // End Date
            const Text(
              'END DATE',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedStartDate?.add(const Duration(days: 30)) ?? DateTime.now().add(const Duration(days: 30)),
                  firstDate: _selectedStartDate ?? DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() => _selectedEndDate = picked);
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.calendar, color: Colors.white54, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      _selectedEndDate != null
                          ? '${_selectedEndDate!.day}/${_selectedEndDate!.month}/${_selectedEndDate!.year}'
                          : 'Select end date',
                      style: TextStyle(
                        color: _selectedEndDate != null ? Colors.white : Colors.white30,
                        fontSize: 14,
                      ),
                    ),
                  ],
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
            const SizedBox(height: 20),

            // Type
            const Text(
              'CONTEST TYPE',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: _types.map((type) {
                final isSelected = _selectedType == type;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedType = type),
                    child: Container(
                      margin: EdgeInsets.only(right: type == 'Public' ? 8 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primary : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        type.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
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
                onPressed: _isCreating ? null : _createContest,
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
                        'CREATE CONTEST',
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
