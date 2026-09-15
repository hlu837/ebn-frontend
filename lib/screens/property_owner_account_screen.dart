import 'package:flutter/material.dart';

import '../models/auth_response.dart';
import '../theme/app_theme.dart';
import 'property_owner_closed_deals_screen.dart';
import 'property_owner_listings_screen.dart';
import 'role_gate_screen.dart';
import 'support_screen.dart';
import 'visitor_account_settings_screen.dart';

/// The Property Owner's real "Account" tab — replaces the [PlaceholderPage]
/// that used to sit here. Mirrors [InvestorAccountScreen]'s structure: a
/// profile header, grouped menu tiles, and a Log Out button.
///
/// "My Listings" and "Closed Deals" wire into screens that already existed
/// in the codebase ([PropertyOwnerListingsScreen], [PropertyOwnerClosedDealsScreen])
/// but had nothing linking to them yet. "Account & Settings" reuses
/// [VisitorAccountSettingsScreen] as-is — same as the Investor side — since
/// it talks to `/api/auth/me/settings`, which is self-scoped by Bearer
/// token and not role-gated. "Contact Support" reuses the generic
/// [SupportScreen] the same way.
///
/// Deliberately no Wallet row: there's no property-owner wallet backend
/// yet (see the note in `property_owner_dashboard_screen.dart`) — add one
/// here once that exists.
class PropertyOwnerAccountScreen extends StatelessWidget {
  const PropertyOwnerAccountScreen({super.key, required this.user});

  final AppUser user;

  void _logout(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleGateScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProfileHeader(user: user),
              const SizedBox(height: 22),
              const _SectionLabel('Properties'),
              const SizedBox(height: 8),
              _MenuTile(
                icon: Icons.apartment_rounded,
                label: 'My Listings',
                subtitle: 'Every property you\'ve posted and its status',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PropertyOwnerListingsScreen(user: user),
                )),
              ),
              const SizedBox(height: 10),
              _MenuTile(
                icon: Icons.task_alt_rounded,
                label: 'Closed Deals',
                subtitle: 'Finalized rentals, with a chat thread to each tenant',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PropertyOwnerClosedDealsScreen(user: user),
                )),
              ),
              const SizedBox(height: 18),
              const _SectionLabel('Support'),
              const SizedBox(height: 8),
              _MenuTile(
                icon: Icons.support_agent_outlined,
                label: 'Contact Support',
                subtitle: 'FAQs, submit a ticket, or reach the team directly',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SupportScreen(user: user),
                )),
              ),
              const SizedBox(height: 18),
              const _SectionLabel('Account'),
              const SizedBox(height: 8),
              _MenuTile(
                icon: Icons.settings_outlined,
                label: 'Account & Settings',
                subtitle: 'Profile, password, notifications, language',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => VisitorAccountSettingsScreen(user: user),
                )),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _logout(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger, width: 1.4),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.button)),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: AppColors.border,
            child: Text(
              user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName,
                  style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, color: AppColors.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: const Text(
                    'Property Owner',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primaryYellow),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.slate, letterSpacing: 0.8),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.primaryYellow.withValues(alpha: 0.1), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(icon, size: 19, color: AppColors.primaryYellow),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.slate, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.slate),
          ],
        ),
      ),
    );
  }
}
