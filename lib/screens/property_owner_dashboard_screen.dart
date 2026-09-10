import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/asset.dart';
import '../models/auth_response.dart';
import '../models/sell_request.dart';
import '../providers/sell_request_controller.dart';
import '../services/asset_service.dart';
import '../theme/app_theme.dart';
import '../utils/media_encoding.dart';
import 'asset_detail_screen.dart';

/// The Property Owner's real Dashboard tab — backed by the same data the
/// Agent side already persists to, since a Property Owner listing is
/// submitted through the exact same `submitAsAgent` pipeline (see
/// `_openListingIntent` in `property_owner_home_screen.dart`).
///
/// Two real sources, no mock data:
/// - [SellRequestController.fetchByOwner]/[SellRequestController.byOwner] —
///   every submission this owner has made and where it stands
///   (pending admin review / rejected / listed).
/// - [AssetService.fetchByBroker] — the live listings that resulted, with
///   their real visibility status (active vs. archived/draft/etc), since
///   Admin approval sets `assets.broker_id` to the submitting owner's id
///   the same way it does for Agent self-listings.
///
/// Deliberately NOT shown here yet because there's no backend for them:
/// an inbox of buyer/tenant requests and a wallet/earnings summary —
/// those need their own tables (rental agreements, a property-owner
/// wallet) that don't exist yet. Once Inbox/Review are built, this
/// screen is the natural place to surface their counts too.
class PropertyOwnerDashboardScreen extends StatefulWidget {
  const PropertyOwnerDashboardScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<PropertyOwnerDashboardScreen> createState() => _PropertyOwnerDashboardScreenState();
}

class _PropertyOwnerDashboardScreenState extends State<PropertyOwnerDashboardScreen> {
  final AssetService _assetService = AssetService();

  List<Asset> _listings = const [];
  bool _listingsLoading = true;
  String? _listingsError;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadListings(), _loadRequests()]);
  }

  Future<void> _loadRequests() {
    return context.read<SellRequestController>().fetchByOwner(widget.user.id);
  }

  Future<void> _loadListings() async {
    setState(() {
      _listingsLoading = true;
      _listingsError = null;
    });
    try {
      final rows = await _assetService.fetchByBroker(widget.user.id);
      if (!mounted) return;
      setState(() {
        _listings = rows;
        _listingsLoading = false;
      });
    } on AssetException catch (e) {
      if (!mounted) return;
      setState(() {
        _listingsLoading = false;
        _listingsError = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = context.watch<SellRequestController>().byOwner(widget.user.id);
    final isLoading = _listingsLoading || context.watch<SellRequestController>().isLoading;

    final pendingCount =
        requests.where((r) => r.status == SellRequestStatus.pendingAdminApproval).length;
    final rejectedCount =
        requests.where((r) => r.status == SellRequestStatus.submissionRejected).length;
    final liveCount = _listings.where((a) => a.status == AssetStatus.active).length;
    final offMarketCount = _listings.where((a) => a.status != AssetStatus.active).length;

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
          children: [
            const Text('Dashboard',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 4),
            const Text('A quick look at your listings.',
                style: TextStyle(fontSize: 13, color: AppColors.slate)),
            const SizedBox(height: AppSpacing.lg),
            if (isLoading && requests.isEmpty && _listings.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: Center(child: CircularProgressIndicator(color: AppColors.primaryYellow)),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                        label: 'Live', value: liveCount, color: AppColors.success),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _StatCard(
                        label: 'Under review', value: pendingCount, color: _amber),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _StatCard(
                        label: 'Needs attention', value: rejectedCount, color: AppColors.danger),
                  ),
                ],
              ),
              if (offMarketCount > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('$offMarketCount listing${offMarketCount == 1 ? '' : 's'} currently off-market',
                    style: const TextStyle(fontSize: 12, color: AppColors.slate)),
              ],
              const SizedBox(height: AppSpacing.xl),
              const Text('Your listings',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: AppSpacing.sm),
              if (_listingsError != null)
                _ErrorStrip(message: _listingsError!, onRetry: _loadListings)
              else if (requests.isEmpty)
                const _EmptyStrip(
                    text: "No listings yet — tap the + button below to post your first property.")
              else
                for (final request in requests) ...[
                  _RequestCard(
                    request: request,
                    asset: request.listedAssetId == null
                        ? null
                        : _listings.where((a) => a.id == request.listedAssetId).firstOrNull,
                    user: widget.user,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
            ],
          ],
        ),
      ),
    );
  }
}

const Color _amber = Color(0xFFB45309);
const Color _amberBg = Color(0xFFFEF3C7);

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text('$value',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.slate)),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.asset, required this.user});

  final SellRequest request;
  final Asset? asset;
  final AppUser user;

  Color get _statusColor {
    switch (request.status) {
      case SellRequestStatus.listed:
        return asset != null && asset!.status != AssetStatus.active
            ? AppColors.slate
            : AppColors.success;
      case SellRequestStatus.submissionRejected:
      case SellRequestStatus.reportRejected:
        return AppColors.danger;
      default:
        return _amber;
    }
  }

  Color get _statusBg {
    switch (request.status) {
      case SellRequestStatus.listed:
        return asset != null && asset!.status != AssetStatus.active
            ? const Color(0xFFEDEBE0)
            : const Color(0xFFE3F5EA);
      case SellRequestStatus.submissionRejected:
      case SellRequestStatus.reportRejected:
        return const Color(0xFFFBEAE4);
      default:
        return _amberBg;
    }
  }

  String get _statusLabel {
    if (request.status == SellRequestStatus.listed) {
      return asset != null && asset!.status != AssetStatus.active
          ? 'Off-market (${asset!.status.label})'
          : 'Live';
    }
    return request.status.label;
  }

  @override
  Widget build(BuildContext context) {
    final content = Container(
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
            child: dataUrlOrNetworkImage(asset?.imageUrl) != null
                ? Image(
                    image: dataUrlOrNetworkImage(asset?.imageUrl)!,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover)
                : Container(
                    width: 60,
                    height: 60,
                    color: AppColors.border,
                    child: const Icon(Icons.home_outlined, color: AppColors.slate),
                  ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text('ETB ${_formatMoney(request.askingPrice)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primaryYellow)),
                const SizedBox(height: 3),
                Text(request.city,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.slate),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: _statusBg, borderRadius: BorderRadius.circular(999)),
            child: Text(_statusLabel,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _statusColor)),
          ),
        ],
      ),
    );

    if (asset == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AssetDetailScreen(asset: asset!, user: user),
      )),
      child: content,
    );
  }
}

class _EmptyStrip extends StatelessWidget {
  const _EmptyStrip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: AppColors.slate)),
    );
  }
}

class _ErrorStrip extends StatelessWidget {
  const _ErrorStrip({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: AppColors.slate)),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
