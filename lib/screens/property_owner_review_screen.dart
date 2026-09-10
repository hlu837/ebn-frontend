import 'dart:async';

import 'package:flutter/material.dart';

import '../models/auth_response.dart';
import '../models/rental_agreement.dart';
import '../services/rental_agreement_service.dart';
import '../theme/app_theme.dart';
import 'property_owner_review_detail_screen.dart';

/// The Property Owner's Review tab — the real implementation of the
/// placeholder described in `property_owner_home_screen.dart`: requests
/// that need a decision (submitted ID/documents), agreements out for
/// payment (24h countdown), and the decided history.
class PropertyOwnerReviewScreen extends StatefulWidget {
  const PropertyOwnerReviewScreen({super.key, required this.user, this.onQueueChanged});

  final AppUser user;

  /// Called after every successful load with the count of rows needing a
  /// decision (documents_submitted) — so the bottom nav can show a badge,
  /// same pattern as the Inbox tab's unread count.
  final ValueChanged<int>? onQueueChanged;

  @override
  State<PropertyOwnerReviewScreen> createState() => _PropertyOwnerReviewScreenState();
}

enum _Filter { needsReview, awaitingPayment, history }

extension _FilterX on _Filter {
  String get label {
    switch (this) {
      case _Filter.needsReview:
        return 'Needs review';
      case _Filter.awaitingPayment:
        return 'Awaiting payment';
      case _Filter.history:
        return 'History';
    }
  }

  String get wireStatus {
    switch (this) {
      case _Filter.needsReview:
        return 'documents_submitted';
      case _Filter.awaitingPayment:
        return 'agreement_sent';
      case _Filter.history:
        return 'all_history'; // handled client-side, see below
    }
  }
}

class _PropertyOwnerReviewScreenState extends State<PropertyOwnerReviewScreen> {
  final _service = RentalAgreementService();
  _Filter _filter = _Filter.needsReview;
  List<RentalAgreement> _rows = const [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  String get _token => widget.user.token ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
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
      // History has no single backend status filter — pull 'active' (the
      // two live states) always for the badge count, plus whatever the
      // current tab needs.
      final active = await _service.listQueue(token: _token, status: 'active');
      widget.onQueueChanged?.call(active.where((r) => r.status == RentalAgreementStatus.documentsSubmitted).length);

      List<RentalAgreement> rows;
      if (_filter == _Filter.history) {
        final paid = await _service.listQueue(token: _token, status: 'paid');
        final rejected = await _service.listQueue(token: _token, status: 'rejected');
        final expired = await _service.listQueue(token: _token, status: 'expired');
        rows = [...paid, ...rejected, ...expired]..sort((a, b) => (b.updatedAt ?? b.createdAt).compareTo(a.updatedAt ?? a.createdAt));
      } else {
        rows = active.where((r) => r.status.wireValue == _filter.wireStatus).toList();
      }

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on RentalAgreementException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.message;
      });
    }
  }

  void _setFilter(_Filter f) {
    setState(() => _filter = f);
    _load();
  }

  Future<void> _openRow(RentalAgreement row) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PropertyOwnerReviewDetailScreen(user: widget.user, agreement: row),
    ));
    if (!mounted) return;
    _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        elevation: 0,
        foregroundColor: AppColors.ink,
        automaticallyImplyLeading: false,
        title: const Text('Review', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink)),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _FilterChips(current: _filter, onChanged: _setFilter),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: () => _load())
                      : _rows.isEmpty
                          ? _EmptyState(filter: _filter)
                          : RefreshIndicator(
                              color: AppColors.primaryYellow,
                              onRefresh: () => _load(),
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                itemCount: _rows.length,
                                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                                itemBuilder: (context, i) => _ReviewCard(agreement: _rows[i], onTap: () => _openRow(_rows[i])),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.current, required this.onChanged});
  final _Filter current;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final f in _Filter.values) ...[
              ChoiceChip(
                label: Text(f.label),
                selected: current == f,
                onSelected: (_) => onChanged(f),
                selectedColor: AppColors.primaryYellow,
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: current == f ? Colors.white : AppColors.ink,
                ),
                backgroundColor: AppColors.card,
                side: BorderSide(color: current == f ? AppColors.primaryYellow : AppColors.border),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.agreement, required this.onTap});
  final RentalAgreement agreement;
  final VoidCallback onTap;

  Color get _statusColor {
    switch (agreement.status) {
      case RentalAgreementStatus.documentsSubmitted:
        return AppColors.primaryYellow;
      case RentalAgreementStatus.agreementSent:
        return AppColors.ink;
      case RentalAgreementStatus.paid:
        return AppColors.success;
      case RentalAgreementStatus.rejected:
      case RentalAgreementStatus.expired:
        return AppColors.danger;
    }
  }

  String get _subtitle {
    switch (agreement.status) {
      case RentalAgreementStatus.documentsSubmitted:
        return 'From ${agreement.requester?.fullName ?? 'a requester'} — needs your review';
      case RentalAgreementStatus.agreementSent:
        return agreement.timeLeft != null ? _formatCountdown(agreement.timeLeft!) : 'Awaiting payment';
      case RentalAgreementStatus.paid:
        return 'Paid by ${agreement.requester?.fullName ?? 'tenant'}';
      case RentalAgreementStatus.rejected:
        return 'Declined';
      case RentalAgreementStatus.expired:
        return 'Payment window expired';
    }
  }

  String _formatCountdown(Duration d) {
    if (d == Duration.zero) return 'Payment window closing…';
    return '${d.inHours}h ${d.inMinutes % 60}m left to pay';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agreement.asset?.title ?? 'Property',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(_subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.slate)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: _statusColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                child: Text(agreement.status.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _statusColor)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});
  final _Filter filter;

  String get _message {
    switch (filter) {
      case _Filter.needsReview:
        return "Nothing needs your review right now — new document submissions will show up here.";
      case _Filter.awaitingPayment:
        return "No agreements are currently waiting on a payment.";
      case _Filter.history:
        return "Decided requests — paid, declined, or expired — will show up here.";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fact_check_outlined, size: 44, color: AppColors.slate),
            const SizedBox(height: 14),
            Text(_message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.slate, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.slate),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.slate, fontSize: 14)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
