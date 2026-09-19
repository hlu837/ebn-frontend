import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/auth_response.dart';
import '../models/owner_bank_account.dart';
import '../models/rental_agreement.dart';
import '../services/rental_agreement_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_buttons.dart';
import 'maintenance_request_form_screen.dart';

const List<String> _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// 'Mon Day, Year' — same convention as the other screens' local
/// _formatDate helpers (see e.g. affiliate_membership_screen.dart).
String _formatDate(DateTime d) {
  final local = d.toLocal();
  return '${_kMonths[local.month - 1]} ${local.day}, ${local.year}';
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

/// The requester's own view of the Review-tab pipeline — "My Rental
/// Agreements": documents under review, an agreement waiting on payment
/// (with a live countdown), or the closed history. Reachable from the
/// visitor Account tab, and landed on straight after submitting
/// documents (see `submit_rental_documents_screen.dart`).
class MyRentalAgreementsScreen extends StatefulWidget {
  const MyRentalAgreementsScreen({super.key, required this.user, this.openAgreementId});

  final AppUser user;

  /// When set, the detail sheet for this agreement opens automatically as
  /// soon as the list has loaded — used by the chat "Open agreement"
  /// button and by tapping a rental-agreement notification, so the tenant
  /// lands straight on the terms instead of hunting for them in the list.
  final String? openAgreementId;

  @override
  State<MyRentalAgreementsScreen> createState() => _MyRentalAgreementsScreenState();
}

class _MyRentalAgreementsScreenState extends State<MyRentalAgreementsScreen> {
  final _service = RentalAgreementService();
  List<RentalAgreement> _rows = const [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  bool _autoOpened = false;

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
      _maybeAutoOpen();
    } on RentalAgreementException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.message;
      });
    }
  }

  /// Opens [MyRentalAgreementsScreen.openAgreementId]'s sheet once, right
  /// after the first successful load. Deferred to a post-frame callback so
  /// the sheet isn't pushed in the middle of a build, and guarded by
  /// [_autoOpened] so the 8s poll never re-opens it after the user closes it.
  void _maybeAutoOpen() {
    final targetId = widget.openAgreementId;
    if (_autoOpened || targetId == null) return;
    _autoOpened = true;
    RentalAgreement? target;
    for (final r in _rows) {
      if (r.id == targetId) {
        target = r;
        break;
      }
    }
    if (target == null) return;
    final row = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openRow(row);
    });
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
                          itemBuilder: (context, i) => _AgreementCard(agreement: _rows[i], onTap: () => _openRow(_rows[i]), user: widget.user),
                        ),
                      ),
      ),
    );
  }
}

class _AgreementCard extends StatelessWidget {
  const _AgreementCard({required this.agreement, required this.onTap, required this.user});

  final RentalAgreement agreement;
  final VoidCallback onTap;
  final AppUser user;

  /// Active lease = paid and not yet vacated. Only then is filing a
  /// maintenance request meaningful — the server re-checks this exact
  /// condition on submit (see maintenanceRequests.create), this just
  /// decides whether to show the button.
  bool get _isActiveLease => agreement.status == RentalAgreementStatus.paid && agreement.vacatedAt == null;

  Color get _statusColor {
    switch (agreement.status) {
      case RentalAgreementStatus.documentsSubmitted:
        return AppColors.slate;
      case RentalAgreementStatus.agreementSent:
      case RentalAgreementStatus.accepted:
      case RentalAgreementStatus.paymentSubmitted:
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                        if ((agreement.status == RentalAgreementStatus.agreementSent ||
                                agreement.status == RentalAgreementStatus.accepted) &&
                            agreement.timeLeft != null)
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
              // Only ever shown on an active lease (paid, not vacated) —
              // this is the sole entry point into filing a maintenance
              // request from this screen. A separate InkWell so tapping
              // it opens the form, not the agreement detail sheet.
              if (_isActiveLease) ...[
                const SizedBox(height: 10),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MaintenanceRequestFormScreen(
                        user: user,
                        assetId: agreement.assetId,
                        assetTitle: agreement.asset?.title ?? 'Property',
                      ),
                    )),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.build_outlined, size: 15, color: AppColors.ink),
                          SizedBox(width: 6),
                          Text(
                            'Report a maintenance issue',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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
        return 'Tap to review the agreement';
      case RentalAgreementStatus.accepted:
        return 'Tap to pay';
      case RentalAgreementStatus.paymentSubmitted:
        return 'Receipt submitted — waiting on the owner to confirm';
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

class _AgreementDetailSheetState extends State<_AgreementDetailSheet> {
  final _rentalService = RentalAgreementService();
  final _picker = ImagePicker();
  late RentalAgreement _agreement;
  bool _accepting = false;
  String? _acceptError;
  bool _readAndAgreed = false;

  List<OwnerBankAccount>? _bankAccounts;
  bool _bankAccountsLoading = false;
  String? _bankAccountsError;

  Uint8List? _receiptBytes;
  String? _receiptDataUri;
  bool _submittingReceipt = false;
  String? _receiptError;

  bool _downloadingDocument = false;

  RentalAgreement get _a => _agreement;

  @override
  void initState() {
    super.initState();
    _agreement = widget.agreement;
    if (_agreement.status == RentalAgreementStatus.accepted ||
        _agreement.status == RentalAgreementStatus.paymentSubmitted) {
      _loadBankAccounts();
    }
  }

  /// The owner's registered accounts to transfer rent into — only fetched
  /// once terms are accepted (the endpoint 409s before that, since
  /// there's nothing to pay against yet).
  Future<void> _loadBankAccounts() async {
    setState(() {
      _bankAccountsLoading = true;
      _bankAccountsError = null;
    });
    try {
      final rows = await _rentalService.fetchBankAccounts(token: widget.user.token ?? '', id: _agreement.id);
      if (!mounted) return;
      setState(() {
        _bankAccounts = rows;
        _bankAccountsLoading = false;
      });
    } on RentalAgreementException catch (e) {
      if (!mounted) return;
      setState(() {
        _bankAccountsLoading = false;
        _bankAccountsError = e.message;
      });
    }
  }

  Future<void> _acceptAgreement() async {
    setState(() {
      _accepting = true;
      _acceptError = null;
    });
    try {
      final row = await _rentalService.acceptAgreement(token: widget.user.token ?? '', id: _agreement.id);
      if (!mounted) return;
      setState(() {
        _agreement = row;
        _accepting = false;
      });
      _loadBankAccounts();
    } on RentalAgreementException catch (e) {
      if (!mounted) return;
      setState(() {
        _accepting = false;
        _acceptError = e.message;
      });
    }
  }

  /// Lets the tenant attach a photo of the bank/cash receipt after
  /// transferring rent — same "no file-storage service" base64 data-URI
  /// convention used everywhere else in this build (see
  /// submit_rental_documents_screen.dart).
  Future<void> _pickReceipt() async {
    setState(() => _receiptError = null);
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final ext = file.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      if (!mounted) return;
      setState(() {
        _receiptBytes = bytes;
        _receiptDataUri = 'data:image/$ext;base64,${base64Encode(bytes)}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _receiptError = 'Could not pick image: $e');
    }
  }

  /// POST /:id/submit-receipt — hands the attached receipt to the owner
  /// for review. Moves this row to 'payment_submitted'; the owner then
  /// either confirms it (closing the deal) or sends it back for a
  /// re-upload (see property_owner_review_detail_screen.dart).
  Future<void> _submitReceipt() async {
    if (_receiptDataUri == null) {
      setState(() => _receiptError = 'Attach a photo of your transfer receipt first.');
      return;
    }
    setState(() {
      _submittingReceipt = true;
      _receiptError = null;
    });
    try {
      final row = await _rentalService.submitReceipt(
        token: widget.user.token ?? '',
        id: _agreement.id,
        receiptUrl: _receiptDataUri!,
      );
      if (!mounted) return;
      setState(() {
        _agreement = row;
        _submittingReceipt = false;
      });
    } on RentalAgreementException catch (e) {
      if (!mounted) return;
      setState(() {
        _submittingReceipt = false;
        _receiptError = e.message;
      });
    }
  }

  /// Opens the signed lease agreement PDF (GET /:id/document) in the
  /// system browser/viewer — the download itself is handled by the OS,
  /// not this app, so all this does is launch the URL. Only reachable
  /// once status is 'paid'.
  Future<void> _downloadDocument() async {
    setState(() => _downloadingDocument = true);
    try {
      final uri = _rentalService.documentDownloadUri(token: widget.user.token ?? '', id: _agreement.id);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the document. Try again from a browser.")),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingDocument = false);
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
        return _paidReceiptBody();
      case RentalAgreementStatus.agreementSent:
        return _reviewTermsBody();
      case RentalAgreementStatus.accepted:
        return _paymentBody();
      case RentalAgreementStatus.paymentSubmitted:
        return _receiptSubmittedBody();
    }
  }

  /// paid: a real receipt instead of a bare confirmation string — the
  /// data (tx ref / paid-by-hand receipt, amount, date, terms) was
  /// already coming back from the API but never made it onto the
  /// screen. Nothing here is generated after the fact; it's all fields
  /// already on the agreement row.
  List<Widget> _paidReceiptBody() {
    final isManual = _a.paymentMethod == 'manual_bank';
    return [
      const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 40),
      const SizedBox(height: 10),
      Text(
        _a.vacatedAt != null ? 'This rental has ended — the listing is open to other users again.' : 'This rental is confirmed and closed.',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
      ),
      const SizedBox(height: AppSpacing.lg),
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Receipt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 10),
            _ReceiptRow(label: 'Property', value: _a.asset?.title ?? '—'),
            _ReceiptRow(label: 'Owner', value: _a.owner?.fullName ?? '—'),
            if (_a.paidAt != null) _ReceiptRow(label: 'Paid on', value: _formatDate(_a.paidAt!)),
            _ReceiptRow(label: 'Rent', value: '${_a.rentAmount?.toStringAsFixed(0) ?? '-'} ${_a.currency}'),
            if (_a.depositAmount != null) _ReceiptRow(label: 'Deposit', value: '${_a.depositAmount!.toStringAsFixed(0)} ${_a.currency}'),
            _ReceiptRow(label: 'Total paid', value: '${_a.totalDue.toStringAsFixed(0)} ${_a.currency}', emphasize: true),
            _ReceiptRow(label: 'Payment method', value: isManual ? 'Bank transfer / cash' : 'Chapa'),
            if (!isManual && _a.paymentTxRef != null) _ReceiptRow(label: 'Reference', value: _a.paymentTxRef!),
            if (_a.leaseEndAt != null) _ReceiptRow(label: 'Lease ends', value: _formatDate(_a.leaseEndAt!)),
            if (_a.agreementTerms?.trim().isNotEmpty == true) ...[
              const Divider(height: 20, color: AppColors.border),
              const Text('Terms', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.slate)),
              const SizedBox(height: 4),
              Text(_a.agreementTerms!, style: const TextStyle(fontSize: 12.5, color: AppColors.ink, height: 1.4)),
            ],
          ],
        ),
      ),
      if (isManual && _a.receiptUrl != null) ...[
        const SizedBox(height: AppSpacing.md),
        const Text('Receipt you were shown', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 8),
        _ReceiptImage(dataUri: _a.receiptUrl!),
      ],
      const SizedBox(height: AppSpacing.lg),
      SecondaryButton(
        label: _downloadingDocument ? 'Opening…' : 'Download lease agreement (PDF)',
        onPressed: _downloadingDocument ? null : _downloadDocument,
      ),
      const SizedBox(height: 6),
      const Text(
        'Print this and bring it to a legal/documentation office if you need it notarized or registered.',
        style: TextStyle(fontSize: 11.5, color: AppColors.slate, height: 1.4),
      ),
    ];
  }

  Widget _termsCard({bool scrollable = false}) {
    final termsText = Text(_a.agreementTerms ?? '', style: const TextStyle(fontSize: 13, color: AppColors.ink, height: 1.5));
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (scrollable)
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              padding: const EdgeInsets.only(right: 4),
              child: Scrollbar(child: SingleChildScrollView(child: termsText)),
            )
          else
            termsText,
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
    );
  }

  /// agreement_sent: the terms are shown for the first time — the
  /// requester must explicitly accept them before a Pay button ever
  /// appears. This is the acceptance step itself; paying is no longer
  /// the only signal that they agreed to what's shown here.
  List<Widget> _reviewTermsBody() {
    final left = _a.timeLeft;
    return [
      if (left != null && left > Duration.zero) _CountdownText(expiresAt: _a.expiresAt!),
      const SizedBox(height: AppSpacing.sm),
      const Text(
        'This is the standard rental agreement for this property. Read it in full before accepting — accepting is the same as signing a Terms & Conditions screen.',
        style: TextStyle(fontSize: 12.5, color: AppColors.slate, height: 1.4),
      ),
      const SizedBox(height: AppSpacing.sm),
      _termsCard(scrollable: true),
      const SizedBox(height: AppSpacing.md),
      InkWell(
        onTap: _accepting ? null : () => setState(() => _readAndAgreed = !_readAndAgreed),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _readAndAgreed,
                onChanged: _accepting ? null : (v) => setState(() => _readAndAgreed = v ?? false),
                activeColor: AppColors.primaryYellow,
              ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'I have read and agree to the rental agreement above.',
                    style: TextStyle(fontSize: 13, color: AppColors.ink, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      if (_acceptError != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(_acceptError!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
      ],
      const SizedBox(height: AppSpacing.lg),
      PrimaryButton(
        label: 'Accept these terms',
        backgroundColor: AppColors.primaryYellow,
        foregroundColor: Colors.white,
        isLoading: _accepting,
        onPressed: (_accepting || !_readAndAgreed) ? null : _acceptAgreement,
      ),
    ];
  }

  /// accepted: terms are locked in, the requester's only action left is
  /// paying by bank transfer, then uploading proof of that transfer.
  List<Widget> _paymentBody() {
    final left = _a.timeLeft;
    return [
      if (left != null && left > Duration.zero) _CountdownText(expiresAt: _a.expiresAt!),
      if (_a.receiptRejectedReason?.trim().isNotEmpty == true) ...[
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Your last receipt couldn't be confirmed: ${_a.receiptRejectedReason}. Please upload a new one.",
                  style: const TextStyle(fontSize: 12.5, color: AppColors.danger, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: AppSpacing.sm),
      _termsCard(),
      const SizedBox(height: AppSpacing.lg),
      ..._bankTransferSection(),
      const SizedBox(height: AppSpacing.lg),
      ..._receiptUploadSection(),
    ];
  }

  /// The upload-a-receipt half of the payment step — attach a photo of
  /// the transfer/cash receipt and hand it to the owner for review (see
  /// _submitReceipt). Replaces the old "message the owner in chat"
  /// instruction with an actual in-app confirmation loop.
  List<Widget> _receiptUploadSection() {
    return [
      const Text('Upload your receipt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
      const SizedBox(height: 6),
      const Text(
        'Once you\'ve transferred the total due, attach a photo of the receipt or transfer screenshot here. The owner will review it and confirm — you\'ll be notified either way.',
        style: TextStyle(fontSize: 12, color: AppColors.slate, height: 1.4),
      ),
      const SizedBox(height: AppSpacing.sm),
      if (_receiptBytes != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(_receiptBytes!, height: 160, width: double.infinity, fit: BoxFit.cover),
        )
      else
        Container(
          height: 120,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: const Text('No receipt selected', style: TextStyle(fontSize: 12.5, color: AppColors.slate)),
        ),
      const SizedBox(height: AppSpacing.sm),
      SecondaryButton(label: _receiptBytes == null ? 'Attach receipt' : 'Change receipt', onPressed: _pickReceipt),
      if (_receiptError != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(_receiptError!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
      ],
      const SizedBox(height: AppSpacing.md),
      PrimaryButton(
        label: 'Submit receipt for review',
        backgroundColor: AppColors.primaryYellow,
        foregroundColor: Colors.white,
        isLoading: _submittingReceipt,
        onPressed: (_submittingReceipt || _receiptDataUri == null) ? null : _submitReceipt,
      ),
    ];
  }

  /// payment_submitted: the tenant already uploaded a receipt — nothing
  /// left to do but wait on the owner's confirm/reject-receipt decision.
  List<Widget> _receiptSubmittedBody() {
    return [
      const Icon(Icons.hourglass_top_rounded, color: AppColors.primaryYellow, size: 36),
      const SizedBox(height: 10),
      const Text(
        'Receipt submitted — waiting on the owner to confirm your payment.',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
      ),
      if (_a.receiptSubmittedAt != null) ...[
        const SizedBox(height: 4),
        Text('Submitted on ${_formatDate(_a.receiptSubmittedAt!)}', style: const TextStyle(fontSize: 12.5, color: AppColors.slate)),
      ],
      const SizedBox(height: AppSpacing.lg),
      if (_a.receiptUrl != null) ...[
        const Text('What you submitted', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 8),
        _ReceiptImage(dataUri: _a.receiptUrl!),
        const SizedBox(height: AppSpacing.md),
      ],
      _termsCard(),
    ];
  }

  /// The owner's bank accounts — the tenant reads the account number
  /// here and transfers from their own banking app, then uses
  /// [_receiptUploadSection] below to hand over proof of that transfer.
  List<Widget> _bankTransferSection() {
    if (_bankAccountsLoading) {
      return const [Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: CircularProgressIndicator(strokeWidth: 2.4)))];
    }
    if (_bankAccountsError != null) {
      return [
        Text(_bankAccountsError!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
        const SizedBox(height: AppSpacing.sm),
      ];
    }
    final accounts = _bankAccounts ?? const [];
    if (accounts.isEmpty) {
      return const [
        Text(
          "The owner hasn't added a bank account to receive payment yet — check back soon or follow up in chat.",
          style: TextStyle(fontSize: 12.5, color: AppColors.slate, height: 1.4),
        ),
      ];
    }
    return [
      const Text('Pay by bank transfer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
      const SizedBox(height: 6),
      const Text(
        'Transfer the total due from your banking app to one of these accounts, then upload the receipt below.',
        style: TextStyle(fontSize: 12, color: AppColors.slate, height: 1.4),
      ),
      const SizedBox(height: AppSpacing.sm),
      ...accounts.map((a) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _BankAccountCard(account: a))),
    ];
  }
}

/// One of the owner's bank accounts, shown on the payment screen — bank
/// name, the name the account is under, and the number, with a one-tap
/// copy for the number since that's the field the tenant actually needs
/// to paste into their banking app.
class _BankAccountCard extends StatelessWidget {
  const _BankAccountCard({required this.account});
  final OwnerBankAccount account;

  void _copyNumber(BuildContext context) {
    Clipboard.setData(ClipboardData(text: account.accountNumber));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account number copied'), duration: Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: account.isDefault ? AppColors.primaryYellow : AppColors.border, width: account.isDefault ? 1.4 : 1),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: AppColors.primaryYellow.withValues(alpha: 0.1), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.account_balance_rounded, size: 18, color: AppColors.primaryYellow),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.bankShortCode?.isNotEmpty == true ? '${account.bankShortCode} — ${account.accountName}' : '${account.bankName} — ${account.accountName}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(account.accountNumber, style: const TextStyle(fontSize: 13, color: AppColors.slate, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _copyNumber(context),
            icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.slate),
            tooltip: 'Copy account number',
          ),
        ],
      ),
    );
  }
}

/// One label/value line in the paid receipt card.
class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value, this.emphasize = false});
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.slate)),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: emphasize ? 15 : 13.5,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders the owner's manual-payment receipt image back to the tenant —
/// previously only visible on the owner's side (see
/// property_owner_review_detail_screen.dart's _DocImage).
class _ReceiptImage extends StatelessWidget {
  const _ReceiptImage({required this.dataUri});
  final String dataUri;

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeDataUri(dataUri);
    if (bytes == null) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: const Text('Could not load image', style: TextStyle(fontSize: 12, color: AppColors.slate)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(bytes, height: 180, width: double.infinity, fit: BoxFit.cover),
    );
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
