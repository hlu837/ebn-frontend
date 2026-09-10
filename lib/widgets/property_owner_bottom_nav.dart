import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Bottom navigation for the Property Owner workspace: Dashboard / Inbox /
/// Post (raised center "+") / Review / Account. Mirrors [AgentBottomNav]'s
/// visual language (same raised-circle treatment for the primary action) —
/// Post now opens the same Sell/Rent intent sheet the Agent side uses,
/// same as [AgentBottomNav.onAddTap], instead of switching to a tab.
///
/// Everything that doesn't have a tab of its own yet (Listings, Settings,
/// Wallet, Support, etc.) lives one tap away under Account — see
/// `property_owner_home_screen.dart`.
class PropertyOwnerBottomNav extends StatelessWidget {
  const PropertyOwnerBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onPostTap,
    this.inboxBadgeCount = 0,
    this.reviewBadgeCount = 0,
  });

  /// 0 = Dashboard, 1 = Inbox, 3 = Review, 4 = Account (2 is the raised
  /// Post button, handled by [onPostTap] instead of a tab index).
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onPostTap;
  final int inboxBadgeCount;
  final int reviewBadgeCount;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 74,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Positioned.fill(
              top: 12,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -4)),
                  ],
                ),
                child: Row(
                  children: [
                    _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard', selected: currentIndex == 0, onTap: () => onTap(0)),
                    _NavItem(icon: Icons.inbox_rounded, label: 'Inbox', selected: currentIndex == 1, onTap: () => onTap(1), badgeCount: inboxBadgeCount),
                    const Expanded(child: SizedBox()), // gap for the raised Post button
                    _NavItem(icon: Icons.fact_check_rounded, label: 'Review', selected: currentIndex == 3, onTap: () => onTap(3), badgeCount: reviewBadgeCount),
                    _NavItem(icon: Icons.person_rounded, label: 'Account', selected: currentIndex == 4, onTap: () => onTap(4)),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              child: GestureDetector(
                onTap: onPostTap,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppColors.primaryYellow,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.cloud, width: 4),
                    boxShadow: [
                      BoxShadow(color: AppColors.primaryYellow.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap, this.badgeCount = 0});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primaryYellow : AppColors.slate;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 24, color: color),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 15),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.card, width: 1.5),
                        ),
                        child: Text(
                          badgeCount > 9 ? '9+' : '$badgeCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
