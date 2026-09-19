import 'package:flutter/material.dart';
import '../models/auth_response.dart';
import '../models/service_provider.dart';
import '../models/maintenance_assignment.dart';
import '../services/affiliate_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_buttons.dart';

/// Expert, merged into the Affiliate dashboard: an Affiliater who wants to
/// take maintenance jobs sets up a service-provider profile here (backed
/// by `service_providers.user_id` — see 086_service_provider_user_link.sql)
/// instead of signing up separately. Three tabs:
///  - Profile: create/edit the directory listing; starts pending admin
///    approval (mirrors the existing admin active/inactive toggle).
///  - Jobs: maintenance jobs tenants have assigned to this Expert.
///  - Wallet: payout ledger + balance (Phase 6), same numbers admin sees.
class AffiliateExpertScreen extends StatefulWidget {
  const AffiliateExpertScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<AffiliateExpertScreen> createState() => _AffiliateExpertScreenState();
}

class _AffiliateExpertScreenState extends State<AffiliateExpertScreen> {
  final _svc = AffiliateService();

  ServiceProvider? _profile;
  List<MaintenanceAssignment> _jobs = [];
  ExpertWalletSummary? _wallet;
  bool _loading = true;
  String? _error;

  String get _token => widget.user.token ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_token.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Not logged in.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _svc.getExpertProfile(_token);
      List<MaintenanceAssignment> jobs = [];
      ExpertWalletSummary? wallet;
      if (profile != null) {
        final rawJobs = await _svc.getExpertJobs(_token);
        jobs = rawJobs.map(MaintenanceAssignment.fromJson).toList();
        wallet = await _svc.getExpertWallet(_token);
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _jobs = jobs;
        _wallet = wallet;
        _loading = false;
      });
    } on AffiliateException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.cloud,
        appBar: AppBar(
          backgroundColor: AppColors.cloud,
          elevation: 0,
          title: const Text('Expert',
              style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
          iconTheme: const IconThemeData(color: AppColors.ink),
          bottom: const TabBar(
            labelColor: AppColors.ink,
            unselectedLabelColor: AppColors.slate,
            indicatorColor: AppColors.primaryYellow,
            tabs: [
              Tab(text: 'Profile'),
              Tab(text: 'Jobs'),
              Tab(text: 'Wallet'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : TabBarView(
                    children: [
                      _ProfileTab(
                        profile: _profile,
                        onSaved: (p) => setState(() => _profile = p),
                        svc: _svc,
                        token: _token,
                        onBecameExpert: _load,
                      ),
                      _JobsTab(jobs: _jobs, hasProfile: _profile != null),
                      _WalletTab(wallet: _wallet, hasProfile: _profile != null),
                    ],
                  ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.slate)),
            const SizedBox(height: AppSpacing.md),
            SecondaryButton(label: 'Retry', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

// ── Profile tab ──────────────────────────────────────────────────────────

class _ProfileTab extends StatefulWidget {
  const _ProfileTab({
    required this.profile,
    required this.onSaved,
    required this.svc,
    required this.token,
    required this.onBecameExpert,
  });

  final ServiceProvider? profile;
  final ValueChanged<ServiceProvider> onSaved;
  final AffiliateService svc;
  final String token;
  final VoidCallback onBecameExpert;

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _rateCtrl;
  ServiceProviderCategory _category = ServiceProviderCategory.electrician;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _phoneCtrl = TextEditingController(text: p?.phone ?? '');
    _cityCtrl = TextEditingController(text: p?.city ?? '');
    _rateCtrl = TextEditingController(text: p != null ? p.rateBirr.toStringAsFixed(0) : '');
    if (p != null) _category = p.category;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final rateCents = ((double.tryParse(_rateCtrl.text.trim()) ?? 0) * 100).round();
    try {
      final ServiceProvider result;
      if (widget.profile == null) {
        result = await widget.svc.createExpertProfile(
          widget.token,
          name: _nameCtrl.text.trim(),
          category: _category.wireValue,
          phone: _phoneCtrl.text.trim(),
          city: _cityCtrl.text.trim(),
          rateCents: rateCents,
        );
        widget.onBecameExpert();
        if (mounted) {
          AppToast.showSuccess(context, 'Expert profile submitted — pending admin approval.');
        }
      } else {
        result = await widget.svc.updateExpertProfile(
          widget.token,
          name: _nameCtrl.text.trim(),
          category: _category.wireValue,
          phone: _phoneCtrl.text.trim(),
          city: _cityCtrl.text.trim(),
          rateCents: rateCents,
        );
        if (mounted) AppToast.showSuccess(context, 'Expert profile updated.');
      }
      widget.onSaved(result);
    } on AffiliateException catch (e) {
      if (mounted) AppToast.showError(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.profile == null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNew)
              const _InfoBanner(
                icon: Icons.engineering_rounded,
                text:
                    'Set up your specialist profile to appear in the tenant maintenance directory and start taking jobs. An admin reviews new profiles before they go live.',
              )
            else if (!widget.profile!.isActive)
              const _InfoBanner(
                icon: Icons.hourglass_top_rounded,
                text: 'Your profile is saved but not live yet — an admin still needs to approve it.',
                color: AppColors.primaryYellowDark,
              )
            else
              const _InfoBanner(
                icon: Icons.check_circle_rounded,
                text: 'Your profile is live in the tenant directory.',
                color: AppColors.success,
              ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Display name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<ServiceProviderCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: ServiceProviderCategory.values
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _cityCtrl,
              decoration: const InputDecoration(labelText: 'City'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _rateCtrl,
              decoration: const InputDecoration(labelText: 'Rate (ETB)', prefixText: 'ETB '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: isNew ? 'Become an Expert' : 'Save changes',
              isLoading: _saving,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text, this.color = AppColors.slate});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }
}

// ── Jobs tab ─────────────────────────────────────────────────────────────

class _JobsTab extends StatelessWidget {
  const _JobsTab({required this.jobs, required this.hasProfile});
  final List<MaintenanceAssignment> jobs;
  final bool hasProfile;

  @override
  Widget build(BuildContext context) {
    if (!hasProfile) {
      return const _EmptyTab(
        icon: Icons.build_rounded,
        text: 'Set up your Expert profile first to start receiving jobs.',
      );
    }
    if (jobs.isEmpty) {
      return const _EmptyTab(
        icon: Icons.inbox_outlined,
        text: 'No jobs assigned to you yet.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) => _JobTile(job: jobs[i]),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job});
  final MaintenanceAssignment job;

  Color get _statusColor {
    switch (job.escrowStatus) {
      case EscrowStatus.pendingPayment:
        return AppColors.slate;
      case EscrowStatus.held:
        return AppColors.primaryYellowDark;
      case EscrowStatus.released:
        return AppColors.success;
      case EscrowStatus.refunded:
        return AppColors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(job.asset?.title ?? 'Maintenance job',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 4),
                Text('${job.quotedCostBirr.toStringAsFixed(0)} ${job.currency}',
                    style: const TextStyle(color: AppColors.slate, fontSize: 12.5)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(job.escrowStatus.label,
                style: TextStyle(color: _statusColor, fontWeight: FontWeight.w700, fontSize: 11.5)),
          ),
        ],
      ),
    );
  }
}

// ── Wallet tab ───────────────────────────────────────────────────────────

class _WalletTab extends StatelessWidget {
  const _WalletTab({required this.wallet, required this.hasProfile});
  final ExpertWalletSummary? wallet;
  final bool hasProfile;

  @override
  Widget build(BuildContext context) {
    if (!hasProfile) {
      return const _EmptyTab(
        icon: Icons.account_balance_wallet_outlined,
        text: 'Set up your Expert profile to start earning job payouts.',
      );
    }
    final w = wallet ?? const ExpertWalletSummary(balanceCents: 0, transactions: []);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Balance owed to you', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
              const SizedBox(height: 6),
              Text('${w.balanceBirr.toStringAsFixed(2)} ETB',
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Paid out offline by an admin once released — see Payout history below.',
                  style: TextStyle(color: Colors.white60, fontSize: 11.5)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text('Ledger', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: AppSpacing.sm),
        if (w.transactions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(child: Text('No transactions yet.', style: TextStyle(color: AppColors.slate))),
          )
        else
          ...w.transactions.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _WalletTile(tx: t),
              )),
      ],
    );
  }
}

class _WalletTile extends StatelessWidget {
  const _WalletTile({required this.tx});
  final ExpertWalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    final isCredit = tx.type == 'credit';
    final color = isCredit ? AppColors.success : AppColors.slate;
    final sign = isCredit ? '+' : '';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: color, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(tx.label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
          ),
          Text('$sign${tx.amountBirr.abs().toStringAsFixed(0)} ETB',
              style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.border),
            const SizedBox(height: AppSpacing.md),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.slate)),
          ],
        ),
      ),
    );
  }
}
