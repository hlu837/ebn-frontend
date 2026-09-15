import 'package:flutter/material.dart';
import '../models/auth_response.dart';
import '../theme/app_theme.dart';
import '../services/affiliate_service.dart';
import 'affiliate_earnings_screen.dart';
import 'affiliate_properties_screen.dart';
import 'affiliater_home_screen.dart';

const _kAccentRed = AppColors.primaryYellow;

/// Full referral history for the Affiliater role — everything the
/// dashboard's "Referral Tracker" only shows a preview of, plus a search
/// box and a running total for whichever filter is active.
///
/// Backed by the real `GET /api/affiliates/me/referrals` endpoint via
/// [AffiliateService.getReferrals] (each row is a [ReferralItem]).
class AffiliateReferralsScreen extends StatefulWidget {
  const AffiliateReferralsScreen(
      {super.key, required this.user, required this.token});

  final AppUser user;
  final String token;

  @override
  State<AffiliateReferralsScreen> createState() =>
      _AffiliateReferralsScreenState();
}

class _AffiliateReferralsScreenState extends State<AffiliateReferralsScreen> {
  final _svc = AffiliateService();
  int _tabIndex = 0; // 0 = All, 1 = Pending, 2 = Completed
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  List<ReferralItem> _referrals = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String? _token() => widget.token.isNotEmpty ? widget.token : null;

  Future<void> _load() async {
    final token = _token();
    if (token == null) {
      setState(() {
        _error = 'Not logged in.';
        _loading = false;
      });
      return;
    }
    try {
      final referrals = await _svc.getReferrals(token);
      if (!mounted) return;
      setState(() {
        _referrals = referrals;
        _loading = false;
      });
    } on AffiliateException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load referrals.';
        _loading = false;
      });
    }
  }

  List<ReferralItem> get _filtered {
    var list = _referrals.where((r) {
      if (_tabIndex == 1) return r.isPending;
      if (_tabIndex == 2) return !r.isPending;
      return true;
    });
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      list = list.where((r) =>
          r.customerName.toLowerCase().contains(q) ||
          r.assetTitle.toLowerCase().contains(q));
    }
    final result = list.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  double get _totalForFilter =>
      _filtered.fold(0, (sum, r) => sum + r.commissionAmount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        title: const Text('My Referrals',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading
                ? null
                : () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _load();
                  },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccentRed))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.slate, size: 40),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: AppColors.slate)),
                      const SizedBox(height: 16),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _buildLoaded(context),
      bottomNavigationBar: _AffiliateBottomNav(
        current: 3,
        user: widget.user,
      ),
    );
  }

  Widget _buildLoaded(BuildContext context) {
    final filtered = _filtered;

    return RefreshIndicator(
      color: _kAccentRed,
      onRefresh: _load,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    prefixIcon:
                        Icon(Icons.search_rounded, color: AppColors.slate),
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(AppRadii.md)),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(AppRadii.md)),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(AppRadii.md)),
                      borderSide:
                          BorderSide(color: AppColors.primaryYellow, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    _FilterChip(
                        label: 'All',
                        active: _tabIndex == 0,
                        onTap: () => setState(() => _tabIndex = 0)),
                    const SizedBox(width: AppSpacing.sm),
                    _FilterChip(
                        label: 'Pending',
                        active: _tabIndex == 1,
                        onTap: () => setState(() => _tabIndex = 1)),
                    const SizedBox(width: AppSpacing.sm),
                    _FilterChip(
                        label: 'Completed',
                        active: _tabIndex == 2,
                        onTap: () => setState(() => _tabIndex = 2)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: 12),
                  decoration: BoxDecoration(
                    color: _kAccentRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${filtered.length} referral${filtered.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.slate),
                      ),
                      Text(
                        '${_totalForFilter.toStringAsFixed(0)} ETB',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: filtered.isEmpty
                ? ListView(
                    // Wrapped in a ListView (not just Center) so RefreshIndicator's
                    // pull-to-refresh still works when the list is empty.
                    children: const [_EmptyReferrals()],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                        AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) =>
                        _ReferralRow(entry: filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AffiliateBottomNav extends StatelessWidget {
  const _AffiliateBottomNav({required this.current, required this.user});

  final int current;
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _AffiliateNavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'Home',
              active: current == 0,
              onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                      builder: (_) => AffiliaterHomeScreen(user: user))),
            ),
            _AffiliateNavItem(
              icon: Icons.holiday_village_outlined,
              activeIcon: Icons.holiday_village_rounded,
              label: 'Properties',
              active: current == 1,
              onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                      builder: (_) => AffiliatePropertiesScreen(user: user))),
            ),
            _AffiliateNavItem(
              icon: Icons.account_balance_wallet_outlined,
              activeIcon: Icons.account_balance_wallet_rounded,
              label: 'Wallet',
              active: current == 2,
              onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                      builder: (_) => AffiliateEarningsScreen(
                          user: user, token: user.token ?? ''))),
            ),
            _AffiliateNavItem(
              icon: Icons.groups_outlined,
              activeIcon: Icons.groups_rounded,
              label: 'Referrals',
              active: current == 3,
              onTap: () {},
            ),
            _AffiliateNavItem(
              icon: Icons.more_horiz_rounded,
              activeIcon: Icons.more_horiz_rounded,
              label: 'More',
              active: current == 4,
              onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                      builder: (_) => AffiliaterHomeScreen(user: user))),
            ),
          ],
        ),
      ),
    );
  }
}

class _AffiliateNavItem extends StatelessWidget {
  const _AffiliateNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(active ? activeIcon : icon,
              size: 22,
              color: active ? AppColors.primaryYellow : AppColors.slate),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? AppColors.primaryYellow : AppColors.slate,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _kAccentRed : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: active ? _kAccentRed : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : AppColors.slate),
        ),
      ),
    );
  }
}

class _ReferralRow extends StatelessWidget {
  const _ReferralRow({required this.entry});

  final ReferralItem entry;

  static const _months = [
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
    'Dec',
  ];

  String get _formattedDate =>
      '${_months[entry.createdAt.month - 1]} ${entry.createdAt.day}, ${entry.createdAt.year}';

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
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.border,
            child: Text(
              entry.customerName.isNotEmpty ? entry.customerName[0] : '?',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: AppColors.ink),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.customerName,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(entry.assetTitle,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.slate)),
                const SizedBox(height: 2),
                Text(_formattedDate,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.slate)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                  '${entry.commissionAmount.toStringAsFixed(0)} ${entry.commissionCurrency}',
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: entry.isPending
                      ? const Color(0xFFFFF3D6)
                      : const Color(0xFFE3F6EA),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  entry.isPending ? 'Pending' : 'Completed',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: entry.isPending
                        ? const Color(0xFFB8860B)
                        : AppColors.success,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyReferrals extends StatelessWidget {
  const _EmptyReferrals();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_2_outlined, size: 40, color: AppColors.slate),
            SizedBox(height: AppSpacing.md),
            Text('No referrals here yet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.ink)),
            SizedBox(height: 6),
            Text(
              'Share your affiliate link from the dashboard to start earning commission.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.slate),
            ),
          ],
        ),
      ),
    );
  }
}
