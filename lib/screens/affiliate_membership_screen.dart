import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/auth_response.dart';
import '../services/affiliate_service.dart';
import '../services/payment_service.dart';
import '../theme/app_theme.dart';
import '../widgets/affiliater_drawer.dart' show AffiliateTier, AffiliateTierX;

String _formatMoney(double value) {
  final s = value.abs().toStringAsFixed(0);
  final buffer = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final posFromEnd = s.length - i;
    buffer.write(s[i]);
    if (posFromEnd > 1 && posFromEnd % 3 == 1) buffer.write(',');
  }
  return '${value < 0 ? '-' : ''}${buffer.toString()}';
}

String _formatDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

AffiliateTier _tierFromString(String tier) => AffiliateTier.values
    .firstWhere((t) => t.name == tier, orElse: () => AffiliateTier.bronze);

/// The affiliate's current membership tier, the perks each tier unlocks, an
/// upgrade flow, and a billing history — backed by
/// `GET/POST /api/affiliates/me/membership*`.
class AffiliateMembershipScreen extends StatefulWidget {
  const AffiliateMembershipScreen(
      {super.key, required this.user, this.initialTier = AffiliateTier.bronze});

  final AppUser user;
  final AffiliateTier initialTier;

  @override
  State<AffiliateMembershipScreen> createState() =>
      _AffiliateMembershipScreenState();
}

class _AffiliateMembershipScreenState extends State<AffiliateMembershipScreen> {
  final _service = AffiliateService();
  late Future<AffiliateMembershipData> _future = _load();

  Future<AffiliateMembershipData> _load() =>
      _service.getMembership(widget.user.token ?? '');

  Future<void> _refresh() async {
    if (!mounted) return;
    final next = _load();
    setState(() => _future = next);
    await next;
    if (!mounted) return;
  }

  Future<void> _changeTier(
      AffiliateTier tier, AffiliateMembershipData membership) async {
    final currentTier = _tierFromString(membership.tier);
    if (tier == currentTier) return;
    final upgrading = tier.index > currentTier.index;
    try {
      final updated = await _service
          .upgradeMembership(widget.user.token ?? '', tier: tier.name);
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            upgrading
                ? 'Upgraded to ${tier.label}. Charged ETB ${_formatMoney(updated.monthlyFeeEtb)} today.'
                : 'Switched to ${tier.label}.',
          ),
        ),
      );
    } on AffiliateException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e, st) {
      // Catch-all so a plan change never fails silently. Logs the
      // real error/stack (visible via `adb logcat` for release
      // APKs) and still surfaces something to the user.
      debugPrint('Plan change failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not change plan: $e')),
      );
    }
  }

  /// Entry point for both "tap a package to switch" (free tiers only, in
  /// practice — see below) and the tier picker sheet's "Upgrade" rows.
  /// A free destination tier (fee == 0, i.e. bronze, or a tier the admin
  /// has priced at 0) switches instantly via [_confirmAndChangeTier] —
  /// there's nothing to charge. Anything with a real fee now has to go
  /// through an actual Chapa checkout: the backend refuses to apply a
  /// paid upgrade directly (see POST /me/membership/upgrade in
  /// routes/affiliates.js) and only grants it once Chapa confirms the
  /// payment (see activateAffiliateMembershipUpgrade in
  /// routes/payments.js) — no admin approval step exists or is needed
  /// for this flow, it's fully automatic on a confirmed payment.
  Future<void> _startUpgrade(
      AffiliateTier tier, AffiliateMembershipData membership) async {
    final currentTier = _tierFromString(membership.tier);
    if (tier == currentTier) return;
    final fee =
        membership.tierPricing[tier.name] ?? _kTierMonthlyFeeEtbFallback[tier] ?? 0;
    if (fee <= 0) {
      await _confirmAndChangeTier(tier, membership);
      return;
    }
    final paid = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cloud,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AffiliateChapaPaymentSheet(
        tier: tier,
        feeEtb: fee,
        user: widget.user,
      ),
    );
    if (paid == true && mounted) {
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Upgraded to ${tier.label}. Charged ETB ${_formatMoney(fee)} today.'),
        ),
      );
    }
  }

  Future<void> _confirmAndChangeTier(
      AffiliateTier tier, AffiliateMembershipData membership) async {
    final currentTier = _tierFromString(membership.tier);
    if (tier == currentTier) return;
    final fee = membership.tierPricing[tier.name] ??
        _kTierMonthlyFeeEtbFallback[tier] ??
        0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Switch to ${tier.label}?'),
        content: Text(fee == 0
            ? 'This plan is free.'
            : "You'll be charged ETB ${_formatMoney(fee)} today, then monthly."),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _changeTier(tier, membership);
  }

  void _openTierSheet(AffiliateMembershipData membership) {
    final currentTier = _tierFromString(membership.tier);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cloud,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _TierPickerSheet(
        currentTier: currentTier,
        tierPricing: membership.tierPricing,
        onSelect: (tier) {
          Navigator.of(context).pop();
          _startUpgrade(tier, membership);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        title: const Text('Membership',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: FutureBuilder<AffiliateMembershipData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              message: snapshot.error is AffiliateException
                  ? (snapshot.error as AffiliateException).message
                  : 'Something went wrong.',
              onRetry: _refresh,
            );
          }
          final membership = snapshot.data!;
          final tier = _tierFromString(membership.tier);
          final perks = membership.perks;
          final fee = membership.monthlyFeeEtb;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(AppRadii.lg)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(tier.icon, color: tier.color, size: 22),
                          const SizedBox(width: 8),
                          Text(tier.label,
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: tier.color)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        fee == 0
                            ? 'Free plan'
                            : 'ETB ${_formatMoney(fee)} / month',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        membership.renewalDate != null
                            ? 'Renews ${_formatDate(membership.renewalDate!)}'
                            : 'No active renewal',
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.white60,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (tier != AffiliateTier.diamond)
                        _TierProgressBar(tier: tier),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryYellow,
                              foregroundColor: Colors.white),
                          onPressed: () => _openTierSheet(membership),
                          icon: const Icon(Icons.workspace_premium_outlined,
                              size: 18),
                          label: Text(tier == AffiliateTier.bronze
                              ? 'Upgrade plan'
                              : 'Manage plan'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text('Packages',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
                const SizedBox(height: 4),
                const Text(
                    'Tap a package to switch — free tiers apply instantly, paid tiers open Chapa checkout.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.slate)),
                const SizedBox(height: AppSpacing.sm),
                for (final t in AffiliateTier.values) ...[
                  _TierOptionRow(
                    tier: t,
                    selected: t == tier,
                    currentTier: tier,
                    feeOverride: membership.tierPricing[t.name],
                    onTap: () => _startUpgrade(t, membership),
                  ),
                  if (t != AffiliateTier.values.last)
                    const SizedBox(height: AppSpacing.sm),
                ],
                const SizedBox(height: AppSpacing.lg),
                const Text('Perks on your plan',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      border: Border.all(color: AppColors.border)),
                  child: Column(
                    children: [
                      for (int i = 0; i < perks.length; i++) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_circle,
                                size: 18, color: tier.color),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(perks[i],
                                    style: const TextStyle(
                                        fontSize: 13.5,
                                        color: AppColors.ink,
                                        height: 1.3))),
                          ],
                        ),
                        if (i != perks.length - 1) const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text('Billing history',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
                const SizedBox(height: AppSpacing.sm),
                if (membership.billingHistory.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Center(
                        child: Text('No billing history yet.',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.slate))),
                  ),
                for (final b in membership.billingHistory) ...[
                  _BillingTile(entry: b),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          );
        },
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

class _TierProgressBar extends StatelessWidget {
  const _TierProgressBar({required this.tier});
  final AffiliateTier tier;

  @override
  Widget build(BuildContext context) {
    const tiers = AffiliateTier.values;
    final idx = tiers.indexOf(tier);
    final next = tiers[idx + 1];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Next tier: ${next.label}',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white70)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: LinearProgressIndicator(
            value: (idx + 1) / tiers.length,
            minHeight: 6,
            backgroundColor: Colors.white24,
            valueColor: AlwaysStoppedAnimation<Color>(tier.color),
          ),
        ),
      ],
    );
  }
}

class _BillingTile extends StatelessWidget {
  const _BillingTile({required this.entry});
  final AffiliateBillingEntry entry;

  @override
  Widget build(BuildContext context) {
    final upcoming = entry.status == 'upcoming';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: (upcoming ? AppColors.primaryYellow : AppColors.success)
                    .withValues(alpha: 0.1),
                shape: BoxShape.circle),
            child: Icon(upcoming ? Icons.schedule_rounded : Icons.check_rounded,
                size: 17,
                color: upcoming ? AppColors.primaryYellow : AppColors.success),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.label,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(_formatDate(entry.billedOn),
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.slate)),
              ],
            ),
          ),
          Text(
            entry.amount == 0 ? 'Free' : 'ETB ${_formatMoney(entry.amount)}',
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}

class _TierPickerSheet extends StatelessWidget {
  const _TierPickerSheet({
    required this.currentTier,
    required this.onSelect,
    this.tierPricing = const {},
  });
  final AffiliateTier currentTier;
  final ValueChanged<AffiliateTier> onSelect;
  final Map<String, double> tierPricing;

  @override
  Widget build(BuildContext context) {
    final upgradeTargets =
        AffiliateTier.values.where((t) => t.index > currentTier.index).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          const Text('Choose a plan',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
          const SizedBox(height: AppSpacing.md),
          if (upgradeTargets.isNotEmpty) ...[
            for (final tier in upgradeTargets) ...[
              _TierOptionRow(
                  tier: tier,
                  selected: tier == currentTier,
                  currentTier: currentTier,
                  feeOverride: tierPricing[tier.name],
                  onTap: () => onSelect(tier)),
              const SizedBox(height: AppSpacing.sm),
            ],
          ] else ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Column(
                  children: [
                    Icon(currentTier.icon, size: 44, color: currentTier.color),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'You are on the highest plan (${currentTier.label})',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'You already enjoy all premium features and top priority benefits.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.slate),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Fallback only — used if the server response ever omits tierPricing
// (e.g. an old cached response). The server is the source of truth so
// admin price changes always show up here.
const Map<AffiliateTier, double> _kTierMonthlyFeeEtbFallback = {
  AffiliateTier.bronze: 0,
  AffiliateTier.silver: 500,
  AffiliateTier.gold: 1500,
  AffiliateTier.diamond: 3500,
};

class _TierOptionRow extends StatelessWidget {
  const _TierOptionRow(
      {required this.tier,
      required this.selected,
      required this.onTap,
      this.currentTier,
      this.feeOverride});
  final AffiliateTier tier;
  final bool selected;
  final VoidCallback onTap;
  final AffiliateTier? currentTier;
  final double? feeOverride;

  @override
  Widget build(BuildContext context) {
    final fee = feeOverride ?? _kTierMonthlyFeeEtbFallback[tier] ?? 0;
    final isUpgrade = currentTier != null && tier.index > currentTier!.index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(
                color: selected ? tier.color : AppColors.border,
                width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(tier.icon, color: tier.color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(tier.label,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink)),
                        if (!selected && isUpgrade)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primaryYellow
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('Upgrade',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryYellow)),
                            ),
                          ),
                      ],
                    ),
                    Text(fee == 0 ? 'Free' : 'ETB ${_formatMoney(fee)} / month',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.slate)),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: tier.color, size: 20)
              else
                const Icon(Icons.chevron_right_rounded, color: AppColors.slate),
            ],
          ),
        ),
      ),
    );
  }
}

/// Real Chapa checkout for a paid tier upgrade. Opens Chapa's hosted
/// checkout in the system browser, then polls `PaymentService.verify`
/// until the payment settles. On success, the backend has already
/// applied the tier upgrade itself (see `activateAffiliateMembershipUpgrade`
/// in `routes/payments.js`) — this sheet just pops `true` so the caller
/// knows to refresh. There's no admin-approval step for this flow: it's
/// either "paid and applied automatically" or "not paid yet".
class _AffiliateChapaPaymentSheet extends StatefulWidget {
  const _AffiliateChapaPaymentSheet({
    required this.tier,
    required this.feeEtb,
    required this.user,
  });

  final AffiliateTier tier;
  final double feeEtb;
  final AppUser user;

  @override
  State<_AffiliateChapaPaymentSheet> createState() =>
      _AffiliateChapaPaymentSheetState();
}

class _AffiliateChapaPaymentSheetState
    extends State<_AffiliateChapaPaymentSheet> {
  bool _loading = false;
  bool _polling = false;
  String? _txRef;
  String? _error;
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _launchChapa() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      String email = widget.user.email;
      if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
        email =
            'user_${widget.user.id.isNotEmpty ? widget.user.id.substring(0, 8) : DateTime.now().millisecondsSinceEpoch}@gmail.com';
      }

      final checkout = await PaymentService().initialize(
        purpose: 'affiliate_membership_${widget.tier.name}',
        amount: widget.feeEtb,
        email: email,
        ownerUserId: widget.user.id.isNotEmpty ? widget.user.id : null,
        firstName: widget.user.fullName.split(' ').first,
        lastName: widget.user.fullName.split(' ').skip(1).join(' '),
        description:
            '${widget.tier.label} affiliate plan - ETB ${widget.feeEtb.toStringAsFixed(0)}',
      );

      if (!mounted) return;
      setState(() {
        _txRef = checkout.txRef;
        _loading = false;
        _polling = true;
      });

      final uri = Uri.parse(checkout.checkoutUrl);
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      _pollTimer =
          Timer.periodic(const Duration(seconds: 3), (_) => _pollVerify());
    } on PaymentException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _pollVerify() async {
    final txRef = _txRef;
    if (txRef == null || !mounted) return;
    try {
      final status = await PaymentService().verify(txRef);
      if (!mounted) return;
      if (status == PaymentStatus.success) {
        _pollTimer?.cancel();
        Navigator.of(context).pop(true);
      } else if (status == PaymentStatus.failed) {
        _pollTimer?.cancel();
        setState(() {
          _polling = false;
          _error = 'Payment was declined or cancelled. Please try again.';
        });
      }
      // pending → keep polling
    } on PaymentException {
      // Transient error — next tick retries.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
                color: AppColors.border, borderRadius: BorderRadius.circular(2)),
          ),
          Row(
            children: [
              Icon(widget.tier.icon, color: widget.tier.color, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Upgrade to ${widget.tier.label}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ETB ${widget.feeEtb.toStringAsFixed(0)} / month, billed today',
            style: const TextStyle(fontSize: 13, color: AppColors.slate),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_polling) ...[
            const Row(
              children: [
                SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Waiting for payment confirmation — finish paying in the browser, then come back here.",
                    style: TextStyle(fontSize: 12.5, color: AppColors.slate),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _pollVerify,
                child: const Text('I already paid — check now'),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _launchChapa,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.tier.color,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.button)),
                  elevation: 0,
                ),
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.bolt_rounded, size: 20),
                label: Text(
                  _loading
                      ? 'Preparing checkout…'
                      : 'Pay ETB ${widget.feeEtb.toStringAsFixed(0)} with Chapa',
                  style:
                      const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
