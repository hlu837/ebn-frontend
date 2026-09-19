import 'package:flutter/material.dart';

import '../models/admin_user.dart';
import '../services/admin_service.dart';
import '../theme/app_theme.dart';

/// Admin's queue for Property Owner sign-ups — visitors who registered
/// with `requestedRole: 'property_owner'` and are sitting in
/// `account_status = 'pending_approval'` (see 064_property_owner_role.sql
/// and auth.js's /signup). Unlike Affiliater/Agent/Investor, this role
/// has no payment step — the only gate is this screen.
///
/// Approve flips the account to `role: 'property_owner'`,
/// `account_status: 'active'`. Reject demotes it back to a plain active
/// Visitor (`role: 'user'`) rather than deleting it, since the
/// email/password are already real — see AdminService.rejectPendingRole.
class AdminPendingPropertyOwnersScreen extends StatefulWidget {
  const AdminPendingPropertyOwnersScreen({super.key, required this.token});

  final String token;

  @override
  State<AdminPendingPropertyOwnersScreen> createState() => _AdminPendingPropertyOwnersScreenState();
}

class _AdminPendingPropertyOwnersScreenState extends State<AdminPendingPropertyOwnersScreen> {
  final _service = AdminService();

  bool _loading = true;
  String? _loadError;
  List<AdminUser> _pending = const [];
  final Set<String> _busyIds = {};

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
      final rows = await _service.fetchPendingPropertyOwners(token: widget.token);
      if (!mounted) return;
      setState(() {
        // Defensive filter — accountStatus=pending_approval is currently
        // Property-Owner-only, but this keeps the screen honest if that
        // ever changes.
        _pending = rows.where((u) => u.isPendingPropertyOwner).toList();
        _loading = false;
      });
    } on AdminServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    }
  }

  Future<bool> _confirm(String title, String body, {required bool isReject}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        content: Text(body, style: const TextStyle(fontSize: 13.5, color: AppColors.slate)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isReject ? AppColors.danger : AppColors.success,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isReject ? 'Reject' : 'Approve'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _approve(AdminUser user) async {
    final ok = await _confirm(
      'Approve ${user.fullName}?',
      'They\'ll be able to sign in as a Property Owner and start listing right away.',
      isReject: false,
    );
    if (!ok) return;
    setState(() => _busyIds.add(user.id));
    try {
      await _service.approvePendingRole(user.id, token: widget.token);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${user.fullName} approved as Property Owner.')));
      setState(() => _pending = _pending.where((u) => u.id != user.id).toList());
    } on AdminServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyIds.remove(user.id));
    }
  }

  Future<void> _reject(AdminUser user) async {
    final ok = await _confirm(
      'Reject this sign-up?',
      '${user.fullName} will stay as a regular Visitor — the account isn\'t deleted, just not made a Property Owner.',
      isReject: true,
    );
    if (!ok) return;
    setState(() => _busyIds.add(user.id));
    try {
      await _service.rejectPendingRole(user.id, token: widget.token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign-up declined.')));
      setState(() => _pending = _pending.where((u) => u.id != user.id).toList());
    } on AdminServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyIds.remove(user.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        title: Text(
          'Property Owner Sign-ups${_pending.isEmpty ? '' : ' (${_pending.length})'}',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _ErrorState(message: _loadError!, onRetry: _load)
              : _pending.isEmpty
                  ? const _EmptyQueue()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: _pending.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) {
                          final u = _pending[i];
                          final busy = _busyIds.contains(u.id);
                          return _PendingOwnerCard(
                            user: u,
                            busy: busy,
                            onApprove: () => _approve(u),
                            onReject: () => _reject(u),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _PendingOwnerCard extends StatelessWidget {
  const _PendingOwnerCard({required this.user, required this.busy, required this.onApprove, required this.onReject});

  final AdminUser user;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays >= 1) return '${diff.inDays} day(s) ago';
    if (diff.inHours >= 1) return '${diff.inHours} hour(s) ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes} minute(s) ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: Color(0xFFF0F0EE), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const Icon(Icons.house_rounded, size: 19, color: Color(0xFF4A4A45)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.fullName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    Text(user.email, style: const TextStyle(fontSize: 11.5, color: AppColors.slate)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.primaryYellow.withOpacity(0.14), borderRadius: BorderRadius.circular(AppRadii.pill)),
                child: const Text('Property Owner', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.ink)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (user.phone != null && user.phone!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('Phone: ${user.phone}', style: const TextStyle(fontSize: 12.5, color: AppColors.ink, fontWeight: FontWeight.w600)),
            ),
          Text('Signed up ${_relative(user.createdAt)}', style: const TextStyle(fontSize: 12, color: AppColors.slate)),
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
                  onPressed: busy ? null : onApprove,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                  child: busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                      : const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.house_rounded, size: 40, color: AppColors.slate),
            SizedBox(height: AppSpacing.md),
            Text('No Property Owner sign-ups waiting on review.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: AppColors.slate)),
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
