import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/auth_response.dart';
import '../models/rental_agreement.dart';
import '../services/payment_service.dart';
import '../services/rental_agreement_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_buttons.dart';

/// The requester's own view of the Review-tab pipeline — "My Rental
/// Agreements": documents under review, an agreement waiting on payment
/// (with a live countdown), or the closed history. Reachable from the
/// visitor Account tab, and landed on straight after submitting
/// documents (see `submit_rental_documents_screen.dart`).
class MyRentalAgreementsScreen extends StatefulWidget {
  const MyRentalAgreementsScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<MyRentalAgreementsScreen> createState() => _MyRentalAgreementsScreenState();
}

class _MyRentalAgreementsScreenState extends State<MyRentalAgreementsScreen> {
  final _service = RentalAgreementService();
  List<RentalAgreement> _rows = const [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  String get _token => widget.user.token ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    // Polling (not just a local countdown) so a decision the owner makes
    // elsewhere — sending the agreement, rejecting — shows up here without
    // a manual refresh, same pattern as property_owner_inbox_screen.dart.
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
      final rows = await _service.listMine(token: _token);
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

  Future<void> _openRow(RentalAgreement row) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AgreementDetailSheet(user: widget.user, agreement: row),
    );
    if (!mounted) return;
    _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text('My Rental Agreements', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
                          itemBuilder: (context, i) => _AgreementCard(agreement: _rows[i], onTap: () => _openRow(_rows[i])),
                        ),
                      ),
      ),
    );
  }
}

class _AgreementCard extends StatelessWidget {
  const _AgreementCard({required this.agreement, required this.onTap});

  final RentalAgreement agreement;
  final VoidCallback onTap;

  Color get _statusColor {
    switch (agreement.status) {
      case RentalAgreementStatus.documentsSubmitted:
        return AppColors.slate;
      case RentalAgreementStatus.agreementSent:
        return AppColors.primaryYellow;
      case RentalAgreementStatus.paid:
        return AppColors.success;
      case RentalAgreementStatus.rejected:
      case RentalAgreementStatus.expired:
        return AppColors.danger;
    }
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
                    if (agreement.status == RentalAgreementStatus.agreementSent && agreement.timeLeft != null)
                      _CountdownText(expiresAt: agreement.expiresAt!)
                    else
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

  String get _subtitle {
    switch (agreement.status) {
      case RentalAgreementStatus.documentsSubmitted:
        return 'Waiting on the owner to review your documents';
      case RentalAgreementStatus.agreementSent:
        return 'Tap to view the agreement and pay';
      case RentalAgreementStatus.paid:
        return 'Rental confirmed';
      case RentalAgreementStatus.rejected:
        return agreement.rejectedReason?.trim().isNotEmpty == true ? agreement.rejectedReason! : 'Owner declined this request';
      case RentalAgreementStatus.expired:
        return 'Payment window closed';
    }
  }
}

/// Live-ticking "Xh Ym left" label — purely cosmetic, the server is the
/// source of truth for actual expiry (see rentalAgreements.expire).
class _CountdownText extends StatefulWidget {
  const _CountdownText({required this.expiresAt});
  final DateTime expiresAt;

  @override
  State<_CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<_CountdownText> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.expiresAt.difference(DateTime.now());
    if (left.isNegative) {
      return const Text('Payment window closing…', style: TextStyle(fontSize: 12.5, color: AppColors.danger, fontWeight: FontWeight.w700));
    }
    final h = left.inHours;
    final m = left.inMinutes % 60;
    return Text('${h}h ${m}m left to pay', style: const TextStyle(fontSize: 12.5, color: AppColors.primaryYellow, fontWeight: FontWeight.w700));
  }
}

class _AgreementDetailSheet extends StatefulWidget {
  const _AgreementDetailSheet({required this.user, required this.agreement});
  final AppUser user;
  final RentalAgreement agreement;

  @override
  State<_AgreementDetailSheet> createState() => _AgreementDetailSheetState();
}

enum _PayStage { idle, launching, waiting, verifying, failed, done }

class _AgreementDetailSheetState extends State<_AgreementDetailSheet> {
  final _paymentService = PaymentService();
  _PayStage _stage = _PayStage.idle;
  String? _txRef;
  String? _error;
  Timer? _poll;
  int _pollAttempts = 0;
  bool _checking = false;

  static const _maxPollAttempts = 60; // ~5 minutes at 5s intervals

  RentalAgreement get _a => widget.agreement;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  (String, String) _splitName() {
    final parts = widget.user.fullName.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return (parts.first, '');
    return (parts.first, parts.sublist(1).join(' '));
  }

  Future<void> _startCheckout() async {
    setState(() {
      _stage = _PayStage.launching;
      _error = null;
    });
    final (firstName, lastName) = _splitName();
    try {
      final checkout = await _paymentService.initialize(
        purpose: 'rental_agreement_${_a.id}',
        amount: _a.totalDue,
        currency: _a.currency,
        email: widget.user.email,
        ownerUserId: widget.user.id,
        firstName: firstName,
        lastName: lastName.isEmpty ? null : lastName,
        description: 'Rental agreement — ${_a.asset?.title ?? "property"}',
      );
      _txRef = checkout.txRef;
      final opened = await launchUrl(Uri.parse(checkout.checkoutUrl), mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (!opened) {
        setState(() {
          _stage = _PayStage.failed;
          _error = "Couldn't open the payment page. Try again.";
        });
        return;
      }
      setState(() => _stage = _PayStage.waiting);
      _pollAttempts = 0;
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _checkStatus());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _PayStage.failed;
        _error = '$e';
      });
    }
  }

  Future<void> _checkStatus({bool manual = false}) async {
    final txRef = _txRef;
    if (txRef == null || _checking) return;
    _checking = true;
    if (manual) {
      _poll?.cancel();
      setState(() => _stage = _PayStage.verifying);
    }
    _pollAttempts++;
    try {
      final status = await _paymentService.verify(txRef);
      if (!mounted) return;
      if (status == PaymentStatus.success) {
        _poll?.cancel();
        setState(() => _stage = _PayStage.done);
        return;
      }
      if (status == PaymentStatus.failed) {
        _poll?.cancel();
        setState(() {
          _stage = _PayStage.failed;
          _error = 'The payment failed or was cancelled.';
        });
        return;
      }
      if (manual) setState(() => _stage = _PayStage.waiting);
      if (_pollAttempts >= _maxPollAttempts) {
        _poll?.cancel();
        setState(() {
          _stage = _PayStage.failed;
          _error = "We haven't seen a payment yet. If you completed checkout, tap Refresh again — otherwise try again.";
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (manual) {
        setState(() {
          _stage = _PayStage.failed;
          _error = '$e';
        });
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(color: AppColors.cloud, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, top: AppSpacing.lg, bottom: AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(_a.asset?.title ?? 'Rental agreement',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  ),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ..._bodyFor(_a.status),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _bodyFor(RentalAgreementStatus status) {
    switch (status) {
      case RentalAgreementStatus.documentsSubmitted:
        return const [
          Text(
            "Your documents are with the owner for review. You'll get a notification as soon as they send the rental agreement — or use the chat if you want to follow up.",
            style: TextStyle(fontSize: 13.5, color: AppColors.slate, height: 1.4),
          ),
        ];
      case RentalAgreementStatus.rejected:
        return [
          const Text('This request was declined.', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
          if (_a.rejectedReason?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(_a.rejectedReason!, style: const TextStyle(fontSize: 13, color: AppColors.slate)),
          ],
        ];
      case RentalAgreementStatus.expired:
        return const [
          Text(
            "The 24-hour payment window closed before a payment came through, so this listing is open to other users again.",
            style: TextStyle(fontSize: 13.5, color: AppColors.slate, height: 1.4),
          ),
        ];
      case RentalAgreementStatus.paid:
        return const [
          Icon(Icons.check_circle_rounded, color: AppColors.success, size: 40),
          SizedBox(height: 10),
          Text('This rental is confirmed and closed.', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
        ];
      case RentalAgreementStatus.agreementSent:
        return _agreementSentBody();
    }
  }

  List<Widget> _agreementSentBody() {
    if (_stage == _PayStage.done) {
      return const [
        SizedBox(height: 8),
        Icon(Icons.check_circle_rounded, color: AppColors.success, size: 40),
        SizedBox(height: 10),
        Text('Payment confirmed — this rental is closed.', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
      ];
    }
    final left = _a.timeLeft;
    return [
      if (left != null && left > Duration.zero) _CountdownText(expiresAt: _a.expiresAt!),
      const SizedBox(height: AppSpacing.sm),
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_a.agreementTerms ?? '', style: const TextStyle(fontSize: 13.5, color: AppColors.ink, height: 1.4)),
            const Divider(height: 20, color: AppColors.border),
            Row(
              children: [
                const Expanded(child: Text('Rent', style: TextStyle(fontSize: 13, color: AppColors.slate))),
                Text('${_a.rentAmount?.toStringAsFixed(0) ?? '-'} ${_a.currency}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ],
            ),
            if (_a.depositAmount != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Expanded(child: Text('Deposit', style: TextStyle(fontSize: 13, color: AppColors.slate))),
                  Text('${_a.depositAmount!.toStringAsFixed(0)} ${_a.currency}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                const Expanded(child: Text('Total due', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink))),
                Text('${_a.totalDue.toStringAsFixed(0)} ${_a.currency}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: AppSpacing.md),
        Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
      ],
      const SizedBox(height: AppSpacing.lg),
      ..._payActionsFor(_stage),
    ];
  }

  List<Widget> _payActionsFor(_PayStage stage) {
    switch (stage) {
      case _PayStage.idle:
      case _PayStage.failed:
        return [
          PrimaryButton(
            label: 'Pay ${_a.totalDue.toStringAsFixed(0)} ${_a.currency} with Chapa',
            backgroundColor: AppColors.primaryYellow,
            foregroundColor: Colors.white,
            onPressed: _startCheckout,
          ),
        ];
      case _PayStage.launching:
      case _PayStage.verifying:
        return const [PrimaryButton(label: 'Please wait…', isLoading: true, onPressed: null)];
      case _PayStage.waiting:
        return [
          PrimaryButton(
            label: "I've paid — check now",
            backgroundColor: AppColors.primaryYellow,
            foregroundColor: Colors.white,
            onPressed: () => _checkStatus(manual: true),
          ),
        ];
      case _PayStage.done:
        return const [];
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fact_check_outlined, size: 44, color: AppColors.slate),
            SizedBox(height: 14),
            Text('No rental agreements yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
            SizedBox(height: 6),
            Text(
              "Once you submit documents for a property you're renting, track its progress here.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.slate, height: 1.4),
            ),
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
