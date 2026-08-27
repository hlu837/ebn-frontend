import 'package:flutter/material.dart';
import '../screens/role_gate_screen.dart';

/// Safely handles back navigation across the app.
///
/// If [Navigator.canPop] is true, it pops to the previous screen.
/// If [Navigator.canPop] is false (e.g. after a `pushAndRemoveUntil` transition),
/// it safely navigates back to the main home page ([RoleGateScreen])
/// instead of closing/exiting the app.
void safePop(BuildContext context) {
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  } else {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleGateScreen()),
      (route) => false,
    );
  }
}
