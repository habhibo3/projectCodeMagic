import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_theme.dart';

class CommunitySafetyHelper {
  /// Displays the End User License Agreement (EULA) and Community Guidelines.
  static void showEula(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF161618),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white12, width: 1),
        ),
        title: const Row(
          children: [
            Icon(LucideIcons.fileText, color: AppTheme.primary, size: 22),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Terms of Service & EULA',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(LucideIcons.alertTriangle, color: Colors.redAccent, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Zero Tolerance Policy: There is strictly NO tolerance for objectionable, harmful, hateful, sexually explicit, or abusive content or users.',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '1. Acceptance of Terms',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  'By creating an account or using this application, you agree to comply with this End User License Agreement (EULA) and Community Safety Guidelines.',
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 12),
                const Text(
                  '2. User Conduct & Content Standards',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Users may not upload, post, transmit, or stream any content that is offensive, defamatory, harassing, sexually explicit, promoting illegal activities, or infringing on intellectual property.',
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 12),
                const Text(
                  '3. Content Moderation & Enforcement',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  'All user reports are investigated within 24 hours. Offending content will be immediately removed, and users who violate these terms will be ejected and permanently banned.',
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 12),
                const Text(
                  '4. Blocking & Reporting',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  'You may report any objectionable content or block abusive users at any time using the in-app reporting and blocking features.',
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('I Understand', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Displays the Report Content / User dialog.
  static void showReportDialog(
    BuildContext context, {
    required String targetId,
    required String targetType, // 'post', 'entry', 'station', 'user', 'comment'
    String? targetName,
  }) {
    String selectedReason = 'Inappropriate Content';
    final List<String> reasons = [
      'Inappropriate Content',
      'Abusive or Harassing Behavior',
      'Hate Speech or Bullying',
      'Spam or Scam',
      'Violence or Dangerous Acts',
      'Copyright Infringement',
      'Other Violation',
    ];

    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF161618),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Colors.white12, width: 1),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.flag, color: Colors.redAccent, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Report ${targetType[0].toUpperCase()}${targetType.substring(1)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Please select the reason for reporting this $targetType:',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ...reasons.map((reason) {
                  final isSelected = selectedReason == reason;
                  return InkWell(
                    onTap: () => setState(() => selectedReason = reason),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: isSelected ? AppTheme.primary : Colors.white38,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              reason,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white60,
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF222226),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(LucideIcons.shieldCheck, color: Colors.white38, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Our moderation team reviews all reports within 24 hours.',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        setState(() => isSubmitting = true);
                        try {
                          final currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
                          await FirebaseFirestore.instance.collection('reports').add({
                            'targetId': targetId,
                            'targetType': targetType,
                            'targetName': targetName ?? '',
                            'reason': selectedReason,
                            'reportedBy': currentUid,
                            'status': 'pending',
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                        } catch (e) {
                          debugPrint('Error creating report: $e');
                        }

                        if (context.mounted) {
                          Navigator.of(dialogContext).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Report submitted. We will review it within 24 hours.'),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                child: const Text('Submit Report', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Displays the Block User dialog and records the block in Firestore.
  static void showBlockUserDialog(
    BuildContext context, {
    required String userId,
    required String userName,
    VoidCallback? onUserBlocked,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF161618),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white12, width: 1),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.userX, color: Colors.redAccent, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Block User',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to block $userName?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 10),
            const Text(
              'You will no longer see posts, stations, or live content from this user. Blocking also automatically alerts our moderation team.',
              style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () async {
              try {
                final currentUid = FirebaseAuth.instance.currentUser?.uid;
                if (currentUid != null && currentUid.isNotEmpty) {
                  // Save blocked user record
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(currentUid)
                      .collection('blocked_users')
                      .doc(userId)
                      .set({
                    'blockedUserId': userId,
                    'blockedUserName': userName,
                    'createdAt': FieldValue.serverTimestamp(),
                  });

                  // Log moderation alert
                  await FirebaseFirestore.instance.collection('reports').add({
                    'targetId': userId,
                    'targetType': 'user_block',
                    'targetName': userName,
                    'reason': 'User Blocked by $currentUid',
                    'reportedBy': currentUid,
                    'status': 'pending',
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                }
              } catch (e) {
                debugPrint('Error blocking user: $e');
              }

              if (context.mounted) {
                Navigator.of(dialogContext).pop();
                onUserBlocked?.call();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$userName has been blocked.'),
                    backgroundColor: Colors.redAccent,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Block User', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
