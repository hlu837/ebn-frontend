import 'package:flutter/material.dart';

import '../models/admin_settings_models.dart';
import '../services/admin_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_buttons.dart';

/// Admin > Settings > Maintenance Jobs. Phase 7 oversight: every
/// escrow-backed assignment across the platform, so an admin can see
/// what's held vs paid out, and — for a disputed job (tenant reported a
/// problem via the existing support-tickets pipeline, see
/// my_maintenance_requests_screen.dart's "Report a problem") — refund
/// the tenant instead of releasing to the specialist.
class AdminMaintenanceAssignmentsScreen extends StatefulWidget {
  const AdminMaintenanceAssignmentsScreen({super.key, required this.token});
  final String token;

  @override
  State<AdminMaintenanceAssignmentsScreen> createState() => _AdminMaintenanceAssignmentsScreenState();
}

class _AdminMaintenanceAssignmentsScreenState extends State<AdminMaintenanceAssignmentsScreen> {
  final _service = AdminSettingsService();
  List<AdminMaintenanceAssignment> _rows = const [];
  bool _loading = true;
  String? _error;
  String? _filter; // null = all

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
      final rows = await _service.fetchMaintenanceAssignments(token: widget.token, escrowStatus: _filter);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on AdminSettingsServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _refund(AdminMaintenanceAssignment row) async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Refund tenant?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Releases the ${row.quotedCostBirr.toStringAsFixed(0)} ${row.currency} held in escrow back to the tenant instead of paying ${row.providerName ?? 'the specialist'}.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.slate),
            ),
            const SizedBox(height: 10),
            TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Reason (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Refund'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.refundMaintenanceAssignment(row.id, note: noteController.text.trim(), token: widget.token);
      await _load();
    } on AdminSettingsServiceException catch (e) {
      if (!mounted) return;
      AppToast.showError(context, e.message);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'held':
        return AppColors.primaryYellow;
      case 'released':
        return AppColors.success;
      case 'refunded':
        return AppColors.slate;
      case 'pending_payment':
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(title: const Text('Maintenance Jobs'), backgroundColor: AppColors.cloud, foregroundColor: AppColors.ink),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(label: 'All', selected: _filter == null, onTap: () => setState(() { _filter = null; _load(); })),
                    const SizedBox(width: 6),
                    _FilterChip(label: 'Held', selected: _filter == 'held', onTap: () => setState(() { _filter = 'held'; _load(); })),
                    const SizedBox(width: 6),
                    _FilterChip(label: 'Released', selected: _filter == 'released', onTap: () => setState(() { _filter = 'released'; _load(); })),
                    const SizedBox(width: 6),
                    _FilterChip(label: 'Refunded', selected: _filter == 'refunded', onTap: () => setState(() { _filter = 'refunded'; _load(); })),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.slate)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: _rows.isEmpty
                              ? ListView(
                                  children: const [
                                    Padding(
                                      padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                                      child: Center(child: Text('Nothing here.', style: TextStyle(color: AppColors.slate))),
                                    ),
                                  ],
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.all(AppSpacing.lg),
                                  itemCount: _rows.length,
                                  itemBuilder: (context, i) {
                                    final row = _rows[i];
                                    final color = _statusColor(row.escrowStatus);
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                                      padding: const EdgeInsets.all(AppSpacing.md),
                                      decoration: BoxDecoration(
                                        color: AppColors.card,
                                        borderRadius: BorderRadius.circular(AppRadii.lg),
                                        border: Border.all(color: AppColors.border),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(row.assetTitle ?? 'Property', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                                                child: Text(row.escrowStatus.replaceAll('_', ' '), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${row.providerName ?? 'Specialist'} · ${row.providerPhone ?? ''} · ${row.quotedCostBirr.toStringAsFixed(0)} ${row.currency}',
                                            style: const TextStyle(fontSize: 12, color: AppColors.slate),
                                          ),
                                          if (row.escrowStatus == 'held') ...[
                                            const SizedBox(height: 8),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: OutlinedButton(
                                                onPressed: () => _refund(row),
                                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
                                                child: const Text('Refund tenant', style: TextStyle(fontSize: 12)),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? AppColors.ink : AppColors.slate)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primaryYellow,
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppColors.border),
    );
  }
}
