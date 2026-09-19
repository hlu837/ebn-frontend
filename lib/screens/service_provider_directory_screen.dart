import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/auth_response.dart';
import '../models/service_provider.dart';
import '../services/service_provider_service.dart';
import '../theme/app_theme.dart';
import 'assign_specialist_screen.dart';

IconData _categoryIcon(ServiceProviderCategory category) {
  switch (category) {
    case ServiceProviderCategory.electrician:
      return Icons.electrical_services_outlined;
    case ServiceProviderCategory.plumber:
      return Icons.plumbing_outlined;
    case ServiceProviderCategory.carpenter:
      return Icons.carpenter_outlined;
    case ServiceProviderCategory.mechanic:
      return Icons.build_circle_outlined;
    case ServiceProviderCategory.applianceTechnician:
      return Icons.kitchen_outlined;
    case ServiceProviderCategory.other:
      return Icons.handyman_outlined;
  }
}

/// Tenant-facing directory of local service professionals — Phase 3 of
/// the maintenance-request workflow. Reached either from a rejected
/// maintenance request (pre-filtered to a matching category) or
/// independently from the account menu, per the original spec: "If a
/// request is rejected by the owner (or for independent tenant needs),
/// the tenant selects a nearby specialist from the directory."
///
/// Every card always offers "Call" to contact a specialist directly. When
/// [maintenanceRequestId] is set (arriving from a rejected maintenance
/// request), cards also offer "Assign this job" — Phase 4/5: picking a
/// specialist here hands off to AssignSpecialistScreen to confirm a
/// quoted cost and pay it into escrow. Browsing independently (no
/// maintenanceRequestId) is still call-only, same as before.
class ServiceProviderDirectoryScreen extends StatefulWidget {
  const ServiceProviderDirectoryScreen({super.key, required this.user, this.initialCategory, this.maintenanceRequestId});

  final AppUser user;

  /// Pre-selects a filter chip — used when arriving from a rejected
  /// maintenance request, so the directory opens already narrowed to a
  /// relevant trade (e.g. a rejected "plumbing" request opens on Plumber).
  final ServiceProviderCategory? initialCategory;

  /// Set when arriving from a rejected maintenance request — unlocks the
  /// "Assign this job" action on each card. Null for independent browsing.
  final String? maintenanceRequestId;

  @override
  State<ServiceProviderDirectoryScreen> createState() => _ServiceProviderDirectoryScreenState();
}

class _ServiceProviderDirectoryScreenState extends State<ServiceProviderDirectoryScreen> {
  final _service = ServiceProviderService();
  final _cityController = TextEditingController();

  ServiceProviderCategory? _category;
  bool _loading = true;
  String? _error;
  List<ServiceProvider> _rows = const [];

  String get _token => widget.user.token ?? '';

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _load();
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.fetchDirectory(
        token: _token,
        category: _category,
        city: _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on ServiceProviderServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _onCategoryChanged(ServiceProviderCategory? next) {
    setState(() => _category = next);
    _load();
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open the dialer.")));
    }
  }

  Future<void> _assign(ServiceProvider provider) async {
    final requestId = widget.maintenanceRequestId;
    if (requestId == null) return;
    final assigned = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => AssignSpecialistScreen(user: widget.user, maintenanceRequestId: requestId, provider: provider),
    ));
    // Once assigned, this request no longer accepts a second assignment —
    // hand control back to whoever opened the directory (e.g.
    // my_maintenance_requests_screen) so it can refresh.
    if (assigned == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text('Service Directory', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cityController,
                      onSubmitted: (_) => _load(),
                      decoration: InputDecoration(
                        hintText: 'Filter by city',
                        prefixIcon: const Icon(Icons.location_on_outlined, size: 18),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.sm), borderSide: const BorderSide(color: AppColors.border)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _load,
                    style: IconButton.styleFrom(backgroundColor: AppColors.primaryYellow),
                    icon: const Icon(Icons.search_rounded, color: AppColors.ink),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                children: [
                  _CategoryChip(label: 'All', selected: _category == null, onTap: () => _onCategoryChanged(null)),
                  const SizedBox(width: 8),
                  ...ServiceProviderCategory.values.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _CategoryChip(label: c.label, selected: _category == c, onTap: () => _onCategoryChanged(c)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : _rows.isEmpty
                          ? const _EmptyState()
                          : RefreshIndicator(
                              color: AppColors.primaryYellow,
                              onRefresh: _load,
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                itemCount: _rows.length,
                                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                                itemBuilder: (context, i) => _ProviderCard(
                                  provider: _rows[i],
                                  onCall: () => _call(_rows[i].phone),
                                  onAssign: widget.maintenanceRequestId == null ? null : () => _assign(_rows[i]),
                                ),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primaryYellow,
      labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? AppColors.ink : AppColors.slate),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: selected ? AppColors.primaryYellow : AppColors.border),
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.provider, required this.onCall, this.onAssign});

  final ServiceProvider provider;
  final VoidCallback onCall;

  /// Null when browsing independently (call-only). Set when arriving from
  /// a rejected maintenance request — adds the "Assign this job" action.
  final VoidCallback? onAssign;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.primaryYellow.withValues(alpha: 0.12), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(_categoryIcon(provider.category), size: 20, color: AppColors.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(provider.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(
                      '${provider.category.label} · ${provider.city}',
                      style: const TextStyle(fontSize: 12, color: AppColors.slate, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (provider.rating != null) ...[
                          const Icon(Icons.star_rounded, size: 15, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(provider.rating!.toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink)),
                          const SizedBox(width: 10),
                        ],
                        if (provider.rateCents > 0)
                          Text('~${provider.rateBirr.toStringAsFixed(0)} Birr / call-out', style: const TextStyle(fontSize: 11.5, color: AppColors.slate)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: onCall,
                style: IconButton.styleFrom(backgroundColor: AppColors.success),
                icon: const Icon(Icons.call_rounded, size: 18, color: Colors.white),
              ),
            ],
          ),
          if (onAssign != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAssign,
                style: FilledButton.styleFrom(backgroundColor: AppColors.primaryYellow, foregroundColor: AppColors.ink),
                icon: const Icon(Icons.handyman_outlined, size: 16),
                label: const Text('Assign this job', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              ),
            ),
          ],
        ],
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
            Icon(Icons.handyman_outlined, size: 40, color: AppColors.slate),
            SizedBox(height: 12),
            Text('No specialists match that filter.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.slate)),
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
            const Icon(Icons.error_outline, size: 40, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.slate)),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
