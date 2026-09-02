import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

/// Shows a dismissible banner sliding in from the top of the screen when
/// a new notification arrives, so it's noticeable even if the user never
/// opens the bell icon. This is purely a foreground, in-app alert — it
/// only fires while this screen is mounted and polling; it does not
/// persist to the OS notification shade or fire while the app is
/// backgrounded/closed (see notification_service.dart for that).
class NotificationAlertOverlay {
  static OverlayEntry? _current;

  static void show(
    BuildContext context, {
    required AppNotification notification,
    required VoidCallback onTap,
  }) {
    _current?.remove();
    final overlayState = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _AlertBanner(
        notification: notification,
        onTap: () {
          entry.remove();
          if (_current == entry) _current = null;
          onTap();
        },
        onDismiss: () {
          entry.remove();
          if (_current == entry) _current = null;
        },
      ),
    );
    _current = entry;
    overlayState.insert(entry);
  }
}

class _AlertBanner extends StatefulWidget {
  const _AlertBanner({
    required this.notification,
    required this.onTap,
    required this.onDismiss,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  State<_AlertBanner> createState() => _AlertBannerState();
}

class _AlertBannerState extends State<_AlertBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _offset = Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(seconds: 5), _dismiss);
  }

  Future<void> _dismiss() async {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    await _controller.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData _iconFor(AppNotificationKind kind) {
    switch (kind) {
      case AppNotificationKind.newDispatch:
        return Icons.local_shipping_outlined;
      case AppNotificationKind.chatMessage:
        return Icons.chat_bubble_outline_rounded;
      case AppNotificationKind.payout:
        return Icons.account_balance_wallet_outlined;
      case AppNotificationKind.system:
        return Icons.notifications_active_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _offset,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _dismissing = true;
              _controller.reverse();
              widget.onTap();
            },
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < 0) _dismiss();
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      shape: BoxShape.circle,
                    ),
                    child:
                        Icon(_iconFor(n.kind), color: Colors.white, size: 17),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          n.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 11.5,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.close_rounded,
                      color: Colors.white.withOpacity(0.6), size: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
