import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../models/auth_response.dart';
import '../services/asset_service.dart';
import '../theme/app_theme.dart';
import '../utils/media_encoding.dart';
import 'asset_detail_screen.dart';

/// Every live/off-market listing this Property Owner has — backed by
/// [AssetService.fetchByBroker], same source `PropertyOwnerDashboardScreen`
/// already uses. Opened from the Account tab's "My Listings" row.
class PropertyOwnerListingsScreen extends StatefulWidget {
  const PropertyOwnerListingsScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<PropertyOwnerListingsScreen> createState() => _PropertyOwnerListingsScreenState();
}

class _PropertyOwnerListingsScreenState extends State<PropertyOwnerListingsScreen> {
  final _assetService = AssetService();

  bool _loading = true;
  String? _loadError;
  List<Asset> _listings = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rows = await _assetService.fetchByBroker(widget.user.id);
      if (!mounted) return;
      setState(() {
        _listings = rows;
        _loading = false;
      });
    } on AssetException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        title: Text('My Listings${_listings.isEmpty ? '' : ' (${_listings.length})'}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
          : _loadError != null
              ? _ErrorState(message: _loadError!, onRetry: _load)
              : _listings.isEmpty
                  ? const _EmptyState()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: _listings.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) => _ListingCard(asset: _listings[i], user: widget.user),
                      ),
                    ),
    );
  }
}

Color _statusColor(AssetStatus status) {
  switch (status) {
    case AssetStatus.active:
      return AppColors.success;
    case AssetStatus.reserved:
    case AssetStatus.underInspection:
      return AppColors.primaryYellowDark;
    case AssetStatus.rented:
    case AssetStatus.sold:
    case AssetStatus.draft:
    case AssetStatus.archived:
      return AppColors.slate;
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.asset, required this.user});

  final Asset asset;
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(asset.status);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AssetDetailScreen(asset: asset, user: user),
      )),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: dataUrlOrNetworkImage(asset.imageUrl) != null
                  ? Image(image: dataUrlOrNetworkImage(asset.imageUrl)!, width: 64, height: 64, fit: BoxFit.cover)
                  : Container(
                      width: 64,
                      height: 64,
                      color: AppColors.border,
                      child: const Icon(Icons.home_outlined, color: AppColors.slate),
                    ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(asset.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text('${asset.priceCurrency} ${_formatMoney(asset.priceAmount)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primaryYellow)),
                  if (asset.city != null) ...[
                    const SizedBox(height: 3),
                    Text(asset.city!,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.slate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(999)),
              child: Text(asset.status.label,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.house_outlined, size: 40, color: AppColors.slate),
            SizedBox(height: AppSpacing.md),
            Text('No listings yet — tap the + button on Dashboard to post your first property.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: AppColors.slate)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.slate),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: AppColors.slate)),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

String _formatMoney(double amount) {
  final s = amount.toStringAsFixed(0);
  final buffer = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
    buffer.write(s[i]);
  }
  return buffer.toString();
}
