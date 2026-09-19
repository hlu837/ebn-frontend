import 'package:flutter/material.dart';

import '../models/auth_response.dart';
import '../models/maintenance_request.dart';
import '../services/maintenance_request_service.dart';
import '../theme/app_theme.dart';

const List<String> _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime d) {
  final local = d.toLocal();
  return '${_kMonths[local.month - 1]} ${local.day}, ${local.year}';
}

Color _statusColor(MaintenanceRequestStatus status) {
  switch (status) {
    case MaintenanceRequestStatus.submitted:
      return Colors.orange;
    case MaintenanceRequestStatus.accepted:
      return AppColors.success;
    case MaintenanceRequestStatus.rejected:
      return AppColors.danger;
    case MaintenanceRequestStatus.assigned:
      return AppColors.primaryYellow;
    case MaintenanceRequestStatus.completed:
      return AppColors.success;
  }
}

IconData _categoryIcon(MaintenanceCategory category) {
  switch (category) {
    case MaintenanceCategory.electrical:
      return Icons.electrical_services_outlined;
    case MaintenanceCategory.plumbing:
      return Icons.plumbing_outlined;
    case MaintenanceCategory.structural:
      return Icons.foundation_outlined;
    case MaintenanceCategory.appliance:
      return Icons.kitchen_outlined;
    case MaintenanceCategory.other:
      return Icons.build_outlined;
  }
}

/// The Property Owner's incoming maintenance-request queue — every issue
/// tenants have reported across their properties. Mirrors
/// [MyMaintenanceRequestsScreen] (the tenant's own list) for styling and
/// `AdminRoleUpgradeRequestsScreen` for the Accept/Reject-with-note flow.
///
/// Accept means the owner is taking responsibility (handling it directly
/// or assigning an external specialist themselves — Phase 1 of the
/// workflow doesn't track who yet, see `maintenanceRequests.js`). Reject
/// hands resolution back to the tenant, who can assign a specialist from
/// the service directory once that exists (Phase 3/4, not built yet).
class PropertyOwnerMaintenanceRequestsScreen extends StatefulWidget {
  const PropertyOwnerMaintenanceRequestsScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<PropertyOwnerMaintenanceRequestsScreen> createState() => _PropertyOwnerMaintenanceRequestsScreenState();
}

enum _Filter { pending, accepted, rejected, all }

extension on _Filter {
  String get label {
    switch (this) {
      case _Filter.pending:
        return 'Pending';
      case _Filter.accepted:
        return 'Accepted';
      case _Filter.rejected:
        return 'Rejected';
      case _Filter.all:
        return 'All';
    }
  }

  String? get wireStatus {
    switch (this) {
      case _Filter.pending:
        return 'submitted';
      case _Filter.accepted:
        return 'accepted';
      case _Filter.rejected:
        return 'rejected';
      case _Filter.all:
        return null;
    }
  }
}

class _PropertyOwnerMaintenanceRequestsScreenState extends State<PropertyOwnerMaintenanceRequestsScreen> {
  final _service = MaintenanceRequestService();

  _Filter _filter = _Filter.pending;
  bool _loading = true;
  String? _error;
  List<MaintenanceRequest> _rows = const [];
  final Set<String> _busyIds = {};

  String get _token => widget.user.token ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.fetchQueue(token: _token, status: _filter.wireStatus);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on MaintenanceRequestException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _onFilterChanged(_Filter next) {
    if (next == _filter) return;
    setState(() => _filter = next);
    _load();
  }

  Future<String?> _promptNote(String title, String hint, {required bool isReject}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.cloud,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.sm), borderSide: const BorderSide(color: AppColors.border)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isReject ? AppColors.danger : AppColors.success,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(isReject ? 'Reject' : 'Accept'),
          ),
        ],
      ),
    );
  }

  Future<void> _decide(MaintenanceRequest request, {required bool accept}) async {
    final note = await _promptNote(
      accept ? 'Accept this request?' : 'Reject this request?',
      accept
          ? 'Optional note for the tenant (e.g. when you\'ll follow up)'
          : 'Why is this being declined? (visible to the tenant)',
      isReject: !accept,
    );
    if (note == null) return;
    setState(() => _busyIds.add(request.id));
    try {
      await _service.decide(token: _token, id: request.id, accept: accept, note: note.isEmpty ? null : note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accept ? 'Marked as accepted.' : 'Request declined.')),
      );
      setState(() => _rows = _rows.where((r) => r.id != request.id).toList());
    } on MaintenanceRequestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyIds.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text('Maintenance Requests', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _Filter.values.map((f) {
                    final selected = f == _filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f.label),
                        selected: selected,
                        onSelected: (_) => _onFilterChanged(f),
                        selectedColor: AppColors.primaryYellow,
                        labelStyle: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: selected ? AppColors.ink : AppColors.slate,
                        ),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                          side: BorderSide(color: selected ? AppColors.primaryYellow : AppColors.border),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : _rows.isEmpty
                          ? _EmptyState(filter: _filter)
                          : RefreshIndicator(
                              color: AppColors.primaryYellow,
                              onRefresh: _load,
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                itemCount: _rows.length,
                                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                                itemBuilder: (context, i) {
                                  final r = _rows[i];
                                  return _RequestCard(
                                    request: r,
                                    busy: _busyIds.contains(r.id),
                                    onAccept: () => _decide(r, accept: true),
                                    onReject: () => _decide(r, accept: false),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.busy, required this.onAccept, required this.onReject});

  final MaintenanceRequest request;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(request.status);
    final isPending = request.status == MaintenanceRequestStatus.submitted;
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
            children: [
              Icon(_categoryIcon(request.category), size: 18, color: AppColors.ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  request.category.label,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                child: Text(
                  isPending ? 'Needs your review' : request.status.name.toUpperCase(),
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          if (request.asset != null) ...[
            const SizedBox(height: 4),
            Text(request.asset!.title, style: const TextStyle(fontSize: 12.5, color: AppColors.slate, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 8),
          Text(request.description, style: const TextStyle(fontSize: 13, color: AppColors.ink, height: 1.4)),
          if (request.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: request.photoUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(request.photoUrls[i], width: 64, height: 64, fit: BoxFit.cover),
                ),
              ),
            ),
          ],
          if (!isPending && request.decisionNote != null && request.decisionNote!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(8)),
              child: Text(
                request.decisionNote!,
                style: const TextStyle(fontSize: 12, color: AppColors.slate, fontStyle: FontStyle.italic),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text('Filed ${_formatDate(request.createdAt)}', style: const TextStyle(fontSize: 11, color: AppColors.slate)),
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onReject,
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: busy ? null : onAccept,
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                    child: busy
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                        : const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});

  final _Filter filter;

  @override
  Widget build(BuildContext context) {
    final message = switch (filter) {
      _Filter.pending => "You're all caught up — no requests waiting on your review.",
      _Filter.accepted => "No accepted requests yet.",
      _Filter.rejected => "No rejected requests yet.",
      _Filter.all => "No maintenance requests have come in yet.",
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.build_outlined, size: 40, color: AppColors.slate),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.slate)),
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
