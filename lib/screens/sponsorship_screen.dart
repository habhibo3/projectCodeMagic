import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/sponsorship_service.dart';
import '../theme/app_theme.dart';
import '../widgets/media_content_preview.dart';

class SponsorshipScreen extends StatefulWidget {
  final String ownerType;
  final String ownerId;
  final String ownerTitle;
  final bool isOwner;

  const SponsorshipScreen({
    super.key,
    required this.ownerType,
    required this.ownerId,
    required this.ownerTitle,
    required this.isOwner,
  });

  @override
  State<SponsorshipScreen> createState() => _SponsorshipScreenState();
}

class _SponsorshipScreenState extends State<SponsorshipScreen> {
  final SponsorshipService _service = SponsorshipService.instance;
  int _durationMonths = 1;
  String? _busyKey;

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(String key, Future<void> Function() action) async {
    if (_busyKey != null) return;
    setState(() => _busyKey = key);
    try {
      await action();
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.platformDefault)) {
      throw Exception('Could not open the secure Stripe page.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: Text('Sponsors · ${widget.ownerTitle}', maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          _buildIntro(),
          const SizedBox(height: 18),
          if (widget.isOwner) _buildPayoutSetup(),
          if (widget.isOwner) _buildOwnerTiers() else _buildAvailableTiers(),
          if (!widget.isOwner) ...[
            const SizedBox(height: 22),
            _buildMySponsorships(),
          ],
        ],
      ),
    );
  }

  Widget _buildIntro() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.heart, color: AppTheme.primary, size: 22),
          const SizedBox(width: 10),
          Text('Support this ${widget.ownerType.toLowerCase()}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
        ]),
        const SizedBox(height: 8),
        Text(
          widget.isOwner
              ? 'Create custom sponsor tiers, set the available slots, and review your payout setup.'
              : 'Choose a sponsor tier. Your artwork will appear after payment and admin approval.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        if (!widget.isOwner && widget.ownerType == 'STATION') ...[
          const SizedBox(height: 14),
          Row(children: [
            const Text('Sponsor duration', style: TextStyle(color: Colors.white70)),
            const Spacer(),
            DropdownButton<int>(
              value: _durationMonths,
              dropdownColor: const Color(0xFF222226),
              style: const TextStyle(color: Colors.white),
              items: List.generate(24, (i) => DropdownMenuItem(
                value: i + 1,
                child: Text('${i + 1} month${i == 0 ? '' : 's'}'),
              )),
              onChanged: (value) => setState(() => _durationMonths = value ?? 1),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _buildPayoutSetup() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _service.getOwnerConnectAccount(),
      builder: (context, snapshot) {
        final accountId = snapshot.data?['stripeConnectAccountId'] as String?;
        return Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF151515),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(children: [
            Icon(accountId == null ? LucideIcons.creditCard : LucideIcons.checkCircle,
                color: accountId == null ? Colors.amber : Colors.greenAccent),
            const SizedBox(width: 12),
            Expanded(child: Text(
              accountId == null ? 'Set up Stripe payouts before accepting sponsors.' : 'Stripe payout account linked. Stripe may still be verifying it.',
              style: const TextStyle(color: Colors.white70),
            )),
            TextButton(
              onPressed: _busyKey == 'connect' ? null : () => _run('connect', () async {
                final url = await _service.startPayoutSetup();
                await _openUrl(url);
                if (mounted) setState(() {});
              }),
              child: Text(_busyKey == 'connect' ? 'Opening…' : 'Set up'),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildAvailableTiers() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.watchTiers(ownerType: widget.ownerType, ownerId: widget.ownerId),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs.where((doc) => doc.data()['active'] == true).toList() ?? [];
        docs.sort((a, b) => (a.data()['price'] as num? ?? 0).compareTo(b.data()['price'] as num? ?? 0));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SectionHeading('AVAILABLE TIERS'),
          if (snapshot.hasError) const _EmptyMessage('Could not load sponsor tiers.'),
          if (docs.isEmpty && !snapshot.hasError) const _EmptyMessage('No sponsor tiers are available yet.'),
          ...docs.map((doc) => _tierCard(doc.id, doc.data(), ownerControls: false)),
        ]);
      },
    );
  }

  Widget _buildOwnerTiers() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.watchTiers(ownerType: widget.ownerType, ownerId: widget.ownerId),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: _SectionHeading('YOUR TIERS')),
            FilledButton.icon(
              onPressed: _busyKey == 'new_tier' ? null : () => _showTierEditor(),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Add tier'),
            ),
          ]),
          if (snapshot.hasError) const _EmptyMessage('Could not load your tiers.'),
          if (docs.isEmpty && !snapshot.hasError) const _EmptyMessage('Create your first custom sponsor tier.'),
          ...docs.map((doc) => _tierCard(doc.id, doc.data(), ownerControls: true)),
        ]);
      },
    );
  }

  Widget _tierCard(String tierId, Map<String, dynamic> tier, {required bool ownerControls}) {
    final price = (tier['price'] as num? ?? 0).toInt();
    final filled = (tier['quantityFilled'] as num? ?? 0).toInt();
    final available = (tier['quantityAvailable'] as num? ?? 0).toInt();
    final soldOut = filled >= available;
    final active = tier['active'] == true;
    final monthly = tier['billingPeriod'] == 'MONTHLY';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151518),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(tier['name'] as String? ?? 'Sponsor',
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold))),
          Text('\$${(price / 100).toStringAsFixed(2)}${monthly ? ' / month' : ''}',
              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        Text('${tier['bannerSize'] ?? 'MEDIUM'} artwork · $filled / $available slots filled${active ? '' : ' · paused'}',
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 12),
        if (ownerControls)
          Wrap(spacing: 8, children: [
            OutlinedButton(
              onPressed: () => _showTierEditor(tierId: tierId, current: tier),
              child: const Text('Edit'),
            ),
            OutlinedButton(
              onPressed: () => _run('tier_$tierId', () => _service.updateTier(tierId, {'active': !active})),
              child: Text(active ? 'Pause' : 'Activate'),
            ),
          ])
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: soldOut || _busyKey != null ? null : () => _run('buy_$tierId', () async {
                final url = await _service.startCheckout(tierId, _durationMonths);
                await _openUrl(url);
              }),
              child: Text(_busyKey == 'buy_$tierId' ? 'Opening checkout…' : soldOut ? 'Sold out' : 'Become a sponsor'),
            ),
          ),
      ]),
    );
  }

  Future<void> _showTierEditor({String? tierId, Map<String, dynamic>? current}) async {
    final name = TextEditingController(text: current?['name'] as String? ?? '');
    final price = TextEditingController(
      text: current == null ? '' : (((current['price'] as num? ?? 0) / 100).toStringAsFixed(2)),
    );
    final quantity = TextEditingController(text: '${current?['quantityAvailable'] ?? 10}');
    var bannerSize = current?['bannerSize'] as String? ?? 'MEDIUM';
    var billingPeriod = current?['billingPeriod'] as String? ?? 'ONE_TIME';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF19191D),
        title: Text(tierId == null ? 'Create sponsor tier' : 'Edit sponsor tier', style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _input(name, 'Tier name'),
          _input(price, 'Price in USD', keyboard: TextInputType.number),
          _input(quantity, 'Available slots', keyboard: TextInputType.number),
          DropdownButtonFormField<String>(
            value: bannerSize,
            dropdownColor: const Color(0xFF222226),
            decoration: const InputDecoration(labelText: 'Artwork size'),
            items: const [
              DropdownMenuItem(value: 'LARGE', child: Text('Large')),
              DropdownMenuItem(value: 'MEDIUM', child: Text('Medium')),
              DropdownMenuItem(value: 'SMALL', child: Text('Small')),
            ],
            onChanged: (value) => setDialogState(() => bannerSize = value ?? 'MEDIUM'),
          ),
          if (widget.ownerType == 'STATION')
            DropdownButtonFormField<String>(
              value: billingPeriod,
              dropdownColor: const Color(0xFF222226),
              decoration: const InputDecoration(labelText: 'Billing'),
              items: const [
                DropdownMenuItem(value: 'ONE_TIME', child: Text('One-time for selected duration')),
                DropdownMenuItem(value: 'MONTHLY', child: Text('Monthly recurring')),
              ],
              onChanged: (value) => setDialogState(() => billingPeriod = value ?? 'ONE_TIME'),
            ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final amount = double.tryParse(price.text.trim());
            final slots = int.tryParse(quantity.text.trim());
            if (name.text.trim().isEmpty || amount == null || slots == null) return;
            Navigator.pop(context, {
              'name': name.text.trim(),
              'price': (amount * 100).round(),
              'quantityAvailable': slots,
              'bannerSize': bannerSize,
              'billingPeriod': billingPeriod,
            });
          }, child: const Text('Save')),
        ],
      )),
    );
    name.dispose();
    price.dispose();
    quantity.dispose();
    if (result == null || !mounted) return;
    await _run('tier_save', () async {
      if (tierId == null) {
        await _service.createTier({
          'ownerType': widget.ownerType,
          'ownerId': widget.ownerId,
          ...result,
        });
      } else {
        await _service.updateTier(tierId, result);
      }
    });
  }

  Widget _input(TextEditingController controller, String label, {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.white60)),
      ),
    );
  }

  Widget _buildMySponsorships() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.watchMySponsorships(ownerType: widget.ownerType, ownerId: widget.ownerId),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SectionHeading('YOUR SPONSORSHIPS'),
          ...docs.map((doc) {
            final data = doc.data();
            final status = data['status'] as String? ?? 'PENDING_PAYMENT';
            final artworkStatus = data['artworkStatus'] as String? ?? 'NOT_SUBMITTED';
            return Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF151518), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(LucideIcons.checkCircle, color: AppTheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${data['sponsorName'] ?? 'Sponsor'} · $status', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  Text('Artwork: $artworkStatus', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ])),
                if (status == 'ACTIVE' && artworkStatus != 'APPROVED')
                  IconButton(
                    tooltip: 'Upload artwork',
                    onPressed: _busyKey == 'art_${doc.id}' ? null : () => _run('art_${doc.id}', () async {
                      final media = await ImagePicker().pickMedia();
                      if (media != null) await _service.uploadArtwork(doc.id, media);
                    }),
                    icon: const Icon(LucideIcons.image, color: Colors.white70),
                  ),
              ]),
            );
          }),
        ]);
      },
    );
  }
}

class SponsorshipBannerStrip extends StatelessWidget {
  final String ownerType;
  final String ownerId;

  const SponsorshipBannerStrip({super.key, required this.ownerType, required this.ownerId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: SponsorshipService.instance.watchSponsors(ownerType: ownerType, ownerId: ownerId),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();
        final ordered = [...docs]..sort((a, b) {
          const rank = {'LARGE': 0, 'MEDIUM': 1, 'SMALL': 2};
          final aSize = a.data()['bannerSize'] as String? ?? 'MEDIUM';
          final bSize = b.data()['bannerSize'] as String? ?? 'MEDIUM';
          return (rank[aSize] ?? 1).compareTo(rank[bSize] ?? 1);
        });
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF141416), borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('SUPPORTED BY', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 11)),
                const SizedBox(height: 10),
                Wrap(spacing: 10, runSpacing: 10, children: ordered.map((doc) {
                  final data = doc.data();
                  final size = data['bannerSize'] as String? ?? 'MEDIUM';
                  final width = size == 'LARGE' ? 250.0 : size == 'SMALL' ? 120.0 : 180.0;
                  final height = size == 'LARGE' ? 96.0 : size == 'SMALL' ? 48.0 : 70.0;
                  final url = data['artworkUrl'] as String? ?? '';
                  final video = (data['artworkContentType'] as String? ?? '').startsWith('video/');
                  return SizedBox(
                    width: width,
                    height: height,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Stack(fit: StackFit.expand, children: [
                        if (url.isNotEmpty)
                          MediaContentPreview(
                            type: video ? 'video' : 'image',
                            contentUrl: url,
                            height: height,
                            fit: BoxFit.cover,
                            autoPlayVideo: false,
                            videoThumbnailMode: true,
                          )
                        else
                          const ColoredBox(color: Color(0xFF222226)),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                            color: Colors.black54,
                            child: Text(data['sponsorName'] as String? ?? 'Sponsor',
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ]),
                    ),
                  );
                }).toList()),
              ]),
            );
      },
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String text;
  const _SectionHeading(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text, style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 11)),
      );
}

class _EmptyMessage extends StatelessWidget {
  final String text;
  const _EmptyMessage(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(text, style: const TextStyle(color: Colors.white54)),
      );
}

class SponsorshipMarketplaceSection extends StatelessWidget {
  final String ownerType;
  final String ownerId;
  final String ownerTitle;
  final String ownerUserId;

  const SponsorshipMarketplaceSection({
    super.key,
    required this.ownerType,
    required this.ownerId,
    required this.ownerTitle,
    required this.ownerUserId,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SponsorshipBannerStrip(ownerType: ownerType, ownerId: ownerId),
      const SizedBox(height: 14),
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SponsorshipScreen(
              ownerType: ownerType,
              ownerId: ownerId,
              ownerTitle: ownerTitle,
              isOwner: FirebaseAuth.instance.currentUser?.uid == ownerUserId,
            ),
          )),
          child: Ink(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF24131D), Color(0xFF17141C)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.42)),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: AppTheme.pinkPurpleGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(LucideIcons.heart, color: Colors.white, size: 21),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sponsorships and support',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Explore ways to support this ${ownerType.toLowerCase()}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.arrowRight,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class PendingSponsorshipArtworkScreen extends StatelessWidget {
  const PendingSponsorshipArtworkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: SponsorshipService.instance.watchPendingReview(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        if (snapshot.hasError) return const Center(child: Text('Unable to load pending sponsorships'));
        if (docs.isEmpty) return const Center(child: Text('No sponsor artwork is waiting for review'));
        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            return Card(
              color: const Color(0xFF171719),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${data['ownerTitle'] ?? data['ownerId']} · ${data['sponsorName'] ?? 'Sponsor'}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if ((data['artworkUrl'] as String? ?? '').isNotEmpty)
                    SizedBox(
                      height: 180,
                      child: MediaContentPreview(
                        type: (data['artworkContentType'] as String? ?? '').startsWith('video/') ? 'video' : 'image',
                        contentUrl: data['artworkUrl'] as String,
                        height: 180,
                        videoThumbnailMode: true,
                      ),
                    ),
                  Text('Tier: ${data['tierId']} · ${((data['amountPaid'] as num? ?? 0) / 100).toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white60)),
                  Row(children: [
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          await SponsorshipService.instance.reviewArtwork(doc.id, approve: true);
                        } catch (error) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                        }
                      },
                      icon: const Icon(LucideIcons.check, color: Colors.greenAccent),
                      label: const Text('Approve'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          await SponsorshipService.instance.reviewArtwork(doc.id, approve: false);
                        } catch (error) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                        }
                      },
                      icon: const Icon(LucideIcons.x, color: Colors.redAccent),
                      label: const Text('Reject'),
                    ),
                  ]),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}
