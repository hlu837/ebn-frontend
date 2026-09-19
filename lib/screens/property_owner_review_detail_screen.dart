import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/auth_response.dart';
import '../models/rental_agreement.dart';
import '../services/rental_agreement_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_buttons.dart';

const List<String> _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// 'Mon Day, Year' — same convention as other screens' local _formatDate
/// helpers (see e.g. affiliate_membership_screen.dart).
String _formatDate(DateTime d) {
  final local = d.toLocal();
  return '${_kMonths[local.month - 1]} ${local.day}, ${local.year}';
}

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
    required int advanceMonths,
    double? depositAmount,
    required int hours,
    int? termMonths,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final row = await _service.sendAgreement(
        token: _token,
        id: _agreement.id,
        advanceMonths: advanceMonths,
        depositAmount: depositAmount,
        hours: hours,
        termMonths: termMonths,
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

  /// Owner confirms a bank transfer / cash payment — the only way a
  /// rental payment closes now that Chapa isn't offered on this flow.
  Future<void> _markPaidManually() async {
    final receiptUri = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ManualPaymentSheet(),
    );
    if (receiptUri == null) return; // cancelled
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final row = await _service.markPaidManually(token: _token, id: _agreement.id, receiptUrl: receiptUri);
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

  /// Owner confirms the tenant actually moved out — the only thing that
  /// reopens the listing after a lease. Explicit action, never automatic
  /// (see rentalAgreements.markVacated on the backend for why).
  Future<void> _markVacated() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark this rental vacated?'),
        content: const Text('This reopens the listing so other users can request it again. Only do this once the tenant has actually moved out.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Mark vacated')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final row = await _service.vacate(token: _token, id: _agreement.id);
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

  /// Owner confirms the tenant's own submitted receipt (payment_submitted
  /// -> paid) — the tenant-driven counterpart to _markPaidManually.
  Future<void> _confirmReceipt() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final row = await _service.confirmReceipt(token: _token, id: _agreement.id);
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

  /// Owner sends a submitted receipt back for a re-upload — drops the
  /// row back to 'accepted' with a fresh payment window rather than
  /// killing the deal outright (use Decline / _reject for that).
  Future<void> _rejectReceipt() async {
    final reason = await _promptReceiptRejectReason();
    if (reason == null) return; // cancelled
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final row = await _service.rejectReceipt(token: _token, id: _agreement.id, reason: reason.isEmpty ? null : reason);
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

  Future<String?> _promptReceiptRejectReason() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Couldn't confirm this receipt?"),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: "What's wrong with it? (shown to the tenant, optional)",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Ask to re-upload'),
          ),
        ],
      ),
    );
  }

  /// Opens the signed lease agreement PDF (GET /:id/document) — the
  /// owner's own copy of the same document the tenant gets.
  Future<void> _downloadDocument() async {
    setState(() => _busy = true);
    try {
      final uri = _service.documentDownloadUri(token: _token, id: _agreement.id);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the document. Try again from a browser.")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
            if (_agreement.faydaIdNumber?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text('Fayda ID: ${_agreement.faydaIdNumber}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
            ],
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
            if (_agreement.status == RentalAgreementStatus.paymentSubmitted && _agreement.receiptUrl != null) ...[
              const SizedBox(height: AppSpacing.lg),
              const Text('Receipt the tenant submitted', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 8),
              _DocImage(dataUri: _agreement.receiptUrl!),
            ],
            if (_agreement.status == RentalAgreementStatus.paid && _agreement.receiptUrl != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                _agreement.receiptSubmittedAt != null ? 'Receipt the tenant uploaded' : 'Receipt you attached',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              const SizedBox(height: 8),
              _DocImage(dataUri: _agreement.receiptUrl!),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
            ],
            const SizedBox(height: AppSpacing.xl),
            if (_agreement.status == RentalAgreementStatus.documentsSubmitted) ..._decisionButtons(),
            if (_agreement.status == RentalAgreementStatus.accepted) ..._manualPaymentButton(),
            if (_agreement.status == RentalAgreementStatus.paymentSubmitted) ..._receiptDecisionButtons(),
            if (_agreement.status == RentalAgreementStatus.paid) ..._downloadDocumentButton(),
            if (_agreement.status == RentalAgreementStatus.paid && _agreement.vacatedAt == null) ..._vacateButton(),
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
            builder: (_) => _SendAgreementSheet(
              monthlyRent: _agreement.asset?.priceAmount,
              currency: _agreement.asset?.priceCurrency ?? _agreement.currency,
            ),
          );
          if (sent != null) {
            await _sendAgreement(advanceMonths: sent.advanceMonths, depositAmount: sent.depositAmount, hours: sent.hours, termMonths: sent.termMonths);
          }
        },
      ),
      const SizedBox(height: AppSpacing.sm),
      SecondaryButton(label: 'Decline', onPressed: _reject, textColor: AppColors.danger, borderColor: AppColors.danger),
    ];
  }

  /// Shown once the requester has accepted the terms and payment is the
  /// only thing left — the tenant pays by bank transfer, and the owner
  /// confirms it here once the money is in hand. Not shown while still
  /// 'agreement_sent': the backend requires 'accepted' before a payment
  /// can close the deal.
  List<Widget> _manualPaymentButton() {
    if (_busy) {
      return const [PrimaryButton(label: 'Please wait…', isLoading: true, onPressed: null)];
    }
    return [
      SecondaryButton(label: 'Mark as paid (bank transfer / cash)', onPressed: _markPaidManually),
    ];
  }

  /// Shown on a 'payment_submitted' row — the tenant already uploaded a
  /// receipt (rendered above via _DocImage), and the owner just decides
  /// whether it checks out.
  List<Widget> _receiptDecisionButtons() {
    if (_busy) {
      return const [PrimaryButton(label: 'Please wait…', isLoading: true, onPressed: null)];
    }
    return [
      PrimaryButton(
        label: 'Confirm payment',
        backgroundColor: AppColors.success,
        foregroundColor: Colors.white,
        onPressed: _confirmReceipt,
      ),
      const SizedBox(height: AppSpacing.sm),
      SecondaryButton(label: "Ask tenant to re-upload", onPressed: _rejectReceipt),
    ];
  }

  /// Shown on a 'paid' row — the owner's own copy of the signed lease
  /// document, same file the tenant can download.
  List<Widget> _downloadDocumentButton() {
    return [
      SecondaryButton(label: 'Download lease agreement (PDF)', onPressed: _busy ? null : _downloadDocument),
      const SizedBox(height: AppSpacing.sm),
    ];
  }

  /// Shown on a 'paid' row that hasn't been marked vacated yet — the
  /// explicit action that reopens the listing once the tenant actually
  /// moves out (lease ending on paper isn't enough on its own).
  List<Widget> _vacateButton() {
    if (_busy) {
      return const [PrimaryButton(label: 'Please wait…', isLoading: true, onPressed: null)];
    }
    return [
      const SizedBox(height: AppSpacing.sm),
      SecondaryButton(label: 'Mark vacated — reopen listing', onPressed: _markVacated),
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
            ? 'Agreement sent — ${left.inHours}h ${left.inMinutes % 60}m left for the tenant to accept and pay.'
            : 'Agreement sent — waiting on the tenant to accept.';
        color = AppColors.ink;
        break;
      case RentalAgreementStatus.accepted:
        final left = agreement.timeLeft;
        text = left != null && left > Duration.zero
            ? 'Terms accepted — ${left.inHours}h ${left.inMinutes % 60}m left for the tenant to pay.'
            : 'Terms accepted — waiting on payment.';
        color = AppColors.ink;
        break;
      case RentalAgreementStatus.paymentSubmitted:
        text = 'The tenant submitted a payment receipt — review it below.';
        color = AppColors.primaryYellow;
        break;
      case RentalAgreementStatus.paid:
        if (agreement.vacatedAt != null) {
          text = 'Vacated — this listing has reopened to other users.';
          color = AppColors.slate;
        } else if (agreement.leaseEndAt != null) {
          text = 'Paid — this rental is closed. Lease ends ${_formatDate(agreement.leaseEndAt!)}.';
          color = AppColors.success;
        } else {
          text = 'Paid — this rental is closed.';
          color = AppColors.success;
        }
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

/// Bottom sheet for confirming a manual (bank transfer / cash) payment.
/// Pops the picked receipt as a base64 data URI — same "no file-storage
/// service" convention as submit_rental_documents_screen.dart — or null
/// if the owner cancels.
class _ManualPaymentSheet extends StatefulWidget {
  const _ManualPaymentSheet();

  @override
  State<_ManualPaymentSheet> createState() => _ManualPaymentSheetState();
}

class _ManualPaymentSheetState extends State<_ManualPaymentSheet> {
  final _picker = ImagePicker();
  Uint8List? _receiptBytes;
  String? _receiptDataUri;
  String? _error;
  bool _picking = false;

  Future<void> _pickReceipt() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
      if (file == null) {
        setState(() => _picking = false);
        return;
      }
      final bytes = await file.readAsBytes();
      final ext = file.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      setState(() {
        _receiptBytes = bytes;
        _receiptDataUri = 'data:image/$ext;base64,${base64Encode(bytes)}';
        _picking = false;
      });
    } catch (e) {
      setState(() {
        _picking = false;
        _error = 'Could not pick image: $e';
      });
    }
  }

  void _submit() {
    if (_receiptDataUri == null) {
      setState(() => _error = 'Attach a receipt or screenshot of the transfer first.');
      return;
    }
    Navigator.of(context).pop(_receiptDataUri);
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
                  const Expanded(child: Text('Confirm bank/cash payment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink))),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Attach a photo of the receipt or transfer screenshot. This closes the deal immediately — only do this once the money is actually in hand.',
                style: TextStyle(fontSize: 12.5, color: AppColors.slate, height: 1.4),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_receiptBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_receiptBytes!, height: 180, width: double.infinity, fit: BoxFit.cover),
                )
              else
                Container(
                  height: 120,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                  child: const Text('No receipt selected', style: TextStyle(fontSize: 12.5, color: AppColors.slate)),
                ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: _receiptBytes == null ? 'Attach receipt' : 'Change receipt',
                onPressed: _picking ? null : _pickReceipt,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(label: 'Confirm paid', backgroundColor: AppColors.success, foregroundColor: Colors.white, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgreementDraft {
  final int advanceMonths;
  final double? depositAmount;
  final int hours;
  final int? termMonths;
  const _AgreementDraft({required this.advanceMonths, this.depositAmount, required this.hours, this.termMonths});
}

class _SendAgreementSheet extends StatefulWidget {
  const _SendAgreementSheet({this.assetTitle, this.monthlyRent, this.currency = 'ETB'});
  final String? assetTitle;
  /// The listing's own advertised monthly rent — what advance months get
  /// multiplied against. If this is somehow null (a listing with no
  /// price set), the sheet blocks sending instead of guessing a figure.
  final double? monthlyRent;
  final String currency;

  @override
  State<_SendAgreementSheet> createState() => _SendAgreementSheetState();
}

class _SendAgreementSheetState extends State<_SendAgreementSheet> {
  final _depositController = TextEditingController();
  final _termMonthsController = TextEditingController();
  int _advanceMonths = 3;
  int _hours = 24;
  String? _error;

  /// Advance months x the listing's monthly price — null when the
  /// listing has no valid price to compute from at all.
  double? get _totalDue =>
      widget.monthlyRent != null && widget.monthlyRent! > 0 ? widget.monthlyRent! * _advanceMonths : null;

  @override
  void dispose() {
    _depositController.dispose();
    _termMonthsController.dispose();
    super.dispose();
  }

  void _submit() {
    final deposit = _depositController.text.trim().isEmpty ? null : double.tryParse(_depositController.text.trim());
    final termMonthsText = _termMonthsController.text.trim();
    if (widget.monthlyRent == null || widget.monthlyRent! <= 0) {
      setState(() => _error = "This listing doesn't have a monthly price set — fix the listing first.");
      return;
    }
    if (_advanceMonths <= 0) {
      setState(() => _error = 'Pick at least 1 month of advance payment.');
      return;
    }
    int? termMonths;
    if (termMonthsText.isNotEmpty) {
      termMonths = int.tryParse(termMonthsText);
      if (termMonths == null || termMonths <= 0) {
        setState(() => _error = 'Lease term must be a whole number of months, or left blank for month-to-month.');
        return;
      }
    }
    Navigator.of(context)
        .pop(_AgreementDraft(advanceMonths: _advanceMonths, depositAmount: deposit, hours: _hours, termMonths: termMonths));
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
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primaryYellow.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.description_outlined, size: 18, color: AppColors.primaryYellow),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A standard rental agreement is generated automatically from the details below — the tenant will read it and accept it before paying, the same way you accept Terms & Conditions.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.ink.withOpacity(0.85), height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Advance payment (months of rent)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                decoration: BoxDecoration(border: Border.all(color: AppColors.slate.withOpacity(0.3)), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _advanceMonths > 1 ? () => setState(() => _advanceMonths -= 1) : null,
                    ),
                    Expanded(
                      child: Text(
                        '$_advanceMonths month${_advanceMonths == 1 ? '' : 's'}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _advanceMonths < 36 ? () => setState(() => _advanceMonths += 1) : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (widget.monthlyRent != null && widget.monthlyRent! > 0)
                Text(
                  'Total due now: ${_totalDue!.toStringAsFixed(0)} ${widget.currency}  '
                  '($_advanceMonths × ${widget.monthlyRent!.toStringAsFixed(0)} ${widget.currency}/mo — the listing\'s own price)',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.slate),
                )
              else
                const Text(
                  "This listing has no monthly price set, so a total can't be computed — fix the listing's price first.",
                  style: TextStyle(fontSize: 12.5, color: AppColors.danger, fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _depositController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Security deposit (optional, ${widget.currency})', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Lease term (months)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 6),
              TextField(
                controller: _termMonthsController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'e.g. 12 — leave blank for month-to-month',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
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
