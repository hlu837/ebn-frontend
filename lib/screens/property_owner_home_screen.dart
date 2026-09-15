import 'package:flutter/material.dart';
import '../models/auth_response.dart';
import '../theme/app_theme.dart';
import '../widgets/listing_intent_sheet.dart';
import '../widgets/property_owner_bottom_nav.dart';
import 'property_owner_account_screen.dart';
import 'property_owner_dashboard_screen.dart';
import 'property_owner_inbox_screen.dart';
import 'property_owner_review_screen.dart';
import 'rent_property_form_screen.dart';
import 'sell_property_form_screen.dart';

/// The Property Owner workspace shell — a bottom-nav layout with five
/// tabs: Dashboard, Inbox, Post, Review, Account. Account is now real too
/// — see [PropertyOwnerAccountScreen] — the catch-all for everything that
/// doesn't have a tab of its own (Listings, Closed Deals, Settings,
/// Support, Log out), the same way Menu works on the Agent/Investor side.
///
/// Dashboard is real — see [PropertyOwnerDashboardScreen] — backed by the
/// same `sell_requests`/`assets` data the Agent side already persists to.
///
/// Inbox is real too — see [PropertyOwnerInboxScreen] — every info/tour/
/// rent-now request across the owner's properties, backed by
/// `property_requests` + the existing chat thread system. Document
/// review, sending the agreement, and the payment countdown live in the
/// Review tab — see [PropertyOwnerReviewScreen].
///
/// Post is already real too: it's the exact same flow as the Agent side's
/// raised "+" (see `_openListingIntent` in `agent_home_screen.dart`) —
/// ask Sell vs Rent, then go straight into the real listing wizard with
/// `isAgentListing: true`, which skips the listing fee and publishes
/// once Admin approves it, same as an Agent self-listing.
class PropertyOwnerHomeScreen extends StatefulWidget {
  const PropertyOwnerHomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<PropertyOwnerHomeScreen> createState() => _PropertyOwnerHomeScreenState();
}

class _PropertyOwnerHomeScreenState extends State<PropertyOwnerHomeScreen> {
  /// 0 = Dashboard, 1 = Inbox, 3 = Review, 4 = Account (2/Post is handled
  /// by the raised "+" button directly — see [_openListingIntent] — and
  /// never becomes the selected tab).
  int _tabIndex = 0;
  int _inboxUnread = 0;
  int _reviewNeedsAttention = 0;

  Future<void> _openListingIntent(BuildContext context) async {
    final intent = await showListingIntentSheet(context);
    if (intent == null || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => intent == ListingIntent.sell
          ? SellPropertyFormScreen(user: widget.user, isAgentListing: true)
          : RentPropertyFormScreen(user: widget.user, isAgentListing: true),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tabIndex == 0 && Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_tabIndex != 0) {
          setState(() => _tabIndex = 0);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.cloud,
        body: IndexedStack(
          index: _tabIndex,
          children: [
            PropertyOwnerDashboardScreen(user: widget.user),
            PropertyOwnerInboxScreen(
              user: widget.user,
              onUnreadChanged: (n) => setState(() => _inboxUnread = n),
            ),
            // Index 2 ("Post") is unreachable as a tab — the raised "+"
            // button opens the listing intent sheet directly instead (see
            // _openListingIntent). This placeholder is kept only so the
            // IndexedStack's indices line up with Review (3) and Account (4).
            const SizedBox.shrink(),
            PropertyOwnerReviewScreen(
              user: widget.user,
              onQueueChanged: (n) => setState(() => _reviewNeedsAttention = n),
            ),
            PropertyOwnerAccountScreen(user: widget.user),
          ],
        ),
        bottomNavigationBar: PropertyOwnerBottomNav(
          currentIndex: _tabIndex,
          onTap: (i) => setState(() => _tabIndex = i),
          onPostTap: () => _openListingIntent(context),
          inboxBadgeCount: _inboxUnread,
          reviewBadgeCount: _reviewNeedsAttention,
        ),
      ),
    );
  }
}
