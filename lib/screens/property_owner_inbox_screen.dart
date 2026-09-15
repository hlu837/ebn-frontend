import 'dart:async';

import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../models/auth_response.dart';
import '../models/property_request.dart';
import '../services/asset_service.dart';
import '../services/property_request_service.dart';
import '../theme/app_theme.dart';
import 'broker_chat_screen.dart';

/// The Property Owner's Inbox — every incoming request across all of
/// their properties (info / tour / rent-now), filterable by property or
/// status. Opening a request goes straight into the same real chat
/// screen the Agent side uses ([BrokerChatScreen.fromThread]) since each
/// request is backed by a normal chat thread — see
/// `backend/src/models/propertyRequests.js`.
///
/// Document review, sending the rental agreement, and the 24h payment
/// countdown are intentionally NOT part of this screen — that's the
/// Review tab, a separate follow-up (see `property_owner_home_screen.dart`).
class PropertyOwnerInboxScreen extends StatefulWidget {
  const PropertyOwnerInboxScreen({super.key, required this.user, this.onUnreadChanged});

  final AppUser user;

  /// Called after every successful load with the sum of unread counts
  /// across all requests, so the bottom nav can show a badge.
  final ValueChanged<int>? onUnreadChanged;

  @override
  State<PropertyOwnerInboxScreen> createState() => _PropertyOwnerInboxScreenState();
}

enum _StatusFilter { all, pending, inProgress, closed }

extension _StatusFilterX on _StatusFilter {
  String get label {
    switch (this) {
      case _StatusFilter.all:
        return 'All';
      case _StatusFilter.pending:
        return 'Needs reply';
      case _StatusFilter.inProgress:
        return 'In progress';
      case _StatusFilter.closed:
        return 'Closed';
    }
  }

  String? get wireValue {
    switch (this) {
      case _StatusFilter.all:
        return null;
      case _StatusFilter.pending:
        return 'pending';
      case _StatusFilter.inProgress:
        return 'in_progress';
      case _StatusFilter.closed:
        return 'closed';
    }
  }
}

class _PropertyOwnerInboxScreenState extends State<PropertyOwnerInboxScreen> {
  final _service = PropertyRequestService();
  final _assetService = AssetService();

  List<PropertyRequest> _requests = const [];
  List<Asset> _properties = const [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  _StatusFilter _statusFilter = _StatusFilter.all;
  String? _assetFilter; // null = all properties

  String get _token => widget.user.token ?? '';

  @override
  void initState() {
    super.initState();
    _loadProperties();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProperties() async {
    try {
      final rows = await _assetService.fetchByBroker(widget.user.id);
      if (!mounted) return;
      setState(() => _properties = rows);
    } on AssetException {
      // The property filter just won't have options — not worth
      // blocking or erroring the whole Inbox over.
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _service.listInbox(
        token: _token,
        status: _statusFilter.wireValue,
        assetId: _assetFilter,
      );
      if (!mounted) return;
      setState(() {
        _requests = rows;
        _loading = false;
        _error = null;
      });
      // Badge reflects everything unread regardless of the active
      // filter, so re-derive it straight from a fresh unfiltered read
      // only when filters are at defaults; otherwise keep it cheap and
      // just sum what's currently loaded when unfiltered.
      if (_statusFilter == _StatusFilter.all && _assetFilter == null) {
        widget.onUnreadChanged?.call(rows.fold<int>(0, (sum, r) => sum + r.unreadCount));
      }
    } on PropertyRequestException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.message;
      });
    }
  }

  Future<void> _openRequest(PropertyRequest request) async {
    if (request.threadId == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BrokerChatScreen.fromThread(thread: request.toChatThread(), currentUser: widget.user),
    ));
    if (!mounted) return;
    _load(silent: true);
  }

  void _setStatusFilter(_StatusFilter filter) {
    setState(() => _statusFilter = filter);
    _load();
  }

  void _setAssetFilter(String? assetId) {
    setState(() => _assetFilter = assetId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      appBar: AppBar(
        backgroundColor: AppColors.cloud,
        elevation: 0,
        foregroundColor: AppColors.ink,
        automaticallyImplyLeading: false,
        title: const Text('Inbox', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink)),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _Filters(
              properties: _properties,
              assetFilter: _assetFilter,
              statusFilter: _statusFilter,
              onAssetChanged: _setAssetFilter,
              onStatusChanged: _setStatusFilter,
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: () => _load())
                      : _requests.isEmpty
                          ? const _EmptyState()
                          : RefreshIndicator(
                              color: AppColors.primaryYellow,
                              onRefresh: () => _load(),
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: EdgeInsets.zero,
                                itemCount: _requests.length,
                                separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border, indent: 78),
                                itemBuilder: (context, i) {
                                  final request = _requests[i];
                                  return _RequestTile(request: request, onTap: () => _openRequest(request));
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.properties,
    required this.assetFilter,
    required this.statusFilter,
    required this.onAssetChanged,
    required this.onStatusChanged,
  });

  final List<Asset> properties;
  final String? assetFilter;
  final _StatusFilter statusFilter;
  final ValueChanged<String?> onAssetChanged;
  final ValueChanged<_StatusFilter> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: [
              for (final f in _StatusFilter.values) ...[
                _FilterChip(label: f.label, selected: statusFilter == f, onTap: () => onStatusChanged(f)),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        if (properties.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: assetFilter,
                isDense: true,
                icon: const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.slate),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('All properties')),
                  for (final p in properties) DropdownMenuItem<String?>(value: p.id, child: Text(p.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: onAssetChanged,
              ),
            ),
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.ink : AppColors.cloud,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? AppColors.ink : AppColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.ink),
          ),
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request, required this.onTap});

  final PropertyRequest request;
  final VoidCallback onTap;

  Color get _typeColor {
    switch (request.requestType) {
      case PropertyRequestType.rentNow:
        return AppColors.primaryYellow;
      case PropertyRequestType.tour:
        return AppColors.success;
      case PropertyRequestType.info:
        return AppColors.slate;
    }
  }

  String get _requesterName =>
      request.requester?.fullName.trim().isNotEmpty == true ? request.requester!.fullName : 'A user';

  String get _initials {
    final parts = _requesterName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final unread = request.unreadCount > 0;
    final needsReply = request.status == PropertyRequestStatus.pending;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 23,
              backgroundColor: AppColors.ink,
              child: Text(_initials, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: _typeColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                        child: Text(
                          request.requestType.label,
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _typeColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _requesterName,
                          style: TextStyle(fontSize: 14.5, fontWeight: unread ? FontWeight.w800 : FontWeight.w700, color: AppColors.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (request.lastMessageAt != null)
                        Text(
                          _relativeTime(request.lastMessageAt!),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: unread ? AppColors.primaryYellow : AppColors.slate,
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (request.asset != null)
                    Text(
                      request.asset!.title,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.slate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (request.lastMessageBody?.trim().isNotEmpty == true
                              ? request.lastMessageBody!
                              : request.message?.trim().isNotEmpty == true
                                  ? request.message!
                                  : needsReply
                                      ? request.status.nextStepLabel
                                      : 'No messages yet'),
                          style: TextStyle(
                            fontSize: 13,
                            color: unread || needsReply ? AppColors.ink : AppColors.slate,
                            fontWeight: unread || needsReply ? FontWeight.w600 : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (unread)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.primaryYellow, borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            request.unreadCount > 9 ? '9+' : '${request.unreadCount}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                        )
                      else if (needsReply)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: AppColors.primaryYellow, shape: BoxShape.circle),
                        ),
                    ],
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
            Icon(Icons.inbox_rounded, size: 44, color: AppColors.slate),
            SizedBox(height: 14),
            Text('No requests yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
            SizedBox(height: 6),
            Text(
              'Info, tour, and rent-now requests on your properties will show up here.',
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

/// Same small self-contained "time ago" formatter as `chat_inbox_screen.dart`.
String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  final weeks = diff.inDays ~/ 7;
  if (weeks < 5) return '${weeks}w';
  return '${dt.month}/${dt.day}/${dt.year % 100}';
}
