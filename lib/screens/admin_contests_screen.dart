import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/admin_service.dart';
import '../data/firebase_service.dart';
import '../models/entry.dart';
import '../theme/app_theme.dart';

class AdminContestsScreen extends StatefulWidget {
  const AdminContestsScreen({super.key});

  @override
  State<AdminContestsScreen> createState() => _AdminContestsScreenState();
}

class _AdminContestsScreenState extends State<AdminContestsScreen> {
  final AdminService _adminService = AdminService();
  final FirebaseService _firebaseService = FirebaseService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _buildContestsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Contest Management',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create, edit, delete, and approve contests',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.search, color: Colors.white54, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Search contests...',
                            hintStyle: TextStyle(color: Colors.white38),
                            border: InputBorder.none,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value.toLowerCase();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(LucideIcons.plus, size: 18),
                label: const Text('Create Contest'),
                onPressed: () => _showCreateContestDialog(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContestsList() {
    return StreamBuilder<List<ContestModel>>(
      stream: _firebaseService.getContests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text(
              'No contests found',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        final contests = snapshot.data!;
        final filteredContests = _searchQuery.isEmpty
            ? contests
            : contests.where((contest) =>
                contest.title.toLowerCase().contains(_searchQuery) ||
                contest.category.toLowerCase().contains(_searchQuery)).toList();

        return ListView.builder(
          padding: const EdgeInsets.all(32),
          itemCount: filteredContests.length,
          itemBuilder: (context, index) {
            final contest = filteredContests[index];
            return _buildContestCard(contest);
          },
        );
      },
    );
  }

  Widget _buildContestCard(ContestModel contest) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (contest.image.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    contest.image,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(LucideIcons.trophy, color: AppTheme.primary),
                    ),
                  ),
                )
              else
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(LucideIcons.trophy, color: AppTheme.primary),
                ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            contest.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _buildStatusBadge(contest),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      contest.category,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildStatChip(LucideIcons.users, '${contest.participantCount}'),
                        const SizedBox(width: 8),
                        _buildStatChip(LucideIcons.heart, '${contest.totalVotes}'),
                        const SizedBox(width: 8),
                        _buildStatChip(LucideIcons.star, contest.rating.toStringAsFixed(1)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  'View Details',
                  LucideIcons.eye,
                  Colors.blue,
                  () => _showContestDetails(contest),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  'Edit',
                  LucideIcons.edit,
                  Colors.orange,
                  () => _showEditContestDialog(contest),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  'Delete',
                  LucideIcons.trash2,
                  Colors.red,
                  () => _showDeleteContestDialog(contest),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(ContestModel contest) {
    final isActive = contest.endDate == null || contest.endDate!.isAfter(DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isActive ? 'Active' : 'Ended',
        style: TextStyle(
          color: isActive ? Colors.green : Colors.grey,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white54),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContestDetails(ContestModel contest) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        title: Text(
          contest.title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Description', contest.description),
              _buildDetailRow('Rules', contest.rules),
              _buildDetailRow('Prize', contest.prize),
              _buildDetailRow('Schedule', contest.schedule),
              _buildDetailRow('Category', contest.category),
              _buildDetailRow('Type', contest.type),
              _buildDetailRow('Participants', contest.participantCount.toString()),
              _buildDetailRow('Total Votes', contest.totalVotes.toString()),
              _buildDetailRow('Rating', contest.rating.toStringAsFixed(1)),
              _buildDetailRow('Location', '${contest.city}, ${contest.country}'),
              if (contest.endDate != null)
                _buildDetailRow('End Date', contest.endDate.toString().split('.')[0]),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateContestDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final rulesController = TextEditingController();
    final prizeController = TextEditingController();
    final categoryController = TextEditingController();
    final typeController = TextEditingController(text: 'Public');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        title: const Text(
          'Create Contest',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField(titleController, 'Title'),
              const SizedBox(height: 12),
              _buildTextField(descriptionController, 'Description', maxLines: 3),
              const SizedBox(height: 12),
              _buildTextField(rulesController, 'Rules', maxLines: 3),
              const SizedBox(height: 12),
              _buildTextField(prizeController, 'Prize'),
              const SizedBox(height: 12),
              _buildTextField(categoryController, 'Category'),
              const SizedBox(height: 12),
              _buildTextField(typeController, 'Type (Public/Official)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (titleController.text.isEmpty) return;
              
              final contest = ContestModel(
                id: 'contest_${DateTime.now().millisecondsSinceEpoch}',
                title: titleController.text,
                subtitle: '',
                description: descriptionController.text,
                rules: rulesController.text,
                prize: prizeController.text,
                schedule: '',
                image: '',
                category: categoryController.text,
                type: typeController.text,
                participantCount: 0,
                totalVotes: 0,
                rating: 0,
                reviewCount: 0,
                endsIn: '30 days',
              );
              
              await _adminService.updateContest(contest.id, contest.toMap());
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Contest created successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showEditContestDialog(ContestModel contest) {
    final titleController = TextEditingController(text: contest.title);
    final descriptionController = TextEditingController(text: contest.description);
    final rulesController = TextEditingController(text: contest.rules);
    final prizeController = TextEditingController(text: contest.prize);
    final categoryController = TextEditingController(text: contest.category);
    final typeController = TextEditingController(text: contest.type);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        title: const Text(
          'Edit Contest',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField(titleController, 'Title'),
              const SizedBox(height: 12),
              _buildTextField(descriptionController, 'Description', maxLines: 3),
              const SizedBox(height: 12),
              _buildTextField(rulesController, 'Rules', maxLines: 3),
              const SizedBox(height: 12),
              _buildTextField(prizeController, 'Prize'),
              const SizedBox(height: 12),
              _buildTextField(categoryController, 'Category'),
              const SizedBox(height: 12),
              _buildTextField(typeController, 'Type (Public/Official)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final updatedContest = ContestModel(
                id: contest.id,
                title: titleController.text,
                subtitle: contest.subtitle,
                description: descriptionController.text,
                rules: rulesController.text,
                prize: prizeController.text,
                schedule: contest.schedule,
                image: contest.image,
                category: categoryController.text,
                type: typeController.text,
                participantCount: contest.participantCount,
                totalVotes: contest.totalVotes,
                rating: contest.rating,
                reviewCount: contest.reviewCount,
                endsIn: contest.endsIn,
                endDate: contest.endDate,
                creatorId: contest.creatorId,
                city: contest.city,
                country: contest.country,
                latitude: contest.latitude,
                longitude: contest.longitude,
                visibilityScope: contest.visibilityScope,
              );
              
              await _adminService.updateContest(contest.id, updatedContest.toMap());
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Contest updated successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
      ),
    );
  }

  void _showDeleteContestDialog(ContestModel contest) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.red, width: 1),
        ),
        title: const Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: Colors.red),
            SizedBox(width: 12),
            Text(
              'Delete Contest',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "${contest.title}"?',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: const Text(
                '⚠️ This will delete all entries and votes associated with this contest. This action cannot be undone.',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await _adminService.deleteContest(contest.id);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${contest.title} has been deleted'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Delete Contest'),
          ),
        ],
      ),
    );
  }
}
