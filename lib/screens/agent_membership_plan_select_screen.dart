import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/auth_response.dart';
import '../models/user_role.dart';
import '../models/role_upgrade_request.dart';
import '../services/agent_service.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../services/role_upgrade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_buttons.dart';
import 'agent_home_screen.dart';
import 'verification_pending_screen.dart';

/// Representation of an Agent Membership Plan matching the official tier poster.
class AgentMembershipPlan {
  final int stepNumber;
  final String title;
  final double priceEtb;
  final String description;
  final List<String> benefits;
  final String footerNote;
  final Color primaryColor;
  final Color headerBgColor;
  final String tierKey;

  const AgentMembershipPlan({
    required this.stepNumber,
    required this.title,
    required this.priceEtb,
    required this.description,
    required this.benefits,
    required this.footerNote,
    required this.primaryColor,
    required this.headerBgColor,
    required this.tierKey,
  });

  String get formattedPrice {
    final s = priceEtb.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final posFromEnd = s.length - i;
      buffer.write(s[i]);
      if (posFromEnd > 1 && posFromEnd % 3 == 1) buffer.write(',');
    }
    return '${buffer.toString()} ETB';
  }
}

const kAgentMembershipPlans = <AgentMembershipPlan>[
  AgentMembershipPlan(
    stepNumber: 1,
    title: 'BASIC STARTER\nMEMBERSHIP',
    priceEtb: 10,
    description:
        'Perfect for beginners and new brokers ready to enter the marketplace.',
    benefits: [
      'Basic Broker Training',
      'Access to AEBNG Community',
      'Personal Promotion Support',
      'Marketplace Introduction',
      'Digital Marketing Basics',
      'Networking Opportunities',
      'Beginner Sales Education',
    ],
    footerNote:
        'Start your broker journey with professional support and technology.',
    primaryColor: AppColors.primaryYellow,
    headerBgColor: Color(0xFFFFF1F1),
    tierKey: 'bronze',
  ),
  AgentMembershipPlan(
    stepNumber: 2,
    title: 'PROFESSIONAL NETWORK\nMEMBERSHIP',
    priceEtb: 20,
    description:
        'Designed for active brokers and marketers who want bigger connections and more business opportunities.',
    benefits: [
      'Advanced Networking Access',
      'Bigger Marketplace Exposure',
      'Lead Generation Support',
      'Team Collaboration Opportunities',
      'Business Branding Assistance',
      'Property & Product Promotion',
      'Marketing Tools & Strategy',
    ],
    footerNote: 'Build strong business relationships across Ethiopia.',
    primaryColor: AppColors.ink,
    headerBgColor: Color(0xFFF3F1ED),
    tierKey: 'silver',
  ),
  AgentMembershipPlan(
    stepNumber: 3,
    title: 'ELITE BUSINESS STRATEGY\nMEMBERSHIP',
    priceEtb: 30,
    description:
        'For serious entrepreneurs and high-level brokers ready to scale faster.',
    benefits: [
      'Premium Business Strategy',
      'High-Level Networking',
      'Investment Connections',
      'Priority Marketplace Position',
      'Large Deal Opportunities',
      'Advanced Technology Access',
      'Leadership & Growth Training',
      'National Business Expansion Support',
    ],
    footerNote: 'Grow from broker to business leader.',
    primaryColor: AppColors.primaryYellowDark,
    headerBgColor: Color(0xFFFBEAE4),
    tierKey: 'gold',
  ),
];

/// Screen displayed after an Agent enters their signup info.
/// They must pick an Agent Membership Plan and complete payment before
/// activating their account and entering the Agent Workspace.
class AgentMembershipPlanSelectScreen extends StatefulWidget {
  const AgentMembershipPlanSelectScreen({super.key, required this.user, this.pendingUserPayload});

  final AppUser user;
  final Map<String, dynamic>? pendingUserPayload;

  @override
  State<AgentMembershipPlanSelectScreen> createState() =>
      _AgentMembershipPlanSelectScreenState();
}

class _AgentMembershipPlanSelectScreenState
    extends State<AgentMembershipPlanSelectScreen> {
  int _selectedIndex = 1; // Default to Professional plan
  final bool _isProcessing = false;
  final _agentService = AgentService();

  AgentMembershipPlan get _selectedPlan =>
      kAgentMembershipPlans[_selectedIndex];

  Future<void> _handlePaymentAndActivate() async {
    final result = await _showPaymentModal(_selectedPlan);
    if (result == null || !mounted) return;

    if (result is AppUser || result == true) {
      final updatedUser = result is AppUser
          ? result
          : widget.user.copyWith(role: UserRole.agent, accountStatus: 'active');
      await _showActivationSuccessDialog(_selectedPlan);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => AgentHomeScreen(user: updatedUser)),
        (route) => false,
      );
      return;
    }

    if (result is RoleUpgradeRequest) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => VerificationPendingScreen(
            user: widget.user,
            targetRole: UserRole.agent,
            pendingRequest: result,
          ),
        ),
        (route) => false,
      );
    }
  }

  Future<dynamic> _showPaymentModal(AgentMembershipPlan plan) {
    return showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cloud,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _AgentPaymentSheet(plan: plan, user: widget.user, pendingUserPayload: widget.pendingUserPayload),
    );
  }

  Future<void> _showActivationSuccessDialog(AgentMembershipPlan plan) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        icon: Container(
          width: 60,
          height: 60,
          decoration:
              BoxDecoration(color: plan.primaryColor, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: const Icon(Icons.workspace_premium_rounded,
              color: Colors.white, size: 34),
        ),
        title: const Text(
          'Membership Activated! 🎉',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Text(
          'Welcome to the EBN Agent Network! Your ${plan.title.replaceAll('\n', ' ')} is active. '
          'You now have full access to marketplace leads, tools, and broker network features.',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppColors.slate, fontSize: 13.5, height: 1.4),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: plan.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl, vertical: AppSpacing.md),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button)),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Enter Agent Workspace',
                style: TextStyle(fontWeight: FontWeight.w800)),
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
        elevation: 0,
        title: const Text(
          'Agent Membership Plans',
          style: TextStyle(
              fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
              child: Column(
                children: [
                  Text(
                    'Choose Your Broker Path',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Select a membership plan to complete your registration and activate your broker profile.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.slate, height: 1.3),
                  ),
                ],
              ),
            ),

            Expanded(
              child: PageView.builder(
                controller: PageController(
                    viewportFraction: 0.88, initialPage: _selectedIndex),
                onPageChanged: (i) => setState(() => _selectedIndex = i),
                itemCount: kAgentMembershipPlans.length,
                itemBuilder: (context, index) {
                  final plan = kAgentMembershipPlans[index];
                  final isSelected = index == _selectedIndex;
                  return _AgentPlanCard(
                    plan: plan,
                    isSelected: isSelected,
                    onTap: () => setState(() => _selectedIndex = index),
                  );
                },
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Indicator dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                kAgentMembershipPlans.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _selectedIndex == i ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _selectedIndex == i
                        ? kAgentMembershipPlans[i].primaryColor
                        : AppColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Bottom Payment Action Bar
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: const BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, -2))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedPlan.title.replaceAll('\n', ' '),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _selectedPlan.primaryColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedPlan.formattedPrice,
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: AppColors.ink),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _selectedPlan.headerBgColor,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          border: Border.all(
                              color:
                                  _selectedPlan.primaryColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          'Step ${_selectedPlan.stepNumber} of 3',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: _selectedPlan.primaryColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(
                    label: 'Pay ${_selectedPlan.formattedPrice} & Activate',
                    isLoading: _isProcessing,
                    backgroundColor: _selectedPlan.primaryColor,
                    onPressed: _handlePaymentAndActivate,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentPlanCard extends StatelessWidget {
  const _AgentPlanCard({
    required this.plan,
    required this.isSelected,
    required this.onTap,
  });

  final AgentMembershipPlan plan;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? plan.primaryColor : AppColors.border,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: plan.primaryColor.withOpacity(0.2),
                      blurRadius: 12,
                      spreadRadius: 1)
                ]
              : [const BoxShadow(color: Colors.black12, blurRadius: 6)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            children: [
              // Card Top Header Banner
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: plan.primaryColor,
                  border: Border(
                      bottom: BorderSide(color: plan.primaryColor, width: 2)),
                ),
                child: Column(
                  children: [
                    // Step Circle Badge
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text(
                        '${plan.stepNumber}',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: plan.primaryColor),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      plan.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Price Pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        plan.formattedPrice,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: plan.primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Description Subtitle
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Text(
                  plan.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    height: 1.3,
                  ),
                ),
              ),

              // BENEFITS Title Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                color: plan.primaryColor,
                child: const Text(
                  'BENEFITS:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ),

              // Benefits Checklist
              Expanded(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    children: [
                      for (final b in plan.benefits) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check,
                                size: 16, color: plan.primaryColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                b,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
              ),

              // Card Bottom Footer Note
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: plan.primaryColor,
                child: Text(
                  plan.footerNote,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Payment Method Selector ──────────────────────────────────────────────────

class _AgentPaymentSheet extends StatefulWidget {
  const _AgentPaymentSheet({required this.plan, required this.user, this.pendingUserPayload});

  final AgentMembershipPlan plan;
  final AppUser user;
  final Map<String, dynamic>? pendingUserPayload;

  @override
  State<_AgentPaymentSheet> createState() => _AgentPaymentSheetState();
}

enum _PayMethod { chapa, bank }

class _AgentPaymentSheetState extends State<_AgentPaymentSheet> {
  _PayMethod _method = _PayMethod.chapa;

  // ── Chapa state ──────────────────────────────────────────────────────
  bool _chapaLoading = false;
  bool _chapaPolling = false;
  String? _chapaTxRef;
  String? _chapaError;
  Timer? _pollTimer;

  // ── Bank-transfer state ──────────────────────────────────────────────
  final _refCtrl = TextEditingController();
  final _picker = ImagePicker();
  XFile? _receiptFile;
  bool _bankSubmitting = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _refCtrl.dispose();
    super.dispose();
  }

  // ── Chapa flow ───────────────────────────────────────────────────────

  Future<void> _launchChapa() async {
    setState(() {
      _chapaLoading = true;
      _chapaError = null;
    });
    try {
      String email = widget.user.email;
      if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
        email = 'user_${widget.user.id.isNotEmpty ? widget.user.id.substring(0, 8) : DateTime.now().millisecondsSinceEpoch}@gmail.com';
      }

      final checkout = await PaymentService().initialize(
        purpose: 'agent_signup_${widget.plan.tierKey}',
        amount: widget.plan.priceEtb,
        email: email,
        ownerUserId: widget.user.id.isNotEmpty ? widget.user.id : null,
        firstName: widget.user.fullName.split(' ').first,
        lastName: widget.user.fullName.split(' ').skip(1).join(' '),
        description:
            '${widget.plan.title.replaceAll('\n', ' ')} - ${widget.plan.formattedPrice}',
        pendingUserPayload: widget.pendingUserPayload,
      );

      setState(() {
        _chapaTxRef = checkout.txRef;
        _chapaLoading = false;
        _chapaPolling = true;
      });

      // Open Chapa hosted checkout in the system browser
      final uri = Uri.parse(checkout.checkoutUrl);
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      // Poll every 3 s until the payment settles
      _pollTimer =
          Timer.periodic(const Duration(seconds: 3), (_) => _pollVerify());
    } on PaymentException catch (e) {
      if (!mounted) return;
      setState(() {
        _chapaLoading = false;
        _chapaError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chapaLoading = false;
        _chapaError = e.toString();
      });
    }
  }

  Future<void> _pollVerify() async {
    final txRef = _chapaTxRef;
    if (txRef == null || !mounted) return;
    try {
      final status = await PaymentService().verify(txRef);
      if (!mounted) return;
      if (status == PaymentStatus.success) {
        _pollTimer?.cancel();
        try {
          final updatedUser = await AuthService().me(widget.user.token ?? '');
          if (!mounted) return;
          Navigator.of(context).pop(updatedUser);
        } catch (_) {
          if (!mounted) return;
          Navigator.of(context).pop(true);
        }
      } else if (status == PaymentStatus.failed) {
        _pollTimer?.cancel();
        setState(() {
          _chapaPolling = false;
          _chapaError = 'Payment was declined or cancelled. Please try again.';
        });
      }
      // pending → keep polling
    } on PaymentException {
      // Transient error — next tick retries
    }
  }

  // ── Bank-transfer flow ────────────────────────────────────────────────

  Future<void> _pickReceipt() async {
    try {
      final img = await _picker.pickImage(source: ImageSource.gallery);
      if (img != null) setState(() => _receiptFile = img);
    } catch (_) {
      setState(() => _receiptFile = XFile(
          'simulated_receipt_${DateTime.now().millisecondsSinceEpoch}.png'));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Simulated receipt image for platform compatibility.')),
      );
    }
  }

  Future<void> _confirmBank() async {
    final ref = _refCtrl.text.trim();
    if (ref.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter the transaction reference number.')));
      return;
    }
    if (_receiptFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please upload a copy of your payment receipt.')));
      return;
    }
    setState(() => _bankSubmitting = true);
    try {
      final message =
          'Manual Bank Transfer for ${widget.plan.title.replaceAll('\n', ' ')} (${widget.plan.formattedPrice}). Reference: #$ref. File: ${_receiptFile!.name}';
      final req = await RoleUpgradeService().submitRequest(
        requestedRole: UserRole.agent,
        message: message,
        agencyOrLicense: widget.user.agencyOrLicense ?? 'Verified Broker',
        token: widget.user.token ?? '',
      );
      if (!mounted) return;
      Navigator.of(context).pop(req);
    } catch (e) {
      if (mounted) {
        setState(() => _bankSubmitting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final planColor = widget.plan.primaryColor;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),

            // Title
            Text(
              'Complete Payment',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.xs),

            // Plan summary pill
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: widget.plan.headerBgColor,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: planColor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.plan.title.replaceAll('\n', ' '),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: planColor),
                      ),
                      const SizedBox(height: 2),
                      Text('Billed to: ${widget.user.fullName}',
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.slate)),
                    ],
                  ),
                  Text(widget.plan.formattedPrice,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: planColor)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Method toggle ──────────────────────────────────────────
            const Text('Choose payment method',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink)),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                    child: _MethodTab(
                  label: 'Pay with Chapa',
                  icon: Icons.bolt_rounded,
                  selected: _method == _PayMethod.chapa,
                  color: const Color(0xFF1DBF73),
                  onTap: () => setState(() => _method = _PayMethod.chapa),
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: _MethodTab(
                  label: 'Bank Transfer',
                  icon: Icons.account_balance_rounded,
                  selected: _method == _PayMethod.bank,
                  color: planColor,
                  onTap: () => setState(() => _method = _PayMethod.bank),
                )),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Method content ─────────────────────────────────────────
            if (_method == _PayMethod.chapa)
              _buildChapaSection(planColor)
            else
              _buildBankSection(planColor),
          ],
        ),
      ),
    );
  }

  Widget _buildChapaSection(Color planColor) {
    if (_chapaPolling) {
      return Column(
        children: [
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: const Color(0xFFE8FBF1),
              borderRadius: BorderRadius.circular(AppRadii.md),
              border:
                  Border.all(color: const Color(0xFF1DBF73).withOpacity(0.4)),
            ),
            child: Column(
              children: [
                const CircularProgressIndicator(color: Color(0xFF1DBF73)),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Waiting for payment confirmation…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.ink),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Complete the payment in your browser. This screen will update automatically once confirmed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.slate, height: 1.4),
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton.icon(
                  onPressed: _launchChapa,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Re-open Chapa checkout'),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF1DBF73)),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: const Color(0xFFE8FBF1),
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: const Color(0xFF1DBF73).withOpacity(0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: Color(0xFF1DBF73),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.bolt_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Chapa Secure Checkout',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: AppColors.ink)),
                    SizedBox(height: 2),
                    Text(
                        'Pay instantly via Telebirr, CBE Birr, HelloCash, bank card, and more.',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.slate,
                            height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('How it works:',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.slate)),
        const SizedBox(height: 6),
        for (final step in [
          '1. Tap the button below to open Chapa\'s secure checkout.',
          '2. Choose your preferred payment option and complete the payment.',
          '3. Return here — your activation will be processed automatically.',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(step,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.slate, height: 1.4)),
          ),
        if (_chapaError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: Border.all(color: AppColors.danger.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppColors.danger, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _chapaError!,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.danger),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _chapaLoading ? null : _launchChapa,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DBF73),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button)),
              elevation: 0,
            ),
            icon: _chapaLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.bolt_rounded, size: 20),
            label: Text(
              _chapaLoading
                  ? 'Preparing checkout…'
                  : 'Pay ${widget.plan.formattedPrice} with Chapa',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBankSection(Color planColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Transfer to Official AEBNG Accounts:',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.cloud,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: const Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('CBE Account:',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate)),
                  Text('1000123456789',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink)),
                ],
              ),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Telebirr Account:',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate)),
                  Text('0912345678',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink)),
                ],
              ),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Account Name:',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate)),
                  Text('AEBNG Trading PLC',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text('Reference / Transaction Number',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: _refCtrl,
          decoration: const InputDecoration(
            hintText: 'e.g. FT2608149832',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('Upload Payment Receipt',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.ink)),
        const SizedBox(height: AppSpacing.xs),
        InkWell(
          onTap: _pickReceipt,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_upload_rounded, color: planColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _receiptFile == null
                        ? 'Select image from gallery'
                        : 'Selected: ${_receiptFile!.name.split('/').last}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: _receiptFile == null
                          ? AppColors.slate
                          : AppColors.ink,
                      fontWeight: _receiptFile == null
                          ? FontWeight.normal
                          : FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: 'Submit Receipt & Request Activation',
          isLoading: _bankSubmitting,
          backgroundColor: planColor,
          onPressed: _confirmBank,
        ),
      ],
    );
  }
}

// ── Small reusable payment-method tab ─────────────────────────────────────────

class _MethodTab extends StatelessWidget {
  const _MethodTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : AppColors.cloud,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? color : AppColors.slate),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? color : AppColors.slate,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
