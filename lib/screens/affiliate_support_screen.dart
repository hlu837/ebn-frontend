import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/faq_data.dart';
import '../models/auth_response.dart';
import '../services/support_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_buttons.dart';

const _kAccentRed = AppColors.primaryYellow;

// TODO: placeholders — swap in the real support email/phone once provided.
const _kSupportEmail = 'support@ebn.et';
const _kSupportPhone = '+251900000000';

/// Affiliate-specific FAQ, layered on top of the shared platform FAQ list,
/// plus a "message us" form backed by the real `POST /api/support-tickets`
/// endpoint — lands in the same admin inbox (`admin_support_inbox_screen.dart`)
/// as Visitor/Agent submissions.
const List<FaqItem> _kAffiliateFaq = [
  FaqItem(
    'How is my commission calculated?',
    'Commission is a percentage of the sale price, set per-listing (shown as a badge on each property '
        'card). It moves to "Pending" once a referred customer completes a deal, and clears once the '
        'transaction is fully settled.',
  ),
  FaqItem(
    'When can I request a payout?',
    'Any cleared (non-pending) commission that hasn\'t already been paid out is available to withdraw '
        'from the Earnings page. Payouts are reviewed by an admin before funds are sent.',
  ),
  FaqItem(
    'How do referral links work?',
    'Tap "Generate Link" on any property to create a shareable link tagged with your affiliate code. '
        'Anyone who signs up or buys through that link is attributed to you automatically.',
  ),
];

class AffiliateSupportScreen extends StatefulWidget {
  const AffiliateSupportScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<AffiliateSupportScreen> createState() => _AffiliateSupportScreenState();
}

class _AffiliateSupportScreenState extends State<AffiliateSupportScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final _service = SupportService();
  int? _expandedIndex;
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // There's no real-time chat channel for the Affiliater role (unlike the
  // buyer<->agent chat threads elsewhere in the app) — this used to just
  // show a "Connecting you to support..." toast and do nothing else,
  // which looked broken because nothing ever actually connected. Until a
  // real live-chat channel exists, the honest action is to jump straight
  // to the one real support channel that *does* work: the message form
  // below, backed by POST /api/support-tickets.
  void _startLiveChat() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
    _messageFocusNode.requestFocus();
    AppToast.showInfo(context, 'Write your message below and our team will reply by email/notification.');
  }

  Future<void> _launch(Uri uri, String failureMessage) async {
    try {
      final ok = await launchUrl(uri);
      if (!ok && mounted) AppToast.showError(context, failureMessage);
    } catch (_) {
      if (mounted) AppToast.showError(context, failureMessage);
    }
  }

  Future<void> _emailUs() =>
      _launch(Uri.parse('mailto:$_kSupportEmail'), 'Couldn\'t open an email app. Email us at $_kSupportEmail.');

  Future<void> _callUs() =>
      _launch(Uri.parse('tel:$_kSupportPhone'), 'Couldn\'t start a call. Call us at $_kSupportPhone.');

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      AppToast.showError(context, 'Write a message first.');
      return;
    }
    final token = widget.user.token;
    if (token == null) {
      AppToast.showError(context, 'Please sign in again to send a message.');
      return;
    }
    setState(() => _sending = true);
    try {
      await _service.submitTicket(
        category: 'other',
        subject: 'Affiliate support message',
        body: text,
        token: token,
      );
      if (!mounted) return;
      _messageController.clear();
      AppToast.showSuccess(context, 'Message sent — our team will get back to you soon.');
    } on SupportServiceException catch (e) {
      if (!mounted) return;
      AppToast.showError(context, e.message);
    } catch (_) {
      // Belt-and-suspenders: without this, any error that isn't a
      // SupportServiceException (a parsing hiccup, etc.) escapes both
      // catch clauses and the button just silently resets — which is
      // exactly the "nothing displayed" symptom this screen was
      // reported for. Every failure path now always shows something.
      if (!mounted) return;
      AppToast.showError(context, 'Failed to send message. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allFaq = [..._kAffiliateFaq, ...faqItems];

    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        title: const Text('Support', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            children: [
              Expanded(
                child: _ContactTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Live Chat',
                  onTap: _startLiveChat,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ContactTile(
                  icon: Icons.mail_outline_rounded,
                  label: 'Email Us',
                  onTap: _emailUs,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ContactTile(
                  icon: Icons.call_outlined,
                  label: 'Call Us',
                  onTap: _callUs,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Frequently Asked Questions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          ...List.generate(allFaq.length, (i) {
            final expanded = _expandedIndex == i;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _FaqTile(
                item: allFaq[i],
                expanded: expanded,
                onTap: () => setState(() => _expandedIndex = expanded ? null : i),
              ),
            );
          }),
          const SizedBox(height: AppSpacing.lg),
          Text('Still need help?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _messageController,
            focusNode: _messageFocusNode,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Describe your issue and we\'ll follow up by email...',
              filled: true,
              fillColor: AppColors.card,
              contentPadding: const EdgeInsets.all(AppSpacing.md),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md), borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md), borderSide: const BorderSide(color: _kAccentRed)),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(label: 'Send Message', onPressed: _sendMessage, isLoading: _sending),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _kAccentRed, size: 22),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.ink), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.item, required this.expanded, required this.onTap});

  final FaqItem item;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(item.question, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  ),
                  Icon(expanded ? Icons.remove_rounded : Icons.add_rounded, color: AppColors.slate, size: 20),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(item.answer, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.slate, height: 1.45)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
