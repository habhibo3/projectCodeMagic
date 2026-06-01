import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../engine/ranking_engine.dart';
import '../models/entry.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_helper.dart';

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

  String _selectedCategory = 'Music';
  String _selectedType = 'Public';
  File? _coverImage;
  bool _isCreating = false;
  DateTime? _selectedEndDate;

  final List<String> _categories = ['Music', 'Dance', 'Comedy', 'Art', 'Sports', 'Fashion', 'Photography', 'Gaming', 'Other'];
  final List<String> _types = ['Public', 'Official'];

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _descriptionController.dispose();
    _rulesController.dispose();
    _prizeController.dispose();
    _scheduleController.dispose();
    _endsInController.dispose();
    super.dispose();
  }

  Future<void> _pickCoverImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() {
        _coverImage = File(picked.path);
      });
    }
  }

  Future<void> _createContest() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a contest title'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (_selectedEndDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an end date'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final engine = Provider.of<RankingEngine>(context, listen: false);

      String imageUrl = 'https://via.placeholder.com/400x200/1E1E1E/FFFFFF?text=Contest';
      if (_coverImage != null) {
        imageUrl = await engine.uploadPostMedia(_coverImage!);
      }

      final contestId = 'contest_${DateTime.now().millisecondsSinceEpoch}';
      final contest = ContestModel(
        id: contestId,
        title: _titleController.text.trim(),
        subtitle: _subtitleController.text.trim(),
        description: _descriptionController.text.trim(),
        rules: _rulesController.text.trim(),
        prize: _prizeController.text.trim(),
        schedule: _scheduleController.text.trim(),
        image: imageUrl,
        category: _selectedCategory,
        type: _selectedType,
        participantCount: 0,
        totalVotes: 0,
        rating: 0.0,
        reviewCount: 0,
        endsIn: _endsInController.text.trim().isEmpty ? '30 days' : _endsInController.text.trim(),
        endDate: _selectedEndDate,
      );

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
        actions: [
          if (_isCreating)
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
              onPressed: _createContest,
              child: const Text(
                'CREATE',
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
            // Cover Image
            const Text(
              'COVER IMAGE',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickCoverImage,
              child: Container(
                width: double.infinity,
                height: 180,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: _coverImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(_coverImage!, fit: BoxFit.cover),
                      )
                    : const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.imagePlus, color: Colors.white30, size: 40),
                            SizedBox(height: 8),
                            Text(
                              'Tap to add cover image',
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

            // Prize
            const Text(
              'PRIZE',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _prizeController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'e.g. \$500 Cash prize',
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

            // Schedule
            const Text(
              'SCHEDULE',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _scheduleController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'e.g. Starts: June 1, Ends: June 30',
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

            // Ends In
            const Text(
              'END DATE',
              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 30)),
                  firstDate: DateTime.now(),
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
          ],
        ),
      ),
    );
  }
}
