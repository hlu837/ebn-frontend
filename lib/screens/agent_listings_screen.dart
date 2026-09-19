import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../models/auth_response.dart';
import '../services/asset_service.dart';
import '../theme/app_theme.dart';
import '../utils/media_encoding.dart';
import 'agent_listing_edit_screen.dart';
import 'asset_detail_screen.dart';

/// Every property a Broker/Agent has posted — any status — with a status
/// filter strip so "Active" (what a customer can currently see live) is
/// easy to isolate from drafts, sold, or archived listings.
///
/// Defaults to the signed-in [user]'s own listings (editable). Pass
/// [viewedBrokerId]/[viewedBrokerName] to instead show a *different*
/// broker's listings read-only — e.g. from the Broker Network screen's
/// "selected broker" sheet, which previously had a listings *count* but no
/// way to actually open that broker's list.
class AgentListingsScreen extends StatefulWidget {
  const AgentListingsScreen({
    super.key,
    required this.user,
    this.viewedBrokerId,
    this.viewedBrokerName,
  });

  final AppUser user;

  /// When set, shows this broker's listings instead of [user]'s own, and
  /// hides the Edit action (you're only allowed to edit your own).
  final String? viewedBrokerId;

  /// Display name for the title when [viewedBrokerId] is set.
  final String? viewedBrokerName;

  @override
  State<AgentListingsScreen> createState() => _AgentListingsScreenState();
}

/// `null` means "All statuses".
typedef _StatusFilter = AssetStatus?;

class _AgentListingsScreenState extends State<AgentListingsScreen> {
  final _assetService = AssetService();

  bool get _isOwnListings => widget.viewedBrokerId == null;
  String get _targetBrokerId => widget.viewedBrokerId ?? widget.user.id;

  bool _loading = true;
  String? _loadError;
  List<Asset> _listings = const [];
  _StatusFilter _filter = AssetStatus.active;

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
      final rows = await _assetService.fetchByBroker(_targetBrokerId);
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

  /// Every status actually present, in enum order, plus a leading "All" —
  /// so the strip never offers an empty filter for a status this broker
  /// has zero listings in.
  List<_StatusFilter> get _availableFilters {
    final present = AssetStatus.values
        .where((s) => _listings.any((a) => a.status == s))
        .toList();
    return [null, ...present];
  }

  @override
  Widget build(BuildContext context) {
    final filter = _filter;
    final visible = filter == null
        ? _listings
        : _listings.where((a) => a.status == filter).toList();
    final activeCount =
        _listings.where((a) => a.status == AssetStatus.active).length;

    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        title: Text(
            _isOwnListings
                ? 'My Listings${_listings.isEmpty ? '' : ' (${_listings.length})'}'
                : "${widget.viewedBrokerName ?? 'Broker'}'s Listings${_listings.isEmpty ? '' : ' (${_listings.length})'}",
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(color: AppColors.primaryYellow))
          : _loadError != null
              ? _ErrorState(message: _loadError!, onRetry: _load)
              : _listings.isEmpty
                  ? _EmptyState(isOwnListings: _isOwnListings)
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                              AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
                          child: SizedBox(
                            height: 34,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _availableFilters.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, i) {
                                final status = _availableFilters[i];
                                final label = status == null
                                    ? 'All'
                                    : status.label;
                                final count = status == null
                                    ? _listings.length
                                    : _listings
                                        .where((a) => a.status == status)
                                        .length;
                                return _StatusChip(
                                  label: '$label ($count)',
                                  // The chip actually drives `_filter` now
                                  // (this is the "Active" button that
                                  // previously had nothing to filter, since
                                  // the screen it lived on didn't exist).
                                  isSelected: _filter == status,
                                  onTap: () =>
                                      setState(() => _filter = status),
                                );
                              },
                            ),
                          ),
                        ),
                        Expanded(
                          child: visible.isEmpty
                              ? _EmptyFilterState(
                                  label: filter?.label ?? 'All',
                                  onClear: filter == null
                                      ? null
                                      : () =>
                                          setState(() => _filter = null),
                                )
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                        AppSpacing.lg,
                                        0,
                                        AppSpacing.lg,
                                        AppSpacing.lg),
                                    itemCount: visible.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: AppSpacing.sm),
                                    itemBuilder: (context, i) => _ListingCard(
                                      asset: visible[i],
                                      user: widget.user,
                                      onChanged: _load,
                                      readOnly: !_isOwnListings,
                                    ),
                                  ),
                                ),
                        ),
                      ],
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

class _StatusChip extends StatelessWidget {
  const _StatusChip(
      {required this.label, required this.isSelected, required this.onTap});
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryYellow : AppColors.card,
            border: Border.all(
                color:
                    isSelected ? AppColors.primaryYellow : AppColors.border),
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : AppColors.slate)),
        ),
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard(
      {required this.asset,
      required this.user,
      required this.onChanged,
      this.readOnly = false});

  final Asset asset;
  final AppUser user;
  final VoidCallback onChanged;

  /// True when browsing another broker's listings (via
  /// [AgentListingsScreen.viewedBrokerId]) — hides the Edit action since
  /// you can only edit your own.
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(asset.status);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AssetDetailScreen(asset: asset, user: user),
        ));
        onChanged();
      },
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
                  ? Image(
                      image: dataUrlOrNetworkImage(asset.imageUrl)!,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover)
                  : Container(
                      width: 64,
                      height: 64,
                      color: AppColors.border,
                      child: const Icon(Icons.home_outlined,
                          color: AppColors.slate),
                    ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(asset.title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text('${asset.priceCurrency} ${_formatMoney(asset.priceAmount)}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryYellow)),
                  if (asset.city != null) ...[
                    const SizedBox(height: 3),
                    Text(asset.city!,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.slate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999)),
                  child: Text(asset.status.label,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: color)),
                ),
                const SizedBox(height: 6),
                if (!readOnly)
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            AgentListingEditScreen(asset: asset, user: user),
                      ));
                      onChanged();
                    },
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                      child: Text('Edit',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryYellow)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isOwnListings});
  final bool isOwnListings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.house_outlined, size: 40, color: AppColors.slate),
            const SizedBox(height: AppSpacing.md),
            Text(
                isOwnListings
                    ? 'No listings yet — tap the + button on Dashboard to post your first property.'
                    : 'This broker has no listings yet.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: AppColors.slate)),
          ],
        ),
      ),
    );
  }
}

class _EmptyFilterState extends StatelessWidget {
  const _EmptyFilterState({required this.label, this.onClear});
  final String label;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.filter_alt_off_outlined,
                size: 40, color: AppColors.slate),
            const SizedBox(height: AppSpacing.md),
            Text('No "$label" listings right now.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: AppColors.slate)),
            if (onClear != null) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: onClear, child: const Text('Show all')),
            ],
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
            const Icon(Icons.error_outline_rounded,
                size: 40, color: AppColors.slate),
            const SizedBox(height: AppSpacing.md),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: AppColors.slate)),
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
