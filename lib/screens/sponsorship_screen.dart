import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
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
  final InAppPurchase _store = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseUpdates;
  final Map<String, Map<String, dynamic>> _appleCatalog = {};
  final Map<String, ProductDetails> _appleProducts = {};
  int _durationMonths = 1;
  String? _busyKey;
  bool? _isUsStorefront;
  bool _applePurchasePending = false;
  String? _applePurchaseError;

  bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    if (_isIos) {
      _purchaseUpdates = _store.purchaseStream.listen(
        _handleApplePurchases,
        onError: (Object error) {
          if (mounted) {
            setState(() => _applePurchaseError =
                'Apple purchases are unavailable right now.');
          }
        },
      );
      _loadAppleSponsorshipProducts();
    }
  }

  @override
  void dispose() {
    _purchaseUpdates?.cancel();
    super.dispose();
  }

  Future<void> _loadAppleSponsorshipProducts() async {
    try {
      final country = await _store.countryCode();
      if (mounted) setState(() => _isUsStorefront = country == 'USA');
      if (country == 'USA') return;
      if (!await _store.isAvailable()) {
        throw StateError('The App Store is not available right now.');
      }
      final configured = await _service.getAppleSponsorshipProducts();
      final catalog = <String, Map<String, dynamic>>{
        for (final item in configured)
          if (item['productId'] is String) item['productId'] as String: item,
      };
      if (catalog.isEmpty) {
        if (mounted) {
          setState(() => _applePurchaseError =
              'Apple sponsorship prices are not configured yet.');
        }
        return;
      }
      final response = await _store.queryProductDetails(catalog.keys.toSet());
      if (!mounted) return;
      setState(() {
        _appleCatalog
          ..clear()
          ..addAll(catalog);
        _appleProducts
          ..clear()
          ..addEntries(response.productDetails.map((product) =>
              MapEntry(product.id, product)));
        _applePurchaseError = response.notFoundIDs.isNotEmpty
            ? 'Some Apple sponsorship products are not ready in App Store Connect.'
            : response.error?.message;
        final availableDurations = catalog.values
            .map((item) => (item['durationMonths'] as num?)?.toInt())
            .whereType<int>()
            .toSet();
        if (availableDurations.isNotEmpty &&
            !availableDurations.contains(_durationMonths)) {
          _durationMonths = availableDurations.first;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _applePurchaseError =
            error.toString().replaceFirst('Bad state: ', ''));
      }
    }
  }

  Future<void> _handleApplePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (!_appleCatalog.containsKey(purchase.productID)) continue;
      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _applePurchasePending = true);
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled ||
          purchase.status == PurchaseStatus.error) {
        await _service.cancelPendingAppleSponsorship(purchase.productID);
        if (purchase.pendingCompletePurchase) {
          await _store.completePurchase(purchase);
        }
        if (mounted) {
          setState(() => _applePurchasePending = false);
          if (purchase.status == PurchaseStatus.error) {
            _message(purchase.error?.message ??
                'The App Store could not complete this purchase.');
          }
        }
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) continue;
      try {
        await _service.verifyAppleSponsorship(
            purchase.verificationData.serverVerificationData);
        if (purchase.pendingCompletePurchase) {
          await _store.completePurchase(purchase);
        }
        if (mounted && purchase.status == PurchaseStatus.purchased) {
          _message('Sponsorship payment confirmed.');
        }
      } catch (error) {
        if (mounted) {
          _message(error.toString().replaceFirst('Exception: ', ''));
        }
      } finally {
        if (mounted) setState(() => _applePurchasePending = false);
      }
    }
  }

  MapEntry<String, ProductDetails>? _appleProductForTier(
      Map<String, dynamic> tier) {
    final ownerType = tier['ownerType'] ?? widget.ownerType;
    final tierPrice = (tier['price'] as num? ?? 0).toInt();
    final monthly = tier['billingPeriod'] == 'MONTHLY';
    final months = ownerType == 'STATION' ? _durationMonths : null;
    for (final entry in _appleCatalog.entries) {
      final config = entry.value;
      final allowedOwners = (config['ownerTypes'] as List<dynamic>? ?? [])
          .map((value) => value.toString()).toSet();
      final configuredPrice = (config['priceCents'] as num? ?? 0).toInt();
      final expectedPrice = monthly ? tierPrice * (months ?? 1) : tierPrice;
      final configuredMonths = (config['durationMonths'] as num?)?.toInt();
      if (!allowedOwners.contains(ownerType) ||
          configuredPrice != expectedPrice ||
          (ownerType == 'STATION' && configuredMonths != months) ||
          !_appleProducts.containsKey(entry.key)) {
        continue;
      }
      return MapEntry(entry.key, _appleProducts[entry.key]!);
    }
    return null;
  }

  List<DropdownMenuItem<int>> _appleDurationOptions() {
    final durations = _appleCatalog.values
        .map((item) => (item['durationMonths'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    if (durations.isEmpty) durations.addAll(List.generate(24, (i) => i + 1));
    return durations
        .map((months) => DropdownMenuItem(
              value: months,
              child: Text('$months month${months == 1 ? '' : 's'}'),
            ))
        .toList();
  }

  bool _hasAppleOptionForAnyTerm(Map<String, dynamic> tier) {
    final ownerType = tier['ownerType'] ?? widget.ownerType;
    final tierPrice = (tier['price'] as num? ?? 0).toInt();
    final monthly = tier['billingPeriod'] == 'MONTHLY';
    return _appleCatalog.entries.any((entry) {
      final config = entry.value;
      final owners = (config['ownerTypes'] as List<dynamic>? ?? [])
          .map((value) => value.toString());
      final configuredPrice = (config['priceCents'] as num? ?? 0).toInt();
      final duration = (config['durationMonths'] as num?)?.toInt();
      if (!owners.contains(ownerType) || !_appleProducts.containsKey(entry.key)) {
        return false;
      }
      if (ownerType == 'CONTEST') return configuredPrice == tierPrice;
      if (!monthly) return configuredPrice == tierPrice && duration != null;
      return duration != null &&
          configuredPrice == tierPrice * duration;
    });
  }

  Future<void> _buyAppleTier(String tierId, Map<String, dynamic> tier) async {
    final matched = _appleProductForTier(tier);
    if (matched == null) {
      throw Exception(_applePurchaseError ??
          'This tier and duration do not have an Apple price option.');
    }
    await _service.startAppleSponsorship(
      tierId: tierId,
      productId: matched.key,
      durationMonths: _durationMonths,
    );
    if (mounted) setState(() => _applePurchasePending = true);
    final started = await _store.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: matched.value),
    );
    if (!started) {
      await _service.cancelPendingAppleSponsorship(matched.key);
      if (mounted) setState(() => _applePurchasePending = false);
      throw Exception('The App Store purchase did not start. Try again.');
    }
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
    final darkTheme = Theme.of(context).copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B0B0F),
      colorScheme: const ColorScheme.dark(
        primary: AppTheme.primary,
        secondary: AppTheme.secondary,
        surface: Color(0xFF18181E),
        onSurface: Color(0xFFF5F5F7),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0B0B0F),
        foregroundColor: Color(0xFFF5F5F7),
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFFF5F5F7)),
        titleTextStyle: TextStyle(color: Color(0xFFF5F5F7), fontSize: 18, fontWeight: FontWeight.w700),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF222229),
        labelStyle: TextStyle(color: Color(0xFFD0D0D8)),
        hintStyle: TextStyle(color: Color(0xFFB7B7C1)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0xFF494952)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: const Color(0xFFF0DCE4)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFF5F5F7),
          side: const BorderSide(color: Color(0xFF666670)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF19191F),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(color: Color(0xFFF5F5F7), fontSize: 20, fontWeight: FontWeight.w700),
        contentTextStyle: TextStyle(color: Color(0xFFD2D2D8)),
      ),
    );

    return Theme(
      data: darkTheme,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0B0F),
        appBar: AppBar(
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
              style: const TextStyle(color: Color(0xFFD0D0D8), height: 1.45),
        ),
        if (!widget.isOwner && _isIos && _isUsStorefront == false) ...[
          const SizedBox(height: 8),
          const Text(
            'Apple purchases are charged once for the selected term and do not renew automatically.',
            style: TextStyle(color: Color(0xFFB9B9C3), height: 1.4),
          ),
        ],
        if (!widget.isOwner && widget.ownerType == 'STATION') ...[
          const SizedBox(height: 14),
          Row(children: [
            const Text('Sponsor duration', style: TextStyle(color: Color(0xFFD0D0D8))),
            const Spacer(),
            DropdownButton<int>(
              value: _durationMonths,
              dropdownColor: const Color(0xFF222226),
              style: const TextStyle(color: Colors.white),
              iconEnabledColor: Colors.white,
              items: _isIos && _isUsStorefront == false
                  ? _appleDurationOptions()
                  : List.generate(24, (i) => DropdownMenuItem(
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
              accountId == null
                  ? 'Link Stripe to receive web, Android, and U.S. iOS sponsorship payments.'
                  : 'Stripe payout account linked. Stripe may still be verifying it.',
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
        final docs = snapshot.data?.docs.where((doc) {
          if (doc.data()['active'] != true) return false;
          if (_isIos && _isUsStorefront == false) {
            return _hasAppleOptionForAnyTerm(doc.data());
          }
          return true;
        }).toList() ?? [];
        docs.sort((a, b) => (a.data()['price'] as num? ?? 0).compareTo(b.data()['price'] as num? ?? 0));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SectionHeading('AVAILABLE TIERS'),
          if (_isIos && _isUsStorefront == false && _applePurchaseError != null)
            _EmptyMessage(_applePurchaseError!),
          if (snapshot.hasError) const _EmptyMessage('Could not load sponsor tiers.'),
          if (docs.isEmpty && !snapshot.hasError)
            _EmptyMessage(_isIos && _isUsStorefront == false
                ? 'No sponsor tiers have a matching Apple price option yet.'
                : 'No sponsor tiers are available yet.'),
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
    final appleMatch = _isIos && _isUsStorefront == false
        ? _appleProductForTier(tier)
        : null;
    final priceLabel = _isIos && _isUsStorefront == false
        ? appleMatch?.value.price ?? 'Apple price unavailable'
        : '\$${(price / 100).toStringAsFixed(2)}${monthly ? ' / month' : ''}';
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
          Text(priceLabel,
              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        Text('${tier['bannerSize'] ?? 'MEDIUM'} artwork · $filled / $available slots filled${active ? '' : ' · paused'}',
            style: const TextStyle(color: Color(0xFFC7C7CF), fontSize: 13)),
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
              onPressed: soldOut || _busyKey != null || _applePurchasePending ||
                      (_isIos && _isUsStorefront == null) ||
                      (_isIos && _isUsStorefront == false && appleMatch == null)
                  ? null
                  : () => _run('buy_$tierId', () async {
                      if (_isIos && _isUsStorefront == false) {
                        await _buyAppleTier(tierId, tier);
                      } else {
                        final url = await _service.startCheckout(
                            tierId, _durationMonths);
                        await _openUrl(url);
                      }
                    }),
              child: Text(_busyKey == 'buy_$tierId'
                  ? 'Opening checkout…'
                  : soldOut
                      ? 'Sold out'
                      : _isIos && _isUsStorefront == false
                          ? 'Purchase with Apple'
                          : 'Become a sponsor'),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          tierId == null ? 'Create sponsor tier' : 'Edit sponsor tier',
          style: const TextStyle(color: Color(0xFFF5F5F7), fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _input(name, 'Tier name'),
          _input(price, 'Price in USD', keyboard: TextInputType.number),
          _input(quantity, 'Available slots', keyboard: TextInputType.number),
          DropdownButtonFormField<String>(
            value: bannerSize,
            dropdownColor: const Color(0xFF222226),
            style: const TextStyle(color: Colors.white),
            iconEnabledColor: Colors.white,
            decoration: const InputDecoration(
              labelText: 'Artwork size',
              labelStyle: TextStyle(color: Color(0xFFE0E0E6)),
              floatingLabelStyle: TextStyle(color: Color(0xFFFF7892)),
              prefixIcon: Icon(LucideIcons.image, size: 18, color: Color(0xFFD0D0D8)),
            ),
            items: const [
              DropdownMenuItem(value: 'LARGE', child: Text('Large · 1200 × 400 px')),
              DropdownMenuItem(value: 'MEDIUM', child: Text('Medium · 800 × 300 px')),
              DropdownMenuItem(value: 'SMALL', child: Text('Small · 400 × 150 px')),
            ],
            onChanged: (value) => setDialogState(() => bannerSize = value ?? 'MEDIUM'),
          ),
          if (widget.ownerType == 'STATION')
            DropdownButtonFormField<String>(
              value: billingPeriod,
              dropdownColor: const Color(0xFF222226),
              style: const TextStyle(color: Colors.white),
              iconEnabledColor: Colors.white,
              decoration: const InputDecoration(
                labelText: 'Billing',
                labelStyle: TextStyle(color: Color(0xFFE0E0E6)),
                floatingLabelStyle: TextStyle(color: Color(0xFFFF7892)),
                prefixIcon: Icon(LucideIcons.repeat, size: 18, color: Color(0xFFD0D0D8)),
              ),
              items: const [
                DropdownMenuItem(value: 'ONE_TIME', child: Text('One-time for selected duration')),
                DropdownMenuItem(value: 'MONTHLY', child: Text('Monthly recurring')),
              ],
              onChanged: (value) => setDialogState(() => billingPeriod = value ?? 'ONE_TIME'),
            ),
        ])),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE0E0E6)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
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
        cursorColor: AppTheme.primary,
        style: const TextStyle(color: Color(0xFFF5F5F7)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFFE0E0E6)),
          floatingLabelStyle: const TextStyle(color: Color(0xFFFF7892)),
          hintStyle: const TextStyle(color: Color(0xFFC0C0C8)),
        ),
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
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF17171D),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(status == 'ACTIVE' ? LucideIcons.checkCircle : LucideIcons.clock3,
                      color: status == 'ACTIVE' ? const Color(0xFF63D7A6) : const Color(0xFFFFC36B)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${data['sponsorName'] ?? 'Sponsor'}',
                      style: const TextStyle(color: Color(0xFFF5F5F7), fontWeight: FontWeight.w700, fontSize: 15))),
                  _StatusPill(status: status),
                ]),
                const SizedBox(height: 12),
                Text('Artwork · ${_humanStatus(artworkStatus)}',
                    style: const TextStyle(color: Color(0xFFC7C7CF), fontSize: 13)),
                if (status == 'ACTIVE' && artworkStatus != 'APPROVED') ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busyKey == 'art_${doc.id}' ? null : () => _run('art_${doc.id}', () async {
                        final media = await ImagePicker().pickMedia();
                        if (media != null) await _service.uploadArtwork(doc.id, media);
                      }),
                      icon: _busyKey == 'art_${doc.id}'
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(LucideIcons.image, size: 16),
                      label: Text(_busyKey == 'art_${doc.id}' ? 'Uploading…' : 'Upload artwork'),
                    ),
                  ),
                ],
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
        child: Text(text, style: const TextStyle(color: Color(0xFFD0D0D8), fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12)),
      );
}

class _EmptyMessage extends StatelessWidget {
  final String text;
  const _EmptyMessage(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(text, style: const TextStyle(color: Color(0xFFC4C4CD))),
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

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final active = status == 'ACTIVE';
    final color = active ? const Color(0xFF63D7A6) : const Color(0xFFFFC36B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _humanStatus(status),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

String _humanStatus(String status) {
  return status
      .toLowerCase()
      .split('_')
      .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
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
