import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Wraps the whole app (see `main.dart`) so that losing network
/// connectivity is caught in one place, no matter which screen — Visitor,
/// Agent, Admin, etc — happens to be on screen at the time. Shows a
/// persistent "Check your network connection ..." strip while offline,
/// and a brief "Back online" confirmation the moment it reconnects.
class NetworkStatusBanner extends StatefulWidget {
  const NetworkStatusBanner({super.key, required this.child});

  final Widget child;

  @override
  State<NetworkStatusBanner> createState() => _NetworkStatusBannerState();
}

class _NetworkStatusBannerState extends State<NetworkStatusBanner> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _offline = false;
  // Shown briefly right after reconnecting, then auto-hidden.
  bool _justReconnected = false;
  Timer? _reconnectedTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final initial = await _connectivity.checkConnectivity();
    _applyResult(initial, announceReconnect: false);
    _subscription =
        _connectivity.onConnectivityChanged.listen(_applyResult);
  }

  void _applyResult(List<ConnectivityResult> results,
      {bool announceReconnect = true}) {
    final isOffline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (!mounted) return;
    if (isOffline == _offline) return;

    setState(() {
      if (_offline && !isOffline && announceReconnect) {
        _justReconnected = true;
        _reconnectedTimer?.cancel();
        _reconnectedTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _justReconnected = false);
        });
      } else if (isOffline) {
        _justReconnected = false;
      }
      _offline = isOffline;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _reconnectedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // Positioned above everything (including dialogs' barriers can't
        // be helped, but app content and navigation bars can) so the
        // notice is visible regardless of which screen is active.
        if (_offline || _justReconnected)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: _StatusStrip(offline: _offline),
            ),
          ),
      ],
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.offline});

  final bool offline;

  @override
  Widget build(BuildContext context) {
    final color = offline ? AppColors.danger : AppColors.success;
    final icon = offline ? Icons.wifi_off_rounded : Icons.wifi_rounded;
    final label = offline
        ? 'Check your network connection and try again.'
        : 'Back online';

    return Material(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
