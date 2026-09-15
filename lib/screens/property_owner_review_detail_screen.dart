import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/auth_response.dart';
import '../models/rental_agreement.dart';
import '../services/rental_agreement_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_buttons.dart';

/// One rental-agreement pipeline row, from the owner's side — view the
/// requester's ID + supporting documents and either approve (send the
/// rental agreement, starting the 24h payment countdown) or reject
/// (reopens the listing). Once a decision is made, shows the resulting
/// state instead (awaiting payment / paid / declined / expired).
class PropertyOwnerReviewDetailScreen extends StatefulWidget {
  const PropertyOwnerReviewDetailScreen({super.key, required this.user, required this.agreement});

  final AppUser user;
  final RentalAgreement agreement;

  @override
  State<PropertyOwnerReviewDetailScreen> createState() => _PropertyOwnerReviewDetailScreenState();
}

class _PropertyOwnerReviewDetailScreenState extends State<PropertyOwnerReviewDetailScreen> {
  final _service = RentalAgreementService();
  late RentalAgreement _agreement;
  bool _busy = false;
  String? _error;

  String get _token => widget.user.token ?? '';

  @override
  void initState() {
    super.initState();
    _agreement = widget.agreement;
  }

  Future<void> _sendAgreement({
    required String terms,
    required double rentAmount,
    double? depositAmount,
    required int hours,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final row = await _service.sendAgreement(
        token: _token,
        id: _agreement.id,
        terms: terms,
        rentAmount: rentAmount,
        depositAmount: depositAmount,
        currency: _agreement.currency,
        hours: hours,
      );
      if (!mounted) return;
      setState(() {
        _agreement = row;
        _busy = false;
      });
    } on RentalAgreementException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _reject() async {
    final reason = await _promptRejectReason();
    if (reason == null) return; // cancelled
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final row = await _service.reject(token: _token, id: _agreement.id, reason: reason.isEmpty ? null : reason);
      if (!mounted) return;
      setState(() {
        _agreement = row;
        _busy = false;
      });
    } on RentalAgreementException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<String?> _promptRejectReason() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline this request?'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Reason (optional) — shown to the requester', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Decline'),
          ),
        ],
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
        elevation: 0,
        title: Text(_agreement.asset?.title ?? 'Review request', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _StatusBanner(agreement: _agreement),
            const SizedBox(height: AppSpacing.lg),
            Text('From ${_agreement.requester?.fullName ?? 'requester'}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
            if (_agreement.requesterNote?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(_agreement.requesterNote!, style: const TextStyle(fontSize: 13, color: AppColors.slate, height: 1.4)),
            ],
            const SizedBox(height: AppSpacing.lg),
            const Text('Digital ID', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 8),
            _DocImage(dataUri: _agreement.idDocumentUrl),
            if (_agreement.documentUrls.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              const Text('Supporting documents', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [for (final url in _agreement.documentUrls) _DocThumb(dataUri: url)],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
            ],
            const SizedBox(height: AppSpacing.xl),
            if (_agreement.status == RentalAgreementStatus.documentsSubmitted) ..._decisionButtons(),
          ],
        ),
      ),
    );
  }

  List<Widget> _decisionButtons() {
    if (_busy) {
      return const [PrimaryButton(label: 'Please wait…', isLoading: true, onPressed: null)];
    }
    return [
      PrimaryButton(
        label: 'Approve & send agreement',
        backgroundColor: AppColors.primaryYellow,
        foregroundColor: Colors.white,
        onPressed: () async {
          final sent = await showModalBottomSheet<_AgreementDraft>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const _SendAgreementSheet(),
          );
          if (sent != null) {
            await _sendAgreement(terms: sent.terms, rentAmount: sent.rentAmount, depositAmount: sent.depositAmount, hours: sent.hours);
          }
        },
      ),
      const SizedBox(height: AppSpacing.sm),
      SecondaryButton(label: 'Decline', onPressed: _reject, textColor: AppColors.danger, borderColor: AppColors.danger),
    ];
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.agreement});
  final RentalAgreement agreement;

  @override
  Widget build(BuildContext context) {
    String text;
    Color color;
    switch (agreement.status) {
      case RentalAgreementStatus.documentsSubmitted:
        text = 'Review the documents below, then approve or decline.';
        color = AppColors.primaryYellow;
        break;
      case RentalAgreementStatus.agreementSent:
        final left = agreement.timeLeft;
        text = left != null && left > Duration.zero
            ? 'Agreement sent — ${left.inHours}h ${left.inMinutes % 60}m left for the tenant to pay.'
            : 'Agreement sent — waiting on payment.';
        color = AppColors.ink;
        break;
      case RentalAgreementStatus.paid:
        text = 'Paid — this rental is closed.';
        color = AppColors.success;
        break;
      case RentalAgreementStatus.rejected:
        text = 'Declined.';
        color = AppColors.danger;
        break;
      case RentalAgreementStatus.expired:
        text = 'The payment window expired — the listing reopened to other users.';
        color = AppColors.danger;
        break;
    }
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadii.md)),
      child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color, height: 1.4)),
    );
  }
}

class _DocImage extends StatelessWidget {
  const _DocImage({required this.dataUri});
  final String dataUri;

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeDataUri(dataUri);
    if (bytes == null) {
      return Container(
        height: 140,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: const Text('Could not load image', style: TextStyle(fontSize: 12, color: AppColors.slate)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(bytes, height: 200, width: double.infinity, fit: BoxFit.cover),
    );
  }
}

class _DocThumb extends StatelessWidget {
  const _DocThumb({required this.dataUri});
  final String dataUri;

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeDataUri(dataUri);
    if (bytes == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => Dialog(child: Image.memory(bytes, fit: BoxFit.contain)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(bytes, width: 84, height: 84, fit: BoxFit.cover),
      ),
    );
  }
}

Uint8List? _decodeDataUri(String dataUri) {
  try {
    final commaIndex = dataUri.indexOf(',');
    final b64 = commaIndex >= 0 ? dataUri.substring(commaIndex + 1) : dataUri;
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

class _AgreementDraft {
  final String terms;
  final double rentAmount;
  final double? depositAmount;
  final int hours;
  const _AgreementDraft({required this.terms, required this.rentAmount, this.depositAmount, required this.hours});
}

class _SendAgreementSheet extends StatefulWidget {
  const _SendAgreementSheet({this.assetTitle});
  final String? assetTitle;

  @override
  State<_SendAgreementSheet> createState() => _SendAgreementSheetState();
}

class _SendAgreementSheetState extends State<_SendAgreementSheet> {
  final _termsController = TextEditingController();
  final _rentController = TextEditingController();
  final _depositController = TextEditingController();
  int _hours = 24;
  String? _error;

  @override
  void dispose() {
    _termsController.dispose();
    _rentController.dispose();
    _depositController.dispose();
    super.dispose();
  }

  void _submit() {
    final terms = _termsController.text.trim();
    final rent = double.tryParse(_rentController.text.trim());
    final deposit = _depositController.text.trim().isEmpty ? null : double.tryParse(_depositController.text.trim());
    if (terms.isEmpty) {
      setState(() => _error = 'Add the agreement terms.');
      return;
    }
    if (rent == null || rent <= 0) {
      setState(() => _error = 'Enter a valid rent amount.');
      return;
    }
    Navigator.of(context).pop(_AgreementDraft(terms: terms, rentAmount: rent, depositAmount: deposit, hours: _hours));
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
                  const Expanded(child: Text('Send rental agreement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink))),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('Agreement terms', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 6),
              TextField(
                controller: _termsController,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(hintText: 'e.g. 12-month lease, rent due on the 1st...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _rentController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Rent (ETB)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _depositController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Deposit (optional)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const Text('Payment window', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const Spacer(),
                  DropdownButton<int>(
                    value: _hours,
                    items: const [12, 24, 48].map((h) => DropdownMenuItem(value: h, child: Text('${h}h'))).toList(),
                    onChanged: (v) => setState(() => _hours = v ?? 24),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(label: 'Send agreement', backgroundColor: AppColors.primaryYellow, foregroundColor: Colors.white, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
