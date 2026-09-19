import 'package:flutter/material.dart';
import '../models/auth_response.dart';
import '../models/user_role.dart';
import '../theme/app_theme.dart';
import 'affiliater_home_screen.dart';
import 'agent_home_screen.dart';
import 'customer_home_screen.dart';
import 'investor_home_screen.dart';

/// Mobile build of the role router (selected via the conditional export in
/// `role_router.dart` whenever `dart.library.html` is NOT available, i.e.
/// every non-web target). Deliberately does not import `admin_home_screen.dart`
/// or `property_owner_home_screen.dart` — doing so here would pull their
/// entire screen subtrees back into the Android build. Admin and Property
/// Owner accounts are web-only; see `role_router_web.dart` for the full
/// six-role version used by `flutter build web`.
Widget dashboardForRole(UserRole role, AppUser user) {
  return switch (role) {
    UserRole.user => CustomerHomeScreen(user: user),
    UserRole.agent => AgentHomeScreen(user: user),
    UserRole.investor => InvestorHomeScreen(user: user),
    UserRole.affiliater => AffiliaterHomeScreen(user: user),
    UserRole.admin => const _WebOnlyScreen(roleLabel: 'Admin'),
    UserRole.propertyOwner => const _WebOnlyScreen(roleLabel: 'Property Owner'),
  };
}

/// Shown instead of a real dashboard if an Admin or Property Owner account
/// somehow signs in from the mobile app (e.g. a role changed server-side
/// after the session was cached). Intentionally has no dependency on any
/// admin/property-owner screen.
class _WebOnlyScreen extends StatelessWidget {
  const _WebOnlyScreen({required this.roleLabel});

  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.desktop_windows_rounded, size: 48, color: AppColors.slate),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '$roleLabel accounts aren\'t available in this app yet.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Please use the web version to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.slate),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
