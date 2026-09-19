import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../models/order_request.dart';
import '../theme/app_theme.dart';

const List<String> _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _shortDate(DateTime d) {
  final local = d.toLocal();
  return '${_kMonths[local.month - 1]} ${local.day}';
}

/// One claimed "Order Us" request, as shown under Property Management ->
/// My claims. It's someone else's requirement (a visitor looking to buy or
/// rent), so the card leads with what they asked for and how to reach them.
class AgentClaimedOrderCard extends StatelessWidget {
  const AgentClaimedOrderCard({super.key, required this.request});

  final OrderRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final disputed = r.status == OrderRequestStatus.disputed;
    final pillColor = disputed ? AppColors.danger : AppColors.primaryYellowDark;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  r.title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: pillColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  r.status.agentLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: pillColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${r.category.label} · ${r.budgetSummary}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.slate),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.place_outlined, size: 14, color: AppColors.slate),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(r.locationSummary, style: const TextStyle(fontSize: 12.5, color: AppColors.slate)),
              ),
            ],
          ),
          if (r.description.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.slate, height: 1.4),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 15, color: AppColors.ink),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${r.requesterName} · ${r.requesterPhone}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ),
            ],
          ),
          if (r.confirmedAt != null) ...[
            const SizedBox(height: 3),
            Text(
              'Claimed ${_shortDate(r.confirmedAt!)}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.slate),
            ),
          ],
        ],
      ),
    );
  }
}
