import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Proactively checks device connectivity before the user attempts an
/// action that needs the network (login, save, submit, send, ...), and
/// pops a blocking alert dialog — not just a toast — when there's no
/// connection, so the person isn't left staring at a spinner or a
/// blink-and-you-miss-it SnackBar wondering what happened.
///
/// Usage at the top of any submit/save handler:
/// ```dart
/// if (!await NetworkAlert.ensureConnected(context)) return;
/// ```
class NetworkAlert {
  NetworkAlert._();

  static Future<bool> ensureConnected(BuildContext context) async {
    final results = await Connectivity().checkConnectivity();
    final offline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (!offline) return true;
    if (!context.mounted) return false;
    await show(context);
    return false;
  }

  /// Shows the alert directly — use this in a `catch` block for a network
  /// exception that already happened (e.g. the request timed out), as a
  /// stronger alternative to a SnackBar toast.
  static Future<void> show(BuildContext context, {String? message}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md)),
        icon: const Icon(Icons.wifi_off_rounded,
            color: AppColors.danger, size: 32),
        title: const Text('No internet connection',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
          message ?? 'Disconnected — please check your network and try again.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.slate),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.ink),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
