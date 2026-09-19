import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/asset.dart';
import '../models/auth_response.dart';
import '../models/sell_request.dart';
import '../providers/order_request_controller.dart';
import '../providers/sell_request_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/agent_claimed_order_card.dart';
import '../widgets/app_buttons.dart';
import 'agent_property_report_screen.dart';

/// The Agent/Broker side of the "sell my property" pipeline: browse
/// requests Admin has opened up, claim one (first come, first served),
/// go inspect it in person, then submit the report from here.
///
/// This is where an agent manages *other people's* work, so "My claims"
/// holds both kinds: properties claimed to inspect, and "Order Us" requests
/// claimed from visitors (see [OrderRequestController.claimedActiveBy]).
class AgentSellRequestsScreen extends StatefulWidget {
  const AgentSellRequestsScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<AgentSellRequestsScreen> createState() =>
      _AgentSellRequestsScreenState();
}

class _AgentSellRequestsScreenState extends State<AgentSellRequestsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  Future<void> _refreshAgentView() async {
    if (!mounted) return;
    final sells = context.read<SellRequestController>();
    final orders = context.read<OrderRequestController>();
    await Future.wait([
      sells.fetchAgentView(widget.user.id),
      // Claimed orders live in a separate controller; refresh them here so
      // they show even if the agent came straight to this screen. Failures
      // are swallowed — the sell-request side has its own error banner and
      // a flaky orders call shouldn't blank it.
      orders.fetchForAgent(widget.user.id).catchError((_) {}),
    ]);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshAgentView();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _refreshAgentView();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _claim(SellRequestController controller, SellRequest r) async {
    final ok = await controller.agentClaim(r.id,
        agentId: widget.user.id, agentName: widget.user.fullName);
    if (!mounted) return;
    if (ok) {
      await _refreshAgentView();
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Claimed — go inspect "${r.title}" and submit your report.'
          : 'Someone else just claimed this one.'),
    ));
  }

  /// A claimed sell request in "My claims" — with the report action that
  /// fits its current status.
  Widget _claimedRequestCard(BuildContext context, SellRequest r) {
    final canSubmit = r.status == SellRequestStatus.claimed ||
        r.status == SellRequestStatus.reportRejected;
    return _RequestCard(
      request: r,
      actionLabel: r.status == SellRequestStatus.reportPendingApproval
          ? null
          : (r.status == SellRequestStatus.reportRejected
              ? 'Revise & resubmit report'
              : 'Submit inspection report'),
      onAction: canSubmit
          ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AgentPropertyReportScreen(request: r),
                ),
              )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SellRequestController>();
    final nearby = controller.broadcastingFor(widget.user.id);
    final open = controller.openToBrokers;
    final mine = [
      ...controller.claimedBy(widget.user.id),
      ...controller.reportsPendingBy(widget.user.id),
    ];
    final claimedOrders =
        context.watch<OrderRequestController>().claimedActiveBy(widget.user.id);
    final claimsCount = mine.length + claimedOrders.length;

    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        title: const Text('Property Management',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.ink,
          unselectedLabelColor: AppColors.slate,
          indicatorColor: AppColors.primaryYellow,
          indicatorWeight: 3,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: [
            Tab(text: 'Available (${nearby.length + open.length})'),
            Tab(text: 'My claims ($claimsCount)'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (controller.lastError != null)
            Container(
              width: double.infinity,
              color: AppColors.danger.withOpacity(0.08),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 16, color: AppColors.danger),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "Couldn't refresh everything — what you see below may be out of date.",
                      style: TextStyle(fontSize: 12, color: AppColors.danger),
                    ),
                  ),
                  TextButton(
                    onPressed: _refreshAgentView,
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: const Text('Retry',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.danger)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                RefreshIndicator(
                  onRefresh: _refreshAgentView,
                  child: (nearby.isEmpty && open.isEmpty)
                      ? ListView(
                          children: const [
                            _EmptyState(
                                message:
                                    'No properties waiting for a broker right now.')
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          children: [
                            if (nearby.isNotEmpty) ...[
                              const _SectionHeader(
                                icon: Icons.near_me_rounded,
                                label: 'Near you — first to claim gets it',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              ...nearby.map((r) => Padding(
                                    padding: const EdgeInsets.only(
                                        bottom: AppSpacing.sm),
                                    child: _RequestCard(
                                      request: r,
                                      isNearby: true,
                                      actionLabel: 'Claim & inspect',
                                      onAction: () => _claim(controller, r),
                                    ),
                                  )),
                              if (open.isNotEmpty)
                                const SizedBox(height: AppSpacing.md),
                            ],
                            if (open.isNotEmpty) ...[
                              const _SectionHeader(
                                icon: Icons.public_rounded,
                                label: 'Open to all agents',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              ...open.map((r) => Padding(
                                    padding: const EdgeInsets.only(
                                        bottom: AppSpacing.sm),
                                    child: _RequestCard(
                                      request: r,
                                      actionLabel: 'Claim & inspect',
                                      onAction: () => _claim(controller, r),
                                    ),
                                  )),
                            ],
                          ],
                        ),
                ),
                RefreshIndicator(
                  onRefresh: _refreshAgentView,
                  child: claimsCount == 0
                      ? ListView(
                          children: const [
                            _EmptyState(
                                message:
                                    "You haven't claimed any properties or orders yet.")
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          children: [
                            if (mine.isNotEmpty) ...[
                              // Headers only matter once both kinds are
                              // present — otherwise the list speaks for itself.
                              if (claimedOrders.isNotEmpty) ...const [
                                _SectionHeader(
                                  icon: Icons.home_work_outlined,
                                  label: 'Properties to inspect',
                                ),
                                SizedBox(height: AppSpacing.sm),
                              ],
                              for (final r in mine)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: AppSpacing.sm),
                                  child: _claimedRequestCard(context, r),
                                ),
                            ],
                            if (claimedOrders.isNotEmpty) ...[
                              if (mine.isNotEmpty)
                                const SizedBox(height: AppSpacing.sm),
                              const _SectionHeader(
                                icon: Icons.shopping_bag_outlined,
                                label: 'Claimed orders',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              for (final o in claimedOrders)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: AppSpacing.sm),
                                  child: AgentClaimedOrderCard(request: o),
                                ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.slate),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.slate)),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard(
      {required this.request,
      this.actionLabel,
      this.onAction,
      this.isNearby = false});

  final SellRequest request;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isNearby;

  @override
  Widget build(BuildContext context) {
    final r = request;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: Text(r.title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink))),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: AppColors.primaryYellow.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(AppRadii.pill)),
                child: Text('ETB ${r.askingPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('${r.category.label} · ${r.city}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.slate)),
          const SizedBox(height: 6),
          Text(r.addressLine,
              style: const TextStyle(fontSize: 12.5, color: AppColors.slate)),
          if (isNearby) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.near_me_rounded,
                    size: 14, color: AppColors.primaryYellowDark),
                SizedBox(width: 6),
                Text('Near you',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primaryYellowDark,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ],
          if (r.status == SellRequestStatus.reportPendingApproval) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.hourglass_top_rounded,
                    size: 14, color: AppColors.primaryYellowDark),
                SizedBox(width: 6),
                Text('Report submitted — waiting on Admin',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primaryYellowDark,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ],
          if (r.status == SellRequestStatus.reportRejected) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppRadii.sm)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: AppColors.danger),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(r.reportRejectionReason ?? 'Needs revision.',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.danger))),
                ],
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
                label: actionLabel!,
                backgroundColor: AppColors.primaryYellow,
                foregroundColor: Colors.white,
                onPressed: onAction),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_rounded, size: 36, color: AppColors.slate),
            const SizedBox(height: AppSpacing.sm),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.slate, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
