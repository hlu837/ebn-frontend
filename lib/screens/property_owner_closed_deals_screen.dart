import 'package:flutter/material.dart';

import '../models/auth_response.dart';
import '../models/rental_agreement.dart';
import '../services/rental_agreement_service.dart';
import '../theme/app_theme.dart';
import 'broker_chat_screen.dart';

/// Finalized rentals — every [RentalAgreement] this owner has that's
/// reached `paid`, backed by `GET /api/rental-agreements/queue?status=paid`
/// (the same endpoint [PropertyOwnerReviewScreen] uses for the active
/// queue, just filtered to the closed-out end of the pipeline). Opened
/// from the Account tab's "Closed Deals" row.
class PropertyOwnerClosedDealsScreen extends StatefulWidget {
  const PropertyOwnerClosedDealsScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<PropertyOwnerClosedDealsScreen> createState() => _PropertyOwnerClosedDealsScreenState();
}

class _PropertyOwnerClosedDealsScreenState extends State<PropertyOwnerClosedDealsScreen> {
  final _service = RentalAgreementService();

  bool _loading = true;
  String? _loadError;
  List<RentalAgreement> _deals = const [];

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
      final rows = await _service.listQueue(token: widget.user.token ?? '', status: 'paid');
      if (!mounted) return;
      setState(() {
        // Newest deal first.
        _deals = rows..sort((a, b) => (b.paidAt ?? b.createdAt).compareTo(a.paidAt ?? a.createdAt));
        _loading = false;
      });
    } on RentalAgreementException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    }
  }

  void _openChat(RentalAgreement deal) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BrokerChatScreen.fromThread(thread: deal.toChatThread(), currentUser: widget.user),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        title: Text('Closed Deals${_deals.isEmpty ? '' : ' (${_deals.length})'}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
          : _loadError != null
              ? _ErrorState(message: _loadError!, onRetry: _load)
              : _deals.isEmpty
                  ? const _EmptyState()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: _deals.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) {
                          final deal = _deals[i];
                          return _DealCard(
                            deal: deal,
                            onMessage: deal.threadId != null ? () => _openChat(deal) : null,
                          );
                        },
                      ),
                    ),
    );
  }
}

class _DealCard extends StatelessWidget {
  const _DealCard({required this.deal, required this.onMessage});

  final RentalAgreement deal;
  final VoidCallback? onMessage;

  String _formatMoney(double amount) {
    final s = amount.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '—';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
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
                decoration: const BoxDecoration(color: Color(0xFFE3F5EA), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const Icon(Icons.check_circle_rounded, size: 19, color: AppColors.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deal.asset?.title ?? 'Listing',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text('Tenant: ${deal.requester?.fullName ?? 'Unknown'}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.slate)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFE3F5EA), borderRadius: BorderRadius.circular(AppRadii.pill)),
                child: const Text('Closed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text('${deal.currency} ${_formatMoney(deal.rentAmount ?? 0)}/mo',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primaryYellow)),
              ),
              Text('Paid ${_formatDate(deal.paidAt)}', style: const TextStyle(fontSize: 11.5, color: AppColors.slate)),
            ],
          ),
          if (onMessage != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: OutlinedButton.icon(
                onPressed: onMessage,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                label: const Text('Message Tenant'),
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
            Icon(Icons.handshake_outlined, size: 40, color: AppColors.slate),
            SizedBox(height: AppSpacing.md),
            Text('No finalized rentals yet — closed deals show up here once a tenant pays.',
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
