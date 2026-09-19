import 'dart:async';

import 'package:flutter/material.dart';

import '../models/auth_response.dart';
import '../models/maintenance_assignment.dart';
import '../models/maintenance_request.dart';
import '../models/service_provider.dart';
import '../services/maintenance_assignment_service.dart';
import '../services/maintenance_request_service.dart';
import '../services/support_service.dart';
import '../theme/app_theme.dart';
import 'service_provider_directory_screen.dart';

const List<String> _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime d) {
  final local = d.toLocal();
  return '${_kMonths[local.month - 1]} ${local.day}, ${local.year}';
}

/// The tenant's own view of every maintenance request they've filed —
/// reachable from the "Report a maintenance issue" flow on an active
/// lease, and lands here straight after submitting a new one.
class MyMaintenanceRequestsScreen extends StatefulWidget {
  const MyMaintenanceRequestsScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<MyMaintenanceRequestsScreen> createState() => _MyMaintenanceRequestsScreenState();
}

class _MyMaintenanceRequestsScreenState extends State<MyMaintenanceRequestsScreen> {
  final _service = MaintenanceRequestService();
  final _assignmentService = MaintenanceAssignmentService();
  List<MaintenanceRequest> _rows = const [];
  // Keyed by maintenanceRequestId — at most one assignment per request
  // (084_maintenance_assignments.sql's UNIQUE constraint).
  Map<String, MaintenanceAssignment> _assignments = const {};
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  String get _token => widget.user.token ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    // Polling so an owner's accept/reject decision, or an escrow payment
    // clearing, made elsewhere shows up here without a manual refresh —
    // same pattern as my_rental_agreements_screen.dart.
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _service.fetchMine(token: _token);
      final assignments = await _assignmentService.fetchMine(token: _token);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _assignments = {for (final a in assignments) a.maintenanceRequestId: a};
        _loading = false;
      });
    } on MaintenanceRequestException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.message;
      });
    } on MaintenanceAssignmentException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.message;
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
        elevation: 0,
        title: const Text('Maintenance Requests', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
            : _error != null
                ? _ErrorState(message: _error!, onRetry: () => _load())
                : _rows.isEmpty
                    ? const _EmptyState()
                    : RefreshIndicator(
                        color: AppColors.primaryYellow,
                        onRefresh: () => _load(),
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, i) => _RequestCard(
                            request: _rows[i],
                            assignment: _assignments[_rows[i].id],
                            user: widget.user,
                            onChanged: () => _load(silent: true),
                          ),
                        ),
                      ),
      ),
    );
  }
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

/// Loosely maps an issue category to the closest specialist trade, to
/// pre-filter the directory when a tenant taps "Browse specialists" off
/// a rejected request. Not a strict mapping (e.g. "structural" issues
/// could need a few different trades) — just a sensible starting filter
/// the tenant can change.
ServiceProviderCategory _suggestedProviderCategory(MaintenanceCategory category) {
  switch (category) {
    case MaintenanceCategory.electrical:
      return ServiceProviderCategory.electrician;
    case MaintenanceCategory.plumbing:
      return ServiceProviderCategory.plumber;
    case MaintenanceCategory.structural:
      return ServiceProviderCategory.carpenter;
    case MaintenanceCategory.appliance:
      return ServiceProviderCategory.applianceTechnician;
    case MaintenanceCategory.other:
      return ServiceProviderCategory.other;
  }
}

class _RequestCard extends StatefulWidget {
  const _RequestCard({required this.request, required this.assignment, required this.user, required this.onChanged});

  final MaintenanceRequest request;
  final MaintenanceAssignment? assignment;
  final AppUser user;
  final VoidCallback onChanged;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  final _assignmentService = MaintenanceAssignmentService();
  final _supportService = SupportService();
  bool _confirming = false;
  bool _reporting = false;

  String get _token => widget.user.token ?? '';

  Future<void> _browseSpecialists() async {
    final assigned = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ServiceProviderDirectoryScreen(
        user: widget.user,
        initialCategory: _suggestedProviderCategory(widget.request.category),
        maintenanceRequestId: widget.request.id,
      ),
    ));
    if (assigned == true) widget.onChanged();
  }

  Future<void> _confirmComplete() async {
    final assignment = widget.assignment;
    if (assignment == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm job done?'),
        content: const Text(
          'This releases the payment held in escrow to the specialist right away. Only confirm once the work is actually finished.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Not yet')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('Confirm & release'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    setState(() => _confirming = true);
    try {
      await _assignmentService.confirmComplete(token: _token, id: assignment.id);
      if (!mounted) return;
      widget.onChanged();
    } on MaintenanceAssignmentException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _reportProblem() async {
    final assignment = widget.assignment;
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Report a problem'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(hintText: "What's wrong with this job?", border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Send to admin'),
          ),
        ],
      ),
    );
    if (note == null || note.isEmpty) return;
    setState(() => _reporting = true);
    try {
      // Reuses the existing support-tickets pipeline rather than a
      // bespoke dispute flow (Phase 7's "reuses support_tickets pattern")
      // — an admin reviewing the ticket can refund the escrow from the
      // maintenance-assignments oversight screen.
      await _supportService.submitTicket(
        token: _token,
        category: 'other',
        subject: 'Maintenance dispute — ${assignment?.provider?.name ?? widget.request.category.label}',
        body: 'Maintenance request ${widget.request.id}'
            '${assignment != null ? ' / assignment ${assignment.id}' : ''}\n\n$note',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reported to admin.')));
    } on SupportServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _reporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final assignment = widget.assignment;
    final color = _statusColor(request.status);
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
                  request.status.label,
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
          if (request.decisionNote != null && request.decisionNote!.trim().isNotEmpty) ...[
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
          if (request.status == MaintenanceRequestStatus.rejected && assignment == null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _browseSpecialists,
                icon: const Icon(Icons.handyman_outlined, size: 16),
                label: const Text('Browse specialists', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink, side: const BorderSide(color: AppColors.border)),
              ),
            ),
          ],
          if (assignment != null) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 10),
            _AssignmentPanel(assignment: assignment),
            if (assignment.escrowStatus == EscrowStatus.held) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _confirming ? null : _confirmComplete,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                  icon: _confirming
                      ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Confirm job done & release payment', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                ),
              ),
            ],
            if (assignment.escrowStatus == EscrowStatus.held || assignment.escrowStatus == EscrowStatus.released) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _reporting ? null : _reportProblem,
                  icon: const Icon(Icons.flag_outlined, size: 15, color: AppColors.danger),
                  label: const Text('Report a problem', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.danger)),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Read-only summary of the assigned specialist + escrow state, shown on
/// a maintenance request card once a specialist has been picked.
class _AssignmentPanel extends StatelessWidget {
  const _AssignmentPanel({required this.assignment});
  final MaintenanceAssignment assignment;

  Color get _escrowColor {
    switch (assignment.escrowStatus) {
      case EscrowStatus.pendingPayment:
        return Colors.orange;
      case EscrowStatus.held:
        return AppColors.primaryYellow;
      case EscrowStatus.released:
        return AppColors.success;
      case EscrowStatus.refunded:
        return AppColors.slate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = assignment.provider;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline, size: 16, color: AppColors.ink),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  provider?.name ?? 'Specialist',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _escrowColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                child: Text(assignment.escrowStatus.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _escrowColor)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${provider?.phone ?? ''}  ·  Quoted ${assignment.quotedCostBirr.toStringAsFixed(0)} ${assignment.currency}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.slate),
          ),
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
            Icon(Icons.build_outlined, size: 40, color: AppColors.slate),
            SizedBox(height: 12),
            Text(
              "No maintenance requests yet",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            SizedBox(height: 6),
            Text(
              "Anything you report on an active lease shows up here.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.slate),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

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
