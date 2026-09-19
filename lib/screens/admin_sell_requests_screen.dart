import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/asset.dart';
import '../models/sell_request.dart';
import '../providers/sell_request_controller.dart';
import '../theme/app_theme.dart';
import '../utils/media_encoding.dart';
import '../widgets/app_buttons.dart';

/// Admin's queue for the "sell my property" pipeline — two stages to
/// screen: brand-new Visitor submissions, and Agent inspection reports
/// that are ready for final sign-off before going live.
class AdminSellRequestsScreen extends StatefulWidget {
  const AdminSellRequestsScreen({super.key, required this.token});

  /// Admin JWT. Publishing an approved submission/report hits
  /// `POST /api/assets`, which is admin-only server-side.
  final String token;

  @override
  State<AdminSellRequestsScreen> createState() =>
      _AdminSellRequestsScreenState();
}

class _AdminSellRequestsScreenState extends State<AdminSellRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  /// ids of requests currently mid-approve/reject — lets the card show a
  /// spinner instead of looking like the tap did nothing.
  final Set<String> _pendingIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SellRequestController>().fetchAdminQueues();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Runs a backend action, showing a per-card spinner while it's in
  /// flight and surfacing any failure loudly (long-lived red SnackBar +
  /// console log) instead of letting it fail unnoticed.
  Future<void> _run(String id, Future<void> Function() action) async {
    setState(() => _pendingIds.add(id));
    try {
      await action();
    } catch (e, st) {
      // ignore: avoid_print
      debugPrint('[AdminSellRequests] action failed for $id: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        duration: const Duration(seconds: 8),
        content: Text('$e'),
      ));
    } finally {
      if (mounted) setState(() => _pendingIds.remove(id));
    }
  }

  Future<String?> _promptReason(String title, String hint) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.cloud,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.sm),
                borderSide: const BorderSide(color: AppColors.border)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SellRequestController>();

    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        foregroundColor: AppColors.ink,
        title: const Text('Sell requests',
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
            Tab(text: 'Submissions (${controller.pendingSubmissions.length})'),
            Tab(text: 'Reports (${controller.pendingReports.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _SubmissionsTab(
            requests: controller.pendingSubmissions,
            pendingIds: _pendingIds,
            onApprove: (id) => _run(
                id, () => controller.adminApproveSubmission(id, token: widget.token)),
            onReject: (id) async {
              final reason = await _promptReason(
                  'Reject submission', 'Why is this being rejected?');
              if (reason != null) {
                _run(id,
                    () => controller.adminRejectSubmission(id, reason: reason));
              }
            },
          ),
          _ReportsTab(
            requests: controller.pendingReports,
            pendingIds: _pendingIds,
            onApprove: (id) => _run(
                id, () => controller.adminApproveReport(id, token: widget.token)),
            onReject: (id) async {
              final reason = await _promptReason(
                  'Send report back', 'What needs to change?');
              if (reason != null) {
                _run(id, () => controller.adminRejectReport(id, reason: reason));
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SubmissionsTab extends StatelessWidget {
  const _SubmissionsTab(
      {required this.requests,
      required this.pendingIds,
      required this.onApprove,
      required this.onReject});

  final List<SellRequest> requests;
  final Set<String> pendingIds;
  final ValueChanged<String> onApprove;
  final ValueChanged<String> onReject;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const _EmptyQueue(
          message: 'No new submissions waiting on review.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final r = requests[index];
        return _QueueCard(
          title: r.title,
          subtitle:
              '${r.category.label} · ${r.city} · ETB ${r.askingPrice.toStringAsFixed(0)}',
          badge: r.isAgentListing ? 'Agent listing' : null,
          media: r.reportMedia,
          detailLines: [
            r.isAgentListing
                ? 'Agent (own listing): ${r.agentName ?? r.ownerName} · ${r.ownerPhone}'
                : 'From: ${r.ownerName} · ${r.ownerPhone}',
            r.addressLine,
            r.description,
            if (r.isAgentListing && r.reportNotes?.isNotEmpty == true)
              r.reportNotes!,
            'Fee paid: ETB ${r.feeAmount.toStringAsFixed(0)}',
          ],
          primaryLabel: r.isAgentListing
              ? 'Approve & publish listing'
              : 'Approve → open to brokers',
          isLoading: pendingIds.contains(r.id),
          onPrimary: () => onApprove(r.id),
          onSecondary: () => onReject(r.id),
        );
      },
    );
  }
}

class _ReportsTab extends StatelessWidget {
  const _ReportsTab(
      {required this.requests,
      required this.pendingIds,
      required this.onApprove,
      required this.onReject});

  final List<SellRequest> requests;
  final Set<String> pendingIds;
  final ValueChanged<String> onApprove;
  final ValueChanged<String> onReject;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const _EmptyQueue(
          message: 'No inspection reports waiting on review.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final r = requests[index];
        return _QueueCard(
          title: r.title,
          subtitle:
              '${r.category.label} · ${r.city} · ETB ${r.askingPrice.toStringAsFixed(0)}',
          media: r.reportMedia,
          detailLines: [
            'Inspected by: ${r.agentName ?? 'Agent'}',
            if (r.reportNotes?.isNotEmpty == true) r.reportNotes!,
          ],
          primaryLabel: 'Approve & publish listing',
          isLoading: pendingIds.contains(r.id),
          onPrimary: () => onApprove(r.id),
          onSecondary: () => onReject(r.id),
        );
      },
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.title,
    required this.subtitle,
    required this.detailLines,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onSecondary,
    this.badge,
    this.media = const [],
    this.isLoading = false,
  });

  final String title;
  final String subtitle;
  final List<String> detailLines;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;
  final String? badge;
  final List<ReportMediaItem> media;
  final bool isLoading;

  void _openViewer(BuildContext context, int startIndex) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _MediaViewerScreen(
          media: media, startIndex: startIndex, title: title),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink))),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppColors.primaryYellow.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(AppRadii.pill)),
                  child: Text(badge!,
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryYellowDark)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(fontSize: 12.5, color: AppColors.slate)),
          const SizedBox(height: 8),
          if (media.isNotEmpty) ...[
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: media.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final item = media[i];
                  final image = dataUrlOrNetworkImage(item.filePath);
                  return GestureDetector(
                    onTap: () => _openViewer(context, i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      child: Container(
                        width: 76,
                        height: 76,
                        color: AppColors.cloud,
                        child: image != null
                            ? Image(image: image, fit: BoxFit.cover)
                            : const Icon(Icons.broken_image_outlined,
                                color: AppColors.slate),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: const Text('No photos attached to this submission.',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
          ],
          for (final line in detailLines.where((l) => l.trim().isNotEmpty)) ...[
            Text(line,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.slate, height: 1.4)),
            const SizedBox(height: 2),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                    label: 'Reject',
                    borderColor: AppColors.danger,
                    textColor: AppColors.danger,
                    onPressed: isLoading ? null : onSecondary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: PrimaryButton(
                    label: primaryLabel,
                    backgroundColor: AppColors.primaryYellow,
                    foregroundColor: Colors.white,
                    isLoading: isLoading,
                    onPressed: onPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Full-screen swipeable viewer for a submission's photos, opened by
/// tapping any thumbnail on a [_QueueCard].
class _MediaViewerScreen extends StatefulWidget {
  const _MediaViewerScreen(
      {required this.media, required this.startIndex, required this.title});

  final List<ReportMediaItem> media;
  final int startIndex;
  final String title;

  @override
  State<_MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<_MediaViewerScreen> {
  late final PageController _controller =
      PageController(initialPage: widget.startIndex);
  late int _index = widget.startIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${widget.title} · ${_index + 1}/${widget.media.length}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.media.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final item = widget.media[i];
          final image = dataUrlOrNetworkImage(item.filePath);
          if (image == null) {
            return const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: Colors.white54, size: 48),
            );
          }
          return Center(
            child: InteractiveViewer(
              child: Image(image: image, fit: BoxFit.contain),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({required this.message});
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
