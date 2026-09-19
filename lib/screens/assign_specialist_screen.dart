import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/auth_response.dart';
import '../models/service_provider.dart';
import '../services/maintenance_assignment_service.dart';
import '../services/payment_service.dart';
import '../theme/app_theme.dart';

enum _Stage { quote, launching, waiting, verifying, failed, done }

/// Phases 4-5 of the maintenance-request workflow: the tenant confirms a
/// quoted cost for [provider], creates the assignment, then pays that
/// amount into escrow via Chapa — same launch/poll/verify pattern
/// my_rental_agreements_screen.dart uses for its own payment, just
/// started from a fresh screen instead of a bottom sheet since there's a
/// quote-entry step first.
class AssignSpecialistScreen extends StatefulWidget {
  const AssignSpecialistScreen({
    super.key,
    required this.user,
    required this.maintenanceRequestId,
    required this.provider,
  });

  final AppUser user;
  final String maintenanceRequestId;
  final ServiceProvider provider;

  @override
  State<AssignSpecialistScreen> createState() => _AssignSpecialistScreenState();
}

class _AssignSpecialistScreenState extends State<AssignSpecialistScreen> {
  final _assignmentService = MaintenanceAssignmentService();
  final _paymentService = PaymentService();
  final _costController = TextEditingController();

  _Stage _stage = _Stage.quote;
  String? _error;
  String? _assignmentId;
  String? _txRef;
  Timer? _poll;
  int _pollAttempts = 0;
  bool _checking = false;
  bool _submitting = false;

  static const _maxPollAttempts = 60; // ~5 minutes at 5s intervals

  String get _token => widget.user.token ?? '';

  @override
  void initState() {
    super.initState();
    if (widget.provider.rateCents > 0) {
      _costController.text = widget.provider.rateBirr.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _costController.dispose();
    super.dispose();
  }

  (String, String) _splitName() {
    final parts = widget.user.fullName.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return (parts.first, '');
    return (parts.first, parts.sublist(1).join(' '));
  }

  Future<void> _confirmAndPay() async {
    final birr = double.tryParse(_costController.text.trim());
    if (birr == null || birr <= 0) {
      setState(() => _error = 'Enter the quoted cost in Birr.');
      return;
    }
    final cents = (birr * 100).round();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final assignment = await _assignmentService.assign(
        token: _token,
        maintenanceRequestId: widget.maintenanceRequestId,
        serviceProviderId: widget.provider.id,
        quotedCostCents: cents,
      );
      _assignmentId = assignment.id;
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _stage = _Stage.launching;
      });
      await _startCheckout(birr);
    } on MaintenanceAssignmentException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    }
  }

  Future<void> _startCheckout(double amountBirr) async {
    final (firstName, lastName) = _splitName();
    try {
      final checkout = await _paymentService.initialize(
        purpose: 'maintenance_escrow_$_assignmentId',
        amount: amountBirr,
        email: widget.user.email,
        ownerUserId: widget.user.id,
        firstName: firstName,
        lastName: lastName.isEmpty ? null : lastName,
        description: 'Maintenance job — ${widget.provider.name}',
      );
      _txRef = checkout.txRef;
      final opened = await launchUrl(Uri.parse(checkout.checkoutUrl), mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (!opened) {
        setState(() {
          _stage = _Stage.failed;
          _error = "Couldn't open the payment page. Try again.";
        });
        return;
      }
      setState(() => _stage = _Stage.waiting);
      _pollAttempts = 0;
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _checkStatus());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
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
      setState(() => _stage = _Stage.verifying);
    }
    _pollAttempts++;
    try {
      final status = await _paymentService.verify(txRef);
      if (!mounted) return;
      if (status == PaymentStatus.success) {
        _poll?.cancel();
        setState(() => _stage = _Stage.done);
        _checking = false;
        return;
      }
      if (status == PaymentStatus.failed) {
        _poll?.cancel();
        setState(() {
          _stage = _Stage.failed;
          _error = 'The payment failed or was cancelled.';
        });
        _checking = false;
        return;
      }
      if (manual) setState(() => _stage = _Stage.waiting);
      if (_pollAttempts >= _maxPollAttempts) {
        _poll?.cancel();
        setState(() {
          _stage = _Stage.failed;
          _error = "We haven't seen a payment yet. If you completed checkout, tap Refresh again.";
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (manual) {
        setState(() {
          _stage = _Stage.failed;
          _error = '$e';
        });
      }
    }
    _checking = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text('Assign Specialist', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _buildStage(context),
        ),
      ),
    );
  }

  Widget _buildStage(BuildContext context) {
    if (_stage == _Stage.done) {
      return _DoneView(onFinish: () => Navigator.of(context).pop(true));
    }
    if (_stage == _Stage.quote) {
      return _QuoteForm(
        provider: widget.provider,
        controller: _costController,
        error: _error,
        submitting: _submitting,
        onSubmit: _confirmAndPay,
      );
    }
    // launching / waiting / verifying / failed all share the same
    // "payment in flight" layout, same as _AgreementDetailSheet's.
    return _PaymentStatusView(
      provider: widget.provider,
      stage: _stage,
      error: _error,
      onRefresh: () => _checkStatus(manual: true),
      onRetry: () {
        setState(() {
          _stage = _Stage.quote;
          _error = null;
        });
      },
    );
  }
}

class _QuoteForm extends StatelessWidget {
  const _QuoteForm({
    required this.provider,
    required this.controller,
    required this.error,
    required this.submitting,
    required this.onSubmit,
  });

  final ServiceProvider provider;
  final TextEditingController controller;
  final String? error;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(provider.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text('${provider.category.label} · ${provider.city}',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.slate, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text('Quoted cost', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 6),
        const Text(
          'Agree this with the specialist first (by phone) — this is what gets held in escrow until you confirm the job is done.',
          style: TextStyle(fontSize: 12, color: AppColors.slate, height: 1.4),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          decoration: InputDecoration(
            prefixText: 'ETB ',
            hintText: 'e.g. 500',
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.sm), borderSide: const BorderSide(color: AppColors.border)),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!, style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
        ],
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: submitting ? null : onSubmit,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryYellow, foregroundColor: AppColors.ink, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink))
                : const Text('Assign & pay into escrow', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }
}

class _PaymentStatusView extends StatelessWidget {
  const _PaymentStatusView({
    required this.provider,
    required this.stage,
    required this.error,
    required this.onRefresh,
    required this.onRetry,
  });

  final ServiceProvider provider;
  final _Stage stage;
  final String? error;
  final VoidCallback onRefresh;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (stage == _Stage.failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(error ?? 'Something went wrong.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.slate)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRefresh,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primaryYellow, foregroundColor: AppColors.ink),
              child: const Text('Check again'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Start over')),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primaryYellow),
          const SizedBox(height: 16),
          Text(
            stage == _Stage.launching ? 'Opening checkout…' : stage == _Stage.verifying ? 'Checking payment…' : 'Waiting for payment…',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 6),
          Text('${provider.name} will be assigned once payment clears.', style: const TextStyle(fontSize: 12.5, color: AppColors.slate), textAlign: TextAlign.center),
          if (stage == _Stage.waiting) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRefresh, child: const Text('I\'ve paid — refresh')),
          ],
        ],
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({required this.onFinish});
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 48, color: AppColors.success),
          const SizedBox(height: 14),
          const Text('Specialist assigned', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 6),
          const Text(
            'Payment is held in escrow. Once the job is done, come back to your maintenance requests and confirm to release it.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.slate, height: 1.4),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: onFinish,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryYellow, foregroundColor: AppColors.ink),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
