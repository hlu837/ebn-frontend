import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'providers/loop_controller.dart';
import 'providers/sell_request_controller.dart';
import 'providers/order_request_controller.dart';
import 'providers/favorites_controller.dart';
import 'providers/pending_form_store.dart';
import 'screens/role_gate_screen.dart';
import 'screens/role_router.dart';
import 'services/auth_service.dart';
import 'services/session_service.dart';
import 'theme/app_theme.dart';
import 'widgets/network_status_banner.dart';

void main() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };
  runApp(const EbnDemoApp());
}

/// Root of the demo. [LoopController], [SellRequestController],
/// [OrderRequestController], and [FavoritesController] are provided once
/// here, above the Navigator, so they stay the single shared source of
/// truth no matter which side (Customer / Admin / Agent) is currently
/// pushed on the stack.
class EbnDemoApp extends StatelessWidget {
  const EbnDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LoopController()),
        ChangeNotifierProvider(create: (_) => SellRequestController()),
        ChangeNotifierProvider(create: (_) => OrderRequestController()),
        ChangeNotifierProvider(create: (_) => FavoritesController()),
        ChangeNotifierProvider(create: (_) => PendingFormStore()),
      ],
      child: MaterialApp(
        title: 'EBN — Verify Any Asset',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: AppLocalizations.fallbackLocale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        localeResolutionCallback: AppLocalizations.localeResolutionCallback,
        builder: (context, child) =>
            NetworkStatusBanner(child: child ?? const SizedBox.shrink()),
        home: const _SessionGate(),
      ),
    );
  }
}

/// Runs once at app start, before anything else is shown: checks for a
/// session saved by [SessionService] (see `login_screen.dart` /
/// `signup_screen.dart` for where it's written, and
/// `visitor_account_screen.dart` for where it's cleared on logout).
///
/// - No saved session → straight to the landing page, as before.
/// - Saved session, still valid → skip the landing page entirely and
///   land the user right back on their own dashboard.
/// - Saved session, but the token's gone stale (expired/revoked
///   server-side) → the session is discarded and it falls back to the
///   landing page rather than getting stuck.
class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  late final Future<Widget> _destination = _resolve();

  Future<Widget> _resolve() async {
    final saved = await SessionService.restoreSession();
    if (saved == null || saved.token == null) return const RoleGateScreen();
    try {
      // Confirm the token is still accepted by the server before trusting
      // it — an on-device copy alone can't tell a live session from one
      // that was revoked or expired since the app last ran.
      final freshUser = await AuthService().me(saved.token!);
      return dashboardForRole(freshUser.role, freshUser);
    } catch (_) {
      await SessionService.clearSession();
      return const RoleGateScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _destination,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppColors.cloud,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data ?? const RoleGateScreen();
      },
    );
  }
}
